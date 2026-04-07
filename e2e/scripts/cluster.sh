#!/usr/bin/env bash
# Kind cluster + ArgoCD e2e infrastructure manager.
# Kubeconfig is stored at e2e/.kubeconfig — never touches ~/.kube/config.
#
# Usage:
#   e2e/scripts/cluster.sh setup              # create Kind + install ArgoCD
#   e2e/scripts/cluster.sh verify             # check cluster + ArgoCD health
#   e2e/scripts/cluster.sh teardown           # delete Kind cluster
#   e2e/scripts/cluster.sh setup --name foo   # custom cluster name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"

E2E_DIR="${REPO_ROOT}/e2e"

# --- Config ---
CLUSTER_NAME="chain-node-e2e"
ARGOCD_CHART_VERSION="9.4.17"
ARGOCD_NAMESPACE="argocd"
E2E_KUBECONFIG="${E2E_DIR}/.kubeconfig"
ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-admin}"

# --- Parse command ---
COMMAND="${1:-}"
shift 2>/dev/null || true

# --- Parse flags ---
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

export KUBECONFIG="${E2E_KUBECONFIG}"

# ============================================================
# Helper functions
# ============================================================

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if eval "$*" &>/dev/null; then
        echo "  [PASS] ${label}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${label}"
        FAIL=$((FAIL + 1))
    fi
}

# ============================================================
# Commands
# ============================================================

cmd_setup() {
    require_cmd kind
    require_cmd helm
    require_cmd kubectl
    require_cmd htpasswd

    echo ""
    echo "=== Cluster Setup ==="
    echo "  Cluster : ${CLUSTER_NAME}"
    echo "  Config  : ${E2E_KUBECONFIG}"
    echo ""

    # --- Kind cluster ---
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "[1/5] Kind cluster '${CLUSTER_NAME}' already exists. Skipping."
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
    kubectl wait --for=condition=Ready pods \
        --field-selector=status.phase=Running \
        -n "${ARGOCD_NAMESPACE}" \
        --timeout=300s
    echo "[4/5] Done."

    echo "[5/5] Cleaning up..."
    kubectl delete secret argocd-initial-admin-secret -n "${ARGOCD_NAMESPACE}" 2>/dev/null || true
    echo "[5/5] Done."

    # Verify
    echo ""
    echo "Running verification..."
    cmd_verify

    echo ""
    echo "==========================================="
    echo "  Cluster ready"
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
    echo "  Next step    : e2e/scripts/ethereum.sh deploy"
    echo "  Teardown     : e2e/scripts/cluster.sh teardown"
    echo "==========================================="
}

cmd_verify() {
    PASS=0
    FAIL=0

    echo ""
    echo "=== Cluster Verification ==="
    echo ""

    # Cluster
    echo "Cluster:"
    check "Kind cluster exists" "kind get clusters 2>/dev/null | grep -q '^${CLUSTER_NAME}$'"
    check "Kubeconfig valid" "kubectl cluster-info"
    check "Nodes ready" "kubectl wait --for=condition=Ready nodes --all --timeout=10s"

    # ArgoCD
    echo ""
    echo "ArgoCD:"
    check "Namespace exists" "kubectl get namespace ${ARGOCD_NAMESPACE}"
    check "Server running" "kubectl get deploy argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
    check "Repo server running" "kubectl get deploy argocd-repo-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
    check "Controller running" "kubectl get statefulset argocd-application-controller -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
    check "Redis running" "kubectl get deploy argocd-redis -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
    check "Server version" "kubectl exec deploy/argocd-server -n ${ARGOCD_NAMESPACE} -- argocd-server version"

    # Summary
    echo ""
    echo "-------------------------------------------"
    echo "  Result: ${PASS} passed, ${FAIL} failed"
    echo "-------------------------------------------"

    if [[ ${FAIL} -gt 0 ]]; then
        return 1
    fi
}

cmd_teardown() {
    require_cmd kind

    echo ""
    echo "=== Cluster Teardown ==="
    echo ""

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "[1/2] Deleting Kind cluster '${CLUSTER_NAME}'..."
        kind delete cluster --name "${CLUSTER_NAME}"
        echo "[1/2] Done."
    else
        echo "[1/2] Cluster '${CLUSTER_NAME}' does not exist. Skipping."
    fi

    if [[ -f "${E2E_KUBECONFIG}" ]]; then
        rm -f "${E2E_KUBECONFIG}"
        echo "[2/2] Removed ${E2E_KUBECONFIG}"
    else
        echo "[2/2] Kubeconfig not found. Skipping."
    fi

    echo ""
    echo "Cluster teardown complete."
}

# ============================================================
# Main
# ============================================================

case "${COMMAND}" in
    setup)
        cmd_setup
        ;;
    verify)
        cmd_verify
        ;;
    teardown)
        cmd_teardown
        ;;
    *)
        echo "Usage: $0 {setup|verify|teardown} [--name <cluster-name>]"
        echo ""
        echo "Commands:"
        echo "  setup      Create Kind cluster and install ArgoCD"
        echo "  verify     Check cluster and ArgoCD health"
        echo "  teardown   Delete Kind cluster and kubeconfig"
        exit 1
        ;;
esac
