# CHANGELOG

## v0.7 -- Post-Release GitOps Drift & Correctness Fixes (2026-04-17)

- [task-08-gitops-drift-fixes.md](archive/task-08-gitops-drift-fixes.md) 작업 문서
- geth: `gcMode: archive` first boot Fatal 수정 — init container에도 `--state.scheme=hash` 를 명시해 main container와 scheme 일치. `full` 모드에서도 명시적으로 `--state.scheme=path` 넘김. Chart: `0.1.3 → 0.1.4`
- charts: StatefulSet `volumeClaimTemplates` 3개(geth/lighthouse/genesis-generator)에 `apiVersion: v1` + `kind: PersistentVolumeClaim` 명시 — k8s API defaulting 값과 일치시켜 ArgoCD OutOfSync 루프 제거. 소비자 측 `ignoreDifferences` 워크어라운드 불필요. Chart: `geth 0.1.2→0.1.3`, `genesis-generator 0.1.0→0.1.1`, `lighthouse 0.1.0→0.1.1`
- genesis-generator: `GENESIS_TIMESTAMP` 를 매 render마다 `now | unixEpoch` 로 덮어쓰던 동작을 sentinel(`""`/`"0"`) 경로로 제한. 명시값은 그대로 보존 → deterministic render, ArgoCD ConfigMap drift/롤링 재시작 루프 해소. Chart: `0.1.1 → 0.1.2`
- 학습: [geth-gcmode-state-scheme.md](learnings/geth-gcmode-state-scheme.md) init/main scheme 쌍 일치 섹션 추가, [gitops-drift.md](learnings/gitops-drift.md) 신규 (volumeClaimTemplates defaulting, 비결정적 template)
- 비목표(분리): 소비자 쪽 umbrella chart 버전 bump 및 `ignoreDifferences` 제거 — 소비자 repo 작업

## v0.6 -- Cosign Keyless Signing for GHCR Charts (2026-04-10)

- [task-07-cosign-signing.md](archive/task-07-cosign-signing.md) 작업 문서
- release workflow: Sigstore Cosign keyless signing 통합 (GitHub Actions OIDC + Fulcio + Rekor)
  - `permissions: id-token: write` 추가, `sigstore/cosign-installer@v3` step 추가
  - `helm push` 출력에서 digest 파싱 → `cosign sign --yes <chart>@<digest>` (immutable digest 기반)
  - 관리할 키 없음: 검증 trust는 workflow identity(`release.yaml@refs/tags/<chart>-*`)에 anchored
- README: "Verify before install" 섹션 추가 — `cosign verify` 명령어 + `certificate-identity-regexp` 패턴 + Kyverno/Connaisseur 포인터
- login: `helm registry login` → `docker/login-action@v3` 교체 — helm 전용 credential store는 cosign이 못 읽어 서명 push가 UNAUTHORIZED로 실패. docker login이 쓰는 `~/.docker/config.json`은 helm v3 OCI + cosign 둘 다 fallback으로 읽음
- 적용 범위: `geth 0.1.2` 이후 서명 (0.1.0과 0.1.1은 unsigned — 0.1.1은 위 auth 이슈로 서명 실패한 상태로 publish됨, OCI immutable이라 사후 서명 불가)
- 검증: `geth-0.1.2` 태그로 end-to-end — Fulcio 인증서 발급, Rekor entry, `cosign verify` OK, negative test(잘못된 identity regex / unsigned 0.1.0) fail 확인
- 비목표(분리): SLSA provenance attestation → task-08, admission webhook 셋업은 consumer 측 작업

## v0.5 -- GHCR(OCI) Helm Chart Publishing (2026-04-09)

- [task-06-ghcr-publishing.md](archive/task-06-ghcr-publishing.md) 작업 문서
- 5개 chart를 GHCR OCI 레지스트리로 publish (`ghcr.io/seokheejang/chain-node-infra/<chart>`, 패턴 C)
  - `common`, `geth`, `lighthouse`, `lighthouse-validator`, `genesis-generator` v0.1.0 — 모두 public, 익명 pull 가능
- workflow: tag 트리거(`<chart>-<semver>`) + raw helm CLI + 멱등성(`helm show chart` 사전 체크)
  - 기존 `chart-releaser-action` (gh-pages) 제거, OCI 단일 채널로 단순화
  - tag-Chart.yaml version 일치 검증 step 포함
