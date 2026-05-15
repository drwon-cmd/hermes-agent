# =============================================================================
# Hermes Agent — WVB 24/7 비서실장 (Railway 배포용)
# Base: nousresearch/hermes-agent:v0.13.0 공식 이미지 위에 WVB layer 추가
# =============================================================================
#
# 설계 결정 (Design §2 → 공식 검증 반영):
#  - 공식 이미지를 base로 사용 (직접 multi-stage build 회피 → 빌드 시간 단축)
#  - debian:13.4 + Python 3.13 + uv + tini + ffmpeg + ripgrep + Node 22 기본 포함
#  - Gateway 모드 `gateway run` 사용 (port 8642 healthcheck endpoint 제공)
#  - Wiki submodule은 빌드 시 fetch (read-only), cron으로 6시간마다 갱신
#  - Railway는 비루트 실행 강제 안 함 (공식 이미지는 node user 사용)
#
# 검증 상태: 공식 install docs + Dockerfile + docker.md 3개 교차 확인 (2026-05-15)
# =============================================================================

ARG HERMES_VERSION=v0.13.0
FROM nousresearch/hermes-agent:${HERMES_VERSION}

# -----------------------------------------------------------------------------
# WVB 추가 시스템 패키지 (공식 이미지가 git/ripgrep/ffmpeg 이미 포함, 보강용)
# -----------------------------------------------------------------------------
USER root

# 한국어 locale (한글 응답 안정성 - UTF-8 인코딩 보장)
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    tzdata \
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
COPY --chown=node:node config.yaml.template /opt/wvb-bootstrap/config.yaml.template
COPY --chown=node:node skills/ /opt/wvb-bootstrap/skills/
COPY --chown=node:node scripts/entrypoint.sh /opt/wvb-bootstrap/entrypoint.sh
COPY --chown=node:node scripts/healthcheck.sh /opt/wvb-bootstrap/healthcheck.sh

RUN chmod +x /opt/wvb-bootstrap/entrypoint.sh /opt/wvb-bootstrap/healthcheck.sh

# -----------------------------------------------------------------------------
# Wiki 디렉토리 (Railway가 시작 시 submodule init/fetch — 이미지에는 포함 안 함)
# 보안: wiki 콘텐츠를 이미지에 굽지 않음 (이미지 layer cache 외부 노출 차단)
# -----------------------------------------------------------------------------
RUN mkdir -p /opt/data/wiki && chown -R node:node /opt/data/wiki

# -----------------------------------------------------------------------------
# Healthcheck (Railway가 /health 엔드포인트 polling — 공식 gateway 제공)
# -----------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /opt/wvb-bootstrap/healthcheck.sh || exit 1

USER node

# -----------------------------------------------------------------------------
# Gateway run + Telegram polling
# entrypoint.sh: config.yaml bootstrap → wiki submodule update → gateway run
# -----------------------------------------------------------------------------
WORKDIR /opt/data
EXPOSE 8642

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/wvb-bootstrap/entrypoint.sh"]
CMD ["gateway", "run"]
