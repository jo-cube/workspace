#!/usr/bin/env bash
set -euo pipefail

# Build and sanity-check the supported workspace images.

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-workspace-test}"
SMOKE_PREFIX="workspace-smoke-$$"
SMOKE_HOME_VOLUME="${SMOKE_PREFIX}-home"

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS += 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL += 1)); }
header() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

image_for() {
  printf '%s/workspace:%s' "$IMAGE_REGISTRY" "$1"
}

build_flavors() {
  header "Building: $*"
  (
    cd "$ROOT_DIR"
    REGISTRY="$IMAGE_REGISTRY" docker buildx bake "$@"
  )
}

run_check() {
  local image="$1" desc="$2"
  shift 2
  if docker run --rm --user dev --entrypoint /bin/sh "$image" -lc "$*" &>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

run_home_check() {
  local image="$1" desc="$2"
  shift 2
  if docker run --rm --user dev \
    --mount "type=volume,src=${SMOKE_HOME_VOLUME},dst=/home/dev" \
    --entrypoint /bin/sh "$image" -lc "$*" &>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

run_version() {
  local image="$1" desc="$2"
  shift 2
  local out
  if out=$(docker run --rm --user dev --entrypoint /bin/sh "$image" -lc "$*" 2>&1); then
    pass "$desc: ${out%%$'\n'*}"
  else
    fail "$desc"
  fi
}

wait_for_url() {
  local container="$1" url="$2"
  for _ in {1..30}; do
    docker exec "$container" curl -fsS --max-time 2 "$url" &>/dev/null && return 0
    sleep 1
  done
  return 1
}

wait_for_health() {
  local container="$1" status
  for _ in {1..40}; do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null)" || return 1
    [ "$status" = healthy ] && return 0
    [ "$status" = unhealthy ] && return 1
    sleep 1
  done
  return 1
}

test_code() {
  local img cid
  img="$(image_for code)"
  header "Testing: code"
  for cmd in zsh git caddy code-server jq rg fd bat eza; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done
  run_check "$img" "/workspace exists" test -d /workspace
  run_check "$img" "/cache exists" test -d /cache
  run_check "$img" "dev user exists" id dev
  run_version "$img" "code-server" code-server --version

  header "Testing: code services"
  cid="$(docker run -d --name "${SMOKE_PREFIX}-code" "$img")"
  if wait_for_url "$cid" http://127.0.0.1:8080/health; then
    pass "Caddy health endpoint responding"
  else
    fail "Caddy health endpoint responding"
  fi
  if wait_for_health "$cid"; then
    pass "Docker healthcheck reports healthy"
  else
    fail "Docker healthcheck reports healthy"
  fi
  if docker exec "$cid" curl --noproxy '*' -fsS --max-time 5 http://127.0.0.1:8081/healthz &>/dev/null; then
    pass "code-server health endpoint responding"
  else
    fail "code-server health endpoint responding"
  fi
  if docker exec "$cid" sh -lc "curl -fsS http://127.0.0.1:8080/status | jq -e '. == {\"status\":\"running\"}'" &>/dev/null; then
    pass "compact status endpoint responding"
  else
    fail "compact status endpoint responding"
  fi
  if docker exec "$cid" sh -lc "curl -fsS http://127.0.0.1:8080/ | grep -q 'Code Server'" &>/dev/null; then
    pass "static dashboard responding"
  else
    fail "static dashboard responding"
  fi
  docker rm -f "$cid" &>/dev/null || true

  header "Testing: code auth"
  cid="$(docker run -d --name "${SMOKE_PREFIX}-code-auth" -e PASSWORD=smoke "$img")"
  wait_for_url "$cid" http://127.0.0.1:8080/code/ || true
  if docker exec "$cid" sh -lc "if curl -fsSI --max-time 5 http://127.0.0.1:8080/code/ | grep -qi '^www-authenticate:'; then exit 1; fi" &>/dev/null; then
    pass "code-server auth headers"
  else
    fail "code-server auth headers"
  fi
  if docker exec "$cid" sh -lc "curl -fsSL --max-time 5 http://127.0.0.1:8080/code/ | grep -qi password" &>/dev/null; then
    pass "code-server serves built-in auth page"
  else
    fail "code-server serves built-in auth page"
  fi
  docker rm -f "$cid" &>/dev/null || true
}

test_platform() {
  local img
  img="$(image_for platform)"
  header "Testing: platform"

  run_version "$img" "uv" uv --version
  run_version "$img" "python" python --version
  run_version "$img" "ipython" ipython --version
  run_version "$img" "java" java -version
  run_version "$img" "go" go version
  run_version "$img" "rustc" rustc --version
  run_version "$img" "node" node --version
  run_check "$img" "Python is image-owned" "test \"\$(uv python dir)\" = /opt/uv-python && test \"\$(command -v python)\" = /opt/uv-tools/bin/python"
  run_check "$img" "Python executes" "python -c 'assert 2 + 2 == 4'"
  run_check "$img" "Kotlin executes" "kotlin -e 'check(2 + 2 == 4)'"
  run_check "$img" "Go executes" "printf 'package main\nfunc main() {}\n' >/tmp/main.go && go run /tmp/main.go"
  run_check "$img" "Rust executes" "printf 'fn main() { assert_eq!(2 + 2, 4); }\n' >/tmp/main.rs && rustc /tmp/main.rs -o /tmp/main && /tmp/main"
  run_check "$img" "Node executes" "node -e 'if (2 + 2 !== 4) process.exit(1)'"

  for cmd in ruff mypy kotlin gradle cargo cc fnm kubectl helm k9s stern kubectx kubens xh grpcurl gron lazygit delta gh just duckdb yq psql redis-cli kcat websocat mlr rsync s5cmd mc ldb sst_dump datamash pv parallel gawk; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done
}

test_full() {
  local img cid
  img="$(image_for full)"
  header "Testing: full"

  for cmd in jupyter-lab gdb strace ltrace valgrind tcpdump sqlite3 trivy gitleaks hyperfine; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done

  docker volume rm -f "$SMOKE_HOME_VOLUME" &>/dev/null || true
  docker volume create "$SMOKE_HOME_VOLUME" &>/dev/null
  docker run --rm \
    --mount "type=volume,src=${SMOKE_HOME_VOLUME},dst=/home/dev,volume-nocopy" \
    --entrypoint /bin/sh "$img" -c 'chown 1000:1000 /home/dev && touch /home/dev/existing-home' &>/dev/null

  run_home_check "$img" "Existing home remains intact" test -f /home/dev/existing-home
  run_home_check "$img" "Python survives an existing home" "python -c 'assert 2 + 2 == 4' && test \"\$(uv python dir)\" = /opt/uv-python"
  run_home_check "$img" "JupyterLab survives an existing home" jupyter-lab --version
  run_home_check "$img" "Jupyter kernels registered" "/opt/uv-tools/jupyterlab/bin/jupyter kernelspec list --json | jq -e '.kernelspecs | has(\"python3\") and has(\"bash\") and has(\"rust\") and has(\"gonb\") and has(\"kotlin\")'"
  run_home_check "$img" "Bash/Kotlin kernel modules import" "/opt/uv-tools/jupyterlab/bin/python -c 'import bash_kernel, run_kotlin_kernel'"
  run_home_check "$img" "Rust kernel exists" command -v evcxr_jupyter
  run_home_check "$img" "Go kernel exists" command -v gonb
  run_home_check "$img" "Go kernel helpers exist" "command -v goimports && command -v gopls"
  run_home_check "$img" "Python kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"python-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"assert 2 + 2 == 4\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Python 3\",\"language\":\"python\",\"name\":\"python3\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/python-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/python-smoke.ipynb"
  run_home_check "$img" "Bash kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"bash-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"test \$((2 + 2)) -eq 4\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Bash\",\"language\":\"bash\",\"name\":\"bash\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/bash-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/bash-smoke.ipynb"
  run_home_check "$img" "Rust kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"rust-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"assert_eq!(2 + 2, 4);\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Rust\",\"language\":\"rust\",\"name\":\"rust\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/rust-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/rust-smoke.ipynb"
  run_home_check "$img" "Go kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"gonb-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"%%\\n\",\"fmt.Println(2 + 2)\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Go (gonb)\",\"language\":\"go\",\"name\":\"gonb\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/gonb-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/gonb-smoke.ipynb"
  run_home_check "$img" "Kotlin kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"kotlin-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"check(2 + 2 == 4)\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Kotlin\",\"language\":\"kotlin\",\"name\":\"kotlin\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/kotlin-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/kotlin-smoke.ipynb"

  header "Testing: full services and auth"
  cid="$(docker run -d --name "${SMOKE_PREFIX}-full-auth" \
    --mount "type=volume,src=${SMOKE_HOME_VOLUME},dst=/home/dev" \
    -e JUPYTER_TOKEN=smoke "$img")"
  wait_for_url "$cid" http://127.0.0.1:8080/lab || true
  if wait_for_health "$cid"; then
    pass "Docker healthcheck covers enabled services"
  else
    fail "Docker healthcheck covers enabled services"
  fi
  if docker exec "$cid" sh -lc "curl -fsS -D - -o /dev/null --max-time 5 http://127.0.0.1:8080/lab | grep -q '^HTTP/.* 302'" &>/dev/null; then
    pass "JupyterLab requires authentication"
  else
    fail "JupyterLab requires authentication"
  fi
  if docker exec "$cid" sh -lc "curl -fsSL --max-time 5 http://127.0.0.1:8080/lab | grep -Eqi 'password|token'" &>/dev/null; then
    pass "JupyterLab serves built-in auth page"
  else
    fail "JupyterLab serves built-in auth page"
  fi
  docker rm -f "$cid" &>/dev/null || true
}

cleanup() {
  docker rm -f "${SMOKE_PREFIX}-code" "${SMOKE_PREFIX}-code-auth" "${SMOKE_PREFIX}-full-auth" &>/dev/null || true
  docker volume rm -f "$SMOKE_HOME_VOLUME" &>/dev/null || true
}

FLAVORS=("${@:-code}")
[[ "${FLAVORS[0]}" == all ]] && FLAVORS=(code platform full)
for flavor in "${FLAVORS[@]}"; do
  case "$flavor" in
    code | platform | full) ;;
    *) echo "Unsupported flavor: $flavor" >&2; exit 1 ;;
  esac
done

trap cleanup EXIT

build_flavors "${FLAVORS[@]}"

for flavor in "${FLAVORS[@]}"; do
  case "$flavor" in
    code) test_code ;;
    platform) test_platform ;;
    full) test_full ;;
    *) echo "Unsupported flavor: $flavor" >&2; exit 1 ;;
  esac
done

header "Results"
echo -e "  ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
[ "$FAIL" -eq 0 ]
