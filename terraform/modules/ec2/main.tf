# ─────────────────────────────────────────────────────────────────────────────
# terraform/modules/ec2/main.tf
#
# CREATES 3 EC2 INSTANCES:
#   1. Jenkins  — CI/CD orchestrator (t3.medium, public subnet)
#   2. SonarQube — SAST code quality (t3.medium, public subnet)
#   3. Nexus    — Artifact repository (t3.small, public subnet)
#
# BOOTSTRAPPING:
#   Each instance uses a user_data script that:
#   1. Updates the OS
#   2. Installs Docker
#   3. Starts the respective tool as a Docker container
#   4. Persists data to EBS-backed volumes
#
# WHY DOCKER FOR TOOLS ON EC2:
#   Avoids OS-level package conflicts. Same Docker run commands as local setup.
#   Easy upgrades: stop container, pull new image, restart.
# ─────────────────────────────────────────────────────────────────────────────

# ── SSH Key Pair ──────────────────────────────────────────────────────────────
# Generates an RSA key pair, stores private key in SSM Parameter Store
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.main.public_key_openssh

  tags = {
    Name = "${var.project_name}-key-pair"
  }
}

# Store private key in SSM (access via AWS Console or CLI)
resource "aws_ssm_parameter" "private_key" {
  name        = "/${var.project_name}/ec2/private-key"
  type        = "SecureString"
  value       = tls_private_key.main.private_key_pem
  description = "EC2 private key for ${var.project_name}"

  tags = {
    Name = "${var.project_name}-private-key"
  }
}

# Save private key locally too (for convenience)
resource "local_file" "private_key" {
  content         = tls_private_key.main.private_key_pem
  filename        = "${path.module}/../../../keys/${var.key_pair_name}.pem"
  file_permission = "0400" # Read-only, owner only
}

# ── IAM Instance Profile for EC2 ─────────────────────────────────────────────
# WHY: Jenkins needs to push/pull from ECR and describe EKS clusters.
#      IAM role on the instance is more secure than storing AWS keys on the server.
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# ECR Full Access (Jenkins needs to push images)
resource "aws_iam_role_policy_attachment" "ecr_full" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# EKS access (Jenkins updates kubeconfig)
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# SSM access (read secrets from Parameter Store)
resource "aws_iam_role_policy_attachment" "ssm_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

# CloudWatch logs (Jenkins build logs)
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_instance_profile" "main" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# ── Jenkins EC2 Instance ───────────────────────────────────────────────────────
resource "aws_instance" "jenkins" {
  ami                    = var.ami_id
  instance_type          = var.jenkins_instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.jenkins_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.main.name

  # 30 GB root volume for Jenkins workspace + Docker images
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-jenkins-volume"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data/jenkins.sh", {
    project_name = var.project_name
    aws_region   = var.aws_region
    ecr_registry = var.ecr_registry
  }))

  tags = {
    Name = "${var.project_name}-jenkins"
    Role = "CI-Orchestrator"
  }

  # Ensure the instance is replaced (not updated in-place) if user_data changes
  lifecycle {
    create_before_destroy = true
  }
}

# ── SonarQube EC2 Instance ────────────────────────────────────────────────────
resource "aws_instance" "sonarqube" {
  ami                    = var.ami_id
  instance_type          = var.sonarqube_instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.sonarqube_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.main.name

  # 20 GB — SonarQube stores analysis data locally (Elasticsearch)
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-sonarqube-volume"
    }
  }

  user_data = base64encode(file("${path.module}/user_data/sonarqube.sh"))

  tags = {
    Name = "${var.project_name}-sonarqube"
    Role = "SAST-Scanner"
  }
}

# ── Nexus EC2 Instance ─────────────────────────────────────────────────────────
resource "aws_instance" "nexus" {
  ami                    = var.ami_id
  instance_type          = var.nexus_instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.nexus_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.main.name

  # 30 GB for Maven artifact storage
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-nexus-volume"
    }
  }

  user_data = base64encode(file("${path.module}/user_data/nexus.sh"))

  tags = {
    Name = "${var.project_name}-nexus"
    Role = "Artifact-Repository"
  }
}

# ── Elastic IPs for stable public addresses ────────────────────────────────────
# WHY: Stopped/restarted EC2 instances get new public IPs by default.
#      Elastic IPs are static — Jenkins URL stays the same even after restart.
resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-jenkins-eip"
  }
}

resource "aws_eip" "sonarqube" {
  instance = aws_instance.sonarqube.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-sonarqube-eip"
  }
}

resource "aws_eip" "nexus" {
  instance = aws_instance.nexus.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-nexus-eip"
  }
}
