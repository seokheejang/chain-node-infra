#!/usr/bin/env bash
# Ethereum EL-CL-VC (geth + lighthouse + validator) e2e test runner.
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
VALIDATOR_RELEASE="validator-e2e"
JWT_SECRET_NAME="ethereum-jwt"
E2E_KUBECONFIG="${E2E_DIR}/.kubeconfig"
GETH_INGRESS_HOST="geth-rpc.127.0.0.1.nip.io"
LIGHTHOUSE_INGRESS_HOST="lighthouse-api.127.0.0.1.nip.io"

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
    echo "=== Deploy Ethereum EL-CL-VC ==="
    echo "  Namespace  : ${NAMESPACE}"
    echo "  Geth       : ${GETH_RELEASE}"
    echo "  Lighthouse : ${LIGHTHOUSE_RELEASE}"
    echo "  Validator  : ${VALIDATOR_RELEASE}"
    echo ""

    # [1/6] Namespace + JWT Secret
    echo "[1/6] Creating namespace and JWT secret..."
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
    echo "[1/6] Done."

    # [2/6] Build dependencies
    echo "[2/6] Building chart dependencies..."
    helm dependency build "${REPO_ROOT}/charts/genesis-generator" --skip-refresh 2>/dev/null
    helm dependency build "${REPO_ROOT}/charts/geth" --skip-refresh 2>/dev/null
    helm dependency build "${REPO_ROOT}/charts/lighthouse" --skip-refresh 2>/dev/null
    helm dependency build "${REPO_ROOT}/charts/lighthouse-validator" --skip-refresh 2>/dev/null
    echo "[2/6] Done."

    # [3/6] Genesis generator (HTTP server)
    echo "[3/6] Deploying genesis-generator (${GENESIS_RELEASE})..."
    helm upgrade --install "${GENESIS_RELEASE}" "${REPO_ROOT}/charts/genesis-generator" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        -f "${E2E_DIR}/values/genesis-generator.yaml" \
        --timeout 5m \
        --wait
    echo "[3/6] Done. Genesis serving at ${GENESIS_RELEASE}-genesis-generator:8000"

    # [4/6] Deploy geth (EL)
    echo "[4/6] Deploying geth (${GETH_RELEASE})..."
    helm upgrade --install "${GETH_RELEASE}" "${REPO_ROOT}/charts/geth" \
        --namespace "${NAMESPACE}" \
        -f "${E2E_DIR}/values/geth.yaml" \
        --timeout 5m \
        --wait
    echo "[4/6] Done."

    # [5/6] Deploy lighthouse (CL)
    echo "[5/6] Deploying lighthouse (${LIGHTHOUSE_RELEASE})..."
    helm upgrade --install "${LIGHTHOUSE_RELEASE}" "${REPO_ROOT}/charts/lighthouse" \
        --namespace "${NAMESPACE}" \
        -f "${E2E_DIR}/values/lighthouse.yaml" \
        --timeout 5m \
        --wait
    echo "[5/6] Done."

    # [6/6] Deploy lighthouse-validator (VC)
    echo "[6/6] Deploying lighthouse-validator (${VALIDATOR_RELEASE})..."
    helm upgrade --install "${VALIDATOR_RELEASE}" "${REPO_ROOT}/charts/lighthouse-validator" \
        --namespace "${NAMESPACE}" \
        -f "${E2E_DIR}/values/lighthouse-validator.yaml" \
        --timeout 5m \
        --wait
    echo "[6/6] Done."

    # Verify
    echo ""
    echo "Running verification..."
    cmd_verify

    echo ""
    echo "==========================================="
    echo "  Ethereum EL-CL-VC deployment ready"
    echo "==========================================="
    echo ""
    echo "  Namespace    : ${NAMESPACE}"
    echo "  Geth RPC     : http://${GETH_INGRESS_HOST}"
    echo "  Lighthouse   : http://${LIGHTHOUSE_INGRESS_HOST}"
    echo "  Validator    : ${VALIDATOR_RELEASE}"
    echo ""
    echo "  Teardown     : e2e/scripts/ethereum.sh teardown"
    echo "==========================================="
}

