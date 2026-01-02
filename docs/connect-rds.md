# 連線 RDS 資料庫

透過 ECS Exec 進入 WordPress 容器連線 RDS。

## 步驟

### 1. 取得 Task ID

```bash
aws ecs list-tasks --cluster usa-ops-wordpress-cluster --service-name wordpress-service-blue --region ap-northeast-1
```

### 2. 進入容器

```bash
aws ecs execute-command \
  --cluster usa-ops-wordpress-cluster \
  --task <task-id> \
  --container wordpress \
  --interactive \
  --command "/bin/sh" \
  --region ap-northeast-1
```

### 3. 安裝 MySQL Client

```bash
apk update && apk add mysql-client
```

### 4. 連線資料庫

```bash
mysql -h $WORDPRESS_DB_HOST -u $WORDPRESS_DB_USER -p"$WORDPRESS_DB_PASSWORD" --skip-ssl
```

## 常用 SQL 指令

```sql
-- 查看資料庫
SHOW DATABASES;

-- 使用 WordPress 資料庫
USE wordpress;

-- 查看資料表
SHOW TABLES;

-- 查看使用者
SELECT user_login, user_email FROM wp_users;
```
