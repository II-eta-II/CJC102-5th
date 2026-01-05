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
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
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
          "iam:PassRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages"
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
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.canary_deploy.arn
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
import re

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    ecs = boto3.client('ecs')
    elbv2 = boto3.client('elbv2')
    ecr = boto3.client('ecr')
    lambda_client = boto3.client('lambda')
    
    # Environment variables
    cluster_name = os.environ['ECS_CLUSTER_NAME']
    blue_service = os.environ['BLUE_SERVICE_NAME']
    green_service = os.environ['GREEN_SERVICE_NAME']
    listener_arn = os.environ['LISTENER_ARN']
    blue_tg_arn = os.environ['BLUE_TG_ARN']
    green_tg_arn = os.environ['GREEN_TG_ARN']
    ecr_repo_url = os.environ['ECR_REPO_URL']
    canary_deploy_lambda_arn = os.environ.get('CANARY_DEPLOY_LAMBDA_ARN', '')
    
    # Get image digest and repo name from ECR push event
    detail = event.get('detail', {})
    image_digest = detail.get('image-digest', '')
    repo_name = detail.get('repository-name', '')
    triggered_tag = detail.get('image-tag', 'latest')
    
    print(f"Triggered by tag: {triggered_tag}, digest: {image_digest}")
    
    # Find version tag (x.x.x format) for the same image digest
    image_tag = None
    if image_digest and repo_name:
        try:
            # Get all tags for this image digest
            response = ecr.describe_images(
                repositoryName=repo_name,
                imageIds=[{'imageDigest': image_digest}]
            )
            
            for image in response.get('imageDetails', []):
                tags = image.get('imageTags', [])
                print(f"Found tags for digest: {tags}")
                
                # Find version tag matching x.x.x pattern
                for tag in tags:
                    if re.match(r'^\d+\.\d+\.\d+$', tag):
                        image_tag = tag
                        print(f"Found version tag: {image_tag}")
                        break
                
                if image_tag:
                    break
        except Exception as e:
            print(f"Error looking up ECR tags: {e}")
    
    if not image_tag:
        print(f"No version tag (x.x.x) found for this image. Using triggered tag: {triggered_tag}")
        image_tag = triggered_tag
    
    print(f"Using image tag: {image_tag}")
    
    # Detect inactive environment (weight = 0)
    rules = elbv2.describe_rules(ListenerArn=listener_arn)['Rules']
    default_rule = next((r for r in rules if r['IsDefault']), None)
    
    if not default_rule:
        return {'statusCode': 500, 'body': 'No default rule found'}
    
    target_groups = default_rule['Actions'][0].get('ForwardConfig', {}).get('TargetGroups', [])
    
    inactive_env = None
    inactive_service = None
    
    for tg in target_groups:
        if tg['TargetGroupArn'] == blue_tg_arn and tg.get('Weight', 0) == 0:
            inactive_env = 'blue'
            inactive_service = blue_service
            break
        elif tg['TargetGroupArn'] == green_tg_arn and tg.get('Weight', 0) == 0:
            inactive_env = 'green'
            inactive_service = green_service
            break
    
    if not inactive_env:
        print("No inactive environment found (both have non-zero weight). Skipping deployment.")
        return {'statusCode': 200, 'body': json.dumps({'status': 'skipped', 'reason': 'no_inactive_env'})}
    
    print(f"Deploying to inactive environment: {inactive_env} (service: {inactive_service})")
    
    # Get current task definition for the inactive service
    service_desc = ecs.describe_services(cluster=cluster_name, services=[inactive_service])
    current_task_def_arn = service_desc['services'][0]['taskDefinition']
    
    # Get task definition details
    task_def = ecs.describe_task_definition(taskDefinition=current_task_def_arn)['taskDefinition']
    
    # Update container image with new tag
    new_image = f"{ecr_repo_url}:{image_tag}"
    for container in task_def['containerDefinitions']:
        if 'wordpress' in container['name'].lower() or container == task_def['containerDefinitions'][0]:
            old_image = container['image']
            container['image'] = new_image
            print(f"Updating container '{container['name']}' image: {old_image} -> {new_image}")
            break
    
    # Register new task definition (copy from existing, just change image)
    new_task_def = ecs.register_task_definition(
        family=task_def['family'],
        taskRoleArn=task_def.get('taskRoleArn', ''),
        executionRoleArn=task_def.get('executionRoleArn', ''),
        networkMode=task_def.get('networkMode', 'awsvpc'),
        containerDefinitions=task_def['containerDefinitions'],
        volumes=task_def.get('volumes', []),
        requiresCompatibilities=task_def.get('requiresCompatibilities', ['FARGATE']),
        cpu=task_def.get('cpu', '256'),
        memory=task_def.get('memory', '512')
    )
    
    new_task_def_arn = new_task_def['taskDefinition']['taskDefinitionArn']
    print(f"Registered new task definition: {new_task_def_arn}")
    
    # Update service to use new task definition
    response = ecs.update_service(
        cluster=cluster_name,
        service=inactive_service,
        taskDefinition=new_task_def_arn,
        forceNewDeployment=True
    )
    
    deployment_id = response['service']['deployments'][0]['id']
    print(f"Successfully triggered deployment for {inactive_service}: {deployment_id}")
    
    # Invoke canary_deploy Lambda (next step in pipeline)
    if canary_deploy_lambda_arn:
        print(f"Invoking canary_deploy Lambda: {canary_deploy_lambda_arn}")
        try:
            # Pass inactive_env info to canary_deploy
            canary_event = {
                'inactive_env': inactive_env,
                'image_tag': image_tag,
                'deployment_id': deployment_id,
                'original_event': event
            }
            lambda_client.invoke(
                FunctionName=canary_deploy_lambda_arn,
                InvocationType='Event',  # Async invoke
                Payload=json.dumps(canary_event)
            )
            print("canary_deploy Lambda invoked successfully")
        except Exception as e:
            print(f"Error invoking canary_deploy Lambda: {e}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'success',
            'environment': inactive_env,
            'service': inactive_service,
            'image_tag': image_tag,
            'task_definition': new_task_def_arn,
            'deployment_id': deployment_id,
            'next_step': 'canary_deploy'
        })
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
      ECS_CLUSTER_NAME         = aws_ecs_cluster.main.name
      BLUE_SERVICE_NAME        = aws_ecs_service.blue.name
      GREEN_SERVICE_NAME       = aws_ecs_service.green.name
      LISTENER_ARN             = aws_lb_listener.https.arn
      BLUE_TG_ARN              = aws_lb_target_group.ecs.arn
      GREEN_TG_ARN             = aws_lb_target_group.ecs_green.arn
      ECR_REPO_URL             = aws_ecr_repository.wordpress.repository_url
      CANARY_DEPLOY_LAMBDA_ARN = aws_lambda_function.canary_deploy.arn
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
      image-tag       = ["latest"]
    }
  })

  tags = {
    Name = "${var.project_name}-ecr-push-rule"
  }
}

