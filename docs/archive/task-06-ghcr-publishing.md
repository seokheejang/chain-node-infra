# Task 06: GHCR(OCI) Helm Chart Publishing

**날짜**: 2026-04-09
**상태**: 완료
**최종 갱신**: 2026-04-09 (Phase A~D 실행 완료, Phase E 후속 작업 적용)

## 작업 결과 요약

- 5개 chart 모두 `ghcr.io/seokheejang/chain-node-infra/<chart>` 경로로 GHCR 첫 publish 성공 (`common`, `geth`, `lighthouse`, `lighthouse-validator`, `genesis-generator` v0.1.0)
- Tag 트리거 workflow 5회 모두 success (17~30초). 멱등성 로직 정상 동작 확인
- 익명 pull 검증 — GHCR이 source repo public 가시성을 자동 승계, 수동 public 전환 불필요
- `helm template`로 OCI fetch 결과와 로컬 source 렌더 결과가 byte-level 일치 (Pulled/Digest 메타 라인 제외)
- Phase E 후속 작업 함께 완료:
  - `common` 의존성을 4개 app chart에서 `file://../common` → `oci://ghcr.io/seokheejang/chain-node-infra` 로 전환. 4번 fetch 모두 동일 digest (`sha256:9779a7...`) — immutability 검증
  - `argocd/applications/*.yaml` 5개를 git path 단일 source → OCI multi-source(chart는 OCI, values는 `$values` ref)로 전환. 자기 dog food
  - `README.md`에 "Use in Other Projects" 섹션 추가 (helm CLI / ArgoCD multi-source / internal mirroring 3패턴 + release 절차)
- 미수행 비목표: cosign signing → task-07로 분리 예정

## 배경

이 저장소(`chain-node-infra`)를 회사 사내 private GitHub 저장소에서 사용해야 하는 상황. 회사 정책상 fork·공유가 불가능하고, 개인 OSS 저장소와 회사 저장소 사이에 코드를 옮겨 다닐 방법이 마땅치 않다.

이전 검토에서 cherry-pick 방식이 후보로 거론됐지만, 양방향 수동 동기화는 운영 부담이 크고 회사 측 작업이 OSS에 새는 사고 위험도 존재한다. 더 근본적으로, 이 저장소를 **공용 Helm chart 저장소**로 키우려는 큰 그림과도 맞지 않는다.

목표는 다음 원칙을 만족하는 배포 모델을 정착시키는 것:

1. **OSS 저장소가 chart 코드의 single source of truth** — 모든 chart 변경은 여기서만 일어난다.
2. **회사 private 저장소는 values + ArgoCD Application 매니페스트만 보유** — chart 코드는 1줄도 복사하지 않는다.
3. **버전 핀(version pin)이 가능해야 한다** — git `main` 추적이 아니라 `0.1.3` 같은 불변 태그.
4. **외부 인증·시크릿 없이 동작** — 누구든 clone 후 즉시 사용 가능해야 OSS답다.

이를 충족하는 가장 깔끔한 방법은 **Helm chart를 OCI 레지스트리(GHCR)에 publish**하는 것이다.

## 현재 상태 (탐색 결과)

| 항목 | 현재 |
|------|------|
| Release workflow | `.github/workflows/release.yaml` — chart-releaser로 gh-pages에 traditional Helm repo만 publish |
| Chart 목록 | `geth`, `lighthouse`, `lighthouse-validator`, `genesis-generator` (application) + `common` (library) |
| Chart 버전 | 모두 `0.1.0` (아직 release 한 적 없음) |
| `common` 의존성 | `file://../common` (로컬 path 의존) |
| ArgoCD Application 참조 방식 | git path (`repoURL: github.com/.../chain-node-infra.git`, `path: charts/geth`) — 소비자가 저장소를 통째로 알아야 하는 강결합 |
| 시크릿/엔드포인트 누출 | 없음. `.gitignore`에 `.env*`, `kubeconfig`, `*.pem`, `*.key`, `credentials.json` 포함. JWT는 templated. |

## 결정 사항

