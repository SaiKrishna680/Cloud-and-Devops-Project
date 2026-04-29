# ─────────────────────────────────────────────────────────────────────────────
# Makefile — DevSecOps Pipeline Developer Shortcuts
#
# USAGE:
#   make setup        → Run full setup (starts all Docker tools)
#   make build        → Build Docker image locally
#   make test         → Run Maven unit tests
#   make scan         → Run Trivy vulnerability scan
#   make sign         → Sign image with Cosign
#   make deploy       → Deploy to Kubernetes
#   make verify       → Verify Cosign signature
#   make logs         → Tail Jenkins logs
#   make status       → Show status of all containers and pods
#   make argocd-pass  → Get Argo CD initial admin password
#   make clean        → Stop and remove containers (keep data)
#   make clean-all    → Remove everything including data volumes
#
# REQUIREMENTS: make (install via 'choco install make' on Windows)
# ─────────────────────────────────────────────────────────────────────────────

# ── Variables ─────────────────────────────────────────────────────────────────
REGISTRY       := localhost:5000
APP_NAME       := devsecops-app
APP_VERSION    := 1.0.0
BUILD_NUMBER   := local
IMAGE_TAG      := $(APP_VERSION)-$(BUILD_NUMBER)
FULL_IMAGE     := $(REGISTRY)/$(APP_NAME):$(IMAGE_TAG)
LATEST_IMAGE   := $(REGISTRY)/$(APP_NAME):latest
COSIGN_KEY     := cosign-keys/cosign.key
COSIGN_PUB     := cosign-keys/cosign.pub
COSIGN_PASS    := DevSecOps@2024
NAMESPACE      := devsecops

# ── Shell ────────────────────────────────────────────────────────────────────
# Use PowerShell on Windows
SHELL          := powershell.exe
.SHELLFLAGS    := -NoProfile -Command

.PHONY: all setup build test scan sign push verify deploy status logs \
        argocd-pass sonar-token nexus-pass clean clean-all help

# ── Default target ────────────────────────────────────────────────────────────
all: help

# ════════════════════════════════════════════════════════════════════════════
# SETUP
# ════════════════════════════════════════════════════════════════════════════
setup:
	@echo "🚀 Running full environment setup..."
	.\scripts\setup.ps1

# ════════════════════════════════════════════════════════════════════════════
# BUILD
# ════════════════════════════════════════════════════════════════════════════
build:
	@echo "🔨 Building Docker image: $(FULL_IMAGE)"
	docker build \
		-f docker/Dockerfile \
		-t $(FULL_IMAGE) \
		-t $(LATEST_IMAGE) \
		.
	@echo "✅ Build complete: $(FULL_IMAGE)"

# ════════════════════════════════════════════════════════════════════════════
# TEST
# ════════════════════════════════════════════════════════════════════════════
test:
	@echo "🧪 Running Maven unit tests..."
	cd app && mvn test jacoco:report -B --no-transfer-progress
	@echo "✅ Tests complete. Coverage report: app/target/site/jacoco/index.html"

# ════════════════════════════════════════════════════════════════════════════
# SCAN
# ════════════════════════════════════════════════════════════════════════════
scan:
	@echo "🛡️  Running Trivy vulnerability scan on $(FULL_IMAGE)..."
	@echo "    Failing on: HIGH, CRITICAL"
	docker run --rm \
		-v //var/run/docker.sock:/var/run/docker.sock \
		-v trivy-cache:/root/.cache/trivy \
		aquasec/trivy:latest image \
		--exit-code 1 \
		--severity HIGH,CRITICAL \
		--no-progress \
		$(FULL_IMAGE)
	@echo "✅ Trivy scan PASSED."

# ════════════════════════════════════════════════════════════════════════════
# SIGN
# ════════════════════════════════════════════════════════════════════════════
sign:
	@echo "✍️  Signing Docker image with Cosign..."
	docker run --rm \
		-v $(PWD)/$(COSIGN_KEY):/cosign.key:ro \
		-v //var/run/docker.sock:/var/run/docker.sock \
		-e COSIGN_PASSWORD=$(COSIGN_PASS) \
		gcr.io/projectsigstore/cosign:latest sign \
		--key /cosign.key \
		--yes \
		$(FULL_IMAGE)
	@echo "✅ Image signed."

