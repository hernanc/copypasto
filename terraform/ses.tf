resource "aws_ses_email_identity" "notification" {
  email = var.notification_email
}
