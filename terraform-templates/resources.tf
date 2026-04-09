data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  resource_prefix = "${local.vpc.name}-${local.vpc.environment}"

  private_subnet_ids = [
    aws_subnet.subnets["private_a"].id,
    aws_subnet.subnets["private_b"].id,
  ]

  private_route_table_ids = [for rt in aws_route_table.private : rt.id]

  lambda_package_path = "${path.module}/build/nordledger_lambda.zip"
  lambda_source_dir   = "${path.module}/lambda"

  lambda_source_files = sort(fileset(local.lambda_source_dir, "*.py"))
  lambda_package_trigger = sha256(join("", concat(
    [for file_name in local.lambda_source_files : filesha256("${local.lambda_source_dir}/${file_name}")],
    [
      filesha256("${local.lambda_source_dir}/requirements.txt"),
      filesha256("${path.module}/build_lambda_package.sh")
    ]
  )))
}

resource "terraform_data" "build_lambda_package" {
  triggers_replace = [local.lambda_package_trigger]

  provisioner "local-exec" {
    working_dir = path.module
    command     = "./build_lambda_package.sh"
  }
}

resource "aws_s3_bucket" "invoice_pdfs" {
  bucket = "${local.resource_prefix}-invoice-pdfs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  tags = {
    Name        = "${local.resource_prefix}-invoice-pdfs"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_s3_bucket_versioning" "invoice_pdfs" {
  bucket = aws_s3_bucket.invoice_pdfs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "invoice_pdfs" {
  bucket = aws_s3_bucket.invoice_pdfs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "invoice_pdfs" {
  bucket = aws_s3_bucket.invoice_pdfs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "invoice_pdfs_ssl_only" {
  bucket = aws_s3_bucket.invoice_pdfs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.invoice_pdfs.arn,
          "${aws_s3_bucket.invoice_pdfs.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = {
    Name        = "${local.resource_prefix}-s3-endpoint"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_security_group" "lambda" {
  name        = "${local.resource_prefix}-lambda-sg"
  description = "Security group for NordLedger Lambda functions"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic from Lambda"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.resource_prefix}-lambda-sg"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_security_group" "database" {
  name        = "${local.resource_prefix}-db-sg"
  description = "Allow PostgreSQL access from NordLedger Lambdas"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Lambda functions"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    description = "Allow outbound traffic from database"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.resource_prefix}-db-sg"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.resource_prefix}-db-subnet-group"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name        = "${local.resource_prefix}-db-subnet-group"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_db_instance" "postgres" {
  identifier                          = "${local.resource_prefix}-postgres"
  engine                              = "postgres"
  engine_version                      = "16"
  instance_class                      = "db.t3.small"
  allocated_storage                   = 20
  max_allocated_storage               = 100
  storage_type                        = "gp3"
  storage_encrypted                   = true
  db_name                             = "nordledger"
  username                            = "nordledgeradmin"
  manage_master_user_password         = true
  port                                = 5432
  multi_az                            = true
  db_subnet_group_name                = aws_db_subnet_group.postgres.name
  vpc_security_group_ids              = [aws_security_group.database.id]
  publicly_accessible                 = false
  backup_retention_period             = 7
  auto_minor_version_upgrade          = true
  apply_immediately                   = true
  skip_final_snapshot                 = true
  deletion_protection                 = false
  copy_tags_to_snapshot               = true
  iam_database_authentication_enabled = false

  tags = {
    Name        = "${local.resource_prefix}-postgres"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

data "aws_secretsmanager_secret_version" "postgres_master_current" {
  secret_id = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

locals {
  postgres_master_secret = jsondecode(data.aws_secretsmanager_secret_version.postgres_master_current.secret_string)

  common_lambda_environment = {
    DB_HOST             = aws_db_instance.postgres.address
    DB_PORT             = tostring(aws_db_instance.postgres.port)
    DB_NAME             = aws_db_instance.postgres.db_name
    DB_USER             = local.postgres_master_secret["username"]
    DB_PASSWORD         = local.postgres_master_secret["password"]
    CUSTOMERS_TABLE     = "customers"
    INVOICES_TABLE      = "invoices"
    INVOICE_ITEMS_TABLE = "invoice_items"
  }
}

resource "aws_iam_role" "lambda_execution" {
  name = "${local.resource_prefix}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${local.resource_prefix}-lambda-execution-role"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_data_access" {
  name = "${local.resource_prefix}-lambda-data-access"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowInvoiceBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          aws_s3_bucket.invoice_pdfs.arn,
          "${aws_s3_bucket.invoice_pdfs.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "schema_init" {
  name              = "/aws/lambda/${local.resource_prefix}-schema-init"
  retention_in_days = 14

  tags = {
    Name        = "${local.resource_prefix}-schema-init-logs"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_cloudwatch_log_group" "generate_invoice_pdf" {
  name              = "/aws/lambda/${local.resource_prefix}-generate-invoice-pdf"
  retention_in_days = 14

  tags = {
    Name        = "${local.resource_prefix}-generate-invoice-pdf-logs"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_cloudwatch_log_group" "create_customer" {
  name              = "/aws/lambda/${local.resource_prefix}-create-customer"
  retention_in_days = 14

  tags = {
    Name        = "${local.resource_prefix}-create-customer-logs"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_cloudwatch_log_group" "create_invoice" {
  name              = "/aws/lambda/${local.resource_prefix}-create-invoice"
  retention_in_days = 14

  tags = {
    Name        = "${local.resource_prefix}-create-invoice-logs"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_lambda_function" "schema_init" {
  function_name = "${local.resource_prefix}-schema-init"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = "python3.11"
  handler       = "schema_init.lambda_handler"
  filename      = local.lambda_package_path

  source_code_hash = base64sha256(local.lambda_package_trigger)
  timeout          = 60
  memory_size      = 512

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = local.common_lambda_environment
  }

  depends_on = [
    terraform_data.build_lambda_package,
    aws_db_instance.postgres,
    aws_cloudwatch_log_group.schema_init,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy.lambda_data_access,
  ]

  tags = {
    Name        = "${local.resource_prefix}-schema-init"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_lambda_invocation" "schema_init" {
  function_name   = aws_lambda_function.schema_init.function_name
  lifecycle_scope = "CREATE_ONLY"
  input = jsonencode({
    action = "init_schema"
  })

  triggers = {
    db_instance_id       = aws_db_instance.postgres.id
    lambda_package_hash  = local.lambda_package_trigger
    schema_function_name = aws_lambda_function.schema_init.function_name
  }

  depends_on = [aws_lambda_function.schema_init]
}

resource "aws_lambda_function" "create_pdf" {
  function_name = "${local.resource_prefix}-create-pdf"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = "python3.11"
  handler       = "create_pdf.lambda_handler"
  filename      = local.lambda_package_path

  source_code_hash = base64sha256(local.lambda_package_trigger)
  timeout          = 90
  memory_size      = 1024

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(
      local.common_lambda_environment,
      {
        INVOICE_BUCKET = aws_s3_bucket.invoice_pdfs.bucket
        PDF_PREFIX     = "invoices"
        SELLER_NAME    = "NordLedger AB"
        SELLER_LINE_1  = "Drottninggatan 1"
        SELLER_LINE_2  = "123 45 Stockholm"
        SELLER_LINE_3  = "Sweden"
        SELLER_LINE_4  = "billing@nordledger.com"
      }
    )
  }

  depends_on = [
    terraform_data.build_lambda_package,
    aws_lambda_invocation.schema_init,
    aws_cloudwatch_log_group.generate_invoice_pdf,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy.lambda_data_access,
  ]

  tags = {
    Name        = "${local.resource_prefix}-generate-invoice-pdf"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_lambda_function" "create_customer" {
  function_name = "${local.resource_prefix}-create-customer"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = "python3.11"
  handler       = "create_customer.lambda_handler"
  filename      = local.lambda_package_path

  source_code_hash = base64sha256(local.lambda_package_trigger)
  timeout          = 30
  memory_size      = 512

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = local.common_lambda_environment
  }

  depends_on = [
    terraform_data.build_lambda_package,
    aws_lambda_invocation.schema_init,
    aws_cloudwatch_log_group.create_customer,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy.lambda_data_access,
  ]

  tags = {
    Name        = "${local.resource_prefix}-create-customer"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_lambda_function" "create_invoice" {
  function_name = "${local.resource_prefix}-create-invoice"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = "python3.11"
  handler       = "create_invoice.lambda_handler"
  filename      = local.lambda_package_path

  source_code_hash = base64sha256(local.lambda_package_trigger)
  timeout          = 30
  memory_size      = 512

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = local.common_lambda_environment
  }

  depends_on = [
    terraform_data.build_lambda_package,
    aws_lambda_invocation.schema_init,
    aws_cloudwatch_log_group.create_invoice,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy.lambda_data_access,
  ]

  tags = {
    Name        = "${local.resource_prefix}-create-invoice"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.resource_prefix}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type", "authorization"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = {
    Name        = "${local.resource_prefix}-http-api"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_apigatewayv2_integration" "create_customer" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.create_customer.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "create_invoice" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.create_invoice.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "generate_invoice_pdf" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.generate_invoice_pdf.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_customer" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /customers"
  target    = "integrations/${aws_apigatewayv2_integration.create_customer.id}"
}

resource "aws_apigatewayv2_route" "create_invoice" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /invoices"
  target    = "integrations/${aws_apigatewayv2_integration.create_invoice.id}"
}

resource "aws_apigatewayv2_route" "generate_invoice_pdf" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /invoices/pdf"
  target    = "integrations/${aws_apigatewayv2_integration.generate_invoice_pdf.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Name        = "${local.resource_prefix}-http-api-stage"
    Project     = local.vpc.name
    Environment = local.vpc.environment
  }
}

resource "aws_lambda_permission" "allow_apigateway_create_customer" {
  statement_id  = "AllowHttpApiInvokeCreateCustomer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_customer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_apigateway_create_invoice" {
  statement_id  = "AllowHttpApiInvokeCreateInvoice"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_invoice.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_apigateway_generate_invoice_pdf" {
  statement_id  = "AllowHttpApiInvokeGenerateInvoicePdf"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_invoice_pdf.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

output "invoice_bucket_name" {
  value = aws_s3_bucket.invoice_pdfs.bucket
}

output "http_api_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "database_endpoint" {
  value = aws_db_instance.postgres.address
}
