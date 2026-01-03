# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_nginx" {
  name              = "/ecs/${var.project_name}-nginx"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-nginx-logs"
  }
}

resource "aws_cloudwatch_log_group" "ecs_api" {
  name              = "/ecs/${var.project_name}-api"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-api-logs"
  }
}
