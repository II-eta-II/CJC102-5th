
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

# Gateway Outputs
output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

# Route Table Outputs
output "public_route_table_id" {
  description = "Public Route Table ID"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private Route Table ID"
  value       = aws_route_table.private.id
}

# EFS Outputs
output "efs_id" {
  description = "EFS File System ID"
  value       = aws_efs_file_system.main.id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = aws_efs_file_system.main.dns_name
}

output "efs_access_point_id" {
  description = "EFS Access Point ID for ECS"
  value       = aws_efs_access_point.ecs.id
}

output "efs_security_group_id" {
  description = "EFS Security Group ID"
  value       = aws_security_group.efs.id
}

output "efs_mount_target_ids" {
  description = "List of EFS Mount Target IDs"
  value       = aws_efs_mount_target.main[*].id
}

# ECS Outputs
output "ecs_cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS Service Name"
  value       = aws_ecs_service.main.name
}

output "ecs_task_definition_arn" {
  description = "ECS Task Definition ARN"
  value       = aws_ecs_task_definition.main.arn
}

output "ecs_security_group_id" {
  description = "ECS Tasks Security Group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "ecs_log_group_name" {
  description = "CloudWatch Log Group for ECS"
  value       = aws_cloudwatch_log_group.ecs.name
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS instance address"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.main.db_name
}

output "rds_username" {
  description = "RDS master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

# ALB Outputs
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.ecs.arn
}



output "alb_url" {
  description = "URL to access the application via ALB"
  value       = "http://${aws_lb.main.dns_name}"
}

# S3 Outputs
output "s3_static_assets_bucket_name" {
  description = "S3 bucket name for static assets"
  value       = aws_s3_bucket.static_assets.id
}

output "s3_static_assets_bucket_arn" {
  description = "S3 bucket ARN for static assets"
  value       = aws_s3_bucket.static_assets.arn
}

output "s3_cloudfront_logs_bucket_name" {
  description = "S3 bucket name for CloudFront logs"
  value       = aws_s3_bucket.cloudfront_logs.id
}

output "s3_media_offload_bucket_name" {
  description = "S3 bucket name for WordPress media offload"
  value       = aws_s3_bucket.media_offload.id
}

output "s3_media_offload_bucket_arn" {
  description = "S3 bucket ARN for WordPress media offload"
  value       = aws_s3_bucket.media_offload.arn
}

# WAF Outputs
output "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  value       = aws_wafv2_web_acl.main.id
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.main.arn
}

# CloudFront Outputs
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_url" {
  description = "URL to access the application via CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

# ECR Outputs
output "ecr_repository_url" {
  description = "ECR repository URL for WordPress image"
  value       = aws_ecr_repository.wordpress.repository_url
}