| 주제 | 결정 | 근거 |
|------|------|------|
| 레지스트리 | **GHCR** | GitHub 계정과 통합, public 패키지 무료, 별도 가입 불필요 |
| OCI 경로 패턴 | **`ghcr.io/seokheejang/chain-node-infra/<chart>`** (패턴 C: repo 이름을 prefix로) | 한 계정에 여러 chart 프로젝트 공존 시 표준 컨벤션. 패키지 페이지 그루핑 깔끔, source repo 자동 링킹 안정. CNCF/community 프로젝트 다수 사용 |
| 가시성 | **Public** | 무료, 인증 없이 pull 가능, 회사 측 ArgoCD 설정 단순 |
| 인증 (CI) | `GITHUB_TOKEN` + `permissions: packages: write` | PAT 발급/관리 불필요 |
| **트리거 방식** | **Git tag push** (`<chart>-<version>`, 예: `geth-0.1.1`) | `main` 자유롭게 작업하면서도 release 시점을 명시적으로 결정. tag = 의도적 release. semver 강제 |
| **Tag 명명 컨벤션** | `<chart-name>-<semver>` per-chart (예: `geth-0.1.0`, `lighthouse-0.1.2`) | chart-releaser action의 GitHub Release 네이밍과 동일 → 컨벤션 일관성. chart 하나만 hotfix 가능 (lockstep 회피) |
| **chart-releaser와의 관계** | **즉시 제거** — 본 task에서 workflow에서 삭제 | 한 번도 release 한 적 없어 legacy 호환성 부담 0. gh-pages 출력 채널 단순화. 업계 추세도 OCI 단방향 이동 (ACR 2025-03, Bitnami 2025-09) |
| Workflow 도구 | **raw helm CLI** (`helm package` + `helm push`) | 의존성 0, `charts/*` glob 자동 발견, chart 추가 시 workflow 수정 불필요. 대안 `appany/helm-oci-chart-releaser@v0.5.0` (matrix 기반)도 검증됨 — 필요 시 swap |
| 멱등성 처리 | `helm show chart` 사전 체크로 이미 publish된 버전은 skip | 5개 chart 모두 package해도 신규 버전만 push됨. 태그 이름과 실제 publish 결과가 자연스럽게 일치 |
| `common` 라이브러리 chart | 동일하게 GHCR push | dependency 해소를 위해 필요. standalone 설치는 안 되지만 push는 가능 |
| OCI annotation | 각 `Chart.yaml`에 `org.opencontainers.image.source` 등 추가 | GHCR 패키지 페이지에서 source repo 자동 링킹, 라이선스/설명 노출 |
| 버전 정책 | `Chart.yaml` version 변경 → 동일 버전 tag push 시에만 publish | 불변성 보장, 실수 방지, 명시적 release 행위 강제 |
| 첫 publish 버전 | `0.1.0` 그대로 (smoke test) | 별도 작업 불필요 |

## 작업 계획

### Phase A — GHCR 사전 준비 (1회성, github.com 수동)

1. 별도 계정 생성 불필요 — 기존 `seokheejang` 계정 그대로 사용.
2. CI에서 첫 `helm push`가 성공하면 패키지가 자동 생성되며 기본 가시성은 **private**.
3. 첫 publish 후 각 패키지를 수동으로 public 전환:
   - `https://github.com/users/seokheejang/packages/container/chain-node-infra%2F<chart>`
   - Package settings → "Change visibility" → **Public**
   - 대상: `chain-node-infra/geth`, `chain-node-infra/lighthouse`, `chain-node-infra/lighthouse-validator`, `chain-node-infra/genesis-generator`, `chain-node-infra/common` (총 5개)
4. (권장) 각 패키지 페이지 → "Manage Actions access" → `chain-node-infra` 저장소에 write 권한 명시 부여. 후속 push 시 권한 문제 방지. (단, `Chart.yaml`에 `org.opencontainers.image.source` annotation을 박으면 GHCR이 자동 링킹하므로 보통 수동 설정 불필요.)

### Phase B — Release workflow 전면 교체

대상 파일: `.github/workflows/release.yaml`

**핵심 변경**: 트리거를 `push: branches: main` → `push: tags`로 전환하고, `helm/chart-releaser-action` step을 완전히 제거. OCI publish가 유일한 출력 채널이 됨.

#### 운영 흐름

```bash
# 1. main에서 자유롭게 작업 (트리거 안 됨)
vim charts/geth/values.yaml
git commit -am "feat(geth): tweak resources" && git push

# 2. release 결정 시 — Chart.yaml version bump 후 태그 push
vim charts/geth/Chart.yaml                    # version: 0.1.0 → 0.1.1
git commit -am "chore(geth): bump to 0.1.1" && git push

git tag geth-0.1.1
git push origin geth-0.1.1                    # ← 여기서 workflow 트리거
```

