#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ../env.sh

PA="${1:-http://${DEBEZIUM_PLATFORM_DOMAIN:-platform.debezium.io}}"
DIR="${2:-payloads}"

command -v jbang    >/dev/null 2>&1 || export PATH="$HOME/.sdkman/candidates/jbang/current/bin:$PATH"
command -v debezium >/dev/null 2>&1 || export PATH="$HOME/.jbang/bin:$PATH"
command -v debezium >/dev/null 2>&1 || { echo "debezium CLI not found. Install: jbang app install debezium@debezium"; exit 1; }
command -v jbang    >/dev/null 2>&1 || { echo "jbang not found on PATH"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

render() {
  local out="$TMP/$1"
  sed \
    -e "s/{{SOURCE_CONN_ID}}/${SOURCE_CONN_ID:-}/g" \
    -e "s/{{JDBC_CONN_ID}}/${JDBC_CONN_ID:-}/g" \
    -e "s/{{HTTP_CONN_ID}}/${HTTP_CONN_ID:-}/g" \
    -e "s/{{REDIS_CONN_ID}}/${REDIS_CONN_ID:-}/g" \
    -e "s/{{ANALYTICS_SOURCE_ID}}/${ANALYTICS_SOURCE_ID:-}/g" \
    -e "s/{{INTEGRATION_SOURCE_ID}}/${INTEGRATION_SOURCE_ID:-}/g" \
    -e "s/{{CACHE_SOURCE_ID}}/${CACHE_SOURCE_ID:-}/g" \
    -e "s/{{ANALYTICS_DEST_ID}}/${ANALYTICS_DEST_ID:-}/g" \
    -e "s/{{INTEGRATION_DEST_ID}}/${INTEGRATION_DEST_ID:-}/g" \
    -e "s/{{CACHE_DEST_ID}}/${CACHE_DEST_ID:-}/g" \
    -e "s|{{WEBHOOK_URL}}|${WEBHOOK_URL:-}|g" \
    "${DIR}/$1" > "$out"
  echo "$out"
}

create() {
  local out id
  out="$(debezium "$1" create -f "$(render "$2")" --platform-address "$PA" 2>&1)" || true
  id="$(printf '%s\n' "$out" | sed -nE 's/.*created with id: ([0-9]+).*/\1/p' | head -1)"
  if [ -z "$id" ]; then
    echo "Failed to create $1 from $2:" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  printf '%s' "$id"
}

echo ">>> Platform: ${PA}"
echo ">>> Creating connections..."
SOURCE_CONN_ID="$(create connection connection-source.yaml)"; echo "    source-postgres  -> id ${SOURCE_CONN_ID}"
JDBC_CONN_ID="$(create connection connection-jdbc.yaml)";     echo "    warehouse-jdbc   -> id ${JDBC_CONN_ID}"
HTTP_CONN_ID="$(create connection connection-http.yaml)";     echo "    integration-http -> id ${HTTP_CONN_ID}"
REDIS_CONN_ID="$(create connection connection-redis.yaml)";   echo "    cache-redis      -> id ${REDIS_CONN_ID}"

echo ">>> Creating sources..."
ANALYTICS_SOURCE_ID="$(create source source-analytics.yaml)";     echo "    analytics-source   -> id ${ANALYTICS_SOURCE_ID}"
INTEGRATION_SOURCE_ID="$(create source source-integration.yaml)"; echo "    integration-source -> id ${INTEGRATION_SOURCE_ID}"
CACHE_SOURCE_ID="$(create source source-cache.yaml)";             echo "    cache-source       -> id ${CACHE_SOURCE_ID}"

echo ">>> Creating destinations..."
ANALYTICS_DEST_ID="$(create destination destination-analytics.yaml)";     echo "    analytics-warehouse -> id ${ANALYTICS_DEST_ID}"
INTEGRATION_DEST_ID="$(create destination destination-integration.yaml)"; echo "    integration-webhook -> id ${INTEGRATION_DEST_ID}"
CACHE_DEST_ID="$(create destination destination-cache.yaml)";             echo "    cache-redis         -> id ${CACHE_DEST_ID}"

