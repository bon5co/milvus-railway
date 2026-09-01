#!/bin/bash
# Railway entrypoint for single-service Milvus standalone.
#
# Responsibilities, in order:
#   1. refuse to boot without a root password (Milvus with authorization
#      enabled and an empty default password is a public vector store)
#   2. start Milvus in the background
#   3. once it answers /healthz, re-apply the root password so that changing
#      MILVUS_ROOT_PASSWORD and redeploying is a working password reset --
#      Milvus only reads COMMON_SECURITY_DEFAULTROOTPASSWORD when it
#      initialises an empty metastore, and it has no offline reset path
#   4. hand the container's exit status back to the Milvus process
set -uo pipefail

log() { echo "[railway] $*"; }

: "${MILVUS_ROOT_PASSWORD:=}"
if [ -z "$MILVUS_ROOT_PASSWORD" ]; then
  log "FATAL: MILVUS_ROOT_PASSWORD is empty. Milvus would start with authorization"
  log "       enabled and no usable credential. Set it and redeploy."
  exit 1
fi
case "$MILVUS_ROOT_PASSWORD" in
  *[![:print:]]*|*:*)
    log "FATAL: MILVUS_ROOT_PASSWORD must be printable and must not contain ':'"
    log "       (Milvus tokens are 'user:password', so a colon breaks the token)."
    exit 1
    ;;
esac

export COMMON_SECURITY_DEFAULTROOTPASSWORD="$MILVUS_ROOT_PASSWORD"

DATA_DIR="${MILVUS_DATA_DIR:-/var/lib/milvus}"
STATE_FILE="$DATA_DIR/.railway-root-password"
HEALTH_PORT="${MILVUS_HEALTH_PORT:-9091}"
API_PORT="${MILVUS_GRPC_PORT:-19530}"

mkdir -p "$DATA_DIR"

rotate_root_password() {
  # Wait for Milvus to serve. First boot on a fresh volume builds the metastore
  # and can take a couple of minutes.
  local i code
  for i in $(seq 1 200); do
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${HEALTH_PORT}/healthz" || true)
    [ "$code" = "200" ] && break
    sleep 3
  done
  if [ "$code" != "200" ]; then
    log "milvus did not become healthy; skipping the root-password check"
    return
  fi

  if [ ! -f "$STATE_FILE" ]; then
    # Fresh metastore: Milvus created root from COMMON_SECURITY_DEFAULTROOTPASSWORD.
    printf '%s' "$MILVUS_ROOT_PASSWORD" > "$STATE_FILE"
    chmod 0600 "$STATE_FILE"
    log "root credential initialised from MILVUS_ROOT_PASSWORD"
    return
  fi

  local previous
  previous=$(cat "$STATE_FILE")
  if [ "$previous" = "$MILVUS_ROOT_PASSWORD" ]; then
    log "root password unchanged"
    return
  fi

  local body
  body=$(curl -s -m 15 -X POST \
    "http://127.0.0.1:${API_PORT}/v2/vectordb/users/update_password" \
    -H "Authorization: Bearer root:${previous}" \
    -H 'Content-Type: application/json' \
    --data-binary "$(printf '{"userName":"root","password":"%s","newPassword":"%s"}' "$previous" "$MILVUS_ROOT_PASSWORD")" || true)

  case "$body" in
    *'"code":0'*)
      printf '%s' "$MILVUS_ROOT_PASSWORD" > "$STATE_FILE"
      chmod 0600 "$STATE_FILE"
      log "root password rotated to the current MILVUS_ROOT_PASSWORD"
      ;;
    *)
      log "could not rotate the root password (the stored one may have been changed"
      log "through the API): ${body}"
      ;;
  esac
}

log "starting milvus standalone (embedded etcd, local storage) on ${API_PORT}"
milvus run standalone &
MILVUS_PID=$!

# bash does not forward signals while it is blocked in `wait`, so Railway's
# SIGTERM would otherwise never reach Milvus and every redeploy would be a
# hard kill after the grace period.
forward() { kill -"$1" "$MILVUS_PID" 2>/dev/null || true; }
trap 'forward TERM' TERM
trap 'forward INT' INT

rotate_root_password &

wait "$MILVUS_PID"
status=$?
# `wait` returns 128+n when a trap fired; wait again for the real exit status.
wait "$MILVUS_PID" 2>/dev/null || true
exit "$status"
