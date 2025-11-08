# DevOps Assignment — Load-Balanced Web Application (Terraform + AWS)

This README explains how to recreate the entire environment from installing tools to verifying a highly available web application deployed on AWS using Terraform.

## Overview

You will deploy:
- A VPC with 2 public subnets
- Two EC2 web servers (running Nginx via `userdata`)
- An Application Load Balancer (ALB) distributing traffic between the servers
- Automatic failover (ALB routes traffic only to healthy targets)

Infrastructure is provisioned using Terraform and verified with the AWS CLI and browser tests.

---

## Prerequisites

You need:
- A Windows 10/11 system (PowerShell access)
- An AWS account
- Basic understanding of CLI and AWS console

---

## Step 1 : Install Required Tools

1. Install Terraform

Open PowerShell as Administrator and run:
```powershell
winget install HashiCorp.Terraform
```

Verify installation:
```powershell
terraform -version
```
Expected output:
```
Terraform v1.9.x
```

2. Install AWS CLI

Download and install from:
https://aws.amazon.com/cli/

Verify:
```powershell
aws --version
```
Expected output:
```
aws-cli/2.x.x Python/3.x.x Windows/10 exe/AMD64
```

3. Configure AWS CLI

Run:
```powershell
aws configure
```

Provide your credentials:
```
AWS Access Key ID [None]: <AWSAccessKey>
AWS Secret Access Key [None]: <AWSSecretKey>
Default region name [None]: us-east-1
Default output format [None]: json
```

To confirm configuration:
```powershell
aws sts get-caller-identity
```
You should see your AWS account ID and user ARN.

4. Generate SSH Key Pair

Run:
```powershell
ssh-keygen
```
Press Enter to accept defaults.

Your keys will be stored at:
```
C:\Users\<YourUser>\.ssh\
```
- `id_rsa` → private key  
- `id_rsa.pub` → public key

To view your public key:
```powershell
cat $env:USERPROFILE\.ssh\id_rsa.pub
```

You’ll use this in Terraform.

---

## Step 2 : Project Setup

Create a folder for your project:
```powershell
mkdir D:\Superops-Assignment\terraform
cd D:\Superops-Assignment\terraform
```

Inside it, create these files:
```
├── main.tf
├── provider.tf
├── variables.tf
├── outputs.tf
├── userdata.sh
└── README.md
```

---

## Step 3 : Terraform Configuration Files

Below are the sample contents for each file. Paste them into the respective files in your project folder.

provider.tf
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

variables.tf
```hcl
variable "aws_region" { default = "us-east-1" }
variable "instance_count" { default = 2 }
variable "instance_type" { default = "t3.micro" }
variable "ssh_public_key" { type = string }
```

userdata.sh
```bash
#!/bin/bash
set -eux

# Install and start nginx on Amazon Linux 2
amazon-linux-extras install -y nginx1
systemctl enable nginx
systemctl start nginx

# Create a simple Hello World page
webroot="/usr/share/nginx/html"
echo "Hello World from $(hostname)" > ${webroot}/index.html
chown root:root ${webroot}/index.html
chmod 644 ${webroot}/index.html
```

⚠️ Ensure this file uses Unix line endings (LF).  
In PowerShell, you can fix it using:
```powershell
(Get-Content .\userdata.sh) -replace "`r`n", "`n" | Set-Content -NoNewline .\userdata.sh
```




main.tf
```hcl
# VPC
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "tf-demo-vpc"
  }
}

# Subnets (two AZs)
resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "tf-subnet-a"
  }
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "tf-subnet-b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "tf-igw"
  }
}

# Route Table & Routes
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "tf-public-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_route_table.rt.id
}

# Security Group
resource "aws_security_group" "web_sg" {
  name   = "web-sg"
  vpc_id = aws_vpc.this.id

  description = "Allow HTTP and SSH"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "tf-web-sg"
  }
}

# Key Pair (uploads public key)
resource "aws_key_pair" "deployer" {
  key_name   = "tf-deployer-key"
  public_key = var.ssh_public_key
}

# Latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Web server instances (counted)
resource "aws_instance" "web" {
  count                       = var.instance_count
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = element([aws_subnet.a.id, aws_subnet.b.id], count.index)
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = file("${path.module}/userdata.sh")

  tags = {
    Name = "web-${count.index + 1}"
  }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "tf-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.a.id, aws_subnet.b.id]
  security_groups    = [aws_security_group.web_sg.id]

  tags = {
    Name = "tf-alb"
  }
}

# Target Group for ALB
resource "aws_lb_target_group" "tg" {
  name     = "tf-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "tf-tg"
  }
}

# Attach instances to target group
resource "aws_lb_target_group_attachment" "tg_attach" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# ALB Listener (HTTP)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
```

outputs.tf
```hcl
output "alb_dns" {
  description = "ALB DNS name"
  value       = aws_lb.alb.dns_name
}
```

---

## Step 4 : Initialize Terraform

In PowerShell (inside your Terraform folder):
```powershell
terraform init
```
This downloads the required AWS provider.

---

## Step 5 : Validate Configuration

```powershell
terraform validate
```

If the configuration is valid, you’ll see:
```
Success! The configuration is valid.
```

---

## Step 6 : Plan Deployment

Run the Terraform plan and pass your public SSH key from your local `.ssh`:
```powershell
terraform plan -var "ssh_public_key=$(Get-Content $env:USERPROFILE\.ssh\id_rsa.pub)"
```

Terraform will show you all resources it’s going to create.

![image alt](https://github.com/shireen215/supops-img/blob/b78fa7a044e41fd6a12b3c8abe39a7b97e02833f/Tf%20plan.png)

---

## Step 7 : Apply Deployment

Apply the plan:
```powershell
terraform apply -var "ssh_public_key=$(Get-Content $env:USERPROFILE\.ssh\id_rsa.pub)" -auto-approve
```

Wait 2–3 minutes while Terraform creates all resources.

At the end, it prints the ALB DNS name, for example:
```
alb_dns = "tf-alb-914652170.us-east-1.elb.amazonaws.com/"
```

![image alt](https://github.com/shireen215/supops-img/blob/b78fa7a044e41fd6a12b3c8abe39a7b97e02833f/Tf%20apply.jpg)

---

## Step 8 : Test Your Load Balancer

1) Browser  
Open:
```
http://tf-alb-914652170.us-east-1.elb.amazonaws.com/
```
You should see:
```
Hello World from ip-10-0-2-102.ec2.internal
```
Refresh — it should alternate between the two servers.
```
Hello World from ip-10-0-1-12.ec2.internal
```

2) PowerShell
```powershell
curl http://$(terraform output -raw alb_dns)
```

---

## Step 9 : Test Failover

1. Go to AWS Console → EC2 → Instances.
2. Stop one instance (e.g., `web-1`).
3. Wait ~60 seconds for ALB health checks to update.
4. Visit the ALB DNS again — it should still serve responses from the healthy instance.

This confirms automatic failover.

---

![image alt]https://github.com/shireen215/supops-img/blob/7b9a64a4e3dd6dff235cb5acd085675b58012309/New%20Project%20(5).png)

---
**What I Liked About My Solution**

- The infrastructure is completely automated using Terraform, which makes it easy to recreate consistently.
- The solution is scalable adding more web servers only requires changing one variable.
- Nginx installation happens automatically through userdata.sh without manual intervention.
- Load Balancer health checks ensure automatic failover, improving reliability.


**What I Disliked About My Solution**

- The EC2 instances are running in public subnets; a production-grade setup should use private subnets.
Why: For a small demo I placed instances in public subnets so they have direct Internet access to download packages during boot and so I could SSH into them for debugging. In production, instances should live in private subnets and use a NAT gateway or a bastion/SSM approach for secure outbound access and administration.
- SSH access is open to the world (0.0.0.0/0), which is not secure for real environments.
Why: For demo/debugging convenience I allowed SSH from anywhere so I could easily reach instances. This is insecure because it exposes SSH to the public internet. In production you should restrict SSH to trusted IPs, use a bastion host, or use AWS Systems Manager Session Manager (no inbound SSH required).
