output "bucket_id" {
  description = "Name of the bucket (S3 uses the name as the ID). Known at plan time."
  value       = aws_s3_bucket.main.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket, for IAM and bucket policies. An object's ARN is this ARN, a slash and the object key."
  value       = aws_s3_bucket.main.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket: the bucket name followed by .s3.amazonaws.com."
  value       = aws_s3_bucket.main.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket, for example for a CloudFront origin."
  value       = aws_s3_bucket.main.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS Region the bucket is in."
  value       = aws_s3_bucket.main.bucket_region
}
