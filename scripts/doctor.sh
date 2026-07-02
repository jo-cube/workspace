#!/usr/bin/env bash
set -euo pipefail

# doctor.sh — workspace health checks
# Run inside the container or against a running compose service.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS += 1)); }
fail() { echo -e "${RED}✗${NC} $1"; ((FAIL += 1)); }
warn() { echo -e "${YELLOW}!${NC} $1"; ((WARN += 1)); }

check_cmd() {
  if command -v "$1" &>/dev/null; then
    pass "$1 found"
  else
    fail "$1 not found"
  fi
}

check_service() {
  local url="$1" name="$2"
  if curl -fsS --max-time 3 "$url" &>/dev/null; then
    pass "$name responding"
  else
    warn "$name not responding (may not be enabled)"
  fi
}

echo "=== Workspace Doctor ==="
echo ""

echo "--- Core tools ---"
for cmd in bash zsh tmux nvim git curl jq rg fd fzf bat eza zoxide starship; do
  check_cmd "$cmd"
done

echo ""
echo "--- Services ---"
check_cmd caddy
check_cmd code-server

echo ""
echo "--- Runtime (if present) ---"
command -v uv &>/dev/null && pass "uv $(uv --version 2>&1 | cut -d' ' -f2)" || warn "uv not installed"
command -v ipython &>/dev/null && pass "ipython $(ipython --version 2>&1)" || warn "ipython not installed"
if command -v python3 &>/dev/null; then
  pass "python3 $(python3 --version 2>&1 | cut -d' ' -f2)"
elif command -v uv &>/dev/null && uv python find 3.14 &>/dev/null; then
  pass "python $(uv run --python 3.14 python --version 2>&1 | cut -d' ' -f2) via uv"
else
  warn "python not installed"
fi
command -v java &>/dev/null && pass "java $(java -version 2>&1 | head -1 | cut -d'"' -f2)" || warn "java not installed"
command -v go &>/dev/null && pass "go $(go version | cut -d' ' -f3)" || warn "go not installed"
command -v rustc &>/dev/null && pass "rustc $(rustc --version | cut -d' ' -f2)" || warn "rust not installed"

# fnm-managed Node requires shell integration — check both PATH and fnm
if command -v node &>/dev/null; then
  pass "node $(node --version)"
elif [ -d /opt/fnm ] && /opt/fnm/fnm list &>/dev/null; then
  warn "node installed via fnm but not in PATH (use interactive shell)"
else
  warn "node not installed"
fi

echo ""
echo "--- Platform tools (if present) ---"
for cmd in kubectl helm k9s stern kubectx gh lazygit delta just yq duckdb kcat websocat mlr rsync s5cmd mc ldb sst_dump datamash pv parallel gawk; do
  command -v "$cmd" &>/dev/null && pass "$cmd found" || true
done

echo ""
echo "--- Network ---"
check_service "http://127.0.0.1:8080/health" "Caddy proxy"
check_service "http://127.0.0.1:8081" "code-server"
[ "${ENABLE_JUPYTER:-false}" = "true" ] && check_service "http://127.0.0.1:8888/lab" "JupyterLab"

echo ""
echo "--- Filesystem ---"
[ -d /workspace ] && pass "/workspace exists" || fail "/workspace missing"
[ -d /cache ] && pass "/cache exists" || fail "/cache missing"
[ -w /workspace ] && pass "/workspace writable" || fail "/workspace not writable"
[ -w /home/dev ] && pass "/home/dev writable" || fail "/home/dev not writable"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings ==="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
