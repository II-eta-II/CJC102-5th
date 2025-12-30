# =============================================================================
# ECR Push → ECS Redeploy Pipeline
# =============================================================================
# When a new image is pushed to ECR, automatically trigger ECS service redeployment

# -----------------------------------------------------------------------------
# IAM Role for Lambda
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ecs_deploy_lambda" {
  name = "${var.project_name}-ecs-deploy-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-ecs-deploy-lambda-role"
  }
}

resource "aws_iam_role_policy" "ecs_deploy_lambda" {
  name = "${var.project_name}-ecs-deploy-lambda-policy"
  role = aws_iam_role.ecs_deploy_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------

data "archive_file" "ecs_deploy_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda/ecs_deploy.zip"

  source {
    content  = <<-EOF
import boto3
import json
import os

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    ecs = boto3.client('ecs')
    cluster_name = os.environ['ECS_CLUSTER_NAME']
    service_names = os.environ['ECS_SERVICE_NAMES'].split(',')
    
    results = []
    for service_name in service_names:
        service_name = service_name.strip()
        if not service_name:
            continue
            
        try:
            print(f"Forcing new deployment for service: {service_name}")
            response = ecs.update_service(
                cluster=cluster_name,
                service=service_name,
                forceNewDeployment=True
            )
            results.append({
                'service': service_name,
                'status': 'success',
                'deploymentId': response['service']['deployments'][0]['id']
            })
            print(f"Successfully triggered deployment for {service_name}")
        except Exception as e:
            print(f"Error updating service {service_name}: {str(e)}")
            results.append({
                'service': service_name,
                'status': 'error',
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps(results)
    }
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "ecs_deploy" {
  filename         = data.archive_file.ecs_deploy_lambda.output_path
  function_name    = "${var.project_name}-ecs-deploy"
  role             = aws_iam_role.ecs_deploy_lambda.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.ecs_deploy_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30

  environment {
    variables = {
      ECS_CLUSTER_NAME  = aws_ecs_cluster.main.name
      ECS_SERVICE_NAMES = "${aws_ecs_service.blue.name},${aws_ecs_service.green.name}"
    }
  }

  tags = {
    Name = "${var.project_name}-ecs-deploy-lambda"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "ecs_deploy_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.ecs_deploy.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-ecs-deploy-lambda-logs"
  }
}

# -----------------------------------------------------------------------------
# EventBridge Rule
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "ecr_push" {
  name        = "${var.project_name}-ecr-push"
  description = "Trigger ECS deployment on ECR image push"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      repository-name = [aws_ecr_repository.wordpress.name]
      result          = ["SUCCESS"]
    }
  })

  tags = {
    Name = "${var.project_name}-ecr-push-rule"
  }
}

resource "aws_cloudwatch_event_target" "ecr_push_lambda" {
  rule      = aws_cloudwatch_event_rule.ecr_push.name
  target_id = "ecs-deploy-lambda"
  arn       = aws_lambda_function.ecs_deploy.arn
}

resource "aws_lambda_permission" "ecr_push" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_deploy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_push.arn
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "ecr_deploy_lambda_arn" {
  description = "ARN of the ECS deploy Lambda function"
  value       = aws_lambda_function.ecs_deploy.arn
}

output "ecr_push_event_rule" {
  description = "Name of the EventBridge rule for ECR push"
  value       = aws_cloudwatch_event_rule.ecr_push.name
}

# =============================================================================
# SQL Import Lambda (S3 → RDS Import for inactive environment)
# =============================================================================

# Security Group for Lambda (allows connecting to RDS)
resource "aws_security_group" "sql_import_lambda" {
  name        = "${var.project_name}-sql-import-lambda-sg"
  description = "Security group for SQL Import Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sql-import-lambda-sg"
  }
}

# IAM Role for SQL Import Lambda
resource "aws_iam_role" "sql_import_lambda" {
  name = "${var.project_name}-sql-import-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-sql-import-lambda-role"
  }
}

