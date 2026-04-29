package com.devsecops;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point for the DevSecOps Spring Boot Demo Application.
 *
 * This application exposes a REST API that demonstrates a production-ready
 * Spring Boot app integrated into a full DevSecOps pipeline:
 *   Jenkins → SonarQube → Nexus → Docker → Trivy → Cosign → ArgoCD → K8s
 */
@SpringBootApplication
public class DevSecOpsApplication {

    public static void main(String[] args) {
        SpringApplication.run(DevSecOpsApplication.class, args);
    }
}
