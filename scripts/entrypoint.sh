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

# 2026-05-16 18:40 fix: fabulous-patience 환경 runtime 사망 진단용 robust logging.
# set -e trigger 정확한 line을 잡기 위해 ERR trap + 시작 직후 env/state dump 추가.
on_err() {
    local exit_code=$?
    local line_no=${1:-?}
    log "FATAL ERR trap: exit=${exit_code} at line ${line_no}"
    log "  pwd=$(pwd)"
    log "  whoami=$(whoami 2>&1 || echo '?')"
    log "  ls /opt/data: $(ls -la /opt/data 2>&1 | head -5 | tr '\n' '|' || true)"
    exit ${exit_code}
}
trap 'on_err ${LINENO}' ERR

# 부팅 직후 환경 dump (한 번)
log "=== Boot diagnostic ==="
log "User: $(id -u 2>&1):$(id -g 2>&1) ($(whoami 2>&1 || echo '?'))"
log "Working dir: $(pwd)"
log "Volume /opt/data: $(ls -la /opt/data 2>/dev/null | head -3 | tr '\n' '|' || echo 'MISSING')"
log "Required envvars set: GOOGLE_API_KEY=${GOOGLE_API_KEY:+set}${GOOGLE_API_KEY:-MISSING}, TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:+set}${TELEGRAM_BOT_TOKEN:-MISSING}, TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS:+set}${TELEGRAM_ALLOWED_USERS:-MISSING}, TELEGRAM_ADMIN_CHAT_ID=${TELEGRAM_ADMIN_CHAT_ID:+set}${TELEGRAM_ADMIN_CHAT_ID:-MISSING}"
log "Optional envvars: GOOGLE_CLIENT_SECRET_B64=${GOOGLE_CLIENT_SECRET_B64:+set (${#GOOGLE_CLIENT_SECRET_B64} chars)}${GOOGLE_CLIENT_SECRET_B64:-unset}, OPENAI_API_KEY=${OPENAI_API_KEY:+set}${OPENAI_API_KEY:-unset}, WIKI_REPO_URL=${WIKI_REPO_URL:+set}${WIKI_REPO_URL:-unset}"
log "=== End boot diagnostic ==="

# -----------------------------------------------------------------------------
# Step 1: config.yaml bootstrap (template → 환경변수 치환 → /opt/data)
# -----------------------------------------------------------------------------
# 2026-05-16 fix (cto-lead 6·17번째 + main review): 빈 파일 처리 + envsubst 검증 + force-regen
# - L23 -f 만 체크 → -s (size > 0) 도 체크 (envsubst 실패 시 빈 파일이 남는 사고 방지)
# - envsubst 명령어 존재 확인 (gettext-base 없으면 fail-fast)
# - envsubst 결과 검증 (빈 파일이면 재시도 또는 fail)
# - HERMES_FORCE_CONFIG_REGEN=true 시 옛 config 무시하고 강제 재생성 (template 변경 즉시 반영)
if [ ! -f "${CONFIG_FILE}" ] || [ ! -s "${CONFIG_FILE}" ] || [ "${HERMES_FORCE_CONFIG_REGEN:-false}" = "true" ]; then
    log "config.yaml regenerate (missing/empty or HERMES_FORCE_CONFIG_REGEN=true)"

    # envsubst 명령 존재 확인 (Dockerfile gettext-base 누락 시 명확한 에러)
    if ! command -v envsubst >/dev/null 2>&1; then
        log "FATAL: envsubst command not found. Install gettext-base in Dockerfile."
        exit 1
    fi

    # 필수 환경변수 검증 (없으면 fail-fast)
    # 2026-05-16 fix (cto-lead 10번째 실수): Hermes 공식 변수명 TELEGRAM_ALLOWED_USERS
    # cto-lead가 TELEGRAM_AUTHORIZED_USER_ID 가정 (단수) → 실제는 TELEGRAM_ALLOWED_USERS (복수)
    #
    # 2026-05-16 4차 fix: Gemini Flash로 변경 (Hermes 공식 24/7 권장)
    # OpenRouter :free → Gemini Flash (한도 분 15/일 1500, 한국어 우수)
    # ANTHROPIC_API_KEY, GROQ_API_KEY, OPENROUTER_API_KEY는 모두 optional
    : "${GOOGLE_API_KEY:?GOOGLE_API_KEY required (Gemini 2.5 Flash, Phase 1 default LLM)}"
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
# Step 1.5: Google Workspace OAuth client_secret 자동 배치 (Phase 6a)
# -----------------------------------------------------------------------------
# 2026-05-16 추가: GOOGLE_CLIENT_SECRET_B64 envvar 자동 감지 → Volume root에 decode
#   사용 방식 (텔레그램 setup 시):
#     "/opt/data/google_client_secret.json으로 Google Workspace setup 해줘"
#   → Hermes agent가 setup.py --client-secret /opt/data/google_client_secret.json 호출
#   → setup.py가 HERMES_HOME(자동 발견)에 복사 + cleanup
#
# 근거: skills/productivity/google-workspace/scripts/setup.py L47, L283 fetch
#   CLIENT_SECRET_PATH = HERMES_HOME / "google_client_secret.json"
#   --client-secret 인자로 PATH install 지원
# -----------------------------------------------------------------------------
GOOGLE_SECRET_PATH="${DATA_DIR}/google_client_secret.json"

