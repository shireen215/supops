variable "aws_region" { default = "us-east-1" }
variable "instance_count" { default = 2 }
variable "instance_type" { default = "t3.micro" }
variable "ssh_public_key" { type = string }