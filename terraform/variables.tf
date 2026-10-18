variable "region" {
  description = "Region in the account which is in use."
  type        = string
  default     = "ap-southeast-2"
}

variable "project" {
  type    = string
  default = "juiceshop"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "evaluator_cidr" {
  description = "The CIDR block for the evaluator"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key used for EC2 access over the VPN"
  type        = string
  default     = "~/.ssh/juiceshop-lab.pub"
}