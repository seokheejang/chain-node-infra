# Task 04: Devnet 운영 개선 (Premine, Ingress, Pectra, RPC API)

**날짜**: 2026-04-09
**상태**: 완료

## 배경

Task 03 (e2e EL-CL 통신 검증) 완료 이후, 컨트랙트 개발자가 mainnet/sepolia와 유사한 환경에서 devnet을 사용할 수 있도록 운영 개선이 필요했다.

핵심 요구사항:
1. 개발자가 바로 쓸 수 있는 EOA 계정과 잔액
2. 외부 도구(MetaMask, Foundry, Hardhat)에서 접근 가능한 RPC 환경
3. mainnet 최신 하드포크(Pectra) 지원
4. e2e 검증을 port-forward가 아닌 ingress 기반으로 전환

## 변경 내용

### 1. Mnemonic 기반 EOA Premine

| 파일 | 변경 |
|------|------|
| `charts/genesis-generator/values.yaml` | `EL_AND_CL_MNEMONIC`, `EL_PREMINE_COUNT=30`, `EL_PREMINE_BALANCE` 추가 |
| `environments/private/genesis-generator.yaml` | 동일 적용, 하드코딩 주소 제거 |
| `e2e/values/genesis-generator.yaml` | 동일 적용 |
| `docs/eth-devnet-premine-accounts.md` | 30개 주소/키/잔액 가이드 (Hardhat/Foundry 표준 mnemonic 사용) |

`test test test...junk` mnemonic에서 BIP-44 (`m/44'/60'/0'/0/x`)로 30개 EOA를 자동 파생, 각 1B ETH 프리펀딩.

### 2. nginx-ingress 기반 e2e 전환

| 파일 | 변경 |
|------|------|
| `e2e/kind/cluster.yaml` | extraPortMappings에 80/443 추가 |
| `e2e/scripts/cluster.sh` | nginx-ingress controller Helm 설치 단계 추가 (step 2/6), `--set-string` 사용 |
| `e2e/scripts/ethereum.sh` | port-forward 제거, ingress hostname (`*.127.0.0.1.nip.io`)로 verify |
| `e2e/values/geth.yaml` | `ingress.type: ingress` + `geth-rpc.127.0.0.1.nip.io` |
| `e2e/values/lighthouse.yaml` | `ingress.type: ingress` + `lighthouse-api.127.0.0.1.nip.io` |

### 3. Genesis chainConfig 개선

| 항목 | 변경 전 | 변경 후 | 이유 |
|------|---------|---------|------|
| `CHAIN_ID` | `32382` | `3238200` | 충돌 방지 (5자리 → 7자리) |
| `ELECTRA_FORK_EPOCH` | `max` (비활성) | `0` | Pectra 메인넷 라이브 (2025) |
| `GENESIS_GASLIMIT` | 미설정 | `60000000` | mainnet 표준 명시 |
| `TERMINAL_TOTAL_DIFFICULTY` | 미설정 | `0` | PoS from genesis 명시 |

### 4. Geth 업그레이드 (Pectra 지원)

`charts/geth/values.yaml`: `v1.14.12` → `v1.17.2` (현재 stable). Pectra(Prague) 활성화에 v1.15+ 필수.

### 5. RPC API 확장

| 파일 | 변경 |
|------|------|
| `charts/geth/values.yaml` | `httpApi`, `wsApi`, `httpCorsDomain` 신규 config 키 |
| `charts/geth/templates/statefulset.yaml` | `--http.api`, `--ws.api`, `--http.corsdomain` 플래그 추가 |
| `e2e/values/geth.yaml` | `httpApi: eth,net,web3,debug,txpool,admin`, `httpCorsDomain: *` |
| `environments/private/geth.yaml` | 동일 적용 |

추가 extraArgs:
- `--rpc.txfeecap=0` — fee cap 제거 (큰 tx 테스트)
- `--rpc.evmtimeout=0` — debug trace timeout 제거
- ~~`--rpc.gascap=0`~~ — 의도적 미적용 (mainnet과 동일하게 gas 제한 유지)

### 6. teardown PVC 정리

`e2e/scripts/ethereum.sh teardown`에 `kubectl delete pvc --all` 단계 추가. helm uninstall이 StatefulSet PVC를 삭제하지 않아 genesis 변경 시 chaindata 충돌이 발생하던 문제 해결.

## 결과

검증 완료 (e2e Kind 클러스터):

| 항목 | 결과 |
|------|------|
| Chain ID | `0x316938` = 3238200 |
| Block 생성 | 정상 (3초 슬롯) |
| EL-CL Sync | `el_offline: false`, `is_syncing: false` |
| Premine | Account #0 (`0xf39Fd6...`) 1B ETH 확인 |
| debug API | `debug_traceTransaction` 응답 OK |
| txpool API | `txpool_status` 응답 OK |
| admin API | `admin_nodeInfo` → Geth/v1.17.2 확인 |
| CORS | `Access-Control-Allow-Origin: *` 응답 |
| Ingress 접근 | `http://geth-rpc.127.0.0.1.nip.io` 정상 |

## 핸드오프

→ CHANGELOG.md에 v0.3으로 기록됨

후속 작업 후보:
- `ADDITIONAL_PRELOADED_CONTRACTS`로 인프라 컨트랙트(CREATE2 deployer, Multicall3 등) genesis 사전 배포
- Block explorer (Blockscout/Otterscan) 차트 추가
- Faucet 차트 추가
