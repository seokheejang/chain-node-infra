---
title: Helm --set의 boolean 자동 변환과 K8s nodeSelector 충돌
date: 2026-04-09
category: tooling
related: e2e/scripts/cluster.sh
---

## 컨텍스트

nginx-ingress를 Helm으로 설치하면서 `controller.nodeSelector."ingress-ready"=true`를 지정했는데 에러:

```
Error: failed to create typed patch object (ingress-nginx/ingress-nginx-controller;
apps/v1, Kind=Deployment): .spec.template.spec.nodeSelector.ingress-ready:
expected string, got &value.valueUnstructured{Value:true}
```

## 내용

**원인:** Helm `--set`은 값을 자동으로 타입 추론한다.
- `--set foo=true` → boolean `true`
- `--set foo=42` → integer `42`
- `--set foo=hello` → string `"hello"`

K8s `nodeSelector`는 모든 값이 **string**이어야 한다. boolean을 넣으면 K8s API가 거부한다.

**해결:** `--set-string`을 사용해 강제로 문자열로 보낸다.

```bash
# 잘못된 예 (boolean으로 변환됨)
helm install ... --set controller.nodeSelector."ingress-ready"=true

# 올바른 예
helm install ... --set-string controller.nodeSelector."ingress-ready"="true"
```

같은 원리가 다른 string-only 필드에도 적용됨:
- `nodeSelector` (모든 값)
- `labels` / `annotations` (모든 값)
- `matchLabels`

## 왜 중요한가

- 에러 메시지가 원인을 비교적 명확히 알려주지만 (`expected string, got valueUnstructured{Value:true}`), 처음 보면 당황스러움
- `nodeSelector`에 `true`/`false` 같은 문자열 값을 쓰는 게 흔한 패턴인데 (`ingress-ready=true`, `production=true`), `--set`으로는 항상 깨짐
- **규칙: K8s string-only 필드는 `--set-string` 사용 또는 values 파일에 quote**
