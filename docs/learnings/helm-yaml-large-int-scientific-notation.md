---
title: Helm values의 큰 정수가 과학적 표기법으로 렌더링되는 문제
date: 2026-04-09
category: tooling
related: charts/geth/values.yaml, charts/geth/templates/statefulset.yaml
---

## 컨텍스트

`CHAIN_ID`를 `32382`에서 `3238200`으로 변경한 후 geth가 시작되지 않음:

```
invalid value "3.2382e+06" for flag -networkid: parse error
```

values.yaml에는 `networkId: 3238200`로 작성했는데, geth는 `3.2382e+06` (과학적 표기법)을 받음.

## 내용

**원인:** YAML이 큰 정수를 float로 파싱한 후 Go template이 float 포맷으로 렌더링한다.
- `networkId: 3238200` → YAML 파서가 float64로 해석
- Go template `{{ .Values.config.networkId }}` 가 float을 `3.2382e+06`로 렌더링
- geth `--networkid` 플래그가 파싱 실패

**해결:** values.yaml에서 문자열로 quote한다.

```yaml
# 잘못된 예 (과학적 표기법으로 렌더링됨)
config:
  networkId: 3238200

# 올바른 예
config:
  networkId: "3238200"
```

`--set` 명령에서도 같은 문제가 발생할 수 있다. 큰 정수는 항상 quote.

## 왜 중요한가

- YAML/Helm으로 큰 숫자(chainId, port mapping, gas limit 등)를 다룰 때 반복적으로 발생할 수 있음
- 에러 메시지(`3.2382e+06`)만으로는 원인을 즉시 파악하기 어려움
- 작은 숫자(예: 1337)에서는 발생하지 않다가 큰 숫자로 바꾸는 순간 터짐
- 컨벤션: **모든 ID/large integer는 string으로 quote**한다
