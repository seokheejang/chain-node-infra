---
title: Geth 버전과 하드포크 활성화의 호환성
date: 2026-04-09
category: tooling
related: charts/geth/values.yaml, environments/*/genesis-generator.yaml
---

## 컨텍스트

`ELECTRA_FORK_EPOCH`을 `max`(비활성)에서 `0`(genesis부터 활성)으로 변경한 후 chain이 진행되지 않음:

```
geth: WARN Forkchoice requested unknown head
lighthouse: WARN Not ready Bellatrix - execution endpoint not yet synced
validator: ERROR PayloadIdUnavailable
```

geth는 v1.14.12, lighthouse는 v8.1.3 (Electra 지원). 즉, **EL이 Electra(Pectra)를 모르는데 CL이 Electra 블록을 요청**하는 상황.

## 내용

**Geth 하드포크 지원 매트릭스 (2026 시점):**

| Fork | Geth 최소 버전 | 활성화 시기 (mainnet) |
|------|---------------|---------------------|
| Shanghai (Capella) | v1.11+ | 2023 |
| Cancun (Deneb) | v1.13+ | 2024 |
| **Prague (Electra/Pectra)** | **v1.15+** | **2025** |

`ELECTRA_FORK_EPOCH=0`을 설정하려면 geth가 Pectra를 지원해야 한다. v1.14.12는 Cancun까지만 지원하므로 genesis에 `pragueTime`이 있어도 인식하지 못하고 fork choice 에러 발생.

**규칙:** genesis-generator의 fork epoch와 geth/lighthouse 이미지 버전은 짝이 맞아야 한다.

| genesis fork 설정 | 필요한 geth 버전 |
|------------------|-----------------|
| Deneb까지 활성 | v1.13.x ~ v1.14.x |
| Electra 활성 | v1.15.x+ (권장 v1.17+) |

## 왜 중요한가

- ethpandaops genesis-generator는 이미지 버전과 무관하게 모든 fork epoch를 설정 가능
- "값을 바꿨는데 안 동작" 류의 디버깅에서 이미지 버전 호환성을 가장 마지막에 의심하게 됨
- fork 활성화는 클라이언트 버전 업그레이드와 한 세트로 PR 처리해야 함
- 메인넷 패리티를 유지하려면 geth/lighthouse 양쪽 모두 최신 stable로 정기 업데이트 필요
