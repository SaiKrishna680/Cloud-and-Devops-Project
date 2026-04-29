# ─────────────────────────────────────────────────────────────────────────────
# terraform/outputs.tf
#
# Displays all important URLs and connection info after `terraform apply`.
# Run `terraform output` at any time to see these values.
# ─────────────────────────────────────────────────────────────────────────────

# ── EC2 Tool Servers ──────────────────────────────────────────────────────────
output "jenkins_url" {
  description = "Jenkins CI server URL — open in browser after 3 min"
  value       = "http://${module.ec2.jenkins_public_ip}:8080"
}

output "jenkins_ssh" {
  description = "SSH command to access Jenkins server"
  value       = "ssh -i keys/devsecops-key.pem ec2-user@${module.ec2.jenkins_public_ip}"
}

output "sonarqube_url" {
  description = "SonarQube code quality server URL"
  value       = "http://${module.ec2.sonarqube_public_ip}:9000"
}

output "sonarqube_ssh" {
  description = "SSH command to access SonarQube server"
  value       = "ssh -i keys/devsecops-key.pem ec2-user@${module.ec2.sonarqube_public_ip}"
}

output "nexus_url" {
  description = "Nexus artifact repository URL"
  value       = "http://${module.ec2.nexus_public_ip}:8081"
}

output "nexus_ssh" {
  description = "SSH command to access Nexus server"
  value       = "ssh -i keys/devsecops-key.pem ec2-user@${module.ec2.nexus_public_ip}"
}

# ── ECR ───────────────────────────────────────────────────────────────────────
output "ecr_repository_url" {
  description = "ECR repository URL — use as Docker image prefix"
  value       = module.ecr.repository_url
}

output "ecr_registry_host" {
  description = "ECR registry host — use in docker login command"
  value       = module.ecr.registry_host
}

output "ecr_login_command" {
  description = "Command to authenticate Docker with ECR (run on Jenkins or locally)"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.registry_host}"
}

# ── EKS ───────────────────────────────────────────────────────────────────────
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "AWS CLI command to update local kubeconfig for kubectl access"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ── Argo CD ──────────────────────────────────────────────────────────────────
output "argocd_note" {
  description = "How to get Argo CD external URL after Helm deploy"
  value       = "kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "argocd_admin_password_command" {
  description = "Command to retrieve Argo CD initial admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

# ── Grafana ───────────────────────────────────────────────────────────────────
output "grafana_note" {
  description = "How to get Grafana external URL"
  value       = "kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "grafana_credentials" {
  description = "Grafana login credentials"
  value       = "admin / admin123"
}

# ── Credentials ───────────────────────────────────────────────────────────────
output "nexus_password_command" {
  description = "Command to retrieve Nexus initial admin password (SSH into Nexus first)"
  value       = "ssh -i keys/devsecops-key.pem ec2-user@${module.ec2.nexus_public_ip} 'docker exec nexus cat /nexus-data/admin.password'"
}

output "jenkins_initial_password_command" {
  description = "Command to retrieve Jenkins initial admin password"
  value       = "ssh -i keys/devsecops-key.pem ec2-user@${module.ec2.jenkins_public_ip} 'docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword'"
}

# ── Cost Warning ──────────────────────────────────────────────────────────────
output "cost_warning" {
  description = "Estimated cost warning"
  value       = "⚠️  COST: This infrastructure costs ~$3-5/day. Run 'terraform destroy' when not in use!"
}

# ── Summary ───────────────────────────────────────────────────────────────────
output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-EOT

    ═══════════════════════════════════════════════════════════
    NEXT STEPS AFTER TERRAFORM APPLY:
    ═══════════════════════════════════════════════════════════

    1. Update kubeconfig:
       aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}

    2. Access Jenkins (wait 3-5 min for startup):
       http://${module.ec2.jenkins_public_ip}:8080

    3. Get Jenkins initial password:
       ssh -i keys/devsecops-key.pem ec2-user@${module.ec2.jenkins_public_ip} \
         'docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword'

    4. Access SonarQube (wait 5 min for startup):
       http://${module.ec2.sonarqube_public_ip}:9000
       (admin / admin)

    5. Access Nexus (wait 3 min):
       http://${module.ec2.nexus_public_ip}:8081

    6. Update jenkins/Jenkinsfile:
       Set ECR_REGISTRY = ${module.ecr.registry_host}
       Set SONAR_HOST = http://${module.ec2.sonarqube_private_ip}:9000
       Set NEXUS_URL = http://${module.ec2.nexus_private_ip}:8081

    7. Apply Argo CD application:
       kubectl apply -f argocd/application.yaml -n argocd

    ═══════════════════════════════════════════════════════════
  EOT
}
