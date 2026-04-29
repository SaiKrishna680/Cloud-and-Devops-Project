# ─────────────────────────────────────────────────────────────────────────────
# Multi-Stage Dockerfile — DevSecOps Spring Boot App
#
# STAGE 1 (builder): Uses Maven + JDK17 to compile and package the JAR.
#                    This stage is DISCARDED — build tools never reach prod.
#
# STAGE 2 (runtime): Uses minimal JRE17 image. Copies only the fat JAR.
#                    Runs as non-root user for security.
# ─────────────────────────────────────────────────────────────────────────────

# ═══════════════════════════════════════════════════════
# STAGE 1 — Build
# ═══════════════════════════════════════════════════════
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

LABEL stage="builder"

WORKDIR /build

# Copy POM first (layer cache — only re-downloads deps if pom.xml changes)
COPY app/pom.xml .

# Download all dependencies (offline future builds)
RUN mvn dependency:go-offline -B

# Copy source code
COPY app/src ./src

# Package — skip tests here (tests ran earlier in Jenkins pipeline)
RUN mvn package -DskipTests -B

# ═══════════════════════════════════════════════════════
# STAGE 2 — Runtime (Production Image)
# ═══════════════════════════════════════════════════════
FROM eclipse-temurin:17-jre-alpine AS runtime

LABEL maintainer="DevSecOps Team <devsecops@example.com>"
LABEL version="1.0.0"
LABEL description="DevSecOps Spring Boot Demo — scanned by Trivy, signed by Cosign"

# Install curl for health checks only (minimise attack surface)
RUN apk add --no-cache curl

# ── Security: run as non-root user ────────────────────────────────────────────
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy the fat JAR from builder stage
COPY --from=builder /build/target/*.jar app.jar

# Ensure the app user owns the file
RUN chown appuser:appgroup app.jar

USER appuser

# ── Expose application port ───────────────────────────────────────────────────
EXPOSE 8080

# ── Health check (Docker-native) ──────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# ── JVM tuning for containers ─────────────────────────────────────────────────
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UseG1GC \
               -Djava.security.egd=file:/dev/./urandom"

# ── Start application ─────────────────────────────────────────────────────────
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
