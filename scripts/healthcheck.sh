#!/bin/bash
# =============================================================================
# Healthcheck — Railway가 /health 엔드포인트 polling
# - Hermes gateway가 응답하면 OK
# - 응답 없으면 Railway가 재시작 (restartPolicyMaxRetries=5)
# =============================================================================
set -e

# Hermes gateway는 기본 port 8642에서 /health 엔드포인트 제공
HEALTH_URL="http://127.0.0.1:8642/health"

# curl로 HTTP 200 확인 (10초 timeout)
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 10 "${HEALTH_URL}" 2>/dev/null || echo "000")

if [ "${HTTP_CODE}" = "200" ]; then
    exit 0
else
    echo "[healthcheck] gateway not responding (HTTP ${HTTP_CODE})"
    exit 1
fi
