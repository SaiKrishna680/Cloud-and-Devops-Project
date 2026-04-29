# 🚀 DevSecOps CI/CD Pipeline — Java Spring Boot on Docker Desktop (Windows)

> **Production-ready, end-to-end DevSecOps pipeline running entirely on Docker Desktop with Kubernetes enabled.**

---

## 📋 Project Overview

This project implements a full **DevSecOps CI/CD pipeline** for a Java Spring Boot application, running locally on **Windows 10/11 with Docker Desktop**. No cloud infrastructure required — everything runs as Docker containers or Kubernetes workloads on your local machine.

### Architecture Flow

```
GitHub → Jenkins → Maven Build → SonarQube Scan → Quality Gate
       → Nexus Upload → Docker Build → Trivy Scan → Cosign Sign
       → Docker Registry → Argo CD → Kubernetes → Prometheus → Grafana
```

---

## 🗂️ Project Structure

```
Devops/      (https://github.com/Deepak122006/Devops.git)
│
├── app/                            # Spring Boot Application
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/devsecops/
│   │   │   │   ├── DevSecOpsApplication.java
│   │   │   │   └── controller/
│   │   │   │       └── HelloController.java
│   │   │   └── resources/
│   │   │       └── application.properties
│   │   └── test/
│   │       └── java/com/devsecops/
│   │           └── HelloControllerTest.java
│   └── pom.xml
│
├── docker/                         # Docker Configuration
│   ├── Dockerfile                  # Multi-stage production build
│   └── .dockerignore
│
├── jenkins/                        # Jenkins Configuration
│   ├── plugins.txt                 # Jenkins plugins list
│   ├── Jenkinsfile                 # Full pipeline definition
│   └── casc/                       # Jenkins Configuration as Code
│       └── jenkins.yaml
│
├── k8s/                            # Kubernetes Manifests
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── secret.yaml
│
├── argocd/                         # Argo CD Configuration
│   ├── install.yaml                # Argo CD installation
│   └── application.yaml            # App manifest for GitOps
│
├── monitoring/                     # Prometheus + Grafana
│   ├── prometheus/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── prometheus.yml          # Scrape config
│   └── grafana/
│       ├── deployment.yaml
│       └── service.yaml
│
├── scripts/                        # Automation Scripts (PowerShell)
│   ├── setup.ps1                   # Bootstrap everything
│   ├── deploy.ps1                  # Deploy to Kubernetes
│   └── cleanup.ps1                 # Tear everything down
│
├── Makefile                        # Developer shortcuts
└── README.md                       # This file
```

---

## 📅 Project Timeline & Phases

| Phase | Title                        | Duration Est. | Status |
|-------|------------------------------|---------------|--------|
| 0     | Prerequisites & Env Setup    | 30 min        | ⬜     |
| 1     | Spring Boot Application      | 20 min        | ⬜     |
| 2     | Docker Multi-Stage Build     | 15 min        | ⬜     |
| 3     | Jenkins Setup                | 30 min        | ⬜     |
| 4     | SonarQube Integration        | 20 min        | ⬜     |
| 5     | Nexus Artifact Repository    | 20 min        | ⬜     |
| 6     | Trivy Security Scanning      | 15 min        | ⬜     |
| 7     | Cosign Image Signing         | 15 min        | ⬜     |
| 8     | Full Jenkinsfile Pipeline     | 30 min        | ⬜     |
| 9     | Kubernetes Manifests          | 20 min        | ⬜     |
| 10    | Argo CD GitOps Setup         | 25 min        | ⬜     |
| 11    | Prometheus + Grafana         | 20 min        | ⬜     |
| 12    | Automation Scripts           | 15 min        | ⬜     |
| **T** | **Total Setup Time**         | **~4.5 hrs**  |        |

---

## ⚙️ Tool Stack & Ports

| Tool        | Docker Image                        | Port  | Purpose                      |
|-------------|-------------------------------------|-------|------------------------------|
| Jenkins     | jenkins/jenkins:lts-jdk17           | 8080  | CI/CD Orchestrator           |
| SonarQube   | sonarqube:10-community              | 9000  | SAST / Code Quality          |
| Nexus       | sonatype/nexus3:latest              | 8081  | Artifact Repository          |
| Trivy       | aquasec/trivy:latest                | -     | Container Security Scanning  |
| Cosign      | gcr.io/projectsigstore/cosign       | -     | Image Signing & Verification |
| Argo CD     | quay.io/argoproj/argocd             | 8443  | GitOps Deployment            |
| Prometheus  | prom/prometheus:latest              | 9090  | Metrics Collection           |
| Grafana     | grafana/grafana:latest              | 3000  | Metrics Dashboards           |
| App         | Custom (built by pipeline)          | 8088  | Spring Boot REST API         |

---

## 🔒 Security Features

| Feature              | Tool     | Pipeline Failure Condition         |
|----------------------|----------|------------------------------------|
| SAST Code Scanning   | SonarQube| Quality Gate = FAILED → Pipeline stops |
| Container Scanning   | Trivy    | HIGH or CRITICAL CVE found → Pipeline stops |
| Image Signing        | Cosign   | Unsigned images rejected by K8s policy |
| Signature Verify     | Cosign   | Verification step before deploy |

