#!/usr/bin/env bash
# Ethereum EL-CL (geth + lighthouse) e2e test runner.
# Prerequisite: e2e/scripts/setup.sh must have been run first.
#
# Usage:
#   e2e/scripts/ethereum.sh deploy              # deploy geth + lighthouse
#   e2e/scripts/ethereum.sh verify              # check health + EL-CL connection
#   e2e/scripts/ethereum.sh teardown            # uninstall + cleanup
#   e2e/scripts/ethereum.sh deploy --namespace my-ns

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"

E2E_DIR="${REPO_ROOT}/e2e"

# --- Config ---
NAMESPACE="ethereum-e2e"
GENESIS_RELEASE="genesis-e2e"
GETH_RELEASE="geth-e2e"
LIGHTHOUSE_RELEASE="lighthouse-e2e"
JWT_SECRET_NAME="ethereum-jwt"
E2E_KUBECONFIG="${E2E_DIR}/.kubeconfig"
GETH_LOCAL_PORT=18545
LIGHTHOUSE_LOCAL_PORT=15052

# --- Parse command ---
COMMAND="${1:-}"
shift 2>/dev/null || true

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
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
PIDS_TO_KILL=()

cleanup_pids() {
    for pid in "${PIDS_TO_KILL[@]}"; do
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    done
    PIDS_TO_KILL=()
}

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

wait_for() {
    local label="$1"
    local timeout="$2"
    shift 2
    local deadline=$((SECONDS + timeout))
    while [[ $SECONDS -lt $deadline ]]; do
        if eval "$*" &>/dev/null; then
            echo "  [PASS] ${label}"
            PASS=$((PASS + 1))
            return 0
        fi
        sleep 5
    done
    echo "  [FAIL] ${label} (timed out after ${timeout}s)"
    FAIL=$((FAIL + 1))
    return 1
}

preflight() {
    if [[ ! -f "${E2E_KUBECONFIG}" ]]; then
        echo "[error] Kubeconfig not found at ${E2E_KUBECONFIG}"
        echo "        Run e2e/scripts/setup.sh first."
        exit 1
    fi
    if ! kubectl cluster-info &>/dev/null; then
        echo "[error] Cannot connect to cluster. Is the Kind cluster running?"
        exit 1
    fi
}

# ============================================================
# Commands
# ============================================================

cmd_deploy() {
    require_cmd helm
    require_cmd kubectl
    require_cmd openssl
    preflight

    echo ""
    echo "=== Deploy Ethereum EL-CL ==="
    echo "  Namespace  : ${NAMESPACE}"
    echo "  Geth       : ${GETH_RELEASE}"
    echo "  Lighthouse : ${LIGHTHOUSE_RELEASE}"
    echo ""

    # [1/5] Namespace + JWT Secret
    echo "[1/5] Creating namespace and JWT secret..."
    # Wait if namespace is still terminating from previous teardown
    while kubectl get namespace "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Terminating; do
        echo "  Waiting for namespace ${NAMESPACE} to finish terminating..."
        sleep 3
    done
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    JWT_HEX=$(openssl rand -hex 32)
    kubectl create secret generic "${JWT_SECRET_NAME}" \
        --from-literal=jwt.hex="${JWT_HEX}" \
        --namespace "${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "[1/5] Done."

    # [2/5] Build dependencies
    echo "[2/5] Building chart dependencies..."
    helm dependency build "${REPO_ROOT}/charts/genesis-generator" --skip-refresh 2>/dev/null
    helm dependency build "${REPO_ROOT}/charts/geth" --skip-refresh 2>/dev/null
    helm dependency build "${REPO_ROOT}/charts/lighthouse" --skip-refresh 2>/dev/null
    echo "[2/5] Done."

    # [3/5] Genesis generator (HTTP server)
    echo "[3/5] Deploying genesis-generator (${GENESIS_RELEASE})..."
    helm upgrade --install "${GENESIS_RELEASE}" "${REPO_ROOT}/charts/genesis-generator" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        -f "${E2E_DIR}/values/genesis-generator.yaml" \
        --timeout 5m \
        --wait
    echo "[3/5] Done. Genesis serving at ${GENESIS_RELEASE}-genesis-generator:8000"

    # [4/5] Deploy geth (EL)
    echo "[4/5] Deploying geth (${GETH_RELEASE})..."
    helm upgrade --install "${GETH_RELEASE}" "${REPO_ROOT}/charts/geth" \
        --namespace "${NAMESPACE}" \
        -f "${E2E_DIR}/values/geth.yaml" \
        --timeout 5m \
        --wait
    echo "[4/5] Done."

    # [5/5] Deploy lighthouse (CL)
    echo "[5/5] Deploying lighthouse (${LIGHTHOUSE_RELEASE})..."
    helm upgrade --install "${LIGHTHOUSE_RELEASE}" "${REPO_ROOT}/charts/lighthouse" \
        --namespace "${NAMESPACE}" \
        -f "${E2E_DIR}/values/lighthouse.yaml" \
        --timeout 5m \
        --wait
    echo "[5/5] Done."

    # Verify
    echo ""
    echo "Running verification..."
    cmd_verify

    echo ""
    echo "==========================================="
    echo "  Ethereum EL-CL deployment ready"
    echo "==========================================="
    echo ""
    echo "  Namespace    : ${NAMESPACE}"
    echo "  Geth RPC     : kubectl port-forward svc/${GETH_RELEASE} 8545:8545 -n ${NAMESPACE}"
    echo "  Lighthouse   : kubectl port-forward svc/${LIGHTHOUSE_RELEASE} 5052:5052 -n ${NAMESPACE}"
    echo ""
    echo "  Teardown     : e2e/scripts/ethereum.sh teardown"
    echo "==========================================="
}

