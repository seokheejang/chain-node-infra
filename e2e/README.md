# E2E Testing

End-to-end test infrastructure for chain-node-infra Helm charts.

## Prerequisites

- [Docker](https://www.docker.com/) (running)
- [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker)
- [helm](https://helm.sh/) (v3.x)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- `htpasswd` (from Apache utils, for ArgoCD admin password)
- `openssl` (for JWT secret generation)
- `curl` (for API verification)

## Quick Start

```bash
# 1. Create Kind cluster + install ArgoCD
e2e/scripts/cluster.sh setup

# 2. Deploy Ethereum EL-CL (geth + lighthouse) and run verification
e2e/scripts/ethereum.sh deploy

# 3. Tear down Ethereum deployment
e2e/scripts/ethereum.sh teardown

# 4. Delete Kind cluster
e2e/scripts/cluster.sh teardown
```

## Scripts

### `cluster.sh` — Infrastructure Management

| Command | Description |
|---------|-------------|
| `cluster.sh setup` | Create Kind cluster, install ArgoCD |
| `cluster.sh verify` | Check cluster nodes + ArgoCD health |
| `cluster.sh teardown` | Delete Kind cluster + kubeconfig |

Options: `--name <cluster-name>` (default: `chain-node-e2e`)

### `ethereum.sh` — Ethereum EL-CL Testing

| Command | Description |
|---------|-------------|
| `ethereum.sh deploy` | Create JWT, deploy geth (EL) + lighthouse (CL) |
| `ethereum.sh verify` | Check pod health, RPC, Beacon API, EL-CL connection |
| `ethereum.sh teardown` | Uninstall Helm releases, delete namespace |

Options: `--namespace <ns>` (default: `ethereum-e2e`)

#### Verification Checks

| Check | Method | Timeout |
|-------|--------|---------|
| Geth pod Ready | `kubectl wait` | 10s |
| Lighthouse pod Ready | `kubectl wait` | 10s |
| Geth RPC responds | `curl eth_syncing` | 30s |
| Lighthouse API responds | `curl /lighthouse/health` | 30s |
| EL-CL Engine API connected | `curl /eth/v1/node/syncing` → `el_offline: false` | 90s |

## Directory Structure

```
e2e/
├── README.md
├── kind/
│   └── cluster.yaml          # Kind cluster node config
├── argocd/
│   └── values.yaml           # Minimal ArgoCD values for e2e
├── values/
│   ├── geth.yaml             # Lightweight geth values for Kind
│   └── lighthouse.yaml       # Lightweight lighthouse values for Kind
└── scripts/
    ├── cluster.sh             # Kind + ArgoCD lifecycle
    └── ethereum.sh            # Ethereum EL-CL lifecycle
```

## Adding New Chains

To add e2e tests for a new chain (e.g., Polygon):

1. Create `e2e/values/<client>.yaml` for each chart
2. Create `e2e/scripts/polygon.sh` following the `ethereum.sh` pattern
3. Implement `deploy`, `verify`, and `teardown` commands

## Notes

- Kubeconfig is stored at `e2e/.kubeconfig` (gitignored, never touches `~/.kube/config`)
- E2E values use minimal resources to fit in Kind (4 CPU / 6 GB shared with ArgoCD)
- Block production is not verified (requires validator client, out of scope)
- Verification uses `port-forward` to access services from the host
