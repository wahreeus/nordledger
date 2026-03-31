locals {
  group_policies = {
    contractors = {
      description = "Requires time-limited access restricted to specific projects and environments."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    engineering-dev = {
      description = "Requires access to dev environments with strict separation from prod and test environments."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    engineering-prod = {
      description = "Requires access to prod environments with strict separation from dev and test environments."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    engineering-test = {
      description = "Requires access to test environments with strict separation from dev and prod environments."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    executives = {
      description = "Requires read-only access to reports and dashboards."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    finance = {
      description = "Requires access to invoicing, payouts, accounting exports, and audit trails."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    platform = {
      description = "Requires elevated administrative access with strong control and auditing."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    sales = {
      description = "Requires access to the CRM and limited customer metadata."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
    support = {
      description = "Requires access to customer accounts, but not to raw payment details."
      statements = [{
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }]
    }
  }
}

resource "aws_iam_group" "groups" {
  for_each = local.group_policies
  name     = each.key
}

resource "aws_iam_policy" "group_policy" {
  for_each = local.group_policies
  name        = "${each.key}-policy"
  description = each.value.description
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value.statements
  })
}

resource "aws_iam_group_policy_attachment" "group_policy_attachment" {
  for_each = local.group_policies
  group      = aws_iam_group.groups[each.key].name
  policy_arn = aws_iam_policy.group_policy[each.key].arn
}