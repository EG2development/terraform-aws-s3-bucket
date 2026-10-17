output "bucket_id" {
  description = "Name of the data bucket."
  value       = module.bucket.bucket_id
}

output "bucket_arn" {
  description = "ARN of the data bucket."
  value       = module.bucket.bucket_arn
}

output "access_log_bucket_id" {
  description = "Name of the bucket that receives the data bucket's server access logs."
  value       = module.access_logs.bucket_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the data bucket. Writers need kms:GenerateDataKey on it."
  value       = aws_kms_key.bucket.arn
}
