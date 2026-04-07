#!/usr/bin/env bash
# Generate a JWT secret for EL-CL Engine API communication.
# Outputs a Kubernetes Secret manifest to stdout.
#
# Usage:
#   ./scripts/generate-jwt-secret.sh                          # dry-run (stdout)
#   ./scripts/generate-jwt-secret.sh | kubectl apply -f -     # apply directly
#   ./scripts/generate-jwt-secret.sh > jwt-secret.yaml        # save to file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_cmd openssl
require_cmd kubectl

NAMESPACE="${KUBE_NAMESPACE:-ethereum-private}"
SECRET_NAME="${1:-ethereum-jwt}"

JWT_HEX=$(openssl rand -hex 32)

echo "[info] Generated JWT secret for namespace '${NAMESPACE}'" >&2
echo "[info] Secret name: ${SECRET_NAME}" >&2
echo "[info] Pipe to 'kubectl apply -f -' to create the secret" >&2

kubectl create secret generic "${SECRET_NAME}" \
  --from-literal=jwt.hex="${JWT_HEX}" \
  --namespace "${NAMESPACE}" \
  --dry-run=client -o yaml
