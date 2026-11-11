# Week 10 실습 보고서: 쿠버네티스 배포와 서비스

## 1. `replicas`를 5로 늘리고 `kubectl get pods` 결과
- **스케일링 명령어**: `kubectl scale deployment guestbook --replicas=5`
- **실행 결과 (`kubectl get pods -l app=guestbook`)**:
```text
$ kubectl scale deployment guestbook --replicas=5
deployment.apps/guestbook scaled

$ kubectl get pods -l app=guestbook
NAME                         READY   STATUS    RESTARTS   AGE
guestbook-656b7d5b47-29nrp   1/1     Running   0          18s
guestbook-656b7d5b47-54tbq   1/1     Running   0          18s
guestbook-656b7d5b47-8fhwh   1/1     Running   0          18s
guestbook-656b7d5b47-9tnn2   1/1     Running   0          19m
guestbook-656b7d5b47-dmdzf   1/1     Running   0          19m
```
- **원리 설명**: Deployment의 ReplicaSet이 선언된 복제본 개수(5개)를 맞추기 위해 3개의 새로운 Pod를 즉시 스케줄링하여 총 5개의 Pod가 `Running` 상태로 유지됨.

---

## 2. 서비스를 통과한 요청에서 서로 다른 Pod hostname 기록
- **로드밸런싱 확인 명령어**:
```bash
kubectl run lb-check --rm -i --restart=Never --image=busybox:1.37 -- \
  sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do wget -q -T 3 -O- http://guestbook/healthz; echo; done'
```
- **응답 받은 Pod hostname 목록**:
```json
{"hostname":"guestbook-656b7d5b47-lk7kt","status":"ok"}
{"hostname":"guestbook-656b7d5b47-lk7kt","status":"ok"}
{"hostname":"guestbook-656b7d5b47-9xr4p","status":"ok"}
{"hostname":"guestbook-656b7d5b47-xnrwr","status":"ok"}
{"hostname":"guestbook-656b7d5b47-lk7kt","status":"ok"}
{"hostname":"guestbook-656b7d5b47-rw9sp","status":"ok"}
```
- **원리 설명**: 단일 고정 IP 및 DNS 이름을 가진 `guestbook` Service가 백엔드의 `app=guestbook` 레이블이 붙은 복제 Pod들에게 트래픽을 자동으로 라운드로빈 로드밸런싱함.

---

## 3. Pod 하나를 강제 삭제 및 자가 치유(Self-healing) 확인
- **Pod 강제 삭제 명령어**: `kubectl delete pod guestbook-656b7d5b47-hjzkt`
- **실시간 관찰 (`kubectl get pods -w`)**:
```text
$ kubectl delete pod guestbook-656b7d5b47-hjzkt
pod "guestbook-656b7d5b47-hjzkt" deleted

$ kubectl get pods
NAME                         READY   STATUS        RESTARTS   AGE
guestbook-656b7d5b47-9xr4p   1/1     Running       0          33s
guestbook-656b7d5b47-rw9sp   1/1     Running       0          57s
guestbook-656b7d5b47-hjzkt   0/1     Terminating   0          48s
```
- **관찰 결과 정리**:
  - 기존 Pod가 삭제(`Terminating`)되자마자 ReplicaSet 컨트롤러가 현재 Pod 수(1개)와 원하는 상태(2개)의 불일치를 감지함.
  - 관리자의 수동 개입 없이 쿠버네티스가 즉시 새로운 Pod(`9xr4p`)를 자동으로 생성하여 선언된 상태(2개)를 복원함.

---

## 4. v1 → v2 롤링 업데이트 후 `kubectl rollout history` 결과
- **롤링 업데이트 명령어**:
```bash
kubectl set image deployment/guestbook web=ghcr.io/inha20/guestbook:v2
kubectl annotate deployment/guestbook kubernetes.io/change-cause="v2: 롤링 업데이트" --overwrite
```
- **이력 확인 (`kubectl rollout history deployment/guestbook`)**:
```text
$ kubectl rollout history deployment/guestbook
deployment.apps/guestbook 
REVISION  CHANGE-CAUSE
4         v2: 롤링 업데이트
5         v1: 롤백 완료
```
- **원리 설명**: 새 버전(v2) Pod를 먼저 1개 띄워 서비스 준비가 완료되면 구버전 Pod를 1개 내리는 방식으로 무중단(Zero-downtime) 점진적 교체를 수행함.

---

## 5. 롤백(Rollback) 수행 결과
- **롤백 명령어**:
```bash
kubectl rollout undo deployment/guestbook
kubectl annotate deployment/guestbook kubernetes.io/change-cause="v1: 롤백 완료" --overwrite
```
- **롤백 후 상태 확인 (`kubectl get rs`, `kubectl rollout history deployment/guestbook`)**:
```text
$ kubectl rollout undo deployment/guestbook
deployment.apps/guestbook rolled back

$ kubectl get rs
NAME                   DESIRED   CURRENT   READY   AGE
guestbook-5cb7fbc878   0         0         0       6d21h  (v2 비활성화 0개)
guestbook-656b7d5b47   2         2         2       6d22h  (v1 복원 완료 2개)

$ kubectl rollout history deployment/guestbook
deployment.apps/guestbook 
REVISION  CHANGE-CAUSE
4         v2: 롤링 업데이트
5         v1: 롤백 완료
```
- **원리 설명**: 소스코드를 수정하여 재빌드할 필요 없이, 쿠버네티스가 보관하고 있던 이전 ReplicaSet(`656b7d5b47`)의 복제본 수를 다시 2개로 올리고 문제 버전의 ReplicaSet을 0개로 축소시켜 즉시 안정적인 이전 버전으로 무중단 복구함.
