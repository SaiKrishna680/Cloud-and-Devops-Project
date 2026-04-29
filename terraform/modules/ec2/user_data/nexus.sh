#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# user_data/nexus.sh — EC2 Bootstrap Script for Nexus Repository Manager
# ─────────────────────────────────────────────────────────────────────────────
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "========================================="
echo "  Nexus Bootstrap Starting"
echo "  $(date)"
echo "========================================="

# ── 1. System Update ──────────────────────────────────────────────────────────
dnf update -y
dnf install -y docker

# ── 2. Start Docker ───────────────────────────────────────────────────────────
systemctl enable docker
systemctl start docker

# ── 3. Create Persistent Volume ───────────────────────────────────────────────
docker volume create nexus_data

# ── 4. Pull and Start Nexus ───────────────────────────────────────────────────
echo "Pulling Nexus image..."
docker pull sonatype/nexus3:latest

echo "Starting Nexus container..."
docker run -d \
    --name nexus \
    --restart unless-stopped \
    -p 8081:8081 \
    -v nexus_data:/nexus-data \
    --memory="2g" \
    sonatype/nexus3:latest

echo "Nexus started. Waiting 2 min for initialization..."
sleep 120

echo "=============================="
echo "  Nexus Bootstrap COMPLETE"
echo "  Access: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "  Admin password: docker exec nexus cat /nexus-data/admin.password"
echo "  $(date)"
echo "=============================="
