# The smallest useful call: one private bucket with the module's defaults
# (SSE-S3, versioning, a TLS-only bucket policy, and a rule that aborts
# incomplete multipart uploads). Examples call the module from the working
# copy so CI validates this repository's code; a real caller pins a Git
# source (README.md, "Usage").

provider "aws" {
  region = var.region
}

module "bucket" {
  source = "../.."

  name = var.name
}
