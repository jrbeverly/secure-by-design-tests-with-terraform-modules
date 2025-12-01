output "bucket_id" {
  value = aws_s3_bucket.storage.id
}

output "bucket_arn" {
  value = aws_s3_bucket.storage.arn
}

output "key_arn" {
  value = aws_kms_key.storage.arn
}
