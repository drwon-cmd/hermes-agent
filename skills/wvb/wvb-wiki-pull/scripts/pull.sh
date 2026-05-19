#!/usr/bin/env bash
# =============================================================================
# WVB Wiki Pull (Script-Only Cron)
# - Hermes cron 매 4시간 SGT 자동 발사 (0 */4 * * *)
# - 또는 사용자 자연어 수동 호출
# - stdout 비어있으면 silent tick. 출력 있으면 텔레그램 알림.
# =============================================================================
set -uo pipefail  # -e 안 씀: 일부 실패해도 다음 단계 계속 (Personal data scrub 등)

WIKI_DIR="/opt/data/wiki"
LOG_PREFIX="[wiki-pull]"

# Step 1: 디렉토리 존재 확인 (entrypoint clone 실패 케이스 대비)
if [ ! -d "${WIKI_DIR}/.git" ]; then
    echo "${LOG_PREFIX} ERROR: ${WIKI_DIR}/.git not found (initial clone may have failed)"
    exit 0  # silent fail — entrypoint 재시도 영역
fi

# Step 2: 현재 commit 기록 (변경 감지용)
BEFORE_SHA=$(git -C "${WIKI_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")

# Step 3: git pull --rebase --quiet
# Note: WIKI_REPO_URL은 origin remote에 이미 PAT 포함. 추가 인증 불필요.
PULL_OUTPUT=$(git -C "${WIKI_DIR}" pull --rebase --quiet 2>&1)
PULL_EXIT=$?

if [ ${PULL_EXIT} -ne 0 ]; then
    # rebase conflict 또는 네트워크 오류
    echo "${LOG_PREFIX} ERROR (exit ${PULL_EXIT}): ${PULL_OUTPUT}" | head -c 500
    # Conflict 시 abort 후 다음 cycle 재시도 (force overwrite 금지)
    if echo "${PULL_OUTPUT}" | grep -qi "conflict\|rebase"; then
        git -C "${WIKI_DIR}" rebase --abort 2>/dev/null || true
        echo "${LOG_PREFIX} rebase aborted, will retry next cycle"
    fi
    exit 0
fi

AFTER_SHA=$(git -C "${WIKI_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")

# Step 4: Personal data scrub (pull로 _personal 등 재유입 가능성 차단)
SCRUBBED=0
if [ -d "${WIKI_DIR}/wiki/_personal" ]; then
    rm -rf "${WIKI_DIR}/wiki/_personal" 2>/dev/null && SCRUBBED=$((SCRUBBED+1))
fi
# 4개 sensitive 파일 패턴 (entrypoint.sh와 동일)
SCRUB_COUNT=$(find "${WIKI_DIR}" -type f \( \
    -name "SOUL.md" -o \
    -name "USER.md" -o \
    -name "ACCESS_POLICY.md" -o \
    -name "HEARTBEAT.md" \
    \) -print -delete 2>/dev/null | wc -l)
SCRUBBED=$((SCRUBBED + SCRUB_COUNT))

# Step 5: 결과 판정 → stdout
if [ "${BEFORE_SHA}" = "${AFTER_SHA}" ]; then
    # Already up to date — silent tick (stdout 비움)
    exit 0
else
    # 변경 있음 — 알림 메시지 생성
    BEFORE_SHORT="${BEFORE_SHA:0:8}"
    AFTER_SHORT="${AFTER_SHA:0:8}"
    CHANGED_COUNT=$(git -C "${WIKI_DIR}" diff --name-only "${BEFORE_SHA}" "${AFTER_SHA}" 2>/dev/null | wc -l)
    CHANGED_SAMPLE=$(git -C "${WIKI_DIR}" diff --name-only "${BEFORE_SHA}" "${AFTER_SHA}" 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//')

    echo "${LOG_PREFIX} ✅ ${BEFORE_SHORT} → ${AFTER_SHORT} (${CHANGED_COUNT} files: ${CHANGED_SAMPLE}${CHANGED_COUNT:+...})"
    if [ ${SCRUBBED} -gt 0 ]; then
        echo "${LOG_PREFIX} 🔒 personal data scrubbed: ${SCRUBBED} items"
    fi
    exit 0
fi
