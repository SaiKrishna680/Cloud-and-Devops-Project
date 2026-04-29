# ─────────────────────────────────────────────────────────────────────────────
# terraform/main.tf — ROOT MODULE
#
# WIRES ALL MODULES TOGETHER:
#   vpc → security_groups → ec2 (Jenkins, SonarQube, Nexus)
#                         → ecr (Docker image registry)
#                         → eks (Kubernetes cluster)
#
# EXECUTION ORDER (Terraform handles this via dependency graph):
#   1. VPC + Subnets
#   2. Security Groups
#   3. ECR Repository
#   4. EC2 Instances (Jenkins, SonarQube, Nexus)
#   5. EKS Cluster
#   6. EKS Node Group
#   7. Kubernetes resources (namespaces, auth)
#
# USAGE:
#   cd terraform
#   cp terraform.tfvars.example terraform.tfvars
#   # Edit terraform.tfvars with your values
#   terraform init
#   terraform plan -out=tfplan
#   terraform apply tfplan
#
# ESTIMATED COST (us-east-1, running 8 hrs/day):
#   Jenkins  t3.medium = ~$0.32/day
#   SonarQube t3.medium = ~$0.32/day
#   Nexus    t3.small  = ~$0.16/day
#   EKS cluster       = $0.10/hr = ~$0.80/day
#   EKS nodes 2x t3.medium = ~$0.64/day
#   NAT Gateway       = ~$0.36/day
#   3x Elastic IPs    = ~$0.27/day (when detached)
#   TOTAL             ≈ $3/day or ~$90/month (stop when not in use!)
# ─────────────────────────────────────────────────────────────────────────────

# ════════════════════════════════════════════════════════════════════════════
# MODULE 1: VPC
# ════════════════════════════════════════════════════════════════════════════
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  eks_cluster_name     = var.eks_cluster_name
}

# ════════════════════════════════════════════════════════════════════════════
# MODULE 2: Security Groups
# ════════════════════════════════════════════════════════════════════════════
module "security_groups" {
  source = "./modules/security_groups"

  project_name        = var.project_name
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = var.vpc_cidr
  allowed_ssh_cidr    = var.allowed_ssh_cidr
  allowed_access_cidr = var.allowed_access_cidr
  eks_cluster_name    = var.eks_cluster_name

  depends_on = [module.vpc]
}

# ════════════════════════════════════════════════════════════════════════════
# MODULE 3: ECR Repository
# ════════════════════════════════════════════════════════════════════════════
module "ecr" {
  source = "./modules/ecr"

  project_name          = var.project_name
  repo_name             = var.ecr_repo_name
  image_retention_count = var.ecr_image_retention_count

  # Forward references — these roles are created in the ec2 and eks modules.
  # We pass the ARNs directly since Terraform resolves the dependency graph.
  jenkins_role_arn  = module.ec2.jenkins_iam_role_arn
  eks_node_role_arn = module.eks.node_role_arn

  depends_on = [module.ec2, module.eks]
}

# ════════════════════════════════════════════════════════════════════════════
# MODULE 4: EC2 Instances (Jenkins, SonarQube, Nexus)
# ════════════════════════════════════════════════════════════════════════════
module "ec2" {
  source = "./modules/ec2"

  project_name            = var.project_name
  aws_region              = var.aws_region
  ami_id                  = data.aws_ami.amazon_linux_2023.id
  key_pair_name           = var.key_pair_name
  public_subnet_id        = module.vpc.public_subnet_ids[0]
  jenkins_sg_id           = module.security_groups.jenkins_sg_id
  sonarqube_sg_id         = module.security_groups.sonarqube_sg_id
  nexus_sg_id             = module.security_groups.nexus_sg_id
  jenkins_instance_type   = var.jenkins_instance_type
  sonarqube_instance_type = var.sonarqube_instance_type
  nexus_instance_type     = var.nexus_instance_type
  ecr_registry            = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  depends_on = [module.vpc, module.security_groups]
}

# ════════════════════════════════════════════════════════════════════════════
# MODULE 5: EKS Cluster
# ════════════════════════════════════════════════════════════════════════════
module "eks" {
  source = "./modules/eks"

  project_name         = var.project_name
  environment          = var.environment
  eks_cluster_name     = var.eks_cluster_name
  eks_cluster_version  = var.eks_cluster_version
  node_instance_type   = var.eks_node_instance_type
  desired_nodes        = var.eks_desired_nodes
  min_nodes            = var.eks_min_nodes
  max_nodes            = var.eks_max_nodes
  public_subnet_ids    = module.vpc.public_subnet_ids
  private_subnet_ids   = module.vpc.private_subnet_ids
  eks_nodes_sg_id      = module.security_groups.eks_nodes_sg_id
  jenkins_ec2_role_arn = module.ec2.jenkins_iam_role_arn

  depends_on = [module.vpc, module.security_groups]
}

# ════════════════════════════════════════════════════════════════════════════
# KUBERNETES NAMESPACE (created after EKS is ready)
# ════════════════════════════════════════════════════════════════════════════
resource "kubernetes_namespace" "devsecops" {
  metadata {
    name = "devsecops"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}

# ════════════════════════════════════════════════════════════════════════════
# ARGO CD (deployed via Helm)
# ════════════════════════════════════════════════════════════════════════════
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.3"
  namespace  = "argocd"

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer" # AWS will create an ELB automatically
        }
        extraArgs = ["--insecure"] # Remove TLS termination (do at LB level)
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd, module.eks]
}

# ════════════════════════════════════════════════════════════════════════════
# PROMETHEUS (deployed via Helm — kube-prometheus-stack)
# ════════════════════════════════════════════════════════════════════════════
resource "helm_release" "prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.2.2"
  namespace  = "monitoring"

  values = [
    yamlencode({
      grafana = {
        adminPassword = "admin123"
        service = {
          type = "LoadBalancer"
        }
      }
      prometheus = {
        service = {
          type = "LoadBalancer"
        }
        prometheusSpec = {
          # Scrape Spring Boot app metrics
          additionalScrapeConfigs = [
            {
              job_name       = "devsecops-app"
              metrics_path   = "/actuator/prometheus"
              static_configs = [{ targets = ["devsecops-app-svc.devsecops:80"] }]
            }
          ]
        }
      }
      alertmanager = {
        enabled = false # Disable for demo; enable in production
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring, module.eks]
}

# ════════════════════════════════════════════════════════════════════════════
# SSM PARAMETERS — Store outputs as SSM params for easy access
# ════════════════════════════════════════════════════════════════════════════
resource "aws_ssm_parameter" "jenkins_url" {
  name  = "/${var.project_name}/jenkins/url"
  type  = "String"
  value = "http://${module.ec2.jenkins_public_ip}:8080"
}

resource "aws_ssm_parameter" "sonarqube_url" {
  name  = "/${var.project_name}/sonarqube/url"
  type  = "String"
  value = "http://${module.ec2.sonarqube_public_ip}:9000"
}

resource "aws_ssm_parameter" "nexus_url" {
  name  = "/${var.project_name}/nexus/url"
  type  = "String"
  value = "http://${module.ec2.nexus_public_ip}:8081"
}

resource "aws_ssm_parameter" "ecr_registry" {
  name  = "/${var.project_name}/ecr/registry"
  type  = "String"
  value = module.ecr.registry_host
}

resource "aws_ssm_parameter" "ecr_repo_url" {
  name  = "/${var.project_name}/ecr/repo-url"
  type  = "String"
  value = module.ecr.repository_url
}