---

## 🚦 Pipeline Stages (Jenkinsfile Overview)

```
Stage 1:  Checkout Source Code       (Git)
Stage 2:  Maven Build & Unit Tests   (Maven)
Stage 3:  SonarQube Analysis         (SonarQube Scanner)
Stage 4:  Quality Gate Check         (FAIL if not passed)
Stage 5:  Upload to Nexus            (Maven Deploy)
Stage 6:  Docker Image Build         (docker build)
Stage 7:  Trivy Vulnerability Scan   (trivy image — FAIL on HIGH/CRITICAL)
Stage 8:  Cosign Sign Image          (cosign sign)
Stage 9:  Push Image to Registry     (docker push)
Stage 10: Cosign Verify              (cosign verify)
```

---

## 🖥️ Prerequisites

### Required Software on Windows Host

| Software      | Version    | Download Link                           |
|---------------|------------|-----------------------------------------|
| Docker Desktop| ≥ 4.25     | https://www.docker.com/products/docker-desktop |
| Git           | ≥ 2.40     | https://git-scm.com/download/win       |
| PowerShell    | ≥ 7.x      | Pre-installed on Win 10/11             |
| kubectl       | ≥ 1.28     | Bundled with Docker Desktop            |
| make (optional)| any       | Via chocolatey: `choco install make`   |

### Docker Desktop Settings Required
1. **Kubernetes**: Settings → Kubernetes → ✅ Enable Kubernetes
2. **Resources**: Minimum 8 GB RAM, 4 CPUs allocated
3. **Expose daemon**: Settings → General → ✅ Expose daemon on tcp://localhost:2375

---

## 🚀 Quick Start (TL;DR)

```powershell
# 1. Clone this repository
git clone https://github.com/Deepak122006/Devops.git
cd Devops

# 2. Run full setup (starts all Docker tools)
.\scripts\setup.ps1

# 3. Configure Jenkins (manual — see Phase 3)
# Open: http://localhost:8080

# 4. Configure SonarQube token (manual — see Phase 4)
# Open: http://localhost:9000

# 5. Run the pipeline from Jenkins UI
# OR trigger via git push to main

# 6. Deploy to Kubernetes
.\scripts\deploy.ps1

# 7. Access Grafana dashboards
# Open: http://localhost:3000
```

---

## 📦 Phase Details

### PHASE 0 — Prerequisites & Environment Setup
**Goal**: Verify Docker Desktop, Kubernetes, and tooling are ready.

**Verification Commands:**
```powershell
docker version
kubectl cluster-info
kubectl get nodes
```

**Expected Output:**
```
NAME                 STATUS   ROLES           AGE   VERSION
docker-desktop       Ready    control-plane   1d    v1.28.x
```

---

### PHASE 1 — Spring Boot Application (`app/`)
**Goal**: A minimal REST API that can be built, tested, and containerized.

**Key Files:**
- `app/pom.xml` — Maven config with SonarQube plugin, Jacoco coverage
- `app/src/main/java/.../HelloController.java` — REST endpoints
- `app/src/test/java/.../HelloControllerTest.java` — Unit tests

**Test:**
```powershell
cd app
mvn test
```

---

### PHASE 2 — Docker Multi-Stage Build (`docker/`)
**Goal**: Produce a lean, secure production image.

**Build stages:**
1. **builder** — JDK17 + Maven → compile & package JAR
2. **runtime** — JRE17 slim → copy JAR only (no build tools)

**Build & Run:**
```powershell
docker build -f docker/Dockerfile -t devsecops-app:latest .
docker run -p 8088:8080 devsecops-app:latest
```

---

### PHASE 3 — Jenkins Setup (`jenkins/`)
**Goal**: Run Jenkins as a Docker container, pre-installed with all plugins.

**Start Jenkins:**
```powershell
docker run -d --name jenkins `
  -p 8080:8080 -p 50000:50000 `
  -v jenkins_home:/var/jenkins_home `
  -v /var/run/docker.sock:/var/run/docker.sock `
  jenkins/jenkins:lts-jdk17
```

**Access:** http://localhost:8080

---

### PHASE 4 — SonarQube Setup
**Goal**: Run SonarQube for code quality and security scanning.

**Start SonarQube:**
```powershell
docker run -d --name sonarqube `
  -p 9000:9000 `
  sonarqube:10-community
```

**Access:** http://localhost:9000 (admin/admin)

**Pipeline Failure Condition:** Quality Gate = FAILED → `error("Quality gate failed!")`

---

### PHASE 5 — Nexus Artifact Repository
**Goal**: Store Maven artifacts in a private repository.

**Start Nexus:**
```powershell
docker run -d --name nexus `
  -p 8081:8081 `
  sonatype/nexus3:latest
```

**Access:** http://localhost:8081

---

### PHASE 6 — Trivy Security Scanning
**Goal**: Scan Docker images for known CVEs before pushing.

