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

### Private PoS Network 구성 시 알아야 할 개념

#### Genesis 파일

Private network를 시작하려면 **체인의 시작 상태**(genesis)를 정의해야 한다.

| 파일 | 대상 | 형식 | 내용 |
|------|------|------|------|
| `genesis.json` | EL (geth) | JSON | chainId, 초기 계정 잔액(alloc), EIP 활성화 블록, TTD |
| `genesis.ssz` | CL (lighthouse) | SSZ (바이너리) | BeaconState — validator set, fork config, EL genesis 참조 |
| `config.yaml` | CL (lighthouse) | YAML | 슬롯 시간, fork epoch, deposit contract 주소 등 CL 파라미터 |

**핵심**: `genesis.json`과 `genesis.ssz`는 반드시 **동일한 소스에서 생성**되어야 한다.
별도로 생성하면 EL genesis block hash가 불일치하여 EL-CL 통신이 실패한다.

#### genesis.ssz를 직접 만들 수 없는 이유

`genesis.ssz`는 SSZ(Simple Serialize) 포맷의 바이너리 파일로, 내부에 다음이 포함된다:
- validator별 BLS public key (mnemonic에서 derive)
- Merkle state root 계산
- fork별 BeaconState 구조체 (Deneb ≠ Capella ≠ Bellatrix)
- EL genesis block hash 참조

이를 직접 구현하는 것은 비현실적이며, `ethpandaops/ethereum-genesis-generator` 같은 전용 도구가 필수.

#### Genesis Generator

