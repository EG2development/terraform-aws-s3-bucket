# Optional inputs change only what they say.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  # Realistic values where the module or an assertion reads them.
  mock_resource "aws_s3_bucket" {
    defaults = {
      id  = "example-bucket"
      arn = "arn:aws:s3:::example-bucket"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name = "example-bucket"
}

run "customer_managed_key" {
  command = apply

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.main.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms" &&
      one(aws_s3_bucket_server_side_encryption_configuration.main.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == "arn:aws:kms:eu-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"
    )
    error_message = "kms_key_arn must switch default encryption to SSE-KMS with that key."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.main.rule).bucket_key_enabled == true
    error_message = "SSE-KMS must use an S3 Bucket Key."
  }
}

run "versioning_off_and_force_destroy_on" {
  command = plan

  variables {
    versioning_enabled = false
    force_destroy      = true
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.main) == 0
    error_message = "versioning_enabled = false must create no versioning configuration."
  }

  assert {
    condition     = aws_s3_bucket.main.force_destroy == true
    error_message = "force_destroy must reach the bucket."
  }
}

run "lifecycle_rules_render_in_order" {
  command = plan

  variables {
    lifecycle_rules = [
      {
        id                                     = "logs"
        prefix                                 = "logs/"
        expiration_days                        = 30
        noncurrent_version_expiration_days     = 7
        abort_incomplete_multipart_upload_days = 2
      },
      { id = "paused", enabled = false, expiration_days = 365 },
    ]
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.main[0].rule : r.id] == ["logs", "paused"]
    error_message = "Rules must keep the order of lifecycle_rules, and the default rule must be replaced."
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].filter[0].prefix == "logs/" &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].expiration[0].days == 30 &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 7 &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 2
    )
    error_message = "Every field of a rule must reach its block."
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.main[0].rule[1].status == "Disabled" &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[1].expiration[0].days == 365 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[1].noncurrent_version_expiration) == 0 &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[1].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    )
    error_message = "enabled = false must disable the rule; unset actions are left out, except the abort default of 7 days."
  }
}

run "no_lifecycle_rules" {
  command = plan

  variables {
    lifecycle_rules = []
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.main) == 0
    error_message = "An empty lifecycle_rules list must create no lifecycle configuration."
  }
}

run "access_logging" {
  command = plan

  variables {
    access_logging = { target_bucket = "example-access-logs", target_prefix = "example-bucket/" }
  }

  assert {
    condition = (
      length(aws_s3_bucket_logging.main) == 1 &&
      aws_s3_bucket_logging.main[0].target_bucket == "example-access-logs" &&
      aws_s3_bucket_logging.main[0].target_prefix == "example-bucket/"
    )
    error_message = "access_logging must reach the logging configuration."
  }
}

run "access_logging_default_prefix" {
  command = plan

  variables {
    access_logging = { target_bucket = "example-access-logs" }
  }

  assert {
    condition     = aws_s3_bucket_logging.main[0].target_prefix == ""
    error_message = "target_prefix defaults to the empty string (the target bucket's root)."
  }
}

run "no_policy_without_tls_or_caller_policy" {
  command = plan

  variables {
    enforce_tls = false
  }

  assert {
    condition     = length(aws_s3_bucket_policy.main) == 0 && length(data.aws_iam_policy_document.main) == 0
    error_message = "enforce_tls = false with no caller policy must attach no bucket policy."
  }
}

run "caller_policy_is_merged_with_the_tls_statement" {
  command = plan

  variables {
    attach_policy_json = true
    policy_json        = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Read\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::444455556666:root\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::example-bucket/*\"}]}"
  }

  assert {
    condition     = data.aws_iam_policy_document.main[0].source_policy_documents == tolist([var.policy_json])
    error_message = "policy_json must be the source document of the bucket policy."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.main[0].statement) == 1 && data.aws_iam_policy_document.main[0].statement[0].sid == "DenyInsecureTransport"
    error_message = "The TLS statement must be added to the caller's statements."
  }
}

run "caller_policy_without_the_tls_statement" {
  command = plan

  variables {
    enforce_tls        = false
    attach_policy_json = true
    policy_json        = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Read\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::444455556666:root\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::example-bucket/*\"}]}"
  }

  assert {
    condition     = length(aws_s3_bucket_policy.main) == 1 && length(data.aws_iam_policy_document.main[0].statement) == 0
    error_message = "With enforce_tls = false the policy holds only the caller's statements."
  }
}

run "caller_tags_pass_through_unchanged" {
  command = plan

  variables {
    tags = { Name = "reports", Project = "example" }
  }

  assert {
    condition     = aws_s3_bucket.main.tags == tomap({ Name = "reports", Project = "example" })
    error_message = "var.tags must reach the bucket unchanged, including a Name tag that differs from the bucket name."
  }
}

# The flag, not the JSON, decides whether the policy exists, so a policy that
# names a role created in the same apply (unknown at plan time) still plans.
# The run passes when the plan succeeds: a count driven by the JSON would
# fail with "Invalid count argument".
run "policy_may_be_unknown_at_plan_time" {
  command = plan

  module {
    source = "./tests/fixtures/policy-from-new-role"
  }
}
