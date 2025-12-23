# Route53 and ACM Configuration for HTTPS

# 使用 locals 來存放 Route53 資訊，避免使用需要 ListHostedZones 權限的 data source
# 跨帳戶 role 只有 ListResourceRecordSets 和 ChangeResourceRecordSets 權限
locals {
  route53_zone_id     = var.route53_zone_id
  route53_domain_name = var.route53_domain_name
}

# ACM Certificate
resource "aws_acm_certificate" "main" {
  domain_name       = local.route53_domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${local.route53_domain_name}"
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
  zone_id         = local.route53_zone_id
}

# ACM Certificate Validation
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# Route53 A Record pointing to ALB (for root domain)
resource "aws_route53_record" "alb" {
  provider = aws.route53
  zone_id  = local.route53_zone_id
  name     = local.route53_domain_name
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
  domain_name       = "${var.subdomain}.${local.route53_domain_name}"
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
  zone_id         = local.route53_zone_id
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
  zone_id  = local.route53_zone_id
  name     = "${var.subdomain}.${local.route53_domain_name}"
  type     = "CNAME"
  ttl      = 300
  records  = [aws_cloudfront_distribution.main.domain_name]
}



