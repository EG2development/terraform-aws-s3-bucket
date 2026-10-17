variable "region" {
  description = "AWS Region to create the buckets in."
  type        = string
  default     = "eu-west-2"
}

variable "name" {
  description = "Name of the data bucket, at most 51 characters: the log bucket is named \"<name>-access-logs\". Include something unique, for example \"example-reports-111122223333\"."
  type        = string
}

variable "reader_role_arn" {
  description = "ARN of an existing IAM role, in this or another account, that may read objects. For example \"arn:aws:iam::444455556666:role/report-reader\"."
  type        = string
}

variable "tags" {
  description = "Tags for both buckets."
  type        = map(string)
  default = {
    Environment = "prod"
    Team        = "data"
  }
}
