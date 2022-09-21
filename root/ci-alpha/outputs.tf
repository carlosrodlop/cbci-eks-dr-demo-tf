output "set_context" {
  value = "kubectl config use-context ${module.eks.cluster_id}"
}

output "dr_cluster_id" {
  value = var.aws_region
}