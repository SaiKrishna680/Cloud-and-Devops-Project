# ─────────────────────────────────────────────────────────────────────────────
# terraform/modules/eks/main.tf
#
# CREATES:
#   - EKS Cluster (control plane managed by AWS)
#   - EKS Node Group (EC2 worker nodes in private subnets)
#   - IAM roles for cluster + nodes
#   - aws-auth ConfigMap (grants Jenkins EC2 access to EKS)
#
# WHY EKS:
#   AWS manages the Kubernetes control plane (API server, etcd).
#   You only pay for and manage the worker nodes.
#   Integrates natively with ECR, IAM, Load Balancers, CloudWatch.
# ─────────────────────────────────────────────────────────────────────────────

# ── IAM Role for EKS Control Plane ────────────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-eks-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ── IAM Role for EKS Worker Nodes ─────────────────────────────────────────────
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-eks-node-role" }
}

# Nodes need these 3 core policies
resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Nodes must pull images from ECR
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.eks_cluster_name
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    security_group_ids      = [var.eks_nodes_sg_id]
    endpoint_public_access  = true          # Allow kubectl from outside VPC
    endpoint_private_access = true          # Allow in-cluster communication
    public_access_cidrs     = ["0.0.0.0/0"] # Restrict to your IP in prod
  }

  # Enable EKS control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = {
    Name = var.eks_cluster_name
  }
}

# ── EKS Node Group ────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Place nodes in PRIVATE subnets
  subnet_ids = var.private_subnet_ids

  instance_types = [var.node_instance_type]
  ami_type       = "AL2_x86_64" # Amazon Linux 2 — optimised for EKS
  disk_size      = 20           # 20 GB per node

  # Auto-scaling configuration
  scaling_config {
    desired_size = var.desired_nodes
    min_size     = var.min_nodes
    max_size     = var.max_nodes
  }

  # Update config — rolling update (1 node at a time)
  update_config {
    max_unavailable = 1
  }

  # Labels applied to all nodes in this group
  labels = {
    role        = "worker"
    environment = var.environment
  }

  # Taint not required for this demo
  # taint { ... }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_read,
  ]

  tags = {
    Name = "${var.project_name}-node-group"
  }

  # Replace nodes when AMI changes or config changes
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ── OIDC Provider (required for IRSA — IAM Roles for Service Accounts) ────────
# WHY: Allows Kubernetes service accounts to assume IAM roles.
#      Argo CD, cluster-autoscaler, and AWS Load Balancer Controller need this.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-oidc"
  }
}

# ── aws-auth ConfigMap — Grant Jenkins EC2 access to EKS ─────────────────────
# WHY: By default, only the IAM principal that created the EKS cluster has access.
#      This ConfigMap grants the Jenkins EC2 role admin access to kubectl.
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  force = true

  data = {
    mapRoles = yamlencode([
      {
        # EKS Node Group role
        rolearn  = aws_iam_role.eks_nodes.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        # Jenkins EC2 role — allow Jenkins to run kubectl
        rolearn  = var.jenkins_ec2_role_arn
        username = "jenkins"
        groups   = ["system:masters"]
      }
    ])
  }

  depends_on = [aws_eks_cluster.main, aws_eks_node_group.main]
}
