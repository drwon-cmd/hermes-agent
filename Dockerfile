# =============================================================================
# Hermes Agent — WVB 24/7 비서실장 (Railway 배포용)
# Base: nousresearch/hermes-agent:main 공식 이미지 위에 WVB layer 추가
# =============================================================================
#
# 설계 결정 (Design §2 → 공식 검증 반영):
#  - 공식 이미지를 base로 사용 (직접 multi-stage build 회피 → 빌드 시간 단축)
#  - debian:13.4 + Python 3.13 + uv + tini + ffmpeg + ripgrep + Node 22 기본 포함
#  - Gateway 모드 `gateway run` 사용 (port 8642 healthcheck endpoint 제공)
#  - Wiki submodule은 빌드 시 fetch (read-only), cron으로 6시간마다 갱신
#  - Railway는 비루트 실행 강제 안 함 (공식 이미지는 node user 사용)
#
# Base image tag 이력:
#  2026-05-15: v0.13.0 → main 변경. v0.13.0은 GitHub release tag일 뿐 Docker Hub
#  publish 없음. cto-lead 산출 실수 (Plan/Design Q2 결정과 충돌).
#  Phase 1 안정 7-14일 후 최신 sha- 태그로 pin 전환 예정 (Task #12).
#
# 검증 상태: Docker Hub tag 페이지 + 공식 docker docs 재확인 (2026-05-15)
# =============================================================================

ARG HERMES_VERSION=main
FROM nousresearch/hermes-agent:${HERMES_VERSION}

# -----------------------------------------------------------------------------
# WVB 추가 시스템 패키지 (공식 이미지가 git/ripgrep/ffmpeg 이미 포함, 보강용)
# -----------------------------------------------------------------------------
USER root

# 한국어 locale (한글 응답 안정성 - UTF-8 인코딩 보장)
# 2026-05-16 추가: gettext-base (envsubst 명령 — cto-lead 6번째 실수 fix)
# 2026-05-18 추가: fonts-noto-cjk — wvb-meeting-memo PDF 한국어 폰트 fallback
#   reportlab CID HYGothic-Medium만으로도 동작하지만 TTF 우선 (가독성 ↑)
#   Plan: docs/plans/2026-05-18-meeting-memo-from-voice.md §5
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    tzdata \
    gettext-base \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && echo "ko_KR.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen \
    && ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime

# 2026-05-16 Phase 6b: softeria ms-365-mcp-server 사전 install (Plan v1.4 §Path B)
# 근거: Hermes mcp_servers spawn stdio subprocess → npx 런타임 install은 첫 호출 지연 +
#       network 불안정 시 fail. 글로벌 install로 안정성 우선.
# npm publish: @softeria/ms-365-mcp-server v0.108.0 (2026-05 fetch 검증, MIT)
# build-then-verify v1.7 §8 외부 의존 spot-check 통과
RUN npm install -g @softeria/ms-365-mcp-server@0.108.0 \
    && npm cache clean --force

# 2026-05-18: wvb-meeting-memo PDF 생성용 Python 의존성
# - reportlab 4.5.1: Markdown → PDF 변환 (CID HYGothic-Medium 한국어 내장)
# - pypdf 6.11.0: 생성된 PDF page count 추출 (Telegram caption용)
# Plan: docs/plans/2026-05-18-meeting-memo-from-voice.md §5
# Pypi fetch 검증 (2026-05-18): reportlab 4.5.1 (2026-05-12 release), pypdf 6.11.0 (2026-05-09)
# uv venv path = /opt/hermes/.venv (Dockerfile L73 .bash_profile auto-activate)
#
# 2026-05-19 fix (build 실패 RCA — feedback_uv_venv_pip_mismatch 재발):
#   - 첫 시도 `/opt/hermes/.venv/bin/pip` → exit 127 (pip not found)
#   - 근본: uv venv는 pip binary 미생성. `uv pip` 사용 필수
#   - 메모리에 박제된 fix template 그대로 적용
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir \
    reportlab==4.5.1 \
    pypdf==6.11.0

# 2026-05-19: WVB patch — Telegram msg.audio dynamic extension fix (upstream bug)
# 원본 base image의 gateway/platforms/telegram.py L4276 msg.audio 핸들러가 모든
# audio 파일을 .mp3로 강제 캐시 → m4a/aac/flac 첨부 시 Whisper API mime mismatch
# 거부 발생. msg.video 패턴 차용해서 file_name/file_path에서 동적 ext 결정.
#
# 사고: 2026-05-19 ~01:00 SGT 사용자가 m4a 첨부 → "지원되는 오디오 파일 형식이
#   아니어서" 봇 거부. wvb-meeting-memo skill의 STT 전사 0건.
# Fix 방식: fork의 gateway/platforms/telegram.py를 base image의 동일 path에 overlay.
# 검증: base image upgrade 시 telegram.py upstream 변경 확인 필요 (별도 task).
COPY --chown=hermes:hermes gateway/platforms/telegram.py /tmp/wvb-telegram.py
RUN PATCH_TARGET=$(/opt/hermes/.venv/bin/python -c "import gateway.platforms.telegram as t; print(t.__file__)") \
    && [ -n "$PATCH_TARGET" ] && [ -f "$PATCH_TARGET" ] \
    && cp /tmp/wvb-telegram.py "$PATCH_TARGET" \
    && rm -f /tmp/wvb-telegram.py \
    && echo "[wvb-patch] telegram.py overlayed at $PATCH_TARGET"

