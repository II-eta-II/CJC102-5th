# Route53 跨帳戶授權設定指南

此目錄包含跨帳戶存取 Route53 Hosted Zone 的相關設定檔案。

## 授權資訊

| 項目 | 值 |
|------|-----|
| Role ARN | `arn:aws:iam::459063348692:role/cjc102-route53-record-manager` |
| Hosted Zone ID | `Z01780191CLMBHU6Y6729` |
| Domain | `cjc102.site` |
| External ID | `cjc102-route53-record-manager` |

---

## 設定步驟

### 1. 設定 AWS CLI Profile

將以下內容加入 `~/.aws/config`：

```ini
[profile cjc102.site]
role_arn = arn:aws:iam::459063348692:role/cjc102-route53-record-manager
source_profile = default
external_id = cjc102-route53-record-manager
region = ap-northeast-1
```

> **注意**：`source_profile` 應設為您的 SSO profile 名稱（例如 `default`）

### 2. 測試權限

執行以下命令測試是否能成功 assume role：

```powershell
aws sts assume-role `
  --role-arn arn:aws:iam::459063348692:role/cjc102-route53-record-manager `
  --role-session-name cjc102-29 `
  --external-id cjc102-route53-record-manager
```

---

## 常用命令

### 列出 DNS 記錄

```powershell
aws route53 list-resource-record-sets `
  --hosted-zone-id Z01780191CLMBHU6Y6729 `
  --profile cjc102.site
```

### 新增/修改 DNS 記錄

使用 JSON 檔案來定義變更：

```powershell
aws route53 change-resource-record-sets `
  --hosted-zone-id Z01780191CLMBHU6Y6729 `
  --change-batch file://change_A_record.json `
  --profile cjc102.site
```

---

## JSON 範例檔案

此目錄包含以下範例檔案：

| 檔案 | 說明 |
|------|------|
| `change_A_record.json` | A 記錄範例 |
| `change_CNAME_record.json` | CNAME 記錄範例 |
| `change_TXT_record.json` | TXT 記錄範例 |

### A 記錄範例

```json
{
    "Comment": "Create or update A record",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "test.cjc102.site.",
                "Type": "A",
                "TTL": 300,
                "ResourceRecords": [
                    { "Value": "1.2.3.4" }
                ]
            }
        }
    ]
}
```

---

## 權限說明

此跨帳戶 Role 具有以下權限：

- `route53:ListResourceRecordSets` - 列出 DNS 記錄
- `route53:ChangeResourceRecordSets` - 新增/修改/刪除 DNS 記錄
- `route53:GetChange` - 查詢變更狀態
- `route53:GetHostedZone` - 查詢 Hosted Zone 資訊

詳細權限請參考 `permission_policy.json`。
