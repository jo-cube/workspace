#!/usr/bin/env bash
set -euo pipefail

# Build and sanity-check the supported workspace images.
# --no-build requires existing local images named <IMAGE_REGISTRY>/workspace:<flavor>-smoke.

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-workspace-test}"
SMOKE_HOME_VOLUME=
SMOKE_ENTERPRISE_IMAGE=

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS += 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL += 1)); }
header() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

image_for() {
  printf '%s/workspace:%s-smoke' "$IMAGE_REGISTRY" "$1"
}

build_flavors() {
  header "Building: $*"
  (
    cd "$ROOT_DIR"
    REGISTRY="$IMAGE_REGISTRY" TAG=smoke docker buildx bake "$@"
  )
}

run_check() {
  local image="$1" desc="$2"
  shift 2
  if docker run --rm --label "$SMOKE_LABEL" --user dev --entrypoint /bin/sh "$image" -lc "$*" &>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

run_home_check() {
  local image="$1" desc="$2"
  shift 2
  if docker run --rm --label "$SMOKE_LABEL" --user dev \
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
  if out=$(docker run --rm --label "$SMOKE_LABEL" --user dev --entrypoint /bin/sh "$image" -lc "$*" 2>&1); then
    pass "$desc: ${out%%$'\n'*}"
  else
    fail "$desc"
  fi
}

wait_for_url() {
  local container="$1" url="$2"
  for _ in {1..30}; do
    docker exec "$container" curl --noproxy '*' -fsS --max-time 2 "$url" &>/dev/null && return 0
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

check_code_login() {
  local cid="$1" password="$2" rejected="$3"
  docker exec "$cid" sh -eu -c '
    url=http://127.0.0.1:8080/code
    curl --noproxy "*" -fsS --max-time 10 -c /tmp/auth.cookies \
      --data-urlencode "password=$2" --data-urlencode base=/code "$url/login" >/dev/null
    test "$(curl --noproxy "*" -sS --max-time 10 -o /dev/null -w "%{http_code}" \
      -b /tmp/auth.cookies "$url/?folder=/workspace")" = 302
    test "$(curl --noproxy "*" -fsS --max-time 10 -o /dev/null -w "%{http_code}" \
      -c /tmp/auth.cookies --data-urlencode "password=$1" --data-urlencode base=/code "$url/login")" = 302
    test "$(curl --noproxy "*" -fsS --max-time 10 -o /dev/null -w "%{http_code}" \
      -b /tmp/auth.cookies "$url/?folder=/workspace")" = 200
  ' sh "$password" "$rejected"
}

test_code_auth() {
  local img="$1" file_hash env_hash scenario credential expected rejected cid
  header "Testing: code credential precedence"
  # Fixed, non-secret Argon2 fixtures for "file-hash" and "env-hash".
  file_hash="\$argon2id\$v=19\$m=65536,t=3,p=4\$aa3EIv12DYoR3LSkMRHc7Q\$GNNVar+4bNfOcaO1epPzHVanca+fBxisYS6VQD6Vfkg"
  env_hash="\$argon2id\$v=19\$m=65536,t=3,p=4\$hpfJRzUYAbwgFwRwNzUJfQ\$pi9cxjPVzz3I6ujlPBw88yP3h2hxeFvjH3XvzhFGJIc"
  for scenario in file environment file-hash environment-hash; do
    printf "%s\n" "PASSWORD='file-password'" > "$SMOKE_DIR/auth.env"
    credential=PASSWORD=
    expected=file-password
    rejected=incorrect
    case "$scenario" in
      environment) credential=PASSWORD=env-password; expected=env-password; rejected=file-password ;;
      file-hash | environment-hash)
        printf "HASHED_PASSWORD='%s'\n" "$file_hash" >> "$SMOKE_DIR/auth.env"
        credential=PASSWORD=env-password; expected=file-hash; rejected=env-password
        if [ "$scenario" = environment-hash ]; then
          credential="HASHED_PASSWORD=$env_hash"; expected=env-hash; rejected=file-hash
        fi
        ;;
    esac
    cid="$(docker create --label "$SMOKE_LABEL" -e "$credential" \
      -e WORKSPACE_CONFIG_FILE=/etc/workspace-test.env "$img")"
    docker cp "$SMOKE_DIR/auth.env" "$cid:/etc/workspace-test.env"
    docker start "$cid" >/dev/null
    if wait_for_url "$cid" http://127.0.0.1:8080/code/login && check_code_login "$cid" "$expected" "$rejected"; then
      pass "code-server accepts the intended $scenario credential and rejects the alternative"
    else
      fail "code-server $scenario credential precedence"
    fi
    docker rm -f "$cid" >/dev/null
  done
}

