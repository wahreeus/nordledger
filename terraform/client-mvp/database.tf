############################
# DB Subnet Group
############################

resource "aws_db_subnet_group" "nordledger" {
  name = "${var.project_name}-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}
