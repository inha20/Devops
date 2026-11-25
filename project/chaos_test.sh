#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DevOps 기말 프로젝트: 카오스 엔지니어링 기반 자가치유 검증 스크립트
# 대상: Minikube + guestbook (Deployment replicas=3, Readiness/Liveness) + Argo CD
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORT_FILE="${SCRIPT_DIR}/chaos_report_latest.txt"

NAMESPACE="default"
ARGOCD_NS="argocd"
APP_NAME="guestbook"
CLIENT_POD="chaos-client"
ARGOCD_PAUSED="false"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

cleanup() {
  log "정리(cleanup) 수행 중..."
  kubectl delete pod "${CLIENT_POD}" -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

  # Redis 복제본 보장
  kubectl scale deployment redis -n "${NAMESPACE}" --replicas=1 >/dev/null 2>&1 || true

  # Argo CD auto-sync 복원
  if [[ "${ARGOCD_PAUSED}" == "true" ]] && [[ -f "${REPO_ROOT}/argocd-application.yaml" ]]; then
    kubectl apply -f "${REPO_ROOT}/argocd-application.yaml" >/dev/null 2>&1 || true
    log "Argo CD syncPolicy (prune/selfHeal) 복원 완료"
  fi
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "오류: '$1' 명령을 찾을 수 없습니다." >&2
    exit 1
  fi
}

require_cmd kubectl
require_cmd awk

exec > >(tee "${REPORT_FILE}") 2>&1

