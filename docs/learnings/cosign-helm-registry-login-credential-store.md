---
title: helm registry login과 cosign의 credential store 불일치
date: 2026-04-10
category: ci/cd
related: .github/workflows/release.yaml
---

## 컨텍스트

Cosign keyless signing을 GHCR publish workflow에 추가한 뒤 첫 release run(`geth-0.1.1`)에서 마지막 단계가 실패:

```
tlog entry created with index: 1271222484
Pushing signature to: ghcr.io/seokheejang/chain-node-infra/geth
Error: signing [ghcr.io/seokheejang/chain-node-infra/geth@sha256:...]:
  signing digest: POST https://ghcr.io/v2/.../blobs/uploads/:
  UNAUTHORIZED: unauthenticated: User cannot be authenticated with the token provided.
```

특이한 점: `helm push`는 성공하고, Fulcio 인증서 발급 + Rekor tlog entry 생성도 전부 성공. **오직 서명 artifact를 OCI 레지스트리에 push하는 마지막 단계만 401.**

## 원인

`helm registry login`과 `cosign`이 **서로 다른 credential store**를 사용한다.

| 도구 | credential 저장 위치 |
|---|---|
| `helm registry login` | `${XDG_CONFIG_HOME}/helm/registry/config.json` (helm-private) |
| `cosign` | `~/.docker/config.json` 또는 `$DOCKER_CONFIG` |
| `helm v3 OCI push` | 자체 store 우선, **없으면 `~/.docker/config.json` fallback** |

workflow가 `helm registry login`만 수행했기 때문에:

- `helm push`는 helm-private store에서 credential을 찾아 성공
- `cosign sign`은 `~/.docker/config.json`을 보는데 거기엔 credential이 없어 anonymous로 push 시도 → GHCR이 401

## 해결

`helm registry login`을 `docker/login-action@v3`으로 교체. 이 action은 `~/.docker/config.json`에 credential을 기록하므로 **cosign과 helm v3 OCI(fallback 경로) 둘 다** 동일 credential을 공유한다.

```yaml
- name: Log in to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

## 교훈

- OCI 레지스트리에 여러 도구(helm, cosign, oras, crane 등)를 함께 쓸 때는 **공통 credential store인 `~/.docker/config.json`을 기준**으로 통일해야 한다.
- `helm registry login`은 해당 shell 안에서 helm만 쓸 때 편리한 단축키지만, 다른 OCI 도구와 협업해야 하면 함정.
- `docker/login-action@v3`은 docker가 설치되어 있지 않아도 동작한다 — 실제로 하는 일은 `~/.docker/config.json`에 base64 토큰을 기록하는 것뿐.
- 첫 failure의 희생양: `geth:0.1.1`이 unsigned 상태로 GHCR에 남음. OCI immutability 때문에 사후 서명 불가 — release 파이프라인에 서명을 끼워 넣을 때는 **별도 브랜치에서 dry-run / sandbox 레지스트리로 먼저 검증**하는 게 안전.
