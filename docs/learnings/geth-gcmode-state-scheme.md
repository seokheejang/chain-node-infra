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