echo "======================================================================"
echo "  DevOps Chaos Engineering & Self-Healing Report"
echo "  실행 시각: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "  컨텍스트: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo "======================================================================"
echo ""

  log "[사전 점검] 클러스터 및 초기 Pod 상태 확인"
  kubectl get nodes -o wide
  echo ""
  kubectl get deploy,svc,pods -n "${NAMESPACE}"
  echo ""

  HAS_ARGOCD="false"
  if kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}" >/dev/null 2>&1; then
    HAS_ARGOCD="true"
    log "Argo CD Application(${APP_NAME}) 감지됨:"
    kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}"
    echo ""
  else
    log "참고: Argo CD Application이 감지되지 않아 Drift(selfHeal) 실험은 건너뜁니다."
  fi

  # ----------------------------------------------------------------------------
  # 실험 1: 부하 발생 중 랜덤 Pod 강제 삭제 (Chaos Monkey) & 무중단 자가치유
  # ----------------------------------------------------------------------------
  echo "----------------------------------------------------------------------"
  echo "[실험 1] Pod 강제 삭제(Chaos Monkey) 중 서비스 무중단 및 ReplicaSet 복구"
  echo "----------------------------------------------------------------------"

  kubectl delete pod "${CLIENT_POD}" -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

  log "클러스터 내부 부하 클라이언트(${CLIENT_POD}, busybox:1.37) 기동 중..."
  kubectl run "${CLIENT_POD}" -n "${NAMESPACE}" --restart=Never --image=busybox:1.37 -- \
    sh -c 'i=0; while [ $i -lt 120 ]; do i=$((i+1)); out=$(wget -q -T 2 -O- http://guestbook/healthz 2>/dev/null); rc=$?; if [ $rc -eq 0 ]; then echo "OK $out"; else echo "ERR rc=$rc"; fi; sleep 0.2; done' >/dev/null

  kubectl wait --for=condition=Ready "pod/${CLIENT_POD}" -n "${NAMESPACE}" --timeout=60s >/dev/null
  sleep 2

  VICTIM_POD="$(kubectl get pods -n "${NAMESPACE}" -l app=guestbook -o jsonpath='{.items[0].metadata.name}')"
  DESIRED_REPLICAS="$(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"
  log "타깃 Pod 강제 삭제 실행: ${VICTIM_POD} (목표 replicas=${DESIRED_REPLICAS})"

  T1_START=$(date +%s)
  kubectl delete pod "${VICTIM_POD}" -n "${NAMESPACE}" --wait=false >/dev/null

  # 새 Pod가 Ready되어 desired 개수만큼 복구될 때까지 대기
  while true; do
    READY_REPLICAS="$(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    READY_REPLICAS="${READY_REPLICAS:-0}"
    TERMINATING_COUNT="$(kubectl get pods -n "${NAMESPACE}" -l app=guestbook --no-headers 2>/dev/null | grep -c Terminating || true)"
    if [[ "${READY_REPLICAS}" -ge "${DESIRED_REPLICAS}" ]] && [[ "${TERMINATING_COUNT}" -eq 0 ]]; then
      break
    fi
    NOW=$(date +%s)
    if (( NOW - T1_START > 90 )); then
      log "경고: Pod 복구 대기 시간(90s) 초과"
      break
    fi
    sleep 1
  done
  T1_END=$(date +%s)
  T1_ELAPSED=$((T1_END - T1_START))

  sleep 3
  TRAFFIC_LOG="$(kubectl logs "${CLIENT_POD}" -n "${NAMESPACE}" 2>/dev/null || true)"
  TOTAL_REQ=$(printf '%s\n' "${TRAFFIC_LOG}" | grep -cE '^(OK|ERR)' || true)
  OK_REQ=$(printf '%s\n' "${TRAFFIC_LOG}" | grep -c '^OK ' || true)
  ERR_REQ=$(printf '%s\n' "${TRAFFIC_LOG}" | grep -c '^ERR ' || true)
  UNIQUE_HOSTS=$(printf '%s\n' "${TRAFFIC_LOG}" | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p' | sort -u | wc -l | tr -d ' ')

  SUCCESS_RATE="0.00"
  if [[ "${TOTAL_REQ}" -gt 0 ]]; then
    SUCCESS_RATE=$(awk -v ok="${OK_REQ}" -v tot="${TOTAL_REQ}" 'BEGIN { printf "%.2f", (ok / tot) * 100 }')
  fi

  echo "  - 삭제된 Pod: ${VICTIM_POD}"
  echo "  - ReplicaSet 완전 복구 소요 시간: ${T1_ELAPSED}초"
  echo "  - 부하 요청 총계: ${TOTAL_REQ}건 (성공: ${OK_REQ}건, 실패: ${ERR_REQ}건)"
  echo "  - 서비스 무중단율(200 OK): ${SUCCESS_RATE}%"
  echo "  - 응답에 참여한 서로 다른 Pod 수: ${UNIQUE_HOSTS}개"
  kubectl get pods -n "${NAMESPACE}" -l app=guestbook
  echo ""

  kubectl delete pod "${CLIENT_POD}" -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

  # ----------------------------------------------------------------------------
  # 실험 2: Argo CD GitOps selfHeal Drift 자동 방어 검증
  # ----------------------------------------------------------------------------
  echo "----------------------------------------------------------------------"
  echo "[실험 2] 수동 스케일 변경(Drift) 시 Argo CD selfHeal 자동 복구 검증"
  echo "----------------------------------------------------------------------"
  if [[ "${HAS_ARGOCD}" == "true" ]]; then
    ORIGINAL_REPLICAS="$(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"
    log "수동 명령으로 replicas를 7로 변경 (Git 선언값=${ORIGINAL_REPLICAS}과 의도적 Drift 유발)"
    T2_START=$(date +%s)
    kubectl scale deployment guestbook -n "${NAMESPACE}" --replicas=7 >/dev/null
    sleep 1
    echo "  - Drift 직후 Deployment spec.replicas: $(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"

    T2_ELAPSED=0
    while true; do
      CURR_SPEC="$(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"
      if [[ "${CURR_SPEC}" == "${ORIGINAL_REPLICAS}" ]]; then
        T2_END=$(date +%s)
        T2_ELAPSED=$((T2_END - T2_START))
        break
      fi
      NOW=$(date +%s)
      if (( NOW - T2_START > 45 )); then
        log "경고: Argo CD selfHeal 대기 시간(45s) 초과"
        T2_ELAPSED=$((NOW - T2_START))
        break
      fi
      sleep 1
    done

    echo "  - Argo CD selfHeal 복원 완료: spec.replicas=${CURR_SPEC} (소요 시간: ${T2_ELAPSED}초)"
    kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}"
    echo ""
  else
    echo "  - Argo CD 미설치로 건너뜀"
    echo ""
  fi

  # ----------------------------------------------------------------------------
  # 실험 3: Redis 중단 시 Readiness Probe(503) 트래픽 격리 및 복구 검증
  # ----------------------------------------------------------------------------
  echo "----------------------------------------------------------------------"
  echo "[실험 3] Redis 중단 시 Readiness Probe(/readyz 503) 격리 및 자동 복구"
  echo "----------------------------------------------------------------------"
  if [[ "${HAS_ARGOCD}" == "true" ]]; then
    log "실험 중 Redis 축소가 selfHeal로 즉시 복원되지 않도록 Argo CD auto-sync 일시 해제"
    kubectl -n "${ARGOCD_NS}" patch application "${APP_NAME}" --type merge -p '{"spec":{"syncPolicy":null}}' >/dev/null
    ARGOCD_PAUSED="true"
  fi

  log "Redis Deployment replicas=0 축소 (DB 장애 시뮬레이션)"
  T3_DOWN_START=$(date +%s)
  kubectl scale deployment redis -n "${NAMESPACE}" --replicas=0 >/dev/null

  while true; do
    READY_COUNT="$(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    READY_COUNT="${READY_COUNT:-0}"
    if [[ "${READY_COUNT}" -eq 0 ]]; then
      break
    fi
    NOW=$(date +%s)
    if (( NOW - T3_DOWN_START > 45 )); then
      log "경고: Readiness 미준비 전환 대기 시간(45s) 초과"
      break
    fi
    sleep 1
  done
  T3_DOWN_END=$(date +%s)
  T3_DETECT_SEC=$((T3_DOWN_END - T3_DOWN_START))

  echo "  - Readiness Probe 503 격리 감지 소요 시간: ${T3_DETECT_SEC}초"
  kubectl get pods -n "${NAMESPACE}" -l app=guestbook
  echo "  - /readyz 직접 점검:"
  kubectl exec deployment/guestbook -n "${NAMESPACE}" -- python -c \
    "import urllib.request as u, urllib.error as e
