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

  taints_cilium = {
    cilium = {
      key    = "node.cilium.io/agent-not-ready"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  }

  wireguard_sg = var.plan_wireguard ? {
    wireguard = {
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
      description = "a very permissive sg rules for Wireguard"
    }
  } : {}
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v5.13.0"

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

  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_subnets
  control_plane_subnet_ids  = module.vpc.private_subnets
  cluster_service_ipv4_cidr = var.service_cidr

  cluster_encryption_config = {}
  cluster_enabled_log_types = []

  eks_managed_node_group_defaults = {
    instance_types = ["t3.medium"]
    taints         = var.install_cilium ? local.taints_cilium : {}
  }

  eks_managed_node_groups = {
    cilium = {
      min_size     = 2
      max_size     = 10
      desired_size = 2
    }
  }

  node_security_group_additional_rules = local.wireguard_sg
}

module "kubeconfig" {
  count  = var.install_cilium ? 1 : 0
  source = "github.com/littlejo/terraform-kubernetes-kubeconfig?ref=no-experiment"

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
  count = var.install_cilium ? 1 : 0
  provisioner "local-exec" {
    command = "kubectl -n kube-system patch daemonset aws-node --type='strategic' -p='${jsonencode(local.cilium_patch)}'"
    environment = {
      KUBECONFIG = "./kubeconfig"
    }
  }
  depends_on = [module.kubeconfig]
}

module "cilium" {
  count  = var.install_cilium ? 1 : 0
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
