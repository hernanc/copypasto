variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "copypasto.com"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "ecs_cpu" {
  description = "ECS task CPU units"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "ECS task memory in MiB"
  type        = number
  default     = 512
}

variable "container_port" {
  description = "Container port for the server"
  type        = number
  default     = 3000
}
