# How to receive load-balancer and CloudTrail logs

Both services write with their own identity and test their access when you point
them at the bucket. Add their statements through `policy_json`, and make the service
resource depend on the module call so the bucket policy exists first.

## Application Load Balancer access logs

Leave `kms_key_arn` unset: Elastic Load Balancing delivers access logs only to
buckets encrypted with SSE-S3.

```hcl
data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}

locals {
  alb_log_bucket = "payments-prod-alb-logs-${data.aws_caller_identity.current.account_id}"
}

data "aws_iam_policy_document" "alb_log_delivery" {
  statement {
    sid       = "AllowELBLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.alb_log_bucket}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }
}

module "alb_logs" {
  source = "git::https://github.com/EG2development/terraform-aws-s3-bucket.git?ref=v1.0.0"

  name = local.alb_log_bucket
  lifecycle_rules = [
    { id = "expire-access-logs", expiration_days = 90, noncurrent_version_expiration_days = 1, abort_incomplete_multipart_upload_days = 1 },
  ]

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.alb_log_delivery.json
}

resource "aws_lb" "main" {
  # ...
  access_logs {
    bucket  = module.alb_logs.bucket_id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [module.alb_logs]
}
```

`data.aws_elb_service_account` names the Elastic Load Balancing account of Regions
available before August 2022, such as `eu-west-2`. In a Region launched later, use a
`Service` principal, `logdelivery.elasticloadbalancing.amazonaws.com`, instead.

Check delivery after a few minutes of traffic:

```bash
BUCKET="payments-prod-alb-logs-$(aws sts get-caller-identity --query Account --output text)"
aws s3 ls "s3://${BUCKET}/alb/AWSLogs/" --recursive | head
```

The listing starts with `ELBAccessLogTestFile`, which Elastic Load Balancing writes
when you enable logging, followed by `.log.gz` files.

## CloudTrail

```hcl
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  trail_name   = "organisation-audit"
  trail_bucket = "audit-trail-${data.aws_caller_identity.current.account_id}"
  trail_arn    = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

data "aws_iam_policy_document" "trail_delivery" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.trail_bucket}"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.trail_bucket}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

module "trail_logs" {
  source = "git::https://github.com/EG2development/terraform-aws-s3-bucket.git?ref=v1.0.0"

  name               = local.trail_bucket
  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.trail_delivery.json
}

resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = module.trail_logs.bucket_id

  depends_on = [module.trail_logs]
}
```

Leave `kms_key_arn` unset on the bucket. To encrypt trail logs with your own key,
set `kms_key_id` on the trail and give CloudTrail access in that key's policy.

Check delivery with
`aws cloudtrail get-trail-status --name organisation-audit --query LatestDeliveryTime`.
