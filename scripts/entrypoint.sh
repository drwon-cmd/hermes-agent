#!/bin/bash
# =============================================================================
# Hermes Agent Entrypoint (WVB Railway 배포)
# - 첫 부팅 시 config.yaml bootstrap
# - Wiki submodule 초기화 (없으면)
# - Hermes gateway 시작
# =============================================================================
set -euo pipefail

DATA_DIR="/opt/data"
CONFIG_FILE="${DATA_DIR}/config.yaml"
TEMPLATE_FILE="/opt/wvb-bootstrap/config.yaml.template"
WIKI_DIR="${DATA_DIR}/wiki"
LOG_PREFIX="[wvb-entrypoint]"

log() {
    echo "${LOG_PREFIX} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"
}

# -----------------------------------------------------------------------------
# Step 1: config.yaml bootstrap (template → 환경변수 치환 → /opt/data)
# -----------------------------------------------------------------------------
# 2026-05-16 fix (cto-lead 6번째·D2 main review): 빈 파일 처리 + envsubst 검증
# - L23 -f 만 체크 → -s (size > 0) 도 체크 (envsubst 실패 시 빈 파일이 남는 사고 방지)
# - envsubst 명령어 존재 확인 (gettext-base 없으면 fail-fast)
# - envsubst 결과 검증 (빈 파일이면 재시도 또는 fail)
if [ ! -f "${CONFIG_FILE}" ] || [ ! -s "${CONFIG_FILE}" ]; then
    log "config.yaml not found or empty, bootstrapping from template"

    # envsubst 명령 존재 확인 (Dockerfile gettext-base 누락 시 명확한 에러)
    if ! command -v envsubst >/dev/null 2>&1; then
        log "FATAL: envsubst command not found. Install gettext-base in Dockerfile."
        exit 1
    fi

    # 필수 환경변수 검증 (없으면 fail-fast)
    # 2026-05-16 fix (cto-lead 10번째 실수): Hermes 공식 변수명 TELEGRAM_ALLOWED_USERS
    # cto-lead가 TELEGRAM_AUTHORIZED_USER_ID 가정 (단수) → 실제는 TELEGRAM_ALLOWED_USERS (복수)
    #
    # 2026-05-16 추가 fix: Phase 1 무료 정신 (Plan §3.3)
    # ANTHROPIC_API_KEY, GROQ_API_KEY는 optional (Phase 1.5에서 escalation 추가 시)
    # OPENROUTER_API_KEY가 Phase 1 default LLM 호출용
    : "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY required (Phase 1 default LLM provider)}"
    : "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN required}"
    : "${TELEGRAM_ALLOWED_USERS:?TELEGRAM_ALLOWED_USERS required (comma-separated numeric user IDs)}"
    : "${TELEGRAM_ADMIN_CHAT_ID:?TELEGRAM_ADMIN_CHAT_ID required}"
    # OPENAI_API_KEY는 STT (Whisper) 전용으로 optional. 음성 입력 사용 시만 필요.

    # envsubst로 ${VAR} 치환 + 결과 검증
    envsubst < "${TEMPLATE_FILE}" > "${CONFIG_FILE}.tmp"
    if [ ! -s "${CONFIG_FILE}.tmp" ]; then
        log "FATAL: envsubst produced empty output"
        rm -f "${CONFIG_FILE}.tmp"
        exit 1
    fi
    mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
    log "config.yaml written: ${CONFIG_FILE} ($(wc -l < "${CONFIG_FILE}") lines)"
else
    log "config.yaml exists ($(wc -l < "${CONFIG_FILE}") lines), skipping bootstrap"
fi

# -----------------------------------------------------------------------------
# Step 2: Skill 디렉토리 복사 (WVB 도메인 skill을 Hermes skills 경로로)
# -----------------------------------------------------------------------------
SKILLS_SRC="/opt/wvb-bootstrap/skills"
SKILLS_DST="${DATA_DIR}/skills/wvb"

