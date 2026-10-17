output "bucket_id" {
  description = "Name of the bucket."
  value       = module.bucket.bucket_id
}

output "bucket_arn" {
  description = "ARN of the bucket, for IAM policies."
  value       = module.bucket.bucket_arn
}
