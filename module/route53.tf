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
    "*.${local.route53_domain_name}",
    "*.${var.subdomain}.${local.route53_domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [subject_alternative_names]
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
# 已移除：不建立或修改 root domain (cjc102.site) 的 A 記錄
# 因為 root domain 可能被其他人使用，我們只使用 subdomain
# resource "aws_route53_record" "alb" {
#   provider = aws.route53
#   zone_id  = local.route53_zone_id
#   name     = local.route53_domain_name
#   type     = "A"
#
#   alias {
#     name                   = aws_lb.main.dns_name
#     zone_id                = aws_lb.main.zone_id
#     evaluate_target_health = true
#   }
# }

# Route53 A Record for subdomain -> ALB
resource "aws_route53_record" "entry_point" {
  provider = aws.route53
  zone_id  = local.route53_zone_id
  name     = "${var.subdomain}.${local.route53_domain_name}"
  type     = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Temporarily disabled - Blue subdomain Route53 record
# resource "aws_route53_record" "blue_subdomain" {
#   provider = aws.route53
#   zone_id  = local.route53_zone_id
#   name     = "blue.${var.subdomain}.${local.route53_domain_name}"
#   type     = "A"
#
#   alias {
#     name                   = aws_lb.main.dns_name
#     zone_id                = aws_lb.main.zone_id
#     evaluate_target_health = true
#   }
# }

# Temporarily disabled - Green subdomain Route53 record
# resource "aws_route53_record" "green_subdomain" {
#   provider = aws.route53
#   zone_id  = local.route53_zone_id
#   name     = "green.${var.subdomain}.${local.route53_domain_name}"
#   type     = "A"
#
#   alias {
#     name                   = aws_lb.main.dns_name
#     zone_id                = aws_lb.main.zone_id
#     evaluate_target_health = true
#   }
# }
