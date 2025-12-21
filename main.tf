terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"

  # Local backend - store tfstate in ./backend/
  backend "local" {
    path = "./backend/terraform.tfstate"
  }
}

# Random 4-char subdomain generator
resource "random_string" "subdomain" {
  length  = 4
  special = false
  upper   = false
  numeric = false
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  # Terraform 會自動使用以下順序尋找 AWS 憑證：
  # 1. 環境變數 (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  # 2. AWS SSO 憑證（如果指定了 profile）
  # 3. ~/.aws/credentials 檔案中的指定 profile 或 [default] profile

  # 使用變數設定預設標籤
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = var.project_name
    }
  }
}

# Provider for WAF (必須在 us-east-1，因為 CloudFront 的 WAF 只能在 us-east-1 創建)
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = var.project_name
    }
  }
}

# WordPress Infrastructure Module
module "wordpress" {
  source = "./module"

  # Pass provider aliases
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  # Core Configuration
  aws_region   = var.aws_region
  aws_profile  = var.aws_profile
  project_name = var.project_name

  # VPC Configuration
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # ECS Configuration
  ecs_cluster_name  = var.ecs_cluster_name
  ecs_service_name  = var.ecs_service_name
  container_image   = var.container_image
  container_port    = var.container_port
  ecs_task_cpu      = var.ecs_task_cpu
  ecs_task_memory   = var.ecs_task_memory
  ecs_desired_count = var.ecs_desired_count
  ecs_min_capacity  = var.ecs_min_capacity
  ecs_max_capacity  = var.ecs_max_capacity
  efs_mount_path    = var.efs_mount_path

  # RDS Configuration
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage

  # WordPress Configuration
  wp_username = var.wp_username
  wp_password = var.wp_password

  # CloudFront Configuration
  cloudfront_price_class        = var.cloudfront_price_class
  cloudfront_default_ttl        = var.cloudfront_default_ttl
  cloudfront_max_ttl            = var.cloudfront_max_ttl
  cloudfront_static_ttl         = var.cloudfront_static_ttl
  cloudfront_log_retention_days = var.cloudfront_log_retention_days

  # WAF Configuration
  waf_rate_limit         = var.waf_rate_limit
  waf_log_retention_days = var.waf_log_retention_days

  # Route53 Configuration
  route53_zone_id = var.route53_zone_id
  subdomain       = var.subdomain != "" ? var.subdomain : random_string.subdomain.result
}

