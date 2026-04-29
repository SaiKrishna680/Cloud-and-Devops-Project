# ─────────────────────────────────────────────────────────────────────────────
# terraform/modules/ecr/main.tf
#
# CREATES:
#   - ECR Private Repository for the Spring Boot application
#   - Lifecycle policy (keep only N most recent images)
#   - Repository policy (who can push/pull)
#
# WHY ECR instead of local registry:
#   - Integrates natively with AWS IAM — no credentials to rotate
#   - EKS nodes can pull images using their IAM role (no imagePullSecrets needed)
#   - Jenkins on EC2 uses its IAM role to push (no docker login passwords)
#   - High availability, replicated across AZs
#   - Free for 500 MB/month in private repos
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = var.repo_name
  image_tag_mutability = "MUTABLE" # Allow same tag to be overwritten

  # Enable image scanning on push (free, checks against CVE databases)
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt images at rest using AWS KMS
  encryption_configuration {
    encryption_type = "AES256" # Use KMS for higher security environments
  }

  tags = {
    Name = "${var.project_name}-ecr-repo"
  }
}

# ── Lifecycle Policy — Keep only N most recent images ─────────────────────────
# WHY: ECR storage costs money. Automatically delete old images.
#      Keep last N tagged images + always clean untagged ones.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        # Rule 1: Keep the N most recent tagged images
        rulePriority = 1
        description  = "Keep last ${var.image_retention_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["1.", "2.", "3."] # Any semver tag
          countType     = "imageCountMoreThan"
          countNumber   = var.image_retention_count
        }
        action = { type = "expire" }
      },
      {
        # Rule 2: Always delete untagged images after 1 day
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── Repository Policy — Restrict access ───────────────────────────────────────
# WHY: Only allow the Jenkins EC2 role to push; EKS nodes to pull.
#      Deny all other principals by default.
resource "aws_ecr_repository_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowJenkinsPush"
        Effect = "Allow"
        Principal = {
          AWS = var.jenkins_role_arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage"
        ]
      },
      {
        Sid    = "AllowEKSNodePull"
        Effect = "Allow"
        Principal = {
          AWS = var.eks_node_role_arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken"
        ]
      }
    ]
  })
}