test_jupyter_auth() {
  local img="$1" cid token expected rejected
  header "Testing: Jupyter credential precedence"
  printf "%s\n" "JUPYTER_TOKEN='file-token'" > "$SMOKE_DIR/jupyter.env"
  for token in '' env-token; do
    expected="${token:-file-token}"
    rejected=incorrect
    [ -z "$token" ] || rejected=file-token
    cid="$(docker create --label "$SMOKE_LABEL" \
      --mount "type=volume,src=${SMOKE_HOME_VOLUME},dst=/home/dev" \
      -e "JUPYTER_TOKEN=$token" -e WORKSPACE_CONFIG_FILE=/etc/workspace-test.env "$img")"
    docker cp "$SMOKE_DIR/jupyter.env" "$cid:/etc/workspace-test.env"
    docker start "$cid" >/dev/null
    if wait_for_url "$cid" http://127.0.0.1:8080/lab/login && docker exec "$cid" sh -eu -c '
      url=http://127.0.0.1:8080/lab/api/kernelspecs
      test "$(curl --noproxy "*" -sS --max-time 5 -o /dev/null -w "%{http_code}" "$url")" = 403
      test "$(curl --noproxy "*" -sS --max-time 5 -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $2" "$url")" = 403
      curl --noproxy "*" -fsS --max-time 5 -H "Authorization: token $1" "$url" |
        jq -e ".kernelspecs | has(\"python3\")" >/dev/null
    ' sh "$expected" "$rejected"; then
      pass "Jupyter accepts $expected and rejects missing/incorrect tokens"
    else
      fail "Jupyter token precedence and authentication"
    fi
    docker rm -f "$cid" >/dev/null
  done
}

test_enterprise_proxy() {
  local base="$1"
  header "Testing: enterprise shell proxy configuration"
  SMOKE_ENTERPRISE_IMAGE="$IMAGE_REGISTRY/enterprise:${SMOKE_DIR##*/}"
  # The smoke base lives in the daemon's image store, not a remote Buildx builder.
  BUILDX_BUILDER='' docker build --build-arg BASE_IMAGE="$base" \
    --tag "$SMOKE_ENTERPRISE_IMAGE" "$ROOT_DIR/templates/enterprise"
  if docker run --rm -i --label "$SMOKE_LABEL" --entrypoint sh "$SMOKE_ENTERPRISE_IMAGE" -s <<'EOF'
set -eu
printf '%s\n' 'HTTP_PROXY=http://proxy.invalid:8080' 'http_proxy=http://proxy.invalid:8080' \
  'NO_PROXY=localhost,127.0.0.1' 'no_proxy=localhost,127.0.0.1' \
  'PROXY_READS=$(( ${PROXY_READS:-0} + 1 ))' > /etc/enterprise/proxy.env
mkdir /tmp/existing-home
for file in .bash_profile .bashrc .zprofile .zshrc; do
  printf '%s\n' 'export USER_PROXY_RC=loaded' 'export HTTP_PROXY=http://user.invalid:8080' \
    > "/tmp/existing-home/$file"
done
chown -R dev:dev /tmp/existing-home
set -- /tmp/existing-home/.bash_profile /tmp/existing-home/.bashrc \
  /tmp/existing-home/.zprofile /tmp/existing-home/.zshrc
before="$(sha256sum "$@")"
for shell in bash zsh; do
  for mode in -lc -ic -lic; do
    /command/s6-setuidgid dev env -u HTTP_PROXY -u http_proxy -u NO_PROXY -u no_proxy \
      -u PROXY_READS -u USER_PROXY_RC HOME=/tmp/existing-home "$shell" "$mode" '
        test "$(printenv PROXY_READS)" = 1 &&
        test "$(printenv USER_PROXY_RC)" = loaded &&
        test "$(printenv HTTP_PROXY)" = http://user.invalid:8080 &&
        test "$(printenv http_proxy)" = http://proxy.invalid:8080 &&
        test "$(printenv NO_PROXY)" = localhost,127.0.0.1 &&
        test "$(printenv no_proxy)" = localhost,127.0.0.1
      '
  done
  /command/s6-setuidgid dev env -u PROXY_READS -u USER_PROXY_RC \
    HOME=/tmp/existing-home HTTP_PROXY=http://inherited.invalid:8080 "$shell" -c '
      test "${PROXY_READS-unset}" = unset &&
      test "${USER_PROXY_RC-unset}" = unset &&
      test "$(printenv HTTP_PROXY)" = http://inherited.invalid:8080
    '
done
test "$before" = "$(sha256sum "$@")"
EOF
  then
    pass "enterprise proxy loads once, preserves user startup files, and leaves non-interactive shells unchanged"
  else
    fail "enterprise shell proxy configuration"
  fi
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
  cid="$(docker run -d --label "$SMOKE_LABEL" "$img")"
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
  if docker exec "$cid" sh -lc "curl -fsS http://127.0.0.1:8080/ | grep -q 'Code Server'" &>/dev/null; then
    pass "static dashboard responding"
  else
    fail "static dashboard responding"
  fi
  docker rm -f "$cid" &>/dev/null || true

  test_code_auth "$img"
}

