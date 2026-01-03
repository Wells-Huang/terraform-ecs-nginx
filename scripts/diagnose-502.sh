#!/bin/bash
# Diagnose 502 Bad Gateway - Check ECS Service Stability

set -e

REGION="${AWS_REGION:-ap-northeast-1}"

# Get Cluster Name
CLUSTER=$(terraform output -raw ecs_cluster_name)
NGINX_SERVICE=$(terraform output -raw nginx_service_name)
API_SERVICE=$(terraform output -raw api_service_name)

echo "=========================================="
echo "🔍 Diagnosing ECS Services in $CLUSTER"
echo "=========================================="

check_service() {
    SERVICE_NAME=$1
    echo "Checking Service: $SERVICE_NAME"
    
    # Get Service Status
    SERVICE_JSON=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE_NAME" --region "$REGION" --output json)
    STATUS=$(echo "$SERVICE_JSON" | jq -r '.services[0].statusbar')
    DESIRED=$(echo "$SERVICE_JSON" | jq -r '.services[0].desiredCount')
    RUNNING=$(echo "$SERVICE_JSON" | jq -r '.services[0].runningCount')
    PENDING=$(echo "$SERVICE_JSON" | jq -r '.services[0].pendingCount')
    
    echo "  Status: $STATUS (Desired: $DESIRED, Running: $RUNNING, Pending: $PENDING)"
    
    if [ "$RUNNING" -lt "$DESIRED" ]; then
        echo "  ⚠️  Service is not fully healthy."
    else
        echo "  ✅ Service seems healthy."
    fi

    # Check for recent stopped tasks to find crash reasons
    echo "  🔍 Checking recent stopped tasks..."
    STOPPED_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE_NAME" --desired-status STOPPED --max-items 5 --region "$REGION" --query "taskArns" --output text)
    
    if [ "$STOPPED_TASKS" != "None" ] && [ -n "$STOPPED_TASKS" ]; then
        aws ecs describe-tasks --cluster "$CLUSTER" --tasks $STOPPED_TASKS --region "$REGION" \
            | jq -r '.tasks[] | "  - Task: " + .taskArn + "\n    Reason: " + .stoppedReason + "\n    Container Exit: " + (.containers[0].exitCode|tostring) + " (" + .containers[0].reason + ")\n    StatusReason: " + .stoppedReason'
        
        # 嘗試抓取最後一個 Failed Task 的 Logs
        LAST_TASK_ARN=$(echo $STOPPED_TASKS | awk '{print $1}')
        TASK_ID=${LAST_TASK_ARN##*/}
        LOG_STREAM="nginx/nginx/$TASK_ID"
        LOG_GROUP="/ecs/${CLUSTER/-cluster/-nginx}" # 推測 Log Group 名稱: /ecs/ecs-nginx-nginx
        
        echo ""
        echo "  📜 Logs for last stopped task ($TASK_ID):"
        if aws logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name "$LOG_STREAM" --limit 20 --region "$REGION" > /dev/null 2>&1; then
            aws logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name "$LOG_STREAM" --limit 20 --region "$REGION" --query "events[*].message" --output text | sed 's/^/    /'
        else
            echo "    (No logs found or log group/stream mismatch)"
        fi
    else
        echo "  No recently stopped tasks found."
    fi
    echo ""
}

check_service "$NGINX_SERVICE"
check_service "$API_SERVICE"
