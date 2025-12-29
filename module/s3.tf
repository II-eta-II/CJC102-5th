# =============================================================================
# S3 Bucket for WordPress Media Offload
# =============================================================================

resource "aws_s3_bucket" "media_offload" {
  bucket        = "${var.project_name}-media-${var.subdomain}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-media-offload"
  }
}

# S3 Bucket Versioning for Media
resource "aws_s3_bucket_versioning" "media_offload" {
  bucket = aws_s3_bucket.media_offload.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption for Media
resource "aws_s3_bucket_server_side_encryption_configuration" "media_offload" {
  bucket = aws_s3_bucket.media_offload.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block for Media
resource "aws_s3_bucket_public_access_block" "media_offload" {
  bucket = aws_s3_bucket.media_offload.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket Policy for Media (Public Read)
resource "aws_s3_bucket_policy" "media_offload" {
  bucket     = aws_s3_bucket.media_offload.id
  depends_on = [aws_s3_bucket_public_access_block.media_offload]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.media_offload.arn}/*"
      }
    ]
  })
}

# S3 Bucket CORS Configuration for Media
resource "aws_s3_bucket_cors_configuration" "media_offload" {
  bucket = aws_s3_bucket.media_offload.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