test_jvm_build() {
  local img="$1" cid
  header "Testing: Java/Kotlin/Gradle compatibility"
  cid="$(docker create --label "$SMOKE_LABEL" -e HOME=/home/dev --entrypoint /bin/sh "$img" -eu -c '
    chown -R dev:dev /tmp/jvm-smoke
    exec /command/s6-setuidgid dev gradle --no-daemon --console=plain -p /tmp/jvm-smoke run
  ')"
  docker cp "$ROOT_DIR/tests/fixtures/jvm" "$cid:/tmp/jvm-smoke"
  if docker start --attach "$cid"; then
    pass "Gradle compiles and runs Java/Kotlin together on the image JDK"
  else
    fail "Java/Kotlin/Gradle compatibility"
  fi
  docker rm "$cid" >/dev/null
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
  run_version "$img" "npm" npm --version
  run_check "$img" "Python is image-owned" "test \"\$(uv python dir)\" = /opt/uv-python && test \"\$(command -v python)\" = /opt/uv-tools/bin/python"
  run_check "$img" "Python executes" "python -c 'assert 2 + 2 == 4'"
  test_jvm_build "$img"
  run_check "$img" "kubectl client dry run" "kubectl create configmap workspace-smoke --from-literal=answer=42 --dry-run=client -o json | jq -e '.data.answer == \"42\"'"
  run_check "$img" "Helm renders a chart" "helm create /tmp/helm-smoke && helm lint /tmp/helm-smoke && helm template review /tmp/helm-smoke > /tmp/helm-smoke.yaml && yq ea -e 'select(.kind == \"Deployment\")' /tmp/helm-smoke.yaml"
  run_check "$img" "DuckDB persists and queries data" "duckdb /tmp/smoke.duckdb -c 'CREATE TABLE t AS SELECT 42 AS answer;' && test \"\$(duckdb -csv -noheader /tmp/smoke.duckdb -c 'SELECT answer FROM t;')\" = 42"
  run_check "$img" "grpcurl parses service descriptors" "printf '%s\n' 'syntax = \"proto3\"; package smoke; message Message {} service Echo { rpc Ping(Message) returns (Message); }' > /tmp/smoke.proto && grpcurl -import-path /tmp -proto smoke.proto describe smoke.Echo"
  run_check "$img" "mc preserves configuration and administrative commands" '
    set -eu
    mkdir -p "$HOME/.mc"
    cat > "$HOME/.mc/config.json" <<EOF
{"version":"10","aliases":{"review":{"url":"http://127.0.0.1:9000","accessKey":"review-access","secretKey":"review-secret","api":"S3v4","path":"auto"}}}
EOF
    before=$(sha256sum "$HOME/.mc/config.json")
    mc --json alias ls review | jq -e ".status == \"success\" and .URL == \"http://127.0.0.1:9000\""
    test "$before" = "$(sha256sum "$HOME/.mc/config.json")"
    mc admin user --help >/dev/null
    mc admin policy --help >/dev/null
  '
  run_check "$img" "npm executes" "mkdir /tmp/npm-smoke && cd /tmp/npm-smoke && npm init --yes >/dev/null && node -e 'if (require(\"./package.json\").name !== \"npm-smoke\") process.exit(1)'"
  run_check "$img" "Kotlin executes" "kotlin -e 'check(2 + 2 == 4)'"
  run_check "$img" "Go executes" "printf 'package main\nfunc main() {}\n' >/tmp/main.go && go run /tmp/main.go"
  run_check "$img" "Rust executes" "printf 'fn main() { assert_eq!(2 + 2, 4); }\n' >/tmp/main.rs && rustc /tmp/main.rs -o /tmp/main && /tmp/main"
  run_check "$img" "Node executes" "node -e 'if (2 + 2 !== 4) process.exit(1)'"

  for cmd in ruff mypy kotlin gradle cargo cc fnm kubectl helm k9s stern kubectx kubens xh grpcurl gron lazygit delta gh just duckdb yq psql redis-cli kcat websocat mlr rsync s5cmd mc ldb sst_dump datamash pv parallel gawk; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done
}

