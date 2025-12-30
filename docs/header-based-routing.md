# 精準連線藍/綠環境

透過 HTTP Header 設定，可以精準指定連線到 Blue 或 Green 環境，不受 WordPress 頁面跳轉影響。

## 原理

ALB Listener Rule 會優先檢查 `X-Target-Env` Header：
- `X-Target-Env: blue` → 所有請求轉發到 Blue Target Group
- `X-Target-Env: green` → 所有請求轉發到 Green Target Group
- 無 Header → 根據 ALB 權重分配

## 設定步驟

### 1. 安裝瀏覽器擴充

| 瀏覽器 | 擴充名稱 | 連結 |
|--------|----------|------|
| Chrome/Edge | ModHeader | [Chrome Web Store](https://chrome.google.com/webstore/detail/modheader/idgpnmonknjnojddfkpgkljpfnnfcklj) |
| Firefox | ModHeader | Firefox Add-ons 搜尋 "ModHeader" |

### 2. 新增 Request Header

1. 點擊 ModHeader 圖示
2. 點擊 `+` 新增 Header
3. 設定：
   - **Name**: `X-Target-Env`
   - **Value**: `blue` 或 `green`
4. 確認已勾選啟用

### 3. 測試連線

開啟網站，無論 WordPress 如何跳轉，都會保持在指定環境。

## 使用情境

| 情境 | Header 設定 |
|------|-------------|
| 測試 Blue 環境新功能 | `X-Target-Env: blue` |
| 測試 Green 環境新功能 | `X-Target-Env: green` |
| 一般瀏覽（依權重） | 移除 Header |

## 注意事項

- Header 會套用到**所有**網站請求
- 測試完畢後記得**停用**或**刪除** Header
- 可在 ModHeader 設定只對特定網域生效