멱등성 로직 덕분에 workflow가 5개 chart를 모두 package해도 **이미 publish된 4개는 skip, `geth-0.1.1`만 GHCR에 push**됨. 태그 이름과 실제 publish 결과가 자연스럽게 일치.

#### 변경 내용

1. **트리거 교체**: `push: branches: main` → `push: tags: ['*-[0-9]+.[0-9]+.[0-9]+']`
2. **chart-releaser action step 삭제**: gh-pages 출력 채널 폐기 (release 한 적 없어 legacy 부담 0)
3. `permissions:`에서 `contents: write` 제거, **`packages: write` 만** 부여 (gh-pages 안 쓰므로)
4. `helm registry login ghcr.io` step 추가 (`${{ github.actor }}` + `${{ secrets.GITHUB_TOKEN }}`)
5. 각 chart packaging + OCI push 루프 — `oci://ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}`로 경로 자동 조합 (하드코딩 없음)
6. 멱등성: `helm show chart` 사전 체크로 이미 publish된 버전은 skip. 첫 release는 자연스럽게 404 → push 진행.
7. `common` 의존성: 현재 `file://../common`이므로 app chart packaging 전에 `helm dependency update`로 로컬 번들. Phase E에서 OCI 의존성으로 전환.
8. 각 chart의 `Chart.yaml`에 OCI annotation 추가:
   ```yaml
   annotations:
     org.opencontainers.image.source: https://github.com/seokheejang/chain-node-infra
     org.opencontainers.image.licenses: Apache-2.0
     org.opencontainers.image.description: <chart 한 줄 설명>
   ```
   GHCR 패키지 페이지에서 source repo 자동 링크 노출.

#### 전체 workflow 스케치

```yaml
name: Release Charts

on:
  push:
    tags:
      - '*-[0-9]+.[0-9]+.[0-9]+'        # e.g. geth-0.1.1, lighthouse-0.2.0

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      packages: write                    # GHCR push 만 필요
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Log in to GHCR
        run: |
          echo "${{ secrets.GITHUB_TOKEN }}" \
            | helm registry login ghcr.io -u ${{ github.actor }} --password-stdin

      - name: Package and push charts to GHCR
        env:
          OCI_REPO: oci://ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}
        run: |
          mkdir -p .release-packages
          for chart in charts/*/; do
            helm dependency update "$chart"
            helm package "$chart" -d .release-packages
          done
          for tgz in .release-packages/*.tgz; do
            name=$(basename "$tgz" .tgz)        # e.g. geth-0.1.1
            chart_name="${name%-*}"
            version="${name##*-}"
            # idempotency: skip if version already exists on GHCR
            if helm show chart "${OCI_REPO}/${chart_name}" --version "${version}" >/dev/null 2>&1; then
              echo "skip: ${chart_name}@${version} already published"
              continue
            fi
            echo "push: ${chart_name}@${version}"
            helm push "$tgz" "$OCI_REPO"
          done
```

#### Tag 검증 (선택)

태그 이름과 `Chart.yaml` 버전이 일치하는지 첫 step에서 명시적으로 확인할 수도 있음:

```yaml
- name: Validate tag matches Chart.yaml version
  run: |
    tag="${GITHUB_REF#refs/tags/}"           # e.g. geth-0.1.1
    chart_name="${tag%-*}"
    tag_version="${tag##*-}"
    chart_version=$(yq '.version' "charts/${chart_name}/Chart.yaml")
    if [ "$tag_version" != "$chart_version" ]; then
      echo "ERROR: tag version ($tag_version) != Chart.yaml version ($chart_version)"
      exit 1
    fi
```

→ "태그 잘못 달았는데 publish됨" 사고 방지. 첫 release 후 추가 권장.

**대안 (참고)**: `appany/helm-oci-chart-releaser@v0.5.0` matrix 기반 사용 가능. 다만 chart 추가 시 matrix 정적 수정 필요해 현재 raw helm CLI 방식이 더 단순. 차후 bash 루프가 복잡해지면 swap 검토.

### Phase C — 보안 체크리스트 (tag push 전 필수)

태그 push = 즉시 publish이므로 **태그 달기 직전에** 확인:

1. 모든 `values.yaml` 및 `ci/default-values.yaml`에서 다음을 grep:
   - 하드코딩된 IP, 내부 호스트명, 실제 fee recipient, 실제 validator pubkey
   - non-empty `jwt.secret`, TLS cert, mnemonic, private key
