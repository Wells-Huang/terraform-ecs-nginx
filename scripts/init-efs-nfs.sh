#!/bin/bash

# 使用 ECS Task 來初始化 EFS 內容
# 適用於無法直接透過 NFS 掛載 EFS 的環境 (如 WSL)

set -e

# 確認是否安裝 aws cli 與 jq
if ! command -v aws &> /dev/null; then
    echo "❌ 請先安裝/設定 AWS CLI"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ 請先安裝 jq (sudo apt-get install jq)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/nginx-config/default.conf"

echo "=========================================="
echo "🚀 使用 ECS Task 初始化 EFS 設定檔"
echo "=========================================="

# 1. 取得 Terraform Output
echo "1️⃣ 讀取 Terraform 輸出..."
cd "$PROJECT_DIR"

CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
TASK_DEF_ARN=$(terraform output -raw nginx_task_definition_arn)
SUBNET_IDS_JSON=$(terraform output -json public_subnet_ids)
SUBNET_ID=$(echo $SUBNET_IDS_JSON | jq -r '.[0]') # 取第一個 Public Subnet
SEC_GROUP_ID=$(terraform output -raw nginx_security_group_id)

echo "  Cluster: $CLUSTER_NAME"
echo "  Task Def: $TASK_DEF_ARN"
echo "  Subnet: $SUBNET_ID"
echo "  Security Group: $SEC_GROUP_ID"

if [ -z "$CLUSTER_NAME" ] || [ -z "$TASK_DEF_ARN" ]; then
    echo "❌ 無法取得必要的 Terraform Output，請確認是否已 Apply"
    exit 1
fi

# 2. 準備設定檔內容 (Base64 Encode)
echo "2️⃣ 讀取並編碼設定檔..."
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 找不到 $CONFIG_FILE"
    exit 1
fi

# 讀取檔案內容並移除換行符號，避免 JSON 格式錯誤
CONFIG_CONTENT=$(cat "$CONFIG_FILE")
# 使用 Base64 編碼以安全傳輸
CONFIG_B64=$(echo "$CONFIG_CONTENT" | base64 -w 0)

# 3. 建立 ECS Run Task 指令
echo "3️⃣ 啟動 ECS Task 更新 EFS..."

# 我們使用 sh -c 來寫入檔案
# 注意：這裡假設容器內有 base64 指令 (nginx image 通常基於 debian/alpine 都有)
CMD="echo '$CONFIG_B64' | base64 -d > /etc/nginx/conf.d/default.conf && echo '✅ Config updated' && cat /etc/nginx/conf.d/default.conf"

# 構建 Network Configuration
NET_CONFIG="{\"awsvpcConfiguration\":{\"subnets\":[\"$SUBNET_ID\"],\"securityGroups\":[\"$SEC_GROUP_ID\"],\"assignPublicIp\":\"ENABLED\"}}"

# 構建 Container Overrides
OVERRIDES="{\"containerOverrides\":[{\"name\":\"nginx\",\"command\":[\"sh\",\"-c\",\"$CMD\"]}]}"

# 執行 Task
TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --launch-type FARGATE \
    --network-configuration "$NET_CONFIG" \
    --overrides "$OVERRIDES" \
    --query "tasks[0].taskArn" \
    --output text)

if [ "$TASK_ARN" == "None" ] || [ -z "$TASK_ARN" ]; then
    echo "❌ 啟動 Task 失敗"
    exit 1
fi

echo "  Task 已啟動: $TASK_ARN"

# 4. 等待 Task 完成
echo "4️⃣ 等待 Task 完成..."
aws ecs wait tasks-stopped --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN"

echo "✅ Task 已完成！"

# 檢視 Log (Optional)
# LOG_GROUP="/ecs/project-nginx" # 需要從變數確認
# echo "您可以查看 CloudWatch Logs 確認執行結果"
