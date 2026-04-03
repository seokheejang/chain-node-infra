#!/usr/bin/env bash
# Install ArgoCD on a Kubernetes cluster via Helm.
#
# Prerequisites:
#   - .envrc configured with KUBECONFIG
#   - helm, kubectl installed
#
# Usage:
#   scripts/install-argocd.sh                   # install with default values
#   scripts/install-argocd.sh -f custom.yaml    # install with custom values

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Config ---
CHART_VERSION="9.4.17"
RELEASE_NAME="argocd"
NAMESPACE="argocd"
VALUES_FILE="${REPO_ROOT}/argocd/install/values.yaml"

# --- Parse args ---
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# --- Preflight checks ---
require_cmd helm
require_cmd kubectl
require_var KUBECONFIG "Path to your kubeconfig file"

echo "=== ArgoCD Installation ==="
echo "  Chart version : argo-cd ${CHART_VERSION}"
echo "  Namespace     : ${NAMESPACE}"
echo "  Values file   : ${VALUES_FILE}"
echo "  KUBECONFIG    : ${KUBECONFIG}"
echo ""

# Verify cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo "[error] Cannot connect to cluster. Check your KUBECONFIG."
    exit 1
fi
echo "[ok] Cluster connection verified"

# --- Add Helm repo ---
echo "[step] Adding Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

# --- Install / Upgrade ---
echo "[step] Installing ArgoCD..."
helm upgrade --install "${RELEASE_NAME}" argo/argo-cd \
    --version "${CHART_VERSION}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f "${VALUES_FILE}" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"

# --- Wait for pods ---
echo "[step] Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pods \
    --all \
    -n "${NAMESPACE}" \
    --timeout=300s

# --- Print admin password ---
echo ""
echo "=== Installation Complete ==="
echo ""
ADMIN_PASS=$(kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
if [[ -n "${ADMIN_PASS}" ]]; then
    echo "  Admin username : admin"
    echo "  Admin password : ${ADMIN_PASS}"
    echo ""
    echo "  Change this password after first login."
else
    echo "  [warn] Could not retrieve initial admin password."
    echo "         It may have been deleted already."
fi
echo ""
echo "  Verify: kubectl get pods -n ${NAMESPACE}"
