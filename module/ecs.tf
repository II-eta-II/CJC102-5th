# =============================================================================
# Blue Environment ECS
# =============================================================================

# CloudWatch Log Group - Blue
resource "aws_cloudwatch_log_group" "blue_ecs" {
  name              = "/ecs/${var.project_name}-${var.ecs_service_name}-blue"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-ecs-logs-blue"
    Environment = "blue"
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-task-execution-role"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Policy for Secrets Manager access (required for secrets in task definition)
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-ecs-task-execution-secrets-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.wordpress_env.arn
      }
    ]
  })
}

# IAM Role for ECS Task (application permissions)

resource "aws_iam_role" "blue_ecs_task" {
  name = "${var.project_name}-ecs-task-role-blue"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-task-role-blue"
  }
}

# Policy for ECS Task to access EFS
resource "aws_iam_role_policy" "blue_ecs_task_efs" {
  name = "${var.project_name}-ecs-task-efs-policy-blue"
  role = aws_iam_role.blue_ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess",
          "elasticfilesystem:DescribeFileSystems"
        ]
        Resource = [
          aws_efs_file_system.main.arn,
          aws_efs_access_point.ecs.arn
        ]
      }
    ]
  })
}

# Policy for ECS Task to access S3 Media Offload bucket
resource "aws_iam_role_policy" "blue_ecs_task_s3_media" {
  name = "${var.project_name}-ecs-task-s3-media-policy-blue"
  role = aws_iam_role.blue_ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Object-level operations
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectAcl",
          "s3:GetObjectAcl"
        ]
        Resource = "${aws_s3_bucket.media_offload.arn}/*"
      },
      {
        # Bucket-level operations (scoped to specific bucket only)
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.media_offload.arn
      },
      {
        # Required by WordPress plugins to list buckets in UI
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }
    ]
  })
}

# Policy for ECS Exec (SSM Session Manager)
resource "aws_iam_role_policy" "blue_ecs_task_exec_ssm" {
  name = "${var.project_name}-ecs-task-exec-ssm-policy-blue"
  role = aws_iam_role.blue_ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Security Group for ECS Tasks - Blue
resource "aws_security_group" "blue_ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-blue-sg"
  description = "Security group for Blue ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-ecs-tasks-blue-sg"
    Environment = "blue"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.ecs_cluster_name}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-ecs-cluster"
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "blue" {
  family                   = "${var.project_name}-${var.ecs_service_name}-blue"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.blue_ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "${aws_ecr_repository.wordpress.repository_url}:${var.blue_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = aws_db_instance.main.address
        },
        {
          name  = "WORDPRESS_DB_NAME"
          value = var.db_name
        },
        {
          name  = "WORDPRESS_CONFIG_EXTRA"
          value = <<-EOT
            // 修正反向代理下的 HTTPS 偵測
            if (isset($$_SERVER['HTTP_X_FORWARDED_PROTO']) && $$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
              $$_SERVER['HTTPS'] = 'on';
              $$_SERVER['SERVER_PORT'] = 443;
            }
            
            // 信任反向代理的 IP
            if (isset($$_SERVER['HTTP_X_FORWARDED_FOR'])) {
              $$_SERVER['REMOTE_ADDR'] = explode(',', $$_SERVER['HTTP_X_FORWARDED_FOR'])[0];
            }
          EOT
        }
      ]

      secrets = [
        {
          name      = "WORDPRESS_DB_USER"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:db_username::"
        },
        {
          name      = "WORDPRESS_DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:db_password::"
        },
        {
          name      = "WORDPRESS_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:wordpress_username::"
        },
        {
          name      = "WORDPRESS_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:wordpress_password::"
        },
        {
          name      = "CWA_API_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:cwa_api_token::"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      mountPoints = [
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.blue_ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wordpress"
        }
      }
    }
  ])

  volume {
    name = "efs-wp-admin"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.wp_admin.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "efs-wp-content"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.ecs.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "efs-wp-includes"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.wp_includes.id
        iam             = "ENABLED"
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-task-definition-blue"
    Environment = "blue"
  }

}

# ECS Service - Blue
resource "aws_ecs_service" "blue" {
  name                   = "${var.ecs_service_name}-blue"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.blue.arn
  desired_count          = var.blue_ecs_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  # 蝯虫?隞餃? 120 蝘???蝺抵???
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.blue_ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "wordpress"
    container_port   = var.container_port
  }

  tags = {
    Name        = "${var.project_name}-ecs-service-blue"
    Environment = "blue"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution,
    aws_efs_mount_target.main,
    aws_lb_listener.http,
    aws_lb_listener.https
  ]
}

# Application Auto Scaling Target
resource "aws_appautoscaling_target" "blue_ecs" {
  max_capacity       = var.blue_ecs_max_capacity
  min_capacity       = var.blue_ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.blue.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy - CPU Based
resource "aws_appautoscaling_policy" "blue_ecs_cpu" {
  name               = "${var.project_name}-ecs-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.blue_ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.blue_ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.blue_ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 30.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 5
  }
}

