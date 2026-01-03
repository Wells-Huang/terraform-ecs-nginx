# EFS File System
resource "aws_efs_file_system" "nginx_config" {
  creation_token = "${var.project_name}-nginx-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${var.project_name}-nginx-efs"
  }
}

# EFS Mount Targets (in each AZ)
resource "aws_efs_mount_target" "nginx_config" {
  count           = length(var.availability_zones)
  file_system_id  = aws_efs_file_system.nginx_config.id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point for Nginx configuration
resource "aws_efs_access_point" "nginx_config" {
  file_system_id = aws_efs_file_system.nginx_config.id

  posix_user {
    gid = 0
    uid = 0
  }

  root_directory {
    path = "/nginx"
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.project_name}-nginx-config-ap"
  }
}
