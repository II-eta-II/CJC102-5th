# DB Subnet Group (必須在 private subnets)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# =============================================================================
# Blue Environment RDS
# =============================================================================

# Security Group for RDS - Blue
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for Blue RDS MySQL database"
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
    Name        = "${var.project_name}-rds-sg"
    Environment = "blue"
  }
}

# RDS MySQL Instance - Blue
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-wordpress-db-blue"
  engine         = "mysql"
  engine_version = "8.0"

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az          = false
  availability_zone = var.availability_zones[0]

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  parameter_group_name            = "default.mysql8.0"

  tags = {
    Name        = "${var.project_name}-wordpress-db-blue"
    Environment = "blue"
  }
}

# =============================================================================
# Green Environment RDS (Blue-Green Deployment)
# =============================================================================

resource "aws_security_group" "rds_green" {
  name        = "${var.project_name}-rds-green-sg"
  description = "Security group for Green RDS MySQL database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from Blue ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "MySQL from Green ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_green.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-rds-green-sg"
    Environment = "green"
  }
}

resource "aws_db_instance" "green" {
  identifier     = "${var.project_name}-wordpress-db-green"
  engine         = "mysql"
  engine_version = "8.0"

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_green.id]
  publicly_accessible    = false

  multi_az          = false
  availability_zone = var.availability_zones[1] # 使用不同 AZ

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  parameter_group_name            = "default.mysql8.0"

  tags = {
    Name        = "${var.project_name}-wordpress-db-green"
    Environment = "green"
  }
}
