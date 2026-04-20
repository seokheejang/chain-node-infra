# Task 07: Cosign Keyless Signing for GHCR Helm Charts

**날짜**: 2026-04-09 (착수), 2026-04-10 (완료)
**상태**: 완료 ✅

## 완료 요약 (2026-04-10)

- Phase A/B/C 모두 완료. `geth-0.1.2` 태그로 end-to-end 검증 통과.
- **Positive**: `cosign verify ghcr.io/seokheejang/chain-node-infra/geth:0.1.2` → Subject=`release.yaml@refs/tags/geth-0.1.2`, Issuer=GitHub OIDC, Rekor logIndex `1271237772`.
- **Negative**: 잘못된 identity regex, unsigned `geth:0.1.0`/`geth:0.1.1` 모두 정상 reject.
- **예상치 못한 이슈** — 첫 시도(`geth-0.1.1`)가 서명 push 단계에서 401로 실패. 원인: `helm registry login`과 `cosign`이 서로 다른 credential store 사용. 해결: `docker/login-action@v3`으로 교체 (`~/.docker/config.json`을 helm v3 OCI fallback과 cosign이 공유). 상세: [docs/learnings/cosign-helm-registry-login-credential-store.md](../learnings/cosign-helm-registry-login-credential-store.md).
- **부작용**: `geth:0.1.1`이 unsigned orphan으로 GHCR에 영구히 남음 (OCI immutable). README에 "`geth 0.1.2+` signed"로 명시.

---

## 배경

Task-06에서 5개 chart를 GHCR에 publish하는 것까지 끝났고 public + 익명 pull도 동작 중. 다음 단계는 "받은 chart가 정말 이 저장소에서 나온 것이 맞는가" 라는 **출처 진위 (authenticity)** 검증.

현재 위험:

- 누군가 GHCR 인증을 탈취해 `geth-0.1.1` 태그에 악성 chart를 push하면 소비자가 알 방법 없음 — public이라 누구나 받지만 위변조를 검증할 수단이 없음
- "이 chart는 정말 `seokheejang/chain-node-infra`의 release workflow에서 빌드됐는가" 를 cryptographically 증명할 방법이 없음

해결: **Sigstore Cosign keyless signing**을 release workflow에 추가하고 README에 verify 절차를 문서화. 회사 측에서는 chart pull 전 `cosign verify`로 출처 검증, 더 나아가 admission webhook으로 서명 없는 chart 차단 가능.

## "내 사인 정보를 넣는다" 가 아니다

흔한 오해: "키 만들어서 GitHub Secret에 넣고 workflow에서 unlock" — 이건 옛날 long-lived key 모델. 이 task는 그게 **아님**.

| 옛날 모델 (long-lived key) | Keyless 모델 (이 task) |
|---|---|
| 개인키 생성 → GitHub Secret에 저장 → workflow에서 unlock해서 서명 | 키 자체가 없음 |
| 키 회전·유출 관리 부담 | 관리할 게 없음 |
| 검증자가 공개키를 어디서 받아야 함 | 검증자가 GitHub Actions OIDC 발급자만 신뢰하면 됨 |

### Keyless 동작 흐름

1. `release.yaml` workflow가 실행되면 GitHub Actions가 자동으로 **OIDC ID Token**을 발급. 이 token에는 "이 token은 `seokheejang/chain-node-infra`의 `release.yaml@refs/tags/geth-0.1.1` workflow에서 발급되었다"는 claim이 들어있음.
2. cosign이 이 OIDC token을 Sigstore의 **Fulcio CA**에 보내면 Fulcio가 그 claim을 기반으로 **단기(10분짜리) X.509 인증서**를 발급. 인증서의 SAN(Subject Alternative Name)에 workflow file 경로가 박힘.
3. cosign이 임시 keypair를 생성해서 chart artifact를 서명하고, 서명 + Fulcio 인증서를 OCI 레지스트리(GHCR)에 함께 push. 그 직후 **임시 keypair는 폐기** (메모리에서 사라짐).
4. 서명 사실이 **Sigstore Rekor (transparency log)** 에 영구 기록 → 누구든 audit 가능.

