############################
# API Gateway
############################

resource "aws_api_gateway_rest_api" "nordledger_api" {
  name        = "${var.project_name}-api"
  description = "NordLedger client MVP API"
}

############################
# Cognito Authorizer
############################

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${var.project_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.nordledger_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.frontend_auth.arn]
}

############################
# API Resources / Paths
############################

# /customers
resource "aws_api_gateway_resource" "customers" {
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  parent_id   = aws_api_gateway_rest_api.nordledger_api.root_resource_id
  path_part   = "customers"
}

# /invoices
resource "aws_api_gateway_resource" "invoices" {
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  parent_id   = aws_api_gateway_rest_api.nordledger_api.root_resource_id
  path_part   = "invoices"
}

# /invoices/active
resource "aws_api_gateway_resource" "invoices_active" {
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  parent_id   = aws_api_gateway_resource.invoices.id
  path_part   = "active"
}

# /invoices/{invoice_id}
resource "aws_api_gateway_resource" "invoice_id" {
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  parent_id   = aws_api_gateway_resource.invoices.id
  path_part   = "{invoice_id}"
}

# /invoices/{invoice_id}/pdf
resource "aws_api_gateway_resource" "invoice_pdf" {
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  parent_id   = aws_api_gateway_resource.invoice_id.id
  path_part   = "pdf"
}

############################
# Route Configuration
############################

locals {
  api_routes = {
    post_customers = {
      resource_id          = aws_api_gateway_resource.customers.id
      http_method          = "POST"
      path                 = "/customers"
      lambda_invoke_arn    = aws_lambda_function.register_customer.invoke_arn
      lambda_function_name = aws_lambda_function.register_customer.function_name
    }

    post_invoices = {
      resource_id          = aws_api_gateway_resource.invoices.id
      http_method          = "POST"
      path                 = "/invoices"
      lambda_invoke_arn    = aws_lambda_function.register_invoice.invoke_arn
      lambda_function_name = aws_lambda_function.register_invoice.function_name
    }

    get_active_invoices = {
      resource_id          = aws_api_gateway_resource.invoices_active.id
      http_method          = "GET"
      path                 = "/invoices/active"
      lambda_invoke_arn    = aws_lambda_function.fetch_active_invoices.invoke_arn
      lambda_function_name = aws_lambda_function.fetch_active_invoices.function_name
    }

    post_invoice_pdf = {
      resource_id          = aws_api_gateway_resource.invoice_pdf.id
      http_method          = "POST"
      path                 = "/invoices/*/pdf"
      lambda_invoke_arn    = aws_lambda_function.generate_invoice_pdf.invoke_arn
      lambda_function_name = aws_lambda_function.generate_invoice_pdf.function_name
    }

    get_invoice_pdf = {
      resource_id          = aws_api_gateway_resource.invoice_pdf.id
      http_method          = "GET"
      path                 = "/invoices/*/pdf"
      lambda_invoke_arn    = aws_lambda_function.fetch_invoice_pdf.invoke_arn
      lambda_function_name = aws_lambda_function.fetch_invoice_pdf.function_name
    }
  }

  cors_resources = {
    customers       = aws_api_gateway_resource.customers.id
    invoices        = aws_api_gateway_resource.invoices.id
    invoices_active = aws_api_gateway_resource.invoices_active.id
    invoice_pdf     = aws_api_gateway_resource.invoice_pdf.id
  }
}

############################
# API Gateway Methods
############################

resource "aws_api_gateway_method" "routes" {
  for_each = local.api_routes
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

############################
# API Gateway Lambda Integrations
############################

resource "aws_api_gateway_integration" "routes" {
  for_each = local.api_routes
  rest_api_id             = aws_api_gateway_rest_api.nordledger_api.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.routes[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = each.value.lambda_invoke_arn
}

############################
# Lambda Permissions
############################

resource "aws_lambda_permission" "allow_api_gateway" {
  for_each = local.api_routes
  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "${aws_api_gateway_rest_api.nordledger_api.execution_arn}/*/${each.value.http_method}${each.value.path}"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

############################
# CORS: OPTIONS Methods
############################

resource "aws_api_gateway_method" "cors" {
  for_each = local.cors_resources
  rest_api_id   = aws_api_gateway_rest_api.nordledger_api.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors" {
  for_each = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  type = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "cors" {
  for_each = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "cors" {
  for_each = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  status_code = aws_api_gateway_method_response.cors[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Authorization,Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [
    aws_api_gateway_integration.cors
  ]
}

############################
# API Gateway Deployment
############################

resource "aws_api_gateway_deployment" "nordledger_api" {
  rest_api_id = aws_api_gateway_rest_api.nordledger_api.id
  triggers = {
    redeployment = sha1(jsonencode({
      resources = [
        aws_api_gateway_resource.customers.id,
        aws_api_gateway_resource.invoices.id,
        aws_api_gateway_resource.invoices_active.id,
        aws_api_gateway_resource.invoice_id.id,
        aws_api_gateway_resource.invoice_pdf.id
      ]
      routes = local.api_routes
      methods = {
        for key, method in aws_api_gateway_method.routes :
        key => method.id
      }
      integrations = {
        for key, integration in aws_api_gateway_integration.routes :
        key => integration.id
      }
      cors_methods = {
        for key, method in aws_api_gateway_method.cors :
        key => method.id
      }
      cors_integrations = {
        for key, integration in aws_api_gateway_integration.cors :
        key => integration.id
      }
    }))
  }
  depends_on = [
    aws_api_gateway_integration.routes,
    aws_api_gateway_integration_response.cors,
    aws_lambda_permission.allow_api_gateway
  ]
  lifecycle {
    create_before_destroy = true
  }
}

############################
# API Gateway Stage
############################

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.nordledger_api.id
  deployment_id = aws_api_gateway_deployment.nordledger_api.id
  stage_name    = "prod"
}
