#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# user_data/jenkins.sh — EC2 Bootstrap Script for Jenkins
#
# RUNS AUTOMATICALLY on first boot of the Jenkins EC2 instance.
# Logs everything to /var/log/user-data.log for debugging.
#
# WHAT IT DOES:
#   1. Updates OS packages
#   2. Installs Docker + Docker Compose
#   3. Installs AWS CLI v2 (for ECR push, EKS kubectl config)
#   4. Installs kubectl (to apply K8s manifests from Jenkins)
#   5. Installs git (for checkout in pipeline)
#   6. Starts Jenkins as a Docker container with:
#      - Docker socket mounted (so Jenkins can run Docker commands)
#      - Persistent volume for jobs/config
#      - JCasC config file
# ─────────────────────────────────────────────────────────────────────────────
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "========================================="
echo "  Jenkins Bootstrap Starting"
echo "  $(date)"
echo "========================================="

# ── Variables (injected by Terraform templatefile) ───────────────────────────
PROJECT_NAME="${project_name}"
AWS_REGION="${aws_region}"
ECR_REGISTRY="${ecr_registry}"

# ── 1. System Update ──────────────────────────────────────────────────────────
echo "[STEP 1] Updating system packages..."
dnf update -y
dnf install -y git curl wget unzip jq

# ── 2. Install Docker ─────────────────────────────────────────────────────────
echo "[STEP 2] Installing Docker..."
dnf install -y docker
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group so Jenkins container can access socket
usermod -aG docker ec2-user

# ── 3. Install AWS CLI v2 ─────────────────────────────────────────────────────
echo "[STEP 3] Installing AWS CLI v2..."
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# Verify
aws --version

# ── 4. Install kubectl ────────────────────────────────────────────────────────
echo "[STEP 4] Installing kubectl..."
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl
kubectl version --client

# ── 5. Install Trivy ──────────────────────────────────────────────────────────
echo "[STEP 5] Installing Trivy..."
# Trivy runs as Docker container in pipeline, but also install CLI for convenience
TRIVY_VERSION=$(curl -fsSL https://api.github.com/repos/aquasecurity/trivy/releases/latest | jq -r '.tag_name' | tr -d 'v')
curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v$${TRIVY_VERSION}/trivy_$${TRIVY_VERSION}_Linux-64bit.rpm"
rpm -i "trivy_$${TRIVY_VERSION}_Linux-64bit.rpm" || true
rm -f "trivy_$${TRIVY_VERSION}_Linux-64bit.rpm"

# ── 6. Configure ECR Login Helper ─────────────────────────────────────────────
echo "[STEP 6] Configuring Docker ECR credential helper..."
mkdir -p /root/.docker
cat > /root/.docker/config.json <<'DOCKEREOF'
{
  "credHelpers": {
    "*.amazonaws.com": "ecr-login"
  }
}
DOCKEREOF

# Install ECR credential helper
dnf install -y amazon-ecr-credential-helper || true

# ── 7. Create Jenkins Volumes ─────────────────────────────────────────────────
echo "[STEP 7] Creating Docker volumes for Jenkins persistence..."
docker volume create jenkins_home

# ── 8. Create JCasC Config ────────────────────────────────────────────────────
echo "[STEP 8] Setting up Jenkins Configuration as Code..."
mkdir -p /opt/jenkins/casc

cat > /opt/jenkins/casc/jenkins.yaml <<'CASCEOF'
jenkins:
  systemMessage: |
    ====================================================
    DevSecOps CI/CD Pipeline — Jenkins on AWS
    Managed by Terraform + JCasC
    ====================================================
  numExecutors: 4
  mode: NORMAL

  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "admin"
          password: "admin123"

  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false

tool:
  maven:
    installations:
      - name: "Maven-3.9"
        properties:
          - installSource:
              installers:
                - maven:
                    id: "3.9.6"

unclassified:
  sonarGlobalConfiguration:
    buildWrapperEnabled: true
    installations:
      - name: "SonarQube"
        serverUrl: "http://SONAR_PRIVATE_IP:9000"
        credentialsId: "sonarqube-token"
CASCEOF

# ── 9. Start Jenkins Container ────────────────────────────────────────────────
echo "[STEP 9] Starting Jenkins Docker container..."
docker run -d \
    --name jenkins \
    --restart unless-stopped \
    -p 8080:8080 \
    -p 50000:50000 \
    -v jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /opt/jenkins/casc:/var/jenkins_home/casc_configs:ro \
    -v /usr/local/bin/kubectl:/usr/local/bin/kubectl:ro \
    -v /usr/local/bin/aws:/usr/local/bin/aws:ro \
    -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1g" \
    -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs \
    jenkins/jenkins:lts-jdk17

# ── 10. Configure Jenkins to use ECR ──────────────────────────────────────────
# Wait for Jenkins to start, then install plugins
echo "[STEP 10] Jenkins container started. Waiting for it to come up..."
sleep 60

# Log initial admin password (in case JCasC doesn't work)
echo "==== Jenkins Initial Admin Password ===="
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "JCasC active - no initial password needed"
echo "========================================="

echo "=============================="
echo "  Jenkins Bootstrap COMPLETE"
echo "  Access: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "  $(date)"
echo "=============================="
