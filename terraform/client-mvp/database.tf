############################
# DB Subnet Group
############################

resource "aws_db_subnet_group" "nordledger-db-subnet-group" {
  name = "${var.project_name}-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

############################
# S3 Bucket
############################

resource "aws_s3_bucket" "invoice_bucket" {
  bucket = var.invoice_bucket_name
  tags = {
    Name    = "${var.project_name}-frontend-bucket"
    Project = var.project_name
  }
}
