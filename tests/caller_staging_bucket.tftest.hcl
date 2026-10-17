# A bucket shape existing callers already run, rendered by this module: a
# staging bucket. Callers move their resources into the module with moved
# blocks; their plan must then show no change, so these values are a
# compatibility contract. Each such shape has its own file, so each starts
# from empty state.
#
# This file uses the real provider, offline: it validates the rendered
# configuration and renders the bucket policy with the real
# aws_iam_policy_document, so the JSON S3 would receive is asserted exactly.
# Every resource is overridden, the credentials are fake, and the S3 and STS
# endpoints point at a closed local port: nothing can reach AWS.

provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "offline-test"
  secret_key                  = "offline-test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true

  endpoints {
    s3  = "http://127.0.0.1:1"
    sts = "http://127.0.0.1:1"
  }
}

override_resource {
  target = aws_s3_bucket_public_access_block.main
}

override_resource {
  target = aws_s3_bucket_server_side_encryption_configuration.main
}

override_resource {
  target = aws_s3_bucket_versioning.main
}

override_resource {
  target = aws_s3_bucket_lifecycle_configuration.main
}

override_resource {
  target = aws_s3_bucket_policy.main
}

override_resource {
  target = aws_s3_bucket_logging.main
}

# A bucket for short-lived staging files: emptied on destroy, no versioning,
# no bucket policy, objects expire after 7 days.
run "staging_bucket" {
  command = apply

  variables {
    name               = "example-prod-ops-111122223333"
    force_destroy      = true
    versioning_enabled = false
    enforce_tls        = false
    lifecycle_rules = [
      { id = "expire-staging-objects", expiration_days = 7, abort_incomplete_multipart_upload_days = 1 },
    ]
    tags = { Project = "x", Environment = "prod", ManagedBy = "terraform" }
  }

  override_resource {
    target = aws_s3_bucket.main
    values = { id = "example-prod-ops-111122223333", arn = "arn:aws:s3:::example-prod-ops-111122223333" }
  }

  assert {
    condition = (
      length(aws_s3_bucket_lifecycle_configuration.main) == 1 &&
      length(aws_s3_bucket_versioning.main) == 0 &&
      length(aws_s3_bucket_policy.main) == 0 &&
      length(data.aws_iam_policy_document.main) == 0 &&
      length(aws_s3_bucket_logging.main) == 0
    )
    error_message = "Exactly four resources: bucket, public access block, encryption and lifecycle configuration. No policy, no versioning, no logging."
  }

  assert {
    condition = (
      aws_s3_bucket.main.bucket == "example-prod-ops-111122223333" &&
      aws_s3_bucket.main.force_destroy == true &&
      aws_s3_bucket.main.tags == tomap({ Project = "x", Environment = "prod", ManagedBy = "terraform" })
    )
    error_message = "The bucket must have the caller's name, force_destroy and exactly the caller's three tags."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.main.block_public_acls && aws_s3_bucket_public_access_block.main.block_public_policy &&
      aws_s3_bucket_public_access_block.main.ignore_public_acls && aws_s3_bucket_public_access_block.main.restrict_public_buckets
    )
    error_message = "All four Block Public Access settings must be on."
  }

  assert {
    condition = (
      length(aws_s3_bucket_server_side_encryption_configuration.main.rule) == 1 &&
      one(aws_s3_bucket_server_side_encryption_configuration.main.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    )
    error_message = "Encryption must be one SSE-S3 (AES256) rule."
  }

  # The module leaves bucket_key_enabled and the filter's prefix null. Both are
  # computed attributes, so after this apply they hold generated values, not
  # null; the assertions rule out what would be a different configuration.
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.main.rule).bucket_key_enabled != true
    error_message = "No S3 Bucket Key may be configured for SSE-S3."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.main[0].rule[0].filter[0].prefix != ""
    error_message = "The filter must be empty (filter {}), not a filter with an empty prefix."
  }

  assert {
    condition = (
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule) == 1 &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].id == "expire-staging-objects" &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].status == "Enabled" &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].filter) == 1 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].expiration) == 1 &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].expiration[0].days == 7 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].abort_incomplete_multipart_upload) == 1 &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 1 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].noncurrent_version_expiration) == 0 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].transition) == 0
    )
    error_message = "The lifecycle configuration must be exactly: rule expire-staging-objects, Enabled, filter {}, expiration 7 days, abort incomplete uploads after 1 day."
  }
}
