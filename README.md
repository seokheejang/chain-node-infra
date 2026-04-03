# chain-node-infra

Helm charts and ArgoCD manifests for managing blockchain node infrastructure on Kubernetes.

## Overview

This repository provides a GitOps-based approach to deploying and managing blockchain RPC nodes on Kubernetes using ArgoCD and Helm.

## Repository Structure

```
chain-node-infra/
├── charts/                  # Helm charts
│   ├── common/              # Shared library chart (naming, labels)
│   └── geth/                # Ethereum execution layer (go-ethereum)
├── argocd/                  # ArgoCD Application manifests
│   └── applications/        # Per-deployment Application specs
├── scripts/                 # CI/CD helper scripts
├── docs/                    # Operation guides & architecture
└── .github/workflows/       # GitHub Actions (lint, release)
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

```bash
# Ensure .envrc is loaded with a valid KUBECONFIG

# Update dependencies and render templates
helm dependency update charts/geth
helm template my-geth charts/geth

# Install to cluster
helm install my-geth charts/geth -n ethereum --create-namespace
```

### Deploy via ArgoCD

See [docs/task-01-argocd-installation.md](docs/task-01-argocd-installation.md) for ArgoCD setup instructions.

```bash
# Ensure ArgoCD is installed and .envrc is loaded
kubectl apply -f argocd/applications/geth.yaml
```

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
