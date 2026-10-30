#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source env.sh

echo ">>> Deleting kind cluster '${CLUSTER}'..."
kind delete cluster --name "${CLUSTER}" || true

echo ">>> Removing /etc/hosts entry for ${DEBEZIUM_PLATFORM_DOMAIN}..."
if grep -qE "^[^#]*\b${DEBEZIUM_PLATFORM_DOMAIN}\b" /etc/hosts; then
  sudo sed -i.bak "/[[:space:]]${DEBEZIUM_PLATFORM_DOMAIN}\$/d" /etc/hosts || \
    echo "    Could not auto-remove; remove the ${DEBEZIUM_PLATFORM_DOMAIN} line from /etc/hosts manually."
  echo "    Done (backup at /etc/hosts.bak)."
else
  echo "    No entry found."
fi

echo "Cleaned up."
