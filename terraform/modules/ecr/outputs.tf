output "repository_url" { value = aws_ecr_repository.app.repository_url }
output "repository_name" { value = aws_ecr_repository.app.name }
output "registry_id" { value = aws_ecr_repository.app.registry_id }

# Helper: ECR registry host (used in docker login command)
# Format: <account-id>.dkr.ecr.<region>.amazonaws.com
output "registry_host" {
  value = "${aws_ecr_repository.app.registry_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

data "aws_region" "current" {}
