############################
# Lambda Permissions
############################

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role"
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
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################
# Lambda Code
############################

data "archive_file" "register_customer" {
  type        = "zip"
  output_path = "${path.module}/build/register_customer.zip"
  source {
    filename = "lambda_function.py"
    content  = <<-PY
      import json
      import uuid
      def lambda_handler(event, context):
          body = json.loads(event.get("body") or "{}")
          return {
              "statusCode": 200,
              "headers": {
                  "Access-Control-Allow-Origin": "*",
                  "Access-Control-Allow-Headers": "Authorization,Content-Type",
                  "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
              },
              "body": json.dumps({
                  "message": "Mock customer registered successfully.",
                  "customer": {
                      "customer_id": str(uuid.uuid4()),
                      "name": body.get("name", "Mock Customer"),
                      "email": body.get("email", "customer@example.com")
                  }
              })
          }
    PY
  }
}

data "archive_file" "register_invoice" {
  type        = "zip"
  output_path = "${path.module}/build/register_invoice.zip"
  source {
    filename = "lambda_function.py"
    content  = <<-PY
      import json
      import uuid
      from datetime import datetime, timezone
      def lambda_handler(event, context):
          body = json.loads(event.get("body") or "{}")
          return {
              "statusCode": 200,
              "headers": {
                  "Access-Control-Allow-Origin": "*",
                  "Access-Control-Allow-Headers": "Authorization,Content-Type",
                  "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
              },
              "body": json.dumps({
                  "message": "Mock invoice registered successfully.",
                  "invoice": {
                      "invoice_id": str(uuid.uuid4()),
                      "customer_id": body.get("customer_id", "mock-customer-id"),
                      "amount": body.get("amount", 1000),
                      "currency": body.get("currency", "SEK"),
                      "status": "active",
                      "created_at": datetime.now(timezone.utc).isoformat()
                  }
              })
          }
    PY
  }
}

data "archive_file" "fetch_active_invoices" {
  type        = "zip"
  output_path = "${path.module}/build/fetch_active_invoices.zip"
  source {
    filename = "lambda_function.py"
    content  = <<-PY
      import json
      def lambda_handler(event, context):
          return {
              "statusCode": 200,
              "headers": {
                  "Access-Control-Allow-Origin": "*",
                  "Access-Control-Allow-Headers": "Authorization,Content-Type",
                  "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
              },
              "body": json.dumps({
                  "message": "Mock active invoices fetched successfully.",
                  "invoices": [
                      {
                          "invoice_id": "inv-001",
                          "customer_name": "Acme AB",
                          "amount": 12500,
                          "currency": "SEK",
                          "status": "active"
                      },
                      {
                          "invoice_id": "inv-002",
                          "customer_name": "Nordic Demo Ltd",
                          "amount": 8900,
                          "currency": "SEK",
                          "status": "active"
                      }
                  ]
              })
          }
    PY
  }
}

data "archive_file" "generate_invoice_pdf" {
  type        = "zip"
  output_path = "${path.module}/build/generate_invoice_pdf.zip"
  source {
    filename = "lambda_function.py"
    content  = <<-PY
      import json
      def lambda_handler(event, context):
          invoice_id = event.get("pathParameters", {}).get("invoice_id", "mock-invoice-id")
          return {
              "statusCode": 200,
              "headers": {
                  "Access-Control-Allow-Origin": "*",
                  "Access-Control-Allow-Headers": "Authorization,Content-Type",
                  "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
              },
              "body": json.dumps({
                  "message": "Mock invoice PDF generated successfully.",
                  "invoice_id": invoice_id,
                  "s3_key": f"invoices/mock-user/{invoice_id}.pdf"
              })
          }
    PY
  }
}

data "archive_file" "fetch_invoice_pdf" {
  type        = "zip"
  output_path = "${path.module}/build/fetch_invoice_pdf.zip"
  source {
    filename = "lambda_function.py"
    content  = <<-PY
      import json
      def lambda_handler(event, context):
          invoice_id = event.get("pathParameters", {}).get("invoice_id", "mock-invoice-id")
          return {
              "statusCode": 200,
              "headers": {
                  "Access-Control-Allow-Origin": "*",
                  "Access-Control-Allow-Headers": "Authorization,Content-Type",
                  "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
              },
              "body": json.dumps({
                  "message": "Mock invoice PDF fetched successfully.",
                  "invoice_id": invoice_id,
                  "download_url": f"https://example.com/mock-downloads/{invoice_id}.pdf"
              })
          }
    PY
  }
}

############################
# Lambda Function Resources
############################

resource "aws_lambda_function" "register_customer" {
  function_name = "${var.project_name}-register-customer"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.register_customer.output_path
  source_code_hash = data.archive_file.register_customer.output_base64sha256
  timeout     = 10
  memory_size = 128
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}

resource "aws_lambda_function" "register_invoice" {
  function_name = "${var.project_name}-register-invoice"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.register_invoice.output_path
  source_code_hash = data.archive_file.register_invoice.output_base64sha256
  timeout     = 10
  memory_size = 128
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}

resource "aws_lambda_function" "fetch_active_invoices" {
  function_name = "${var.project_name}-fetch-active-invoices"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.fetch_active_invoices.output_path
  source_code_hash = data.archive_file.fetch_active_invoices.output_base64sha256
  timeout     = 10
  memory_size = 128
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}

resource "aws_lambda_function" "generate_invoice_pdf" {
  function_name = "${var.project_name}-generate-invoice-pdf"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.generate_invoice_pdf.output_path
  source_code_hash = data.archive_file.generate_invoice_pdf.output_base64sha256
  timeout     = 10
  memory_size = 128
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}

resource "aws_lambda_function" "fetch_invoice_pdf" {
  function_name = "${var.project_name}-fetch-invoice-pdf"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.fetch_invoice_pdf.output_path
  source_code_hash = data.archive_file.fetch_invoice_pdf.output_base64sha256
  timeout     = 10
  memory_size = 128
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}