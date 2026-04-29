output "jenkins_public_ip" { value = aws_eip.jenkins.public_ip }
output "sonarqube_public_ip" { value = aws_eip.sonarqube.public_ip }
output "nexus_public_ip" { value = aws_eip.nexus.public_ip }
output "jenkins_private_ip" { value = aws_instance.jenkins.private_ip }
output "sonarqube_private_ip" { value = aws_instance.sonarqube.private_ip }
output "nexus_private_ip" { value = aws_instance.nexus.private_ip }
output "key_pair_name" { value = aws_key_pair.main.key_name }
output "private_key_pem" {
  value     = tls_private_key.main.private_key_pem
  sensitive = true
}
# IAM Role ARN — used by ECR module policy and EKS aws-auth ConfigMap
output "jenkins_iam_role_arn" { value = aws_iam_role.ec2_role.arn }
