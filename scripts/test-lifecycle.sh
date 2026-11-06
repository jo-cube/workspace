#!/usr/bin/env bash
set -euo pipefail

# Exercise the real /init and services in an already-built image; publish no ports.
# Test-only init/finish hooks gate startup and record exit signals, without changing run scripts.
IMAGE="${1:?Usage: bash scripts/test-lifecycle.sh IMAGE}"
docker image inspect "$IMAGE" >/dev/null
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/workspace-lifecycle.XXXXXXXXXX")"
TEST_LABEL="workspace.lifecycle=${TEST_DIR##*/}"

cleanup() {
  local status=$? containers volumes
  trap - EXIT
  trap '' HUP INT TERM
  # Labels also cover interruption before a create command returns its resource ID.
  containers="$(docker ps -aq --filter "label=$TEST_LABEL")" || status=1
  for container in $containers; do
    if [ "$status" -ne 0 ]; then docker logs "$container" >&2 || true; fi
    docker rm -f "$container" >/dev/null || status=1
  done
  volumes="$(docker volume ls -q --filter "label=$TEST_LABEL")" || status=1
  for volume in $volumes; do docker volume rm "$volume" >/dev/null || status=1; done
  rm -rf "$TEST_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

wait_until() {
  for _ in {1..60}; do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "Timed out: $*" >&2
  return 1
}

health_is() {
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$CID")" = "$1" ]
}

wait_healthy() {
  wait_until docker exec "$CID" /scripts/healthcheck.sh
  wait_until health_is healthy
}

# Let the host release initialization explicitly, rather than racing a fixed sleep.
cat > "$TEST_DIR/init" <<'EOF'
#!/bin/sh
set -eu
touch /run/lifecycle-init-waiting
while [ ! -e /run/lifecycle-init-release ]; do sleep 0.1; done
/bin/sh /tmp/lifecycle-fix-perms
touch /run/lifecycle-init-done
EOF
chmod +x "$TEST_DIR/init"

HOME_VOLUME="$(docker volume create --label "$TEST_LABEL")"
CACHE_VOLUME="$(docker volume create --label "$TEST_LABEL")"

for phase in fresh reused; do
  echo "Lifecycle: $IMAGE ($phase volumes)"
  CID="$(docker create --pull=never --label "$TEST_LABEL" --stop-timeout 10 \
    --health-interval 1s --health-start-period 1s --health-retries 1 \
    --mount "type=volume,src=$HOME_VOLUME,dst=/home/dev,volume-nocopy" \
    --mount "type=volume,src=$CACHE_VOLUME,dst=/cache,volume-nocopy" "$IMAGE")"
  docker cp "$CID:/etc/cont-init.d/00-fix-perms" "$TEST_DIR/fix-perms"
  docker cp "$TEST_DIR/fix-perms" "$CID:/tmp/lifecycle-fix-perms"
  docker cp "$TEST_DIR/init" "$CID:/etc/cont-init.d/00-fix-perms"
  for service in caddy code-server jupyter; do
    # Exit arguments expand later, when s6 invokes the finish script.
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "$1" "$2" > /tmp/lifecycle-exit-%s\n' "$service" > "$TEST_DIR/finish"
    chmod +x "$TEST_DIR/finish"
    docker cp "$TEST_DIR/finish" "$CID:/etc/s6-overlay/s6-rc.d/$service/finish"
  done
  docker start "$CID" >/dev/null
  wait_until docker exec "$CID" test -e /run/lifecycle-init-waiting

  # Timeout (99) is the expected result: no service may start while init is held.
  result=0
  docker exec "$CID" /command/s6-svwait -u -o -t 1000 \
    /run/service/caddy /run/service/code-server /run/service/jupyter >/dev/null 2>&1 || result=$?
  if [ "$result" -ne 99 ]; then
    echo "A service started before permission initialization (s6-svwait: $result)" >&2
    exit 1
  fi
  docker exec "$CID" touch /run/lifecycle-init-release
  wait_until docker exec "$CID" test -e /run/lifecycle-init-done
  wait_healthy
  docker exec --user dev "$CID" sh -eu -c '
    for path in /home/dev /home/dev/.local/share /home/dev/.local/state /home/dev/.cache /home/dev/.config /cache /cache/uv /cache/go /cache/gradle; do
      test -w "$path"
    done'
  echo "  Initialization ordered; enabled applications healthy; persistent directories writable"

  if [ "$phase" = fresh ]; then
    docker exec --user dev "$CID" sh -eu -c '
      printf "%s\n" "{\"editor.fontSize\": 17}" > /home/dev/.config/code-server/User/settings.json
      printf "%s\n" "# user shell configuration" > /home/dev/.bashrc
      mkdir -p /home/dev/.jupyter
      printf "%s\n" "# user Jupyter configuration" > /home/dev/.jupyter/jupyter_server_config.py
      printf "%s\n" "persistent cache" > /cache/lifecycle-sentinel'
    docker exec "$CID" sha256sum /home/dev/.config/code-server/User/settings.json /home/dev/.bashrc \
      /home/dev/.jupyter/jupyter_server_config.py /cache/lifecycle-sentinel > "$TEST_DIR/persistent.sha256"
  else
    docker exec -i "$CID" sha256sum -c < "$TEST_DIR/persistent.sha256"
    echo "  User configuration and cached data survived container replacement"

    # Keep each enabled service down long enough to observe Docker's health state.
    # Then separately kill it while supervision is enabled to prove automatic restart.
    services=(caddy)
    if docker exec "$CID" sh -c '[ "$ENABLE_CODE" = true ]'; then services+=(code-server); fi
    if docker exec "$CID" sh -c '[ "$ENABLE_JUPYTER" = true ]'; then services+=(jupyter); fi
    for service in "${services[@]}"; do
      path="/run/service/$service"
      docker exec "$CID" /command/s6-svc -wD -T 10000 -d "$path"
      if docker exec "$CID" /scripts/healthcheck.sh >/dev/null 2>&1; then
        echo "Healthcheck ignored stopped $service" >&2
        exit 1
      fi
      wait_until health_is unhealthy
      docker exec "$CID" /command/s6-svc -u "$path"
      wait_healthy
      docker exec "$CID" /command/s6-svc -wr -T 10000 -k "$path"
      wait_healthy
      echo "  $service: health detects outage; supervision recovers after crash"
    done
  fi

  # Clear earlier crash/down observations so only the final stop can satisfy this check.
  docker exec "$CID" sh -c 'for service in caddy code-server jupyter; do : > "/tmp/lifecycle-exit-$service"; done'
  stop_started=$SECONDS
  docker stop "$CID" >/dev/null
  test "$(docker inspect -f '{{.State.ExitCode}}' "$CID")" = 0
  for service in caddy code-server jupyter; do
    docker cp "$CID:/tmp/lifecycle-exit-$service" "$TEST_DIR/exit"
    case "$(cat "$TEST_DIR/exit")" in
      "0 0" | "256 15") ;;
      *) echo "$service did not exit cleanly: $(cat "$TEST_DIR/exit")" >&2; exit 1 ;;
    esac
  done
  echo "  Clean shutdown in $((SECONDS - stop_started))s (Docker stop budget: 10s; no service SIGKILL)"
  docker rm "$CID" >/dev/null
done
