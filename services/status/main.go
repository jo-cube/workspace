// workspace-status: lightweight HTTP service for workspace health and introspection.
// Endpoints: /health, /ready, /status, /status/services, /status/tools
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"
)

var startTime = time.Now()
var (
	toolsOnce  sync.Once
	toolsCache []map[string]string
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/ready", handleReady)
	mux.HandleFunc("/status", handleStatus)
	mux.HandleFunc("/status/services", handleServices)
	mux.HandleFunc("/status/tools", handleTools)

	addr := ":8082"
	if v := os.Getenv("STATUS_PORT"); v != "" {
		addr = ":" + v
	}

	fmt.Printf("workspace-status listening on %s\n", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "OK")
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	// Ready if Caddy is responding
	if !portOpen("127.0.0.1:8080") {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprint(w, "NOT READY")
		return
	}
	w.Header().Set("Content-Type", "text/plain")
	fmt.Fprint(w, "OK")
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()
	status := map[string]any{
		"status":   "running",
		"hostname": hostname,
		"uptime":   time.Since(startTime).Round(time.Second).String(),
		"arch":     runtime.GOARCH,
		"os":       runtime.GOOS,
		"user":     os.Getenv("USER"),
		"services": getServices(),
	}
	writeJSON(w, status)
}

func handleServices(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, getServices())
}

func handleTools(w http.ResponseWriter, r *http.Request) {
	toolsOnce.Do(func() {
		toolsCache = detectTools()
	})
	writeJSON(w, toolsCache)
}

func detectTools() []map[string]string {
	tools := []map[string]string{}
	checks := []struct{ name, bin string }{
		{"git", "git"}, {"neovim", "nvim"}, {"tmux", "tmux"},
		{"zsh", "zsh"}, {"curl", "curl"}, {"jq", "jq"},
		{"ripgrep", "rg"}, {"fd", "fd"}, {"fzf", "fzf"},
		{"bat", "bat"}, {"eza", "eza"}, {"starship", "starship"},
		{"caddy", "caddy"}, {"code-server", "code-server"},
		{"python", "python3"}, {"uv", "uv"}, {"ruff", "ruff"},
		{"java", "java"}, {"kotlin", "kotlin"}, {"gradle", "gradle"},
		{"go", "go"}, {"rustc", "rustc"}, {"cargo", "cargo"},
		{"node", "node"}, {"kubectl", "kubectl"}, {"helm", "helm"},
		{"k9s", "k9s"}, {"docker", "docker"}, {"just", "just"},
		{"lazygit", "lazygit"}, {"gh", "gh"}, {"duckdb", "duckdb"},
		{"kcat", "kcat"}, {"websocat", "websocat"}, {"miller", "mlr"},
		{"rsync", "rsync"}, {"s5cmd", "s5cmd"}, {"mc", "mc"},
		{"ldb", "ldb"}, {"sst_dump", "sst_dump"},
		{"datamash", "datamash"}, {"pv", "pv"}, {"parallel", "parallel"},
		{"gawk", "gawk"},
	}
	for _, c := range checks {
		path, err := exec.LookPath(c.bin)
		if err == nil {
			tools = append(tools, map[string]string{
				"name":    c.name,
				"path":    path,
				"version": getVersion(c.bin),
			})
		}
	}
	return tools
}

func getServices() []map[string]any {
	services := []map[string]any{
		{
			"name":    "caddy",
			"port":    8080,
			"running": portOpen("127.0.0.1:8080"),
		},
		{
			"name":    "code-server",
			"port":    8081,
			"running": portOpen("127.0.0.1:8081"),
		},
		{
			"name":    "jupyter",
			"port":    8888,
			"running": portOpen("127.0.0.1:8888"),
		},
		{
			"name":    "workspace-status",
			"port":    8082,
			"running": true,
		},
	}
	return services
}

func portOpen(addr string) bool {
	conn, err := net.DialTimeout("tcp", addr, 500*time.Millisecond)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func getVersion(bin string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, bin, "--version").CombinedOutput()
	if err != nil {
		return ""
	}
	line := strings.Split(strings.TrimSpace(string(out)), "\n")[0]
	// Truncate overly long version strings
	if len(line) > 80 {
		line = line[:80]
	}
	return line
}

func writeJSON(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(data)
}
