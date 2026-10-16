# The bucket policy: the caller's statements (policy_json) followed by the
# module's TLS-only statement. Whether a policy exists is decided by two
# booleans, never by the JSON, which may be unknown until apply.

locals {
  create_policy = var.enforce_tls || var.attach_policy_json

  # Built from the name, not read from aws_s3_bucket.main: a data source that
  # refers to a resource with any pending change is read only at apply, so the
  # whole policy would plan as "known after apply" whenever the bucket drifts.
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.name}"
}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "main" {
  count = local.create_policy ? 1 : 0

  source_policy_documents = var.attach_policy_json ? [var.policy_json] : []

  dynamic "statement" {
    for_each = var.enforce_tls ? ["DenyInsecureTransport"] : []

    content {
      sid       = statement.value
      effect    = "Deny"
      actions   = ["s3:*"]
      resources = [local.bucket_arn, "${local.bucket_arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["false"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "main" {
  count = local.create_policy ? 1 : 0

  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.main[0].json

  # A policy must never reach the bucket before public access is blocked.
  depends_on = [aws_s3_bucket_public_access_block.main]
}
