terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"

  backend "s3" {
    bucket         = "cjc102-5th-terraform-state-4zr7cthj"
    key            = "terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "cjc102-5th-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  # Terraform 會自動使用以下順序尋找 AWS 憑證：
  # 1. 環境變數 (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  # 2. AWS SSO 憑證
  # 3. ~/.aws/credentials 檔案中的 [default] profile

  # 使用變數設定預設標籤
  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  }
}
