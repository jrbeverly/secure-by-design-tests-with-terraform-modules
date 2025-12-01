terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "encrypted_bucket" {
  source = "../caller-provided-kms"

  bucket_name = "secure-by-design-caller-provided-kms-example"

  # Placeholder: replace with the ARN of a key the caller owns and manages.
  kms_key_id = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
}