# ════════════════════════════════════════════════════════════════════════════
# PUSH
# ════════════════════════════════════════════════════════════════════════════
push:
	@echo "📤 Pushing image to registry..."
	docker push $(FULL_IMAGE)
	docker push $(LATEST_IMAGE)
	@echo "✅ Image pushed: $(FULL_IMAGE)"

# ════════════════════════════════════════════════════════════════════════════
# VERIFY
# ════════════════════════════════════════════════════════════════════════════
verify:
	@echo "🔐 Verifying Cosign signature on $(FULL_IMAGE)..."
	docker run --rm \
		-v $(PWD)/$(COSIGN_PUB):/cosign.pub:ro \
		gcr.io/projectsigstore/cosign:latest verify \
		--key /cosign.pub \
		$(FULL_IMAGE)
	@echo "✅ Signature verified."

# ════════════════════════════════════════════════════════════════════════════
# DEPLOY
# ════════════════════════════════════════════════════════════════════════════
deploy:
	@echo "🚀 Deploying to Kubernetes..."
	.\scripts\deploy.ps1 -ImageTag "$(IMAGE_TAG)"

# ════════════════════════════════════════════════════════════════════════════
# STATUS
# ════════════════════════════════════════════════════════════════════════════
status:
	@echo "─── Docker Containers ───────────────────────────────"
	docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
		--filter name=jenkins \
		--filter name=sonarqube \
		--filter name=nexus \
		--filter name=registry
	@echo ""
	@echo "─── Kubernetes Pods (namespace: $(NAMESPACE)) ──────"
	kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "(Kubernetes not available)"
	@echo ""
	@echo "─── Argo CD Pods ─────────────────────────────────────"
	kubectl get pods -n argocd 2>/dev/null || echo "(Argo CD not installed)"

# ════════════════════════════════════════════════════════════════════════════
# LOGS
# ════════════════════════════════════════════════════════════════════════════
logs:
	@echo "📋 Tailing Jenkins container logs (Ctrl+C to stop)..."
	docker logs -f jenkins

logs-sonar:
	docker logs -f sonarqube

logs-nexus:
	docker logs -f nexus

logs-app:
	kubectl logs -f deployment/devsecops-app -n $(NAMESPACE)

# ════════════════════════════════════════════════════════════════════════════
# CREDENTIALS HELPERS
# ════════════════════════════════════════════════════════════════════════════
argocd-pass:
	@echo "🔑 Argo CD initial admin password:"
	kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" 2>/dev/null | \
		%{[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($$_))}

nexus-pass:
	@echo "🔑 Nexus admin password:"
	docker exec nexus cat /nexus-data/admin.password

jenkins-pass:
	@echo "🔑 Jenkins initial admin password:"
	docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

sonar-info:
	@echo "🔑 SonarQube: http://localhost:9000"
	@echo "   Default credentials: admin / admin"
	@echo "   Generate token: Administration → Security → Users → Tokens"

# ════════════════════════════════════════════════════════════════════════════
# CLEAN
# ════════════════════════════════════════════════════════════════════════════
clean:
	@echo "🧹 Stopping and removing Docker containers (keeping data)..."
	.\scripts\cleanup.ps1 -Force

clean-all:
	@echo "🧹 Removing EVERYTHING including data volumes..."
	.\scripts\cleanup.ps1 -RemoveData -Force

# ════════════════════════════════════════════════════════════════════════════
# HELP
# ════════════════════════════════════════════════════════════════════════════
help:
	@echo ""
	@echo "DevSecOps Pipeline — Available Make Targets:"
	@echo "─────────────────────────────────────────────────────"
	@echo "  make setup        → Bootstrap full environment"
	@echo "  make build        → Build Docker image"
	@echo "  make test         → Run Maven tests + coverage"
	@echo "  make scan         → Trivy vulnerability scan"
	@echo "  make sign         → Sign image with Cosign"
	@echo "  make push         → Push image to registry"
	@echo "  make verify       → Verify Cosign signature"
	@echo "  make deploy       → Deploy to Kubernetes"
	@echo "  make status       → Show all tool/pod status"
	@echo "  make logs         → Tail Jenkins logs"
	@echo "  make logs-app     → Tail app pod logs"
	@echo "  make argocd-pass  → Get Argo CD admin password"
	@echo "  make nexus-pass   → Get Nexus admin password"
	@echo "  make jenkins-pass → Get Jenkins initial password"
	@echo "  make clean        → Remove containers (keep data)"
	@echo "  make clean-all    → Remove everything incl. data"
	@echo "─────────────────────────────────────────────────────"
	@echo ""