2. `git grep -iE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|mnemonic|secretKey|0x[a-f0-9]{40}'` — 마지막 sanity sweep.
3. `.envrc`가 template-only인지 재확인.
4. workflow `permissions`은 **`packages: write`만** — 그 이상 절대 부여 금지 (chart-releaser 제거 후 `contents: write` 불필요).
5. (선택) `actions/checkout`, `azure/setup-helm`을 SHA로 핀 — supply-chain 위생.
6. 첫 publish는 `0.1.0`으로 smoke test 성격. 무언가 잘못되면 GHCR 패키지 페이지에서 해당 버전 즉시 삭제 가능.
7. **태그 push는 force-push 금지** — 한 번 publish된 OCI 버전은 immutable. 같은 태그 재사용 금지.

### Phase D — 소비 패턴 (문서화 대상)

#### 패턴 1: Public 소비자 (누구나, OSS 예시 포함)

```bash
helm pull oci://ghcr.io/seokheejang/chain-node-infra/geth --version 0.1.0
helm install my-geth oci://ghcr.io/seokheejang/chain-node-infra/geth --version 0.1.0 -f my-values.yaml
```

인증 없음. 회사 외 어떤 사용자도 동일하게 사용 가능.

**Production-grade 운영 권장: internal registry mirroring** — 외부 OCI 의존을 피하려면 회사 내부 ECR/Harbor/Nexus에 미러링:

```bash
# oras 사용 예 (binary diff 없이 manifest+blob 단순 복사)
oras copy ghcr.io/seokheejang/chain-node-infra/geth:0.1.0 \
  <internal-registry>/helm/chain-node-infra/geth:0.1.0
```

OSS 저장소가 사라지거나 GHCR 장애 시 안정성 확보. 회사 README에 미러링 절차를 명시하는 것을 권장.

#### 패턴 2: 회사 private 저장소 — ArgoCD multi-source

회사 private repo는 chart 코드 없이 다음만 보유:

```
company-infra/                  # private GitHub repo
├── argocd/
│   └── applications/
│       └── geth-mainnet.yaml
└── values/
    └── geth-mainnet.yaml       # 회사 전용 override
```

`geth-mainnet.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: geth-mainnet
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: ghcr.io/seokheejang/chain-node-infra        # OCI registry (스킴 없이)
      chart: geth
      targetRevision: 0.1.0                       # 불변 버전 핀
      helm:
        valueFiles:
          - $values/values/geth-mainnet.yaml
    - repoURL: git@github.com:company/company-infra.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: ethereum
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

ArgoCD ≥ 2.7부터 OCI Helm source 네이티브 지원. 회사가 얻는 이점:

- 저장소에 chart 코드 0줄
- 불변 버전 핀 (`0.1.0` → `0.1.1` 명시 bump)
- 회사 RBAC 하의 자체 values 관리
- 업그레이드 = `targetRevision` 한 줄 수정

#### 패턴 3: GHCR 패키지를 private으로 운영할 경우 (당장은 아님)

ArgoCD `argocd` 네임스페이스에 GitHub PAT(`read:packages`) 기반 `repo-creds` Secret 추가 필요:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: helm
  url: ghcr.io/seokheejang/chain-node-infra
  enableOCI: "true"
  username: <github-user>
  password: <PAT-with-read:packages>
```

문서에는 기재하되 OSS 저장소는 **public이 기본값**.

### Phase E — 후속 정리 (첫 publish 차단 요소 아님)

1. 이 저장소의 `argocd/applications/*.yaml`도 OCI 참조로 전환 — OSS가 자기 dog food를 먹는 모습 보여야 함. 현재는 git path 참조.
2. `README.md`에 "Consume from GHCR" 섹션 추가 (패턴 1 + 패턴 2 + internal mirroring 옵션) + release 절차 (tag push 흐름) 문서화.
3. `common` 의존성을 `file://../common` → `oci://ghcr.io/seokheejang/chain-node-infra`로 전환. `common` v0.1.0이 GHCR에 publish된 이후에 가능 (chicken-and-egg). 전환 후에는 `helm dependency update`가 로컬 파일시스템 대신 레지스트리에서 fetch.
4. Tag 검증 step 추가 — Phase B의 "선택" 섹션을 정식 step으로 승격. 태그 이름과 `Chart.yaml` 버전 불일치 시 fail.
5. (별도 task) cosign으로 chart signing + provenance attestation 추가 — task-07로 분리. OCI 시대의 표준 위생이지만 첫 publish 차단 요소 아님.

