# CLAUDE.md - Project Conventions for chain-node-infra

## Project Overview

Helm charts and ArgoCD manifests for blockchain RPC node infrastructure on Kubernetes.
GitOps workflow: ArgoCD + Helm (no Kustomize).

**This is an open-source repository.** Anyone can clone and use it with their own cluster.
All documentation, scripts, and examples must be written for external users, not just the maintainer.

## Open-Source Execution Principles

- **Cluster access is the user's responsibility**: This repo never contains kubeconfig files, SSH keys, or cluster endpoints.
- **`.envrc.example` pattern**: Commit an env var template as `.envrc.example`. Users copy it to `.envrc` and customize. Works with direnv (auto-load on cd) or without (source manually). Scripts also source `.envrc` automatically.
- **Scripts must respect `$KUBECONFIG`**: Never hardcode kubeconfig paths. Helm and kubectl natively follow `$KUBECONFIG`.
- **Never write bare `kubectl apply -f ...` in docs**: Always state prerequisites (KUBECONFIG setup, namespace existence, etc.) or provide a script that handles them.
- **Deployment scripts live under `scripts/`**: Scripts source `.envrc` automatically. Users just configure `.envrc` and run the script.
- **Never commit real secrets, endpoints, or kubeconfig files into this repo.**

## Repository Structure

- `charts/` - Helm charts (flat listing per client, plus `common/` library chart)
- `argocd/` - ArgoCD Application manifests
- `scripts/` - CI/CD helper scripts
- `docs/` - Operation guides and architecture documentation
- `.github/workflows/` - GitHub Actions for lint, test, and release

## Chart Conventions

### Naming

- Chart directory names: lowercase, matching the client binary name (e.g., `geth`, `lighthouse`, `bor`)
- Chart names in `Chart.yaml` must match the directory name exactly
- Kubernetes resource names: `{{ include "<chart>.fullname" . }}`

### Chart Structure

Every chart under `charts/` must have:

- `Chart.yaml` - apiVersion: v2, type: application
- `values.yaml` - all configurable values with comments
- `templates/_helpers.tpl` - naming, labels, serviceaccount helpers (calls common library)
- `templates/` - Kubernetes manifests
- `ci/default-values.yaml` - values for chart-testing `ct lint`/`ct install`
- `.helmignore`

### Common Library Chart

- Located at `charts/common/`, type: library
- Provides shared helpers: naming conventions, standard labels
- Other charts declare it as a dependency in Chart.yaml
- Keep minimal: only add helpers when 3+ charts would benefit

### Values Conventions

- Use camelCase for value keys
- Group related values under a parent key (e.g., `persistence:`, `service:`)
- Every value must have a YAML comment explaining its purpose
- Default values should be safe for local/test environments
- Image tags should default to a specific version, never `latest`

## ArgoCD Conventions

- One Application manifest per deployment under `argocd/applications/`
- Application names follow: `<client>-<role>` (e.g., `geth-rpc`)
- Use Helm as the source type, pointing to `charts/` in this repo
- Value overrides inline in the Application spec

## Git Commit Security Policy

**Always perform a security review before every commit.**

- Review all staged changes with `git diff --staged`
- **NEVER commit** if any of the following are found:
  - Secrets, private keys, JWT tokens, API keys (patterns: `secret`, `password`, `token`, `apikey`, `private_key`)
  - Files: `.env`, `credentials.json`, `*.pem`, `*.key`
  - Hardcoded IP addresses, internal domains, or credentials
  - Base64-encoded secret data
- Values like `jwt.secret` and TLS certs in values.yaml must always be empty strings or placeholders
- ArgoCD Application manifests must not contain real cluster endpoints or credentials

## Language

- **English**: Code, comments, YAML values, commit messages, README.md, CLAUDE.md, and all finalized documentation.
- **Korean**: Task plans and work-in-progress documents (`docs/task-*.md`) — these are for the maintainer to review and make decisions.

## Commit Conventions

- Use Conventional Commits: `type(scope): description`
- Types: feat, fix, docs, chore, refactor, test, ci
- Scope: chart name or directory (e.g., `feat(geth): add readiness probe`)

## CI/CD

- **Every chart must pass `ct lint` and `ct install` before merge.** This is the primary verification gate — if it doesn't work in ct, it doesn't ship.
- `ct install` runs against a Kind cluster in CI (GitHub Actions). All charts must be testable in this environment without external dependencies (no real kubeconfig, no external clusters).
- Each chart's `ci/default-values.yaml` must contain values that allow successful installation in a Kind cluster.
- chart-releaser packages and publishes charts on merge to main.
- The `ci/` directory inside each chart is for ct test values only, NOT for environments.

## Development Commands

- `make lint` - run chart-testing lint via Docker
- `make docs` - regenerate chart READMEs via helm-docs
- `make template` - render chart templates locally
