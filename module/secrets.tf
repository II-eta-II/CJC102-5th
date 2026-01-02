# =============================================================================
# AWS Secrets Manager for Sensitive Data
# =============================================================================

# Combined WordPress and Database Credentials
resource "aws_secretsmanager_secret" "wordpress_env" {
  name                    = "${var.project_name}-wordpress-env"
  description             = "WordPress and Database credentials (username and password)"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-wordpress-env"
  }
}

resource "aws_secretsmanager_secret_version" "wordpress_env" {
  secret_id = aws_secretsmanager_secret.wordpress_env.id
  secret_string = jsonencode({
    wordpress_username = var.wp_username
    wordpress_password = var.wp_password
    db_username        = var.db_username
    db_password        = var.db_password
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "wordpress_env_secret_arn" {
  description = "ARN of WordPress environment secret (contains all credentials)"
  value       = aws_secretsmanager_secret.wordpress_env.arn
  sensitive   = true
}

output "wordpress_env_secret_name" {
  description = "Name of WordPress environment secret"
  value       = aws_secretsmanager_secret.wordpress_env.name
}

