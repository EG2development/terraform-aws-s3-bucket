variable "region" {
  description = "AWS Region to create the bucket in."
  type        = string
  default     = "eu-west-2"
}

variable "name" {
  description = "Bucket name. Bucket names are shared by every AWS account, so include something unique, for example \"example-111122223333-eu-west-2\"."
  type        = string
}
