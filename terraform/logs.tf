resource "aws_cloudwatch_log_group" "server" {
  name              = "/ecs/copypasto-${var.environment}-server"
  retention_in_days = 30

  tags = {
    Name = "copypasto-${var.environment}-server-logs"
  }
}
