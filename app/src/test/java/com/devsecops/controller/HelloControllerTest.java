package com.devsecops.controller;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Unit tests for HelloController.
 *
 * Uses MockMvc to avoid starting a real server — tests run fast in CI.
 * JaCoCo measures coverage from these tests and reports to SonarQube.
 */
@WebMvcTest(HelloController.class)
class HelloControllerTest {

    @Autowired
    private MockMvc mockMvc;

    // ─── Root ─────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("GET / should return 200 with 'message' field")
    void rootEndpoint_shouldReturn200() throws Exception {
        mockMvc.perform(get("/"))
               .andExpect(status().isOk())
               .andExpect(content().contentType(MediaType.APPLICATION_JSON))
               .andExpect(jsonPath("$.message", containsString("DevSecOps")))
               .andExpect(jsonPath("$.status", is("running")));
    }

    // ─── Hello ────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("GET /api/hello should return default greeting for World")
    void helloEndpoint_defaultName() throws Exception {
        mockMvc.perform(get("/api/hello"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.greeting", is("Hello, World!")))
               .andExpect(jsonPath("$.version", is("1.0.0")));
    }

    @Test
    @DisplayName("GET /api/hello?name=Alice should return personalised greeting")
    void helloEndpoint_customName() throws Exception {
        mockMvc.perform(get("/api/hello").param("name", "Alice"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.greeting", is("Hello, Alice!")));
    }

    // ─── Info ─────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("GET /api/info should return application metadata")
    void infoEndpoint_shouldReturnMetadata() throws Exception {
        mockMvc.perform(get("/api/info"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.application", notNullValue()))
               .andExpect(jsonPath("$.version",     is("1.0.0")))
               .andExpect(jsonPath("$.java",        notNullValue()))
               .andExpect(jsonPath("$.pipeline",    containsString("Jenkins")));
    }

    // ─── Health ───────────────────────────────────────────────────────────────

    @Test
    @DisplayName("GET /api/health should return status UP")
    void healthEndpoint_shouldReturnUp() throws Exception {
        mockMvc.perform(get("/api/health"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.status", is("UP")));
    }

    // ─── Echo ─────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("POST /api/echo should echo back the request body")
    void echoEndpoint_shouldEchoBody() throws Exception {
        String body = "{\"message\": \"test-payload\"}";

        mockMvc.perform(post("/api/echo")
                   .contentType(MediaType.APPLICATION_JSON)
                   .content(body))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.echo.message", is("test-payload")))
               .andExpect(jsonPath("$.timestamp",    notNullValue()));
    }
}
