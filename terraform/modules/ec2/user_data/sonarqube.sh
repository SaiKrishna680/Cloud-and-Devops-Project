#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# user_data/sonarqube.sh — EC2 Bootstrap Script for SonarQube
#
# REQUIREMENTS:
#   - t3.medium minimum (SonarQube + Elasticsearch need 2GB RAM)
#   - vm.max_map_count must be set (Elasticsearch requirement)
# ─────────────────────────────────────────────────────────────────────────────
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "========================================="
echo "  SonarQube Bootstrap Starting"
echo "  $(date)"
echo "========================================="

# ── 1. System Update ──────────────────────────────────────────────────────────
dnf update -y
dnf install -y docker

# ── 2. Elasticsearch kernel parameter (REQUIRED by SonarQube) ─────────────────
# WHY: Elasticsearch (embedded in SonarQube) needs vm.max_map_count >= 262144.
#      Without this, SonarQube fails to start with an Elasticsearch error.
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
echo "fs.file-max=65536"       >> /etc/sysctl.conf
sysctl -p

# Also set ulimits
cat >> /etc/security/limits.conf <<'EOF'
sonarqube   -   nofile   65536
sonarqube   -   nproc    4096
EOF

# ── 3. Start Docker ───────────────────────────────────────────────────────────
systemctl enable docker
systemctl start docker

# ── 4. Create Persistent Volumes ─────────────────────────────────────────────
docker volume create sonarqube_data
docker volume create sonarqube_logs
docker volume create sonarqube_extensions

# ── 5. Pull SonarQube Image ───────────────────────────────────────────────────
echo "Pulling SonarQube image..."
docker pull sonarqube:10-community

# ── 6. Start SonarQube Container ─────────────────────────────────────────────
echo "Starting SonarQube container..."
docker run -d \
    --name sonarqube \
    --restart unless-stopped \
    -p 9000:9000 \
    -v sonarqube_data:/opt/sonarqube/data \
    -v sonarqube_logs:/opt/sonarqube/logs \
    -v sonarqube_extensions:/opt/sonarqube/extensions \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    -e SONAR_JDBC_URL="" \
    --memory="2g" \
    --memory-swap="2g" \
    sonarqube:10-community

echo "=============================="
echo "  SonarQube Bootstrap COMPLETE"
echo "  Access: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo "  Default credentials: admin / admin"
echo "  IMPORTANT: SonarQube takes 3-5 min to fully initialize"
echo "  $(date)"
echo "=============================="
