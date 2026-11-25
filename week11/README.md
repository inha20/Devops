# Week 11 실습 보고서: 쿠버네티스 설정과 상태 점검

## 1. Secret을 `base64 -d`로 읽은 화면 및 보안 취약성 설명
- **Secret 디코딩 명령어**:
  ```bash
  kubectl get secret guestbook-secret -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d; echo
  ```
- **실행 결과**:
  ```text
  $ kubectl get secret guestbook-secret -o yaml
  ...
  data:
    REDIS_PASSWORD: ZGV2b3BzMTIzNA==

  $ kubectl get secret guestbook-secret -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d; echo
  devops1234
  ```
- **Secret이 안전하지 않은 이유 (인코딩 vs 암호화)**:
  - 쿠버네티스 Secret의 `data`는 **암호화(Encryption)**된 것이 아니라 단순한 **Base64 인코딩(Encoding)**에 불과합니다.
  - 암호화는 비밀 키(Secret Key)가 있어야만 복호화할 수 있지만, Base64 인코딩은 누구나 디코딩 명령(`base64 -d`)을 통해 평문(Plaintext)을 즉시 복구할 수 있습니다.
  - 따라서 `secret.yaml`을 GitHub 등 공개 저장소에 푸시하면 비밀번호가 노출되므로, `.gitignore`에 등록하고 실무에서는 Vault, KMS 등 외부 비밀 관리 도구나 저장 시 암호화 설정을 병행해야 합니다.

---

## 2. ConfigMap만 변경하여 제목 또는 색이 바뀐 화면 확인
- **수정 방식**:
  - `guestbook-config` ConfigMap 적용 후 `APP_TITLE`과 `THEME_COLOR` 변경 (`"방명록 (k8s)"` / `"#16a34a"` → `"New 방명록 (k8s)"` / `"#e11d48"`)
- **Pod 재시작 명령어 (환경변수 반영)**:
  ```bash
  kubectl rollout restart deployment guestbook
  kubectl rollout status deployment guestbook
  ```
- **적용 및 접속 확인 결과**:
  ```text
  $ kubectl apply -f k8s/configmap.yaml
  configmap/guestbook-config created

  $ kubectl rollout restart deployment/guestbook
  deployment.apps/guestbook restarted

  $ kubectl rollout status deployment/guestbook
  deployment "guestbook" successfully rolled out

  # 로그 및 환경변수 주입 확인
  [INFO] Redis 연결 성공: redis:6379
  # 브라우저 접속 시 제목("New 방명록 (k8s)") 및 배지("저장소: Redis") 색상 변경 확인
  ```
- **핵심 원리 (12-Factor App)**:
  - 컨테이너 이미지를 다시 빌드(`docker build`)하지 않고도, 외부의 ConfigMap 설정만 변경하고 Pod를 재시작해 앱의 동작과 외형을 즉시 변경할 수 있음을 확인했습니다.

---

## 3. 상태 점검(Probe) 실패 실험 및 동작 관찰

### (1) Readiness Probe 실패 실험 (기동 순서 차이로 인한 `/readyz` 503 관찰)
- **실험 상황 및 절차**:
  - `guestbook` Pod이 `redis` Pod보다 먼저 기동되면서 초기 Redis 연결에 실패(`redis_client = None` 고정)하여 실제 Readiness Probe 실패 현상을 관찰함.
  - 이어서 `kubectl get pods`, `kubectl logs`, `kubectl describe pod` 3단 루틴으로 원인을 추적하고 `kubectl rollout restart deployment/guestbook`으로 복구함.
- **실행 결과 (`kubectl get pods`, `logs`, `describe`)**:
  ```text
  $ kubectl get pods
  NAME                         READY   STATUS    RESTARTS   AGE
  guestbook-656b7d5b47-9tnn2   1/1     Running   0          87m   ← 구버전(유지)
  guestbook-656b7d5b47-dmdzf   1/1     Running   0          87m   ← 구버전(유지)
  guestbook-767db74986-mnmvw   0/1     Running   0          74s   ← 신버전(READY 아님!)
  redis-57d7f66958-94nfd       1/1     Running   0          78s

  # kubectl logs 출력
  GET /readyz HTTP/1.1" 503 -    ← Readiness Probe 실패
  GET /healthz HTTP/1.1" 200 -   ← Liveness Probe는 정상

  # kubectl describe pod Events 출력
  Warning  Unhealthy  2s (x16 over 74s)  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 503
  ```