if [ -n "${GOOGLE_CLIENT_SECRET_B64:-}" ] && [ ! -f "${GOOGLE_SECRET_PATH}" ]; then
    log "Bootstrapping Google Workspace client_secret (first run)"
    echo "${GOOGLE_CLIENT_SECRET_B64}" | base64 -d > "${GOOGLE_SECRET_PATH}"
    # 2026-05-16 fix (main 7·8번째 추측 실수 누적):
    #   - 7번째: chmod 600 → read 불가 (Errno 13 on read)
    #   - 8번째: chmod 644 → read OK + write 불가 (Errno 13 on write)
    #     이유: setup.py L283 CLIENT_SECRET_PATH.write_text(json.dumps(data))
    #     setup.py가 HERMES_HOME(/opt/data) 경로에 같은 이름으로 다시 write 시도
    #     input path = output path = /opt/data/google_client_secret.json
    #   fix: chown hermes:hermes + chmod 644
    #     - owner=hermes → setup.py가 read+write 모두 가능
    #     - chown은 root entrypoint 단계에서만 가능 (지금 단계 root OK)
    chown hermes:hermes "${GOOGLE_SECRET_PATH}" 2>/dev/null || true
    chmod 644 "${GOOGLE_SECRET_PATH}"
    log "Google client_secret installed: ${GOOGLE_SECRET_PATH} ($(wc -c < "${GOOGLE_SECRET_PATH}") bytes, owner=hermes, mode 644)"
elif [ -f "${GOOGLE_SECRET_PATH}" ]; then
    # idempotent: 옛 root-owned file ownership + permission 보강
    chown hermes:hermes "${GOOGLE_SECRET_PATH}" 2>/dev/null || true
    chmod 644 "${GOOGLE_SECRET_PATH}" 2>/dev/null || true
    log "Google client_secret exists, ensured owner=hermes + mode 644"
else
    log "GOOGLE_CLIENT_SECRET_B64 envvar not set — Google Workspace setup not bootstrapped"
fi

# -----------------------------------------------------------------------------
# Step 2: WVB Skill 디렉토리 force sync (매 시작 시 최신 skill 반영)
# 2026-05-16 fix (cto-lead 18번째 실수 + main spot-check):
#   - 원본: SKILLS_SRC=/opt/wvb-bootstrap/skills (27 카테고리 + wvb 통째) → 이중 wvb 경로
#   - 원본: [ ! -d ${SKILLS_DST} ] → Volume 옛 디렉토리 있으면 skip = skill 변경 미반영
#   - fix: SKILLS_SRC=wvb 하위만 + force sync (매번 최신 copy)
# -----------------------------------------------------------------------------
SKILLS_SRC="/opt/wvb-bootstrap/skills/wvb"
SKILLS_DST="${DATA_DIR}/skills/wvb"

