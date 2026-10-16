# Every validation rejects bad input at plan time, before any API call, and
# valid edge cases are accepted.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name = "example-bucket"
}

run "accepts_valid_input" {
  command = plan
}

# Bucket names: the general purpose bucket naming rules.

run "rejects_name_too_short" {
  command = plan
  variables {
    name = "ab"
  }
  expect_failures = [var.name]
}

run "rejects_name_too_long" {
  command = plan
  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  expect_failures = [var.name]
}

run "rejects_uppercase_name" {
  command = plan
  variables {
    name = "Example-bucket"
  }
  expect_failures = [var.name]
}

run "rejects_underscore_in_name" {
  command = plan
  variables {
    name = "example_bucket"
  }
  expect_failures = [var.name]
}

run "rejects_name_starting_with_a_hyphen" {
  command = plan
  variables {
    name = "-example-bucket"
  }
  expect_failures = [var.name]
}

run "rejects_name_ending_with_a_dot" {
  command = plan
  variables {
    name = "example-bucket."
  }
  expect_failures = [var.name]
}

run "rejects_adjacent_dots" {
  command = plan
  variables {
    name = "example..bucket"
  }
  expect_failures = [var.name]
}

run "rejects_ip_address_name" {
  command = plan
  variables {
    name = "192.168.5.4"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_prefix_xn" {
  command = plan
  variables {
    name = "xn--example"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_prefix_sthree" {
  command = plan
  variables {
    name = "sthree-example"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_prefix_amzn_s3_demo" {
  command = plan
  variables {
    name = "amzn-s3-demo-example"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_suffix_s3alias" {
  command = plan
  variables {
    name = "example-s3alias"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_suffix_object_lambda" {
  command = plan
  variables {
    name = "example--ol-s3"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_suffix_mrap" {
  command = plan
  variables {
    name = "example.mrap"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_suffix_directory_bucket" {
  command = plan
  variables {
    name = "example--x-s3"
  }
  expect_failures = [var.name]
}

run "rejects_reserved_suffix_table_bucket" {
  command = plan
  variables {
    name = "example--table-s3"
  }
  expect_failures = [var.name]
}

run "accepts_63_character_name_with_dots_and_digits" {
  command = plan
  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaa.1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  assert {
    condition     = length(aws_s3_bucket.main.bucket) == 63
    error_message = "A 63-character name with dots, hyphens and digits is valid."
  }
}

run "accepts_three_character_name" {
  command = plan
  variables {
    name = "a1b"
  }
  assert {
    condition     = aws_s3_bucket.main.bucket == "a1b"
    error_message = "A 3-character name is valid."
  }
}

run "accepts_dotted_digits_that_are_not_an_ip_address" {
  command = plan
  variables {
    name = "1.2.3"
  }
  assert {
    condition     = aws_s3_bucket.main.bucket == "1.2.3"
    error_message = "Three dotted numbers are not an IP address."
  }
}

# KMS key ARN.

run "rejects_kms_alias_arn" {
  command = plan
  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:alias/example"
  }
  expect_failures = [var.kms_key_arn]
}

run "rejects_kms_key_id" {
  command = plan
  variables {
    kms_key_arn = "00000000-0000-0000-0000-000000000000"
  }
  expect_failures = [var.kms_key_arn]
}

run "accepts_multi_region_key_in_another_partition" {
  command = plan
  variables {
    kms_key_arn = "arn:aws-us-gov:kms:us-gov-west-1:111122223333:key/mrk-1234abcd12ab34cd56ef1234567890ab"
  }
  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.main.rule) == 1
    error_message = "A multi-Region key ARN in another partition is valid."
  }
}

# Lifecycle rules.

run "rejects_empty_rule_id" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "" }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_rule_id_over_255_characters" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr" }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_duplicate_rule_ids" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "expire", expiration_days = 30 }, { id = "expire", expiration_days = 60 }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_empty_prefix" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "logs", prefix = "" }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_zero_days" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "expire", expiration_days = 0 }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_fractional_days" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "expire", noncurrent_version_expiration_days = 1.5 }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_negative_abort_days" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "abort", abort_incomplete_multipart_upload_days = -1 }]
  }
  expect_failures = [var.lifecycle_rules]
}

# Bucket policy.

run "rejects_invalid_policy_json" {
  command = plan
  variables {
    attach_policy_json = true
    policy_json        = "{not json"
  }
  expect_failures = [var.policy_json]
}

run "rejects_policy_without_policy_flag" {
  command = plan
  variables {
    policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
  expect_failures = [var.policy_json]
}

run "rejects_policy_flag_without_policy" {
  command = plan
  variables {
    attach_policy_json = true
  }
  expect_failures = [var.policy_json]
}

# Server access logging.

run "rejects_empty_logging_target" {
  command = plan
  variables {
    access_logging = { target_bucket = "" }
  }
  expect_failures = [var.access_logging]
}

run "rejects_null_logging_target" {
  command = plan
  variables {
    access_logging = { target_bucket = null }
  }
  expect_failures = [var.access_logging]
}

run "rejects_logging_into_the_same_bucket" {
  command = plan
  variables {
    access_logging = { target_bucket = "example-bucket" }
  }
  expect_failures = [var.access_logging]
}
