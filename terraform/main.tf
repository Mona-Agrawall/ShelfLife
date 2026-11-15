# =============================================================================
# ShelfLife - Terraform Main Configuration
# =============================================================================
#
# OPTIONAL: Uncomment the backend block below to store Terraform state in S3.
# Prerequisites:
#   1. Create an S3 bucket: aws s3 mb s3://your-tfstate-bucket
#   2. Create a DynamoDB table (name: terraform-lock, partition key: LockID)
#   3. Replace bucket name and region below, then run: terraform init
#
# terraform {
#   backend "s3" {
#     bucket         = "your-tfstate-bucket"
#     key            = "shelflife/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-lock"
#     encrypt        = true
#   }
# }
# =============================================================================

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.region
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------
locals {
  instance_profile = var.instance_profile_name != "" ? var.instance_profile_name : null
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# -----------------------------------------------------------------------------
# SSH Key Pair
# -----------------------------------------------------------------------------

resource "tls_private_key" "shelflife_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "shelflife_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.shelflife_key.public_key_openssh

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

resource "local_file" "private_key" {
  content         = tls_private_key.shelflife_key.private_key_pem
  filename        = "shelflife-key.pem"
  file_permission = "0400"
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

# Jenkins Server Security Group
resource "aws_security_group" "jenkins_sg" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins CI server"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Jenkins web UI
  ingress {
    description = "Jenkins Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-jenkins-sg"
    Project = var.project_name
  }
}

# App Server Security Group
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for ShelfLife application server"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # App port (Flask/Gunicorn via Docker)
  ingress {
    description = "App port"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # HTTP (port 80 for reverse proxy / deployed container)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-app-sg"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# EC2 Instances
# -----------------------------------------------------------------------------

# Jenkins CI Server
resource "aws_instance" "jenkins_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.shelflife_key.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  user_data              = file("user_data_jenkins.sh")
  iam_instance_profile   = local.instance_profile

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-jenkins"
    Project = var.project_name
    Role    = "CI"
  }
}

# Application Server
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.shelflife_key.key_name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  user_data              = file("user_data_app.sh")
  iam_instance_profile   = local.instance_profile

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-app"
    Project = var.project_name
    Role    = "App"
  }
}

# -----------------------------------------------------------------------------
# Elastic IPs
# -----------------------------------------------------------------------------

resource "aws_eip" "jenkins_eip" {
  domain = "vpc"

  depends_on = [aws_instance.jenkins_server]

  tags = {
    Name    = "${var.project_name}-jenkins-eip"
    Project = var.project_name
  }
}

resource "aws_eip_association" "jenkins_eip_assoc" {
  instance_id   = aws_instance.jenkins_server.id
  allocation_id = aws_eip.jenkins_eip.id
}

resource "aws_eip" "app_eip" {
  domain = "vpc"

  depends_on = [aws_instance.app_server]

  tags = {
    Name    = "${var.project_name}-app-eip"
    Project = var.project_name
  }
}

resource "aws_eip_association" "app_eip_assoc" {
  instance_id   = aws_instance.app_server.id
  allocation_id = aws_eip.app_eip.id
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------

# Log group for application logs
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/shelflife/app"
  retention_in_days = 7

  tags = {
    Name    = "${var.project_name}-app-logs"
    Project = var.project_name
  }
}

# CPU utilization alarm for app server
resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  alarm_name          = "${var.project_name}-app-cpu-high"
  alarm_description   = "Triggers when app server CPU exceeds 70% for 10 minutes"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  # alarm_actions is empty - add an SNS topic ARN here to get notifications
  alarm_actions = []

  tags = {
    Name    = "${var.project_name}-cpu-alarm"
    Project = var.project_name
  }
}
