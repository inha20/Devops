# 방명록 (DevOps)

인하공업전문대학 DevOps 수업 프로젝트 및 주차별(2~13주차) 실습 기록 저장소입니다.

## 1. 아키텍처

```text
코드 ──git push──▶ GitHub (PR + Branch Protection)
                      │
                      ▼
               GitHub Actions ──린트 & 테스트 & 빌드──▶ ghcr.io/inha20/guestbook:<commit-sha>
                                                               │
                                   배포 태그 PR(deployment.yaml) │ 이미지 pull
                                                               ▼
┌──────────────────────── Kubernetes (minikube) ────────────────────────┐
│  [Argo CD (argocd ns)] ──감시 & 자동 Sync(prune, selfHeal)──▶ Git     │
│                                                                       │
│  [Service: guestbook, NodePort 30080] (selector: app=guestbook)       │
│     └── [Deployment: guestbook, replicas 2] ── Pod ── Pod             │
│            ◀── ConfigMap (guestbook-config), Secret (guestbook-secret)│
│                                                                       │
│  [Service: redis, ClusterIP 6379] ── [Deployment: redis] ── Pod       │
│                                                                       │
│  [Monitoring (monitoring ns)] Prometheus ──▶ Grafana                  │
└───────────────────────────────────────────────────────────────────────┘
```

## 2. 기술 스택

- **애플리케이션**: Python 3.12, Flask, Redis (`redis:7-alpine`)
- **컨테이너 & 오케스트레이션**: Docker, Docker Compose, Kubernetes (Minikube)
- **CI / CD (GitOps)**: GitHub Actions, GitHub Container Registry (`ghcr.io`), Argo CD
- **모니터링**: Kubernetes `metrics-server`, Prometheus, Grafana (`kube-prometheus-stack`), Helm

## 3. 실행 방법

1. 클러스터 시작 및 저장소 클론:
   ```bash
   minikube start --driver=docker
   gh repo clone inha20/Devops
   cd Devops
   ```
2. Secret 준비 (`.gitignore` 제외 대상이므로 로컬에서 직접 생성 및 적용):
   ```bash
   cp guestbook/k8s/secret.yaml.example guestbook/k8s/secret.yaml
   # guestbook/k8s/secret.yaml의 CHANGE_ME를 실제 비밀번호로 수정 후 적용
   kubectl apply -f guestbook/k8s/secret.yaml
   ```
3. 애플리케이션 배포 및 확인:
   ```bash
   kubectl apply -f guestbook/k8s
   kubectl get pods                  # 확인: guestbook Pod 2개, redis Pod 1개
   minikube service guestbook
   ```
4. *(선택)* GitOps (Argo CD) & 모니터링 연결:
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd --server-side --force-conflicts -f \
     https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl apply -f argocd-application.yaml
   ```

## 4. 배포 절차

1. 기능 브랜치에서 코드 수정 후 PR 생성 (`main`은 Branch Protection 적용)
2. GitHub Actions(`build.yml`)에서 `ruff` 린트, 단위 테스트, 멀티 아키텍처 Docker 이미지 빌드 통과 후 PR 머지
3. `main` 머지 커밋의 짧은 SHA 태그로 `ghcr.io/inha20/guestbook:<sha>` 이미지 게시
4. `guestbook/k8s/deployment.yaml`의 `image:` 태그를 새 `<sha>`로 변경하는 배포 PR 머지
5. 클러스터 내부의 Argo CD가 `guestbook/k8s` 변경을 감지해 무중단 롤링 업데이트 수행
6. `kubectl top`, `kubectl logs`, Grafana 대시보드로 상태 및 리소스 모니터링

## 5. 설정

| 구분 | 리소스명 | 주요 항목 | 비고 |
|---|---|---|---|
| **ConfigMap** | `guestbook-config` | `APP_TITLE`, `THEME_COLOR`, `REDIS_HOST`, `REDIS_PORT` | `guestbook/k8s/configmap.yaml` |
| **Secret** | `guestbook-secret` | `REDIS_PASSWORD` | `.gitignore` 제외 (`secret.yaml.example` 템플릿 제공) |

## 6. 트러블슈팅 기록

### (1) Minikube 재시작 후 `guestbook` Pod가 `0/1 Running`으로 유지되는 현상
- **증상**: `kubectl get pods`에서 `guestbook` Pod가 `0/1 Running`에 머무르고 Readiness Probe 실패 경고가 반복됨.
- **확인**: `kubectl describe pod` 및 `kubectl logs` 확인 결과 `/readyz`가 `503` 반환, 기동 로그에 `Redis 연결 실패 (Temporary failure in name resolution)` 출력.
- **원인**: `app.py`가 앱 시작 시점에 1회만 Redis 연결을 시도하는데, 클러스터 재기동 시 DNS/Redis 준비 전에 `guestbook`이 먼저 시작되면서 메모리 모드로 고정됨.
- **조치**: `kubectl rollout restart deployment guestbook` 실행.
- **결과**: 새 Pod들이 Redis에 정상 연결되어 `1/1 Running` 및 Service 엔드포인트 복구.

### (2) Argo CD + Prometheus/Grafana 동시 구동 시 API 서버 응답 지연 (`TLS handshake timeout`)
- **증상**: `kube-prometheus-stack` 설치 중 `Unable to connect to the server: net/http: TLS handshake timeout` 및 `Metrics API not available` 발생.
- **확인**: `docker stats` 확인 시 `minikube` 컨테이너 메모리가 `2.62GiB / 3GiB (87%)`로 한계에 근접하고 CPU 부하가 급증함.
- **원인**: Minikube 컨테이너 메모리 상한(3GiB) 상태에서 Argo CD와 모니터링 스택이 동시에 이미지를 받고 초기화하며 리소스 경합 발생.
- **조치**: `docker update --memory=5g --memory-swap=-1 minikube`로 컨테이너 메모리 한도를 5GiB로 확장.
- **결과**: `guestbook`, `argocd`, `monitoring`, `metrics-server` Pod가 모두 정상 `Running` 및 `Healthy` 상태로 안정화.

---

## 주차별 실습 기록

- [`week02/README.md`](week02/README.md): WSL2 Ubuntu 환경 세팅, 가상화 비교, Git & `gh` 기초
- [`week03/README.md`](week03/README.md): 셸 스크립팅과 자동화 기초
- [`week04/README.md`](week04/README.md): 파이프라인, 네트워크 기초 및 로컬 웹 서버 테스트
- [`week05/README.md`](week05/README.md): Docker 기초 및 Nginx 다중 컨테이너 실행
- [`week06/README.md`](week06/README.md): Dockerfile과 이미지 배포 (ghcr.io)
- [`week07/README.md`](week07/README.md): Docker Compose (`web=3` 스케일 아웃, 볼륨 영속성)
- [`week09/README.md`](week09/README.md): Kubernetes 기초 실습
- [`week10/README.md`](week10/README.md): Kubernetes Deployment, Service, 롤링 업데이트 및 롤백
- [`week11/README.md`](week11/README.md): ConfigMap, Secret, Readiness/Liveness Probe 및 트러블슈팅
- [`week13/README.md`](week13/README.md): GitOps(Argo CD) 및 Prometheus/Grafana 모니터링 실습