검증자는:

```bash
cosign verify ghcr.io/seokheejang/chain-node-infra/geth:0.1.1 \
  --certificate-identity-regexp '^https://github\.com/seokheejang/chain-node-infra/\.github/workflows/release\.yaml@.*$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

→ "이 artifact는 정확히 `seokheejang/chain-node-infra`의 `release.yaml`에서 GitHub Actions OIDC를 통해 서명된 게 맞다" 가 검증되면 OK.

**즉, workflow에 추가되는 작업은 "OIDC 권한 + cosign sign 명령어"가 전부.** 키 관리, 시크릿 추가, 인증서 갱신 모두 0.

## 결정 사항

| 주제 | 결정 | 근거 |
|---|---|---|
| 서명 방식 | **Keyless (Sigstore Fulcio + GitHub OIDC)** | 키 관리 0, 검증 trust가 GitHub Actions identity에 anchored |
| 서명 대상 | **digest 기반** (`chart@sha256:...`) | tag는 mutable. digest는 immutable artifact를 정확히 핀 |
| Cosign 버전 | `sigstore/cosign-installer@v3` | active maintenance, Cosign 2.x default |
| 적용 범위 | **0.1.1부터** | 0.1.0은 task-07 이전 publish. 재서명은 immutability 흐려짐 |
| 멱등성 | publish skip 시 sign도 skip | 서명은 publish와 1:1 |
| Admission 강제 | OSS 범위 외 | README에 Kyverno/Connaisseur 포인터만 |
| Provenance attestation | task-08로 분리 | SLSA 별도 표준 |

## 작업 계획

### Phase A — release.yaml 수정

`.github/workflows/release.yaml` 에 3가지 변경:

1. `permissions:` 에 `id-token: write` 추가 (Sigstore OIDC)
2. `Set up Helm` 다음에 `Install Cosign` step 추가 (`sigstore/cosign-installer@v3`)
3. "Package and push" step을 "Package, push and sign" 으로 교체 — `helm push` 출력에서 digest 파싱 → `cosign sign --yes <chart>@<digest>` 호출

### Phase B — README "Verify before install" 섹션 추가

`Use in Other Projects` 섹션의 "Pattern 1: helm CLI" 위에 `cosign verify` 명령어 + `certificate-identity-regexp` 패턴 + admission webhook 옵션 (Kyverno/Connaisseur) 안내.

### Phase C — 검증

1. 새 버전 bump (예: `geth-0.1.1`) → tag push → workflow 트리거
2. Workflow 로그에서 "Signing ghcr.io/.../geth@sha256:..." 출력 + Fulcio 인증서 발급 + Rekor entry 확인
3. GHCR 패키지 페이지에서 `geth` 패키지에 `sha256-<digest>.sig` artifact 추가 확인
4. 로컬에서 `cosign verify` → "Verified OK" 출력 확인
5. **Negative test**: identity regex를 일부러 다른 repo로 바꿔서 → fail 확인 (origin 강제가 실제로 동작)
6. 0.1.0 (서명 없음) verify 시도 → fail 확인 (정상)

## 변경 대상 파일

| 파일 | 변경 |
|---|---|
| `.github/workflows/release.yaml` | `id-token: write` 추가, cosign installer step 추가, push 루프에 sign 통합 |
| `README.md` | "Verify before install" 섹션 추가 |
| `docs/CHANGELOG.md` | v0.6 entry 추가 |

신규 파일 없음 (이 task 문서 제외).

## 비목표 (명시적)

- 기존 0.1.0 chart 재서명 — immutability 흐려짐. "0.1.1+ are signed" 로 README 명시
- Provenance attestation (`actions/attest-build-provenance`) — task-08로 분리
- Admission webhook (Kyverno/Connaisseur) 셋업 — 회사 측 작업이라 OSS repo 범위 외. README에 포인터만
- 회사 측 PAT 기반 private GHCR pull 가이드 — 본 task는 public 모델 가정
- 키 기반 (long-lived key) signing 옵션 — 명시적으로 채택 안 함
