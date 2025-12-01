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
  source = "../aws-managed-sse"

  bucket_name = "secure-by-design-aws-managed-sse-example"
}
