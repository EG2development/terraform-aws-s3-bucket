# The examples are real configurations. Each must plan against the mocked
# provider, so an example that stops working fails CI.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  # The mock would return a random string; the module checks that a policy
  # is JSON, so the mock must return a policy document.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-2:111122223333:key/00000000-0000-0000-0000-000000000000" }
  }
}

run "basic_example_plans" {
  command = plan

  module {
    source = "./examples/basic"
  }

  variables {
    name = "example-111122223333-eu-west-2"
  }

  assert {
    condition     = output.bucket_id == "example-111122223333-eu-west-2"
    error_message = "The basic example creates one bucket named var.name."
  }
}

run "complete_example_plans" {
  command = plan

  module {
    source = "./examples/complete"
  }

  variables {
    name            = "example-reports-111122223333"
    reader_role_arn = "arn:aws:iam::444455556666:role/report-reader"
  }

  assert {
    condition     = output.bucket_id == "example-reports-111122223333" && output.access_log_bucket_id == "example-reports-111122223333-access-logs"
    error_message = "The complete example creates the data bucket and its access-log bucket."
  }
}
