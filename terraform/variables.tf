# ─────────────────────────────────────────────────────────────────────────────
# terraform/variables.tf
#
# WHY: Centralise all configuration in one file.
#      Override values via terraform.tfvars (never commit secrets).
# ─────────────────────────────────────────────────────────────────────────────

# ── General ────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner tag for all resources (your name or team)"
  type        = string
  default     = "devsecops-team"
}

variable "project_name" {
  description = "Project name prefix for all resource names"
  type        = string
  default     = "devsecops"
}

# ── VPC ────────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ── EC2 Instances (Jenkins, SonarQube, Nexus) ─────────────────────────────
variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4 GB RAM — minimum for Jenkins
}

variable "sonarqube_instance_type" {
  description = "EC2 instance type for SonarQube server"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4 GB RAM — SonarQube needs 2+ GB
}

variable "nexus_instance_type" {
  description = "EC2 instance type for Nexus repository"
  type        = string
  default     = "t3.small" # 2 vCPU, 2 GB RAM
}

variable "key_pair_name" {
  description = "Name for the AWS EC2 key pair (auto-generated if not provided)"
  type        = string
  default     = "devsecops-key"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into EC2 instances (your IP). Use your IP: x.x.x.x/32"
  type        = string
  default     = "0.0.0.0/0" # ⚠️ CHANGE THIS to your IP in terraform.tfvars!
}

variable "allowed_access_cidr" {
  description = "CIDR allowed to access Jenkins/SonarQube/Nexus UIs"
  type        = string
  default     = "0.0.0.0/0" # ⚠️ CHANGE THIS to your IP in production!
}

# ── EKS Cluster ────────────────────────────────────────────────────────────
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "devsecops-eks"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_desired_nodes" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_min_nodes" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "eks_max_nodes" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 3
}

# ── ECR ────────────────────────────────────────────────────────────────────
variable "ecr_repo_name" {
  description = "Name for the ECR Docker image repository"
  type        = string
  default     = "devsecops-app"
}

variable "ecr_image_retention_count" {
  description = "Number of Docker images to keep in ECR (older ones are deleted)"
  type        = number
  default     = 10
}

# ── RDS (Optional — not used in demo app) ─────────────────────────────────
variable "enable_rds" {
  description = "Set to true to provision an RDS database (not needed for demo)"
  type        = bool
  default     = false
}

# ── S3 ─────────────────────────────────────────────────────────────────────
variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform remote state (must be globally unique)"
  type        = string
  default     = "" # Override in terraform.tfvars
}
