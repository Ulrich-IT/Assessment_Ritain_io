# Define provider
provider "aws" {
  region = "us-west-2"  # Change to your preferred region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Public Subnet for ELB
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
}

# Private Subnet for Application and Database
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
}

# Security Group for EC2 instances
resource "aws_security_group" "app_sg" {
  name        = "app_sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instances for Application (Auto-scaling Group)
resource "aws_launch_template" "app" {
  name          = "app-launch-template"
  image_id      = "ami-0c55b159cbfafe1f0"  # Use the latest Amazon Linux AMI
  instance_type = "t3.micro"

  key_name = "my-key"  # Replace with your key

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8
    }
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                 = "app_asg"  
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.public.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300
}

# Elastic Load Balancer
resource "aws_elb" "app_elb" {
  name               = "app-elb"
  security_groups    = [aws_security_group.app_sg.id]
  subnets            = [aws_subnet.public.id]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# RDS Instance (PostgreSQL)
resource "aws_db_instance" "db" {
  allocated_storage    = 20
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  #name                 = "topsurveydb"
  username             = "admin"
  password             = "password123"  # Use a secure password
  parameter_group_name = "default.postgres10"
  skip_final_snapshot  = true
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet.id
}

# DB Subnet Group
resource "aws_db_subnet_group" "db_subnet" {
  name       = "db_subnet"
  subnet_ids = [aws_subnet.private.id]
}
