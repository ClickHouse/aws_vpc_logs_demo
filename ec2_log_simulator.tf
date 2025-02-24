// ec2.tf
// ---------------------------------------------------------------------
// This file provisions additional resources to simulate traffic:
//   - A public subnet (if creating a new VPC)
//   - A security group for the EC2 instance
//   - An EC2 instance that continuously generates outbound HTTP traffic
// This traffic will create VPC Flow Logs.
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

// EC2 instance that simulates traffic by continuously sending HTTP requests.
resource "aws_instance" "simulator" {
  count = var.deploy_simulator ? 1 : 0

  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  // Use the new subnet if deploying a new VPC; otherwise, use an existing subnet provided by the user.
  subnet_id = var.deploy_vpc ? aws_subnet.public[0].id : var.existing_subnet_id

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  // User data script to continuously generate outbound HTTP traffic.
  user_data = <<-EOF
    #!/bin/bash
    
    # Enable logging of user data script execution
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    
    echo "[INFO] Starting user data script execution"
    
    # Update and install required packages
    echo "[INFO] Updating system packages"
    yum update -y
    echo "[INFO] Installing curl"
    yum install -y curl
    
    # Create a systemd service file
    echo "[INFO] Creating traffic generator service"
    cat <<'SERVICE' > /etc/systemd/system/traffic-generator.service
[Unit]
Description=Traffic Generator Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/generate-traffic.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

    # Create the traffic generator script
    echo "[INFO] Creating traffic generator script"
    cat <<'SCRIPT' > /usr/local/bin/generate-traffic.sh
#!/bin/bash

# Set up logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

echo "Traffic generator script started"

while true; do
    echo "Sending request to example.com"
    if curl -s https://www.example.com > /dev/null; then
        echo "Request successful"
    else
        echo "Request failed"
    fi
    sleep 5
done
SCRIPT

    # Make the script executable
    echo "[INFO] Setting permissions"
    chmod +x /usr/local/bin/generate-traffic.sh
    
    # Start the service
    echo "[INFO] Starting traffic generator service"
    systemctl daemon-reload
    systemctl enable traffic-generator
    systemctl start traffic-generator
    
    echo "[INFO] User data script execution completed"
  EOF

  tags = {
    Name = "EC2-Simulator"
  }
}