test_full() {
  local img
  img="$(image_for full)"
  header "Testing: full"
  run_version "$img" "Trivy" trivy --version
  run_check "$img" "Hyperfine executes and exports JSON v2" "hyperfine --runs 2 --export-json /tmp/hyperfine.json true && jq -e '.schema_version == 2 and (.results[0].measurements | length) == 2 and .results[0].summary.time_wall_clock.count == 2' /tmp/hyperfine.json"

  for cmd in jupyter-lab gdb strace ltrace valgrind tcpdump sqlite3 trivy gitleaks hyperfine; do
    run_check "$img" "$cmd exists" command -v "$cmd"
  done

  SMOKE_HOME_VOLUME="$(docker volume create --label "$SMOKE_LABEL")"
  docker run --rm --label "$SMOKE_LABEL" \
    --mount "type=volume,src=${SMOKE_HOME_VOLUME},dst=/home/dev,volume-nocopy" \
    --entrypoint /bin/sh "$img" -c 'chown 1000:1000 /home/dev && touch /home/dev/existing-home' &>/dev/null

  run_home_check "$img" "Existing home remains intact" test -f /home/dev/existing-home
  run_home_check "$img" "Python survives an existing home" "python -c 'assert 2 + 2 == 4' && test \"\$(uv python dir)\" = /opt/uv-python"
  run_home_check "$img" "JupyterLab survives an existing home" jupyter-lab --version
  run_home_check "$img" "Jupyter kernels registered" "/opt/uv-tools/jupyterlab/bin/jupyter kernelspec list --json | jq -e '.kernelspecs | has(\"python3\") and has(\"bash\") and has(\"rust\") and has(\"gonb\") and has(\"kotlin\")'"
  run_home_check "$img" "Bash/Kotlin kernel modules import" "/opt/uv-tools/jupyterlab/bin/python -c 'import bash_kernel, run_kotlin_kernel'"
  run_home_check "$img" "Rust kernel exists" command -v evcxr_jupyter
  run_home_check "$img" "Go kernel exists" command -v gonb
  run_version "$img" "gopls" gopls version
  run_home_check "$img" "Go kernel helpers exist" "command -v goimports && command -v gopls"
  run_home_check "$img" "Python kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"python-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"assert 2 + 2 == 4\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Python 3\",\"language\":\"python\",\"name\":\"python3\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/python-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/python-smoke.ipynb"
  run_home_check "$img" "Bash kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"bash-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"test \$((2 + 2)) -eq 4\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Bash\",\"language\":\"bash\",\"name\":\"bash\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/bash-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/bash-smoke.ipynb"
  run_home_check "$img" "Rust kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"rust-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"assert_eq!(2 + 2, 4);\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Rust\",\"language\":\"rust\",\"name\":\"rust\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/rust-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/rust-smoke.ipynb"
  run_home_check "$img" "Go kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"gonb-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"%%\\n\",\"fmt.Println(2 + 2)\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Go (gonb)\",\"language\":\"go\",\"name\":\"gonb\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/gonb-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/gonb-smoke.ipynb"
  run_home_check "$img" "Kotlin kernel executes" "/opt/uv-tools/jupyterlab/bin/python -c 'import json; json.dump({\"cells\":[{\"cell_type\":\"code\",\"execution_count\":None,\"id\":\"kotlin-smoke\",\"metadata\":{},\"outputs\":[],\"source\":[\"check(2 + 2 == 4)\\n\"]}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Kotlin\",\"language\":\"kotlin\",\"name\":\"kotlin\"}},\"nbformat\":4,\"nbformat_minor\":5}, open(\"/tmp/kotlin-smoke.ipynb\", \"w\"))' && /opt/uv-tools/jupyterlab/bin/jupyter execute /tmp/kotlin-smoke.ipynb"

  test_jupyter_auth "$img"
}

