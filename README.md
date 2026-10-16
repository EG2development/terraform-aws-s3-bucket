# terraform-aws-s3-bucket

A Terraform module for one private, general purpose Amazon S3 bucket with secure
defaults: every Block Public Access setting on, default encryption (SSE-S3, or
SSE-KMS with an S3 Bucket Key when you give a key), a bucket policy that denies
requests not sent over TLS, versioning, and a lifecycle rule that aborts incomplete
multipart uploads.

Use it for application data, reports, staging files and log archives: anything that
must never be public. You do not need to know anything about the project it came
from.

It deliberately does **not** manage:

- **Who may read and write.** Grant access in your own IAM policies with the
  `bucket_arn` output, or add bucket policy statements through `policy_json`.
- **KMS keys and log buckets.** Create them next to the module call and pass them in.
  A second call of this module makes a good log bucket.
- **Public access, websites, replication, Object Lock and event notifications.** See
  [design decisions](docs/explanation/design-decisions.md) for why.
- **Provider configuration and state.** There is no `provider` or `backend` block.

## Usage

```hcl
module "bucket" {
  source = "git::https://github.com/EG2development/terraform-aws-s3-bucket.git?ref=v1.0.0" # x-release-please-version

  name = "payments-prod-reports-111122223333"
}
```

Pin `?ref=`
to a release tag (inside the organisation) or the release's full commit SHA (outside
it), never to a branch. Run `terraform init` after changing `source`.

## Examples

| Example | Shows |
| --- | --- |
| [`examples/basic`](examples/basic) | One bucket with the defaults |
| [`examples/complete`](examples/complete) | A data bucket encrypted with a customer managed key, versioned, with old versions expired after 90 days and read access for an IAM role, whose server access logs go to a second bucket made by a second call of the module |

## Documentation

