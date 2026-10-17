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