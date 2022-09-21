data "aws_region" "current" {}

locals {
  aws_region = data.aws_region.current.name
}

module "velero_eks_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "velero-${local.aws_region}"
  attach_velero_policy  = true
  velero_s3_bucket_arns = [var.s3_bucket_arn]

  oidc_providers = {
    main = {
      provider_arn               = var.k8s_cluster_oidc_arn
      namespace_service_accounts = ["${var.namespace}:${var.service_account}"]
    }
  }
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "this" {
  depends_on = [kubernetes_namespace.this]

  chart      = "velero"
  name       = var.release_name
  namespace  = var.namespace
  repository = "https://vmware-tanzu.github.io/helm-charts"
  values = [templatefile("${path.module}/velero.cb.values.yaml", {
    bucket_name   = var.bucket_name,
    bucket_region = var.region_name,
    velero_region = local.aws_region,
    rol_arn       = module.velero_eks_role.iam_role_arn
    cluster_name  = var.cluster_name
    zone          = var.zone
  })]
  version = var.chart_version
  replace = true
}

