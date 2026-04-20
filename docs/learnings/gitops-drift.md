# GitOps Drift Learnings

ArgoCD/Flux 같은 GitOps 컨트롤러가 "manifest 값 == 클러스터 실제 상태" 를 지속 비교하는 과정에서 드러나는 패턴들. 로컬 `helm install`/`kubectl apply` 에서는 잠복하다가 sync 루프가 돌기 시작하면 폭발한다.

---

## 2026-04-17 — StatefulSet volumeClaimTemplates는 apiVersion/kind 를 명시해야 한다

**Category**: convention
**Related**: [charts/geth/templates/statefulset.yaml](../../charts/geth/templates/statefulset.yaml), [charts/lighthouse/templates/statefulset.yaml](../../charts/lighthouse/templates/statefulset.yaml), [charts/genesis-generator/templates/statefulset.yaml](../../charts/genesis-generator/templates/statefulset.yaml)

### 컨텍스트

ArgoCD가 3개 chart(geth/lighthouse/genesis-generator) StatefulSet을 매 sync마다 OutOfSync로 감지. diff를 보면 `spec.volumeClaimTemplates[0].apiVersion: v1` 과 `kind: PersistentVolumeClaim` 가 "live에는 있고 git에는 없는" 필드로 찍힘. 실제 변경 없음에도 무한 재sync.

### 내용

k8s API Server는 `StatefulSet.spec.volumeClaimTemplates[*]` 를 admit할 때 누락된 `apiVersion`/`kind` 를 자동으로 `v1` / `PersistentVolumeClaim` 으로 채워넣는다 (defaulting). 반면 manifest 쪽에는 없음 → GitOps 컨트롤러가 이를 "누락 → 추가 필요" 로 해석, 드리프트로 리포트.

**수정:**

```yaml
volumeClaimTemplates:
- apiVersion: v1              # 명시
  kind: PersistentVolumeClaim # 명시
  metadata:
    name: data
  spec:
    ...
```

k8s 자동 defaulting 값과 정확히 일치 → diff 소스 제거.

**대체 회피법(비추):** 소비자 쪽 ArgoCD Application에 `ignoreDifferences` 로 해당 path를 무시. 증상만 숨기고 chart가 잘못된 상태로 배포되는 본질은 그대로 → chart를 고치는 게 맞음.

### 왜 중요한가

- 같은 패턴이 `PodTemplate` 같은 서브리소스에서도 반복된다. "API가 defaulting하는 필드는 template에 명시하라" 가 규칙.
- `helm install` → 로컬에서는 k8s가 다 채워넣고 끝이라 문제가 드러나지 않는다. GitOps 환경에서만 보이는 종류의 버그.
- Spec이 하나라도 비어 있으면 사용자 측 워크어라운드(ignoreDifferences)가 퍼지고, 진짜 drift가 발생해도 묻힌다.

---

## 2026-04-17 — 비결정적 Helm template은 GitOps 환경에서 ConfigMap drift 루프를 만든다

**Category**: architecture
**Related**: [charts/genesis-generator/templates/configmap-input.yaml](../../charts/genesis-generator/templates/configmap-input.yaml)

### 컨텍스트

genesis-generator의 ConfigMap이 ArgoCD 환경에서 매 sync마다 "변경됨" 으로 찍히고, 연쇄로 StatefulSet pod-template-hash가 바뀌어 Pod 롤링 재시작이 무한 루프. 원인: template이 `GENESIS_TIMESTAMP` 를 **무조건** `now | unixEpoch` 로 덮어쓰고 있었다 — 매 render마다 값이 달라짐.

### 내용

Helm template의 **non-deterministic 함수 사용은 GitOps 환경에서 위험**하다. ArgoCD는 "live cluster state" 와 "desired state (helm template 결과)" 를 주기적으로 비교하며, render 결과가 호출마다 다르면 실제 변경이 없어도 desired state 자체가 계속 움직인다.

**잘못된 패턴:**

```yaml
{{- if eq $key "GENESIS_TIMESTAMP" }}
export GENESIS_TIMESTAMP={{ now | unixEpoch | quote }}   # 매 render마다 다른 값
{{- end }}
```

**수정 패턴 — 명시값 우선, sentinel("0"/"")만 auto-set:**

```yaml
{{- if and (eq $key "GENESIS_TIMESTAMP") (or (eq ($value | toString) "") (eq ($value | toString) "0")) }}
export {{ $key }}={{ now | unixEpoch | quote }}
{{- else }}
export {{ $key }}={{ $value | quote }}
{{- end }}
```

사용자는 초기 1회 배포 시 auto-set으로 쓰고, 이후 실제 생성된 timestamp를 values에 고정하면 deterministic render가 보장된다.

**다른 non-deterministic 함수 목록 (GitOps 환경에서 경계):**
- `now`, `date` — 시간 기반
- `randAlphaNum`, `randNumeric`, `uuidv4` — 랜덤
- `lookup` — 클러스터 상태 의존 (partial하게 drift를 만듦)

### 왜 중요한가

- "로컬에서는 문제 없는데 ArgoCD에 올리면 재시작 루프가 돈다" 는 전형적 증상의 루트 원인이다.
- `checksum/config` annotation 패턴과 결합하면 한 번의 비결정성이 전체 워크로드 롤링 재시작으로 확대된다.
- Chart를 처음 작성할 때 non-deterministic 함수는 반드시 **sentinel 값일 때만 auto-generate** 하는 패턴으로 짠다. 초기 배포 편의는 지키고 재현성은 보존.
