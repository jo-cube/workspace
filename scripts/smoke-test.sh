#!/usr/bin/env bash
set -euo pipefail

# Build and sanity-check workspace image flavors.
# This is intentionally small; exhaustive checks belong in the image build logs
# and in manual runtime validation when changing service startup.

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-workspace-test}"
IMAGE_TAG="${IMAGE_TAG:-smoke}"

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS += 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL += 1)); }
header() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

image_for() {
  printf '%s/workspace:%s' "$IMAGE_REGISTRY" "$1"
}

build_flavor() {
  local flavor="$1"
  header "Building: ${flavor}"
  (
    cd "$ROOT_DIR"
    REGISTRY="$IMAGE_REGISTRY" TAG="$IMAGE_TAG" docker buildx bake "$flavor"
  )
}

run_check() {
  local image="$1" desc="$2"
  shift 2
  if docker run --rm --entrypoint /bin/sh "$image" -lc "$*" &>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

run_version() {
  local image="$1" desc="$2"
  shift 2
  local out
  if out=$(docker run --rm --entrypoint /bin/sh "$image" -lc "$*" 2>&1); then
    pass "$desc: ${out%%$'\n'*}"
  else
    fail "$desc"
  fi
}

test_base() {
  local img
  img="$(image_for base)"
  build_flavor base
  header "Testing: base"
  for cmd in zsh git caddy workspace-status jq rg fd bat eza; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done
  run_check "$img" "/workspace exists" test -d /workspace
  run_check "$img" "/cache exists" test -d /cache
  run_check "$img" "dev user exists" id dev
}

test_code() {
  local img cid
  img="$(image_for code)"
  build_flavor code
  header "Testing: code"
  run_version "$img" "code-server" code-server --version

  header "Testing: code services"
  docker rm -f smoke-code &>/dev/null || true
  cid="$(docker run -d --name smoke-code "$img")"
  sleep 8
  if docker exec "$cid" curl -fsS --max-time 5 http://127.0.0.1:8080/health &>/dev/null; then
    pass "Caddy health endpoint responding"
  else
    fail "Caddy health endpoint responding"
  fi
  if docker exec "$cid" curl -fsS --max-time 5 http://127.0.0.1:8081 &>/dev/null; then
    pass "code-server responding"
  else
    fail "code-server responding"
  fi
  docker rm -f "$cid" &>/dev/null || true

  header "Testing: code auth"
  docker rm -f smoke-code-auth &>/dev/null || true
  cid="$(docker run -d --name smoke-code-auth -e PASSWORD=smoke "$img")"
  sleep 8
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

test_python() {
  local img
  img="$(image_for python)"
  build_flavor python
  header "Testing: python"
  run_version "$img" "uv" uv --version
  run_version "$img" "python 3.14" uv run --python 3.14 python --version
  run_version "$img" "ipython" ipython --version
  run_version "$img" "uvx ipython" uvx --from ipython ipython --version
  run_check "$img" "ruff exists" command -v ruff
  run_check "$img" "mypy exists" command -v mypy
}

test_jvm() {
  local img
  img="$(image_for jvm)"
  build_flavor jvm
  header "Testing: jvm"
  run_version "$img" "java" java -version
  run_check "$img" "kotlin exists" command -v kotlin
  run_check "$img" "gradle exists" command -v gradle
}

test_polyglot() {
  local img
  img="$(image_for polyglot)"
  build_flavor polyglot
  header "Testing: polyglot"
  run_version "$img" "uv" uv --version
  run_version "$img" "go" go version
  run_version "$img" "rustc" rustc --version
  run_check "$img" "java exists" command -v java
  run_check "$img" "gradle exists" command -v gradle
  run_check "$img" "cargo exists" command -v cargo
  run_check "$img" "C linker exists" command -v cc
  run_check "$img" "fnm exists" test -x /opt/fnm/fnm
}

test_lab() {
  local img cid
  img="$(image_for lab)"
  build_flavor lab
  header "Testing: lab"
  run_check "$img" "jupyter-lab exists" command -v jupyter-lab
  run_check "$img" "Jupyter kernels registered" "/opt/uv-tools/jupyterlab/bin/jupyter kernelspec list --json | jq -e '.kernelspecs | has(\"bash\") and has(\"rust\") and has(\"gonb\") and has(\"kotlin\")'"
  run_check "$img" "Bash/Kotlin kernel modules import" "/opt/uv-tools/jupyterlab/bin/python -c 'import bash_kernel, run_kotlin_kernel'"
  run_check "$img" "Rust kernel exists" command -v evcxr_jupyter
  run_check "$img" "Go kernel exists" command -v gonb
  run_check "$img" "Go kernel helpers exist" "command -v goimports && command -v gopls"
  run_check "$img" "GoNB executes %% cell" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"gonb-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"%%\\n\",\"fmt.Println(2 + 2)\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Go (gonb)\",\"language\":\"go\",\"name\":\"gonb\"},\"language_info\":{\"name\":\"go\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/gonb-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/gonb-smoke.ipynb"

  header "Testing: lab auth"
  docker rm -f smoke-lab-auth &>/dev/null || true
  cid="$(docker run -d --name smoke-lab-auth -e JUPYTER_TOKEN=smoke "$img")"
  sleep 10
  if docker exec "$cid" sh -lc "if curl -fsS -D - -o /dev/null --max-time 5 http://127.0.0.1:8080/lab | grep -qi '^www-authenticate:'; then exit 1; fi" &>/dev/null; then
    pass "JupyterLab auth headers"
  else
    fail "JupyterLab auth headers"
  fi
  if docker exec "$cid" sh -lc "curl -fsSL --max-time 5 http://127.0.0.1:8080/lab | grep -Eqi 'password|token'" &>/dev/null; then
    pass "JupyterLab serves built-in auth page"
  else
    fail "JupyterLab serves built-in auth page"
  fi
  docker rm -f "$cid" &>/dev/null || true
}

test_platform() {
  local img
  img="$(image_for platform)"
  build_flavor platform
  header "Testing: platform"
  for cmd in kubectl helm k9s stern kubectx kubens xh grpcurl lazygit delta http gh just duckdb yq psql redis-cli kcat websocat mlr rsync s5cmd mc ldb sst_dump datamash pv parallel gawk; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done
}

test_full() {
  local img
  img="$(image_for full)"
  build_flavor full
  header "Testing: full"
  for cmd in jupyter-lab gdb strace tcpdump sqlite3 trivy gitleaks hyperfine; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done
  run_check "$img" "Jupyter kernels registered" "/opt/uv-tools/jupyterlab/bin/jupyter kernelspec list --json | jq -e '.kernelspecs | has(\"bash\") and has(\"rust\") and has(\"gonb\") and has(\"kotlin\")'"
}

cleanup() {
  docker rm -f smoke-code &>/dev/null || true
  docker rm -f smoke-code-auth &>/dev/null || true
  docker rm -f smoke-lab-auth &>/dev/null || true
}

FLAVORS=("${@:-code}")
[[ "${FLAVORS[0]}" == "all" ]] && FLAVORS=(base code python jvm polyglot lab platform full)

trap cleanup EXIT

for flavor in "${FLAVORS[@]}"; do
  case "$flavor" in
    base) test_base ;;
    code) test_code ;;
    python) test_python ;;
    jvm) test_jvm ;;
    polyglot) test_polyglot ;;
    lab) test_lab ;;
    platform) test_platform ;;
    full) test_full ;;
    *) echo "Unknown flavor: $flavor" >&2; exit 1 ;;
  esac
done

header "Results"
echo -e "  ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