resource "aws_cloudwatch_event_target" "ecr_push_sql_import" {
  rule      = aws_cloudwatch_event_rule.ecr_push.name
  target_id = "sql-import-lambda"
  arn       = aws_lambda_function.sql_import.arn
}

resource "aws_lambda_permission" "ecr_push_sql_import" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sql_import.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_push.arn
}

# Note: ecs_deploy and canary_deploy are now invoked sequentially by sql_import and ecs_deploy respectively
# Flow: ECR Push → sql_import → ecs_deploy → canary_deploy


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
# PyMySQL Lambda Layer
# =============================================================================

resource "aws_lambda_layer_version" "pymysql" {
  filename            = "${path.module}/lambda/pymysql-layer.zip"
  layer_name          = "${var.project_name}-pymysql"
  description         = "PyMySQL library for Python 3.11"
  compatible_runtimes = ["python3.11"]
  source_code_hash    = filebase64sha256("${path.module}/lambda/pymysql-layer.zip")
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
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.ecs_deploy.arn
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
    lambda_client = boto3.client('lambda')
    
    # Environment variables
    bucket_name = os.environ['SQL_BUCKET_NAME']
    listener_arn = os.environ['LISTENER_ARN']
    blue_tg_arn = os.environ['BLUE_TG_ARN']
    green_tg_arn = os.environ['GREEN_TG_ARN']
    blue_rds_host = os.environ['BLUE_RDS_HOST']
    green_rds_host = os.environ['GREEN_RDS_HOST']
    db_name = os.environ['DB_NAME']
    secret_arn = os.environ['SECRET_ARN']
    ecs_deploy_lambda_arn = os.environ.get('ECS_DEPLOY_LAMBDA_ARN', '')
    
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
    blue_weight = None
    green_weight = None
    
    # Get weights for each target group
    for tg in target_groups:
        if tg['TargetGroupArn'] == blue_tg_arn:
            blue_weight = tg.get('Weight', 0)
        elif tg['TargetGroupArn'] == green_tg_arn:
            green_weight = tg.get('Weight', 0)
    
    print(f"Blue weight: {blue_weight}, Green weight: {green_weight}")
    
    # Determine which environment has weight = 0
    if blue_weight == 0 and green_weight is not None and green_weight > 0:
        inactive_env = 'blue'
        rds_host = blue_rds_host
    elif green_weight == 0 and blue_weight is not None and blue_weight > 0:
        inactive_env = 'green'
        rds_host = green_rds_host
    else:
        # Both have non-zero weight or no weighted routing found
        print("No environment with weight=0 found. Skipping SQL import.")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'skipped',
                'reason': 'Both environments have non-zero weight or no weighted routing',
                'blue_weight': blue_weight,
                'green_weight': green_weight
            })
        }
    
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
        # Use CLIENT.MULTI_STATEMENTS to execute multiple SQL statements at once
        from pymysql.constants import CLIENT
        conn = pymysql.connect(
            host=rds_host,
            user=db_user,
            password=db_password,
            database=db_name,
            connect_timeout=30,
            client_flag=CLIENT.MULTI_STATEMENTS
        )
        
        with open(sql_file_path, 'r', encoding='utf-8') as f:
            sql_content = f.read()
        
        cursor = conn.cursor()
        # Execute entire SQL dump as multi-statement
        cursor.execute(sql_content)
        
        # Consume all results to avoid "Commands out of sync" error
        while cursor.nextset():
            pass
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"SQL import completed successfully to {inactive_env} environment")
        
        # 6. Invoke ecs_deploy Lambda (next step in pipeline)
        if ecs_deploy_lambda_arn:
            print(f"Invoking ecs_deploy Lambda: {ecs_deploy_lambda_arn}")
            try:
                lambda_client.invoke(
                    FunctionName=ecs_deploy_lambda_arn,
                    InvocationType='Event',  # Async invoke
                    Payload=json.dumps(event)
                )
                print("ecs_deploy Lambda invoked successfully")
            except Exception as e:
                print(f"Error invoking ecs_deploy Lambda: {e}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'environment': inactive_env,
                'file': latest_file['Key'],
                'status': 'success',
                'next_step': 'ecs_deploy'
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
      SQL_BUCKET_NAME       = aws_s3_bucket.sql_backup.id
      LISTENER_ARN          = aws_lb_listener.https.arn
      BLUE_TG_ARN           = aws_lb_target_group.ecs.arn
      GREEN_TG_ARN          = aws_lb_target_group.ecs_green.arn
      BLUE_RDS_HOST         = aws_db_instance.main.address
      GREEN_RDS_HOST        = aws_db_instance.green.address
      DB_NAME               = var.db_name
      SECRET_ARN            = aws_secretsmanager_secret.wordpress_env.arn
      ECS_DEPLOY_LAMBDA_ARN = aws_lambda_function.ecs_deploy.arn
    }
  }

  # PyMySQL Lambda Layer
  layers = [aws_lambda_layer_version.pymysql.arn]

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