| You want to | Read |
| --- | --- |
| Create your first bucket and watch it refuse plain HTTP | [Tutorial: create your first bucket](docs/tutorials/create-your-first-bucket.md) |
| Let another role or account read or write | [How to grant access with a bucket policy](docs/how-to/grant-access-with-a-bucket-policy.md) |
| Receive load-balancer access logs or CloudTrail logs | [How to receive load-balancer and CloudTrail logs](docs/how-to/receive-load-balancer-and-cloudtrail-logs.md) |
| Hand bucket resources you already manage to the module | [How to move an existing bucket into the module](docs/how-to/move-an-existing-bucket-into-the-module.md) |
| Look up every resource, policy statement and permission | [Reference: resources, bucket policy and permissions](docs/reference/resources-policy-and-permissions.md) |
| See the resources and how they connect, on one page | [Architecture diagram](docs/reference/architecture.png) |
| Understand why it is built this way | [Design decisions](docs/explanation/design-decisions.md) |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| aws | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_policy.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the bucket. Bucket names are shared by every AWS account in the partition, so include something unique, such as the account ID. The module adds no Name tag: the bucket name is the bucket's identity. Changing it replaces the bucket. | `string` | n/a | yes |
| access\_logging | Server access logging: S3 writes a record of each request to target\_bucket, under target\_prefix (default "", the bucket root). The target bucket must be another bucket in the same account and Region, use SSE-S3, and allow the logging.s3.amazonaws.com service principal to write in its bucket policy. Null (default) turns access logging off. | <pre>object({<br/>    target_bucket = string<br/>    target_prefix = optional(string, "")<br/>  })</pre> | `null` | no |
| attach\_policy\_json | Merge policy\_json into the bucket policy. A separate flag, rather than a null check on the JSON, so the decision is known at plan time even when the policy names resources created in the same apply. | `bool` | `false` | no |
| enforce\_tls | Add a bucket policy statement, DenyInsecureTransport, that denies every request not sent over TLS. On by default. Setting it to false allows requests over plain HTTP. | `bool` | `true` | no |
| force\_destroy | Let Terraform delete every object and object version when it destroys the bucket, so a destroy succeeds on a bucket that is not empty. Dangerous: a mistaken destroy, or a change that replaces the bucket, then deletes the data for good. Default false. It takes effect only after an apply has recorded it in state. | `bool` | `false` | no |
| kms\_key\_arn | ARN of a customer managed KMS key for default encryption (SSE-KMS with an S3 Bucket Key). Null (default) uses SSE-S3 (AES256). A key ARN, not an alias: S3 resolves an alias in the account of whoever writes, which may not be the bucket owner. Writers and readers need kms:GenerateDataKey and kms:Decrypt on the key. Load-balancer access logs and S3 server access logs can only be delivered to an SSE-S3 bucket. | `string` | `null` | no |
| lifecycle\_rules | Lifecycle rules, applied in this order. Each rule has an id (unique, 1-255 characters), optional enabled (default true), optional prefix (null, the default, applies the rule to every object), and actions in whole days: expiration\_days (expire current versions; on a versioned bucket this adds a delete marker), noncurrent\_version\_expiration\_days (delete versions that stopped being current that many days ago) and abort\_incomplete\_multipart\_upload\_days (default 7). The default is one rule, "abort-incomplete-multipart-uploads", that only removes the parts of uploads not completed within 7 days. Passing a list replaces the default rule. An empty list creates no lifecycle configuration. | <pre>list(object({<br/>    id                                     = string<br/>    enabled                                = optional(bool, true)<br/>    prefix                                 = optional(string)<br/>    expiration_days                        = optional(number)<br/>    noncurrent_version_expiration_days     = optional(number)<br/>    abort_incomplete_multipart_upload_days = optional(number, 7)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "id": "abort-incomplete-multipart-uploads"<br/>  }<br/>]</pre> | no |
| policy\_json | A JSON policy document whose statements are added to the bucket policy, for example the json of an aws\_iam\_policy\_document data source. Used only when attach\_policy\_json is true. A statement with the Sid DenyInsecureTransport is replaced by the module's own. S3 rejects a statement that would make the bucket public, because public access is blocked. | `string` | `null` | no |
| tags | Tags for the bucket. The module adds no tags of its own, not even Name: the bucket name identifies the bucket. Tags from the provider's default\_tags apply as usual. | `map(string)` | `{}` | no |
| versioning\_enabled | Keep every version of every object, so an overwritten or deleted object can be restored. On by default. Setting it to false on an existing bucket suspends versioning (S3 cannot switch it off once enabled) and keeps the versions that already exist. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the bucket, for IAM and bucket policies. An object's ARN is this ARN, a slash and the object key. |
| bucket\_domain\_name | Global domain name of the bucket: the bucket name followed by .s3.amazonaws.com. |
| bucket\_id | Name of the bucket (S3 uses the name as the ID). Known at plan time. |
| bucket\_region | AWS Region the bucket is in. |
| bucket\_regional\_domain\_name | Regional domain name of the bucket, for example for a CloudFront origin. |
<!-- END_TF_DOCS -->

## Defaults and security decisions

| Decision | Default | Why | How to change it |
| --- | --- | --- | --- |
| Block Public Access | All four settings on | No policy or ACL can make the bucket public | Not configurable |
| Encryption at rest | SSE-S3 (`AES256`) | Every AWS log-delivery service can write to it; no key to manage | `kms_key_arn` for SSE-KMS with an S3 Bucket Key |
| Transport | `DenyInsecureTransport` denies every request not sent over TLS | Data and signed requests never cross the network in clear text | `enforce_tls = false` |
| Versioning | On | An overwritten or deleted object can be restored | `versioning_enabled = false` |
| Lifecycle | One rule: abort incomplete multipart uploads after 7 days | Parts of failed uploads are billed but invisible | `lifecycle_rules` |
| ACLs | Disabled: S3's default object ownership for new buckets, `BucketOwnerEnforced` | Access is decided by policies alone | Not managed by the module |
| Deletion | `force_destroy = false` | A destroy fails while the bucket holds objects | `force_destroy = true` (dangerous) |
| Tags | Exactly `tags`; no `Name` tag | The bucket name is the bucket's identity | `tags` |
| Server access logging | Off | Needs a second bucket | `access_logging` |

## Security scanning

Checkov runs on every pull request. Two checks are skipped, in
[`.github/workflows/ci.yml`](.github/workflows/ci.yml):

| Check | Why it is skipped |
| --- | --- |
| `CKV_AWS_144` "S3 bucket has cross-region replication enabled" | Replication needs a bucket in another Region, an IAM role and a decision about what to copy, so it is out of scope. Versioning, which replication needs, is on by default; add `aws_s3_bucket_replication_configuration` next to the module call |
| `CKV2_AWS_62` "S3 buckets should have event notifications enabled" | Notifications go to a consumer (a queue, topic, function or EventBridge) that only the caller knows; add `aws_s3_bucket_notification` next to the module call |

## Upgrading

Read [`CHANGELOG.md`](CHANGELOG.md) for every version between yours and the new one,
change `?ref=`, run `terraform init`, and review the plan. A minor or patch release
plans no changes unless you opt into something new. To hand a bucket you already
manage to the module without replacing it, follow
[How to move an existing bucket into the module](docs/how-to/move-an-existing-bucket-into-the-module.md).

## Versioning and releases

Semantic versions, tags `vMAJOR.MINOR.PATCH`, created by release-please from
Conventional Commit pull-request titles. Patch: a fix that changes no plan. Minor: a
new optional input, output or off-by-default resource. Major: anything that can
change or replace an existing caller's resources, or raise a minimum version.
Details: [the standard](https://github.com/EG2development/terraform-module-standards/blob/main/docs/standard.md).

## Contributing and ownership

See [`CONTRIBUTING.md`](CONTRIBUTING.md). The team in
[`.github/CODEOWNERS`](.github/CODEOWNERS) reviews every change and owns releases.
Report vulnerabilities as described in [`SECURITY.md`](SECURITY.md).
