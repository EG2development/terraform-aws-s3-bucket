# How to move an existing bucket into the module

If your configuration already manages a bucket with its own `aws_s3_bucket*`
resources, hand them to the module with `moved` blocks. Nothing is replaced and no
object is touched.

## 1. Check the bucket's object ownership

```bash
BUCKET="payments-prod-ops-111122223333"
aws s3api get-bucket-ownership-controls --bucket "$BUCKET" \
  --query 'OwnershipControls.Rules[0].ObjectOwnership' --output text
```

It must print `BucketOwnerEnforced`. If it prints anything else, or fails with
`OwnershipControlsNotFoundError`, the bucket still uses ACLs, which the module does
not manage. Check that no reader depends on object ACLs, then disable them:

```bash
aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
```

## 2. Replace the resources with a module call

Choose the inputs that reproduce what you have:

| Your configuration | Module input |
| --- | --- |
| `bucket = "<name>"` | `name = "<name>"` |
| `force_destroy` | `force_destroy` |
| `tags` | `tags`, unchanged. The module adds none |
| An `AES256` encryption rule | Leave `kms_key_arn` unset |
| An `aws:kms` rule with a key | `kms_key_arn = "<key ARN>"`. The module also turns on the S3 Bucket Key |
| No `aws_s3_bucket_versioning` | `versioning_enabled = false` |
| `aws_s3_bucket_versioning` with `Enabled` | Leave `versioning_enabled` unset |
| Lifecycle `rule` blocks | One `lifecycle_rules` entry each, in the same order. `filter {}` is a rule without `prefix` |
| A policy with a deny on `aws:SecureTransport = false` | Leave `enforce_tls` unset; pass every other statement in `policy_json` with `attach_policy_json = true` |
| No bucket policy | `enforce_tls = false` |

For example, a staging bucket:

```hcl
module "ops_bucket" {
  source = "git::https://github.com/EG2development/terraform-aws-s3-bucket.git?ref=v1.0.0"

  name               = "payments-prod-ops-${data.aws_caller_identity.current.account_id}"
  force_destroy      = true
  versioning_enabled = false
  enforce_tls        = false
  lifecycle_rules = [
    { id = "expire-staging-objects", expiration_days = 7, abort_incomplete_multipart_upload_days = 1 },
  ]
  tags = { Project = "payments", Environment = "prod", ManagedBy = "terraform" }
}
```

## 3. Add a moved block for each resource you had

```hcl
moved {
  from = aws_s3_bucket.ops
  to   = module.ops_bucket.aws_s3_bucket.main
}

moved {
  from = aws_s3_bucket_public_access_block.ops
  to   = module.ops_bucket.aws_s3_bucket_public_access_block.main
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.ops
  to   = module.ops_bucket.aws_s3_bucket_server_side_encryption_configuration.main
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.ops
  to   = module.ops_bucket.aws_s3_bucket_lifecycle_configuration.main[0]
}
```

Add the same for `aws_s3_bucket_versioning` (to `aws_s3_bucket_versioning.main[0]`),
`aws_s3_bucket_policy` (to `aws_s3_bucket_policy.main[0]`) and
`aws_s3_bucket_logging` (to `aws_s3_bucket_logging.main[0]`) if you had them.

## 4. Plan and check

```bash
terraform init
terraform plan
```

The plan must list each resource as moved and show no changes. If it creates a
public access block or a bucket policy, your bucket did not have one: accept the
creation or match the inputs. An in-place update of the bucket policy usually means
your TLS statement had another `Sid` or shape; the module's statement is in the
[reference](../reference/resources-policy-and-permissions.md#bucket-policy). If the
plan shows any other change, or any replacement, stop and compare your inputs with
the table in step 2. Apply only a plan you have read.

## 5. Apply and tidy up

```bash
terraform apply
```

Keep the `moved` blocks until every workspace that uses the configuration has
applied them, then delete them.
