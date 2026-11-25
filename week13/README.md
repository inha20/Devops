# Week 13 실습 보고서: GitOps (Argo CD) & 모니터링 (Prometheus / Grafana)

## 1. Argo CD 설치 및 애플리케이션 등록 (Slide #13 ~ #20)
- **설치 및 초기 비밀번호 확인**:
  ```bash
  kubectl create namespace argocd
  kubectl apply -n argocd --server-side --force-conflicts -f \
    https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl get pods -n argocd
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d ; echo
  ```
- **애플리케이션 등록 (`argocd-application.yaml`, 저장소 루트)**:
  - `repoURL`: `https://github.com/inha20/Devops.git`
  - `targetRevision`: `main`, `path`: `guestbook/k8s`
  - `destination.namespace`: `default`
  - `syncPolicy.automated`: `prune: true`, `selfHeal: true`
  - PR #6 (`c853006`): `ops/argocd-app` 브랜치로 `argocd-application.yaml` Git 기록 완료
- **관찰 결과 (`kubectl get application -n argocd`)**:
  ```text
  NAME        SYNC STATUS   HEALTH STATUS
  guestbook   Synced        Healthy
  ```

---

## 2. 실습 1 — Git 변경으로 스케일 아웃 (`replicas: 2 → 4`)
- **수행 내용**: `ops/scale-four` 브랜치에서 `guestbook/k8s/deployment.yaml`의 `replicas`를 `2`에서 `4`로 수정 후 PR #9 (`c96156c`) 머지 (`kubectl` 직접 명령 미사용).
- **결과 (`kubectl get po`)**:
  ```text
  NAME                         READY   STATUS    RESTARTS      AGE
  guestbook-858f46df8d-gxvhx   1/1     Running   0             12m
  guestbook-858f46df8d-lfnzh   1/1     Running   0             12m
  guestbook-858f46df8d-qtjd9   1/1     Running   0             7s
  guestbook-858f46df8d-vbtzg   1/1     Running   0             7s
  redis-57d7f66958-hv5nk       1/1     Running   1 (57m ago)   7d
  ```
- **확인**: Git(`main`) 변경만으로 Argo CD가 자동 감지해 Pod 4개(`Synced / Healthy`)로 확장됨.

---

## 3. 실습 2 — 수동 변경과 자가 치유 (`selfHeal`)
- **수행 내용**:
  ```bash
  kubectl scale deployment guestbook --replicas=10
  ```
- **관찰 결과**:
  - `kubectl scale` 직후 ReplicaSet이 일시적으로 10개까지 확장을 시도했으나(`rgpqq`, `8k88f`, `jcgg8`, `hqdd4`, `p56vt` 등), Argo CD의 `selfHeal: true`가 Drift(Git 선언 `4` vs 클러스터 `10`)를 즉시 감지하고 수 초 내에 `replicas: 4`로 자동 되돌림(`Scaled down replica set guestbook-858f46df8d from 10 to 4`).
  - **핵심 원리**: GitOps 환경에서는 Git에 기록되지 않은 수동 변경은 허용되지 않으며, Argo CD가 Git의 상태(`desired state`)로 자동 복구함.

---

## 4. 실습 3 — `git revert`를 이용한 롤백
- **수행 내용**: `ops/revert-scale` 브랜치에서 `git revert c96156c68c8526e5d64e5adb136a4194b19f1257 --no-edit` 실행 후 PR #10 (`81d3e82`) 머지.
- **결과 (`kubectl get po`)**:
  ```text
  NAME                         READY   STATUS        RESTARTS      AGE
  guestbook-858f46df8d-gxvhx   1/1     Running       0             14m
  guestbook-858f46df8d-lfnzh   1/1     Running       0             14m
  guestbook-858f46df8d-qtjd9   1/1     Terminating   0             111s
  guestbook-858f46df8d-vbtzg   1/1     Terminating   0             111s
  redis-57d7f66958-hv5nk       1/1     Running       1 (58m ago)   7d
  ```
- **확인**: `kubectl rollout undo` 대신 `git revert`로 롤백하면 Git 이력에 롤백 사유/시점이 남고 `selfHeal`과 충돌하지 않음.

---

