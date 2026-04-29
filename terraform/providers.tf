# ─────────────────────────────────────────────────────────────────────────────
# terraform/providers.tf
#
# WHY: Declares required providers and their versions.
#      Pinning versions ensures reproducible infrastructure across team members.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    # For generating SSH key pair stored in AWS SSM
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # For Kubernetes resources (EKS config)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    # For Helm charts (Argo CD, Prometheus, Grafana)
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    # For local file generation
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    # For null resources (provisioners)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # ── Remote State Backend (S3 + DynamoDB locking) ────────────────────────
  # WHY: Shared state allows team collaboration.
  #      DynamoDB prevents concurrent Terraform runs from corrupting state.
  #
  # SETUP BEFORE FIRST RUN:
  #   aws s3api create-bucket --bucket <your-bucket-name> --region us-east-1
  #   aws dynamodb create-table \
  #     --table-name terraform-devsecops-lock \
  #     --attribute-definitions AttributeName=LockID,AttributeType=S \
  #     --key-schema AttributeName=LockID,KeyType=HASH \
  #     --billing-mode PAY_PER_REQUEST \
  #     --region us-east-1
  #
  # Then uncomment:
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket-devsecops"
  #   key            = "devsecops/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-devsecops-lock"
  #   encrypt        = true
  # }
}

# ── AWS Provider ─────────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "DevSecOps-Pipeline"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# ── Kubernetes Provider (configured after EKS is created) ────────────────────
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.main.token
}

# ── Helm Provider ─────────────────────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# ── Data source: EKS cluster auth token ──────────────────────────────────────
data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

# ── Data source: Current AWS account ID and region ───────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Data source: Available AZs ────────────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ── Data source: Latest Amazon Linux 2023 AMI ───────────────────────────────
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
