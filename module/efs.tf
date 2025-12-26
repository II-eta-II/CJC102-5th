# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-efs-sg"
  }
}

# =============================================================================
# Blue Environment EFS
# =============================================================================

# EFS File System - Blue
resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_name}-efs-blue"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "${var.project_name}-efs-blue"
    Environment = "blue"
  }
}

# EFS Mount Targets (一個在每個 Private Subnet)
resource "aws_efs_mount_target" "main" {
  count           = length(var.availability_zones)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point for ECS - Blue
# Bitnami containers run as UID 1001 (daemon user)
resource "aws_efs_access_point" "ecs" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    uid = 1001
    gid = 1001
  }

  root_directory {
    path = "/bitnami"
    creation_info {
      owner_uid   = 1001
      owner_gid   = 1001
      permissions = "0755"
    }
  }

  tags = {
    Name        = "${var.project_name}-ecs-access-point-blue"
    Environment = "blue"
  }
}

# =============================================================================
# Green Environment EFS (Blue-Green Deployment)
# =============================================================================

resource "aws_efs_file_system" "green" {
  creation_token = "${var.project_name}-efs-green"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "${var.project_name}-efs-green"
    Environment = "green"
  }
}

resource "aws_efs_mount_target" "green" {
  count           = length(var.availability_zones)
  file_system_id  = aws_efs_file_system.green.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "green" {
  file_system_id = aws_efs_file_system.green.id

  posix_user {
    uid = 1001
    gid = 1001
  }

  root_directory {
    path = "/bitnami"
    creation_info {
      owner_uid   = 1001
      owner_gid   = 1001
      permissions = "0755"
    }
  }

  tags = {
    Name        = "${var.project_name}-ecs-access-point-green"
    Environment = "green"
  }
}
