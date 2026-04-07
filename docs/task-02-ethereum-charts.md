# Task 02: 이더리움 차트 작성

## 목표

이더리움 노드 인프라를 Helm 차트로 작성한다.
Private Network → Testnet → Mainnet 순서로 점진적으로 확장한다.

## 이더리움 노드 구성 개요

이더리움은 The Merge(2022.09) 이후 두 레이어로 구성된다:

| 레이어 | 역할 | 대표 클라이언트 |
|--------|------|-----------------|
| Execution Layer (EL) | 트랜잭션 실행, 상태 관리 | geth, nethermind, besu, erigon |
| Consensus Layer (CL) | PoS 합의, 블록 제안 | lighthouse, prysm, teku, nimbus |

EL + CL은 **Engine API (JWT 인증)** 로 통신한다.
**두 레이어 모두 있어야** 노드가 정상 동작한다.

## 현재 상태

- `charts/geth/` (v0.1.0) - EL 차트 (private network, genesis init, Engine API, JWT, Ingress/HTTPRoute)
- `charts/lighthouse/` (v0.1.0) - CL 차트 (beacon node, genesis.ssz 자동 생성, JWT, Ingress/HTTPRoute)
- JWT 시크릿: geth/lighthouse 간 Kubernetes Secret 공유 구조 완성
- Genesis: ConfigMap 기반 관리 (EL genesis.json + CL config.yaml)
- ArgoCD: `valueFiles` + `environments/` 구조로 환경별 values 분리
- Ingress: Kubernetes Ingress + Cilium Gateway API (HTTPRoute) 듀얼 지원
- CI: ct lint/install 용 default-values.yaml 작성 완료
- 검증: `helm template` 렌더링 통과 (기본값, private, ingress, httpRoute 모두)

## 설계 결정사항

| 항목 | 결정 | 근거 |
|------|------|------|
| CL 클라이언트 | Lighthouse (sigp) | Rust 구현 메모리 효율, ethpandaops 레퍼런스, 커뮤니티 Helm 사례 풍부 |
| EL-CL 아키텍처 | 별도 Pod (Separate StatefulSets) | 독립 스케일링, 장애 격리, 독립 업그레이드 |
| genesis.ssz 생성 | lighthouse InitContainer (`ethpandaops/ethereum-genesis-generator`) | 차트만으로 완결, 업계 표준 도구 |
| Contract 배포 | genesis.json alloc 필드 | 블록 0부터 존재, 단순 확실 |
| 개발자 계정 ETH | genesis.json alloc 필드 | 동일 |
| Genesis config 관리 | ConfigMap (EL: genesis.json, CL: config.yaml) | 1MB 이내, K8s 네이티브 |
| JWT 관리 | Kubernetes Secret (geth/lighthouse 공유) | existingSecret 패턴 |
| Values 관리 | `environments/` 디렉토리 + ArgoCD `valueFiles` | inline 대비 확장성, 환경별 diff 명확 |
| 엔드포인트 노출 | Ingress + HTTPRoute 듀얼 지원 (`ingress.type` 토글) | Cilium Gateway API 대응 |
| Chain Reset | Phase 4에서 구현 (Helm pre-upgrade Hook 방식 설계) | devnet 특성상 빈번한 초기화 대비 |

## 검증 원칙

모든 차트는 Kind 클러스터에서 `ct lint` + `ct install`을 통과해야 한다.
각 Phase마다 외부 의존성 없이 Kind에서 설치 가능한 `ci/default-values.yaml`을 포함해야 한다.

---

## Phase 1: Private Network (완료)

### 목적

로컬/개발 환경에서 프라이빗 이더리움 네트워크를 구축한다.
차트 구조를 검증하고 EL-CL 통신을 확인한다.

### 작업 범위

