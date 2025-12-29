# 上傳 WordPress 映像檔到 ECR

在 AWS CloudShell 中執行以下指令：

```bash
# 1. 拉取官方映像
docker pull wordpress:latest

# 2. 標記映像
docker tag wordpress:latest 459063348692.dkr.ecr.ap-northeast-1.amazonaws.com/usa-wordpress:official

# 3. 登入 ECR
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin 459063348692.dkr.ecr.ap-northeast-1.amazonaws.com

# 4. 推送到 ECR
docker push 459063348692.dkr.ecr.ap-northeast-1.amazonaws.com/usa-wordpress:official
```
