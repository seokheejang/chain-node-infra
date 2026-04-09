# Task 01: ArgoCD Helm 설치

## 목표

K8s 1.33.9 클러스터에 ArgoCD를 Helm으로 안전하게 설치한다.

## 버전 선정

| 항목 | 값 |
|------|-----|
| Helm chart | `argo-cd` (argoproj/argo-helm) |
| Chart version | **9.4.17** |
| ArgoCD version | **v3.3.6** (2026-03-27 릴리스) |
| kubeVersion 제약 | `>=1.25.0-0` |
| K8s 1.33 호환 | 공식 테스트 완료 (tested: v1.32 ~ v1.35) |

### 선정 근거

- ArgoCD v3.3은 K8s 1.33이 테스트 범위 중앙에 위치 (edge가 아님)
- 현재 보안/버그 패치가 지원되는 3개 minor 중 최신 (v3.1, v3.2, v3.3)
- 알려진 K8s 1.33 관련 호환성 이슈 없음

## 사전 준비

- Helm 3.x 설치
- kubectl 설치
- 대상 클러스터의 kubeconfig 파일
- 클러스터에 네임스페이스 생성 권한

### 환경 설정

```bash
# 1. 환경 변수 파일 설정
cp .envrc.example .envrc

# 2. .envrc에서 KUBECONFIG 경로를 자신의 kubeconfig로 수정
#    예: export KUBECONFIG="${PWD}/.kubeconfig"
#    또는: export KUBECONFIG="${HOME}/.kube/config"

# 3. 환경 변수 로드
direnv allow       # direnv 사용 시 (cd 하면 자동 로드)
source .envrc      # direnv 없을 때

# 4. 클러스터 연결 확인
kubectl cluster-info
```

## 설치 순서

### 방법 1: 설치 스크립트 (권장)

```bash
scripts/install-argocd.sh
```

스크립트 내부 동작:

1. `$KUBECONFIG` 환경변수 확인 (미설정 시 에러)
2. Helm repo 추가 (`argo https://argoproj.github.io/argo-helm`)
3. `argocd/install/values.yaml`을 사용하여 Helm install 실행
4. pod Ready 대기
5. 초기 admin 패스워드 출력

### 방법 2: 수동 설치

```bash
# KUBECONFIG 설정 확인
echo $KUBECONFIG

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --version 9.4.17 \
  --namespace argocd \
  --create-namespace \
  -f argocd/install/values.yaml
```

## values 커스터마이징

`argocd/install/values.yaml`에 기본 설정이 있다. 환경에 맞게 수정 후 실행한다.

```yaml
# argocd/install/values.yaml
global:
  domain: argocd.example.com  # 실제 도메인으로 교체

server:
  service:
    type: ClusterIP

  ingress:
    enabled: false  # 필요 시 true로 변경

configs:
  params:
    server.insecure: false

  repositories:
    chain-node-infra:
      url: https://github.com/<your-org>/chain-node-infra.git
      type: git

controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 1Gi

repoServer:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

## 설치 확인

```bash
# pod 상태 확인
kubectl get pods -n argocd

# 초기 admin 패스워드 확인
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

## 설치 후 할 일

- [ ] admin 패스워드 변경
- [ ] SSO 연동 (필요 시)
- [ ] `argocd/applications/` 하위 Application 매니페스트 apply
- [ ] RBAC 설정 (project별 권한 분리)
- [ ] Notification 설정 (Slack 등)

## 주의사항

- ArgoCD CRD는 Helm chart에 포함되어 자동 설치됨
- 업그레이드 시 CRD는 `kubectl apply --server-side --force-conflicts`로 별도 관리 필요
- `argocd-initial-admin-secret`은 첫 로그인 후 삭제 권장
- values 파일에 실제 secret/credential을 넣지 말 것