1. **geth 차트 보강** (완료)
   - genesis.json ConfigMap 지원 (커스텀 제네시스 블록)
   - `geth init` InitContainer 추가 (제네시스 초기화, idempotent)
   - Engine API (authrpc) 포트 및 args 추가
   - bootnode 설정 지원
   - private network 모드 (`config.network: private` → `--networkid` 플래그)
   - JWT Secret 템플릿 추가
   - Ingress + HTTPRoute 듀얼 지원

2. **CL 차트 신규 작성** — lighthouse (완료)
   - StatefulSet 기반 beacon node
   - `ethpandaops/ethereum-genesis-generator:v5.3.5` InitContainer로 genesis.ssz 자동 생성
   - EL 연결 설정 (Engine API endpoint)
   - custom testnet-dir 지원 (CL config.yaml + mnemonics ConfigMap)
   - Ingress + HTTPRoute 듀얼 지원

3. **JWT 시크릿 공유 구조** (완료)
   - EL과 CL이 동일한 Kubernetes Secret을 `existingSecret`으로 참조
   - `scripts/generate-jwt-secret.sh` 헬퍼 스크립트 제공

4. **genesis 관리** (완료)
   - EL: genesis.json을 ConfigMap으로 관리 (values에서 YAML로 정의 → JSON 변환)
   - CL: config.yaml + deploy_block + mnemonics.yaml을 ConfigMap으로 관리
   - genesis alloc으로 개발자 계정 ETH 사전 할당 및 contract bytecode 배포 지원

5. **환경별 values 관리** (완료)
   - `environments/` 디렉토리 도입 (private, mainnet)
   - ArgoCD Application에서 `valueFiles`로 참조 (inline values 제거)
   - CI values: `ci/default-values.yaml` 별도 유지

6. **검증** (부분 완료)
   - `helm template` 렌더링: 통과 (mainnet 기본값, private, ingress, httpRoute)
   - `ct lint`: 미실행 (CI에서 검증 예정)
   - `ct install`: 미실행 (Kind 클러스터 필요)
   - EL-CL 통합 테스트: 미구현

### 산출물

```
charts/
├── geth/          (private network, genesis, Engine API, JWT, Ingress/HTTPRoute)
├── lighthouse/    (beacon node, genesis.ssz generator, JWT, Ingress/HTTPRoute)
└── common/        (변경 없음)

environments/
├── private/
│   ├── geth.yaml
│   └── lighthouse.yaml
└── mainnet/
    └── geth.yaml

argocd/applications/
├── geth.yaml              (mainnet, valueFiles 참조)
├── geth-private.yaml      (private, valueFiles 참조)
└── lighthouse-private.yaml (private, valueFiles 참조)

scripts/
└── generate-jwt-secret.sh
```

---

## Phase 2: Testnet (Sepolia / Holesky)

### 목적

퍼블릭 테스트넷에 연결하여 실제 네트워크 환경에서 차트를 검증한다.

### 작업 범위

1. **geth 차트 조정**
   - `--sepolia` / `--holesky` 네트워크 플래그 지원 (이미 존재)
   - checkpoint sync 설정 추가 (빠른 초기 동기화)
   - snapshot pruning 설정

2. **CL 차트 조정**
   - 테스트넷 체크포인트 sync URL 설정
   - 테스트넷 bootnodes 설정

3. **모니터링 연동**
   - Prometheus ServiceMonitor 활성화
   - sync 상태 대시보드 기본 설정

4. **리소스 프로파일링**
   - 테스트넷 기준 적정 resources 값 확인
   - PVC 사이즈 가이드 (테스트넷별)

5. **환경 values 추가**
   - `environments/sepolia/`, `environments/holesky/` 디렉토리 추가

### 산출물

```
environments/
├── sepolia/
│   ├── geth.yaml
│   └── lighthouse.yaml
└── holesky/
    ├── geth.yaml
    └── lighthouse.yaml

argocd/applications/
├── geth-sepolia.yaml
├── lighthouse-sepolia.yaml
├── geth-holesky.yaml
└── lighthouse-holesky.yaml
```

---

## Phase 3: Mainnet

### 목적