cleanup() {
  local status=$? containers volumes
  trap - EXIT
  trap '' HUP INT TERM
  containers="$(docker ps -aq --filter "label=$SMOKE_LABEL")" || status=1
  for container in $containers; do
    if [ "$status" -ne 0 ]; then docker logs "$container" >&2 || true; fi
    docker rm -f "$container" >/dev/null || status=1
  done
  volumes="$(docker volume ls -q --filter "label=$SMOKE_LABEL")" || status=1
  for volume in $volumes; do docker volume rm "$volume" >/dev/null || status=1; done
  if [ -n "$SMOKE_ENTERPRISE_IMAGE" ] && docker image inspect "$SMOKE_ENTERPRISE_IMAGE" >/dev/null 2>&1; then
    docker image rm --no-prune "$SMOKE_ENTERPRISE_IMAGE" >/dev/null || status=1
  fi
  rm -rf "$SMOKE_DIR"
  exit "$status"
}

BUILD_IMAGES=true
if [ "${1:-}" = --no-build ]; then
  BUILD_IMAGES=false
  shift
fi
FLAVORS=("${@:-code}")
[[ "${FLAVORS[0]}" == all ]] && FLAVORS=(code platform full)
for flavor in "${FLAVORS[@]}"; do
  case "$flavor" in
    code | platform | full) ;;
    *) echo "Unsupported flavor: $flavor" >&2; exit 1 ;;
  esac
done

SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/workspace-smoke.XXXXXXXXXX")"
SMOKE_LABEL="workspace.smoke=${SMOKE_DIR##*/}"
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$BUILD_IMAGES" = true ]; then
  build_flavors "${FLAVORS[@]}"
else
  for flavor in "${FLAVORS[@]}"; do docker image inspect "$(image_for "$flavor")" >/dev/null; done
fi

for flavor in "${FLAVORS[@]}"; do
  case "$flavor" in
    code) test_code ;;
    platform) test_platform ;;
    full) test_full ;;
    *) echo "Unsupported flavor: $flavor" >&2; exit 1 ;;
  esac
done

# All flavors share the runtime layer; full also exercises Jupyter when available.
lifecycle_flavor="${FLAVORS[0]}"
for flavor in "${FLAVORS[@]}"; do
  if [ "$flavor" = full ]; then lifecycle_flavor=full; fi
done
if bash "$SCRIPT_DIR/test-lifecycle.sh" "$(image_for "$lifecycle_flavor")"; then
  pass "$lifecycle_flavor service lifecycle"
else
  fail "$lifecycle_flavor service lifecycle"
fi

test_enterprise_proxy "$(image_for "$lifecycle_flavor")"

header "Results"
echo -e "  ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
[ "$FAIL" -eq 0 ]
