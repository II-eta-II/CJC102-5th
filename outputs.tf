# =============================================================================
# 主要輸出 - 依照重要性排序
# =============================================================================

output "a_website_url" {
  description = "WordPress 網站 URL (Route53 CNAME)"
  value       = "https://${local.subdomain}.${var.route53_domain_name}"
}

output "b_alb_dns_name" {
  description = "ALB DNS 名稱（實際端點）"
  value       = module.wordpress.alb_dns_name
}

output "c_blue_green_traffic" {
  description = "藍綠環境流量權重比例"
  value = {
    blue_weight  = var.blue_weight
    green_weight = var.green_weight
  }
}

output "d_blue_environment" {
  description = "Blue 環境配置"
  value = {
    image_tag     = var.blue_image_tag
    desired_count = var.blue_ecs_desired_count
  }
}

output "e_green_environment" {
  description = "Green 環境配置"
  value = {
    image_tag     = var.green_image_tag
    desired_count = var.green_ecs_desired_count
  }
}

# =============================================================================
# 基礎設施詳細資訊
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.wordpress.vpc_id
}


output "s3_media_offload_bucket_name" {
  description = "S3 bucket name for WordPress media offload"
  value       = module.wordpress.s3_media_offload_bucket_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for WordPress image"
  value       = module.wordpress.ecr_repository_url
}
