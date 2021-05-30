# KMS key to encrypt k8s secrets
resource "aws_kms_key" "eks" {
  description = "EKS Secret Encryption Key"
}

# Vault KMS section to follow
resource "aws_kms_key" "vault_unseal" {
  description = "Vault auto-unseal key"
}

resource "aws_kms_alias" "vault_unseal_alias" {
  name          = "alias/vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# NOTE(mboekhoff): This has to be defined in here because we have to create a
# service account for Vault. We need the role ARN in the below service account
# for IRSA to work:
# https://docs.aws.amazon.com/eks/latest/userguide/specify-service-account-role.html
# A neat solution to this might be an AWS Kubernetes operator that can create
# the service account & role but I didn't look into this because of time 
# constraints & to keep things simple.
# NOTE(mboekhoff): see the following for the AWS operator:
# https://aws-controllers-k8s.github.io/community/services/#aws-iam
# https://github.com/aws-controllers-k8s/community/issues/222
resource "kubernetes_namespace" "vault_ns" {
  metadata {
    name = "vault"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
    ]
  }
}

resource "aws_iam_policy" "kms_policy" {
  name = "kms_policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
  }
}

resource "aws_iam_role" "vault_role" {
  name                = "vault_role"
  managed_policy_arns = [aws_iam_policy.kms_policy.arn]
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "kubernetes_service_account" "kms_sa" {
  depends_on = [kubernetes_namespace.vault_ns]

  metadata {
    name      = "vault-sa"
    namespace = "vault"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.vault_role.arn
    }
  }
}

# Usage of this is not strictly encouraged for production,
# but I wanted to make it easy to run this module.
resource "tls_private_key" "flux_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "vault-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    Terraform = "true"
  }

  vpc_tags = {
    Name = "vault-vpc"
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "vault-example"
  cluster_version = "1.19"
  subnets         = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  cluster_endpoint_private_access = true

  # To enable fine-grained IAM policies to Kubernetes service accounts
  enable_irsa = true

  # Encrypt k8s secrets
  cluster_encryption_config = [
    {
      provider_key_arn = aws_kms_key.eks.arn
      resources        = ["secrets"]
    }
  ]

  worker_groups = [
    {
      name                 = "node-group-1"
      instance_type        = "t3.small"
      asg_desired_capacity = 1
      asg_max_size         = 3
    },
  ]
}

module "flux" {
  source = "./modules/flux"

  target_path          = "clusters/vault-example"
  git_repository       = "ssh://git@github.com/michielboekhoff/aws-vault-infra.git"
  git_branch           = "master"
  flux_ssh_key_public  = tls_private_key.flux_ssh_key.public_key_pem
  flux_ssh_key_private = tls_private_key.flux_ssh_key.private_key_pem
}
