# The bucket policy as S3 would receive it, in each mode the module offers.
#
# This file uses the real provider, offline, so the policy JSON is rendered by
# the real aws_iam_policy_document. Every resource is overridden, the
# credentials are fake, and the S3 and STS endpoints point at a closed local
# port: nothing can reach AWS. Every run uses the same bucket, so the
# bucket's ARN is fixed for the whole file.

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
  target = aws_s3_bucket.main
  values = { id = "example-bucket", arn = "arn:aws:s3:::example-bucket" }
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

variables {
  name = "example-bucket"
}

run "default_policy_is_tls_only" {
  command = apply

  assert {
    condition = jsondecode(aws_s3_bucket_policy.main[0].policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource  = jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[0].Resource
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        },
      ]
    }
    error_message = "The default policy must hold only the DenyInsecureTransport statement."
  }

  assert {
    condition     = toset(jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[0].Resource) == toset(["arn:aws:s3:::example-bucket", "arn:aws:s3:::example-bucket/*"])
    error_message = "DenyInsecureTransport must cover the bucket and every object in it."
  }
}

run "caller_statements_only_when_tls_is_not_enforced" {
  command = apply

  variables {
    enforce_tls        = false
    attach_policy_json = true
    policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "ReadFromPartner"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::444455556666:root" }
          Action    = "s3:GetObject"
          Resource  = "arn:aws:s3:::example-bucket/*"
        },
      ]
    })
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.main[0].policy).Statement : s.Sid] == ["ReadFromPartner"]
    error_message = "With enforce_tls = false the policy must hold only the caller's statements."
  }
}

run "caller_statement_named_deny_insecure_transport_is_replaced" {
  command = apply

  variables {
    attach_policy_json = true
    policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::444455556666:root" }
          Action    = "s3:GetObject"
          Resource  = "arn:aws:s3:::example-bucket/*"
        },
      ]
    })
  }

  assert {
    condition = (
      length(jsondecode(aws_s3_bucket_policy.main[0].policy).Statement) == 1 &&
      jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.main[0].policy).Statement[0].Principal == "*"
    )
    error_message = "A caller statement with the Sid DenyInsecureTransport must be replaced by the module's own."
  }
}