cmd_verify() {
    require_cmd kubectl
    require_cmd curl
    preflight
    trap cleanup_pids EXIT

    PASS=0
    FAIL=0

    echo ""
    echo "=== Ethereum EL-CL Verification ==="
    echo ""

    # Pod Readiness
    echo "Pod Readiness:"
    check "Geth pod ready" \
        "kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=${GETH_RELEASE} -n ${NAMESPACE} --timeout=10s"
    check "Lighthouse pod ready" \
        "kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=${LIGHTHOUSE_RELEASE} -n ${NAMESPACE} --timeout=10s"

    # Port Forwards
    echo ""
    echo "Starting port-forwards..."
    kubectl port-forward "svc/${GETH_RELEASE}" "${GETH_LOCAL_PORT}:8545" -n "${NAMESPACE}" &>/dev/null &
    PIDS_TO_KILL+=($!)
    kubectl port-forward "svc/${LIGHTHOUSE_RELEASE}" "${LIGHTHOUSE_LOCAL_PORT}:5052" -n "${NAMESPACE}" &>/dev/null &
    PIDS_TO_KILL+=($!)
    sleep 3

    # Geth Health
    echo ""
    echo "Geth (EL):"
    wait_for "RPC responds (eth_syncing)" 30 \
        "curl -sf -X POST -H 'Content-Type: application/json' \
            --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' \
            http://localhost:${GETH_LOCAL_PORT}"

    wait_for "eth_blockNumber responds" 30 \
        "curl -sf -X POST -H 'Content-Type: application/json' \
            --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
            http://localhost:${GETH_LOCAL_PORT}"

    # Lighthouse Health
    echo ""
    echo "Lighthouse (CL):"
    wait_for "Beacon API responds (/lighthouse/health)" 30 \
        "curl -sf http://localhost:${LIGHTHOUSE_LOCAL_PORT}/lighthouse/health"

    # EL-CL Connection
    echo ""
    echo "EL-CL Communication:"
    wait_for "Engine API connected (el_offline=false)" 90 \
        "curl -sf http://localhost:${LIGHTHOUSE_LOCAL_PORT}/eth/v1/node/syncing | grep -q '\"el_offline\":false'"

    # Cleanup port-forwards
    cleanup_pids
    trap - EXIT

    # Summary
    echo ""
    echo "-------------------------------------------"
    echo "  Result: ${PASS} passed, ${FAIL} failed"
    echo "-------------------------------------------"

    if [[ ${FAIL} -gt 0 ]]; then
        echo ""
        echo "  Debug commands:"
        echo "    kubectl logs sts/${GETH_RELEASE} -n ${NAMESPACE} --tail=50"
        echo "    kubectl logs sts/${LIGHTHOUSE_RELEASE} -n ${NAMESPACE} --tail=50"
        echo "    kubectl get pods -n ${NAMESPACE}"
        return 1
    fi
}

cmd_teardown() {
    require_cmd helm
    require_cmd kubectl
    preflight

    echo ""
    echo "=== Teardown Ethereum EL-CL ==="
    echo ""

    echo "[1/4] Uninstalling lighthouse (${LIGHTHOUSE_RELEASE})..."
    helm uninstall "${LIGHTHOUSE_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[2/4] Uninstalling geth (${GETH_RELEASE})..."
    helm uninstall "${GETH_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[3/4] Uninstalling genesis-generator (${GENESIS_RELEASE})..."
    helm uninstall "${GENESIS_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[4/4] Deleting namespace (${NAMESPACE})..."
    kubectl delete namespace "${NAMESPACE}" --wait=false 2>/dev/null || echo "  (not found, skipping)"

    echo ""
    echo "Ethereum EL-CL teardown complete."
    echo "To also delete the Kind cluster: e2e/scripts/cluster.sh teardown"
}

# ============================================================
# Main
# ============================================================

case "${COMMAND}" in
    deploy)
        cmd_deploy
        ;;
    verify)
        cmd_verify
        ;;
    teardown)
        cmd_teardown
        ;;
    *)
        echo "Usage: $0 {deploy|verify|teardown} [--namespace <ns>]"
        echo ""
        echo "Commands:"
        echo "  deploy     Deploy geth (EL) + lighthouse (CL) with JWT"
        echo "  verify     Check pod health and EL-CL Engine API connection"
        echo "  teardown   Uninstall releases and delete namespace"
        exit 1
        ;;
esac