## 5. 실습 4 — `prune: true` 동작 확인 (`hello.yaml` 추가/삭제)
- **추가 (`ops/add-hello`, PR #11 `df83b05`)**:
  - `guestbook/k8s/hello.yaml` (`ConfigMap name: hello`) 생성 후 머지
  - 확인 (`kubectl get cm hello`):
    ```text
    NAME    DATA   AGE
    hello   1      2s
    ```
- **삭제 (`ops/remove-hello`, PR #12 `c52c902`)**:
  - `git rm guestbook/k8s/hello.yaml` 후 머지
  - 확인 (`kubectl get cm hello`):
    ```text
    Error from server (NotFound): configmaps "hello" not found
    ```
- **원리**: `prune: true` 설정 덕분에 Git에서 삭제된 리소스가 클러스터에서도 자동으로 제거됨.

---

## 6. 실습 5 — CI 이미지 빌드 & GitOps 이미지 태그 배포
1. **코드 수정 PR (`feature/title-cicd`, PR #13 `c1b2f1c`)**:
   - `guestbook/templates/index.html`: `<h1>{{ title }} new</h1>` → `<h1>{{ title }} CI/CD</h1>`
   - `main` push 후 GitHub Actions `Build and Push Image` (Run `45529010571`) 성공, `ghcr.io/inha20/guestbook:c1b2f1c` 게시.
2. **이미지 태그 배포 PR (`ops/image-c1b2f1c`, PR #14 `218bb65`)**:
   - `guestbook/k8s/deployment.yaml`: `image: ghcr.io/inha20/guestbook:a18e437` → `ghcr.io/inha20/guestbook:c1b2f1c`
3. **Argo CD 롤링 업데이트 & 서비스 응답 확인**:
   ```text
   NAME                         READY   STATUS    RESTARTS      AGE     IP
   guestbook-6474b47b45-czdpp   1/1     Running   0             10m     10.244.0.28
   guestbook-6474b47b45-prkgf   1/1     Running   2 (49s ago)   3m33s   10.244.0.29
   redis-57d7f66958-hv5nk       1/1     Running   1 (77m ago)   7d      10.244.0.2
   ```
   - `http://guestbook/` HTML 확인 결과: `<h1>New 방명록 (k8s) CI/CD</h1>` 정상 반영.

---

## 7. 모니터링 실습 (`metrics-server`, Prometheus & Grafana, 부하 테스트, 로그)
- **`metrics-server` & `kube-prometheus-stack` 설치**:
  - `minikube addons enable metrics-server`
  - `helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace`
  - `monitoring` 네임스페이스 6개 Pod(`alertmanager`, `monitoring-grafana`, `operator`, `kube-state-metrics`, `node-exporter`, `prometheus`) 모두 `Running` 확인
- **부하 전 vs 부하 중 `kubectl top` 비교**:
  - **부하 전**:
    ```text
    NAME       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
    minikube   460m         5%       3656Mi          46%

    NAME                         CPU(cores)   MEMORY(bytes)
    guestbook-6474b47b45-czdpp   1m           40Mi
    guestbook-6474b47b45-prkgf   1m           33Mi
    redis-57d7f66958-hv5nk       5m           5Mi
    ```
  - **부하 중 (`load` Pod `busybox` `wget` 루프 60초 후)**:
    ```text
    NAME       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
    minikube   1068m        13%      3750Mi          47%

    NAME                         CPU(cores)   MEMORY(bytes)
    guestbook-6474b47b45-czdpp   113m         41Mi
    guestbook-6474b47b45-prkgf   88m          33Mi
    load                         480m         3Mi
    redis-57d7f66958-hv5nk       27m          5Mi
    ```
  - **분석**: 부하 발생 시 `guestbook` Pod의 CPU 사용량이 `1m`에서 `113m` / `88m`으로 상승(`requests: 100m` 근접·초과, `limits: 500m` 이내)함을 확인.
- **부하 Pod 정리 확인**:
  ```text
  $ kubectl delete pod load
  pod "load" deleted from default namespace
  ```
- **로그 확인 (`kubectl logs`)**:
  - `kubectl logs -l app=guestbook --tail=20 --prefix` 및 `kubectl logs deploy/guestbook --since=5m` 실행 시 두 Pod 모두 `load` Pod(`10.244.0.30`)로부터 들어온 `"GET / HTTP/1.1" 200 -` 요청과 `/healthz`, `/readyz` `200` 응답 로그 확인.
