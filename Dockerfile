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
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    tzdata \
    gettext-base \
    && rm -rf /var/lib/apt/lists/* \
    && echo "ko_KR.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen \
    && ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime

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

# 공식 base image 검증 (2026-05-15): hermes user UID 10000 사전 생성 (Hermes 공식 Dockerfile L28)
# cto-lead 3번째 실수 fix: 'node' 가정 → 실제 'hermes' (https://raw.githubusercontent.com/NousResearch/hermes-agent/main/Dockerfile L104)
USER hermes

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
