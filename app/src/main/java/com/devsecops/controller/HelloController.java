package com.devsecops.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.Map;

/**
 * REST Controller — DevSecOps Demo API
 *
 * Endpoints:
 *   GET  /             → Health/welcome message
 *   GET  /api/hello    → Hello World JSON
 *   GET  /api/info     → Application info
 *   GET  /api/health   → Custom health check
 */
@RestController
@RequestMapping
public class HelloController {

    private static final Logger log = LoggerFactory.getLogger(HelloController.class);

    private static final String APP_VERSION = "1.0.0";
    private static final String APP_NAME    = "DevSecOps Spring Boot App";

    // ─── Root endpoint ────────────────────────────────────────────────────────

    /**
     * Root endpoint — basic welcome.
     *
     * @return 200 OK with welcome message
     */
    @GetMapping("/")
    public ResponseEntity<Map<String, Object>> root() {
        log.info("Root endpoint called");
        return ResponseEntity.ok(Map.of(
            "message", "Welcome to the DevSecOps Pipeline Demo!",
            "status",  "running",
            "time",    Instant.now().toString()
        ));
    }

    // ─── Hello endpoint ───────────────────────────────────────────────────────

    /**
     * Hello World endpoint.
     *
     * @param name Optional query parameter for personalised greeting
     * @return 200 OK with greeting JSON
     */
    @GetMapping("/api/hello")
    public ResponseEntity<Map<String, Object>> hello(
            @RequestParam(defaultValue = "World") String name) {

        log.info("Hello endpoint called with name={}", name);
        return ResponseEntity.ok(Map.of(
            "greeting", "Hello, " + name + "!",
            "app",      APP_NAME,
            "version",  APP_VERSION
        ));
    }

    // ─── Info endpoint ────────────────────────────────────────────────────────

    /**
     * Application information endpoint.
     *
     * @return 200 OK with detailed app metadata
     */
    @GetMapping("/api/info")
    public ResponseEntity<Map<String, Object>> info() {
        log.info("Info endpoint called");
        return ResponseEntity.ok(Map.of(
            "application", APP_NAME,
            "version",     APP_VERSION,
            "java",        System.getProperty("java.version"),
            "pipeline",    "Jenkins → SonarQube → Nexus → Docker → Trivy → Cosign → ArgoCD",
            "timestamp",   Instant.now().toString()
        ));
    }

    // ─── Health endpoint ──────────────────────────────────────────────────────

    /**
     * Custom health check (complement to Spring Actuator /actuator/health).
     *
     * @return 200 OK with status=UP
     */
    @GetMapping("/api/health")
    public ResponseEntity<Map<String, Object>> health() {
        return ResponseEntity.ok(Map.of(
            "status",    "UP",
            "timestamp", Instant.now().toString()
        ));
    }

    // ─── Echo endpoint (POST) ─────────────────────────────────────────────────

    /**
     * Echo endpoint — returns whatever was posted.
     *
     * @param body Request body map
     * @return 200 OK with echoed body
     */
    @PostMapping("/api/echo")
    public ResponseEntity<Map<String, Object>> echo(@RequestBody Map<String, Object> body) {
        log.info("Echo endpoint called with body={}", body);
        return ResponseEntity.ok(Map.of(
            "echo",      body,
            "timestamp", Instant.now().toString()
        ));
    }
}
