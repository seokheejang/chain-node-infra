---
title: Helm 템플릿에서 외부 파일을 JSON 환경변수로 렌더링하는 패턴
date: 2026-04-09
category: tooling
related: charts/genesis-generator/templates/configmap-input.yaml, charts/genesis-generator/files/preloaded/
---

## 컨텍스트

genesis-generator chart에 인프라 컨트랙트(CREATE2 Deployer, Multicall3, ERC-1820)의 runtime bytecode를 사전 배포해야 했다. 각 bytecode는:

- CREATE2 Deployer: 69 bytes
- Multicall3: 3,808 bytes
- ERC-1820: 2,501 bytes

이걸 `ADDITIONAL_PRELOADED_CONTRACTS` 환경변수에 JSON 형식으로 넘겨야 한다:

```json
{
  "0x4e59b4...": {"balance": "0", "code": "0x7fff...", "nonce": "1"},
  "0xcA11bd...": {"balance": "0", "code": "0x6080...", "nonce": "1"},
  ...
}
```

긴 hex 문자열을 values.yaml에 인라인하면 가독성이 망가지고, 환경별 override 시 매번 복사돼서 유지보수가 어렵다.

## 내용

**해결 패턴: `.Files.Get` + `dict` 빌더 + `toJson | quote`**

### 디렉토리 구조

```
charts/<chart>/
├── files/preloaded/
│   ├── create2-deployer.hex     ← 단일 hex 문자열, 줄바꿈 없음
│   ├── multicall3.hex
│   └── erc1820-registry.hex
├── values.yaml                  ← 메타데이터만 (주소, 파일 경로)
└── templates/configmap-input.yaml
```

**중요**: hex 파일은 trailing newline이 없어야 한다. `cast code ...`의 출력을 그대로 redirect하면 newline이 들어가므로 `tr -d '\n'`로 제거하거나 `echo -n` 사용.

### values.yaml: 구조화된 메타데이터

```yaml
preloadedContracts:
  enabled: true
  contracts:
    - address: "0x4e59b44847b379578588920cA78FbF26c0B4956C"
      file: "files/preloaded/create2-deployer.hex"
      nonce: 1
    - address: "0xcA11bde05977b3631167028862bE2a173976CA11"
      file: "files/preloaded/multicall3.hex"
      nonce: 1
```

### 템플릿: dict 빌더로 JSON 객체 구성

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

### 핵심 트릭들

1. **`$root := .`** — `range` 안에서는 `.`이 변경되므로 외부 컨텍스트(`.Files`)에 접근하려면 root를 미리 캡처해야 한다.

2. **`.Files.Get path`** — chart 빌드 타임에 파일 내용을 문자열로 읽어온다. 경로는 chart root 기준 (`files/preloaded/...`).

3. **`| trim`** — hex 파일에 혹시 trailing whitespace가 있으면 JSON이 깨지므로 항상 trim.

4. **`dict` + `set`** — Go template에서 JSON 객체를 동적으로 구성. `set` 결과가 dict 자체를 반환하므로 throwaway 변수(`$_`)에 할당.

5. **`(.nonce | toString)`** — YAML 파서가 `1`을 int로 읽지만 ethereum-genesis-generator는 nonce를 문자열로 받음. 명시적 변환 필수.

6. **`lower .address`** — 주소 키를 소문자로 정규화. 일부 도구들이 case-sensitive 매칭을 함.

7. **`toJson | quote`** — `toJson`이 JSON 문자열을 만들고, `quote`가 그 전체를 큰따옴표로 감싸서 셸 환경변수로 안전하게 export. `quote`는 내부 따옴표를 자동 escape.

### 결과 (helm template 출력)

```bash
export ADDITIONAL_PRELOADED_CONTRACTS="{\"0x4e59b4...\":{\"balance\":\"0\",\"code\":\"0x7fff...\",\"nonce\":\"1\"},...}"
```

## 왜 중요한가

- **재사용성**: 같은 패턴으로 인증서, JWT secret, 큰 컨피그 파일, 컨트랙트 ABI 등을 chart에 포함시킬 수 있다.
- **values.yaml 가독성**: 메타데이터만 남고 실제 데이터는 별도 파일로 분리되어 diff/PR 리뷰가 쉬워진다.
- **환경별 override**: `enabled: false`로 통째로 끄거나 `contracts:` 배열을 환경별로 다르게 구성 가능.
- **`$root` 패턴**: `range` 안에서 `.Files`/`.Values`/`.Release` 접근은 항상 외부에서 캡처해야 한다는 게 Helm 초보자가 자주 헷갈리는 부분.
- **`toJson | quote` 콤보**: 셸로 큰 JSON을 안전하게 넘기는 사실상 표준 패턴. 직접 escape하려고 하면 backslash 지옥에 빠진다.
