# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# =============================================================================
# Blue Environment Target Group
# =============================================================================

# Target Group for ECS Service - Blue
resource "aws_lb_target_group" "ecs" {
  name_prefix = "blue-"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 20
    interval            = 60
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
  }

  deregistration_delay = 30





  tags = {
    Name        = "${var.project_name}-ecs-target-group-blue"
    Environment = "blue"
  }
}

# ALB Listener - HTTP (with weighted routing for Blue-Green, used by CloudFront)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ALB Listener - HTTPS (with weighted routing for Blue-Green)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.main.certificate_arn

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.ecs.arn
        weight = var.blue_weight
      }
      target_group {
        arn    = aws_lb_target_group.ecs_green.arn
        weight = var.green_weight
      }
    }
  }

  # Ignore manual weight adjustments made via AWS Console or CLI
}

# =============================================================================
# Header-based routing for direct Blue/Green access
# Use browser extension (ModHeader) to set X-Target-Env header
# =============================================================================

# Route to Blue when X-Target-Env: blue
resource "aws_lb_listener_rule" "blue_header" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  condition {
    http_header {
      http_header_name = "X-Target-Env"
      values           = ["blue"]
    }
  }
}

# Route to Green when X-Target-Env: green
resource "aws_lb_listener_rule" "green_header" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_green.arn
  }

  condition {
    http_header {
      http_header_name = "X-Target-Env"
      values           = ["green"]
    }
  }
}

# Temporarily disabled - Blue subdomain listener rule
# resource "aws_lb_listener_rule" "blue_subdomain" {
#   listener_arn = aws_lb_listener.https.arn
#   priority     = 10
#
#   action {
#     type = "forward"
#     forward {
#       target_group {
#         arn    = aws_lb_target_group.ecs.arn
#         weight = 100
#       }
#       stickiness {
#         enabled  = true
#         duration = 86400
#       }
#     }
#   }
#
#   condition {
#     host_header {
#       values = ["blue.${var.subdomain}.${var.route53_domain_name}"]
#     }
#   }
# }

# Temporarily disabled - Green subdomain listener rule
# resource "aws_lb_listener_rule" "green_subdomain" {
#   listener_arn = aws_lb_listener.https.arn
#   priority     = 20
#
#   action {
#     type = "forward"
#     forward {
#       target_group {
#         arn    = aws_lb_target_group.ecs_green.arn
#         weight = 100
#       }
#       stickiness {
#         enabled  = true
#         duration = 86400
#       }
#     }
#   }
#
#   condition {
#     host_header {
#       values = ["green.${var.subdomain}.${var.route53_domain_name}"]
#     }
#   }
# }

# =============================================================================
# Green Environment Target Group (Blue-Green Deployment)
# =============================================================================

resource "aws_lb_target_group" "ecs_green" {
  name_prefix = "green-"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 20
    interval            = 60
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
  }

  deregistration_delay = 30

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-ecs-target-group-green"
    Environment = "green"
  }
}

# =============================================================================
# CloudWatch Monitoring - HTTP Error Alarms
# =============================================================================

# Extract ALB ARN suffix for CloudWatch metrics
locals {
  alb_arn_suffix = regex("app/.+$", aws_lb.main.arn)
}

# CloudWatch Alarm - ALB 4XX Errors (Client Errors)
resource "aws_cloudwatch_metric_alarm" "alb_4xx_errors" {
  alarm_name          = "${var.project_name}-alb-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 50 # Alert if > 50 4xx errors in 5 minutes
  alarm_description   = "ALB 4XX errors exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
  }

  tags = {
    Name = "${var.project_name}-alb-4xx-alarm"
  }
}

# CloudWatch Alarm - ALB 5XX Errors (Server Errors)
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 10 # Alert if > 10 5xx errors in 5 minutes
  alarm_description   = "ALB 5XX errors exceeded threshold - potential server issues"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
  }

  tags = {
    Name = "${var.project_name}-alb-5xx-alarm"
  }
}

# CloudWatch Alarm - ALB ELB 5XX (Load Balancer Errors)
resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx_errors" {
  alarm_name          = "${var.project_name}-alb-elb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5 # Alert if > 5 ELB 5xx errors
  alarm_description   = "ELB 5XX errors - Load Balancer connectivity issues"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
  }

  tags = {
    Name = "${var.project_name}-alb-elb-5xx-alarm"
  }
}

# CloudWatch Dashboard for HTTP Errors Overview
resource "aws_cloudwatch_dashboard" "http_errors" {
  dashboard_name = "${var.project_name}-http-errors"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ALB HTTP 4XX Errors"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", local.alb_arn_suffix, { stat = "Sum", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ALB HTTP 5XX Errors"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_arn_suffix, { stat = "Sum", period = 60 }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb_arn_suffix, { stat = "Sum", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Request Count"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_arn_suffix, { stat = "Sum", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Target Response Time"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix, { stat = "Average", period = 60 }]
          ]
        }
      }
    ]
  })
}