# =============================================================================
# Canary Deploy Lambda (金絲雀部署 - 漸進式流量切換)
# =============================================================================

# IAM Role for Canary Deploy Lambda
resource "aws_iam_role" "canary_deploy_lambda" {
  name = "${var.project_name}-canary-deploy-lambda-role"

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
    Name = "${var.project_name}-canary-deploy-lambda-role"
  }
}

resource "aws_iam_role_policy" "canary_deploy_lambda" {
  name = "${var.project_name}-canary-deploy-lambda-policy"
  role = aws_iam_role.canary_deploy_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeListeners"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetHealth"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.synthetic_traffic.arn
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

# Canary Deploy Lambda Function
data "archive_file" "canary_deploy_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda/canary_deploy.zip"

  source {
    content  = <<-EOF
import boto3
import json
import os
import time

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    elbv2 = boto3.client('elbv2')
    cloudwatch = boto3.client('cloudwatch')
    lambda_client = boto3.client('lambda')
    
    # Environment variables
    listener_arn = os.environ['LISTENER_ARN']
    blue_tg_arn = os.environ['BLUE_TG_ARN']
    green_tg_arn = os.environ['GREEN_TG_ARN']
    canary_enabled = os.environ.get('CANARY_ENABLED', 'true').lower() == 'true'
    pre_deploy_wait = int(os.environ.get('PRE_DEPLOY_WAIT_SEC', '120'))
    canary_pct = int(os.environ.get('CANARY_PERCENTAGE', '10'))
    canary_duration = int(os.environ.get('CANARY_DURATION_SEC', '300'))
    full_deploy_wait = int(os.environ.get('FULL_DEPLOY_WAIT_SEC', '60'))
    alarm_5xx_name = os.environ.get('ALARM_5XX_NAME', '')
    synthetic_lambda_arn = os.environ.get('SYNTHETIC_LAMBDA_ARN', '')
    
    if not canary_enabled:
        print("Canary deployment is disabled. Skipping.")
        return {'statusCode': 200, 'body': json.dumps({'status': 'skipped', 'reason': 'disabled'})}
    
    # Stage 0: Pre-deploy wait - wait for new deployment to be ready
    print(f"Stage 0: Waiting {pre_deploy_wait} seconds for new deployment to be ready...")
    time.sleep(pre_deploy_wait)
    
    # Get inactive environment from event or detect from ALB
    inactive_env = event.get('inactive_env')
    
    if not inactive_env:
        # Detect from ALB weights
        rules = elbv2.describe_rules(ListenerArn=listener_arn)['Rules']
        default_rule = next((r for r in rules if r['IsDefault']), None)
        
        if not default_rule:
            return {'statusCode': 500, 'body': 'No default rule found'}
        
        tgs = default_rule['Actions'][0].get('ForwardConfig', {}).get('TargetGroups', [])
        for tg in tgs:
            if tg['TargetGroupArn'] == blue_tg_arn and tg.get('Weight', 0) == 0:
                inactive_env = 'blue'
                break
            elif tg['TargetGroupArn'] == green_tg_arn and tg.get('Weight', 0) == 0:
                inactive_env = 'green'
                break
    
    if not inactive_env:
        print("No inactive environment found. Skipping canary deployment.")
        return {'statusCode': 200, 'body': json.dumps({'status': 'skipped', 'reason': 'no_inactive_env'})}
    
    print(f"Starting canary deployment for: {inactive_env}")
    
    # Determine target groups
    if inactive_env == 'blue':
        new_tg_arn = blue_tg_arn
        old_tg_arn = green_tg_arn
    else:
        new_tg_arn = green_tg_arn
        old_tg_arn = blue_tg_arn
    
    # Helper function to modify listener default action
    def set_traffic_weights(tg1_arn, tg1_weight, tg2_arn, tg2_weight):
        """Modify listener default action to set traffic weights"""
        elbv2.modify_listener(
            ListenerArn=listener_arn,
            DefaultActions=[{
                'Type': 'forward',
                'ForwardConfig': {
                    'TargetGroups': [
                        {'TargetGroupArn': tg1_arn, 'Weight': tg1_weight},
                        {'TargetGroupArn': tg2_arn, 'Weight': tg2_weight}
                    ]
                }
            }]
        )
    
    def rollback(reason):
        """Rollback to old environment"""
        print(f"ROLLBACK triggered: {reason}")
        set_traffic_weights(old_tg_arn, 100, new_tg_arn, 0)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'rollback',
                'reason': reason,
                'environment': inactive_env
            })
        }
    
    def check_alarms():
        """Check CloudWatch alarms for errors"""
        if not alarm_5xx_name:
            return None
        
        try:
            response = cloudwatch.describe_alarms(AlarmNames=[alarm_5xx_name])
            for alarm in response.get('MetricAlarms', []):
                if alarm['StateValue'] == 'ALARM':
                    return alarm['AlarmName']
        except Exception as e:
            print(f"Error checking alarms: {e}")
        return None
    
    def check_target_health():
        """Check Target Group health - only 'unhealthy' status triggers rollback"""
        unhealthy_threshold = 0  # Trigger rollback if any unhealthy targets
        
        try:
            response = elbv2.describe_target_health(TargetGroupArn=new_tg_arn)
            targets = response.get('TargetHealthDescriptions', [])
            
            unhealthy_count = 0
            other_states = {}
            
            for target in targets:
                health_state = target.get('TargetHealth', {}).get('State', '')
                if health_state == 'unhealthy':
                    unhealthy_count += 1
                else:
                    # Count other states for logging only
                    other_states[health_state] = other_states.get(health_state, 0) + 1
            
            total_count = len(targets)
            print(f"Target health check - Total: {total_count}, Unhealthy: {unhealthy_count}, Others: {other_states}")
            
            # Only 'unhealthy' status triggers rollback
            if unhealthy_count > unhealthy_threshold:
                return f"Unhealthy targets detected: {unhealthy_count}/{total_count}"
                
        except Exception as e:
            print(f"Error checking target health: {e}")
        
        return None
    
    def invoke_synthetic_traffic():
        """Invoke synthetic traffic Lambda"""
        if not synthetic_lambda_arn:
            print("No synthetic traffic Lambda configured")
            return
        
        try:
            print("Invoking synthetic traffic Lambda...")
            lambda_client.invoke(
                FunctionName=synthetic_lambda_arn,
                InvocationType='Event'  # Async
            )
            print("Synthetic traffic Lambda invoked")
        except Exception as e:
            print(f"Error invoking synthetic traffic: {e}")
    
    # Stage 1: Canary - small percentage to new environment
    print(f"Stage 1: Canary - {canary_pct}% to new environment ({inactive_env})")
    set_traffic_weights(old_tg_arn, 100 - canary_pct, new_tg_arn, canary_pct)
    
    # Invoke synthetic traffic to ensure we have requests
    invoke_synthetic_traffic()
    
    # Wait for canary observation with alarm monitoring
    print(f"Waiting {canary_duration} seconds for canary observation...")
    check_interval = 30  # Check every 30 seconds
    elapsed = 0
    
    while elapsed < canary_duration:
        time.sleep(check_interval)
        elapsed += check_interval
        
        # Check for alarms
        alarm_triggered = check_alarms()
        if alarm_triggered:
            return rollback(f"CloudWatch alarm triggered: {alarm_triggered}")
        
        # Check target health
        health_error = check_target_health()
        if health_error:
            return rollback(f"Target health check failed: {health_error}")
        
        print(f"Canary check at {elapsed}s - All checks passed")
    
    # Stage 2: Full deployment - 100% to new environment
    print(f"Stage 2: Full deployment - 100% to new environment ({inactive_env})")
    set_traffic_weights(old_tg_arn, 0, new_tg_arn, 100)
    
    # Invoke synthetic traffic again for full deployment test
    invoke_synthetic_traffic()
    
    # Wait for full deployment with alarm monitoring
    print(f"Waiting {full_deploy_wait} seconds for full deployment...")
    elapsed = 0
    
    while elapsed < full_deploy_wait:
        time.sleep(min(check_interval, full_deploy_wait - elapsed))
        elapsed += check_interval
        
        # Check for alarms
        alarm_triggered = check_alarms()
        if alarm_triggered:
            return rollback(f"CloudWatch alarm triggered during full deploy: {alarm_triggered}")
        
        # Check target health
        health_error = check_target_health()
        if health_error:
            return rollback(f"Target health check failed during full deploy: {health_error}")
    
    print(f"Canary deployment completed successfully for {inactive_env}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'deployed',
            'environment': inactive_env,
            'canary_percentage': canary_pct,
            'canary_duration': canary_duration
        })
    }
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "canary_deploy" {
  filename         = data.archive_file.canary_deploy_lambda.output_path
  function_name    = "${var.project_name}-canary-deploy"
  role             = aws_iam_role.canary_deploy_lambda.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.canary_deploy_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 900 # 15 minutes for long running canary
  memory_size      = 128

  environment {
    variables = {
      LISTENER_ARN         = aws_lb_listener.https.arn
      BLUE_TG_ARN          = aws_lb_target_group.ecs.arn
      GREEN_TG_ARN         = aws_lb_target_group.ecs_green.arn
      CANARY_ENABLED       = tostring(var.canary_enabled)
      PRE_DEPLOY_WAIT_SEC  = tostring(var.pre_deploy_wait_sec)
      CANARY_PERCENTAGE    = tostring(var.canary_percentage)
      CANARY_DURATION_SEC  = tostring(var.canary_duration_sec)
      FULL_DEPLOY_WAIT_SEC = tostring(var.full_deploy_wait_sec)
      ALARM_5XX_NAME       = aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name
      SYNTHETIC_LAMBDA_ARN = aws_lambda_function.synthetic_traffic.arn
    }
  }

  tags = {
    Name = "${var.project_name}-canary-deploy-lambda"
  }
}

