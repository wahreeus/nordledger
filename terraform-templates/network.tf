data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

locals {
  vpc = {
    name        = "nordledger"
    cidr_block  = "10.1.0.0/20"
    environment = "shared"
  }
  subnets = {
    public_a = {
      cidr_block  = "10.1.1.0/24"
      role        = "public"
      route_table = "public"
      az_index    = 0
    }
    private_a = {
      cidr_block  = "10.1.2.0/24"
      role        = "private"
      route_table = "private"
      az_index    = 0
    }
    public_b = {
      cidr_block  = "10.1.3.0/24"
      role        = "public"
      route_table = "public"
      az_index    = 1
    }
    private_b = {
      cidr_block  = "10.1.4.0/24"
      role        = "private"
      route_table = "private"
      az_index    = 1
    }
  }
  public_subnets = {
    for name, subnet in local.subnets :
    name => subnet
    if subnet.role == "public"
  }
  private_subnets = {
    for name, subnet in local.subnets :
    name => subnet
    if subnet.role == "private"
  }
  public_subnet_by_az = {
    for name, subnet in local.public_subnets :
    tostring(subnet.az_index) => name
  }
}

resource "aws_vpc" "main" {
  cidr_block           = local.vpc.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${local.vpc.name}-${local.vpc.environment}-vpc"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_subnet" "subnets" {
  for_each = local.subnets
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = data.aws_availability_zones.available.names[each.value.az_index]
  map_public_ip_on_launch = each.value.role == "public"
  tags = {
    Name        = "${local.vpc.name}-${local.vpc.environment}-${each.key}-subnet"
    Project     = local.vpc.name
    Environment = local.vpc.environment
    Role        = each.value.role
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${local.vpc.name}-${local.vpc.environment}-igw"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_eip" "nat" {
  for_each = local.public_subnets
  domain = "vpc"
  tags = {
    Name        = "${local.vpc.name}-${local.vpc.environment}-${each.key}-nat-eip"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_nat_gateway" "nat" {
  for_each = local.public_subnets
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.subnets[each.key].id
  tags = {
    Name        = "${local.vpc.name}-${local.vpc.environment}-${each.key}-nat"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "${local.vpc.name}-${local.vpc.environment}-public-rt"
    Project     = local.vpc.name
    Environment = local.vpc.environment
    Role        = "public"
  }
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[
      local.public_subnet_by_az[tostring(each.value.az_index)]
    ].id
  }
  tags = {
    Name        = "${local.vpc.name}-${local.vpc.environment}-${each.key}-rt"
    Project     = local.vpc.name
    Environment = local.vpc.environment
    Role        = "private"
  }
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets
  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets
  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}