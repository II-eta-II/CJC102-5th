variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS profile name for SSO or credentials (leave empty to use default)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "Project"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ECS Configuration
variable "ecs_cluster_name" {
  description = "ECS Cluster name"
  type        = string
  default     = "wordpress-cluster"
}

variable "ecs_service_name" {
  description = "ECS Service name"
  type        = string
  default     = "wordpress-service"
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
  default     = "public.ecr.aws/bitnami/wordpress:latest"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 8080
}

variable "ecs_task_cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 1024
}

variable "ecs_task_memory" {
  description = "Memory for the task in MB"
  type        = number
  default     = 2048
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 10
}

variable "efs_mount_path" {
  description = "Path to mount EFS in container"
  type        = string
  default     = "/var/www/html/wp-content"
}

# RDS Configuration
variable "db_name" {
  description = "Database name for WordPress"
  type        = string
  default     = "wordpress"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

# WordPress Configuration
variable "wp_username" {
  description = "WordPress admin username"
  type        = string
  default     = "admin"
}

variable "wp_password" {
  description = "WordPress admin password"
  type        = string
  sensitive   = true
}

# CloudFront Configuration
variable "cloudfront_price_class" {
  description = "Price class for CloudFront distribution (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_All"
}

variable "cloudfront_default_ttl" {
  description = "Default TTL for CloudFront cache in seconds"
  type        = number
  default     = 86400 # 24 hours
}

variable "cloudfront_max_ttl" {
  description = "Maximum TTL for CloudFront cache in seconds"
  type        = number
  default     = 31536000 # 1 year
}

variable "cloudfront_static_ttl" {
  description = "TTL for static assets in CloudFront cache in seconds"
  type        = number
  default     = 31536000 # 1 year
}

variable "cloudfront_log_retention_days" {
  description = "Number of days to retain CloudFront logs in S3"
  type        = number
  default     = 30
}

# WAF Configuration
variable "waf_rate_limit" {
  description = "Rate limit for WAF (requests per 5 minutes per IP)"
  type        = number
  default     = 2000
}

variable "waf_log_retention_days" {
  description = "Number of days to retain WAF logs in CloudWatch"
  type        = number
  default     = 30
}

# Route53 Configuration
variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID for ACM certificate DNS validation"
  type        = string
}

variable "subdomain" {
  description = "Subdomain name for the application entry point (e.g., 'app' will create app.yourdomain.com)"
  type        = string
}



