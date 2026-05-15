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
if [ ! -f "${CONFIG_FILE}" ]; then
    log "config.yaml not found, bootstrapping from template"

    # 필수 환경변수 검증 (없으면 fail-fast)
    : "${GROQ_API_KEY:?GROQ_API_KEY required}"
    : "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY required}"
    : "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN required}"
    : "${TELEGRAM_AUTHORIZED_USER_ID:?TELEGRAM_AUTHORIZED_USER_ID required}"
    : "${TELEGRAM_ADMIN_CHAT_ID:?TELEGRAM_ADMIN_CHAT_ID required}"

    # envsubst로 ${VAR} 치환
    envsubst < "${TEMPLATE_FILE}" > "${CONFIG_FILE}"
    log "config.yaml written: ${CONFIG_FILE}"
else
    log "config.yaml exists, skipping bootstrap"
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
if [ ! -d "${WIKI_DIR}/.git" ] && [ -n "${WIKI_REPO_URL:-}" ]; then
    log "Cloning wiki repo (shallow, read-only): ${WIKI_REPO_URL}"
    git clone --depth 1 "${WIKI_REPO_URL}" "${WIKI_DIR}" || \
        log "WARNING: wiki clone failed (continuing without wiki)"

    # _personal, SOUL 강제 제외 (Personal Data Protection)
    if [ -d "${WIKI_DIR}/_personal" ]; then
        log "SECURITY: removing wiki/_personal/ (CCO block)"
        rm -rf "${WIKI_DIR}/_personal"
    fi
    # find로 SOUL.md, USER.md, ACCESS_POLICY.md, HEARTBEAT.md 제거
    find "${WIKI_DIR}" -type f \( \
        -name "SOUL.md" -o \
        -name "USER.md" -o \
        -name "ACCESS_POLICY.md" -o \
        -name "HEARTBEAT.md" \
        \) -exec rm -f {} \;
fi

# -----------------------------------------------------------------------------
# Step 4: 시크릿 누수 grep 체크 (build-then-verify Pattern §6)
# -----------------------------------------------------------------------------
if grep -rE "sk-[a-zA-Z0-9_-]{20,}|gsk_[a-zA-Z0-9_-]{20,}|ghp_[a-zA-Z0-9]{30,}" \
    "${TEMPLATE_FILE}" "/opt/wvb-bootstrap/skills/" 2>/dev/null; then
    log "FATAL: hardcoded secret detected in template/skills — refusing to start"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 5: Hermes gateway 시작
# -----------------------------------------------------------------------------
log "Starting Hermes gateway: $*"
log "Config: ${CONFIG_FILE}"
log "Data dir: ${DATA_DIR}"
log "Wiki: ${WIKI_DIR} ($(ls -1 "${WIKI_DIR}" 2>/dev/null | wc -l) entries)"

# Hermes 공식 entrypoint 위임
exec hermes "$@"
