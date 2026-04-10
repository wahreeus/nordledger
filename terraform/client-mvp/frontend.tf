############################
# CloudFront
############################

resource "aws_cloudfront_distribution" "frontend_distribution" {
  enabled             = true
  default_root_object = "index.html"
  origin {
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id                = "s3-frontend-bucket-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_bucket.id
  }
  default_cache_behavior {
    target_origin_id       = "s3-frontend-bucket-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  tags = {
    Name    = "${var.project_name}-cloudfront"
    Project = var.project_name
  }
}

############################
# S3 Bucket
############################

resource "aws_s3_bucket" "frontend_bucket" {
  bucket = var.frontend_bucket_name
  tags = {
    Name    = "${var.project_name}-frontend-bucket"
    Project = var.project_name
  }
}
