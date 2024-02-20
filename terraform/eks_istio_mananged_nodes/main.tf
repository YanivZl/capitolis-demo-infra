provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

locals {
  tags = {
    Name  = var.cluster_name
    Environment = "Prod"
    Description = "Capitolis DevOps Task"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                   = var.cluster_name
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy  = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    mng1 = {
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t3.medium"]
    attach_cluster_primary_security_group = false
    iam_role_additional_policies = { 
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" 
    }
  }

  #  EKS K8s API cluster needs to be able to talk with the EKS worker nodes with port 15017/TCP and 15012/TCP which is used by Istio
  #  Istio in order to create sidecar needs to be able to communicate with webhook and for that network passage to EKS is needed.
  node_security_group_additional_rules = {
    ingress_15017 = {
      description                   = "Cluster API - Istio Webhook namespace.sidecar-injector.istio.io"
      protocol                      = "TCP"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_15012 = {
      description                   = "Cluster API to nodes ports/protocols"
      protocol                      = "TCP"
      from_port                     = 15012
      to_port                       = 15012
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  tags = local.tags
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

################################################################################
# EKS Blueprints Addons
################################################################################

resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = "istio-system"
  }
}

resource "kubernetes_namespace_v1" "jenkins" {
  metadata {
    name = "jenkins"
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.14"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # This is required to expose Istio Ingress Gateway
  enable_aws_load_balancer_controller = true

  depends_on = [
    # Wait for EBS CSI, etc. to be installed first
    module.eks
  ]

  enable_argocd                                = true
  enable_argo_rollouts                         = true
  enable_argo_workflows                        = true
  enable_aws_cloudwatch_metrics                = true
  enable_aws_privateca_issuer                  = true
  enable_cluster_autoscaler                    = true
  enable_metrics_server                        = true

  # Wait for all Cert-manager related resources to be ready
  enable_cert_manager = true
  cert_manager = {
    wait = true
  }

  helm_releases = {
    istio-base = {
      chart         = "base"
      chart_version = var.istio_chart_version
      repository    = var.istio_chart_url
      name          = "istio-base"
      namespace     = kubernetes_namespace_v1.istio_system.metadata[0].name
    }

    istiod = {
      chart         = "istiod"
      chart_version = var.istio_chart_version
      repository    = var.istio_chart_url
      name          = "istiod"
      namespace     = kubernetes_namespace_v1.istio_system.metadata[0].name

      set = [
        {
          name  = "meshConfig.accessLogFile"
          value = "/dev/stdout"
        }
      ]
    }

    istio-ingress = {
      chart            = "gateway"
      chart_version    = var.istio_chart_version
      repository       = var.istio_chart_url
      name             = "istio-ingress"
      namespace        = "istio-ingress" # per https://github.com/istio/istio/blob/master/manifests/charts/gateways/istio-ingress/values.yaml#L2
      create_namespace = true

      values = [
        yamlencode(
          {
            labels = {
              istio = "ingressgateway"
            }
            service = {
              annotations = {
                "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
                "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
                "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
                "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "load_balancing.cross_zone.enabled=true"
              }
            }
          }
        )
      ]
    }

    jenkins = {
      name       = "jenkins"
      repository = "https://charts.jenkins.io"
      chart      = "jenkins"
      namespace  = "jenkins"

      values = [
        "${file("../../kubernetes/jenkins/helm/jenkins-values.yaml")}"
      ]

      set_sensitive = [
        {
          name  = "controller.admin.username"
          value = var.jenkins_admin_user
        },
        {
          name  = "controller.admin.password"
          value = var.jenkins_admin_password
        }
      ]
    }
  }

  tags = local.tags
}

################################################################################
# Kubernetes Manifests
################################################################################

resource "kubernetes_manifest" "istio_alb_ingress" {
  manifest = yamldecode(file("../../kubernetes/istio/istio_alb_ingress.yaml"))
}

resource "kubernetes_manifest" "istio_ingress_gateway" {
  manifest = yamldecode(file("../../kubernetes/istio/istio_alb_ingress.yaml"))
}

resource "kubernetes_manifest" "cert_manager_ca_certificate" {
  manifest = yamldecode(file("../../kubernetes/istio/istio_alb_ingress.yaml"))
}

resource "kubernetes_manifest" "cert_manager_ca_issuer" {
  manifest = yamldecode(file("../../kubernetes/istio/istio_alb_ingress.yaml"))
}

resource "kubernetes_manifest" "cert_manager_certifiacte" {
  manifest = yamldecode(file("../../kubernetes/istio/istio_alb_ingress.yaml"))
}

resource "kubernetes_manifest" "cert_manager_selfsigned_issuer" {
  manifest = yamldecode(file("../../kubernetes/istio/istio_alb_ingress.yaml"))
}

resource "kubernetes_manifest" "istio_virtual_services" {
  manifest = yamldecode(file("../../kubernetes/istio/istio_alb_ingress.yaml"))
}

resource "kubernetes_manifest" "jenkins_service_account" {
  manifest = yamldecode(file("../../kubernetes/jenkins/manifests/jenkins-service-account.yaml"))
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}