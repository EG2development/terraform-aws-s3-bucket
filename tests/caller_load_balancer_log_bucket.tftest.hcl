# A bucket shape existing callers already run, rendered by this module: a
# bucket for load-balancer access logs. Callers move their resources into the
# module with moved blocks; their plan must then show no change, so these
# values are a compatibility contract. Each such shape has its own file, so
# each starts from empty state.
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

# A bucket that receives load-balancer access logs: SSE-S3 (the only
# encryption ELB log delivery supports), no versioning, objects expire after
# 90 days, and a policy that lets the eu-west-2 ELB account write.
run "load_balancer_log_bucket" {
  command = apply

  variables {
    name               = "example-prod-alb-logs-111122223333"
    versioning_enabled = false
    enforce_tls        = true
    attach_policy_json = true
    policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AllowELBLogDelivery"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::652711504416:root" }
          Action    = "s3:PutObject"
          Resource  = "arn:aws:s3:::example-prod-alb-logs-111122223333/alb/AWSLogs/111122223333/*"
        },
      ]
    })
    lifecycle_rules = [
      { id = "expire-access-logs", expiration_days = 90, abort_incomplete_multipart_upload_days = 1 },
    ]
    tags = { Project = "x", Environment = "prod", ManagedBy = "terraform", Name = "example-prod-alb-logs" }
  }

  override_resource {
    target = aws_s3_bucket.main
    values = { id = "example-prod-alb-logs-111122223333", arn = "arn:aws:s3:::example-prod-alb-logs-111122223333" }
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.main) == 0 && length(aws_s3_bucket_policy.main) == 1 && length(aws_s3_bucket_logging.main) == 0
    error_message = "No versioning, one bucket policy, no logging."
  }

  assert {
    condition     = aws_s3_bucket.main.force_destroy == false && aws_s3_bucket.main.tags["Name"] == "example-prod-alb-logs"
    error_message = "force_destroy stays off, and a caller's Name tag that differs from the bucket name is kept."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.main.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "A load-balancer log bucket must use SSE-S3."
  }

  assert {
    condition = (
      [for r in aws_s3_bucket_lifecycle_configuration.main[0].rule : r.id] == ["expire-access-logs"] &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].expiration[0].days == 90 &&
      aws_s3_bucket_lifecycle_configuration.main[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 1 &&
      length(aws_s3_bucket_lifecycle_configuration.main[0].rule[0].noncurrent_version_expiration) == 0
    )
    error_message = "The lifecycle configuration must be exactly: rule expire-access-logs, expiration 90 days, abort incomplete uploads after 1 day."
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.main[0].policy).Statement) == 2
    error_message = "The bucket policy must hold exactly two statements."
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[0] == {
      Sid       = "AllowELBLogDelivery"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::652711504416:root" }
      Action    = "s3:PutObject"
      Resource  = "arn:aws:s3:::example-prod-alb-logs-111122223333/alb/AWSLogs/111122223333/*"
    }
    error_message = "The first statement must be the caller's AllowELBLogDelivery statement, unchanged."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[1].Sid == "DenyInsecureTransport" &&
      jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[1].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[1].Principal == "*" &&
      jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[1].Action == "s3:*" &&
      toset(jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[1].Resource) == toset(["arn:aws:s3:::example-prod-alb-logs-111122223333", "arn:aws:s3:::example-prod-alb-logs-111122223333/*"]) &&
      jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[1].Condition == { Bool = { "aws:SecureTransport" = "false" } }
    )
    error_message = "The second statement must be DenyInsecureTransport: deny s3:* on the bucket and its objects to everyone when aws:SecureTransport is false."
  }
}
