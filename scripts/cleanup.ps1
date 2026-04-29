# ─────────────────────────────────────────────────────────────────────────────
# scripts/cleanup.ps1 — Tear Down Entire DevSecOps Environment
#
# WHAT THIS DOES:
#   1. Removes Kubernetes deployments + namespace
#   2. Uninstalls Argo CD
#   3. Stops and removes Docker containers (Jenkins, SonarQube, Nexus, Registry)
#   4. Removes Docker volumes (optionally — data is lost!)
#   5. Removes Docker network
#
# USAGE:
#   .\scripts\cleanup.ps1              → Remove containers (keeps volumes)
#   .\scripts\cleanup.ps1 -RemoveData → Remove containers AND all data volumes
#
# ⚠️  WARNING: -RemoveData will permanently delete all Jenkins jobs,
#             SonarQube configurations, and Nexus repositories!
# ─────────────────────────────────────────────────────────────────────────────

param(
    [switch]$RemoveData = $false,
    [switch]$Force      = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"  # Don't fail if containers already stopped

function Write-Step { param($msg) Write-Host "`n🔷 $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  ✅ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  ⚠️  $msg" -ForegroundColor Yellow }

Write-Host @"

╔══════════════════════════════════════════════════════════╗
║   DevSecOps Pipeline — Cleanup / Teardown                ║
"@ -ForegroundColor Red

if ($RemoveData) {
    Write-Host "║   ⚠️  DATA VOLUMES WILL BE DELETED — DATA LOSS!          ║" -ForegroundColor Red
}

Write-Host @"
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Red

# Confirm if not forced
if (-not $Force) {
    $confirm = Read-Host "`nAre you sure? Type 'YES' to continue"
    if ($confirm -ne "YES") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: Remove Kubernetes Resources
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 1: Removing Kubernetes resources..."

try {
    kubectl delete -f "$PSScriptRoot\..\monitoring\grafana\"    --ignore-not-found=true 2>$null
    kubectl delete -f "$PSScriptRoot\..\monitoring\prometheus\" --ignore-not-found=true 2>$null
    kubectl delete -f "$PSScriptRoot\..\k8s\"                  --ignore-not-found=true 2>$null
    Write-Ok "Application Kubernetes resources removed."

    kubectl delete namespace argocd --ignore-not-found=true 2>$null
    Write-Ok "Argo CD namespace removed."

    kubectl delete namespace devsecops --ignore-not-found=true 2>$null
    Write-Ok "devsecops namespace removed."
} catch {
    Write-Warn "Kubernetes cleanup: some resources may not have existed."
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: Stop and Remove Docker Containers
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 2: Stopping and removing Docker containers..."

$containers = @("jenkins", "sonarqube", "nexus", "registry")

foreach ($container in $containers) {
    $exists = docker ps -a --filter "name=^${container}$" --format "{{.Names}}" 2>$null
    if ($exists) {
        docker stop $container 2>$null | Out-Null
        docker rm   $container 2>$null | Out-Null
        Write-Ok "Removed container: $container"
    } else {
        Write-Warn "Container not found: $container (already removed)"
    }
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: Remove Docker Volumes (optional)
# ════════════════════════════════════════════════════════════════════════════
if ($RemoveData) {
    Write-Step "STEP 3: Removing Docker volumes (ALL DATA DELETED)..."

    $volumes = @("jenkins_home", "sonarqube_data", "sonarqube_logs",
                 "sonarqube_extensions", "nexus_data", "trivy-cache")

    foreach ($vol in $volumes) {
        docker volume rm $vol 2>$null | Out-Null
        Write-Ok "Removed volume: $vol"
    }
} else {
    Write-Warn "STEP 3: Volumes preserved (data kept). Use -RemoveData to delete."
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: Remove Docker Network
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 4: Removing Docker network..."

docker network rm devsecops-net 2>$null | Out-Null
Write-Ok "Docker network 'devsecops-net' removed."

# ════════════════════════════════════════════════════════════════════════════
# STEP 5: Clean up docker images
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 5: Pruning unused Docker images..."
docker image prune -f 2>$null | Out-Null
Write-Ok "Unused images pruned."

Write-Host @"

╔══════════════════════════════════════════════════╗
║   ✅  CLEANUP COMPLETE                           ║
"@ -ForegroundColor Green

if ($RemoveData) {
    Write-Host "║   All containers, volumes, and data REMOVED.    ║" -ForegroundColor Green
} else {
    Write-Host "║   Containers removed. Data volumes preserved.   ║" -ForegroundColor Green
    Write-Host "║   Run .\scripts\setup.ps1 to restart.           ║" -ForegroundColor Green
}

Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Green
