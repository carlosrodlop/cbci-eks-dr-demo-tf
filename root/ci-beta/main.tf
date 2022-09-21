data "aws_route53_zone" "domain" {
  name = var.domain_name
}

data "aws_eks_cluster_auth" "auth" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  cluster_name           = "${var.name}-${var.dr_cluster}"
  s3_backup_name         = "${var.name}.${var.dr_cluster}.backup"
  cluster_version        = "1.23"
  aws_account_id         = data.aws_caller_identity.current.account_id
  aws_region             = data.aws_region.current.name
  cluster_endpoint       = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  cluster_auth_token     = data.aws_eks_cluster_auth.auth.token
  oidc_issuer            = trimprefix(module.eks.cluster_oidc_issuer_url, "https://")
  oidc_provider_arn      = module.eks.oidc_provider_arn
  default_storage_class  = "gp2"
  kubeconfig_file        = "${path.cwd}/kubeconfig_file"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  ci_host_name  = "ci.${var.domain_name}"
  ingress_class = "alb"
  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
    "alb.ingress.kubernetes.io/target-type" = "ip"
  }
  platform         = "eks"
  ci_chart_version = "3.47.0+117b80441352"

}

module "iam" {
  source = "../../modules/eks-iam-roles"

  cluster_name = local.cluster_name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.17.0"

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version
  create_iam_role = false
  enable_irsa     = true
  iam_role_arn    = module.iam.cluster_role_arn
  subnet_ids      = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  eks_managed_node_group_defaults = {
    min_size     = 1
    max_size     = 4
    desired_size = 2

    create_iam_role       = false
    create_security_group = false
    iam_role_arn          = module.iam.node_role_arn
    instance_types        = ["m5.2xlarge"]
  }

  eks_managed_node_groups = { for index, zone in local.azs :
    "${local.cluster_name}-${zone}" => {
      subnet_ids = [module.vpc.private_subnets[index]]
    }
  }

  node_security_group_additional_rules = {
    egress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      self        = true
    }

    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    egress_ssh_all = {
      description      = "Egress all ssh to internet for github"
      protocol         = "tcp"
      from_port        = 22
      to_port          = 22
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }

  }

}

################################################################
# Custom EKS Modules
################################################################

module "aws_load_balancer_controller" {
  depends_on = [module.eks]
  source     = "../../modules/aws-load-balancer-controller"

  aws_account_id            = local.aws_account_id
  aws_region                = local.aws_region
  cluster_name              = local.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id    = module.eks.node_security_group_id
  oidc_issuer               = local.oidc_issuer
}

module "external_dns" {
  depends_on = [module.aws_load_balancer_controller]
  count      = var.primary_cluster ? 1 : 0
  source     = "../../modules/external-dns-eks"

  aws_account_id  = local.aws_account_id
  cluster_name    = local.cluster_name
  oidc_issuer     = local.oidc_issuer
  route53_zone_id = data.aws_route53_zone.domain.id
}

module "cloudbees_ci" {
  depends_on = [module.external_dns]
  count      = var.primary_cluster ? 1 : 0
  source     = "../../modules/cloudbees-ci"

  chart_version       = local.ci_chart_version
  platform            = local.platform
  host_name           = local.ci_host_name
  ingress_annotations = local.ingress_annotations
  ingress_class       = local.ingress_class
  oc_cpu              = 1
  oc_memory           = 2
}

module "velero_aws" {
  source     = "../../modules/velero-eks"
  depends_on = [module.eks]

  cluster_name         = local.cluster_name
  k8s_cluster_oidc_arn = local.oidc_provider_arn
  zone                 = tostring(local.azs[0])

  # Diferentiate between primary and secondary clusters
  region_name   = local.aws_region
  s3_bucket_arn = module.aws_s3_backups.s3_bucket_arn
  bucket_name   = module.aws_s3_backups.s3_bucket_id
}

module "cluster_metrics" {
  depends_on = [module.eks]
  source     = "../../modules/metrics-server"
}

module "ebs_driver" {
  depends_on = [module.eks]
  source     = "../../modules/aws-ebs-csi-driver"

  aws_account_id = local.aws_account_id
  aws_region     = local.aws_region
  cluster_name   = local.cluster_name
  oidc_issuer    = local.oidc_issuer
  volume_tags    = var.tags
}

################################################################
# AWS Resources
################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.cluster_name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.cluster_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.cluster_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.cluster_name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

}

module "acm_certificate" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.domain.id

  subject_alternative_names = [
    "*.${var.domain_name}",
  ]

  wait_for_validation = true
}

module "aws_s3_backups" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.4.0"

  bucket = local.s3_backup_name

  # Allow deletion of non-empty bucket
  # NOTE: This is enabled for example usage only, you should not enable this for production workloads
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  acl = "private"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  versioning = {
    status     = true
    mfa_delete = false
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

################################################################################
# Post-provisioning commands
################################################################################

resource "null_resource" "update_kubeconfig" {

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_id} --alias ${module.eks.cluster_id} --profile ${var.aws_profile} --region ${var.aws_region} --kubeconfig ${local.kubeconfig_file}"
  }
}

resource "null_resource" "update_default_storage_class" {

  provisioner "local-exec" {
    command = "kubectl annotate --overwrite storageclass ${local.default_storage_class} storageclass.kubernetes.io/is-default-class=false"
    environment = {
      KUBECONFIG = local.kubeconfig_file
    }
  }

  provisioner "local-exec" {
    command = "kubectl annotate --overwrite storageclass ${module.ebs_driver.storage_class_name} storageclass.kubernetes.io/is-default-class=true"
    environment = {
      KUBECONFIG = local.kubeconfig_file
    }
  }
}