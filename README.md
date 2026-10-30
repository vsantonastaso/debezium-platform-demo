# Beyond the First Pipeline: Scaling Data Pipelines Across Teams

Live-demo environment for the Platform Day talk. **One source database → three teams → three different sinks**, all managed by **Debezium Platform**.

```
                                  ┌─────────────────────────────┐
                                  │      Debezium Platform       │
                                  │  (Conductor + Stage UI +     │
                                  │   Operator one per pipeline  │
                                  │   runs a Debezium Server)    │
                                  └─────────────────────────────┘
                                             deploys ▼
   ┌───────────────┐   analytics-pipeline   ┌───────────────────────────┐
   │               │ ─────────────────────▶ │  Analytics → PostgreSQL    │  (JDBC sink)
   │   source      │   integration-pipeline  │  warehouse                 │
   │  PostgreSQL   │ ─────────────────────▶ │  Integration → HTTP webhook │  (HTTP sink)
   │  (inventory)  │   cache-pipeline        │  Cache → Redis streams      │  (Redis sink)
   │               │ ─────────────────────▶ │                            │
   └───────────────┘                         └───────────────────────────┘
        one shared source connection, reused by all three pipelines
```
## Prerequisites

- CLI tools: `brew install kind kubectl helm jq`
- **Debezium CLI** (used by `seed/seed.sh` and `seed/cleanup-pipelines.sh`), installed via JBang:
  `sdk install jbang` then `jbang app install debezium@debezium` (needs Java 17+).
- **A webhook.site inbox** for the Integration team's HTTP sink. Open <https://webhook.site>,
  copy your unique URL, and set it in `env.sh` (`WEBHOOK_URL=...`). Free inboxes are ephemeral
  and rate-limited (~100 requests), so generate a fresh one shortly before the talk.

## One-time setup

```sh
./init.sh      # kind cluster + ingress-nginx + /etc/hosts (asks for sudo)
```

Wait until all pods are Ready, then open the UI:

```sh
kubectl get pods -n debezium-platform
open http://platform.debezium.io/
```
---

## Reset / teardown

```sh
# delete ONLY the pipelines (keep connections/sources/destinations) e.g. to rebuild live:
./seed/cleanup-pipelines.sh http://platform.debezium.io

# (re)create everything via the Debezium CLI (connections + sources + destinations + pipelines):
./seed/seed.sh http://platform.debezium.io

# full teardown (whole cluster):
./clean-up.sh
```