cmd_verify() {
    require_cmd kubectl
    require_cmd curl
    preflight

    PASS=0
    FAIL=0

    echo ""
    echo "=== Ethereum EL-CL-VC Verification ==="
    echo ""

    # Pod Readiness
    echo "Pod Readiness:"
    check "Geth pod ready" \
        "kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=${GETH_RELEASE} -n ${NAMESPACE} --timeout=10s"
    check "Lighthouse pod ready" \
        "kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=${LIGHTHOUSE_RELEASE} -n ${NAMESPACE} --timeout=10s"
    check "Validator pod ready" \
        "kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=${VALIDATOR_RELEASE} -n ${NAMESPACE} --timeout=10s"

    # Ingress Readiness
    echo ""
    echo "Ingress:"
    check "Geth ingress exists" \
        "kubectl get ingress ${GETH_RELEASE} -n ${NAMESPACE}"
    check "Lighthouse ingress exists" \
        "kubectl get ingress ${LIGHTHOUSE_RELEASE} -n ${NAMESPACE}"

    # Geth Health (via ingress)
    echo ""
    echo "Geth (EL) via ingress (${GETH_INGRESS_HOST}):"
    wait_for "RPC responds (eth_syncing)" 60 \
        "curl -sf -X POST -H 'Content-Type: application/json' \
            --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' \
            http://${GETH_INGRESS_HOST}"

    wait_for "eth_blockNumber responds" 30 \
        "curl -sf -X POST -H 'Content-Type: application/json' \
            --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
            http://${GETH_INGRESS_HOST}"

    # Lighthouse Health (via ingress)
    echo ""
    echo "Lighthouse (CL) via ingress (${LIGHTHOUSE_INGRESS_HOST}):"
    wait_for "Beacon API responds (/lighthouse/health)" 60 \
        "curl -sf http://${LIGHTHOUSE_INGRESS_HOST}/lighthouse/health"

    # EL-CL Connection
    echo ""
    echo "EL-CL Communication:"
    wait_for "Engine API connected (el_offline=false)" 90 \
        "curl -sf http://${LIGHTHOUSE_INGRESS_HOST}/eth/v1/node/syncing | grep -q '\"el_offline\":false'"

    # Block Production
    echo ""
    echo "Block Production (Validator):"
    wait_for "Block number > 3 (validator producing blocks)" 180 \
        "curl -sf -X POST -H 'Content-Type: application/json' \
            --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
            http://${GETH_INGRESS_HOST} \
            | python3 -c 'import sys,json; r=json.load(sys.stdin); sys.exit(0 if int(r[\"result\"],16)>3 else 1)'"

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
        echo "    kubectl logs sts/${VALIDATOR_RELEASE} -n ${NAMESPACE} --tail=50"
        echo "    kubectl get pods -n ${NAMESPACE}"
        echo "    kubectl get ingress -n ${NAMESPACE}"
        return 1
    fi
}

cmd_teardown() {
    require_cmd helm
    require_cmd kubectl
    preflight

    echo ""
    echo "=== Teardown Ethereum EL-CL-VC ==="
    echo ""

    echo "[1/6] Uninstalling lighthouse-validator (${VALIDATOR_RELEASE})..."
    helm uninstall "${VALIDATOR_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[2/6] Uninstalling lighthouse (${LIGHTHOUSE_RELEASE})..."
    helm uninstall "${LIGHTHOUSE_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[3/6] Uninstalling geth (${GETH_RELEASE})..."
    helm uninstall "${GETH_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[4/6] Uninstalling genesis-generator (${GENESIS_RELEASE})..."
    helm uninstall "${GENESIS_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[5/6] Deleting PVCs (StatefulSet data)..."
    kubectl delete pvc --all --namespace "${NAMESPACE}" 2>/dev/null || echo "  (not found, skipping)"

    echo "[6/6] Deleting namespace (${NAMESPACE})..."
    kubectl delete namespace "${NAMESPACE}" --wait=false 2>/dev/null || echo "  (not found, skipping)"

    echo ""
    echo "Ethereum EL-CL-VC teardown complete."
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
        echo "  deploy     Deploy geth (EL) + lighthouse (CL) + validator (VC) with JWT"
        echo "  verify     Check pod health, EL-CL connection, and block production"
        echo "  teardown   Uninstall releases and delete namespace"
        exit 1
        ;;
esac
