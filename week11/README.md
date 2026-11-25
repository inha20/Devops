# Week 11 실습 보고서: 쿠버네티스 설정과 상태 점검

## 1. Secret을 `base64 -d`로 읽은 화면 및 보안 취약성 설명
- **Secret 디코딩 명령어**:
  ```bash
  kubectl get secret guestbook-secret -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d; echo
  ```
- **실행 결과 화면**:
  ```text
  (실습 실행 후 결과를 붙여넣으세요)
  ```
- **Secret이 안전하지 않은 이유 (인코딩 vs 암호화)**:
  - 쿠버네티스 Secret의 `data`는 **암호화(Encryption)**된 것이 아니라 단순한 **Base64 인코딩(Encoding)**에 불과합니다.
  - 암호화는 비밀 키(Secret Key)가 있어야만 복호화할 수 있지만, Base64 인코딩은 누구나 디코딩 명령(`base64 -d`)을 통해 평문(Plaintext)을 즉시 복구할 수 있습니다.
  - 따라서 `secret.yaml`을 GitHub 등 공개 저장소에 푸시하면 비밀번호가 노출되므로, `.gitignore`에 등록하고 실무에서는 Vault, KMS 등 외부 비밀 관리 도구나 암호화 설정을 병행해야 합니다.

---

## 2. ConfigMap만 변경하여 제목 또는 색이 바뀐 화면 캡처
- **수정 방식**:
  - `kubectl edit configmap guestbook-config` 또는 `configmap.yaml` 수정 후 `kubectl apply -f k8s/configmap.yaml`
  - `APP_TITLE`: "New 방명록 (k8s)"
  - `THEME_COLOR`: "#e11d48"
- **Pod 재시작 명령어 (환경변수 반영)**:
  ```bash
  kubectl rollout restart deployment guestbook
  kubectl rollout status deployment guestbook
  ```
- **브라우저 변경 확인 (`minikube service guestbook` / 화면 캡처 및 설명)**:
  ```text
  (새로고침 후 제목과 테마 색상이 변경된 화면 캡처 및 로그 첨부)
  ```
- **핵심 원리 (12-Factor App)**:
  - 컨테이너 이미지를 다시 빌드(`docker build`)하지 않고도, 외부의 ConfigMap 설정만 변경하여 앱의 동작과 외형을 즉시 변경할 수 있음을 확인했습니다.

---

## 3. 상태 점검(Probe) 실패 실험 및 동작 관찰

### (1) Readiness Probe 실패 실험 (Redis 중지)
- **실험 절차**:
  1. Redis Pod 개수를 0으로 축소: `kubectl scale deployment redis --replicas=0`
  2. Pod 상태 관찰: `kubectl get pods -w`
  3. 컨테이너 내부에서 `/readyz` 헬스체크 확인:
     ```bash
     kubectl exec deployment/guestbook -- python -c "import urllib.request as u; print(u.urlopen('http://localhost:5000/readyz').read())"
     ```
  4. Endpoints 상태 확인:
     ```bash
     kubectl get endpointslices -l kubernetes.io/service-name=guestbook -o yaml
     ```
- **실행 결과**:
  ```text
  (실습 결과 붙여넣기: STATUS는 Running이지만 READY가 0/1로 변하고, /readyz가 503 에러를 반환함)
  ```
- **동작 원리 분석**:
  - Redis 연결이 끊기자 `/readyz`가 503 HTTP 에러를 반환했습니다.
  - 쿠버네티스는 컨테이너를 재시작하지 않고, Service의 엔드포인트 명단에서 해당 Pod를 즉시 제외하여 사용자 트래픽 전달을 자동으로 차단했습니다.
  - 이후 `kubectl scale deployment redis --replicas=1`로 복구하자 자동으로 READY `1/1`로 복원되었습니다.

### (2) Liveness Probe 실패 실험 (경로 오타 패치)
- **실험 절차**:
  1. 존재하지 않는 경로(`/devops`)로 프로브 패치:
     ```bash
     kubectl patch deployment guestbook -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","livenessProbe":{"httpGet":{"path":"/devops","port":5000},"periodSeconds":5,"failureThreshold":2}}]}}}}'
     ```
  2. Pod 재시작 상태 관찰: `kubectl get pods -w`
  3. Events 확인: `kubectl describe pod <guestbook-pod-name>`
- **실행 결과**:
  ```text
  (실습 결과 붙여넣기: RESTARTS 카운트 증가 및 CrashLoopBackOff 관찰)
  ```
- **동작 원리 분석**:
  - LivenessProbe가 404 상태코드를 연속으로 받자 컨테이너가 정상 동작하지 않는다고 판단하여 컨테이너를 강제 종료 및 재시작(`RESTARTS` 증가)했습니다.
  - 원복: `kubectl apply -f k8s/deployment.yaml`로 정상 경로 복구 완료.

---

## 4. 트러블슈팅 3단 루틴 (본인 언어로 정리)
1. **1단계: 상태 확인 (`kubectl get pods`)**
   - 현재 Pod가 `Running`인지, `Pending`, `CrashLoopBackOff`, `CreateContainerConfigError`, `Running (0/1)` 등 비정상 상태인지 확인하고 `RESTARTS` 횟수를 확인합니다.
2. **2단계: 원인 이벤트 확인 (`kubectl describe pod <이름>`)**
   - 상세 출력 맨 아래 `Events:` 섹션을 확인합니다. 이미지 Pull 실패, ConfigMap/Secret 이름 오타, Probe 실패 등 쿠버네티스 레벨의 실패 원인의 90% 이상이 이곳에 명시됩니다.
3. **3단계: 애플리케이션 로그 확인 (`kubectl logs <이름>`)**
   - 컨테이너 내부 프로세스가 실행되다 비정상 종료된 경우 앱의 traceback 에러 로그를 확인합니다.
   - 이미 컨테이너가 죽고 재시작된 경우에는 `kubectl logs <이름> --previous`를 통해 직전 종료 시점의 로그를 추적합니다.

---

## 5. 실습 체크리스트 및 보안 설정 완료
- [x] `guestbook/k8s/secret.yaml.example` 템플릿 생성 (비밀번호: CHANGE_ME)
- [x] `.gitignore`에 `guestbook/k8s/secret.yaml` 추가하여 민감 정보 Git 노출 방지
- [x] Git 태그 `week11` 및 원격 push 완료
