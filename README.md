# chain-node-infra

Helm charts and ArgoCD manifests for managing blockchain node infrastructure on Kubernetes.

## Overview

This repository provides a GitOps-based approach to deploying and managing blockchain RPC nodes on Kubernetes using ArgoCD and Helm. It includes a complete Ethereum private devnet stack (EL + CL + Validator + Genesis) for contract development.

## Repository Structure

```
chain-node-infra/
├── charts/                       # Helm charts
│   ├── common/                   # Shared library chart (naming, labels)
│   ├── genesis-generator/        # Ethereum genesis generator (ethpandaops)
│   ├── geth/                     # Execution layer (go-ethereum v1.17.2)
│   ├── lighthouse/               # Consensus layer (sigp/lighthouse v8.1.3)
│   └── lighthouse-validator/     # Validator client
├── environments/                 # Per-environment value overrides
│   ├── mainnet/
│   ├── testnet/sepolia/
│   └── private/                  # Private devnet (Pectra-enabled)
├── argocd/                       # ArgoCD Application manifests
│   └── applications/             # Per-deployment Application specs
├── e2e/                          # End-to-end test infrastructure
│   ├── kind/cluster.yaml         # Kind cluster config (with nginx-ingress)
│   ├── scripts/                  # cluster.sh, ethereum.sh
│   └── values/                   # E2E test values
├── scripts/                      # CI/CD helper scripts
├── docs/                         # Operation guides & architecture
│   ├── archive/                  # Completed task documents
│   └── learnings/                # Patterns, gotchas, decisions
└── .github/workflows/            # GitHub Actions (lint, release)
```

## Quick Start

### Prerequisites