**Scan Command (in pipeline):**
```powershell
docker run --rm `
  -v /var/run/docker.sock:/var/run/docker.sock `
  aquasec/trivy:latest image `
  --exit-code 1 --severity HIGH,CRITICAL `
  devsecops-app:latest
```

**Pipeline Failure Condition:** Exit code 1 on HIGH/CRITICAL → Jenkins marks stage FAILED

---

### PHASE 7 — Cosign Image Signing
**Goal**: Sign Docker images cryptographically to prove integrity.

**Generate Keys:**
```powershell
docker run --rm -v ${PWD}:/workspace -w /workspace `
  gcr.io/projectsigstore/cosign:latest generate-key-pair
```

**Sign:**
```powershell
docker run --rm -v ${PWD}:/workspace -w /workspace `
  -e COSIGN_PASSWORD=$env:COSIGN_PASSWORD `
  gcr.io/projectsigstore/cosign:latest sign `
  --key /workspace/cosign.key `
  YOUR_REGISTRY/devsecops-app:latest
```

---

### PHASE 8 — Full Jenkins Pipeline (`jenkins/Jenkinsfile`)
**Goal**: Orchestrate all stages automatically on every commit.

**Jenkinsfile Stages:** Checkout → Build → Test → Sonar → Gate → Nexus → Docker Build → Trivy → Cosign Sign → Push → Verify

---

### PHASE 9 — Kubernetes Manifests (`k8s/`)
**Goal**: Deploy the signed, scanned image to the local Kubernetes cluster.

**Deploy:**
```powershell
kubectl apply -f k8s/
kubectl get pods -n devsecops
```

---

### PHASE 10 — Argo CD GitOps (`argocd/`)
**Goal**: Automate Kubernetes deployments via Git — push to repo = auto-deploy.

**Install:**
```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f argocd/install.yaml
```

**Access:** https://localhost:8443

---

### PHASE 11 — Monitoring (`monitoring/`)
**Goal**: Observe application health and performance metrics.

**Deploy:**
```powershell
kubectl apply -f monitoring/prometheus/
kubectl apply -f monitoring/grafana/
```

**Access:**
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (admin/admin123)

---

### PHASE 12 — Automation Scripts (`scripts/`)
**Goal**: One-click setup, deploy, and cleanup for everything.

| Script          | Command                    | Purpose                       |
|-----------------|----------------------------|-------------------------------|
| `setup.ps1`     | `.\scripts\setup.ps1`      | Start all Docker tools        |
| `deploy.ps1`    | `.\scripts\deploy.ps1`     | Deploy app to Kubernetes      |
| `cleanup.ps1`   | `.\scripts\cleanup.ps1`    | Stop and remove everything    |

---

## 🐛 Common Errors & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `Cannot connect to Docker daemon` | Docker Desktop not running | Start Docker Desktop |
| `connection refused` on Jenkins | Port conflict | Check `netstat -aon \| findstr :8080` |
| SonarQube returns 503 | Not ready yet | Wait 2-3 min after container start |
| Nexus `401 Unauthorized` | Wrong credentials | Check `admin` password in Nexus volume |
| Trivy `exit code 1` | HIGH/CRITICAL CVE found | Update base image or pin safe version |
| Cosign `key not found` | Keys not mounted | Ensure cosign.key is in pipeline workspace |
| Argo CD `ImagePullBackOff` | Image not pushed | Verify docker push succeeded |
| `kubectl` not found | kubectl not in PATH | Reinstall Docker Desktop or set PATH |

---

## 📝 Credentials Reference

| Service    | Username | Password       | Notes                        |
|------------|----------|----------------|------------------------------|
| Jenkins    | admin    | (generated)    | From container logs          |
| SonarQube  | admin    | admin          | Change on first login        |
| Nexus      | admin    | (generated)    | From `/nexus-data/admin.password` |
| Grafana    | admin    | admin123       | Set in env var               |
| Argo CD    | admin    | (generated)    | `argocd admin initial-password` |

---

## 🔁 GitOps Flow (Argo CD)

```
Developer pushes code
        ↓
GitHub triggers Jenkins webhook
        ↓
Jenkins builds → scans → signs → pushes image (new tag)
        ↓
Jenkins updates k8s/deployment.yaml image tag
        ↓
Jenkins pushes manifest update to Git
        ↓
Argo CD detects Git change
        ↓
Argo CD syncs Kubernetes cluster
        ↓
New pod rolls out with signed, scanned image
```

---

## 📊 Monitoring & Alerting

- **Prometheus** scrapes Spring Boot Actuator metrics at `/actuator/prometheus`
- **Grafana** displays dashboards: JVM memory, HTTP request rates, error rates
- **Alerts**: Configurable in Grafana for SLO/SLA violations

---

## 🙌 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -m "feat: add my feature"`
4. Push: `git push origin feature/my-feature`
5. Create a Pull Request → triggers the full pipeline automatically

---

## 📄 License

MIT License — Free to use, modify, and distribute.

---

*Generated by Antigravity DevSecOps Pipeline Generator — 2026*
