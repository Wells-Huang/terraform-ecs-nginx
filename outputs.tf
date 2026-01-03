# ALB DNS Name
output "alb_dns_name" {
  description = "ALB 的 DNS 名稱"
  value       = aws_lb.main.dns_name
}

# ECS Cluster Name
output "ecs_cluster_name" {
  description = "ECS Cluster 名稱"
  value       = aws_ecs_cluster.main.name
}

# EFS File System ID
output "efs_id" {
  description = "EFS 檔案系統 ID"
  value       = aws_efs_file_system.nginx_config.id
}

# VPC ID
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# Public Subnet IDs
output "public_subnet_ids" {
  description = "公開子網路 ID 列表"
  value       = aws_subnet.public[*].id
}

# Private Subnet IDs
output "private_subnet_ids" {
  description = "私有子網路 ID 列表"
  value       = aws_subnet.private[*].id
}

# Service Discovery Namespace
output "service_discovery_namespace" {
  description = "服務探索命名空間"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

# Nginx Service Name
output "nginx_service_name" {
  description = "Nginx 服務名稱"
  value       = aws_ecs_service.nginx.name
}

# API Service Name
output "api_service_name" {
  description = "API 服務名稱"
  value       = aws_ecs_service.api.name
}

# Nginx Task Definition ARN
output "nginx_task_definition_arn" {
  description = "Nginx Task Definition ARN"
  value       = aws_ecs_task_definition.nginx.arn
}

# Nginx Security Group ID
output "nginx_security_group_id" {
  description = "Nginx Security Group ID"
  value       = aws_security_group.nginx_task.id
}