# Disable retries for Canary Deploy Lambda (失敗不重試)
resource "aws_lambda_function_event_invoke_config" "canary_deploy" {
  function_name          = aws_lambda_function.canary_deploy.function_name
  maximum_retry_attempts = 0
}

# CloudWatch Log Group for Canary Deploy Lambda
resource "aws_cloudwatch_log_group" "canary_deploy_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.canary_deploy.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-canary-deploy-lambda-logs"
  }
}

# Output
output "canary_deploy_lambda_arn" {
  description = "ARN of the Canary Deploy Lambda function"
  value       = aws_lambda_function.canary_deploy.arn
}

# =============================================================================
# Synthetic Traffic Lambda (合成流量測試 - 金絲雀期間自動發送請求)
# =============================================================================

# IAM Role for Synthetic Traffic Lambda
resource "aws_iam_role" "synthetic_traffic_lambda" {
  name = "${var.project_name}-synthetic-traffic-lambda-role"

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
    Name = "${var.project_name}-synthetic-traffic-lambda-role"
  }
}

resource "aws_iam_role_policy" "synthetic_traffic_lambda" {
  name = "${var.project_name}-synthetic-traffic-lambda-policy"
  role = aws_iam_role.synthetic_traffic_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

# Synthetic Traffic Lambda Function
data "archive_file" "synthetic_traffic_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda/synthetic_traffic.zip"

  source {
    content  = <<-EOF
import json
import os
import time
import urllib.request
import urllib.error
import concurrent.futures

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    # Environment variables
    target_url = os.environ.get('TARGET_URL', '')
    min_requests = int(os.environ.get('MIN_REQUESTS', '100'))
    concurrent_requests = int(os.environ.get('CONCURRENT_REQUESTS', '10'))
    request_interval_ms = int(os.environ.get('REQUEST_INTERVAL_MS', '100'))
    pre_deploy_wait = int(os.environ.get('PRE_DEPLOY_WAIT_SEC', '120'))
    
    # Override from event if provided
    target_url = event.get('target_url', target_url)
    min_requests = event.get('min_requests', min_requests)
    
    if not target_url:
        return {'statusCode': 400, 'body': json.dumps({'error': 'TARGET_URL not configured'})}
    
    # Stage 0: Pre-deploy wait - same as canary
    print(f"Stage 0: Waiting {pre_deploy_wait} seconds for new deployment to be ready...")
    time.sleep(pre_deploy_wait)
    
    print(f"Starting synthetic traffic test")
    print(f"Target URL: {target_url}")
    print(f"Minimum requests: {min_requests}")
    print(f"Concurrent requests: {concurrent_requests}")
    
    success_count = 0
    error_4xx = 0
    error_5xx = 0
    other_errors = 0
    
    def make_request(i):
        try:
            req = urllib.request.Request(target_url, headers={'User-Agent': 'SyntheticTrafficLambda/1.0'})
            with urllib.request.urlopen(req, timeout=30) as response:
                status = response.getcode()
                return ('success', status)
        except urllib.error.HTTPError as e:
            return ('http_error', e.code)
        except Exception as e:
            return ('error', str(e))
    
    # Send requests in batches
    batch_size = concurrent_requests
    total_batches = (min_requests + batch_size - 1) // batch_size
    
    for batch in range(total_batches):
        start_idx = batch * batch_size
        end_idx = min(start_idx + batch_size, min_requests)
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrent_requests) as executor:
            futures = [executor.submit(make_request, i) for i in range(start_idx, end_idx)]
            
            for future in concurrent.futures.as_completed(futures):
                result_type, result_value = future.result()
                if result_type == 'success':
                    success_count += 1
                elif result_type == 'http_error':
                    if 400 <= result_value < 500:
                        error_4xx += 1
                    elif 500 <= result_value < 600:
                        error_5xx += 1
                else:
                    other_errors += 1
        
        # Small delay between batches
        time.sleep(request_interval_ms / 1000)
        
        # Log progress
        if (batch + 1) % 10 == 0:
            print(f"Progress: {end_idx}/{min_requests} requests completed")
    
    total_requests = success_count + error_4xx + error_5xx + other_errors
    
    result = {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'completed',
            'target_url': target_url,
            'total_requests': total_requests,
            'success_count': success_count,
            'error_4xx': error_4xx,
            'error_5xx': error_5xx,
            'other_errors': other_errors,
            'success_rate': f"{(success_count / total_requests * 100):.2f}%" if total_requests > 0 else "N/A"
        })
    }
    
    print(f"Result: {json.dumps(result['body'])}")
    
    # Return error if too many 5xx errors
    if error_5xx > min_requests * 0.1:  # More than 10% 5xx errors
        result['statusCode'] = 500
        result['body'] = json.dumps({
            'status': 'error',
            'reason': 'Too many 5xx errors detected',
            'error_5xx': error_5xx,
            'threshold': min_requests * 0.1
        })
    
    return result
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "synthetic_traffic" {
  filename         = data.archive_file.synthetic_traffic_lambda.output_path
  function_name    = "${var.project_name}-synthetic-traffic"
  role             = aws_iam_role.synthetic_traffic_lambda.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.synthetic_traffic_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300 # 5 minutes
  memory_size      = 256

  environment {
    variables = {
      TARGET_URL          = "https://${var.subdomain}.${var.route53_domain_name}/"
      MIN_REQUESTS        = "100" # 2x of 50 (4xx threshold)
      CONCURRENT_REQUESTS = "10"
      REQUEST_INTERVAL_MS = "100"
      PRE_DEPLOY_WAIT_SEC = tostring(var.pre_deploy_wait_sec)
    }
  }

  tags = {
    Name = "${var.project_name}-synthetic-traffic-lambda"
  }
}

