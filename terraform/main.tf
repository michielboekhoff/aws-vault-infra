resource "aws_kms_key" "eks" {
  description = "EKS Secret Encryption Key"
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