# Auto Scaling Policy - Memory Based
resource "aws_appautoscaling_policy" "blue_ecs_memory" {
  name               = "${var.project_name}-ecs-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.blue_ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.blue_ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.blue_ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 30.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 5
  }
}

# =============================================================================
# Green Environment ECS (Blue-Green Deployment)
# =============================================================================

resource "aws_cloudwatch_log_group" "ecs_green" {
  name              = "/ecs/${var.project_name}-${var.ecs_service_name}-green"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-ecs-logs-green"
    Environment = "green"
  }
}

# =============================================================================
# Green Environment - Security Groups
# =============================================================================

resource "aws_security_group" "ecs_tasks_green" {
  name        = "${var.project_name}-ecs-tasks-green-sg"
  description = "Security group for Green ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-ecs-tasks-green-sg"
    Environment = "green"
  }
}

resource "aws_iam_role" "ecs_task_green" {
  name = "${var.project_name}-ecs-task-role-green"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-role-green"
    Environment = "green"
  }
}

resource "aws_iam_role_policy" "ecs_task_efs_green" {
  name = "${var.project_name}-ecs-task-efs-policy-green"
  role = aws_iam_role.ecs_task_green.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess",
        "elasticfilesystem:DescribeFileSystems"
      ]
      Resource = [aws_efs_file_system.green.arn, aws_efs_access_point.green.arn]
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_s3_media_green" {
  name = "${var.project_name}-ecs-task-s3-media-policy-green"
  role = aws_iam_role.ecs_task_green.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Object-level operations
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectAcl",
          "s3:GetObjectAcl"
        ]
        Resource = "${aws_s3_bucket.media_offload.arn}/*"
      },
      {
        # Bucket-level operations (scoped to specific bucket only)
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.media_offload.arn
      },
      {
        # Required by WordPress plugins to list buckets in UI
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }
    ]
  })
}

resource "aws_ecs_task_definition" "green" {
  family                   = "${var.project_name}-${var.ecs_service_name}-green"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_green.arn

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "${aws_ecr_repository.wordpress.repository_url}:${var.green_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = aws_db_instance.green.address
        },
        {
          name  = "WORDPRESS_DB_NAME"
          value = var.db_name
        },
        {
          name  = "WORDPRESS_CONFIG_EXTRA"
          value = <<-EOT
            // 修正反向代理下的 HTTPS 偵測
            if (isset($$_SERVER['HTTP_X_FORWARDED_PROTO']) && $$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
              $$_SERVER['HTTPS'] = 'on';
              $$_SERVER['SERVER_PORT'] = 443;
            }
            
            // 信任反向代理的 IP
            if (isset($$_SERVER['HTTP_X_FORWARDED_FOR'])) {
              $$_SERVER['REMOTE_ADDR'] = explode(',', $$_SERVER['HTTP_X_FORWARDED_FOR'])[0];
            }
          EOT
        }
      ]

      secrets = [
        {
          name      = "WORDPRESS_DB_USER"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:db_username::"
        },
        {
          name      = "WORDPRESS_DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:db_password::"
        },
        {
          name      = "WORDPRESS_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:wordpress_username::"
        },
        {
          name      = "WORDPRESS_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:wordpress_password::"
        },
        {
          name      = "CWA_API_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.wordpress_env.arn}:cwa_api_token::"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      mountPoints = [
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_green.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wordpress"
        }
      }
    }
  ])

  volume {
    name = "efs-wp-admin-green"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.green.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.wp_admin_green.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "efs-wp-content-green"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.green.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.green.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "efs-wp-includes-green"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.green.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.wp_includes_green.id
        iam             = "ENABLED"
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-task-definition-green"
    Environment = "green"
  }

}

resource "aws_ecs_service" "green" {
  name                   = "${var.ecs_service_name}-green"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.green.arn
  desired_count          = var.green_ecs_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks_green.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_green.arn
    container_name   = "wordpress"
    container_port   = var.container_port
  }

  tags = {
    Name        = "${var.project_name}-ecs-service-green"
    Environment = "green"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution,
    aws_efs_mount_target.green,
    aws_lb_listener.http,
    aws_lb_listener.https
  ]
}

resource "aws_appautoscaling_target" "ecs_green" {
  max_capacity       = var.green_ecs_max_capacity
  min_capacity       = var.green_ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.green.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu_green" {
  name               = "${var.project_name}-ecs-cpu-autoscaling-green"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_green.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_green.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_green.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification { predefined_metric_type = "ECSServiceAverageCPUUtilization" }
    target_value       = 30.0
    scale_in_cooldown  = 120
    scale_out_cooldown = 20
  }
}

resource "aws_appautoscaling_policy" "ecs_memory_green" {
  name               = "${var.project_name}-ecs-memory-autoscaling-green"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_green.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_green.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_green.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification { predefined_metric_type = "ECSServiceAverageMemoryUtilization" }
    target_value       = 30.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 20
  }
}