# -----------------------------------------------------------------------------
# 2026-05-18: hermes user .bash_profile + .profile 에 venv auto-activate 추가
# -----------------------------------------------------------------------------
# 근거: tools/environments/base.py init_session() 이 bash -l -c '...' 로 snapshot
#   캡처 → hermes user 의 login shell rc 파일이 venv 를 source 하지 않으면
#   snapshot PATH 에 venv (/opt/hermes/.venv/bin) 없음 → 이후 모든 'python ...'
#   호출이 "command not found" 로 실패.
#
# 사고 이력: 2026-05-18 wvb-daily-brief cron 실패 (bare python not found).
#   v2.1.1 SKILL 절대경로 fix 는 ad-hoc — SKILL 작성자가 매번 venv 절대경로를
#   써야 누락 위험. 본 fix 는 root cause (login shell PATH) 직접 해결.
#
# 위치 선택:
#   - .bash_profile: login shell 이 자동 source (bash -l). interactivity guard 없음.
#   - .profile: .bash_profile 없을 때 fallback. 일부 distro 가 사용.
#   - .bashrc 는 의도적으로 제외 — Debian default 첫 줄 interactivity guard
#     (case $- in *i*) ;; *) return;; esac) 가 non-interactive 호출에서
#     early return 시켜 우리 append 라인 미실행.
#
# Idempotent: grep guard 로 marker 중복 방지. 이미지 rebuild 시 중복 append 차단.
RUN HOME_HERMES="$(getent passwd hermes | cut -d: -f6)" \
    && [ -n "${HOME_HERMES}" ] || (echo "FATAL: hermes user not found in /etc/passwd" && exit 1) \
    && mkdir -p "${HOME_HERMES}" \
    && for rcfile in "${HOME_HERMES}/.bash_profile" "${HOME_HERMES}/.profile"; do \
         touch "$rcfile"; \
         if ! grep -q "wvb-venv-activate" "$rcfile" 2>/dev/null; then \
           printf '\n# wvb-venv-activate (Dockerfile-injected, 2026-05-18 cron RCA)\n[ -f /opt/hermes/.venv/bin/activate ] && . /opt/hermes/.venv/bin/activate\n' >> "$rcfile"; \
         fi; \
         chown hermes:hermes "$rcfile"; \
       done \
    && echo "hermes user dotfiles patched: HOME=${HOME_HERMES}"

ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    LANGUAGE=ko_KR:ko \
    TZ=Asia/Singapore \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# -----------------------------------------------------------------------------
# WVB Config Bootstrap
# -----------------------------------------------------------------------------
# config.yaml은 Railway 첫 부팅 시 /opt/data 에 없으면 이 스크립트가 복사
# -----------------------------------------------------------------------------
WORKDIR /opt/wvb-bootstrap

# Skill 디렉토리 (WVB 도메인 룰 미러링)
COPY --chown=hermes:hermes config.yaml.template /opt/wvb-bootstrap/config.yaml.template
COPY --chown=hermes:hermes skills/ /opt/wvb-bootstrap/skills/
COPY --chown=hermes:hermes scripts/entrypoint.sh /opt/wvb-bootstrap/entrypoint.sh
COPY --chown=hermes:hermes scripts/healthcheck.sh /opt/wvb-bootstrap/healthcheck.sh

RUN chmod +x /opt/wvb-bootstrap/entrypoint.sh /opt/wvb-bootstrap/healthcheck.sh

# -----------------------------------------------------------------------------
# Wiki 디렉토리 처리: entrypoint.sh runtime에서 git clone으로 자동 생성
# 빌드 시점 mkdir/chown 시도 → 실패 (Hermes 이미지가 /opt/data를 VOLUME 선언).
# 보안: wiki 콘텐츠를 이미지에 굽지 않음 (이미지 layer cache 외부 노출 차단)
# 2026-05-15 cto-lead 실수 fix: 빌드 [9/10] exit code 1 → 빌드 단계 제거.
# -----------------------------------------------------------------------------
# (의도적으로 빈 단계 — wiki 처리는 entrypoint.sh §Step 2에서 수행)

# -----------------------------------------------------------------------------
# Healthcheck (Railway가 /health 엔드포인트 polling — 공식 gateway 제공)
# -----------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /opt/wvb-bootstrap/healthcheck.sh || exit 1

# 2026-05-16 fix (cto-lead 15번째 실수 + Volume permission):
#   - USER hermes 명시 → Railway Volume이 root 소유로 mount → /opt/data write Permission denied
#   - Hermes 공식 패턴: USER root로 시작 → /opt/hermes/docker/entrypoint.sh가 gosu로 hermes drop
#   - 공식 Dockerfile L104: USER root (Volume mount 후 권한 처리 위해)
#   - wvb-entrypoint.sh가 root로 시작 → /opt/data write OK → 공식 entrypoint chain → hermes drop
# USER hermes  ← 제거 (root 유지)

# -----------------------------------------------------------------------------
# Gateway run + Telegram polling
# entrypoint.sh: config.yaml bootstrap → wiki submodule update → gateway run
# -----------------------------------------------------------------------------
WORKDIR /opt/data
EXPOSE 8642

# 2026-05-16 fix (cto-lead 12번째 실수): Hermes 공식 명령은 'hermes gateway' (run 없음)
# CMD에서 "run" 제거 → entrypoint.sh가 "gateway"만 args로 받음 → 공식 entrypoint chain에 정확히 전달
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/wvb-bootstrap/entrypoint.sh"]
CMD ["gateway"]
