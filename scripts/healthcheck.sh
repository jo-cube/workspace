#!/bin/sh
set -eu

check() { curl --noproxy '*' -fsS --max-time 3 "$1" >/dev/null; }

check http://127.0.0.1:8080/health
[ "${ENABLE_CODE:-false}" != "true" ] || check http://127.0.0.1:8081/healthz
[ "${ENABLE_JUPYTER:-false}" != "true" ] || check http://127.0.0.1:8888/lab
