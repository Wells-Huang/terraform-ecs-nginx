# Terraform ECS Nginx 部署指南

此專案使用 Terraform 部署 ECS 上的 Nginx 和私有 API 服務。
開發時使用 wsl環境

## 架構說明

- **VPC**: 包含公開和私有子網路
- **Nginx**: 部署在公開子網路，透過 ALB 對外提供服務
- **Private API**: 部署在私有子網路，僅能透過 Nginx 訪問
- **EFS**: 掛載 Nginx 設定檔，支援動態更新
- **Cloud Map**: 服務探索，讓 Nginx 透過 DNS 找到 API

## 前置需求

1. AWS CLI 已設定並具備適當權限
2. Terraform >= 1.0
3. (選用) amazon-efs-utils 用於本地掛載 EFS

## 部署步驟

### 1. 初始化 Terraform

```bash
cd terraform-ecs-nginx
terraform init
```

### 2. 檢視計畫

```bash
terraform plan
```

### 3. 套用變更

```bash
terraform apply
```

> ⚠️ **注意**: 此部署包含 NAT Gateway，會產生每小時費用（約 $0.045/小時）

### 4. 上傳 Nginx 設定檔到 EFS

部署完成後，需要將設定檔上傳到 EFS：

```bash
# 取得 EFS ID
EFS_ID=$(terraform output -raw efs_id)

# 執行初始化腳本（使用 ECS Task 寫入設定）
chmod +x scripts/init-efs-nfs.sh
./scripts/init-efs-nfs.sh
```

**說明**：此步驟至關重要。新建立的 EFS 是空的，如果不執行初始化，Nginx 將因找不到設定檔而無法啟動 (502 Bad Gateway)。

**Windows 使用者替代方案**：
- 使用 AWS CloudShell
- 或透過 EC2 跳板機掛載 EFS

### 5. 重啟 Nginx 服務以載入設定

```bash
# 強制更新服務以使用新設定
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw nginx_service_name) \
  --force-new-deployment
```

## 驗證

### 測試公開存取

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
curl http://$ALB_DNS
```

預期回應：`Nginx is running!`

### 測試反向代理

驗證 Nginx 是否能成功將請求轉發給 Private Subnet 內的 API 服務 (whoami)。

```bash
curl http://$ALB_DNS/api
```

**預期回應**：
若成功，您將看到來自 API 容器的內部資訊：

```text
Hostname: ip-10-0-xx-xx.ap-northeast-1.compute.internal
IP: 127.0.0.1
IP: 10.0.xx.xx
RemoteAddr: 10.0.xx.xx:xxxxx
GET /api HTTP/1.1
Host: ecs-nginx-alb-xxxx.ap-northeast-1.elb.amazonaws.com
...
```

### 檢查日誌

```bash
aws logs tail /ecs/ecs-nginx-nginx --follow
aws logs tail /ecs/ecs-nginx-api --follow
```

## 清理資源

```bash
terraform destroy
```

## 費用估算

主要費用來源：
- **NAT Gateway**: ~$32/月
- **ECS Fargate**: 依 vCPU 和記憶體使用量計費
- **ALB**: ~$16/月
- **EFS**: 依儲存量計費（設定檔很小，幾乎免費）
- **Data Transfer**: 依流量計費

## 架構圖

```
Internet
   │
   ▼
  ALB (Public)
   │
   ▼
Nginx (Public Subnet) ─── EFS (Config)
   │
   │ (Service Discovery: api.local)
   │
   ▼
Private API (Private Subnet)
   │
   ▼
NAT Gateway → Internet (for image pull)
```

## 技術實作細節

### 1. Task 調度方式 (Task Scheduling)

本專案使用 **AWS Fargate** 作為運算引擎，這是一種 Serverless 的容器調度方式。如果不使用 Fargate，則需要自行管理 EC2 Instance。

- **Launch Type**: `FARGATE`
- **Network Mode**: `awsvpc` (每個 Task 都有獨立的 ENI 和 IP)
- **子網路配置**:
  - **Nginx Service**: 部署於 **Public Subnet**，開啟 `assign_public_ip = true`，以便接收來自 ALB 的流量（並非直接對外，而是透過 Security Group 限制僅允許 ALB 訪問）。
  - **API Service**: 部署於 **Private Subnet**，關閉 `assign_public_ip`，確保僅能透過內網（VPC）訪問。

### 2. Nginx 配置與 Volume 掛載

為了讓 Nginx 設定檔具備彈性且不需重新打包 Image，我們使用了 **AWS EFS (Elastic File System)** 進行掛載。

- **Volume 定義**: 在 `aws_ecs_task_definition` 中定義了一個名為 `nginx-config` 的 Volume，對應到 Terraform 建立的 EFS File System。
- **Container 掛載**:
  ```hcl
  mountPoints = [
    {
      sourceVolume  = "nginx-config"
      containerPath = "/etc/nginx/conf.d"
      readOnly      = false
    }
  ]
  ```
- **運作原理**:
  1. 容器啟動時，EFS 會被掛載到 `/etc/nginx/conf.d`。
  2. Nginx 主程序會讀取該目錄下的 `*.conf` 檔案。
  3. 由於原生的 Docker Image 該目錄通常包含預設設定，但**掛載行為會覆蓋原本目錄內容**，導致目錄變為空。
  4. 這就是為什麼必須執行 `scripts/init-efs-nfs.sh` 的原因：我們必須手動將 `default.conf` 寫入到這個掛載的 Volume 中，Nginx 才能正常運作。

