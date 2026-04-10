############################
# Network Variables
############################

variable "project_name" {
  description = "Project name used in tags and resource names."
  type        = string
  default     = "nordledger"
}

variable "vpc_cidr" {
  description = "CIDR block for the NordLedger VPC."
  type        = string
  default     = "10.0.0.0/22"
}

variable "private_subnet_a_cidr" {
  description = "CIDR block for private subnet A."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_b_cidr" {
  description = "CIDR block for private subnet B."
  type        = string
  default     = "10.0.2.0/24"
}