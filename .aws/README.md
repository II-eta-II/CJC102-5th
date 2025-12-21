# 組員需要在自己帳號建立的 IAM 設定

## 概述
你的帳號需要建立一個 IAM Role，讓你可以操作 Route53 記錄。

## 需要建立的資源

### 1. IAM Role: `cjc102-29-route53`
### 2. IAM Policy: `route53-record-policy`

## 建立步驟

```powershell
# 1. 建立 Role (使用 trust-policy.json)
aws iam create-role --role-name cjc102-29-route53 --assume-role-policy-document file://.aws/teammate/trust-policy.json

# 2. 建立 Policy (使用 route53-record-policy.json)
aws iam create-policy --policy-name route53-record-policy --policy-document file://.aws/teammate/route53-record-policy.json

# 3. 附加 Policy 到 Role (替換 YOUR_ACCOUNT_ID)
aws iam attach-role-policy --role-name cjc102-29-route53 --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/route53-record-policy
```

## 驗證

```powershell
# 確認 Role 已建立
aws iam get-role --role-name cjc102-29-route53

# 確認 Policy 已附加
aws iam list-attached-role-policies --role-name cjc102-29-route53
```
