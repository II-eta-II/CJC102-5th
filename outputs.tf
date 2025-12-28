# Root-level outputs - forwarding from module

output "vpc_id" {
  description = "VPC ID"
  value       = module.wordpress.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.wordpress.vpc_cidr
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.wordpress.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.wordpress.private_subnet_ids
}

output "efs_id" {
  description = "EFS File System ID"
  value       = module.wordpress.efs_id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = module.wordpress.efs_dns_name
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = module.wordpress.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS Service Name"
  value       = module.wordpress.ecs_service_name
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.wordpress.rds_endpoint
}

output "rds_address" {
  description = "RDS instance address"
  value       = module.wordpress.rds_address
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.wordpress.alb_dns_name
}

output "alb_url" {
  description = "URL to access the application via ALB"
  value       = module.wordpress.alb_url
}

output "s3_media_offload_bucket_name" {
  description = "S3 bucket name for WordPress media offload"
  value       = module.wordpress.s3_media_offload_bucket_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for WordPress image"
  value       = module.wordpress.ecr_repository_url
}
