output "set_context" {
  value = "kubectl config use-context ${module.eks.cluster_id}"
}

output "s3_bucket_arn" {
  value = module.aws_s3_backups.s3_bucket_arn
}

output "s3_bucket_id" {
  value = module.aws_s3_backups.s3_bucket_id
}

output "s3_bucket_region" {
  value = var.aws_region
}

output "dr_cluster_id" {
  value = var.aws_region
}
