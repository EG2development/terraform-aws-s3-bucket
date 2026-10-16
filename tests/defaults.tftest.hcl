# What a caller gets from the required input alone. These assertions pin
# names, tags and secure defaults; a change to any of them changes existing
# callers' infrastructure, which is a major release.
# The provider is mocked: no credentials, nothing created.
#
# Some attributes are Optional and Computed in the provider schema (the
# lifecycle filter's prefix; on aws 6.40 and later the encryption rule's
# kms_master_key_id and bucket_key_enabled). The module leaves them null, so a
# plan shows them as known after apply and a test cannot compare them with
# null; the resources in main.tf are the record of that configuration.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  # Realistic values where the module or an assertion reads them.
  mock_resource "aws_s3_bucket" {
    defaults = {
      id                          = "example-bucket"
      arn                         = "arn:aws:s3:::example-bucket"
      bucket_domain_name          = "example-bucket.s3.amazonaws.com"
      bucket_regional_domain_name = "example-bucket.s3.eu-west-2.amazonaws.com"
      bucket_region               = "eu-west-2"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name = "example-bucket"
  tags = { Team = "platform" }
}

run "secure_defaults" {
  command = apply

  assert {
    condition = (
      aws_s3_bucket_public_access_block.main.block_public_acls &&
      aws_s3_bucket_public_access_block.main.block_public_policy &&
      aws_s3_bucket_public_access_block.main.ignore_public_acls &&
      aws_s3_bucket_public_access_block.main.restrict_public_buckets
    )
    error_message = "Every Block Public Access setting must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.main.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Default encryption must be SSE-S3 (AES256) when no KMS key is given."
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.main) == 1 && aws_s3_bucket_versioning.main[0].versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be on by default."
  }

  assert {
    condition     = aws_s3_bucket.main.force_destroy == false
    error_message = "force_destroy must be off by default so a mistaken destroy cannot delete objects."
  }

  assert {
    condition     = length(aws_s3_bucket_logging.main) == 0
    error_message = "Server access logging is off unless access_logging is set."
  }
}

run "default_lifecycle_rule_aborts_incomplete_uploads" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.main) == 1 && length(aws_s3_bucket_lifecycle_configuration.main[0].rule) == 1
    error_message = "The default lifecycle configuration has exactly one rule."
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].expiration) == 0 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].noncurrent_version_expiration) == 0
    )
    error_message = "The default rule only aborts multipart uploads that are not complete after 7 days."
  }

  assert {
    condition = (
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].filter) == 1 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].filter[0].and) == 0 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].filter[0].tag) == 0
    )
    error_message = "The default rule has one empty filter, which applies it to every object."
  }
}

run "tls_only_bucket_policy" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_policy.main) == 1 && aws_s3_bucket_policy.main[0].policy == data.aws_iam_policy_document.main[0].json
    error_message = "The bucket policy must be attached by default, from the module's policy document."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.main[0].source_policy_documents) == 0 && length(data.aws_iam_policy_document.main[0].statement) == 1
    error_message = "With no caller policy, the document holds only the module's statement."
  }

  assert {
    condition = (
      data.aws_iam_policy_document.main[0].statement[0].effect == "Deny" &&
      data.aws_iam_policy_document.main[0].statement[0].actions == toset(["s3:*"]) &&
      data.aws_iam_policy_document.main[0].statement[0].resources == toset(["arn:aws:s3:::example-bucket", "arn:aws:s3:::example-bucket/*"]) &&
      one(data.aws_iam_policy_document.main[0].statement[0].principals).type == "*" &&
      one(data.aws_iam_policy_document.main[0].statement[0].principals).identifiers == toset(["*"])
    )
    error_message = "The TLS statement must deny every S3 action on the bucket and its objects to every principal."
  }

  assert {
    condition = (
      one(data.aws_iam_policy_document.main[0].statement[0].condition).test == "Bool" &&
      one(data.aws_iam_policy_document.main[0].statement[0].condition).variable == "aws:SecureTransport" &&
      one(data.aws_iam_policy_document.main[0].statement[0].condition).values == tolist(["false"])
    )
    error_message = "The TLS statement must apply only to requests not sent over TLS."
  }
}

run "names_and_tags_are_stable" {
  command = plan

  # Callers that adopt an existing bucket rely on these exact values; changing
  # one is a breaking change.
  assert {
    condition     = aws_s3_bucket.main.bucket == "example-bucket"
    error_message = "The bucket must be named exactly var.name, with no prefix or suffix."
  }

  assert {
    condition     = aws_s3_bucket.main.tags == tomap({ Team = "platform" })
    error_message = "Bucket tags must be exactly var.tags: the module adds no Name tag."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.main[0].rule[0].id == "abort-incomplete-multipart-uploads"
    error_message = "The default lifecycle rule id changed."
  }

  assert {
    condition     = data.aws_iam_policy_document.main[0].statement[0].sid == "DenyInsecureTransport"
    error_message = "The TLS statement Sid changed."
  }
}

run "outputs_report_the_bucket" {
  command = apply

  assert {
    condition = (
      output.bucket_id == "example-bucket" &&
      output.bucket_arn == "arn:aws:s3:::example-bucket" &&
      output.bucket_domain_name == "example-bucket.s3.amazonaws.com" &&
      output.bucket_regional_domain_name == "example-bucket.s3.eu-west-2.amazonaws.com" &&
      output.bucket_region == "eu-west-2"
    )
    error_message = "Each output must report the matching bucket attribute."
  }
}
