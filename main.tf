locals {
  subnets_num       = length(var.azs)
  total_subnets_num = local.subnets_num * 2
  num_list          = [for i in range(0, local.total_subnets_num) : local.subnets_num]
  subnets_cidr      = cidrsubnets(var.cidr, local.num_list...)
  cilium_patch = {
    spec = {
      template = {
        spec = {
          nodeSelector = {
            "io.cilium/aws-node-enabled" = "true"
          }
        }
      }
    }
  }
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v5.0.0"

  name = var.vpc_name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = slice(local.subnets_cidr, 0, local.subnets_num)
  public_subnets  = slice(local.subnets_cidr, local.subnets_num, local.total_subnets_num)

  enable_nat_gateway = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  cluster_encryption_config = {}
  cluster_enabled_log_types = []

  eks_managed_node_group_defaults = {
    instance_types = ["t3.medium"]
    taints = {
      cilium = {
        key    = "node.cilium.io/agent-not-ready"
        value  = "true"
        effect = "NO_EXECUTE"
      }
    }
  }

  eks_managed_node_groups = {
    cilium = {
      min_size     = 2
      max_size     = 10
      desired_size = 2
    }
  }
}

module "kubeconfig" {
  source = "github.com/mvachhar/terraform-kubernetes-kubeconfig?ref=no-experiment"

  current_context = "eks"
  clusters = [{
    name                       = "kubernetes"
    server                     = module.eks.cluster_endpoint
    certificate_authority_data = module.eks.cluster_certificate_authority_data
  }]
  contexts = [{
    name         = "eks",
    cluster_name = "kubernetes",
    user         = "eks",
  }]
  users = [{
    name  = "eks",
    token = data.aws_eks_cluster_auth.this.token
    }
  ]
}

resource "terraform_data" "cilium_patch" {
  provisioner "local-exec" {
    command = "kubectl -n kube-system patch daemonset aws-node --type='strategic' -p='${jsonencode(local.cilium_patch)}'"
    environment = {
      KUBECONFIG = "./kubeconfig"
    }
  }
  depends_on = [module.kubeconfig]
}

module "cilium" {
  source = "github.com/terraform-helm/terraform-helm-cilium?ref=v0.3"
  set_values = concat([
    {
      name  = "eni.enabled"
      value = "true"
    },
    {
      name  = "ipam.mode"
      value = "eni"
    },
    {
      name  = "egressMasqueradeInterfaces"
      value = "eth0"
    },
    {
      name  = "tunnel"
      value = "disabled"
    }
  ])
}