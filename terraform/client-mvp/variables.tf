############################
# Authentication Variables
############################

variable "cognito_domain_prefix" {
  description = "Unique prefix for the Cognito managed login domain"
  type        = string
  default     = "nordledger-pool"
}

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

############################
# Resource Variables
############################

variable "frontend_bucket_name" {
  description = "Name of the S3 bucket that stores the frontend files."
  type        = string
  default     = "nordledger-frontend"
}
