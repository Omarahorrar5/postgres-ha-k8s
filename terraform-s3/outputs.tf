output "bucket_name" {
  value = aws_s3_bucket.backups.bucket
}

output "region" {
  value = var.region
}