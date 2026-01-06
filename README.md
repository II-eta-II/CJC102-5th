# WordPress on AWS ECS Fargate

使用 Terraform 在 AWS 上部署 WordPress，包含 ECS Fargate、RDS、EFS、藍綠部署等完整架構。

## 架構圖

```
User → ALB (HTTPS) → ECS Fargate (Blue/Green) → RDS MySQL (Blue/Green)
                           ↓
                          EFS (wp-content)
```

## 功能特色

- **ECS Fargate** - 無伺服器容器運算
- **RDS MySQL** - 託管資料庫
- **EFS** - 共享檔案儲存 (wp-content)
- **ACM** - 自動 SSL 憑證
- **Auto Scaling** - 自動擴展
- **Blue-Green Deployment** - 自動藍綠部署

## 快速開始

### 0. Route53 跨帳戶設定（必要）

本專案使用共享的 Route53 Hosted Zone (`cjc102.site`)，部署前需先完成跨帳戶權限設定：

1. **設定 AWS CLI Profile** - 詳細步驟請參考 [.aws/README.md](.aws/README.md)
2. **測試權限** - 確認可以存取 Route53 Hosted Zone

```powershell
# 測試是否能列出 DNS 記錄
aws route53 list-resource-record-sets `
  --hosted-zone-id Z01780191CLMBHU6Y6729 `
  --profile cjc102.site
```

> ⚠️ **重要**：若未完成此設定，`terraform apply` 將會因權限不足而失敗。

### 1. 前置準備

```powershell
# 安裝 Terraform
# https://developer.hashicorp.com/terraform/downloads

# 設定 AWS SSO
aws configure sso
aws sso login --profile your-profile
```

### 2. 複製設定檔

```powershell
# 複製並編輯設定檔
cp terraform.tfvars.sample terraform.tfvars
cp secret.auto.tfvars.sample secret.auto.tfvars
```

### 3. 編輯設定檔

**terraform.tfvars:**
```hcl
aws_profile  = "your-aws-profile"
project_name = "your-project-name"
subdomain    = "your-subdomain"  # 組合成 subdomain.cjc102.site
```

**secret.auto.tfvars:**
```hcl
db_username = "admin"
db_password = "YourSecurePassword123!"
wp_username = "admin"
wp_password = "YourWordPressPassword!"
```

### 4. 部署

```powershell
terraform init
terraform plan
terraform apply
```

### 5. 存取

部署完成後，可透過以下方式存取：
- **HTTPS URL**: `https://your-subdomain.cjc102.site`
- **ALB URL**: 從 `terraform output alb_url` 取得

## 目錄結構

```
.
├── main.tf                    # 主要設定 (provider, module)
├── variables.tf               # 變數定義
├── outputs.tf                 # 輸出值
├── bluegreen.auto.tfvars      # 藍綠部署設定
├── ops.tfvars                 # 生產環境設定
├── secret.auto.tfvars         # 機密變數 (不納入版控)
├── *.tfvars.sample            # 範例設定檔
│
├── module/                    # 基礎設施模組
│   ├── vpc.tf                 # VPC, Subnets, NAT Gateway
│   ├── ecs.tf                 # ECS Cluster, Service, Task (Blue/Green)
│   ├── ec2.tf                 # ALB, Target Group, CloudWatch Alarms
│   ├── rds.tf                 # RDS MySQL (Blue/Green)
│   ├── efs.tf                 # EFS 檔案系統
│   ├── s3.tf                  # S3 媒體儲存 + SQL 備份
│   ├── ecr.tf                 # ECR 容器 Registry
│   ├── pipeline.tf            # CI/CD Lambda (ecs_deploy, canary_deploy, sql_import)
│   ├── secrets.tf             # Secrets Manager
│   ├── route53.tf             # DNS, ACM 憑證
│   └── lambda/                # Lambda 程式碼打包
│
├── docs/                      # 文件
│   ├── cicd-auto-deployment.md
│   ├── connect-rds.md
│   ├── copy-s3-to-efs.md
│   ├── header-based-routing.md
│   └── push-image-to-ecr.md
│
└── .aws/                      # AWS CLI 腳本
    └── teammate/              # 跨帳號設定
```

## Route53 跨帳號設定

如需使用共享的 Route53 Hosted Zone (`cjc102.site`)：

1. 參考 `.aws/teammate/README.md`
2. 在你的帳號建立對應的 IAM Role

## 常用指令

```powershell
# 查看輸出值
terraform output

# 更新部署
terraform apply

# 銷毀資源
terraform destroy

# 列出 Route53 記錄
.\.aws\list-route53-record.ps1

# 新增 CNAME 記錄
.\.aws\route53-add-cname.ps1 -Subdomain "myapp" -Target "example.com"
```

## 注意事項

- 首次部署需等待約 5-10 分鐘讓 ACM 憑證驗證完成
- `*.tfvars` 檔案包含機密資料，請勿提交至版控

## 預估成本

| 服務 | 預估月費 (USD) |
|------|----------------|
| ECS Fargate | ~$15-30 |
| RDS db.t3.micro x2 | ~$30 |
| ALB | ~$16 |
| EFS | ~$0.30/GB |
| NAT Gateway | ~$32 |
| **合計** | **~$95-110+** |

> 💡 開發環境可考慮使用 `terraform destroy` 關閉資源以節省成本

## License

MIT
