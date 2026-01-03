variable "aws_region" {
  description = "AWS 區域"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "環境名稱"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "專案名稱"
  type        = string
  default     = "ecs-nginx"
}

variable "vpc_cidr" {
  description = "VPC CIDR 區塊"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "可用區域列表"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "nginx_image" {
  description = "Nginx Docker 映像"
  type        = string
  default     = "nginx:latest"
}

variable "api_image" {
  description = "API Docker 映像"
  type        = string
  default     = "traefik/whoami:latest"
}
