# ─────────────────────────────────────────────────────────────────────────────
# scripts/setup.ps1 — Full Environment Bootstrap
#
# WHAT THIS DOES:
#   1. Verifies Docker Desktop and Kubernetes are running
#   2. Creates a Docker bridge network for inter-container communication
#   3. Starts Jenkins, SonarQube, Nexus as Docker containers
#   4. Starts a local Docker Registry
#   5. Generates Cosign key pair
#   6. Creates Kubernetes namespace and secrets
#   7. Deploys Argo CD to Kubernetes
#   8. Deploys Prometheus and Grafana to Kubernetes
#
# USAGE:
#   PowerShell (Run as Administrator):
#     .\scripts\setup.ps1
#
# REQUIREMENTS:
#   - Docker Desktop running with Kubernetes enabled
#   - Internet access (to pull Docker images)
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$DockerRegistry    = "localhost:5000",
    [string]$JenkinsPort       = "8080",
    [string]$SonarPort         = "9000",
    [string]$NexusPort         = "8081",
    [string]$RegistryPort      = "5000",
    [string]$CosignPassword    = "DevSecOps@2024",
    [switch]$SkipArgoCD        = $false,
    [switch]$SkipMonitoring    = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Colors ────────────────────────────────────────────────────────────────────
function Write-Step   { param($msg) Write-Host "`n🔷 $msg" -ForegroundColor Cyan }
function Write-Ok     { param($msg) Write-Host "  ✅ $msg" -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "  ⚠️  $msg" -ForegroundColor Yellow }
function Write-Err    { param($msg) Write-Host "  ❌ $msg" -ForegroundColor Red }
function Write-Info   { param($msg) Write-Host "  ℹ️  $msg" -ForegroundColor White }

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║   DevSecOps Pipeline — Full Environment Setup                ║
║   Docker Desktop | Jenkins | SonarQube | Nexus | Argo CD    ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: Verify Prerequisites
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 1: Verifying prerequisites..."

# Docker
try {
    $dockerVer = docker version --format '{{.Server.Version}}' 2>&1
    Write-Ok "Docker Desktop: $dockerVer"
} catch {
    Write-Err "Docker Desktop is not running. Please start Docker Desktop first."
    exit 1
}

