# Nginx Task Definition - 階段二（含 EFS Volume 掛載）
resource "aws_ecs_task_definition" "nginx" {
  family                   = "${var.project_name}-nginx"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # EFS Volume 定義
  volume {
    name = "nginx-config"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.nginx_config.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.nginx_config.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = var.nginx_image
      essential = true

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      # 掛載 EFS Volume 到容器
      mountPoints = [
        {
          sourceVolume  = "nginx-config"
          containerPath = "/etc/nginx/conf.d"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_nginx.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }

      environment = [
        {
          name  = "NGINX_PORT"
          value = "80"
        }
      ]
    }
  ])

  tags = {
    Name = "${var.project_name}-nginx-task"
  }
}

# Nginx ECS Service
resource "aws_ecs_service" "nginx" {
  name            = "${var.project_name}-nginx-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.nginx.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.nginx_task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nginx.arn
    container_name   = "nginx"
    container_port   = 80
  }

  # 啟用 ECS Exec 以便除錯
  enable_execute_command = true

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_task_execution,
    aws_efs_mount_target.nginx_config
  ]

  tags = {
    Name = "${var.project_name}-nginx-service"
  }
}
