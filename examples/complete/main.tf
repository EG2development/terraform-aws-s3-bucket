# A production-style pair of buckets. The data bucket is encrypted with a
# customer managed KMS key, versioned, removes old versions after 90 days,
# lets one IAM role read, and sends server access logs to a second bucket.
# The log bucket is a second call of the same module.

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # Built from the names, which are known at plan time, so neither bucket's
  # policy has to wait for the other bucket to exist.
  bucket_arn        = "arn:${data.aws_partition.current.partition}:s3:::${var.name}"
  log_bucket_name   = "${var.name}-access-logs"
  log_bucket_arn    = "arn:${data.aws_partition.current.partition}:s3:::${local.log_bucket_name}"
  access_log_prefix = "${var.name}/"
}

# ---------------------------------------------------------------------------
# Access-log bucket
# ---------------------------------------------------------------------------

# S3 delivers server access logs as the logging service principal. Only the
# data bucket in this account may cause a delivery (confused-deputy
# protection), and only under its prefix.
data "aws_iam_policy_document" "access_log_delivery" {
  statement {
    sid       = "S3ServerAccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${local.log_bucket_arn}/${local.access_log_prefix}*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bucket_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

module "access_logs" {
  source = "../.."

  # No kms_key_arn: S3 server access logs can only be delivered to a bucket
  # whose default encryption is SSE-S3.
  name = local.log_bucket_name

  lifecycle_rules = [
    { id = "expire-access-logs", expiration_days = 365, noncurrent_version_expiration_days = 30 },
  ]

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.access_log_delivery.json

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Data bucket and its key
# ---------------------------------------------------------------------------

# Customer managed key. The account's IAM policies govern who may use it; the
# reader role may also decrypt, but only through S3 and only for this bucket
# (with an S3 Bucket Key the encryption context is the bucket ARN).
resource "aws_kms_key" "bucket" {
  description         = "${var.name} S3 bucket"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "ReaderDecryptThroughS3"
        Effect    = "Allow"
        Principal = { AWS = var.reader_role_arn }
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"                   = "s3.${var.region}.amazonaws.com"
            "kms:EncryptionContext:aws:s3:arn" = local.bucket_arn
          }
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "reader" {
  statement {
    sid       = "ReadFromRole"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arn, "${local.bucket_arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [var.reader_role_arn]
    }
  }
}

module "bucket" {
  source = "../.."

  name        = var.name
  kms_key_arn = aws_kms_key.bucket.arn

  # Replaces the default rule; abort_incomplete_multipart_upload_days keeps
  # its default of 7 in this rule.
  lifecycle_rules = [
    { id = "expire-noncurrent-versions", noncurrent_version_expiration_days = 90 },
  ]

  access_logging = {
    target_bucket = module.access_logs.bucket_id
    target_prefix = local.access_log_prefix
  }

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.reader.json

  tags = var.tags
}