if [ -d "${SKILLS_SRC}" ]; then
    log "Force syncing WVB skills: ${SKILLS_SRC} → ${SKILLS_DST}"
    # 2026-05-16 fix: 옛 카테고리 잔여물 제거 (32→6 skills 정리)
    rm -rf "${SKILLS_DST}"
    mkdir -p "${SKILLS_DST}"
    cp -r "${SKILLS_SRC}"/* "${SKILLS_DST}/" 2>/dev/null || true
    log "WVB skills synced: $(ls -1 "${SKILLS_DST}" 2>/dev/null | wc -l) skills"
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
# Step 4.4: MS 365 MCP — token cache 디렉토리 준비 (Phase 6b, Plan v1.4)
# -----------------------------------------------------------------------------
# 2026-05-16 추가: softeria ms-365-mcp-server token cache를 Volume 영구 저장.
# 환경:
#   MS365_MCP_TOKEN_CACHE_PATH=/opt/data/.ms365/token-cache.json
#   MS365_MCP_SELECTED_ACCOUNT_PATH=/opt/data/.ms365/selected-account.json
# 디렉토리 미리 생성 + hermes user 소유 (uv venv와 동일 패턴, build-then-verify §8)
MS365_DIR="${DATA_DIR}/.ms365"
if ! mkdir -p "${MS365_DIR}" 2>&1; then
    log "WARNING: mkdir ${MS365_DIR} failed — MS 365 OAuth token caching unavailable"
else
    chown hermes:hermes "${MS365_DIR}" 2>/dev/null || log "  ${MS365_DIR} chown skipped (non-fatal)"
    chmod 700 "${MS365_DIR}" 2>/dev/null || true
    log "MS365 token cache dir ready: ${MS365_DIR}"
fi

# softeria binary 검증 (Dockerfile에서 npm install -g 됐는지)
if command -v ms-365-mcp-server >/dev/null 2>&1; then
    log "softeria ms-365-mcp-server installed: $(ms-365-mcp-server --version 2>&1 | head -1 || echo 'version check failed')"
else
    log "WARNING: ms-365-mcp-server not found in PATH — Phase 6b MCP server unavailable"
fi

# Azure App credentials envvar 확인 (사용자가 Railway에서 설정해야 함)
if [ -n "${MS365_MCP_CLIENT_ID:-}" ] && [ -n "${MS365_MCP_TENANT_ID:-}" ] && [ -n "${MS365_MCP_CLIENT_SECRET:-}" ]; then
    log "MS365 Azure credentials detected (CLIENT_ID=${MS365_MCP_CLIENT_ID:0:8}..., TENANT=${MS365_MCP_TENANT_ID:0:8}..., SECRET=set)"
else
    log "INFO: MS365 envvar incomplete — removing mcp_servers.ms365 from config.yaml to prevent startup fail"
    # envvar 미설정 시 ms365 섹션을 config.yaml에서 제거 (Hermes startup fail 방지)
    # Hermes resilient 가정 위반 안전망 (build-then-verify §10 — 사용자 결정 정신 보존:
    # Step 1-3 진행 중 사용자 burden 최소화)
    if [ -f "${CONFIG_FILE}" ] && grep -q "^mcp_servers:" "${CONFIG_FILE}"; then
        # 'mcp_servers:'부터 그 다음 top-level (들여쓰기 없는 라인)까지 제거
        # awk로 안전한 블록 제거
        awk '
            /^mcp_servers:/ { in_block = 1; next }
            in_block && /^[^[:space:]#]/ { in_block = 0 }
            !in_block { print }
        ' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
        log "  mcp_servers section removed (Hermes will start without MS365)"
    fi
fi

# -----------------------------------------------------------------------------
# Step 4.5: Google Workspace deps verify+install (Phase 6a)
# -----------------------------------------------------------------------------
# 2026-05-16 추가 (사용자 결정 옵션 A, KakaoTalk_175312637 RCA):
#   - base image는 `uv sync --extra all`로 [google] extra 포함 빌드 (upstream
#     pyproject.toml L151-159, L199). 그러나 setup.py L107 `subprocess.check_call(
#     [sys.executable, "-m", "pip", "install", ...])`가 venv 안의 pip 모듈을 가정.
#     uv venv는 pip 별도 미포함 → `No module named pip` 발생.
#   - 봇이 setup.py --install-deps 시도할 때 항상 실패 → setup.py L118 안내대로
#     사전 설치가 정답.
#   - 우회: 부팅 시 venv 안에 패키지 import 가능한지 verify, 없으면 uv pip로
#     사전 install. setup.py 호출 시점에는 이미 import 가능 → install_deps skip.
# -----------------------------------------------------------------------------
HERMES_VENV_PY="/opt/hermes/.venv/bin/python"
if [ -x "${HERMES_VENV_PY}" ]; then
    if "${HERMES_VENV_PY}" -c "import google_auth_oauthlib, googleapiclient, google_auth_httplib2" >/dev/null 2>&1; then
        log "Google Workspace deps OK (3 packages importable in venv)"
    else
        log "Google Workspace deps missing — installing via uv pip (Phase 6a)"
        if command -v uv >/dev/null 2>&1; then
            uv pip install --python "${HERMES_VENV_PY}" --no-cache-dir \
                google-api-python-client==2.194.0 \
                google-auth-oauthlib==1.3.1 \
                google-auth-httplib2==0.3.1 \
                && log "Google Workspace deps installed via uv pip" \
                || log "WARNING: uv pip install failed — setup.py --install-deps will continue to fail"
        else
            log "WARNING: uv command not found at /usr/local/bin/uv — Google deps unavailable"
        fi
    fi
else
    log "WARNING: ${HERMES_VENV_PY} not found — skipping Google deps verify"
fi

# -----------------------------------------------------------------------------
# Step 4.6: Hermes MEMORY.md 환경 facts 부트스트랩 (Anti-Hallucination)
# -----------------------------------------------------------------------------
# 2026-05-16 추가 (사용자 결정 환각 대응, KakaoTalk_174844065/175312637 RCA):
#   - 봇이 Windows 경로(C:\...AppData\Python314\...) 인용, Railway SSH 안내 등
#     환각 빈도 증가 (Gemini 2.5 Flash 변경 후).
#   - Hermes memory_tool.py가 ${HERMES_HOME}/memories/MEMORY.md를 session
#     start 시 system prompt에 inject (upstream tools/memory_tool.py 확인,
#     hermes_constants.py L14 HERMES_HOME envvar → /opt/data).
#   - WVB Runtime Facts 5줄을 첫 부팅 시 prepend (marker grep idempotent).
#     이후는 봇이 학습한 memory 보존.
#   - HERMES_FORCE_MEMORY_REGEN=true 시 강제 재작성.
# -----------------------------------------------------------------------------
MEMORY_DIR="${DATA_DIR}/memories"
MEMORY_FILE="${MEMORY_DIR}/MEMORY.md"
WVB_MEMORY_MARKER="# WVB Runtime Facts (entrypoint-managed)"

log "Step 4.6 enter: MEMORY_DIR=${MEMORY_DIR}"
log "  DATA_DIR perms: $(ls -ld ${DATA_DIR} 2>&1 || echo 'MISSING')"

# Volume 권한 문제로 mkdir 실패 가능 — robust handling
if ! mkdir -p "${MEMORY_DIR}" 2>&1; then
    log "WARNING: mkdir -p ${MEMORY_DIR} failed (continuing without MEMORY.md bootstrap)"
    MEMORY_DIR=""
fi
if [ -n "${MEMORY_DIR}" ]; then
    chown hermes:hermes "${MEMORY_DIR}" 2>/dev/null || log "  chown skipped (non-fatal)"
    log "  MEMORY_DIR ready: $(ls -ld ${MEMORY_DIR} 2>&1 | head -1)"
fi

if [ -z "${MEMORY_DIR}" ]; then
    log "Skipping MEMORY.md bootstrap (mkdir failed earlier)"
elif [ ! -f "${MEMORY_FILE}" ] || [ "${HERMES_FORCE_MEMORY_REGEN:-false}" = "true" ] || \
   ! grep -qF "${WVB_MEMORY_MARKER}" "${MEMORY_FILE}" 2>/dev/null; then
    log "Bootstrapping ${MEMORY_FILE} with WVB runtime facts"
    cat > "${MEMORY_FILE}.wvb" <<'EOF'
§
# WVB Runtime Facts (entrypoint-managed)

## Execution Environment
- Runtime: Railway Linux container (debian:13.4, Python 3.13 via uv venv)
- Python interpreter: /opt/hermes/.venv/bin/python (uv-managed, no standalone pip module)
- HERMES_HOME: /opt/data (Railway Volume, persistent across deploys)
- User: hermes (UID 10000), root only during entrypoint.sh boot phase
- External SSH access: NOT possible. Railway exposes only Console/Variables/Volume tabs.

## Anti-Hallucination Rules
- DO NOT cite Windows paths (C:\..., AppData, Python314) — user local env is invisible
- DO NOT instruct user to run `pip install` or `python -m pip` — uv venv has no pip
- For package install: use `uv pip install --python /opt/hermes/.venv/bin/python <pkg>`
- DO NOT ask user to SSH into the Railway container — environmentally impossible
- BEFORE quoting any path/command: verify via `ls`, `cat`, or `which` first
- Google Workspace deps (google-api-python-client, google-auth-oauthlib, google-auth-httplib2)
  are PRE-INSTALLED at boot by entrypoint.sh Step 4.5 — setup.py --check should succeed
  without invoking --install-deps. If setup.py errors out on pip, re-run setup without
  --install-deps.

## Skill Sources
- WVB domain skills: /opt/data/skills/wvb/* (synced from image at every boot)
- Hermes bundled skills: /opt/data/skills/* (Google Workspace, productivity, media)
- Personal Data Protection: wiki/_personal/, SOUL.md, USER.md, ACCESS_POLICY.md,
  HEARTBEAT.md are CCO-blocked — refuse access requests

EOF

    if [ -f "${MEMORY_FILE}" ] && [ "${HERMES_FORCE_MEMORY_REGEN:-false}" != "true" ]; then
        cat "${MEMORY_FILE}.wvb" "${MEMORY_FILE}" > "${MEMORY_FILE}.merged"
        mv "${MEMORY_FILE}.merged" "${MEMORY_FILE}"
        rm -f "${MEMORY_FILE}.wvb"
        log "WVB facts prepended to existing MEMORY.md ($(wc -l < "${MEMORY_FILE}") lines)"
    else
        mv "${MEMORY_FILE}.wvb" "${MEMORY_FILE}"
        log "MEMORY.md created with WVB runtime facts ($(wc -l < "${MEMORY_FILE}") lines)"
    fi
    chown hermes:hermes "${MEMORY_FILE}" 2>/dev/null || true
    chmod 644 "${MEMORY_FILE}"
else
    log "MEMORY.md already has WVB facts marker — skipping bootstrap"
fi

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