[ethpandaops/ethereum-genesis-generator](https://github.com/ethpandaops/ethereum-genesis-generator) 이미지를 사용한다.

- 입력: `values.env` (체인 설정), `mnemonics.yaml` (validator 키)
- 출력: `genesis.json` (EL) + `genesis.ssz` (CL) + `config.yaml` (CL) 등
- 내부에 python HTTP 서버를 포함하여 (`SERVER_ENABLED=true`) 생성된 아티팩트를 HTTP로 서빙
- `genesis.ssz`가 2~3MB로 ConfigMap 크기 제한(3MB)을 초과할 수 있어 HTTP 서빙 방식이 필수

#### Fork Epochs

이더리움은 하드포크를 통해 프로토콜을 업그레이드한다. Private network에서는 `FORK_EPOCH: 0`으로 설정하여 genesis부터 활성화한다.

| Fork | 주요 변경 | devnet 설정 |
|------|----------|------------|
| Altair | Light client 지원 | epoch 0 |
| Bellatrix | The Merge (PoS 전환) | epoch 0 |
| Capella | Validator 출금 | epoch 0 |
| Deneb | Blob 트랜잭션 (EIP-4844) | epoch 0 |
| Electra | 미래 | far-future (비활성화) |
| Fulu | 미래 | far-future (비활성화) |

`ELECTRA_FORK_EPOCH: "18446744073709551615"` (uint64 최대값)으로 설정하면 사실상 비활성화.

#### Deposit Contract

- 주소: `0x4242424242424242424242424242424242424242` (devnet 표준)
- 목적: Validator가 되려면 이 컨트랙트에 32 ETH를 보내야 함
- genesis-generator가 `genesis.json`에 자동 포함
- `deposit_contract_block.txt`: deposit contract가 배포된 EL 블록 번호 (devnet에서는 "0")
- lighthouse가 시작 시 이 파일을 필수로 요구 (deposit 이벤트 스캔 시작점)

#### Premine (사전 할당 계정)

`EL_PREMINE_ADDRS` 환경변수로 genesis에 미리 ETH를 할당:
```
EL_PREMINE_ADDRS: '{"0x123463...": {"balance": "1000000000ETH"}}'
```
Contract bytecode도 genesis alloc에 포함 가능 (블록 0부터 존재).

#### JWT (JSON Web Token)

EL과 CL이 Engine API로 통신할 때 인증에 사용:
```
openssl rand -hex 32 → jwt.hex
geth: --authrpc.jwtsecret=/secrets/jwt/jwt.hex
lighthouse: --execution-jwt=/secrets/jwt/jwt.hex
```
K8s에서는 Kubernetes Secret으로 관리하여 양쪽 Pod에 마운트.

#### Validator Mnemonics

genesis-generator는 BIP-39 mnemonic에서 validator BLS 키를 derive:
```yaml
mnemonics:
  - mnemonic: "test test test test test test test test test test test junk"
    count: 1  # 생성할 validator 수
```
devnet에서는 test mnemonic 사용. 프로덕션에서는 절대 사용 금지.

---

## 현재 상태

- `charts/genesis-generator/` (v0.1.0) - Genesis 생성 StatefulSet + HTTP 서버 (ethpandaops 패턴)
- `charts/geth/` (v0.1.0) - EL 차트 (private network, genesis init via wget, Engine API, JWT, Ingress/HTTPRoute)
- `charts/lighthouse/` (v0.1.0) - CL 차트 (beacon node, testnet-dir via wget, JWT, Ingress/HTTPRoute)
- `charts/lighthouse-validator/` (v0.1.0) - VC 차트 (validator client, lighthouse account recover key gen, beacon API 연결)
- Genesis: genesis-generator가 EL+CL genesis 생성 → HTTP(8000)로 서빙 → geth/lighthouse/validator initContainer wget
- Genesis timestamp: ConfigMap 템플릿에서 Helm `now | unixEpoch`로 배포 시점 자동 설정 (`GENESIS_TIMESTAMP`)
- JWT 시크릿: geth/lighthouse 간 Kubernetes Secret 공유
- Validator keys: genesis mnemonic → `lighthouse account validator recover` initContainer → lighthouse vc
- ArgoCD: `valueFiles` + `environments/` 구조
- Ingress: Kubernetes Ingress + Cilium Gateway API (HTTPRoute) 듀얼 지원
- PVC 정책: Kubernetes 기본값(Retain) — ArgoCD App 삭제 시 PVC 보존, namespace 삭제 시 정리
- E2E: `e2e/scripts/cluster.sh` (인프라) + `e2e/scripts/ethereum.sh` (체인) 통합 스크립트

## Genesis 생성 Flow

```
genesis-generator StatefulSet (ethpandaops/ethereum-genesis-generator)
  ├─ 입력: values.env (chainConfig), mnemonics.yaml
  ├─ 실행: entrypoint.sh all → genesis 생성
  ├─ 서빙: python3 -m http.server 8000 --directory /data
  │         ├─ /metadata/genesis.json    (EL genesis)
  │         ├─ /metadata/genesis.ssz     (CL genesis, ~2.7MB)
  │         ├─ /metadata/config.yaml     (CL config)
  │         └─ /metadata/deposit_contract_block.txt
  │
  ├─ geth initContainer
  │    └─ wget genesis.json → geth init
  │
  ├─ lighthouse initContainer
  │    └─ wget genesis.ssz + config.yaml → --testnet-dir
  │
  └─ lighthouse-validator initContainers
       ├─ wget genesis.ssz + config.yaml → --testnet-dir
       └─ lighthouse account validator recover (동일 mnemonic) → --datadir/validators
```

ConfigMap 방식 대신 HTTP 서버를 사용하는 이유:
- `genesis.ssz`가 2~3MB → ConfigMap 크기 제한(3MB, base64 시 초과) 위반
- ethpandaops 표준 패턴 (이미지에 `SERVER_ENABLED` 내장)
- RBAC 불필요 (ConfigMap 생성 권한이 필요 없음)

## 설계 결정사항

| 항목 | 결정 | 근거 |
|------|------|------|
| CL 클라이언트 | Lighthouse (sigp) | Rust 구현 메모리 효율, ethpandaops 레퍼런스 |
| EL-CL 아키텍처 | 별도 Pod (Separate StatefulSets) | 독립 스케일링, 장애 격리, 독립 업그레이드 |
| Genesis 생성 | 별도 StatefulSet (`charts/genesis-generator/`) | EL+CL genesis 동시 생성, HTTP 서빙 |
| Genesis 공유 | HTTP 서버 (port 8000) | genesis.ssz 크기 제한 회피, ethpandaops 표준 |
| Genesis 소비 | geth/lighthouse initContainer wget | genesis-generator 서비스 ready 후 다운로드 |
| Contract/계정 | genesis-generator의 `EL_PREMINE_ADDRS` 환경변수 | 블록 0부터 존재 |
| JWT 관리 | Kubernetes Secret (geth/lighthouse 공유) | existingSecret 패턴 |
| Values 관리 | `environments/` 디렉토리 + ArgoCD `valueFiles` | inline 대비 확장성 |
| 엔드포인트 노출 | Ingress + HTTPRoute 듀얼 지원 (`ingress.type` 토글) | Cilium Gateway API 대응 |
| Validator Key 생성 | `lighthouse account validator recover` initContainer (devnet), Secret 주입 (prod) | 동일 이미지, 추가 의존성 없음 |
| Validator 차트 | 별도 차트 (`charts/lighthouse-validator/`) | beacon node와 독립 스케일링, 라이프사이클 분리 |
| Validator 스토리지 | emptyDir (PVC 없음) | devnet용, slashing protection은 prod에서 PVC 추가 가능 |
| Genesis timestamp | ConfigMap 템플릿에서 `now \| unixEpoch` 자동 설정 | 배포 시점 기준 slot 0부터 시작, 고정값 불필요 |
| PVC 정책 | Kubernetes 기본값 Retain (자동 삭제 안 함) | ArgoCD App 실수 삭제 시 데이터 보존, namespace 삭제로 정리 |
| PVC 사이즈 (devnet) | geth 50Gi, lighthouse 20Gi, genesis-generator 1Gi | 6개월~1년 운영 기준 |
| Chain Reset | Phase 4에서 구현 (Helm pre-upgrade Hook 방식 설계) | devnet 특성상 빈번한 초기화 대비 |

### Genesis 소스 우선순위 (하위 호환)

geth/lighthouse 차트는 3가지 genesis 소스를 모두 지원:

| 우선순위 | 방식 | values 키 | 용도 |
|---------|------|----------|------|
| 1 (최우선) | HTTP 다운로드 | `genesis.fromUrl` / `testnetDir.fromUrls` | genesis-generator 서버 참조 |
| 2 | ConfigMap 참조 | `genesis.existingConfigMap` / `testnetDir.existingConfigMap` | 외부 ConfigMap |
| 3 | inline values | `genesis.config` / `testnetDir.config` | 직접 정의 (소규모 테스트) |

## 검증 원칙

모든 차트는 Kind 클러스터에서 `ct lint` + `ct install`을 통과해야 한다.
각 Phase마다 외부 의존성 없이 Kind에서 설치 가능한 `ci/default-values.yaml`을 포함해야 한다.

---

## Phase 1: Private Network (완료)

### 목적

로컬/개발 환경에서 프라이빗 이더리움 네트워크를 구축한다.
차트 구조를 검증하고 EL-CL 통신을 확인한다.

### 작업 범위

1. **genesis-generator 차트** (완료)
   - `ethpandaops/ethereum-genesis-generator:5.3.5` 기반 StatefulSet
   - 이미지 entrypoint(`/work/entrypoint.sh all`)로 genesis 생성 후 HTTP 서빙
   - `SERVER_ENABLED=true`, `SERVER_PORT=8000`
   - ConfigMap으로 `values.env` + `mnemonics.yaml` 주입 (subPath 마운트)
   - Service(ClusterIP)로 클러스터 내부 노출
   - readinessProbe: `/metadata/genesis.json` HTTP GET

2. **geth 차트 보강** (완료)
   - `genesis.fromUrl`로 genesis-generator HTTP 서버에서 genesis.json 다운로드
   - download-genesis initContainer (wget + retry loop)
   - geth-init initContainer (geth init, idempotent)
   - Engine API (authrpc) 포트 및 args
   - private network 모드 (`config.network: private` → `--networkid`)
   - bootnode, JWT Secret, Ingress + HTTPRoute 듀얼 지원

3. **lighthouse 차트** (완료)
   - `testnetDir.fromUrls`로 genesis-generator에서 genesis.ssz + config.yaml 다운로드
   - download-testnet initContainer (wget + retry loop)
   - `deposit_contract_block.txt` 자동 생성
   - `command: lighthouse` + `args: beacon_node` (이미지 ENTRYPOINT=null)
   - JWT, Ingress + HTTPRoute 듀얼 지원

4. **JWT 시크릿 공유 구조** (완료)
   - `scripts/generate-jwt-secret.sh` 헬퍼 스크립트

5. **환경별 values 관리** (완료)
   - `environments/` 디렉토리 + ArgoCD `valueFiles` 참조

6. **E2E 테스트 스크립트** (완료)
   - `e2e/scripts/cluster.sh setup|verify|teardown`
   - `e2e/scripts/ethereum.sh deploy|verify|teardown`

7. **검증** (EL-CL 연결 확인) (완료)
   - `helm template` 렌더링: 통과
   - E2E: genesis-generator ✅, geth ✅, lighthouse ✅, EL-CL 연결 (`el_offline: false`) ✅

8. **lighthouse-validator 차트** (완료)
   - `charts/lighthouse-validator/` 별도 차트로 생성
   - `sigp/lighthouse:v8.1.3` 이미지, `lighthouse validator_client` 서브커맨드
   - lighthouse beacon node HTTP API (`http://lighthouse:5052`)로 통신
   - validator key: `lighthouse account validator recover` initContainer에서 genesis 동일 mnemonic으로 생성 (추가 이미지 불필요)
   - testnet-dir: genesis-generator에서 genesis.ssz + config.yaml wget (private network)
   - health check: TCP metrics port (validator는 HTTP API 없음, metrics 활성 시만 probe)
   - `--init-slashing-protection`: 최초 실행 시 slashing protection DB 초기화
   - 스토리지: emptyDir (devnet용, PVC 불필요)
   - mainnet은 Kubernetes Secret 외부 주입 또는 Web3Signer 연동 (Phase 3)

9. **genesis-generator genesis timestamp 수정** (완료)
   - CL config 템플릿 내부 변수명 확인: `MIN_GENESIS_TIME: $GENESIS_TIMESTAMP`
   - ConfigMap 템플릿에서 `GENESIS_TIMESTAMP`를 Helm `now | unixEpoch`로 자동 설정
   - 배포 시점 기준 slot 0부터 시작, 과거 타임스탬프로 인한 slot 밀림 방지

10. **검증** (블록 생성 확인) (완료)
    - E2E: genesis-generator ✅, geth ✅, lighthouse ✅, validator ✅
    - genesis_time 정상 (배포 시점 자동 설정) ✅
    - EL-CL 연결 (`el_offline: false`) ✅
    - 블록 생성 확인 (`eth_blockNumber > 3`, 수동 검증 통과) ✅
    - `ethereum.sh verify` 블록 체크 스크립트 수정 완료 (자동 검증 재확인 필요)

### 배포 순서

```
1. genesis-generator StatefulSet → HTTP 서버 Ready (readinessProbe 통과)
2. geth StatefulSet → initContainer wget genesis.json → geth init → Running
3. lighthouse StatefulSet → initContainer wget genesis.ssz + config.yaml → Running
4. lighthouse → geth Engine API 연결 (el_offline: false)
5. lighthouse-validator → initContainer wget genesis.ssz + config.yaml + lighthouse account recover → Running
6. lighthouse-validator → lighthouse beacon API 연결 → 블록 생성 시작
```

geth/lighthouse initContainer의 wget은 genesis-generator가 ready될 때까지 자동 retry.

### 산출물

```
charts/
├── genesis-generator/      (StatefulSet + Service: genesis 생성 → HTTP 서빙)
├── geth/                   (private network, genesis via wget, Engine API, JWT, Ingress/HTTPRoute)
├── lighthouse/             (beacon node, testnet-dir via wget, JWT, Ingress/HTTPRoute)
├── lighthouse-validator/   (validator client, lighthouse account recover key gen, beacon API, emptyDir)
└── common/                 (변경 없음)

environments/
├── private/
│   ├── genesis-generator.yaml
│   ├── geth.yaml
│   ├── lighthouse.yaml
│   └── lighthouse-validator.yaml
└── mainnet/
    └── geth.yaml

argocd/applications/
├── genesis-generator-private.yaml
├── geth.yaml
├── geth-private.yaml
├── lighthouse-private.yaml
└── lighthouse-validator-private.yaml

e2e/
├── scripts/
│   ├── cluster.sh      (setup|verify|teardown)
│   └── ethereum.sh     (deploy|verify|teardown — EL+CL+VC)
├── values/
│   ├── genesis-generator.yaml
│   ├── geth.yaml
│   ├── lighthouse.yaml
│   └── lighthouse-validator.yaml
└── README.md

scripts/
└── generate-jwt-secret.sh
```

---

## Phase 2: Testnet (Sepolia / Holesky)

### 목적

퍼블릭 테스트넷에 연결하여 실제 네트워크 환경에서 차트를 검증한다.
테스트넷은 genesis-generator가 불필요 (공식 genesis 사용).

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
Phase 1 (Private Network) — 완료
  ├─ genesis-generator (StatefulSet + HTTP 서빙, GENESIS_TIMESTAMP auto)
  ├─ geth (genesis via wget, Engine API, Ingress/HTTPRoute)
  ├─ lighthouse (testnet-dir via wget, Ingress/HTTPRoute)
  ├─ lighthouse-validator (lighthouse account recover, emptyDir, beacon API)
  ├─ JWT 시크릿 공유 구조
  ├─ environments/ + valueFiles 구조
  ├─ E2E 스크립트 (cluster.sh + ethereum.sh — EL+CL+VC)
  └─ E2E 검증 완료
       ├─ EL-CL 통신 (el_offline: false) ✅
       ├─ 블록 생성 (3초 간격) ✅
       ├─ Finality (64 validators, epoch 3 finalized) ✅
       └─ Fee recipient 설정 ✅
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

### 2026-04-08 E2E Devnet 검증 및 설정 개선

**상태**: 일시중단

#### 배경

Phase 1 최종 검증(EL-CL 통신, 블록 생성, Finality)을 위해 Kind 클러스터에 배포.
3개 컴포넌트 로그를 병렬 모니터링하여 에러 패턴을 분석하고 설정을 개선했다.

#### 발견 및 수정

| # | 이슈 | 원인 | 수정 |
|---|------|------|------|
| 1 | `ERROR Validator is missing fee recipient` | validator에 `--suggested-fee-recipient` 미설정 | e2e/private values에 `suggestedFeeRecipient: "0x...0001"` 추가 |
| 2 | Finality 미도달 (`finalized_epoch: 0` 고착) | mainnet preset(32 slots/epoch) + validator 1개 → committee 32개 중 1개만 참여 → 참여율 ~3% | validator count 1→64로 증가 (genesis-generator + lighthouse-validator) |
| 3 | 블록 시간 12초 (3초 의도) | `SLOT_DURATION_IN_SECONDS: "3"` → `SECONDS_PER_SLOT: 3`만 설정, `SLOT_DURATION_MS: 12000`은 mainnet preset 고정. Lighthouse가 `SLOT_DURATION_MS` 우선 사용 | `SLOT_DURATION_MS: "3000"` 별도 추가 |
| 4 | `mnemonics.count` 미override | e2e values에서 `NUMBER_OF_VALIDATORS: 64`는 설정했으나 `mnemonics.count`는 기본값 1 유지 | `mnemonics` 섹션 override 추가 (`count: 64`) |
| 5 | `.envrc` KUBECONFIG 경로 불일치 | `${PWD}/.kubeconfig` 참조하지만 실제 파일은 `e2e/.kubeconfig`에 존재 | KUBECONFIG 설정을 주석 처리 (사용자가 직접 설정, e2e 스크립트는 자체 관리) |
| 6 | `WARN Unknown config environment variable` (GETH_) | K8s Service `geth-e2e` → `GETH_E2E_*` 환경변수 자동 주입 → geth가 설정 플래그로 오인 | 미수정 (식별만). `enableServiceLinks: false` 추가로 해결 가능 |

#### 변경 파일

| 파일 | 변경 |
|------|------|
| `e2e/values/genesis-generator.yaml` | `NUMBER_OF_VALIDATORS: 64`, `SLOT_DURATION_MS: "3000"`, `mnemonics.count: 64` |
| `e2e/values/lighthouse-validator.yaml` | `count: 64`, `suggestedFeeRecipient` 추가 |
| `environments/private/genesis-generator.yaml` | `NUMBER_OF_VALIDATORS: 64`, `SLOT_DURATION_MS: "3000"` |
| `environments/private/lighthouse-validator.yaml` | `count: 64`, `suggestedFeeRecipient` 추가 |
| `.envrc` / `.envrc.example` | KUBECONFIG 기본값 주석 처리 |

#### 검증 결과 (수정 후)

- 블록 시간: **3초** ✅
- Active validators: **64/64** ✅
- Finality: **epoch 3 finalized** ✅
- Fee recipient ERROR: **해소** ✅
- EL-CL 통신: `el_offline: false` ✅

#### 핸드오프

- `enableServiceLinks: false` geth 차트 적용 검토
- `ethereum.sh verify` 자동 검증 스크립트에 finality 체크 추가 검토
- Phase 1 완료 후 → Phase 2 (Testnet) 진행

---

## 참고

- 각 Phase는 이전 Phase의 차트를 기반으로 values override로 확장
- 차트 자체는 모든 네트워크를 지원하도록 범용적으로 작성
- 네트워크 차이는 `environments/` 디렉토리의 values 파일에서 처리
- 엔드포인트 노출은 `ingress.type` 토글로 Ingress/HTTPRoute 선택
- 참조 프로젝트: [ethpandaops/ethereum-helm-charts](https://github.com/ethpandaops/ethereum-helm-charts), [ethpandaops/ethereum-genesis-generator](https://github.com/ethpandaops/ethereum-genesis-generator)
