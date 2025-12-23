# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.project_name}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  web_acl_id          = aws_wafv2_web_acl.main.arn

  # Custom domain aliases
  aliases = ["${var.subdomain}.${local.route53_domain_name}"]

  # ALB ‰ΩúÁÇ∫‰æÜÊ?ÔºàOAC ?™ËÉΩ?®Êñº S3ÔºåALB ‰∏çÈ?Ë¶ÅÔ?
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "ALB-${var.project_name}"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 60
      origin_keepalive_timeout = 5
    }

    custom_header {
      name  = "X-Forwarded-Host"
      value = aws_lb.main.dns_name
    }
  }

  # ?ØÈÅ∏ÔºöS3 ‰ΩúÁÇ∫?úÊ?Ë≥áÊ?‰æÜÊ?
  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = "S3-${var.project_name}-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ?êË®≠Âø´Â?Ë°åÁÇ∫ÔºàÊ???ALBÔº?
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-${var.project_name}"

    forwarded_values {
      query_string = true
      headers      = ["Host", "CloudFront-Forwarded-Proto"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = var.cloudfront_default_ttl
    max_ttl                = var.cloudfront_max_ttl
  }

  # ?úÊ?Ë≥áÊ?Âø´Â?Ë°åÁÇ∫ÔºàÊ???S3Ôº?
  ordered_cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.project_name}-static"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = var.cloudfront_static_ttl
    max_ttl                = var.cloudfront_static_ttl
  }

  # ?™Ë??ØË™§?ÅÈù¢
  custom_error_response {
    error_code         = 403
    response_code      = 403
    response_page_path = "/error.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/error.html"
  }

  # ?•Ë?Ë®≠Â?
  logging_config {
    bucket          = aws_s3_bucket.cloudfront_logs.bucket_domain_name
    include_cookies = false
    prefix          = "cloudfront-logs"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use ACM certificate from us-east-1 for custom domain
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-cloudfront"
  }
}

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.project_name}-s3-oac"
  description                       = "OAC for S3 static assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 Bucket Policy for CloudFront OAC
resource "aws_s3_bucket_policy" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_assets.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# Ê≥®Ê?ÔºöCloudFront ?ÉÈÄöÈ??¨Á∂≤Ë®™Â? ALB
# ALB ??security group Â∑≤Á??ÅË®±‰æÜËá™Á∂≤È?Á∂≤Ë∑Ø??HTTP/HTTPS ÊµÅÈ?
# Â¶ÇÊ??ÄË¶ÅÊõ¥?¥Ê†º?ÑÂ??®Êéß?∂Ô??Ø‰ª•?ÉÊÖÆ‰ΩøÁî® AWS WAF ‰æÜÈ??∂‰?Ê∫?IP

