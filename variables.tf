variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS profile name for SSO or credentials (leave empty to use default)"
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "usa"
}

variable "extra_tags" {
  description = "Extra tags to apply to all resources (can be overridden in tfvars)"
  type        = map(string)
  default     = {}
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

variable "ecr_repository_name" {
  description = "ECR repository name for WordPress image"
  type        = string
  default     = "usa-wordpress"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port exposed by the container (80 for official WordPress, 8080 for Bitnami)"
  type        = number
  default     = 80
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



variable "efs_mount_path" {
  description = "Path to mount EFS in container (Bitnami: /bitnami, Official: /var/www/html)"
  type        = string
  default     = "/bitnami"
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

variable "cwa_api_token" {
  description = "CWA API Token for external service integration"
  type        = string
  sensitive   = true
  default     = ""
}

# Route53 Configuration
variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID for ACM certificate DNS validation"
  type        = string
  default     = "Z01780191CLMBHU6Y6729"
}

variable "route53_domain_name" {
  description = "Domain name of the Route53 Hosted Zone (e.g., 'cjc102.site'). Required because cross-account role lacks ListHostedZones permission."
  type        = string
  default     = "cjc102.site"
}

variable "subdomain" {
  description = "Subdomain name for the application entry point (e.g., 'app' will create app.yourdomain.com). Leave empty for random 4-char subdomain."
  type        = string
  default     = ""
}

# =============================================================================
# Blue-Green Deployment Configuration
# =============================================================================

# Blue Environment
variable "blue_ecs_desired_count" {
  description = "Desired count for Blue ECS service (0 = standby mode)"
  type        = number
  default     = 2
}

variable "blue_ecs_min_capacity" {
  description = "Minimum capacity for Blue ECS Auto Scaling (0 = can scale to zero)"
  type        = number
  default     = 0
}

variable "blue_ecs_max_capacity" {
  description = "Maximum capacity for Blue ECS Auto Scaling"
  type        = number
  default     = 4
}

variable "blue_image_tag" {
  description = "Docker image tag for Blue environment"
  type        = string
  default     = "latest"
}

# Green Environment
variable "green_ecs_desired_count" {
  description = "Desired count for Green ECS service (0 = standby mode)"
  type        = number
  default     = 0
}

variable "green_ecs_min_capacity" {
  description = "Minimum capacity for Green ECS Auto Scaling (0 = can scale to zero)"
  type        = number
  default     = 0
}

variable "green_ecs_max_capacity" {
  description = "Maximum capacity for Green ECS Auto Scaling"
  type        = number
  default     = 4
}

variable "green_image_tag" {
  description = "Docker image tag for Green environment"
  type        = string
  default     = "latest"
}

# ALB Traffic Weights
variable "blue_weight" {
  description = "Traffic weight for Blue environment (0-100)"
  type        = number
  default     = 100
}

variable "green_weight" {
  description = "Traffic weight for Green environment (0-100)"
  type        = number
  default     = 0
}

# =============================================================================
# Canary Deployment Configuration
# =============================================================================

variable "canary_enabled" {
  description = "Enable Canary deployment automation"
  type        = bool
  default     = true
}

variable "canary_percentage" {
  description = "Initial traffic percentage for canary (0-50)"
  type        = number
  default     = 10
}

variable "pre_deploy_wait_sec" {
  description = "Wait time for new deployment to be ready before canary (seconds)"
  type        = number
  default     = 120
}

variable "canary_duration_sec" {
  description = "Duration to observe canary before full deployment (seconds)"
  type        = number
  default     = 300
}

variable "full_deploy_wait_sec" {
  description = "Wait time after full deployment (seconds)"
  type        = number
  default     = 60
}

variable "rollback_window_sec" {
  description = "Time window for manual rollback after deployment (seconds)"
  type        = number
  default     = 600
}