resource "aws_iam_role_policy" "sql_import_lambda" {
  name = "${var.project_name}-sql-import-lambda-policy"
  role = aws_iam_role.sql_import_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sql_backup.arn,
          "${aws_s3_bucket.sql_backup.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeListeners"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.wordpress_env.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function for SQL Import
data "archive_file" "sql_import_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda/sql_import.zip"

  source {
    content  = <<-EOF
import boto3
import json
import os
import pymysql
import tempfile

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    s3 = boto3.client('s3')
    elbv2 = boto3.client('elbv2')
    secrets = boto3.client('secretsmanager')
    
    # Environment variables
    bucket_name = os.environ['SQL_BUCKET_NAME']
    listener_arn = os.environ['LISTENER_ARN']
    blue_tg_arn = os.environ['BLUE_TG_ARN']
    green_tg_arn = os.environ['GREEN_TG_ARN']
    blue_rds_host = os.environ['BLUE_RDS_HOST']
    green_rds_host = os.environ['GREEN_RDS_HOST']
    db_name = os.environ['DB_NAME']
    secret_arn = os.environ['SECRET_ARN']
    
    # 1. Get latest .sql file from S3
    print(f"Listing objects in bucket: {bucket_name}")
    response = s3.list_objects_v2(Bucket=bucket_name, Prefix='')
    sql_files = [obj for obj in response.get('Contents', []) if obj['Key'].endswith('.sql')]
    
    if not sql_files:
        return {'statusCode': 404, 'body': 'No .sql files found'}
    
    latest_file = max(sql_files, key=lambda x: x['LastModified'])
    print(f"Latest SQL file: {latest_file['Key']}")
    
    # 2. Determine which environment has 0 weight
    rules = elbv2.describe_rules(ListenerArn=listener_arn)['Rules']
    default_rule = next((r for r in rules if r['IsDefault']), None)
    
    if not default_rule:
        return {'statusCode': 500, 'body': 'No default rule found'}
    
    # Find target group weights
    target_groups = default_rule['Actions'][0].get('ForwardConfig', {}).get('TargetGroups', [])
    
    inactive_env = None
    rds_host = None
    
    for tg in target_groups:
        if tg['TargetGroupArn'] == blue_tg_arn and tg.get('Weight', 0) == 0:
            inactive_env = 'blue'
            rds_host = blue_rds_host
            break
        elif tg['TargetGroupArn'] == green_tg_arn and tg.get('Weight', 0) == 0:
            inactive_env = 'green'
            rds_host = green_rds_host
            break
    
    if not inactive_env:
        # Check if listener uses simple forward (no weights)
        print("No weighted routing found, using Blue RDS as default")
        inactive_env = 'blue'
        rds_host = blue_rds_host
    
    print(f"Inactive environment: {inactive_env}, RDS Host: {rds_host}")
    
    # 3. Get database credentials from Secrets Manager
    secret_value = secrets.get_secret_value(SecretId=secret_arn)
    secret = json.loads(secret_value['SecretString'])
    db_user = secret['db_username']
    db_password = secret['db_password']
    
    # 4. Download SQL file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sql', delete=False) as tmp:
        s3.download_file(bucket_name, latest_file['Key'], tmp.name)
        sql_file_path = tmp.name
    
    # 5. Execute SQL on RDS
    print(f"Connecting to RDS: {rds_host}")
    try:
        conn = pymysql.connect(
            host=rds_host,
            user=db_user,
            password=db_password,
            database=db_name,
            connect_timeout=30
        )
        
        with open(sql_file_path, 'r') as f:
            sql_content = f.read()
        
        cursor = conn.cursor()
        # Execute each statement separately
        for statement in sql_content.split(';'):
            statement = statement.strip()
            if statement:
                cursor.execute(statement)
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"SQL import completed successfully to {inactive_env} environment")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'environment': inactive_env,
                'file': latest_file['Key'],
                'status': 'success'
            })
        }
    except Exception as e:
        print(f"Error executing SQL: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "sql_import" {
  filename         = data.archive_file.sql_import_lambda.output_path
  function_name    = "${var.project_name}-sql-import"
  role             = aws_iam_role.sql_import_lambda.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.sql_import_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 512

  # VPC Configuration - Required for RDS access
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.sql_import_lambda.id]
  }

  environment {
    variables = {
      SQL_BUCKET_NAME = aws_s3_bucket.sql_backup.id
      LISTENER_ARN    = aws_lb_listener.https.arn
      BLUE_TG_ARN     = aws_lb_target_group.ecs.arn
      GREEN_TG_ARN    = aws_lb_target_group.ecs_green.arn
      BLUE_RDS_HOST   = aws_db_instance.main.address
      GREEN_RDS_HOST  = aws_db_instance.green.address
      DB_NAME         = var.db_name
      SECRET_ARN      = aws_secretsmanager_secret.wordpress_env.arn
    }
  }

  # NOTE: This Lambda requires pymysql package
  # You can either:
  # 1. Create a Lambda Layer manually with pymysql
  # 2. Use the AWS CLI to deploy with dependencies bundled
  # 
  # To create layer manually:
  # mkdir python && pip install pymysql -t python
  # zip -r pymysql-layer.zip python
  # aws lambda publish-layer-version --layer-name pymysql --zip-file fileb://pymysql-layer.zip --compatible-runtimes python3.11
  # Then uncomment and update the ARN below:
  # layers = ["arn:aws:lambda:ap-northeast-1:YOUR_ACCOUNT:layer:pymysql:1"]

  tags = {
    Name = "${var.project_name}-sql-import-lambda"
  }
}

# CloudWatch Log Group for SQL Import Lambda
resource "aws_cloudwatch_log_group" "sql_import_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.sql_import.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-sql-import-lambda-logs"
  }
}

# Output
output "sql_import_lambda_arn" {
  description = "ARN of the SQL Import Lambda function"
  value       = aws_lambda_function.sql_import.arn
}

