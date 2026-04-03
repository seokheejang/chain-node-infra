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

- `charts/geth/` - EL 차트 초안 존재 (기본 StatefulSet, Service, ConfigMap)
- CL 차트 미작성
- JWT 시크릿 관리 구조 미완성
- Private network용 genesis 설정 미지원

## 검증 원칙

모든 차트는 Kind 클러스터에서 `ct lint` + `ct install`을 통과해야 한다.
각 Phase마다 외부 의존성 없이 Kind에서 설치 가능한 `ci/default-values.yaml`을 포함해야 한다.

---

## Phase 1: Private Network

### 목적

로컬/개발 환경에서 프라이빗 이더리움 네트워크를 구축한다.
차트 구조를 검증하고 EL-CL 통신을 확인한다.

### 작업 범위

1. **geth 차트 보강**
   - genesis.json ConfigMap 지원 (커스텀 제네시스 블록)
   - `geth init` InitContainer 추가 (제네시스 초기화)
   - bootnode 설정 지원
   - private network 전용 values 프리셋

2. **CL 차트 신규 작성** (lighthouse 또는 prysm 중 택 1)
   - StatefulSet 기반
   - beacon node + validator 구성
   - EL 연결 설정 (Engine API endpoint)

3. **JWT 시크릿 공유 구조**
   - EL과 CL이 동일한 JWT secret을 참조
   - Kubernetes Secret으로 관리
   - 생성 방법: Job 또는 외부에서 사전 생성

4. **genesis 관리**
   - genesis.json을 ConfigMap으로 관리
   - validator 키 생성 가이드

5. **통합 테스트**
   - EL-CL 연결 확인
   - 블록 생성 확인
   - ci/ values 작성 (Kind에서 ct install 통과 필수)

### 산출물

```
charts/
├── geth/          (보강)
├── lighthouse/    (신규) 또는 prysm/
└── common/        (필요 시 헬퍼 추가)

argocd/applications/
├── geth-private.yaml
└── lighthouse-private.yaml
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

5. **ArgoCD Application 작성**
   - 테스트넷별 values override

### 산출물

```
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

5. **ArgoCD Application 작성**
   - mainnet 전용 values (높은 리소스, 큰 PVC)
   - sync 정책 검토 (automated vs manual)

### 산출물

```
argocd/applications/
├── geth-mainnet.yaml
└── lighthouse-mainnet.yaml
```

---

## 차트 개발 순서 요약

```
Phase 1 (Private Network)
  ├─ geth 차트 보강 (genesis, init, bootnode)
  ├─ CL 차트 신규 작성
  ├─ JWT 시크릿 공유 구조
  └─ 통합 테스트 (ct install)
      ↓
Phase 2 (Testnet)
  ├─ checkpoint sync 추가
  ├─ 모니터링 연동
  ├─ 리소스 프로파일링
  └─ ArgoCD Application 작성
      ↓
Phase 3 (Mainnet)
  ├─ 보안 강화 (NetworkPolicy, PDB)
  ├─ 고가용성 구성
  ├─ 운영 최적화
  └─ 백업/복구 전략
```

## 참고

- 각 Phase는 이전 Phase의 차트를 기반으로 values override로 확장
- 차트 자체는 모든 네트워크를 지원하도록 범용적으로 작성
- 네트워크 차이는 ArgoCD Application의 values에서 처리