프로덕션 메인넷 노드를 안정적으로 운영한다.

### 작업 범위

1. **보안 강화**
   - NetworkPolicy 추가 (P2P, RPC 포트 분리)
   - PodDisruptionBudget 설정
   - Secret 관리 (External Secrets Operator 연동)

2. **고가용성**
   - 복수 replica 구성 검증
   - anti-affinity 규칙
   - graceful shutdown 설정 (preStop hook)

3. **운영 최적화**
   - 리소스 튜닝 (mainnet 기준)
   - PVC 사이즈: EL ~2TB, CL ~500GB (시점에 따라 변동)
   - 노드 스케줄링 (nodeSelector, tolerations)

4. **백업/복구**
   - 체인 데이터 스냅샷 전략
   - 장애 복구 절차 문서화

5. **환경 values 보강**
   - `environments/mainnet/lighthouse.yaml` 추가
   - sync 정책 검토 (automated vs manual)

### 산출물

```
environments/
└── mainnet/
    ├── geth.yaml          (보강)
    └── lighthouse.yaml    (신규)

argocd/applications/
├── geth-mainnet.yaml      (기존 geth.yaml 리네이밍 검토)
└── lighthouse-mainnet.yaml
```

---

## Phase 4: Chain Reset (설계 완료, 구현 예정)

### 목적

devnet 특성상 contract 재배포 및 누적 데이터 초기화가 빈번하다.
K8s-native한 chain reset 방안을 도입한다.

### 설계

**Soft Reset (데이터만 초기화, PVC 유지)**:
- Helm `pre-upgrade` hook Job으로 구현
- `chainReset.enabled: true` → geth chaindata 삭제 + genesis re-init
- ArgoCD에서 values 하나 변경으로 트리거 가능
- 실행 후 `chainReset.enabled: false`로 복원

**Hard Reset (PVC 삭제 + 재설치)**:
- `helm uninstall` + `kubectl delete pvc` + `helm install`
- 운영 가이드 문서로 제공

### 산출물

```
charts/geth/templates/job-chain-reset.yaml       (Helm pre-upgrade hook)
charts/lighthouse/templates/job-chain-reset.yaml  (Helm pre-upgrade hook)
docs/operations/chain-reset.md                    (운영 가이드)
```

---

## 차트 개발 순서 요약

```
Phase 1 (Private Network) ✅ 완료
  ├─ geth 차트 보강 (genesis, init, Engine API, bootnode, Ingress/HTTPRoute)
  ├─ lighthouse 차트 신규 작성 (beacon node, genesis.ssz, Ingress/HTTPRoute)
  ├─ JWT 시크릿 공유 구조
  ├─ environments/ + valueFiles 구조 도입
  └─ helm template 렌더링 검증
      ↓
Phase 2 (Testnet) — 다음 작업
  ├─ checkpoint sync 추가
  ├─ 모니터링 연동
  ├─ 리소스 프로파일링
  └─ environments/sepolia, holesky 추가
      ↓
Phase 3 (Mainnet)
  ├─ 보안 강화 (NetworkPolicy, PDB)
  ├─ 고가용성 구성
  ├─ 운영 최적화
  └─ 백업/복구 전략
      ↓
Phase 4 (Chain Reset)
  ├─ Helm pre-upgrade hook 구현
  └─ 운영 가이드 문서화
```

## 참고

- 각 Phase는 이전 Phase의 차트를 기반으로 values override로 확장
- 차트 자체는 모든 네트워크를 지원하도록 범용적으로 작성
- 네트워크 차이는 `environments/` 디렉토리의 values 파일에서 처리
- 엔드포인트 노출은 `ingress.type` 토글로 Ingress/HTTPRoute 선택
- 참조 프로젝트: [ethpandaops/ethereum-helm-charts](https://github.com/ethpandaops/ethereum-helm-charts), [OffchainLabs/eth-pos-devnet](https://github.com/OffchainLabs/eth-pos-devnet)
