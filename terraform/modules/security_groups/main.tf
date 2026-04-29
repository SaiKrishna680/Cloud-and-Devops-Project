# ─────────────────────────────────────────────────────────────────────────────
# terraform/modules/security_groups/main.tf
#
# CREATES SECURITY GROUPS FOR:
#   - Jenkins EC2  (ports: 22/SSH, 8080/Jenkins UI, 50000/Agents)
#   - SonarQube EC2 (ports: 22/SSH, 9000/SonarQube UI)
#   - Nexus EC2    (ports: 22/SSH, 8081/Nexus UI)
#   - EKS nodes    (all traffic within VPC)
#
# WHY SEPARATE SECURITY GROUPS:
#   Each tool has different port requirements. Least-privilege principle:
#   only open the ports each service actually needs.
# ─────────────────────────────────────────────────────────────────────────────

# ── Jenkins Security Group ────────────────────────────────────────────────────
resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins CI server"
  vpc_id      = var.vpc_id

  # SSH access (restrict to your IP in production)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Jenkins Web UI
  ingress {
    description = "Jenkins Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_access_cidr]
  }

  # Jenkins agent communication (JNLP)
  ingress {
    description = "Jenkins JNLP Agents"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # All outbound traffic (Jenkins pulls from npm, maven, docker hub)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-jenkins-sg"
  }
}

# ── SonarQube Security Group ───────────────────────────────────────────────────
resource "aws_security_group" "sonarqube" {
  name        = "${var.project_name}-sonarqube-sg"
  description = "Security group for SonarQube static analysis server"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # SonarQube Web UI + API
  ingress {
    description = "SonarQube UI + API"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_access_cidr]
  }

  # Allow Jenkins to call SonarQube API
  ingress {
    description     = "Jenkins → SonarQube"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sonarqube-sg"
  }
}

# ── Nexus Security Group ───────────────────────────────────────────────────────
resource "aws_security_group" "nexus" {
  name        = "${var.project_name}-nexus-sg"
  description = "Security group for Nexus artifact repository"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Nexus Web UI + Maven/NPM repository
  ingress {
    description = "Nexus UI + Repository"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.allowed_access_cidr]
  }

  # Allow Jenkins to upload artifacts
  ingress {
    description     = "Jenkins → Nexus"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  # Allow EKS nodes to pull artifacts (optional)
  ingress {
    description = "EKS → Nexus"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nexus-sg"
  }
}

# ── EKS Worker Node Security Group ────────────────────────────────────────────
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # All traffic within the VPC (node-to-node, node-to-control-plane)
  ingress {
    description = "All VPC internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow NodePort services to be accessed from outside VPC
  ingress {
    description = "NodePort range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.allowed_access_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-nodes-sg"
    # EKS requires this tag on node security groups
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
  }
}