try:
    print(u.urlopen('http://localhost:5000/readyz').read().decode())
except e.HTTPError as err:
    print('HTTP', err.code, err.read().decode().strip())" || true
  echo "  - Service EndpointSlice 상태 (ready=false 확인):"
  kubectl get endpointslices -n "${NAMESPACE}" -l "kubernetes.io/service-name=guestbook" \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'

  log "Redis Deployment replicas=1 복구 실행"
  T3_UP_START=$(date +%s)
  kubectl scale deployment redis -n "${NAMESPACE}" --replicas=1 >/dev/null
  kubectl rollout status deployment/redis -n "${NAMESPACE}" --timeout=60s >/dev/null

  while true; do
    READY_COUNT="$(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    DESIRED_COUNT="$(kubectl get deploy guestbook -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"
    READY_COUNT="${READY_COUNT:-0}"
    if [[ "${READY_COUNT}" -ge "${DESIRED_COUNT}" ]]; then
      break
    fi
    NOW=$(date +%s)
    if (( NOW - T3_UP_START > 60 )); then
      log "경고: Readiness 자동 복귀 대기 시간(60s) 초과"
      break
    fi
    sleep 1
  done
  T3_UP_END=$(date +%s)
  T3_RECOVER_SEC=$((T3_UP_END - T3_UP_START))

  echo "  - Redis 복구 후 Readiness 자동 복귀 소요 시간: ${T3_RECOVER_SEC}초"
  kubectl get pods -n "${NAMESPACE}"
  echo "  - 복구 후 Service EndpointSlice 상태:"
  kubectl get endpointslices -n "${NAMESPACE}" -l "kubernetes.io/service-name=guestbook" \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
  echo ""

  if [[ "${ARGOCD_PAUSED}" == "true" ]]; then
    kubectl apply -f "${REPO_ROOT}/argocd-application.yaml" >/dev/null
    ARGOCD_PAUSED="false"
    log "Argo CD syncPolicy (prune/selfHeal) 복원 완료"
  fi

  echo "======================================================================"
  echo "  최종 요약 (발표 및 project/README.md 기록용)"
  echo "======================================================================"
  echo "  1) Chaos Monkey (Pod 삭제): 무중단율 ${SUCCESS_RATE}% (${OK_REQ}/${TOTAL_REQ}), 복구 ${T1_ELAPSED}초, 분산 Pod ${UNIQUE_HOSTS}개"
  if [[ "${HAS_ARGOCD}" == "true" ]]; then
    echo "  2) GitOps selfHeal (Drift): 수동 replicas=7 -> ${ORIGINAL_REPLICAS} 자동 복원 (${T2_ELAPSED}초)"
  fi
  echo "  3) Readiness 503 격리: 장애 감지 ${T3_DETECT_SEC}초, Redis 복구 후 자동 투입 ${T3_RECOVER_SEC}초"
  echo "  * 리포트 저장 위치: ${REPORT_FILE}"
  echo "======================================================================"
