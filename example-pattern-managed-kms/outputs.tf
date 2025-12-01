output "bucket_id" {
  value = module.encrypted_bucket.bucket_id
}

output "bucket_arn" {
  value = module.encrypted_bucket.bucket_arn
}

output "key_arn" {
  value = module.encrypted_bucket.key_arn
}