- chart: 5개 `Chart.yaml`에 OCI annotation 추가 (`source`/`licenses`/`description`)
- chart: 4개 app chart의 `common` 의존성을 `file://../common` → `oci://ghcr.io/...`로 전환 (immutability 보장)
- argocd: 5개 Application을 git path 단일 source → OCI multi-source(chart=OCI, values=`$values` ref)로 전환 (자기 dog food)
- README: "Use in Other Projects" 섹션 추가 — helm CLI / ArgoCD multi-source / internal registry mirroring(`oras copy`) 3패턴 + maintainer release 절차
- 검증: 5회 workflow 모두 success, OCI render == 로컬 render byte 일치, `common` 4번 fetch 동일 digest
- 비목표(분리): cosign signing → task-07 예정

## v0.4 -- 인프라 컨트랙트 사전 배포 (2026-04-09)

- [task-05-infra-contracts.md](archive/task-05-infra-contracts.md) 작업 문서
- genesis-generator: `ADDITIONAL_PRELOADED_CONTRACTS`로 mainnet 인프라 컨트랙트 3개 사전 배포
  - CREATE2 Deployer (`0x4e59b44...4956C`) — Foundry/Hardhat deterministic deploy
  - Multicall3 (`0xcA11bde0...CA11`) — viem/ethers/wagmi 자동 호출
  - ERC-1820 Registry (`0x1820a4B7...fAD24`) — ERC-777/1155 인터페이스 레지스트리
- chart: `files/preloaded/*.hex`에 runtime bytecode 분리 저장 + `.Files.Get` 패턴
- chart: `preloadedContracts.enabled` flag로 통째 비활성 가능
- 검증: `eth_getCode` 3개 모두 OK, Multicall3 `getCurrentBlockTimestamp/getEthBalance/getChainId` 정상 동작

## v0.3 -- Devnet 운영 개선: Premine, Ingress, Pectra, RPC API (2026-04-09)

- [task-04-devnet-improvements.md](archive/task-04-devnet-improvements.md) 작업 문서
- genesis-generator: mnemonic 기반 30개 EOA 자동 premine (`EL_PREMINE_COUNT`)
- genesis: Pectra(Electra) fork epoch 0 활성화, `GENESIS_GASLIMIT`/`TERMINAL_TOTAL_DIFFICULTY` 명시
- geth: v1.14.12 → v1.17.2 (Pectra 지원), httpApi/wsApi/httpCorsDomain config 추가
- geth: debug/txpool/admin RPC namespace 노출, `--rpc.txfeecap=0`/`--rpc.evmtimeout=0`
- e2e: port-forward → nginx-ingress 기반 verify (`*.127.0.0.1.nip.io`)
- e2e: Kind cluster.yaml에 80/443 포트, cluster.sh에 nginx-ingress 설치 단계
- e2e: teardown에 PVC 삭제 단계 추가 (genesis 변경 시 chaindata 충돌 해결)
- CHAIN_ID: 32382 → 3238200 (충돌 방지)
- 신규 가이드: [eth-devnet-premine-accounts.md](eth-devnet-premine-accounts.md) 30개 주소/키 표

## v0.2 -- gcMode, Ingress Convention, PVC Sizing (2026-04-09)

- [task-02-ethereum-charts.md](archive/task-02-ethereum-charts.md) 작업 문서
- geth: gcMode (full/archive) + state.scheme 자동 유도 추가
- lighthouse: archiveMode + --reconstruct-historic-states 플래그 추가
- Ingress: per-port hostname 듀얼 포맷 (string + structured, nip.io 컨벤션)
- PVC: 네트워크×모드별 권장 사이즈 가이드 주석
- Environments: 3-tier 구조 (mainnet/testnet/private), sepolia 추가

## v0.1 -- Phase 1 Private Network (2026-04-08)

- [task-02-ethereum-charts.md](archive/task-02-ethereum-charts.md) 작업 문서
- genesis-generator: StatefulSet + HTTP 서빙, GENESIS_TIMESTAMP auto
- geth: genesis via wget, Engine API, JWT, Ingress/HTTPRoute
- lighthouse: beacon node, testnet-dir via wget, JWT, Ingress/HTTPRoute
- lighthouse-validator: lighthouse account recover, emptyDir, beacon API
- E2E: cluster.sh + ethereum.sh 통합 스크립트
- Devnet 검증: 3초 블록, 64 validators, finality 정상, fee recipient 설정
