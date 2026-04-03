#!/usr/bin/env bash
# Verify e2e environment health.
# Can be run standalone or called from setup.sh.
#
# Usage:
#   e2e/scripts/verify.sh
#   e2e/scripts/verify.sh --name foo   # custom cluster name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="chain-node-e2e"
E2E_KUBECONFIG="${E2E_DIR}/.kubeconfig"
ARGOCD_NAMESPACE="argocd"

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

echo ""
echo "=== e2e Verification ==="
echo ""

# --- Cluster ---
echo "Cluster:"
check "Kind cluster exists" "kind get clusters 2>/dev/null | grep -q '^${CLUSTER_NAME}$'"
check "Kubeconfig valid" "kubectl cluster-info"
check "Nodes ready" "kubectl wait --for=condition=Ready nodes --all --timeout=10s"

# --- ArgoCD ---
echo ""
echo "ArgoCD:"
check "Namespace exists" "kubectl get namespace ${ARGOCD_NAMESPACE}"
check "Server running" "kubectl get deploy argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
check "Repo server running" "kubectl get deploy argocd-repo-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
check "Controller running" "kubectl get statefulset argocd-application-controller -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
check "Redis running" "kubectl get deploy argocd-redis -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
check "Server version" "kubectl exec deploy/argocd-server -n ${ARGOCD_NAMESPACE} -- argocd-server version"

# --- Summary ---
echo ""
echo "-------------------------------------------"
echo "  Result: ${PASS} passed, ${FAIL} failed"
echo "-------------------------------------------"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
