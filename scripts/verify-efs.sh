#!/bin/bash
# Verify EFS Content - Check if default.conf exists

set -e

# Get Variables
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
TASK_DEF_ARN=$(terraform output -raw nginx_task_definition_arn)
SUBNET_IDS_JSON=$(terraform output -json public_subnet_ids)
SUBNET_ID=$(echo $SUBNET_IDS_JSON | jq -r '.[0]')
SEC_GROUP_ID=$(terraform output -raw nginx_security_group_id)

echo "=========================================="
echo "📂 Verifying EFS Content in $CLUSTER_NAME"
echo "=========================================="

CMD="ls -la /etc/nginx/conf.d/ && echo '--- Content of default.conf ---' && cat /etc/nginx/conf.d/default.conf || echo '❌ File not found'"

NET_CONFIG="{\"awsvpcConfiguration\":{\"subnets\":[\"$SUBNET_ID\"],\"securityGroups\":[\"$SEC_GROUP_ID\"],\"assignPublicIp\":\"ENABLED\"}}"
OVERRIDES="{\"containerOverrides\":[{\"name\":\"nginx\",\"command\":[\"sh\",\"-c\",\"$CMD\"]}]}"

echo "🚀 Launching Verification Task..."
TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --launch-type FARGATE \
    --network-configuration "$NET_CONFIG" \
    --overrides "$OVERRIDES" \
    --query "tasks[0].taskArn" \
    --output text)

echo "  Task ARN: $TASK_ARN"
echo "  Waiting for task to complete..."
aws ecs wait tasks-stopped --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN"

echo "📝 Task Output (Logs):"
# Get Log Stream Name
TASK_ID=$(basename "$TASK_ARN")
LOG_STREAM="nginx/nginx/$TASK_ID"

# Fetch logs
aws logs get-log-events \
    --log-group-name "/ecs/ecs-nginx-nginx" \
    --log-stream-name "$LOG_STREAM" \
    --output text \
    --query "events[*].message"

echo ""
echo "=========================================="
