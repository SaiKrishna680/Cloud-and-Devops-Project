# ─────────────────────────────────────────────────────────────────────────────
# scripts/deploy.ps1 — Deploy Application to Kubernetes
#
# WHAT THIS DOES:
#   1. Builds the Docker image locally
#   2. Runs Trivy scan (fails on HIGH/CRITICAL)
#   3. Pushes image to local registry
#   4. Applies Kubernetes manifests
#   5. Waits for rollout to complete
#   6. Prints access URL
#
# USAGE:
#   .\scripts\deploy.ps1 -ImageTag "1.0.0-42"
#   .\scripts\deploy.ps1   (uses 'latest' tag)
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$ImageTag       = "latest",
    [string]$DockerRegistry = "localhost:5000",
    [string]$AppName        = "devsecops-app",
    [switch]$SkipTrivyScan  = $false,
    [switch]$SkipCosignSign = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "`n🔷 $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  ✅ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  ⚠️  $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "  ℹ️  $msg" -ForegroundColor White }

$FullImage = "$DockerRegistry/${AppName}:$ImageTag"

Write-Host @"

╔══════════════════════════════════════════════════╗
║   DevSecOps — Deploy to Kubernetes               ║
║   Image: $FullImage
╚══════════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: Build Docker Image
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 1: Building Docker image..."

$repoRoot = "$PSScriptRoot\.."

docker build `
    -f "$repoRoot\docker\Dockerfile" `
    -t "$FullImage" `
    -t "$DockerRegistry/${AppName}:latest" `
    "$repoRoot"

Write-Ok "Image built: $FullImage"

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: Trivy Security Scan
# ════════════════════════════════════════════════════════════════════════════
if (-not $SkipTrivyScan) {
    Write-Step "STEP 2: Running Trivy vulnerability scan..."
    Write-Info "Scanning: $FullImage"
    Write-Info "Failing on: HIGH, CRITICAL"

    $trivyResult = docker run --rm `
        -v //var/run/docker.sock:/var/run/docker.sock `
        -v trivy-cache:/root/.cache/trivy `
        aquasec/trivy:latest image `
        --exit-code 1 `
        --severity HIGH,CRITICAL `
        --no-progress `
        "$FullImage"

    if ($LASTEXITCODE -eq 1) {
        Write-Host "`n❌ TRIVY FOUND HIGH/CRITICAL VULNERABILITIES — DEPLOY ABORTED!" -ForegroundColor Red
        Write-Host "   Fix: Update your base image or dependencies, then re-run." -ForegroundColor Yellow
        exit 1
    }

    Write-Ok "Trivy scan PASSED — no HIGH/CRITICAL vulnerabilities."
} else {
    Write-Warn "Trivy scan SKIPPED (--SkipTrivyScan flag set)"
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: Push Image to Registry
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 3: Pushing image to local registry..."

docker push "$FullImage"
docker push "$DockerRegistry/${AppName}:latest"
Write-Ok "Image pushed: $FullImage"

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: Update Kubernetes Manifest Image Tag
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 4: Updating Kubernetes deployment image tag..."

$deploymentFile = "$repoRoot\k8s\deployment.yaml"
$content = Get-Content $deploymentFile -Raw

# Replace image tag line
$content = $content -replace "image: $DockerRegistry/${AppName}:.*", "image: $FullImage"
Set-Content $deploymentFile $content

Write-Ok "deployment.yaml updated with image: $FullImage"

# ════════════════════════════════════════════════════════════════════════════
# STEP 5: Apply Kubernetes Manifests
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 5: Applying Kubernetes manifests..."

kubectl apply -f "$repoRoot\k8s\namespace.yaml"
kubectl apply -f "$repoRoot\k8s\secret.yaml"
kubectl apply -f "$repoRoot\k8s\deployment.yaml"
kubectl apply -f "$repoRoot\k8s\service.yaml"

Write-Ok "Kubernetes manifests applied."

# ════════════════════════════════════════════════════════════════════════════
# STEP 6: Wait for Rollout
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 6: Waiting for deployment rollout..."

kubectl rollout status deployment/devsecops-app -n devsecops --timeout=120s

Write-Ok "Deployment rolled out successfully!"

# ════════════════════════════════════════════════════════════════════════════
# STEP 7: Verify Pods Running
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 7: Verifying pods..."

kubectl get pods -n devsecops -l app=devsecops-app

# ════════════════════════════════════════════════════════════════════════════
# DONE
# ════════════════════════════════════════════════════════════════════════════
Write-Host @"

╔══════════════════════════════════════════════════════════╗
║   ✅  DEPLOYMENT COMPLETE                                ║
╠══════════════════════════════════════════════════════════╣
║   App URL:    http://localhost:30080                     ║
║   API Hello:  http://localhost:30080/api/hello           ║
║   App Health: http://localhost:30080/api/health          ║
║   Metrics:    http://localhost:30080/actuator/prometheus ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
