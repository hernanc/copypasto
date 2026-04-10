resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/copypasto/${var.environment}/jwt-secret"
  description = "JWT signing secret for access tokens"
  type        = "SecureString"
  value       = "CHANGE_ME_BEFORE_DEPLOY"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "copypasto-${var.environment}-jwt-secret"
  }
}

resource "aws_ssm_parameter" "jwt_refresh_secret" {
  name        = "/copypasto/${var.environment}/jwt-refresh-secret"
  description = "JWT signing secret for refresh tokens"
  type        = "SecureString"
  value       = "CHANGE_ME_BEFORE_DEPLOY"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "copypasto-${var.environment}-jwt-refresh-secret"
  }
}
