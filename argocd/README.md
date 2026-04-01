# ArgoCD Applications

This directory contains ArgoCD Application manifests for deploying blockchain nodes.

## Structure

```
argocd/
└── applications/
    └── geth.yaml          # Ethereum geth RPC node
```

## Adding a New Application

1. Copy an existing Application manifest
2. Update `metadata.name`, `spec.source.path`, and `spec.destination.namespace`
3. Adjust inline `helm.values` for your deployment
4. Commit and push -- ArgoCD will auto-sync

## Naming Convention

Application names follow: `<client>-<role>`

Examples:
- `geth-rpc` - Ethereum geth RPC node
- `lighthouse-beacon` - Ethereum Lighthouse beacon node
- `bor-rpc` - Polygon bor RPC node
