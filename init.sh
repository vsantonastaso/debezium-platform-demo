#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source env.sh

echo ">>> Creating kind cluster '${CLUSTER}'..."
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  echo "    Cluster '${CLUSTER}' already exists, skipping create."
else
  kind create cluster --name "${CLUSTER}" --config kind-ingress.yaml
fi

echo ">>> Installing ingress-nginx..."
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=NodePort \
  --kube-context "kind-${CLUSTER}"

echo ">>> Waiting for ingress-nginx controller to be ready..."
kubectl --context "kind-${CLUSTER}" wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout="${TIMEOUT}"

echo ">>> Ensuring /etc/hosts maps ${DEBEZIUM_PLATFORM_DOMAIN} -> 127.0.0.1..."
if grep -qE "^[^#]*\b${DEBEZIUM_PLATFORM_DOMAIN}\b" /etc/hosts; then
  echo "    /etc/hosts already has an entry for ${DEBEZIUM_PLATFORM_DOMAIN}."
else
  echo "127.0.0.1 ${DEBEZIUM_PLATFORM_DOMAIN}" | sudo tee -a /etc/hosts >/dev/null
  echo "    Added: 127.0.0.1 ${DEBEZIUM_PLATFORM_DOMAIN}"
fi

CTX="kind-${CLUSTER}"
kubectl config use-context "${CTX}"

echo ">>> Creating namespace: ${NAMESPACE}"
kubectl create ns "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace="${NAMESPACE}"

echo ">>> Deploying source PostgreSQL..."
kubectl apply -n "${NAMESPACE}" -f k8s/source-postgresql.yml

echo ">>> Deploying sink: warehouse PostgreSQL..."
kubectl apply -n "${NAMESPACE}" -f k8s/sink-postgresql.yml

echo ">>> Deploying sink: Redis..."
kubectl apply -n "${NAMESPACE}" -f k8s/sink-redis.yml

echo ">>> Waiting for source database..."
kubectl wait pod -n "${NAMESPACE}" -l app=source-postgresql --for=condition=Ready --timeout="${TIMEOUT}"

echo ">>> Waiting for sink backends..."
kubectl wait pod -n "${NAMESPACE}" -l app=warehouse-postgresql --for=condition=Ready --timeout="${TIMEOUT}"
kubectl wait pod -n "${NAMESPACE}" -l app=redis --for=condition=Ready --timeout="${TIMEOUT}"

echo ">>> Installing OpenTelemetry Operator..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry-operator-system --create-namespace \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true
kubectl -n opentelemetry-operator-system rollout status deploy/opentelemetry-operator --timeout="${TIMEOUT}"

echo ">>> Installing Prometheus (kube-prometheus-stack)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.enabled=false \
  --set alertmanager.enabled=false \
  --set nodeExporter.enabled=false \
  --set kubeStateMetrics.enabled=false \
  --set prometheus.prometheusSpec.retention=2h \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.resources.requests.memory=400Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=1Gi

echo ">>> Waiting for the Prometheus StatefulSet to be created..."
for _ in $(seq 1 30); do
  kubectl -n monitoring get statefulset prometheus-kube-prometheus-stack-prometheus >/dev/null 2>&1 && break
  sleep 5
done
echo ">>> Waiting for Prometheus to be ready..."
kubectl -n monitoring rollout status statefulset/prometheus-kube-prometheus-stack-prometheus --timeout="${TIMEOUT}"

echo "Source + sinks + monitoring stack are up. Next: ./03-install-platform.sh"

echo ">>> Installing Debezium Platform via Helm (values from platform-values.yaml)..."
helm repo add debezium https://charts.debezium.io >/dev/null 2>&1 || true
helm repo update debezium >/dev/null

helm upgrade --install debezium-platform debezium/debezium-platform \
  --namespace "${NAMESPACE}" \
  --values "$(pwd)/platform-values.yaml"

echo ">>> Waiting for platform pods to be ready..."
kubectl wait --for=condition=Available deployments/conductor --timeout="${TIMEOUT}" -n "${NAMESPACE}"
kubectl wait --for=condition=Available deployments/stage --timeout="${TIMEOUT}" -n "${NAMESPACE}"

