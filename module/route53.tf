# Route53 and ACM Configuration for HTTPS

# Data source for existing Route53 Hosted Zone
# 使用跨帳戶授權的 provider 來存取 Route53 hosted zone
data "aws_route53_zone" "main" {
  provider = aws.route53
  zone_id  = var.route53_zone_id
}

# ACM Certificate
resource "aws_acm_certificate" "main" {
  domain_name       = data.aws_route53_zone.main.name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${data.aws_route53_zone.main.name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-acm-cert"
  }
}

# DNS Validation Records
resource "aws_route53_record" "acm_validation" {
  provider = aws.route53

  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# ACM Certificate Validation
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# Route53 A Record pointing to ALB (for root domain)
resource "aws_route53_record" "alb" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = data.aws_route53_zone.main.name
  type     = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# ========================================
# CloudFront ACM Certificate (us-east-1)
# CloudFront requires certificates in us-east-1
# ========================================

# ACM Certificate for CloudFront (must be in us-east-1)
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = "${var.subdomain}.${trimsuffix(data.aws_route53_zone.main.name, ".")}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cloudfront-acm-cert"
  }
}

# DNS Validation Record for CloudFront ACM (single domain)
resource "aws_route53_record" "cloudfront_acm_validation" {
  provider        = aws.route53
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.cloudfront.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.cloudfront.domain_validation_options)[0].resource_record_value]
  ttl             = 60
  type            = tolist(aws_acm_certificate.cloudfront.domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# CloudFront ACM Certificate Validation
resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [aws_route53_record.cloudfront_acm_validation.fqdn]
}

# Route53 CNAME Record for subdomain -> CloudFront
resource "aws_route53_record" "entry_point" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "${var.subdomain}.${trimsuffix(data.aws_route53_zone.main.name, ".")}"
  type     = "CNAME"
  ttl      = 300
  records  = [aws_cloudfront_distribution.main.domain_name]
}



