# Getting Started

## Prerequisites

- [Helm 3.x](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured for your cluster
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/getting_started/) installed on the cluster

## Deploy Your First Node

### Option 1: Direct Helm Install

```bash
# Clone the repository
git clone https://github.com/seokheejang/chain-node-infra.git
cd chain-node-infra

# Update chart dependencies
helm dependency update charts/geth

# Preview the rendered templates
helm template my-geth charts/geth

# Install to your cluster
helm install my-geth charts/geth \
  --namespace ethereum \
  --create-namespace \
  --set config.network=sepolia \
  --set persistence.size=50Gi
```

### Option 2: ArgoCD GitOps

```bash
# Apply the ArgoCD Application manifest
kubectl apply -f argocd/applications/geth.yaml

# Monitor the sync status
argocd app get geth-rpc
```

## Verify the Deployment

```bash
# Check pod status
kubectl get pods -n ethereum

# Check sync status via RPC
kubectl port-forward svc/my-geth 8545:8545 -n ethereum

curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545
```

## Customizing Values

Override default values by creating a custom values file:

```yaml
# my-values.yaml
config:
  network: sepolia
  syncMode: snap
  cache: 2048

persistence:
  size: 50Gi

resources:
  requests:
    cpu: "1"
    memory: 4Gi
```

```bash
helm install my-geth charts/geth -f my-values.yaml -n ethereum --create-namespace
```

## Next Steps

- Read [architecture.md](architecture.md) for repository design details
- Add more client charts under `charts/`
- Configure ArgoCD ApplicationSets for multi-chain deployments
