#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source env.sh

ROUNDS="${1:-1}"
POD=$(kubectl get pod -n "${NAMESPACE}" -l app=source-postgresql -o jsonpath='{.items[0].metadata.name}')

run_sql() {
  kubectl exec -n "${NAMESPACE}" -i "${POD}" -- \
    env PGPASSWORD=debezium psql -U debezium -d debezium -v ON_ERROR_STOP=1 -c "$1"
}

for i in $(seq 1 "${ROUNDS}"); do
  echo ">>> Round ${i}/${ROUNDS}"
  run_sql "UPDATE inventory.products SET weight = round((weight + 0.1)::numeric, 2) WHERE id = 101;"
  run_sql "UPDATE inventory.products_on_hand SET quantity = quantity - 1 WHERE product_id = 101;"
  run_sql "INSERT INTO inventory.orders (order_date, purchaser, quantity, product_id) VALUES (CURRENT_DATE, 1001, $((RANDOM % 5 + 1)), 102);"
  run_sql "UPDATE inventory.customers SET email = 'sally.thomas+${i}@acme.com' WHERE id = 1001;"
  [ "${ROUNDS}" -gt 1 ] && sleep 2 || true
done

echo "Changes applied. Check the sinks with scripts/check-*.sh"
