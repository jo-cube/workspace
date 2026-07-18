package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandler(t *testing.T) {
	handler := newHandler()

	t.Run("health", func(t *testing.T) {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/health", nil))

		if response.Code != http.StatusOK || response.Body.String() != "OK" {
			t.Fatalf("GET /health = %d %q", response.Code, response.Body.String())
		}
	})

	t.Run("status", func(t *testing.T) {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/status", nil))

		var status struct {
			Status   string           `json:"status"`
			Services []map[string]any `json:"services"`
		}
		if err := json.NewDecoder(response.Body).Decode(&status); err != nil {
			t.Fatal(err)
		}
		if response.Code != http.StatusOK || status.Status != "running" || len(status.Services) != 4 {
			t.Fatalf("GET /status = %d, status %q, %d services", response.Code, status.Status, len(status.Services))
		}
	})

	t.Run("method", func(t *testing.T) {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/health", nil))

		if response.Code != http.StatusMethodNotAllowed {
			t.Fatalf("POST /health = %d, want %d", response.Code, http.StatusMethodNotAllowed)
		}
	})
}