# CloudWatch Log Group for Synthetic Traffic Lambda
resource "aws_cloudwatch_log_group" "synthetic_traffic_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.synthetic_traffic.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-synthetic-traffic-lambda-logs"
  }
}

# Output
output "synthetic_traffic_lambda_arn" {
  description = "ARN of the Synthetic Traffic Lambda function"
  value       = aws_lambda_function.synthetic_traffic.arn
}

# =============================================================================
# Rollback Lambda (緊急回滾 - 在金絲雀部署任何階段安全回滾)
# =============================================================================

# IAM Role for Rollback Lambda
resource "aws_iam_role" "rollback_lambda" {
  name = "${var.project_name}-rollback-lambda-role"

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
    Name = "${var.project_name}-rollback-lambda-role"
  }
}

resource "aws_iam_role_policy" "rollback_lambda" {
  name = "${var.project_name}-rollback-lambda-policy"
  role = aws_iam_role.rollback_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeListeners"
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

# Rollback Lambda Function
data "archive_file" "rollback_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda/rollback.zip"

  source {
    content  = <<-EOF
import boto3
import json
import os

def handler(event, context):
    """
    Emergency Rollback Lambda
    
    可在金絲雀部署任何階段觸發，立即將流量切回原環境。
    
    Event 參數:
    - target_env: 'blue' 或 'green' (可選，不指定則自動偵測)
    
    使用方式:
    1. AWS Console: 手動 Test Lambda
    2. CLI: aws lambda invoke --function-name usa-ops-rollback ...
    """
    print(f"Received event: {json.dumps(event)}")
    
    elbv2 = boto3.client('elbv2')
    
    # Environment variables
    listener_arn = os.environ['LISTENER_ARN']
    blue_tg_arn = os.environ['BLUE_TG_ARN']
    green_tg_arn = os.environ['GREEN_TG_ARN']
    
    # Get current weights from listener
    listeners = elbv2.describe_listeners(ListenerArns=[listener_arn])['Listeners']
    if not listeners:
        return {'statusCode': 500, 'body': 'No listener found'}
    
    listener = listeners[0]
    tgs = listener['DefaultActions'][0].get('ForwardConfig', {}).get('TargetGroups', [])
    
    blue_weight = 0
    green_weight = 0
    
    for tg in tgs:
        if tg['TargetGroupArn'] == blue_tg_arn:
            blue_weight = tg.get('Weight', 0)
        elif tg['TargetGroupArn'] == green_tg_arn:
            green_weight = tg.get('Weight', 0)
    
    print(f"Current weights - Blue: {blue_weight}, Green: {green_weight}")
    
    # Determine target environment
    target_env = event.get('target_env')
    
    if not target_env:
        # Auto-detect: rollback to the one with higher weight (the "old" env)
        if blue_weight >= green_weight:
            target_env = 'blue'
        else:
            target_env = 'green'
    
    # Set 100% traffic to target environment
    if target_env == 'blue':
        new_blue_weight = 100
        new_green_weight = 0
    else:
        new_blue_weight = 0
        new_green_weight = 100
    
    print(f"ROLLBACK: Setting traffic to {target_env} (100%)")
    
    elbv2.modify_listener(
        ListenerArn=listener_arn,
        DefaultActions=[{
            'Type': 'forward',
            'ForwardConfig': {
                'TargetGroups': [
                    {'TargetGroupArn': blue_tg_arn, 'Weight': new_blue_weight},
                    {'TargetGroupArn': green_tg_arn, 'Weight': new_green_weight}
                ]
            }
        }]
    )
    
    print(f"Rollback completed successfully to {target_env}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'rollback_completed',
            'target_environment': target_env,
            'previous_weights': {'blue': blue_weight, 'green': green_weight},
            'new_weights': {'blue': new_blue_weight, 'green': new_green_weight}
        })
    }
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "rollback" {
  filename         = data.archive_file.rollback_lambda.output_path
  function_name    = "${var.project_name}-rollback"
  role             = aws_iam_role.rollback_lambda.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.rollback_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      LISTENER_ARN = aws_lb_listener.https.arn
      BLUE_TG_ARN  = aws_lb_target_group.ecs.arn
      GREEN_TG_ARN = aws_lb_target_group.ecs_green.arn
    }
  }

  tags = {
    Name = "${var.project_name}-rollback-lambda"
  }
}

# CloudWatch Log Group for Rollback Lambda
resource "aws_cloudwatch_log_group" "rollback_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.rollback.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-rollback-lambda-logs"
  }
}

# Lambda Function URL for easy access (no authentication required)
resource "aws_lambda_function_url" "rollback" {
  function_name      = aws_lambda_function.rollback.function_name
  authorization_type = "NONE"
}

# Output
output "rollback_lambda_arn" {
  description = "ARN of the Rollback Lambda function"
  value       = aws_lambda_function.rollback.arn
}

output "rollback_lambda_url" {
  description = "URL to trigger Rollback Lambda (no auth required)"
  value       = aws_lambda_function_url.rollback.function_url
}