# Kubernetes
try {
    $k8sVer = kubectl version --client --short 2>&1
    Write-Ok "kubectl: $k8sVer"
    $nodes = kubectl get nodes --no-headers 2>$null
    if ($nodes -match "Ready") {
        Write-Ok "Kubernetes cluster: Ready"
    } else {
        Write-Warn "Kubernetes not ready. Enable it in Docker Desktop Settings → Kubernetes."
        Write-Warn "Skipping Kubernetes-dependent steps..."
        $SkipArgoCD = $true
        $SkipMonitoring = $true
    }
} catch {
    Write-Warn "kubectl not found. Skipping Kubernetes steps."
    $SkipArgoCD = $true
    $SkipMonitoring = $true
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: Create Docker Network
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 2: Creating Docker bridge network..."

$networkExists = docker network ls --filter name=devsecops-net --format "{{.Name}}" 2>$null
if ($networkExists -eq "devsecops-net") {
    Write-Ok "Network 'devsecops-net' already exists."
} else {
    docker network create devsecops-net | Out-Null
    Write-Ok "Created Docker network: devsecops-net"
}

Write-Info "WHY: All containers join this network so they can reach each other by name."
Write-Info "     Example: Jenkins can reach SonarQube at http://sonarqube:9000"

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: Start Local Docker Registry
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 3: Starting local Docker Registry..."

$regExists = docker ps -a --filter name=registry --format "{{.Names}}" 2>$null
if ($regExists -eq "registry") {
    docker start registry | Out-Null
    Write-Ok "Registry container restarted."
} else {
    docker run -d `
        --name registry `
        --network devsecops-net `
        --restart always `
        -p "${RegistryPort}:5000" `
        registry:2 | Out-Null
    Write-Ok "Local Docker Registry started on port $RegistryPort"
}

Write-Info "Registry URL: $DockerRegistry"
Write-Info "Push images: docker push $DockerRegistry/devsecops-app:tag"

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: Start Jenkins
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 4: Starting Jenkins CI server..."

$jenkinsExists = docker ps -a --filter name=jenkins --format "{{.Names}}" 2>$null
if ($jenkinsExists -eq "jenkins") {
    docker start jenkins | Out-Null
    Write-Ok "Jenkins container restarted."
} else {
    # Create named volume for Jenkins data persistence
    docker volume create jenkins_home | Out-Null

    docker run -d `
        --name jenkins `
        --network devsecops-net `
        --restart unless-stopped `
        -p "${JenkinsPort}:8080" `
        -p "50000:50000" `
        -v jenkins_home:/var/jenkins_home `
        -v //var/run/docker.sock:/var/run/docker.sock `
        -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" `
        -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs `
        jenkins/jenkins:lts-jdk17 | Out-Null

    Write-Ok "Jenkins started on port $JenkinsPort"
}

# Wait for Jenkins to be healthy
Write-Info "Waiting for Jenkins to start (this takes ~60 seconds)..."
$retries = 0
do {
    Start-Sleep -Seconds 10
    $retries++
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$JenkinsPort/login" -UseBasicParsing -TimeoutSec 5 2>$null
        if ($response.StatusCode -eq 200) { break }
    } catch { }
    Write-Info "  Still starting... ($($retries * 10)s)"
} while ($retries -lt 12)

if ($retries -eq 12) {
    Write-Warn "Jenkins took longer than expected. Check: http://localhost:$JenkinsPort"
} else {
    Write-Ok "Jenkins is ready at http://localhost:$JenkinsPort"
}

# Get initial admin password
try {
    $initialPass = docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    Write-Info "Jenkins initial admin password: $initialPass"
} catch {
    Write-Warn "Could not read initial password — Jenkins may already be configured."
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 5: Start SonarQube
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 5: Starting SonarQube..."

$sonarExists = docker ps -a --filter name=sonarqube --format "{{.Names}}" 2>$null
if ($sonarExists -eq "sonarqube") {
    docker start sonarqube | Out-Null
    Write-Ok "SonarQube container restarted."
} else {
    docker volume create sonarqube_data      | Out-Null
    docker volume create sonarqube_logs      | Out-Null
    docker volume create sonarqube_extensions| Out-Null

    docker run -d `
        --name sonarqube `
        --network devsecops-net `
        --restart unless-stopped `
        -p "${SonarPort}:9000" `
        -v sonarqube_data:/opt/sonarqube/data `
        -v sonarqube_logs:/opt/sonarqube/logs `
        -v sonarqube_extensions:/opt/sonarqube/extensions `
        -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true `
        sonarqube:10-community | Out-Null

    Write-Ok "SonarQube started on port $SonarPort"
}

Write-Info "SonarQube URL: http://localhost:$SonarPort"
Write-Info "Default credentials: admin / admin (change on first login)"
Write-Info "⚠️  SonarQube takes 2-3 minutes to initialize fully."

# ════════════════════════════════════════════════════════════════════════════
# STEP 6: Start Nexus
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 6: Starting Nexus Repository Manager..."

$nexusExists = docker ps -a --filter name=nexus --format "{{.Names}}" 2>$null
if ($nexusExists -eq "nexus") {
    docker start nexus | Out-Null
    Write-Ok "Nexus container restarted."
} else {
    docker volume create nexus_data | Out-Null

    docker run -d `
        --name nexus `
        --network devsecops-net `
        --restart unless-stopped `
        -p "${NexusPort}:8081" `
        -v nexus_data:/nexus-data `
        sonatype/nexus3:latest | Out-Null

    Write-Ok "Nexus started on port $NexusPort"
}

Write-Info "Nexus URL: http://localhost:$NexusPort"
Write-Info "⚠️  Nexus takes 2-3 minutes to initialize. Check admin password with:"
Write-Info "    docker exec nexus cat /nexus-data/admin.password"

# ════════════════════════════════════════════════════════════════════════════
# STEP 7: Generate Cosign Key Pair
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 7: Generating Cosign key pair..."

$cosignKeysDir = "$PSScriptRoot\..\cosign-keys"
if (-not (Test-Path $cosignKeysDir)) {
    New-Item -ItemType Directory -Path $cosignKeysDir | Out-Null
}

if ((Test-Path "$cosignKeysDir\cosign.key") -and (Test-Path "$cosignKeysDir\cosign.pub")) {
    Write-Ok "Cosign keys already exist — skipping generation."
} else {
    Write-Info "Generating Cosign key pair with password: [provided]"

    # Generate keys using Cosign Docker image
    $cosignPassEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CosignPassword))

    docker run --rm `
        -v "${cosignKeysDir}:/workspace" `
        -w /workspace `
        -e "COSIGN_PASSWORD=$CosignPassword" `
        gcr.io/projectsigstore/cosign:latest generate-key-pair 2>&1 | Out-Null

    if ((Test-Path "$cosignKeysDir\cosign.key") -and (Test-Path "$cosignKeysDir\cosign.pub")) {
        Write-Ok "Cosign keys generated:"
        Write-Info "  Private key: cosign-keys\cosign.key  (⚠️  KEEP SECRET)"
        Write-Info "  Public key:  cosign-keys\cosign.pub  (share freely)"
    } else {
        Write-Warn "Cosign key generation failed. Check Docker Hub connectivity."
    }
}

