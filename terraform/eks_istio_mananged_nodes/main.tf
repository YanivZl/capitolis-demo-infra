locals {
  tags = {
    Name        = var.cluster_name
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
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
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
    ami_type                              = "AL2_x86_64"
    instance_types                        = ["t3.medium"]
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

  # Add-ons
  enable_argocd                 = true
  enable_argo_rollouts          = true
  enable_argo_workflows         = true
  enable_aws_cloudwatch_metrics = true
  enable_cluster_autoscaler     = true
  enable_metrics_server         = true
  enable_cert_manager           = true
  enable_aws_privateca_issuer   = true
  aws_privateca_issuer = {
    acmca_arn        = aws_acmpca_certificate_authority.this.arn
    namespace        = "aws-privateca-issuer"
    create_namespace = true
  }

  helm_releases = {
    cert-manager-csi-driver = {
      description   = "Cert Manager CSI Driver Add-on"
      chart         = "cert-manager-csi-driver"
      namespace     = "cert-manager"
      chart_version = "v0.5.0"
      repository    = "https://charts.jetstack.io"
    }

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
              type = "NodePort"
              # annotations = {
              #   "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
              #   "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
              #   "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
              #   "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "load_balancing.cross_zone.enabled=true"
              # }
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

#-------------------------------
# Associates a certificate with an AWS Certificate Manager Private Certificate Authority (ACM PCA Certificate Authority).
# An ACM PCA Certificate Authority is unable to issue certificates until it has a certificate associated with it.
# A root level ACM PCA Certificate Authority is able to self-sign its own root certificate.
#-------------------------------

resource "aws_acmpca_certificate_authority" "this" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = var.certificate_dns
    }
  }

  tags = local.tags
}

resource "aws_acmpca_certificate" "this" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.this.arn
  certificate_signing_request = aws_acmpca_certificate_authority.this.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "this" {
  certificate_authority_arn = aws_acmpca_certificate_authority.this.arn

  certificate       = aws_acmpca_certificate.this.certificate
  certificate_chain = aws_acmpca_certificate.this.certificate_chain
}

#-------------------------------
#  This resource creates a CRD of AWSPCAClusterIssuer Kind, which then represents the ACM PCA in K8
#-------------------------------

# Using kubectl to workaround kubernetes provider issue https://github.com/hashicorp/terraform-provider-kubernetes/issues/1453
resource "kubectl_manifest" "cluster_pca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "awspca.cert-manager.io/v1beta1"
    kind       = "AWSPCAClusterIssuer"

    metadata = {
      name = module.eks.cluster_name
    }

    spec = {
      arn = aws_acmpca_certificate_authority.this.arn
      region : var.region
    }
  })

  depends_on = [
    module.eks_blueprints_addons
  ]
}

################################################################################
# Kubernetes Manifests
################################################################################

# data "kubectl_filename_list" "manifests" {
#     pattern = "../../kubernetes/*/*.yaml"
# }

# resource "kubectl_manifest" "k8s_manifests" {
#     count = length(data.kubectl_filename_list.manifests.matches)
#     yaml_body = file(element(data.kubectl_filename_list.manifests.matches, count.index))
# }

resource "kubectl_manifest" "istio_alb_ingress" {
  yaml_body = file("../../kubernetes/istio/istio_alb_ingress.yaml")
}

resource "kubectl_manifest" "istio_default_gateway" {
  yaml_body = file("../../kubernetes/istio/istio_default_gateway.yaml")
}

resource "kubectl_manifest" "istio_virtualservice_application" {
  yaml_body = file("../../kubernetes/istio/istio_virtualservice_application.yaml")
}

resource "kubectl_manifest" "istio_virtualservice_argocd" {
  yaml_body = file("../../kubernetes/istio/istio_virtualservice_argocd.yaml")
}

resource "kubectl_manifest" "jenkins_service_account" {
  yaml_body = file("../../kubernetes/jenkins/manifests/jenkins-service-account.yaml")
}

# resource "kubectl_manifest" "cert_manager_ca_certificate" {
#   yaml_body = file("../../kubernetes/cert_manager/ca-certificate.yaml")
# }

# resource "kubectl_manifest" "cert_manager_ca_issuer" {
#   yaml_body = file("../../kubernetes/cert_manager/ca-issuer.yaml")
# }

# resource "kubectl_manifest" "cert_manager_certifiacte" {
#   yaml_body = file("../../kubernetes/cert_manager/certificate.yaml")
# }

# resource "kubectl_manifest" "cert_manager_selfsigned_issuer" {
#   yaml_body = file("../../kubernetes/cert_manager/selfsigned-issuer.yaml")
# }

#-------------------------------
# This resource creates a CRD of Certificate Kind, which then represents certificate issued from ACM PCA,
# mounted as K8 secret
#-------------------------------

# Using kubectl to workaround kubernetes provider issue https://github.com/hashicorp/terraform-provider-kubernetes/issues/1453
resource "kubectl_manifest" "pca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = var.certificate_name
      namespace = "default"
    }

    spec = {
      commonName = var.certificate_dns
      duration   = "2160h0m0s"
      issuerRef = {
        group = "awspca.cert-manager.io"
        kind  = "AWSPCAClusterIssuer"
        name : module.eks.cluster_name
      }
      renewBefore = "360h0m0s"
      secretName  = join("-", [var.certificate_name, "clusterissuer"]) # This is the name with which the K8 Secret will be available
      usages = [
        "server auth",
        "client auth"
      ]
      privateKey = {
        algorithm : "RSA"
        size : 2048
      }
    }
  })

  depends_on = [
    kubectl_manifest.cluster_pca_issuer,
  ]
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