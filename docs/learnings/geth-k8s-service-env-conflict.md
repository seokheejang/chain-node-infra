---
title: K8s Service 이름이 GETH_ 접두사일 때 환경변수 충돌
date: 2026-04-08
category: debugging
related: charts/geth
---

## 컨텍스트

geth init 컨테이너 로그에 `WARN Unknown config environment variable` 경고가 28건 발생.
실제 설정 오류는 아니지만 로그를 오염시킨다.

## 내용

Kubernetes는 같은 namespace의 Service에 대해 환경변수를 자동 주입한다:

```
Service name: geth-e2e
→ GETH_E2E_PORT=tcp://10.96.x.x:8545
→ GETH_E2E_SERVICE_HOST=10.96.x.x
→ GETH_E2E_SERVICE_PORT=8545
→ ... (28개)
```

Geth는 `GETH_` 접두사를 가진 환경변수를 **설정 플래그로 해석**하려고 시도한다.
K8s가 주입한 `GETH_E2E_*` 변수는 유효한 geth 설정이 아니므로 경고가 발생.

**해결 방법 2가지:**

```yaml
# 방법 1: Pod spec에 enableServiceLinks 비활성화 (권장)
spec:
  template:
    spec:
      enableServiceLinks: false

# 방법 2: Service 이름을 GETH_ 접두사가 아닌 것으로 변경
# 예: geth-e2e → el-e2e (fullname 로직 변경 필요)
```

## 왜 중요한가

- 기능적 문제는 없지만 로그 모니터링 시 실제 경고를 가리는 노이즈가 됨
- geth 외에도 `GETH_`, `PRYSM_` 등 환경변수 기반 설정을 사용하는 클라이언트에서 동일 패턴 발생 가능
- `enableServiceLinks: false`는 부작용이 거의 없으므로 블록체인 노드 차트에서는 기본 적용 권장