> **gh-pages chart-releaser는 Phase B에서 이미 제거됨** — Phase E에 별도 항목 없음.

## 변경 대상 파일

| 파일 | 변경 내용 |
|------|----------|
| `.github/workflows/release.yaml` | `packages: write` 권한, GHCR login step, package + push 루프 (robust idempotency) |
| `charts/*/Chart.yaml` | OCI annotation 추가 (`org.opencontainers.image.source`, `licenses`, `description`) |
| `README.md` | "Consume from GHCR" 섹션 (패턴 1 + 패턴 2 + internal mirroring) |
| `argocd/applications/*.yaml` | (Phase E) git path → OCI multi-source 전환 |
| `charts/*/Chart.yaml` (재) | (Phase E) `common` 의존성을 OCI repo로 전환 |

신규 파일 없음.

## 검증

첫 release 절차:

0. **태그 push** — `git tag geth-0.1.0 && git push origin geth-0.1.0` (한 chart씩 순차 진행 권장 — 5개 chart에 대해 5번 반복)
1. **Actions 실행 모니터링** — workflow가 태그 트리거에 정상 반응하고 GHCR push 성공하는지.
2. **패키지 페이지 확인** — `https://github.com/seokheejang?tab=packages`에서 5개 패키지(`chain-node-infra/geth`, `chain-node-infra/lighthouse`, `chain-node-infra/lighthouse-validator`, `chain-node-infra/genesis-generator`, `chain-node-infra/common`) 노출. 각 패키지가 source repo로 자동 링크되는지 확인 (annotation 효과).
3. **각 패키지 public 전환** (Phase A 단계 3).
4. **Pull 테스트** (clean 머신):
   ```bash
   helm pull oci://ghcr.io/seokheejang/chain-node-infra/geth --version 0.1.0
   tar -tzf geth-0.1.0.tgz | head
   ```
5. **Render 테스트**:
   ```bash
   helm template test oci://ghcr.io/seokheejang/chain-node-infra/geth --version 0.1.0 \
     -f charts/geth/ci/default-values.yaml
   ```
   결과가 로컬 `make template CHART=geth`와 동일해야 함.
6. **(권장) E2E** — 폐기용 private repo에 패턴 2 매니페스트 1개만 두고 kind 클러스터에 ArgoCD sync 검증.
7. **버전 bump + 멱등성 테스트** — `charts/geth/Chart.yaml` 버전을 `0.1.1`로 올려 머지 후 `geth-0.1.1` 태그 push. workflow 로그에서 다른 chart 4개는 "skip: ... already published"로 건너뛰고 `geth-0.1.1`만 새로 push되는지 확인. GHCR에 `0.1.1` 신규 등장 + `0.1.0` 무손상 (불변성 확인).

## 범위 외 (명시적 비목표)

- Cherry-pick / 회사 → OSS 양방향 동기화 워크플로우 — 본 모델에서는 불필요 (values는 회사 repo에만 존재)
- 통합 버전 태그 (`v0.1.0`) 방식 — per-chart 태그(`geth-0.1.0`)로 결정. 5개 chart의 lockstep release는 이 프로젝트에서 부적합
- Cosign signing / provenance — task-07로 분리 예정
- 이 저장소 자체의 ArgoCD 예시를 OCI로 전환 — Phase E

## 참고: best-practice 리서치 요약

이 task는 별도 best-practice 리서치를 거쳐 다음을 확인했다 (2026-04-09 기준):

- **OCI 방향이 정답**: Helm 3.8+ native 지원, ACR 2025-03 legacy deprecation, Bitnami 2025-09 OCI 전환 등 업계 단방향 이동.
- **현재 monorepo + common library 구조는 표준** (bitnami/charts, prometheus-community/helm-charts와 동일 패턴). umbrella chart로 묶는 것은 블록체인 컴포넌트의 독립적 진화 특성상 안티패턴.
- **OCI 경로는 패턴 C** (`<owner>/<repo>/<chart>`) — 한 계정에 여러 chart 프로젝트 공존 시 표준. CNCF 프로젝트 다수 사용.
- **ArgoCD multi-source** (OCI chart + git values): ArgoCD v2.6+ 표준 권장 패턴.
- **`appany/helm-oci-chart-releaser`** 도 검증된 옵션이지만, 본 task는 chart 추가 시 workflow 수정이 필요 없는 raw helm CLI를 채택.
