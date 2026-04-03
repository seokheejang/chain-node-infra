#!/usr/bin/env bash
# Set up a local e2e test environment: Kind + ArgoCD.
# Kubeconfig is stored at e2e/.kubeconfig — never touches ~/.kube/config.
#
# Usage:
#   e2e/scripts/setup.sh              # create with defaults
#   e2e/scripts/setup.sh --name foo   # custom cluster name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"

E2E_DIR="${REPO_ROOT}/e2e"

# --- Config ---
CLUSTER_NAME="chain-node-e2e"
ARGOCD_CHART_VERSION="9.4.17"
ARGOCD_NAMESPACE="argocd"
E2E_KUBECONFIG="${E2E_DIR}/.kubeconfig"
ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-admin}"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# All kubectl/helm commands use this kubeconfig
export KUBECONFIG="${E2E_KUBECONFIG}"

# --- Preflight ---
require_cmd kind
require_cmd helm
require_cmd kubectl
require_cmd htpasswd

echo ""
echo "=== e2e Setup ==="
echo "  Cluster : ${CLUSTER_NAME}"
echo "  Config  : ${E2E_KUBECONFIG}"
echo ""

# --- Kind cluster ---
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "[1/5] Kind cluster '${CLUSTER_NAME}' already exists. Skipping."
    # Export kubeconfig for existing cluster
    kind get kubeconfig --name "${CLUSTER_NAME}" > "${E2E_KUBECONFIG}"
else
    echo "[1/5] Creating Kind cluster '${CLUSTER_NAME}'..."
    kind create cluster \
        --name "${CLUSTER_NAME}" \
        --config "${E2E_DIR}/kind/cluster.yaml" \
        --kubeconfig "${E2E_KUBECONFIG}" \
        --wait 60s
fi
echo "[1/5] Done."

# --- ArgoCD ---
echo "[2/5] Adding Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

echo "[3/5] Installing ArgoCD (chart ${ARGOCD_CHART_VERSION})..."

# Generate bcrypt hash for admin password
BCRYPT_HASH=$(htpasswd -nbBC 10 "" "${ADMIN_PASSWORD}" | cut -d: -f2)

helm upgrade --install argocd argo/argo-cd \
    --version "${ARGOCD_CHART_VERSION}" \
    --namespace "${ARGOCD_NAMESPACE}" \
    --create-namespace \
    -f "${E2E_DIR}/argocd/values.yaml" \
    --set "configs.secret.argocdServerAdminPassword=${BCRYPT_HASH}" \
    --timeout 10m \
    --wait

echo "[3/5] Done."

echo "[4/5] Waiting for all pods to be ready..."
# Exclude completed Job pods (e.g. redis-secret-init) which never become Ready
kubectl wait --for=condition=Ready pods \
    --field-selector=status.phase=Running \
    -n "${ARGOCD_NAMESPACE}" \
    --timeout=300s
echo "[4/5] Done."

# --- Delete initial admin secret (we set our own password) ---
echo "[5/6] Cleaning up..."
kubectl delete secret argocd-initial-admin-secret -n "${ARGOCD_NAMESPACE}" 2>/dev/null || true
echo "[5/6] Done."

# --- Verify ---
echo "[6/6] Verifying environment..."
"${SCRIPT_DIR}/verify.sh" --name "${CLUSTER_NAME}"

echo ""
echo "==========================================="
echo "  e2e environment ready"
echo "==========================================="
echo ""
echo "  Cluster      : kind-${CLUSTER_NAME}"
echo "  KUBECONFIG   : ${E2E_KUBECONFIG}"
echo "  ArgoCD NS    : ${ARGOCD_NAMESPACE}"
echo "  Admin user   : ${ARGOCD_ADMIN_USER:-admin}"
echo "  Admin pass   : ${ADMIN_PASSWORD}"
echo ""
echo "  Use kubectl/helm:"
echo "    export KUBECONFIG=${E2E_KUBECONFIG}"
echo ""
echo "  ArgoCD UI:"
echo "    kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
echo "    open https://localhost:8080"
echo ""
echo "  Re-verify:"
echo "    e2e/scripts/verify.sh"
echo ""
echo "  Teardown:"
echo "    e2e/scripts/teardown.sh"
echo "==========================================="
