############################
# Network Outputs
############################

output "vpc_id" {
  value = aws_vpc.nordledger.id
}

output "private_subnet_ids" {
  value = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.nordledger.name
}

output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "s3_vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}