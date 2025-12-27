# =============================================================================
# CodeBuild CI/CD Pipeline
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "enable_cicd" {
  description = "Enable CI/CD pipeline for Docker image builds"
  type        = bool
  default     = false
}

variable "github_repo_owner" {
  description = "GitHub repository owner (user or organization)"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch to trigger builds"
  type        = string
  default     = "main"
}



# -----------------------------------------------------------------------------
# CodeStar Connection for GitHub
# -----------------------------------------------------------------------------

resource "aws_codestarconnections_connection" "github" {
  count         = var.enable_cicd ? 1 : 0
  name          = "${var.project_name}-github-connection"
  provider_type = "GitHub"

  tags = {
    Name = "${var.project_name}-github-connection"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket for Pipeline Artifacts
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "codepipeline_artifacts" {
  count  = var.enable_cicd ? 1 : 0
  bucket = "${var.project_name}-codepipeline-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-codepipeline-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "codepipeline_artifacts" {
  count  = var.enable_cicd ? 1 : 0
  bucket = aws_s3_bucket.codepipeline_artifacts[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for CodeBuild
# -----------------------------------------------------------------------------

resource "aws_iam_role" "codebuild" {
  count = var.enable_cicd ? 1 : 0
  name  = "${var.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project_name}-codebuild-role"
  }
}

resource "aws_iam_role_policy" "codebuild" {
  count = var.enable_cicd ? 1 : 0
  name  = "${var.project_name}-codebuild-policy"
  role  = aws_iam_role.codebuild[0].id

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
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.codepipeline_artifacts[0].arn}/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CodeBuild Project
# -----------------------------------------------------------------------------

resource "aws_codebuild_project" "docker_build" {
  count         = var.enable_cicd ? 1 : 0
  name          = "${var.project_name}-docker-build"
  description   = "Build Docker image and push to ECR"
  build_timeout = 30
  service_role  = aws_iam_role.codebuild[0].arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.wordpress.repository_url
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOF
      version: 0.2
      phases:
        pre_build:
          commands:
            - echo Logging in to Amazon ECR...
            - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
        build:
          commands:
            - echo Build started on `date`
            - echo Building the Docker image...
            - docker build -t $ECR_REPOSITORY_URI:$IMAGE_TAG .
            - docker tag $ECR_REPOSITORY_URI:$IMAGE_TAG $ECR_REPOSITORY_URI:$CODEBUILD_RESOLVED_SOURCE_VERSION
        post_build:
          commands:
            - echo Build completed on `date`
            - echo Pushing the Docker image...
            - docker push $ECR_REPOSITORY_URI:$IMAGE_TAG
            - docker push $ECR_REPOSITORY_URI:$CODEBUILD_RESOLVED_SOURCE_VERSION
            - echo Writing image definitions file...
            - printf '[{"name":"wordpress","imageUri":"%s"}]' $ECR_REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json
      artifacts:
        files:
          - imagedefinitions.json
    EOF
  }

  tags = {
    Name = "${var.project_name}-docker-build"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for CodePipeline
# -----------------------------------------------------------------------------

resource "aws_iam_role" "codepipeline" {
  count = var.enable_cicd ? 1 : 0
  name  = "${var.project_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project_name}-codepipeline-role"
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  count = var.enable_cicd ? 1 : 0
  name  = "${var.project_name}-codepipeline-policy"
  role  = aws_iam_role.codepipeline[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.codepipeline_artifacts[0].arn,
          "${aws_s3_bucket.codepipeline_artifacts[0].arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = aws_codebuild_project.docker_build[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = aws_codestarconnections_connection.github[0].arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CodePipeline
# -----------------------------------------------------------------------------

resource "aws_codepipeline" "main" {
  count    = var.enable_cicd ? 1 : 0
  name     = "${var.project_name}-docker-pipeline"
  role_arn = aws_iam_role.codepipeline[0].arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts[0].bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github[0].arn
        FullRepositoryId = "${var.github_repo_owner}/${var.github_repo_name}"
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.docker_build[0].name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-docker-pipeline"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = var.enable_cicd ? aws_codepipeline.main[0].name : null
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = var.enable_cicd ? aws_codebuild_project.docker_build[0].name : null
}

output "codestar_connection_arn" {
  description = "ARN of the CodeStar connection for GitHub (must be activated in AWS Console)"
  value       = var.enable_cicd ? aws_codestarconnections_connection.github[0].arn : null
}