Write-Info "NEXT STEP: Upload cosign.key and cosign.pub to Jenkins Credentials Store."
Write-Info "  Jenkins → Credentials → Global → Add Credential → Secret File"
Write-Info "  ID for key: 'cosign-private-key'"
Write-Info "  ID for pub: 'cosign-public-key'"

# ════════════════════════════════════════════════════════════════════════════
# STEP 8: Kubernetes Setup
# ════════════════════════════════════════════════════════════════════════════
if (-not $SkipArgoCD) {
    Write-Step "STEP 8: Setting up Kubernetes namespace and secrets..."

    # Create namespace
    kubectl apply -f "$PSScriptRoot\..\k8s\namespace.yaml" | Out-Null
    Write-Ok "Namespace 'devsecops' created/updated."

    # Create Docker registry pull secret
    $registrySecretExists = kubectl get secret registry-secret -n devsecops 2>$null
    if ($LASTEXITCODE -ne 0) {
        kubectl create secret docker-registry registry-secret `
            --docker-server=$DockerRegistry `
            --docker-username=admin `
            --docker-password=admin123 `
            -n devsecops | Out-Null
        Write-Ok "Docker registry pull secret created."
    } else {
        Write-Ok "Docker registry secret already exists."
    }

    # ── STEP 9: Install Argo CD ──────────────────────────────────────────────
    Write-Step "STEP 9: Installing Argo CD..."

    $argoCDNS = kubectl get namespace argocd 2>$null
    if ($LASTEXITCODE -ne 0) {
        kubectl create namespace argocd | Out-Null
    }

    # Use official stable release
    kubectl apply -n argocd `
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml | Out-Null

    Write-Ok "Argo CD installation applied."
    Write-Info "Waiting for Argo CD to be ready (this takes ~2 minutes)..."

    kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

    # Patch Argo CD server to use NodePort for local access
    kubectl patch svc argocd-server -n argocd `
        -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "nodePort": 30443}]}}' | Out-Null

    Write-Ok "Argo CD ready! Access at: https://localhost:30443"

    # Get initial admin password
    Start-Sleep -Seconds 10
    try {
        $argoPass = kubectl -n argocd get secret argocd-initial-admin-secret `
            -o jsonpath="{.data.password}" 2>$null
        if ($argoPass) {
            $argoPassDecoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($argoPass))
            Write-Info "Argo CD initial admin password: $argoPassDecoded"
        }
    } catch {
        Write-Warn "Could not retrieve Argo CD password. Run:"
        Write-Info "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    }
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 10: Deploy Monitoring (Prometheus + Grafana)
# ════════════════════════════════════════════════════════════════════════════
if (-not $SkipMonitoring) {
    Write-Step "STEP 10: Deploying Prometheus and Grafana..."

    kubectl apply -f "$PSScriptRoot\..\monitoring\prometheus\" | Out-Null
    kubectl apply -f "$PSScriptRoot\..\monitoring\grafana\"    | Out-Null

    Write-Ok "Monitoring stack deployed."
    Write-Info "Prometheus: http://localhost:30090"
    Write-Info "Grafana:    http://localhost:30030  (admin / admin123)"
}

# ════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════════════════
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════╗
║   ✅  SETUP COMPLETE — Service URLs                                      ║
╠══════════════════════════════════════════════════════════════════════════╣
║   Jenkins      →  http://localhost:8080   (admin / <initial-password>)  ║
║   SonarQube    →  http://localhost:9000   (admin / admin)               ║
║   Nexus        →  http://localhost:8081   (admin / <from volume>)       ║
║   Docker Reg   →  localhost:5000                                         ║
║   Argo CD      →  https://localhost:30443 (admin / <from secret>)       ║
║   Prometheus   →  http://localhost:30090                                 ║
║   Grafana      →  http://localhost:30030  (admin / admin123)            ║
║   App (after deploy) → http://localhost:30080                            ║
╠══════════════════════════════════════════════════════════════════════════╣
║   NEXT STEPS:                                                            ║
║   1. Open Jenkins → Install suggested plugins                            ║
║   2. Add credentials (SonarQube token, Nexus, Cosign keys)              ║
║   3. Create Pipeline job → Use Jenkinsfile from SCM                     ║
║   4. Push code to GitHub → Pipeline triggers automatically               ║
╚══════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
