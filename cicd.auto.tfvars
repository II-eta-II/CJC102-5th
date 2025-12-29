# =============================================================================
# CI/CD Configuration
# =============================================================================

# 啟用 CI/CD Pipeline
enable_cicd = false

# GitHub Repository
github_repo_owner = "II-eta-II"
github_repo_name  = "wordpress_image"
github_branch     = "eta"

# NOTE: CodeStar Connection 由 Terraform 自動建立
# 建立後需要在 AWS Console 中手動授權 GitHub 連接

# Pipeline Failure Notifications
# 設定後會收到 SNS 確認郵件，必須點擊確認連結才能接收通知
pipeline_notification_email = "yitaoshieh@gmail.com" # 請填入您的 email 地址
