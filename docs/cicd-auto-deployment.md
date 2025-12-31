# CI/CD 自動化部署流程

本文件說明如何透過 GitHub Actions 和 AWS Lambda 實現全自動化的藍綠部署。

## 架構概覽

```
GitHub Push → GitHub Actions → ECR + S3 → EventBridge → Lambda → ECS + RDS
```

---

## 完整流程

### 1. GitHub Actions 觸發

當 GitHub repo 收到 push 時，自動執行：

```yaml
name: Deploy to AWS

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      # 建立 Docker Image
      - name: Build and Push to ECR
        run: |
          aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $ECR_REGISTRY
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        env:
          ECR_REGISTRY: ${{ secrets.ECR_REGISTRY }}
          ECR_REPOSITORY: ${{ secrets.ECR_REPOSITORY }}
          IMAGE_TAG: ${{ github.sha }}
      
      # 匯出資料庫並上傳
      - name: Export Database and Upload to S3
        run: |
          mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME > db_dump_$(date +%Y-%m-%d-%H-%M).sql
          aws s3 cp db_dump_*.sql s3://$SQL_BACKUP_BUCKET/
        env:
          DB_HOST: ${{ secrets.DB_HOST }}
          DB_USER: ${{ secrets.DB_USER }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
          DB_NAME: ${{ secrets.DB_NAME }}
          SQL_BACKUP_BUCKET: usa-ops-sql-backup-usa
```

---

### 2. EventBridge 監聽 ECR Push

當 Docker Image 推送到 ECR 時，EventBridge 自動觸發：

**觸發條件：**
- Event Source: `aws.ecr`
- Action Type: `PUSH`
- Repository: `usa-ops-wordpress`
- Result: `SUCCESS`

**觸發目標：**
1. `usa-ops-ecs-deploy` Lambda
2. `usa-ops-sql-import` Lambda

---

### 3. Lambda 自動部署

#### 3.1 ECS Deploy Lambda

**功能：** 強制 ECS Service 重新部署新的 Task

**程式邏輯：**
```python
# 讀取環境變數
cluster_name = os.environ['ECS_CLUSTER_NAME']
service_names = os.environ['ECS_SERVICE_NAMES'].split(',')

# 對每個 Service 執行 force-new-deployment
for service_name in service_names:
    ecs.update_service(
        cluster=cluster_name,
        service=service_name,
        forceNewDeployment=True
    )
```

**結果：** ECS 自動 pull 最新 Image 並重啟 Tasks

---

#### 3.2 SQL Import Lambda

**功能：** 匯入最新 SQL 到流量為 0 的環境

**程式邏輯：**

1. **從 S3 取得最新 .sql 檔案**
   ```python
   response = s3.list_objects_v2(Bucket=bucket_name)
   sql_files = [obj for obj in response['Contents'] if obj['Key'].endswith('.sql')]
   latest_file = max(sql_files, key=lambda x: x['LastModified'])
   ```

2. **判斷哪個環境流量為 0**
   ```python
   rules = elbv2.describe_rules(ListenerArn=listener_arn)
   target_groups = default_rule['Actions'][0]['ForwardConfig']['TargetGroups']
   
   for tg in target_groups:
       if tg['Weight'] == 0:
           inactive_env = 'blue' or 'green'
           rds_host = blue_rds_host or green_rds_host
   ```

3. **連接 RDS 並 Import SQL**
   ```python
   conn = pymysql.connect(
       host=rds_host,
       user=db_user,
       password=db_password,
       database=db_name,
       client_flag=CLIENT.MULTI_STATEMENTS  # 支援多語句執行
   )
   cursor.execute(sql_content)  # 執行整個 SQL dump
   conn.commit()
   ```

**結果：** 非活躍環境的資料庫同步到最新狀態

---

## 權限需求

### GitHub Actions Secrets

| Secret 名稱 | 說明 |
|------------|------|
| `AWS_ACCESS_KEY_ID` | AWS IAM 使用者 Access Key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM 使用者 Secret Key |
| `ECR_REGISTRY` | ECR Registry URL |
| `ECR_REPOSITORY` | ECR Repository 名稱 |
| `DB_HOST` | RDS Endpoint |
| `DB_USER` | 資料庫使用者名稱 |
| `DB_PASSWORD` | 資料庫密碼 |
| `DB_NAME` | 資料庫名稱 |

### Lambda IAM 權限

**ECS Deploy Lambda:**
- `ecs:UpdateService`
- `ecs:DescribeServices`

**SQL Import Lambda:**
- `s3:GetObject`, `s3:ListBucket`
- `elasticloadbalancing:DescribeRules`
- `secretsmanager:GetSecretValue`
- `ec2:CreateNetworkInterface` (VPC 存取)

---

## 測試部署流程

### 1. 手動測試 Lambda

```bash
# 測試 ECS Deploy
aws lambda invoke \
  --function-name usa-ops-ecs-deploy \
  --region ap-northeast-1 \
  output.json

# 測試 SQL Import
aws lambda invoke \
  --function-name usa-ops-sql-import \
  --region ap-northeast-1 \
  output.json
```

### 2. 模擬 ECR Push

```bash
# Push 測試 Image
docker tag myapp:latest $ECR_REGISTRY/$ECR_REPOSITORY:test
docker push $ECR_REGISTRY/$ECR_REPOSITORY:test
```

EventBridge 應該會自動觸發兩個 Lambda。

### 3. 查看 CloudWatch Logs

```bash
# ECS Deploy Logs
aws logs tail /aws/lambda/usa-ops-ecs-deploy --follow --region ap-northeast-1

# SQL Import Logs
aws logs tail /aws/lambda/usa-ops-sql-import --follow --region ap-northeast-1
```

---

## 故障排除

### Lambda 無法連接 RDS

**症狀：** Connection timed out

**解決：**
- 確認 Lambda Security Group 加入 RDS Security Group 的 ingress rule
- 檢查 Lambda 是否在正確的 VPC Subnets

### SQL Import 語法錯誤

**症狀：** MySQL syntax error

**解決：**
- 確認使用 `CLIENT.MULTI_STATEMENTS` flag
- 檢查 SQL dump 編碼為 UTF-8

### EventBridge 未觸發

**症狀：** ECR Push 後 Lambda 沒有執行

**解決：**
- 檢查 EventBridge Rule 是否 enabled
- 確認 Lambda Permission 正確設定
- 查看 EventBridge 的 CloudWatch Metrics

---

## 藍綠部署流程

1. **開發階段** → Push to GitHub
2. **GitHub Actions** → Build Image → Push to ECR → Upload SQL to S3
3. **EventBridge** → 偵測 ECR Push
4. **SQL Import Lambda** → 匯入 SQL 到流量為 0 的環境 (例如 Green)
5. **ECS Deploy Lambda** → 強制 ECS 重新部署 (Green 使用新 Image)
6. **手動驗證** → 使用 ModHeader 設定 `X-Target-Env: green` 測試
7. **切換流量** → 調整 `bluegreen.auto.tfvars` 的 `blue_weight` 和 `green_weight`
8. **Apply Terraform** → 完成藍綠切換

---

## 自動化程度

| 階段 | 自動化 | 手動操作 |
|------|--------|---------|
| Code Push | ✅ | - |
| Build & Push Image | ✅ | - |
| Export & Upload SQL | ✅ | - |
| Import SQL to Inactive Env | ✅ | - |
| Deploy New Image | ✅ | - |
| 測試新環境 | - | ✅ (使用 ModHeader) |
| 切換流量 | - | ✅ (調整 tfvars) |
| Rollback | - | ✅ (調整 tfvars) |
