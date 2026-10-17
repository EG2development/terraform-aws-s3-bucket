# How to grant access with a bucket policy

Add statements to the bucket policy through `policy_json`. The module puts them
before its own `DenyInsecureTransport` statement. For principals in the bucket's own
account, an IAM policy on the principal is enough; use the bucket policy for other
accounts and for AWS services.

## Let a role in another account read objects

1. Build the statements with `aws_iam_policy_document` and pass them to the module:

   ```hcl
   data "aws_iam_policy_document" "read" {
     statement {
       sid       = "ReadFromAnalytics"
       actions   = ["s3:GetObject", "s3:ListBucket"]
       resources = [module.bucket.bucket_arn, "${module.bucket.bucket_arn}/*"]

       principals {
         type        = "AWS"
         identifiers = ["arn:aws:iam::444455556666:role/analytics-reader"]
       }
     }
   }

   module "bucket" {
     # ...
     attach_policy_json = true
     policy_json        = data.aws_iam_policy_document.read.json
   }
   ```

   Set `attach_policy_json = true` as a literal, even when the policy names a role
   that the same configuration creates.

2. If the bucket uses `kms_key_arn`, add a statement to the key policy that allows
   the role `kms:Decrypt`, as
   [`examples/complete`](../../examples/complete/main.tf) does with
   `ReaderDecryptThroughS3`.
3. In the other account, give the role an IAM policy that allows the same actions on
   the same resources. Cross-account access needs both sides.
4. Run `terraform plan`. Check it shows only `aws_s3_bucket_policy.main[0]` being
   created or updated in place, then apply.
5. From the other account, as the role:

   ```bash
   aws s3 ls "s3://${BUCKET}/"
   ```

## Let an AWS service write

Use a `Service` principal and limit it to your resources with `aws:SourceAccount` and
`aws:SourceArn` conditions. The complete example's
`S3ServerAccessLogDelivery` statement is a working pattern. For load balancers and
CloudTrail, follow
[How to receive load-balancer and CloudTrail logs](receive-load-balancer-and-cloudtrail-logs.md).

## If S3 rejects the policy

`PutBucketPolicy` fails with `AccessDenied` when a statement would make the bucket
public, for example `"Principal": "*"` on an `Allow` with no restricting condition.
Name the principals, or add a condition such as `aws:PrincipalOrgID`.
