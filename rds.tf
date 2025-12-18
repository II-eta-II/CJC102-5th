# DB Subnet Group (必須在 private subnets)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS MySQL database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# RDS MySQL Instance (最便宜的沙盒方案)
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-wordpress-db"
  engine         = "mysql"
  engine_version = "8.0"

  # 最便宜的實例類型
  instance_class = var.db_instance_class

  # 最小儲存空間
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  # 資料庫設定
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  # 網路設定
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # 單一 AZ (最便宜)
  multi_az          = false
  availability_zone = var.availability_zones[0]

  # 備份設定 (最小化以節省成本)
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  skip_final_snapshot     = true
  deletion_protection     = false

  # 效能設定
  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # 參數設定
  parameter_group_name = "default.mysql8.0"

  tags = {
    Name        = "${var.project_name}-wordpress-db"
    Environment = var.environment
  }
}
