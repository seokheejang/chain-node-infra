---
title: Helm ingress hostnames에서 string/map 듀얼 포맷을 kindIs로 분기하는 패턴
date: 2026-04-09
category: convention
related: charts/geth/templates/ingress.yaml, charts/lighthouse/templates/ingress.yaml
---

## 컨텍스트

geth 차트에서 RPC(8545)와 WebSocket(8546) 포트를 별도 hostname으로 노출해야 했다.
기존 `ingress.hostnames`는 단순 string 배열이라 포트를 지정할 수 없었다.
하위 호환을 유지하면서 per-port 라우팅을 추가해야 했다.

## 내용

Helm의 `kindIs` 함수로 리스트 항목의 타입을 분기:

```yaml
{{- range .Values.ingress.hostnames }}
{{- if kindIs "string" . }}
# 기존 형식: 단순 문자열 → 기본 포트(rpc)로 라우팅
- host: {{ . | quote }}
  ...
  port:
    number: {{ $.Values.service.ports.rpc }}
{{- else }}
# 신규 형식: map → 지정 포트로 라우팅
- host: {{ .hostname | quote }}
  ...
  port:
    number: {{ index $.Values.service.ports .port }}
{{- end }}
{{- end }}
```

사용 예:
```yaml
# 기존 호환 (string)
hostnames:
  - geth-rpc.192.168.1.100.nip.io

# 신규 per-port (map)
hostnames:
  - hostname: geth-rpc.192.168.1.100.nip.io
    port: rpc
  - hostname: geth-ws.192.168.1.100.nip.io
    port: ws
```

`index $.Values.service.ports .port`로 동적 포트 룩업. `.port` 값이 `service.ports`의 키와 불일치하면 `helm template`에서 즉시 에러 → 조용한 실패 없음.

## 왜 중요한가

- 하위 호환을 유지하면서 기능을 확장하는 Helm 패턴으로 재활용 가능
- bitnami 등 대형 차트에서도 사용하는 검증된 패턴 (kindIs)
- 동일 패턴을 Ingress + HTTPRoute 양쪽에 일관 적용해야 함 (누락 주의)
