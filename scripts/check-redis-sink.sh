#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source env.sh

POD=$(kubectl get pod -n "${NAMESPACE}" -l app=redis -o jsonpath='{.items[0].metadata.name}')

redis() { kubectl exec -n "${NAMESPACE}" -i "${POD}" -- redis-cli "$@"; }

echo ">>> Redis keys (streams):"
redis KEYS '*'

echo
echo ">>> Stream length + latest entries received (up to 5):"
for stream in $(redis KEYS '*' | tr -d '\r'); do
  echo "=== ${stream} (length: $(redis XLEN "${stream}" | tr -d '\r')) ==="
  redis XREVRANGE "${stream}" + - COUNT 5 || true
  echo
done
