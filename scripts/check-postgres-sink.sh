#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source env.sh

POD=$(kubectl get pod -n "${NAMESPACE}" -l app=warehouse-postgresql -o jsonpath='{.items[0].metadata.name}')

psql_q() { kubectl exec -n "${NAMESPACE}" -i "${POD}" -- env PGPASSWORD=warehouse psql -U warehouse -d warehouse "$@"; }

echo ">>> Tables in the warehouse:"
psql_q -c "\dt public.*"

echo
echo ">>> Row counts per table:"
psql_q -t -c "
  SELECT format('%I.%I', schemaname, relname) AS table, n_live_tup AS approx_rows
  FROM pg_stat_user_tables ORDER BY 1;"

echo
echo ">>> Rows received in each table (up to 10):"
TABLES=$(psql_q -t -A -c "SELECT format('%I.%I', schemaname, relname) FROM pg_stat_user_tables ORDER BY 1;" | tr -d '\r')
for t in ${TABLES}; do
  echo "--- ${t} ---"
  psql_q -c "SELECT * FROM ${t} LIMIT 10;"
done
