# Task 03: E2E EL-CL 통신 검증

## 목표

Kind 클러스터에서 geth(EL) + lighthouse(CL)를 배포하고,
Engine API를 통한 EL-CL 통신이 정상적으로 이루어지는지 자동 검증한다.

## 배경

Task 02 Phase 1에서 geth/lighthouse Helm 차트를 작성하고 `helm template` 렌더링 검증을 통과했다.
그러나 실제 K8s 클러스터에서 Pod가 정상 구동되고 두 레이어가 통신하는지는 아직 확인하지 않았다.

| 검증 레벨 | 내용 | 도구 | 상태 |
|-----------|------|------|------|
| 1. Template | YAML 문법, 값 참조 | `helm template` | 통과 |
| 2. Lint | 차트 규약, 베스트프랙티스 | `ct lint` | 미실행 (CI에서) |
| 3. Install | Pod 생성 + Ready | `ct install` | 미실행 (Kind 필요) |
| **4. E2E** | **EL-CL 통신, API 응답** | **커스텀 스크립트** | **이 작업** |

## 기존 e2e 인프라

- `e2e/scripts/cluster.sh setup|verify|teardown` — Kind 클러스터 + ArgoCD 관리
- `e2e/kind/cluster.yaml` — Kind 노드 구성 (control-plane + worker)
- `e2e/argocd/values.yaml` — e2e용 ArgoCD 경량 설정

## 설계 결정사항

### 배포 방식: Helm 직접 설치 (ArgoCD 경유 X)

ArgoCD를 거치지 않고 `helm upgrade --install`로 직접 배포한다.
- 빠른 피드백 (ArgoCD sync 대기 불필요)
- 디버깅 용이 (helm status로 직접 확인)
- e2e 테스트에 ArgoCD 의존성 제거

### 릴리스 네이밍

`common.names.fullname` 로직에 따라:
- release 이름에 chart 이름이 포함되면 → fullname = release 이름

| 항목 | 값 |
|------|-----|
| namespace | `ethereum-e2e` |
| geth release | `geth-e2e` → Service: `geth-e2e`, ConfigMap: `geth-e2e-genesis` |
| lighthouse release | `lighthouse-e2e` → Service: `lighthouse-e2e` |
| EL endpoint | `http://geth-e2e:8551` |

### 리소스 예산

Kind 클러스터 (4 CPU / 6 GB)에서 ArgoCD와 공존:

| 컴포넌트 | CPU req | Memory req |
|----------|---------|------------|
| ArgoCD (기존) | ~450m | ~700Mi |
| geth-e2e | 100m | 256Mi |
| lighthouse-e2e | 100m | 256Mi |
| 시스템 오버헤드 | ~500m | ~500Mi |
| **합계** | **~1150m** | **~1712Mi** |

### 블록 생성 불가

Private PoS 네트워크에서 validator client 없이는 블록이 생성되지 않는다.
이 e2e 테스트에서는 **EL-CL Engine API 연결 확인**까지만 검증한다.

## 검증 항목

| # | 검증 | 방법 | 타임아웃 |
|---|------|------|---------|
| 1 | Geth pod Ready | `kubectl wait --for=condition=Ready` | 120s |
| 2 | Lighthouse pod Ready | `kubectl wait --for=condition=Ready` | 120s |
| 3 | Geth RPC 응답 | `curl eth_syncing` (port-forward) | 30s |
| 4 | Lighthouse API 응답 | `curl /lighthouse/health` (port-forward) | 30s |
| 5 | **EL-CL 연결** | `curl /eth/v1/node/syncing` → `el_offline: false` | 90s |

## 실행 순서

```bash
# 1. Kind + ArgoCD 설정
e2e/scripts/cluster.sh setup

# 2. EL-CL 배포 + 검증
e2e/scripts/ethereum.sh deploy

# 3. 수동 재검증 (선택)
e2e/scripts/ethereum.sh verify

# 4. EL-CL 정리
e2e/scripts/ethereum.sh teardown

# 5. Kind 클러스터 정리 (선택)
e2e/scripts/cluster.sh teardown
```

## 산출물

```
e2e/
├── values/
│   ├── geth.yaml              # e2e 전용 geth values (경량)
│   └── lighthouse.yaml        # e2e 전용 lighthouse values (경량)
└── scripts/
    └── ethereum.sh            # 통합 스크립트 (deploy|verify|teardown)
```

## 주의사항

- e2e values는 `environments/private/`와 별개 — 리소스/probe 설정이 Kind에 최적화됨
- `executionEndpoint`와 `elGenesisConfigMap`은 geth release 이름(`geth-e2e`)에 의존
- lighthouse InitContainer(genesis.ssz 생성)가 geth genesis ConfigMap을 참조하므로 geth 먼저 배포
- 검증 스크립트는 `port-forward`를 사용하며, trap으로 프로세스 정리
