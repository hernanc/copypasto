resource "aws_ecs_cluster" "main" {
  name = "copypasto-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "copypasto-${var.environment}-cluster"
  }
}

resource "aws_ecs_task_definition" "server" {
  family                   = "copypasto-${var.environment}-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "server"
      image     = "${aws_ecr_repository.server.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "DYNAMODB_USERS_TABLE", value = aws_dynamodb_table.users.name },
        { name = "DYNAMODB_CLIPBOARD_TABLE", value = aws_dynamodb_table.clipboard.name },
        { name = "DYNAMODB_WAITLIST_TABLE", value = aws_dynamodb_table.waitlist.name },
        { name = "NOTIFICATION_EMAIL", value = var.notification_email },
      ]

      secrets = [
        {
          name      = "JWT_SECRET"
          valueFrom = aws_ssm_parameter.jwt_secret.arn
        },
        {
          name      = "JWT_REFRESH_SECRET"
          valueFrom = aws_ssm_parameter.jwt_refresh_secret.arn
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.server.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "copypasto-${var.environment}-server-task"
  }
}

resource "aws_ecs_service" "server" {
  name            = "copypasto-${var.environment}-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.server.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.server.arn
    container_name   = "server"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.https]

  tags = {
    Name = "copypasto-${var.environment}-server-service"
  }
}
