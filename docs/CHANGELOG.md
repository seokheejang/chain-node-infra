# CHANGELOG

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
