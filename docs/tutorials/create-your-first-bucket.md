# Tutorial: create your first bucket

In this tutorial you create a bucket, upload an object, watch the bucket refuse the
same request sent over plain HTTP, and remove everything again. It takes about ten
minutes and costs a fraction of a penny: a few requests and a few bytes of storage.

## Before you start

- Terraform 1.16 or later, the AWS CLI version 2, `curl`, and credentials for a
  sandbox AWS account that may create S3 buckets and bucket policies.
- Read access to this repository (`git ls-remote https://github.com/EG2development/terraform-aws-s3-bucket.git`
  lists its tags).

## 1. Write the configuration

Create an empty directory and a file `main.tf` in it:

```hcl
terraform {
  required_version = ">= 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.40"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

data "aws_caller_identity" "current" {}

module "bucket" {
  source = "git::https://github.com/EG2development/terraform-aws-s3-bucket.git?ref=v1.0.0"

  # Bucket names are shared by every AWS account; your account ID makes this one yours.
  name = "tutorial-${data.aws_caller_identity.current.account_id}"
}

output "bucket" {
  value = module.bucket.bucket_id
}
```

## 2. Create the bucket

```bash
terraform init
terraform apply
```

Read the plan before you type `yes`. You should see six resources: the bucket, its
public access block, encryption configuration, versioning configuration, lifecycle
configuration and bucket policy.

## 3. Upload an object

```bash
export AWS_REGION=eu-west-2
BUCKET="$(terraform output -raw bucket)"
echo "hello" > hello.txt
VERSION_ID="$(aws s3api put-object --bucket "$BUCKET" --key hello.txt --body hello.txt --query VersionId --output text)"
aws s3api head-object --bucket "$BUCKET" --key hello.txt --query ServerSideEncryption --output text
```

The last command prints `AES256`: S3 encrypted the object with the bucket's default
encryption, although you did not ask for it.

## 4. Send the same request over HTTPS and over HTTP

A presigned URL lets `curl` send a signed request. The signature does not cover the
scheme, so the same URL can be sent over HTTPS and over plain HTTP.

```bash
URL="$(aws s3 presign "s3://${BUCKET}/hello.txt" --expires-in 300)"
curl -s "$URL"
curl -s "${URL/https:/http:}"
```

The first request prints `hello`. The second prints an XML error with the code
`AccessDenied`: the bucket policy's `DenyInsecureTransport` statement refused it,
although the signature is valid.

## 5. Clean up

```bash
aws s3api delete-object --bucket "$BUCKET" --key hello.txt --version-id "$VERSION_ID"
terraform destroy
```

Deleting by version ID removes the object for good. Without the version ID, the
versioned bucket would only add a delete marker, the bucket would not be empty, and
`terraform destroy` would fail.

## Next steps

- [Grant access with a bucket policy](../how-to/grant-access-with-a-bucket-policy.md)
  to let another role or account read the bucket.
- [Receive load-balancer and CloudTrail logs](../how-to/receive-load-balancer-and-cloudtrail-logs.md)
  in a bucket made with this module.
