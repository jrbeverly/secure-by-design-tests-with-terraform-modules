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
  source = "../pattern-managed-kms"

  bucket_name = "secure-by-design-pattern-managed-kms-example"
}