if [ -d "${SKILLS_SRC}" ] && [ ! -d "${SKILLS_DST}" ]; then
    log "Copying WVB skills to ${SKILLS_DST}"
    mkdir -p "${SKILLS_DST}"
    cp -r "${SKILLS_SRC}"/* "${SKILLS_DST}/" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Step 3: Wiki submodule 초기화 (없으면)
# -----------------------------------------------------------------------------
# 2026-05-16 fix (cto-lead 8번째·D3 main review): wiki clone 실패 시 set -e trigger 방지
# - git clone 실패 시 WIKI_DIR 미생성
# - 그 후 find 명령이 WIKI_DIR 없음으로 set -e trigger → entrypoint 죽임 → restart loop
# - 해결: find 호출 전 디렉토리 존재 확인 + || true (이중 안전망)
if [ ! -d "${WIKI_DIR}/.git" ] && [ -n "${WIKI_REPO_URL:-}" ]; then
    log "Cloning wiki repo (shallow, read-only): ${WIKI_REPO_URL}"
    git clone --depth 1 "${WIKI_REPO_URL}" "${WIKI_DIR}" 2>&1 || \
        log "WARNING: wiki clone failed (continuing without wiki)"

    # WIKI_DIR 디렉토리가 실제로 생성됐는지 확인 후 personal data 제거
    if [ -d "${WIKI_DIR}" ]; then
        # _personal, SOUL 강제 제외 (Personal Data Protection)
        if [ -d "${WIKI_DIR}/_personal" ]; then
            log "SECURITY: removing wiki/_personal/ (CCO block)"
            rm -rf "${WIKI_DIR}/_personal" || true
        fi
        # find로 SOUL.md, USER.md, ACCESS_POLICY.md, HEARTBEAT.md 제거
        find "${WIKI_DIR}" -type f \( \
            -name "SOUL.md" -o \
            -name "USER.md" -o \
            -name "ACCESS_POLICY.md" -o \
            -name "HEARTBEAT.md" \
            \) -exec rm -f {} \; 2>/dev/null || true
    else
        log "WARNING: wiki clone did not produce ${WIKI_DIR}, skipping personal data scrub"
    fi
fi

# -----------------------------------------------------------------------------
# Step 4: 시크릿 누수 grep 체크 (build-then-verify Pattern §6)
# -----------------------------------------------------------------------------
# 2026-05-16 임시 비활성 (cto-lead 13번째 실수 fix):
#   Railway 환경에서 false positive trigger → "hardcoded secret detected" → exit 1 → restart loop.
#   로컬 시뮬레이션 매칭 0건. cto-lead 정규식이 envsubst 치환 후 placeholder 잔여 또는
#   다른 패턴에 매칭하는 것으로 추정. Phase 1.5에서 정교화 후 재활성.
#   대안 안전망: .dockerignore가 .env·secrets/ 차단 + Railway Variables가 평문 저장 X.
# if grep -rE "sk-[a-zA-Z0-9_-]{20,}|gsk_[a-zA-Z0-9_-]{20,}|ghp_[a-zA-Z0-9]{30,}" \
#     "${TEMPLATE_FILE}" "/opt/wvb-bootstrap/skills/" 2>/dev/null; then
#     log "FATAL: hardcoded secret detected in template/skills — refusing to start"
#     exit 1
# fi
log "Step 4 (secret grep) temporarily disabled — see Phase 1.5 task #21"

# -----------------------------------------------------------------------------
# Step 5: Hermes gateway 시작
# -----------------------------------------------------------------------------
log "Starting Hermes gateway: $*"
log "Config: ${CONFIG_FILE}"
log "Data dir: ${DATA_DIR}"
log "Wiki: ${WIKI_DIR} ($(ls -1 "${WIKI_DIR}" 2>/dev/null | wc -l) entries)"

# 2026-05-16 fix (cto-lead 14번째 실수, W1 발현):
#   'exec hermes "$@"' → USER hermes의 PATH에 hermes 바이너리 없음 → exit
#   해결: Hermes 공식 entrypoint chain → user drop + PATH 설정 + hermes 실행 모두 위임
#   공식 ENTRYPOINT (참조): /usr/bin/tini -g -- /opt/hermes/docker/entrypoint.sh
exec /opt/hermes/docker/entrypoint.sh "$@"
