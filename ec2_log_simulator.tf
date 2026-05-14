// ec2_log_simulator.tf
// ---------------------------------------------------------------------
// This file provisions resources to simulate workload activity:
//   - A public subnet (when a new VPC is created)
//   - A security group for the EC2 instance
//   - An IAM instance profile that lets the EC2 ship application logs
//     to CloudWatch (only attached when deploy_cloudwatch_logs is true)
//   - An EC2 instance that:
//       * continuously generates outbound HTTP traffic (drives VPC Flow Logs)
//       * writes structured JSON application logs to /var/log/app/app.log
//       * runs the awslogs agent to forward /var/log/app/app.log to the
//         demo CloudWatch Logs group (streaming pipeline source)
// ---------------------------------------------------------------------

// Create a public subnet if a new VPC is being deployed.
resource "aws_subnet" "public" {
  count = var.deploy_vpc ? 1 : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

// Create an Internet Gateway for the VPC
resource "aws_internet_gateway" "main" {
  count = var.deploy_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "main-igw"
  }
}

// Create a route table for the public subnet
resource "aws_route_table" "public" {
  count = var.deploy_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "public-rt"
  }
}

// Associate the public subnet with the public route table
resource "aws_route_table_association" "public" {
  count = var.deploy_vpc ? 1 : 0

  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

// Security group for the EC2 simulator instance.
// If using an existing VPC, the user must ensure that a valid VPC ID is supplied.
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-simulator-sg"
  description = "Allow SSH and all outbound traffic"
  vpc_id      = var.deploy_vpc ? aws_vpc.main[0].id : var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // For production, restrict this to your IP range.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-simulator-sg"
  }
}

// Data block to fetch the latest Amazon Linux 2 AMI.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

// ---------------------------------------------------------------------
// IAM instance profile for the simulator
//
// Only created when the CloudWatch Logs pipeline is enabled. The role
// allows the awslogs agent on the instance to push log events to the
// demo log group.
// ---------------------------------------------------------------------
resource "aws_iam_role" "simulator" {
  count = var.deploy_simulator && var.deploy_cloudwatch_logs ? 1 : 0
  name  = "apac-sa-demo-simulator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "simulator_cw_logs" {
  count = var.deploy_simulator && var.deploy_cloudwatch_logs ? 1 : 0
  name  = "SimulatorCloudWatchLogsPolicy"
  role  = aws_iam_role.simulator[0].id

  // logs:CreateLogGroup is required because the awslogs daemon calls it
  // defensively on startup even when the group already exists; without
  // it the publisher thread crashes with AccessDeniedException and never
  // ships data. The group ARN (without `:*`) covers CreateLogGroup; the
  // `:*` form scopes the stream-level actions.
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ],
      Resource = [
        aws_cloudwatch_log_group.app_logs[0].arn,
        "${aws_cloudwatch_log_group.app_logs[0].arn}:*",
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "simulator" {
  count = var.deploy_simulator && var.deploy_cloudwatch_logs ? 1 : 0
  name  = "apac-sa-demo-simulator-profile"
  role  = aws_iam_role.simulator[0].name
}

// EC2 instance that simulates traffic by continuously sending HTTP requests.
resource "aws_instance" "simulator" {
  count = var.deploy_simulator ? 1 : 0

  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  // Use the new subnet if deploying a new VPC; otherwise, use an existing subnet provided by the user.
  subnet_id = var.deploy_vpc ? aws_subnet.public[0].id : var.existing_subnet_id

  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  // Attach the CloudWatch-capable instance profile only when the
  // streaming pipeline is enabled. Otherwise the instance runs without
  // a profile, exactly as it did before this integration.
  iam_instance_profile = var.deploy_cloudwatch_logs ? aws_iam_instance_profile.simulator[0].name : null

  // User data script:
  //   - generates outbound HTTP traffic (drives VPC Flow Logs, batch pipeline)
  //   - writes structured JSON application logs to /var/log/app/app.log
  //   - configures awslogs to ship those logs to CloudWatch Logs when
  //     the streaming pipeline is enabled (passed in via templatefile)
  user_data = templatefile("${path.module}/ec2_simulator_user_data.sh.tftpl", {
    enable_cloudwatch_logs = var.deploy_cloudwatch_logs
    cloudwatch_log_group   = var.deploy_cloudwatch_logs ? aws_cloudwatch_log_group.app_logs[0].name : ""
    aws_region             = var.aws_region
  })

  tags = {
    Name = "EC2-Simulator"
  }
}