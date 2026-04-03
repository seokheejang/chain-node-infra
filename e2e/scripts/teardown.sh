#!/usr/bin/env bash
# Tear down the local e2e test environment.
# Removes the Kind cluster and cleans up e2e/.kubeconfig.
#
# Usage:
#   e2e/scripts/teardown.sh              # delete default cluster
#   e2e/scripts/teardown.sh --name foo   # delete custom cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="chain-node-e2e"
E2E_KUBECONFIG="${E2E_DIR}/.kubeconfig"

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

if ! command -v kind &>/dev/null; then
    echo "[error] 'kind' is required but not installed."
    exit 1
fi

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "[step] Deleting Kind cluster '${CLUSTER_NAME}'..."
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "[done] Cluster deleted."
else
    echo "[info] Cluster '${CLUSTER_NAME}' does not exist."
fi

if [[ -f "${E2E_KUBECONFIG}" ]]; then
    rm -f "${E2E_KUBECONFIG}"
    echo "[done] Removed ${E2E_KUBECONFIG}"
fi
