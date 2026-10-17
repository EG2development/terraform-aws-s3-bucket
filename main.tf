# Resource names are "main" so that a caller migrating from its own bucket
# resources can move them here with moved blocks and keep stable addresses
# afterwards. Renaming one is a breaking change and needs a moved block.

resource "aws_s3_bucket" "main" {
  bucket        = var.name
  force_destroy = var.force_destroy

  # No Name tag: the bucket name is the bucket's identity, and callers that
  # adopt an existing bucket must not see a tag change.
  tags = var.tags
}

# Every setting on, always. A bucket that must be public does not belong in
# this module.
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 unless a key is given. With no key, kms_master_key_id and
# bucket_key_enabled stay null, so the configuration is exactly
# rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }.
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    # A Bucket Key cuts KMS requests (and their cost) by reusing a bucket-level
    # data key. It means nothing for SSE-S3.
    bucket_key_enabled = var.kms_key_arn == null ? null : true
  }
}

resource "aws_s3_bucket_versioning" "main" {
  count = var.versioning_enabled ? 1 : 0

  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.main.id

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id = rule.value.id

      # Disabled only when the caller says so. Written this way, rather than
      # "enabled ? ...", so scanners that ignore the type's default of true
      # still see an enabled rule.
      status = rule.value.enabled == false ? "Disabled" : "Enabled"

      # A null prefix renders an empty filter {}, which applies the rule to
      # every object in the bucket.
      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days == null ? [] : [rule.value.expiration_days]

        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days == null ? [] : [rule.value.noncurrent_version_expiration_days]

        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      # Always present: the variable's type defaults this value to 7 days,
      # even when a caller sets it to null.
      abort_incomplete_multipart_upload {
        days_after_initiation = rule.value.abort_incomplete_multipart_upload_days
      }
    }
  }

  # Rules for noncurrent versions need versioning to be configured first.
  depends_on = [aws_s3_bucket_versioning.main]
}

# The object passed in access_logging is built in the caller's configuration,
# so whether it is null is known at plan time even when target_bucket is not.
resource "aws_s3_bucket_logging" "main" {
  count = var.access_logging != null ? 1 : 0

  bucket        = aws_s3_bucket.main.id
  target_bucket = var.access_logging.target_bucket
  target_prefix = var.access_logging.target_prefix
}
