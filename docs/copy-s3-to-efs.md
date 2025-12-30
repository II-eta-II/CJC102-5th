# 複製 S3 資料到 EFS

CloudShell 無法直接存取 EFS，需透過 EC2 執行。

## 方法：使用 EC2 Bastion Host

### 1. SSH 進入 EC2

```bash
ssh -i your-key.pem ec2-user@<EC2-IP>
```

### 2. 安裝必要工具

```bash
sudo yum install -y amazon-efs-utils
```

### 3. 掛載 EFS

```bash
# Blue 環境
sudo mkdir -p /mnt/efs
sudo mount -t efs fs-0d7cfb7adf0c50a68:/ /mnt/efs

# 或 Green 環境
# sudo mount -t efs <green-efs-id>:/ /mnt/efs
```

### 4. 從 S3 複製到 EFS

```bash
# 複製整個資料夾
aws s3 cp s3://your-bucket/wp-content/ /mnt/efs/wp-content/ --recursive

# 複製 wp-admin
aws s3 cp s3://your-bucket/wp-admin/ /mnt/efs/wp-admin/ --recursive

# 複製 wp-includes
aws s3 cp s3://your-bucket/wp-includes/ /mnt/efs/wp-includes/ --recursive
```

### 5. 設定權限

```bash
# WordPress 需要 www-data (UID 33) 權限
sudo chown -R 33:33 /mnt/efs/
sudo chmod -R 755 /mnt/efs/
```

---

## 替代方案：AWS DataSync

如果資料量大，可使用 AWS DataSync 服務自動同步 S3 到 EFS。
