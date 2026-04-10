############################
# Data Sources
############################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

############################
# Locals
############################

locals {
  az_a = data.aws_availability_zones.available.names[0]
  az_b = data.aws_availability_zones.available.names[1]
  common_tags = {
    Project = var.project_name
  }
}

############################
# VPC
############################

resource "aws_vpc" "nordledger" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

############################
# Private Subnets
############################

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.nordledger.id
  cidr_block              = var.private_subnet_a_cidr
  availability_zone       = local.az_a
  map_public_ip_on_launch = false
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-a"
    Tier = "private"
    AZ   = local.az_a
  })
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.nordledger.id
  cidr_block              = var.private_subnet_b_cidr
  availability_zone       = local.az_b
  map_public_ip_on_launch = false
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-b"
    Tier = "private"
    AZ   = local.az_b
  })
}

############################
# Private Route Table
############################

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.nordledger.id
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

############################
# S3 Gateway VPC Endpoint
############################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.nordledger.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private.id
  ]
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3-endpoint"
  })
}
