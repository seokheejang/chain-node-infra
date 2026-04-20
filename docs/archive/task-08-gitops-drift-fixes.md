# Task 08: Post-Release GitOps Drift & Correctness Fixes

**날짜**: 2026-04-17
**상태**: 완료 ✅

## 배경

Task-06/07로 GHCR OCI publish + cosign keyless signing이 끝나고 ArgoCD가 실제 배포를 맡으면서, dog-food 과정에서 3가지 실무 이슈가 드러남.

1. **geth archive 모드가 첫 기동에서 Fatal로 죽음** — init container가 `--state.scheme` flag를 main container와 다르게 전달.
2. **ArgoCD가 매 sync마다 OutOfSync로 떨어짐** — 3개 chart의 `volumeClaimTemplates`에 `apiVersion`/`kind` 미선언 → k8s API 자동 채움 값과 template 값 차이로 drift.
3. **genesis-generator의 ConfigMap이 매 render마다 바뀜** — `GENESIS_TIMESTAMP`가 `now | unixEpoch`로 **무조건** 덮어써져, GitOps 환경에서 ConfigMap drift → StatefulSet 롤링 재시작 루프.

모두 "GitOps 파이프라인에서만 드러나는" 문제들. 로컬 `helm install` 시점에는 잠복.

## 변경 내용

| 파일/디렉토리 | 변경 | 설명 |
|---|---|---|
| [charts/geth/templates/statefulset.yaml](../../charts/geth/templates/statefulset.yaml) | 수정 | init container에 `--state.scheme` 명시 (archive→hash, 그 외→path). main container와 쌍 일치 |
| [charts/geth/Chart.yaml](../../charts/geth/Chart.yaml) | version bump | 0.1.3 → 0.1.4 |
| [charts/genesis-generator/templates/configmap-input.yaml](../../charts/genesis-generator/templates/configmap-input.yaml) | 수정 | `GENESIS_TIMESTAMP`가 `""`/`"0"`일 때만 `now | unixEpoch` 적용. 그 외 값은 그대로 보존 → deterministic render |
| [charts/genesis-generator/values.yaml](../../charts/genesis-generator/values.yaml) | 수정 | 해당 값의 의미 주석 업데이트 |
| [charts/genesis-generator/Chart.yaml](../../charts/genesis-generator/Chart.yaml) | version bump | 0.1.0 → 0.1.2 (중간에 volumeClaimTemplates 수정으로 0.1.1) |
| [charts/genesis-generator/templates/statefulset.yaml](../../charts/genesis-generator/templates/statefulset.yaml) | 수정 | `volumeClaimTemplates`에 `apiVersion: v1` + `kind: PersistentVolumeClaim` 명시 |
| [charts/geth/templates/statefulset.yaml](../../charts/geth/templates/statefulset.yaml) | 수정 | 상동 |
| [charts/lighthouse/templates/statefulset.yaml](../../charts/lighthouse/templates/statefulset.yaml) | 수정 | 상동 |
| [charts/lighthouse/Chart.yaml](../../charts/lighthouse/Chart.yaml) | version bump | 0.1.0 → 0.1.1 |

## 결과

- `geth archive` 모드 first boot 정상. `incompatible state scheme` Fatal 재현 안 됨.
- ArgoCD Application 3개 (geth/lighthouse/genesis-generator) Sync 완료 후 OutOfSync 재진입 없음 — 소비자 측에서 사용하던 `ignoreDifferences` 워크어라운드 제거 가능.
- `helm template`을 동일 values로 연속 2회 호출 시 ConfigMap 내용 byte 일치 (`GENESIS_TIMESTAMP` 명시값 경로). `""`/`"0"` 경로는 기존과 동일하게 auto-set (backward compatible).

## 핸드오프

→ [docs/CHANGELOG.md](../CHANGELOG.md) v0.7 항목에 요약.
→ 학습 기록: [docs/learnings/geth-gcmode-state-scheme.md](../learnings/geth-gcmode-state-scheme.md) (init/main scheme 쌍 일치 섹션 추가), [docs/learnings/gitops-drift.md](../learnings/gitops-drift.md) (volumeClaimTemplates apiVersion/kind, 비결정적 template).

### 소비자 쪽 (ArgoCD) 반영 체크리스트

1. 상위 umbrella chart의 `dependencies` 버전 bump:
   - `genesis-generator`: `0.1.2`
   - `geth`: `0.1.4`
   - `lighthouse`: `0.1.1`
2. `helm dep update`로 `Chart.lock` 갱신
3. `values`에 `GENESIS_TIMESTAMP` 고정 값 명시 (drift 예방)
4. 기존 `ignoreDifferences` (volumeClaimTemplates 관련) 제거
