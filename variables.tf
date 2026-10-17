variable "name" {
  description = "Name of the bucket. Bucket names are shared by every AWS account in the partition, so include something unique, such as the account ID. The module adds no Name tag: the bucket name is the bucket's identity. Changing it replaces the bucket."
  type        = string
  nullable    = false

  # The general purpose bucket naming rules in the Amazon S3 User Guide, in
  # three groups so the error says which rule was broken.
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name)) && !strcontains(var.name, "..")
    error_message = "name must be 3-63 characters: lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit, with no two adjacent dots."
  }

  validation {
    condition     = !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.name))
    error_message = "name must not be formatted like an IP address, for example 192.168.5.4."
  }

  validation {
    condition = (
      !anytrue([for prefix in ["xn--", "sthree-", "amzn-s3-demo-"] : startswith(var.name, prefix)]) &&
      !anytrue([for suffix in ["-s3alias", "--ol-s3", ".mrap", "--x-s3", "--table-s3"] : endswith(var.name, suffix)])
    )
    error_message = "name must not start with \"xn--\", \"sthree-\" or \"amzn-s3-demo-\", and must not end with \"-s3alias\", \"--ol-s3\", \".mrap\", \"--x-s3\" or \"--table-s3\": S3 reserves them."
  }
}

variable "force_destroy" {
  description = "Let Terraform delete every object and object version when it destroys the bucket, so a destroy succeeds on a bucket that is not empty. Dangerous: a mistaken destroy, or a change that replaces the bucket, then deletes the data for good. Default false. It takes effect only after an apply has recorded it in state."
  type        = bool
  default     = false
  nullable    = false
}

variable "kms_key_arn" {
  description = "ARN of a customer managed KMS key for default encryption (SSE-KMS with an S3 Bucket Key). Null (default) uses SSE-S3 (AES256). A key ARN, not an alias: S3 resolves an alias in the account of whoever writes, which may not be the bucket owner. Writers and readers need kms:GenerateDataKey and kms:Decrypt on the key. Load-balancer access logs and S3 server access logs can only be delivered to an SSE-S3 bucket."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, \"arn:<partition>:kms:<region>:<account-id>:key/<key-id>\". Alias ARNs and key IDs are not accepted."
  }
}

variable "versioning_enabled" {
  description = "Keep every version of every object, so an overwritten or deleted object can be restored. On by default. Setting it to false on an existing bucket suspends versioning (S3 cannot switch it off once enabled) and keeps the versions that already exist."
  type        = bool
  default     = true
  nullable    = false
}

variable "lifecycle_rules" {
  description = <<-EOT
    Lifecycle rules, applied in this order. Each rule has an id (unique, 1-255 characters), optional enabled (default true), optional prefix (null, the default, applies the rule to every object), and actions in whole days: expiration_days (expire current versions; on a versioned bucket this adds a delete marker), noncurrent_version_expiration_days (delete versions that stopped being current that many days ago) and abort_incomplete_multipart_upload_days (default 7). The default is one rule, "abort-incomplete-multipart-uploads", that only removes the parts of uploads not completed within 7 days. Passing a list replaces the default rule. An empty list creates no lifecycle configuration.
  EOT
  type = list(object({
    id                                     = string
    enabled                                = optional(bool, true)
    prefix                                 = optional(string)
    expiration_days                        = optional(number)
    noncurrent_version_expiration_days     = optional(number)
    abort_incomplete_multipart_upload_days = optional(number, 7)
  }))
  default  = [{ id = "abort-incomplete-multipart-uploads" }]
  nullable = false

  validation {
    condition     = alltrue([for rule in var.lifecycle_rules : try(length(rule.id) >= 1 && length(rule.id) <= 255, false)])
    error_message = "Every lifecycle rule id must be 1-255 characters."
  }

  validation {
    condition     = length(distinct([for rule in var.lifecycle_rules : rule.id])) == length(var.lifecycle_rules)
    error_message = "Lifecycle rule ids must be unique."
  }

  validation {
    condition     = alltrue([for rule in var.lifecycle_rules : rule.prefix == null || try(length(rule.prefix) > 0, false)])
    error_message = "A lifecycle rule prefix must not be empty. Leave prefix out to apply the rule to every object."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.lifecycle_rules : [
        for days in [rule.expiration_days, rule.noncurrent_version_expiration_days, rule.abort_incomplete_multipart_upload_days] :
        days == null || try(days >= 1 && floor(days) == days, false)
      ]
    ]))
    error_message = "Every lifecycle days value (expiration_days, noncurrent_version_expiration_days, abort_incomplete_multipart_upload_days) must be a whole number of at least 1."
  }
}

variable "enforce_tls" {
  description = "Add a bucket policy statement, DenyInsecureTransport, that denies every request not sent over TLS. On by default. Setting it to false allows requests over plain HTTP."
  type        = bool
  default     = true
  nullable    = false
}

variable "attach_policy_json" {
  description = "Merge policy_json into the bucket policy. A separate flag, rather than a null check on the JSON, so the decision is known at plan time even when the policy names resources created in the same apply."
  type        = bool
  default     = false
  nullable    = false
}

variable "policy_json" {
  description = "A JSON policy document whose statements are added to the bucket policy, for example the json of an aws_iam_policy_document data source. Used only when attach_policy_json is true. A statement with the Sid DenyInsecureTransport is replaced by the module's own. S3 rejects a statement that would make the bucket public, because public access is blocked."
  type        = string
  default     = null

  validation {
    condition     = var.policy_json == null || can(jsondecode(var.policy_json))
    error_message = "policy_json must be valid JSON."
  }

  # Both cross-checks live here: Terraform rejects validations of two
  # variables that refer to each other. A policy passed without the flag
  # would otherwise be dropped silently.
  validation {
    condition     = var.policy_json == null || var.attach_policy_json
    error_message = "policy_json is set but attach_policy_json is false. Set attach_policy_json = true to attach it."
  }

  validation {
    condition     = var.policy_json != null || !var.attach_policy_json
    error_message = "attach_policy_json is true but policy_json is not set."
  }
}

variable "access_logging" {
  description = "Server access logging: S3 writes a record of each request to target_bucket, under target_prefix (default \"\", the bucket root). The target bucket must be another bucket in the same account and Region, use SSE-S3, and allow the logging.s3.amazonaws.com service principal to write in its bucket policy. Null (default) turns access logging off."
  type = object({
    target_bucket = string
    target_prefix = optional(string, "")
  })
  default = null

  validation {
    condition     = var.access_logging == null || try(length(var.access_logging.target_bucket) > 0, false)
    error_message = "access_logging.target_bucket must be the name of a bucket."
  }

  # Logging a bucket into itself writes a log record for every log record.
  validation {
    condition     = var.access_logging == null || try(var.access_logging.target_bucket != var.name, true)
    error_message = "access_logging.target_bucket must be another bucket, not this one."
  }
}

variable "tags" {
  description = "Tags for the bucket. The module adds no tags of its own, not even Name: the bucket name identifies the bucket. Tags from the provider's default_tags apply as usual."
  type        = map(string)
  default     = {}
  nullable    = false
}
