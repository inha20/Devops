# Week 09 실습 보고서: 쿠버네티스 (Kubernetes) 첫 배포

## 1. `kubectl get nodes` 결과
- **사용한 도구**: `minikube` (driver: docker)
- **노드 상태**: `Ready` 상태 확인 완료

```text
$ kubectl get nodes -o wide
NAME       STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION   CONTAINER-RUNTIME
minikube   Ready    control-plane   118m   v1.37.0   172.17.0.2    <none>        Ubuntu 22.04.5 LTS   5.15.167.4-m     containerd://2.3.4
```

---

## 2. Pod를 지운 뒤 새 Pod가 태어난 `get pods -w` 화면 확인
`kubectl create deployment mynginx --image=nginx --replicas=3` 상태에서 특정 Pod를 강제 삭제했을 때, 쿠버네티스의 조정 루프(Reconciliation Loop)에 의해 즉시 새로운 Pod가 생성되어 선언된 복제본 개수(3개)를 자동으로 유지하는 자가 치유(Self-healing) 과정을 확인했습니다.

### Pod 강제 삭제 및 실시간 관찰 (`kubectl get pods -w`)
```text
$ kubectl get pods -w
NAME                       READY   STATUS    RESTARTS   AGE
mynginx-668c4f948b-7rw5m   1/1     Running   0          25s
mynginx-668c4f948b-9vmxp   1/1     Running   0          25s
mynginx-668c4f948b-xsv6s   1/1     Running   0          25s
mynginx-668c4f948b-7rw5m   1/1     Terminating 0        27s
mynginx-668c4f948b-p542g   0/1     Pending     0        0s
mynginx-668c4f948b-p542g   0/1     ContainerCreating 0  0s
mynginx-668c4f948b-7rw5m   0/1     Terminating 0        28s
mynginx-668c4f948b-p542g   1/1     Running     0        2s
```

- **관찰 결과**:
  - `mynginx-668c4f948b-7rw5m` Pod를 삭제하자마자 상태가 `Terminating`으로 변경됨
  - 동시에 복제본 개수를 3개로 맞추기 위해 새 Pod `mynginx-668c4f948b-p542g`가 생성(`Pending` ➔ `ContainerCreating` ➔ `Running`)됨
  - Pod는 "되살아난 것"이 아니라 ReplicaSet 컨트롤러에 의해 **완전히 새로운 무작위 해시 번호의 Pod가 생성**된 것임

---

## 3. 방명록(`guestbook:v1`) 쿠버네티스 배포 및 브라우저 확인 화면
- **배포 이미지**: `ghcr.io/inha20/guestbook:v1`
- **배포 명령어**: `kubectl create deployment guestbook --image=ghcr.io/inha20/guestbook:v1`
- **포트포워딩**: `kubectl port-forward deployment/guestbook 8080:5000`

### 배포 상태 확인 (`kubectl get pods -l app=guestbook -o wide`)
```text
NAME                        READY   STATUS    RESTARTS   AGE   IP           NODE       NOMINATED NODE   READINESS GATES
guestbook-c557d598b-lhm2b   1/1     Running   0          3m    10.244.0.8   minikube   <none>           <none>
```

### 브라우저 (`http://localhost:8080`) 확인 정보
```text
제목: InhaTC DevOps 방명록
배지:
  - [저장소: Memory]
  - [Pod/Host: guestbook-c557d598b-lhm2b]
```

- **포트포워딩 접속 및 Pod/Host 배지 확인**:
  - 로컬 노트북의 8080 포트와 guestbook 컨테이너의 5000 포트가 성공적으로 터널링됨
  - 화면 상단 배지에 쿠버네티스가 할당한 Pod 이름(`guestbook-c557d598b-lhm2b`)이 호스트명으로 정상 표시됨

---

## 4. "선언형(Declarative)"의 정의 및 일상 속 예시
- **한 줄 정의**:
  - '어떻게(How)'를 단계별로 일일이 지시하는 명령형과 달리, **'원하는 최종 상태(Desired State, What)'를 선언해두면 시스템(쿠버네티스 컨트롤러)이 현재 상태(Actual State)를 끊임없이 비교·감시하며 그 상태를 알아서 맞춰 유지하는 방식**입니다.
- **일상 속 비유**:
  - **에어컨 희망 온도 설정**: 26도로 설정해두면 더울 때는 찬바람을 틀고, 온도가 도달하면 멈추며 알아서 26도를 유지하는 것과 같습니다. (매번 사람이 껐다 켰다 지시할 필요가 없음)

---

## 5. 오늘 막혔던 점 및 해결 방법
1. **8080 포트 충돌**:
   - 지난 7주차 Docker Compose 실습에서 실행되었던 `guestbook-web` 컨테이너가 8080 포트를 점유하고 있어 포트포워딩 시 충돌 위험이 있었습니다.
   - `docker stop`으로 기존 컨테이너를 안전하게 중지하여 8080 포트를 확보한 후 정상 진행했습니다.
2. **GHCR 이미지 배포 준비**:
   - `ghcr.io/inha20/guestbook:v1` 패키지의 접근 권한을 Public으로 확인하고, 로컬 minikube 노드에 이미지를 캐싱하여 `ImagePullBackOff` 에러 없이 빠르게 배포를 완료했습니다.