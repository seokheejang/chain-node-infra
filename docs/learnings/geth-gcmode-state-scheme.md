---
title: geth gcMode와 state.scheme는 반드시 쌍으로 설정해야 한다
date: 2026-04-09
category: architecture
related: charts/geth/templates/statefulset.yaml, charts/geth/values.yaml
---

## 컨텍스트

geth에 archive/pruned 모드를 추가하면서, gcMode와 state.scheme를 독립 파라미터로 할지 자동 유도할지 결정해야 했다.

## 내용

geth의 두 설정은 고정 쌍이다:

| gcMode | state.scheme | 용도 |
|--------|-------------|------|
| `full` | `path` | pruned 모드. 최근 상태만 유지, 작은 디스크 |
| `archive` | `hash` | archive 모드. 전체 히스토리컬 상태 보존, 큰 디스크 |

**잘못된 조합의 위험:**
- `archive` + `path`: 조용히 히스토리컬 상태를 저장하지 않음 (archive 의미 없음)
- `full` + `hash`: 불필요하게 느린 state 접근, 디스크 낭비

**설계 결정: state.scheme를 gcMode에서 자동 유도**

```yaml
# values.yaml — 사용자는 gcMode만 설정
config:
  gcMode: full    # or "archive"

# statefulset.yaml — state.scheme는 자동 결정
- --gcmode={{ .Values.config.gcMode }}
{{- if eq .Values.config.gcMode "archive" }}
- --state.scheme=hash
{{- else }}
- --state.scheme=path
{{- end }}
```

비표준 조합이 필요한 특수한 경우에는 `extraArgs`로 override 가능.

## 왜 중요한가

- 사용자가 두 설정의 관계를 몰라도 안전하게 동작
- 잘못된 조합은 에러 없이 조용히 실패하므로 (데이터 미보존), 자동화로 방지하는 것이 핵심
- geth v1.14+에서 path scheme이 기본이 되면서 이 쌍이 더욱 중요해짐

---

## 2026-04-17 — `geth init` 에도 동일한 --state.scheme 를 넘겨야 한다

**Category**: debugging
**Related**: [charts/geth/templates/statefulset.yaml](../../charts/geth/templates/statefulset.yaml)

### 컨텍스트

위 섹션의 자동 유도 로직을 `geth` main container에만 적용했더니, `gcMode: archive` 로 깔린 Pod이 first boot에서 Fatal로 죽음:

```
Fatal: incompatible state scheme, stored: path, provided: hash
```

`full` 모드에서는 init/main 둘 다 기본값인 `path` 로 떨어지면서 우연히 일치, 잠복.

### 내용

StatefulSet에는 초기화 단계가 둘이다:

1. `initContainers` 의 `geth init` (genesis를 datadir에 씀)
2. `containers` 의 `geth` main (실행)

이 둘은 **같은 datadir을 공유**하므로 state scheme이 반드시 일치해야 한다. scheme flag 없이 `geth init` 을 돌리면 geth의 default scheme (`path`) 으로 DB가 구성됨. 나중에 main이 `--state.scheme=hash` 로 올라오면 mismatch Fatal.

**수정:**

```yaml
initContainers:
- name: init-genesis
  command:
  - sh
  - -c
  - |
    if [ ! -d {{ .Values.config.dataDir }}/geth/chaindata ]; then
      {{- if eq .Values.config.gcMode "archive" }}
      INIT_FLAGS="--state.scheme=hash"
      {{- else }}
      INIT_FLAGS="--state.scheme=path"
      {{- end }}
      geth init $INIT_FLAGS --datadir {{ .Values.config.dataDir }} /config/genesis.json
    fi
```

Main container의 scheme 결정 로직을 init에도 그대로 복제 — 한 소스에서 둘 다 파생되는 게 이상적이지만, 현 구조에서는 양쪽에 명시하는 게 가장 단순/안전하다.

### 왜 중요한가

- `full` 모드에서는 잠복하다가 archive 전환 시 첫 배포에서 터지는 부류의 버그. 사용자가 "archive로 바꿨을 뿐인데 왜 안 뜨지" 로 시간을 잃는다.
- **일반화된 규칙: main container에 영향을 주는 persistent state 관련 flag는 init container에도 동일하게 전달해야 한다.** datadir을 공유하는 모든 체인 클라이언트(lighthouse의 `--datadir` 옵션 포함)에 확장 가능.
- geth가 `geth init` 시 default scheme을 `path` 로 가정하는 사실이 문서화되어 있지 않다 — CLI --help나 소스를 봐야 알 수 있음. 경험 기반 기록.
