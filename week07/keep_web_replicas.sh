#!/bin/bash
# ==============================================================================
# Script Name: keep_web_replicas.sh
# Purpose    : Docker Compose 환경에서 web 인스턴스 3개(web=3)를 상시 유지하는 감시 데몬
# Description: 3주차 셸 스크립팅(while, if, sleep) + 4주차 파이프라인/grep + 7주차 compose CLI 활용
# ==============================================================================

# 스크립트 실행 위치 기준 경로 고정 (3주차 관용구)
cd "$(dirname "$0")/../guestbook" || exit 1

TARGET_SERVICE="web"
DESIRED_COUNT=3
CHECK_INTERVAL=3  # 3초마다 상태 점검

echo "=========================================================="
echo "[Reconciliation Daemon] Starting Web Replicas Watcher..."
echo "Target Service: ${TARGET_SERVICE} | Desired Count: ${DESIRED_COUNT}"
echo "=========================================================="

while true; do
    # 1. 현재 실행 중(running)인 web 서비스 컨테이너 개수 산출 (4주차 파이프, grep 활용)
    CURRENT_COUNT=$(docker compose ps --status running --format "{{.Service}}" 2>/dev/null | grep -c "^${TARGET_SERVICE}$")

    # 2. 원하는 레플리카 수(3개)와 비교
    if [ "$CURRENT_COUNT" -lt "$DESIRED_COUNT" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] Current ${TARGET_SERVICE} replicas: ${CURRENT_COUNT}/${DESIRED_COUNT}"
        echo "[ACTION] Restoring desired state: Running 'docker compose up -d --scale ${TARGET_SERVICE}=${DESIRED_COUNT}'..."
        
        # 3. 누락된 인스턴스를 즉시 스케일 아웃 및 재기동 (7주차 학습 내용)
        docker compose up -d --scale "${TARGET_SERVICE}=${DESIRED_COUNT}"
        
        RESTORED_COUNT=$(docker compose ps --status running --format "{{.Service}}" 2>/dev/null | grep -c "^${TARGET_SERVICE}$")
        echo "[RESULT] Restored successfully! Active replicas: ${RESTORED_COUNT}/${DESIRED_COUNT}"
    fi

    # 주기적 폴링 간격 대기
    sleep "$CHECK_INTERVAL"
done
