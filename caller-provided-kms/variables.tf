variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name; the one caller choice the use case requires."
}

variable "kms_key_id" {
  type        = string
  description = "KMS key identifier (ARN or key ID) the caller owns and manages; required, the pattern supplies no substitute."
}
