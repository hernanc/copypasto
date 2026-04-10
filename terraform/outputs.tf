output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.server.repository_url
}

output "users_table_name" {
  description = "DynamoDB users table name"
  value       = aws_dynamodb_table.users.name
}

output "clipboard_table_name" {
  description = "DynamoDB clipboard table name"
  value       = aws_dynamodb_table.clipboard.name
}

output "app_url" {
  description = "Application URL"
  value       = "https://api.${var.domain_name}"
}
