# Test fixture: a caller whose bucket policy names a role created in the same
# apply, so policy_json is unknown at plan time. The policy also uses the
# module's own bucket_arn output, which must not create a cycle.

resource "aws_iam_role" "reader" {
  name = "example-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

data "aws_iam_policy_document" "read" {
  statement {
    sid       = "Read"
    actions   = ["s3:GetObject"]
    resources = ["${module.bucket.bucket_arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.reader.arn]
    }
  }
}

module "bucket" {
  source = "../../.."

  name               = "example-bucket"
  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.read.json

  # Off so that only the caller's policy decides whether a policy exists;
  # with the TLS statement on, a regression could hide behind it.
  enforce_tls = false
}