- [Helm 3.x](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [direnv](https://direnv.net/) (recommended) or source `.envrc` manually

### Environment Setup

```bash
# 1. Copy the environment template
cp .envrc.example .envrc

# 2. Edit .envrc — set KUBECONFIG to your kubeconfig path
#    e.g.: export KUBECONFIG="${HOME}/.kube/config"

# 3. Load environment variables
direnv allow       # with direnv (auto-loads on cd / new terminal)
source .envrc      # without direnv

# 4. Verify cluster connectivity
kubectl cluster-info
```

### Local Development (no cluster required)

```bash
# Lint all changed charts
make lint

# Render templates for a specific chart
make template CHART=geth

# Generate chart documentation
make docs
```

### Deploy to Cluster

Recommended: install from GHCR (no clone needed). For local development against a working tree, use the local source path instead.

```bash
# Ensure .envrc is loaded with a valid KUBECONFIG

# From GHCR (recommended)
helm install my-geth oci://ghcr.io/seokheejang/chain-node-infra/geth \
  --version 0.1.0 \
  -n ethereum --create-namespace \
  -f my-values.yaml

# From local source (for chart development)
helm dependency update charts/geth
helm install my-geth charts/geth -n ethereum --create-namespace
```

### Deploy via ArgoCD

See [docs/archive/task-01-argocd-installation.md](docs/archive/task-01-argocd-installation.md) for ArgoCD setup instructions.

```bash
# Ensure ArgoCD is installed and .envrc is loaded
kubectl apply -f argocd/applications/geth.yaml
```

The example Application manifests in [argocd/applications/](argocd/applications/) use the multi-source pattern: chart from GHCR (immutable version pin), values from this repo via `$values` ref. See [Use in Other Projects](#use-in-other-projects) for the full pattern.

## Use in Other Projects

All charts are published to **GitHub Container Registry (GHCR)** as OCI artifacts on every per-chart semver tag. Public, no authentication required.

**Available charts** (all at `0.1.0`):

```
oci://ghcr.io/seokheejang/chain-node-infra/geth
oci://ghcr.io/seokheejang/chain-node-infra/lighthouse
oci://ghcr.io/seokheejang/chain-node-infra/lighthouse-validator
oci://ghcr.io/seokheejang/chain-node-infra/genesis-generator
oci://ghcr.io/seokheejang/chain-node-infra/common               # library, dependency only
```

### Pattern 1: helm CLI (any consumer)

```bash
helm pull oci://ghcr.io/seokheejang/chain-node-infra/geth --version 0.1.0
helm template test oci://ghcr.io/seokheejang/chain-node-infra/geth --version 0.1.0 -f my-values.yaml
helm install my-geth oci://ghcr.io/seokheejang/chain-node-infra/geth \
  --version 0.1.0 -n ethereum --create-namespace -f my-values.yaml
```

### Pattern 2: ArgoCD multi-source (recommended for production)

Keep your private repo free of chart code — store only the Application manifest and values:

```
your-private-infra/
├── argocd/applications/geth-mainnet.yaml
└── values/geth-mainnet.yaml         # your environment-specific overrides
```

`geth-mainnet.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: geth-mainnet
  namespace: argocd
spec:
  project: default
  sources:
    # Chart from GHCR — immutable version pin
    - repoURL: ghcr.io/seokheejang/chain-node-infra
      chart: geth
      targetRevision: 0.1.0
      helm:
        valueFiles:
          - $values/values/geth-mainnet.yaml
    # Values from your own repo — mounted as $values
    - repoURL: git@github.com:your-org/your-private-infra.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: ethereum
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

ArgoCD ≥ 2.7 supports OCI Helm sources natively. Upgrade = bump `targetRevision` only.

### Pattern 3: Internal registry mirroring (production hardening)

For air-gapped or supply-chain-sensitive environments, mirror to your internal registry (ECR / Harbor / Nexus / GitLab) so production never depends on external GHCR availability:

```bash
# Using oras (https://oras.land)
oras copy \
  ghcr.io/seokheejang/chain-node-infra/geth:0.1.0 \
  <internal-registry>/helm/chain-node-infra/geth:0.1.0
```

Then point your ArgoCD `repoURL` at the internal registry.

### Releasing a new version (maintainer)

Releases are tag-triggered. To publish a new chart version:

```bash
# 1. Bump version in Chart.yaml
vim charts/geth/Chart.yaml          # version: 0.1.0 → 0.1.1
git commit -am "chore(geth): bump to 0.1.1" && git push

# 2. Push the per-chart tag
git tag geth-0.1.1
git push origin geth-0.1.1
```

The [Release Charts workflow](.github/workflows/release.yaml) packages all charts and pushes only versions not yet on GHCR (idempotent). Tag convention: `<chart-name>-<semver>`.

## Private Devnet (Local Development)

Run a complete Ethereum devnet (EL + CL + Validator) on a local Kind cluster, accessible via nginx-ingress.

### Features

- **Latest hardforks**: Pectra (Electra) enabled at genesis
- **30 prefunded EOAs**: derived from the standard test mnemonic — see [docs/eth-devnet-premine-accounts.md](docs/eth-devnet-premine-accounts.md)
- **MetaMask/Foundry/Hardhat ready**: CORS enabled, full RPC API namespaces (`eth, net, web3, debug, txpool, admin`)
- **Mainnet-parity**: same gas limit (60M), same opcodes, same precompiles
- **Chain ID**: `3238200`

### Quick Start

```bash
# 1. Create Kind cluster + ArgoCD + nginx-ingress
e2e/scripts/cluster.sh setup

# 2. Deploy Ethereum stack (genesis-generator → geth → lighthouse → validator)
e2e/scripts/ethereum.sh deploy

# 3. Access via ingress
curl -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://geth-rpc.127.0.0.1.nip.io

# 4. Teardown (also deletes PVCs)
e2e/scripts/ethereum.sh teardown
```

### Endpoints

| Service | URL |
|---------|-----|
| Geth RPC (HTTP) | `http://geth-rpc.127.0.0.1.nip.io` |
| Lighthouse Beacon API | `http://lighthouse-api.127.0.0.1.nip.io` |
| ArgoCD UI | `http://localhost:8080` |

### Importing a Test Account

```bash
# First account (Hardhat/Foundry standard)
Address:     0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
Balance:     1,000,000,000 ETH
```

See [docs/eth-devnet-premine-accounts.md](docs/eth-devnet-premine-accounts.md) for all 30 accounts.

## Adding a New Chart

1. Create `charts/<client-name>/` with Chart.yaml, values.yaml, and templates/
2. Add `common` as a dependency in Chart.yaml
3. Create `ci/default-values.yaml` for chart-testing
4. Create `argocd/applications/<client-name>.yaml`
5. Run `make lint` to validate

## References

### Chart Structure & Implementation

- [ethpandaops/ethereum-helm-charts](https://github.com/ethpandaops/ethereum-helm-charts) - Ethereum client Helm charts (geth, lighthouse, prysm, etc.)
- [dysnix/charts](https://github.com/dysnix/charts) - Multi-chain Helm charts (geth, bsc, solana, arbitrum)
- [graphops/launchpad-charts](https://github.com/graphops/launchpad-charts) - Blockchain node Helm charts with monitoring & proxyd

### Documentation & Architecture

- [hyperledger-bevel/bevel](https://github.com/hyperledger-bevel/bevel) - Multi-platform DLT deployment framework (Ansible + Helm + GitOps)

### GitOps Patterns

- [argoproj/argocd-example-apps](https://github.com/argoproj/argocd-example-apps) - Official ArgoCD example patterns
- [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) - GitOps directory structure reference

### Helm Chart Patterns

- [bitnami/charts](https://github.com/bitnami/charts) - Helm monorepo & common library chart reference
- [prometheus-community/helm-charts](https://github.com/prometheus-community/helm-charts) - Community Helm chart CI/CD patterns

### Blockchain Node Operators (Alternative Approaches)

- [kotalco/kotal](https://github.com/kotalco/kotal) - K8s Operator for multi-chain blockchain nodes
- [paritytech/helm-charts](https://github.com/paritytech/helm-charts) - Substrate/Polkadot Helm charts with common library pattern

## License

[MIT](LICENSE)
