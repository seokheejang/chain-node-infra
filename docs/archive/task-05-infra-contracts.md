# Task 05: 인프라 컨트랙트 사전 배포

**날짜**: 2026-04-09
**상태**: 완료

## 배경

Task 04(devnet 운영 개선) 이후, 컨트랙트 개발자가 mainnet과 동일한 환경에서 작업하려면 "메인넷에 이미 배포되어 있다고 가정되는" 인프라 컨트랙트들이 devnet에도 같은 주소에 존재해야 한다.

| 도구 | 자동 호출하는 컨트랙트 |
|------|---------------------|
| Foundry `forge create2` | CREATE2 Deployer (`0x4e59...4956C`) |
| Hardhat deterministic deploy | CREATE2 Deployer |
| viem / ethers / wagmi `multicall` | Multicall3 (`0xcA11...CA11`) |
| ERC-777 / 일부 ERC-1155 | ERC-1820 Registry (`0x1820...fAD24`) |

이들이 없으면 `forge script` 배포 실패, viem batched read 실패, ERC-777 토큰 전송 실패 등이 발생한다.

ethpandaops/ethereum-genesis-generator의 `ADDITIONAL_PRELOADED_CONTRACTS` 환경변수가 mnemonic premine과 **머지**되므로 기존 EOA 30개와 충돌 없이 추가 가능하다.

## 변경 내용

| 파일 | 변경 |
|------|------|
| `charts/genesis-generator/files/preloaded/create2-deployer.hex` | 신규 (69 bytes runtime bytecode) |
| `charts/genesis-generator/files/preloaded/multicall3.hex` | 신규 (3,808 bytes) |
| `charts/genesis-generator/files/preloaded/erc1820-registry.hex` | 신규 (2,501 bytes) |
| `charts/genesis-generator/values.yaml` | `preloadedContracts` 섹션 추가 (enabled flag + contract list) |
| `charts/genesis-generator/templates/configmap-input.yaml` | `.Files.Get` + dict 빌더로 `ADDITIONAL_PRELOADED_CONTRACTS` JSON 렌더링 |

### 1. Bytecode 수집

각 컨트랙트의 runtime bytecode를 mainnet에서 직접 가져와 검증:

```bash
cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url https://ethereum-rpc.publicnode.com
cast code 0xcA11bde05977b3631167028862bE2a173976CA11 --rpc-url https://ethereum-rpc.publicnode.com
cast code 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24 --rpc-url https://ethereum-rpc.publicnode.com
```

각 결과를 `0x` 접두사 포함, 줄바꿈 없는 단일 hex 문자열로 `files/preloaded/*.hex`에 저장.

### 2. values.yaml 구조

```yaml
preloadedContracts:
  enabled: true
  contracts:
    - address: "0x4e59b44847b379578588920cA78FbF26c0B4956C"
      name: "create2-deployer"
      file: "files/preloaded/create2-deployer.hex"
      nonce: 1
    - address: "0xcA11bde05977b3631167028862bE2a173976CA11"
      name: "multicall3"
      file: "files/preloaded/multicall3.hex"
      nonce: 1
    - address: "0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24"
      name: "erc1820-registry"
      file: "files/preloaded/erc1820-registry.hex"
      nonce: 1
```

`enabled: false`로 통째로 비활성화 가능 (non-EVM 체인 또는 "missing infra" 시나리오 테스트).

### 3. configmap-input.yaml 렌더링 로직

기존 `range chainConfig` 다음에 conditional 블록 추가:

```yaml
{{- if .Values.preloadedContracts.enabled }}
{{- $root := . }}
{{- $contracts := dict }}
{{- range .Values.preloadedContracts.contracts }}
{{- $code := $root.Files.Get .file | trim }}
{{- $entry := dict "balance" "0" "code" $code "nonce" (.nonce | toString) }}
{{- $_ := set $contracts (lower .address) $entry }}
{{- end }}
export ADDITIONAL_PRELOADED_CONTRACTS={{ $contracts | toJson | quote }}
{{- end }}
```

핵심:
- `.Files.Get`으로 hex 파일 내용을 chart 빌드 타임에 읽음
- `dict` 빌더로 JSON 객체 구성
- `lower .address`로 주소를 소문자로 정규화 (genesis-generator가 소문자 키를 기대)
- `toJson | quote`로 환경변수 안전하게 export

## 결과

검증 완료 (e2e Kind 클러스터):

```
=== Preloaded contracts code check ===
[OK]   CREATE2-Deployer @ 0x4e59b44847b379578588920cA78FbF26c0B4956C — bytecode size: 69 bytes
[OK]   Multicall3       @ 0xcA11bde05977b3631167028862bE2a173976CA11 — bytecode size: 3808 bytes
[OK]   ERC-1820         @ 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24 — bytecode size: 2501 bytes

=== Multicall3.getCurrentBlockTimestamp() ===
1775720328

=== Multicall3.getEthBalance(0xf39Fd6...) ===
1000000000000000000000000000   (1B ETH, premine 잔액과 일치)

=== Multicall3.getChainId() ===
3238200   (devnet chain ID와 일치)

=== ERC-1820 getManager(0xf39Fd6...) ===
0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266   (EIP-1820 스펙: 미등록 주소는 자기 자신 반환)
```

세 컨트랙트 모두:
1. genesis에 코드가 박힘 ✓
2. 외부에서 호출 가능 ✓
3. 실제 EVM 컨텍스트(block, balance, chain id) 접근 ✓
4. 각자의 표준 동작 정상 ✓

## 핸드오프

→ CHANGELOG.md에 v0.4로 기록 예정

후속 작업 후보:
- Block Explorer (Ethernal vs Blockscout 결정 후)
- Faucet 차트
- 인프라 컨트랙트 추가 후보: Permit2 (`0x000000000022D473030F116dDEE9F6B43aC78BA3`), EntryPoint v0.7 (ERC-4337)