- **복구 결과**:
  ```text
  $ kubectl rollout restart deployment/guestbook
  deployment.apps/guestbook restarted

  $ kubectl get pods
  NAME                        READY   STATUS    RESTARTS   AGE
  guestbook-ffd59cd47-4dpcb   1/1     Running   0          24s
  guestbook-ffd59cd47-cxrk4   1/1     Running   0          18s
  redis-57d7f66958-94nfd      1/1     Running   0          2m9s

  $ kubectl rollout status deployment/guestbook
  deployment "guestbook" successfully rolled out
  ```
- **동작 원리 분석**:
  - `app.py`는 프로세스 시작 시 1회만 Redis 연결을 시도하므로 Redis보다 먼저 뜬 Pod의 `/readyz`가 503을 반환했습니다.
  - 쿠버네티스는 Liveness(`/healthz` 200)가 정상이므로 컨테이너를 재시작하지 않고, **Readiness가 실패한 신버전 Pod(`0/1 Running`)만 Service 엔드포인트에서 제외**해 구버전 Pod로 무중단 서비스를 유지했습니다.

### (2) Liveness Probe 실패 실험 (경로 오타 패치)
- **실험 절차**:
  1. 존재하지 않는 경로(`/devops`)로 프로브 패치:
     ```bash
     kubectl patch deployment guestbook -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","livenessProbe":{"httpGet":{"path":"/devops","port":5000},"periodSeconds":5,"failureThreshold":2}}]}}}}'
     ```
  2. Pod 재시작 상태 및 Events 관찰:
     ```bash
     kubectl get pods -w
     kubectl describe pod -l app=guestbook
     ```
  3. 원복 적용:
     ```bash
     kubectl apply -f guestbook/k8s/deployment.yaml
     ```
- **동작 원리 분석**:
  - Liveness Probe가 `/devops` 요청에서 404 상태코드를 `failureThreshold: 2` 연속 수신하면, kubelet이 컨테이너를 비정상으로 판단해 **강제 종료 및 재시작(`RESTARTS` 증가 / `CrashLoopBackOff`)**을 반복합니다.
  - Readiness 실패(트래픽 차단)와 달리 Liveness 실패는 컨테이너 자체를 재시작하므로 경로·임계치 설정에 주의해야 함을 확인했습니다.

---

## 4. 트러블슈팅 3단 루틴 (본인 언어로 정리)
1. **1단계: 상태 확인 (`kubectl get pods`)**
   - 현재 Pod가 `Running`인지, `Pending`, `CrashLoopBackOff`, `CreateContainerConfigError`, `0/1 Running` 등 비정상 상태인지 확인하고 `RESTARTS` 횟수를 확인합니다.
2. **2단계: 원인 이벤트 확인 (`kubectl describe pod <이름>`)**
   - 상세 출력 맨 아래 `Events:` 섹션을 확인합니다. 이미지 Pull 실패, ConfigMap/Secret 이름 오타, Probe 실패(503/404) 등 쿠버네티스 레벨 원인의 대부분이 이곳에 명시됩니다.
3. **3단계: 애플리케이션 로그 확인 (`kubectl logs <이름>`)**
   - 컨테이너 내부 프로세스 오류나 연결 실패 원인을 확인합니다.
   - 이미 컨테이너가 죽고 재시작된 경우에는 `kubectl logs <이름> --previous`로 직전 종료 시점의 로그를 추적합니다.

---

## 5. 실습 체크리스트 및 보안 설정 완료
- [x] `guestbook/k8s/secret.yaml.example` 템플릿 생성 (비밀번호: `CHANGE_ME`)
- [x] `.gitignore`에 `guestbook/k8s/secret.yaml` 추가하여 민감 정보 Git 노출 방지
- [x] Deployment에 `envFrom`, `resources`, `livenessProbe`, `readinessProbe` 반영 (`guestbook/k8s/deployment.yaml`)
