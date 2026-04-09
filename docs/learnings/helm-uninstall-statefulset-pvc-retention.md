---
title: helm uninstall이 StatefulSet PVC를 삭제하지 않아 발생하는 chaindata 충돌
date: 2026-04-09
category: debugging
related: e2e/scripts/ethereum.sh, charts/geth, charts/lighthouse
---

## 컨텍스트

genesis 설정(fork epoch, gas limit 등)을 변경한 후 e2e teardown → deploy를 반복했더니, geth가 새 genesis를 거부하고 lighthouse가 동기화 실패:

```
geth: WARN Forkchoice requested unknown head hash=d893b4..494819
validator: ERROR PayloadIdUnavailable
```

PVC 목록을 확인하니 이전 배포의 PVC가 그대로 살아 있었다.

## 내용

**원인:** Helm이 StatefulSet의 PVC(volumeClaimTemplates)를 의도적으로 보존한다. K8s 설계상 데이터 보호를 위한 것.

```bash
helm uninstall geth-e2e -n ethereum-e2e
# → StatefulSet, Pod 삭제됨
# → PVC는 남아있음 (data-geth-e2e-0)

kubectl get pvc -n ethereum-e2e
# data-geth-e2e-0   Bound   ...   <-- 여전히 존재
```

다음 deploy 시:
1. 새 genesis-generator가 새 timestamp/hash로 genesis 생성
2. 새 geth Pod가 기존 PVC를 마운트
3. `geth init`은 chaindata가 이미 있으면 skip
4. 결과: 새 genesis와 이전 chaindata 불일치 → forkchoice 에러

**해결:** teardown 스크립트에서 PVC를 명시적으로 삭제한다.

```bash
# e2e/scripts/ethereum.sh teardown
helm uninstall ${RELEASE} -n ${NAMESPACE}
kubectl delete pvc --all -n ${NAMESPACE}
kubectl delete namespace ${NAMESPACE}
```

geth init 템플릿도 확인:
```sh
if [ ! -d /data/geth/geth/chaindata ]; then
  geth init ...    # 새 genesis 적용
else
  echo "Chain data already exists, skipping init."   # ← 이게 함정
fi
```

## 왜 중요한가

- 블록체인 노드 차트는 특히 중요. genesis가 바뀌면 chaindata도 reset 필요
- helm uninstall만으로는 클린 상태가 되지 않는다는 것을 모르면 디버깅에 시간 소모
- 프로덕션에서는 PVC 보존이 맞지만, devnet/e2e에서는 매번 reset 필요
- 에러 메시지(`Forkchoice requested unknown head`)가 원인을 직접적으로 알려주지 않음
