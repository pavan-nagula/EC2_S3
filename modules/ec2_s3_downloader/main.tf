# --- Data Sources remains the same ---
# data "aws_region" "current" {

# }

data "aws_ami" "amazon_linux" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- 1. Networking: No Inbound Ports Needed ---
resource "aws_security_group" "ssm_only" {
  name        = "ec2-ssm-only-sg"
  description = "No inbound ports, only outbound for S3 and SSM"
  vpc_id      = data.aws_vpc.default.id

  # Ingress is empty! No SSH (Port 22) required.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 2. IAM: Added SSM Permissions ---
resource "aws_iam_role" "ec2_role" {
  name = "ec2-ssm-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach the standard SSM policy
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach your custom S3 read policy
resource "aws_iam_policy" "s3_read" {
  name = "ec2-s3-read-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:GetObject"]
      Effect   = "Allow"
      Resource = ["arn:aws:s3:::pavan-2026-s3-demo/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_read.arn
}

resource "aws_iam_instance_profile" "profile" {
  role = aws_iam_role.ec2_role.name
}

# --- 3. Compute: No key_name used ---
resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.nano"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ssm_only.id]
  iam_instance_profile   = aws_iam_instance_profile.profile.name

  # Even if this is false, SSM still works via the VPC Endpoint!
  associate_public_ip_address = true

  # key_name IS REMOVED

  user_data = <<-EOF
    #!/bin/bash
    yum install -y awscli
    mkdir -p /home/ec2-user/s3-downloads
    aws s3 cp s3://pavan-2026-s3-demo/sample.txt /home/ec2-user/s3-downloads/
    chown -R ec2-user:ec2-user /home/ec2-user/s3-downloads
  EOF

  tags = { Name = "Prod_S3_Downloader_NoKey" }
}

