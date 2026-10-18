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

variable "app_instance_type" {
  description = "The instance type for the Juice Shop application"
  type        = string
  default     = "t3.medium"
}
variable "juiceshop_image" {
  description = "OWASP Juice Shop container image"
  type        = string
  default     = "bkimminich/juice-shop:v19.0.0"
}

variable "wazuh_instance_type" {
  description = "The instance type for the Wazuh server"
  type        = string
  default     = "t3.micro"
}

variable "app_root_volume_size" {
  description = "The root volume size for the Juice Shop application instance"
  type        = number
  default     = 20
}

variable "wg_instance_type" {
  description = "Instance type for the WireGuard gateway"
  type        = string
  default     = "t3.micro" # VPN gateway is tiny
}

variable "wg_client_public_key" {
  description = "The WireGuard CLIENT public key (from ~/.wg/juiceshop-client.pub). Public key only."
  type        = string
  # no default — must be supplied in terraform.tfvars
}

variable "wg_server_port" {
  description = "WireGuard listen port (UDP)"
  type        = number
  default     = 51820
}

variable "wg_vpn_cidr" {
  description = "VPN tunnel subnet (internal to WireGuard)"
  type        = string
  default     = "10.8.0.0/24"
}
variable "wg_root_volume_size" {
  description = "The root volume size for the WireGuard gateway instance"
  type        = number
  default     = 10
}