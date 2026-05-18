# Design: Meeting Memo from Voice (Telegram Voice → PDF Memo)

**Date**: 2026-05-18
**Plan**: `docs/plans/2026-05-18-meeting-memo-from-voice.md`
**PDCA Route**: 옵션 2 main 직접 (cto-lead-routing.md v3)
**Status**: Design draft — 사용자 승인 대기

---

## §1. Architecture (시퀀스 다이어그램)

```
사용자 (Telegram)                Hermes Bot                  External
─────────────────                ──────────                  ────────
   │
   │ 1. 음성/audio 첨부 전송
   ├──────────────────────────►  telegram.py:4266
   │                              │ msg.voice.get_file()
   │                              │ download → cached_path
   │                              │ event.media_urls = [path]
   │                              │ event.media_types = ["audio/ogg"]
   │                              ▼
   │                             stt.enabled: true
   │                              │ provider: openai, model: whisper-1
   │                              ├────────────────────────► OpenAI Whisper API
   │                              │                          (env: OPENAI_API_KEY)
   │                              │ ◄────────── transcript ────
   │                              ▼
   │                             trigger: wvb-meeting-memo skill
   │                              │ (자동: voice msg + transcript)
   │                              ▼
   │                             cost estimate: $X (duration 기반)
   │                              │
   │ 2. ⚠️ 사전 승인 prompt    ◄────  send_exec_approval (재활용)
   │   [✅ Allow Once] [❌ Deny]       │
   ◄──────────────────────────       │
   │
   │ 3. ✅ Allow Once click
   ├──────────────────────────►  approval resolved
   │                              ▼
   │                             LLM 호출 (Hermes 기본 모델, OpenRouter)
   │                              │ system: 김실장 v2 포맷 prompt
   │                              │ user: transcript
   │                              ├────────────────────────► OpenRouter LLM
   │                              │ ◄────── markdown memo ───
   │                              ▼
   │                             PDF 생성 (reportlab)
   │                              │ /tmp/memo-{uuid}.pdf
   │                              ▼
   │                             send_document(pdf_path)
   │ 4. PDF 첨부 답신          ◄──────  telegram.py:3268
   │   📎 meeting-memo.pdf
   │                              │
   │                              ▼
   │                             cleanup: /tmp/memo-*.pdf 삭제
   │                             log: 본문 미저장, 메타만 (duration, cost)
```

---

## §2. Data Model

### 2.1 Skill Frontmatter (`skills/wvb/wvb-meeting-memo/SKILL.md`)

```yaml
---
name: wvb-meeting-memo
description: 음성 파일 전사 → 김실장 v2 미팅메모 포맷 → PDF 변환 → Telegram 답신. 1회당 사용자 승인 후 진행.
version: 1.0.0
metadata:
  tags: [wvb, meeting, memo, voice, pdf]
  domain: wvb
  trigger_keywords:
    - 미팅 메모
    - 미팅메모
    - 회의 정리
    - meeting memo
    - /memo
  triggers_on_media:
    - audio/ogg
    - audio/mp3
    - audio/mpeg
    - audio/wav
---
```

**디렉토리명 규칙**: `wvb-meeting-memo` (frontmatter name과 정확히 일치 — `project_hermes_skills` 룰)

### 2.2 비용 추정 모델

```python
WHISPER_COST_PER_MIN = 0.006  # USD, OpenAI Whisper-1
duration_min = audio_duration_seconds / 60
estimated_cost_usd = duration_min * WHISPER_COST_PER_MIN
estimated_cost_krw = estimated_cost_usd * 1350  # 환율 근사
```

### 2.3 Approval Prompt 형식

```
⚠️ 미팅 메모 생성 — 비용 사전 승인

📊 음성 길이: 47분 23초
💰 추정 비용: $0.28 (≈ ₩378)
   - Whisper STT: $0.28

진행하시겠습니까?

[✅ Allow Once]  [❌ Deny]
```

`send_exec_approval` 재활용 시 4-option (Once/Session/Always/Deny) 중 Once + Deny만 사용 (Always는 비용 자동 승인 위험).

### 2.4 PDF 출력 메타

- 파일명: `meeting-memo_YYMMDD_HHMM.pdf` (예: `meeting-memo_260518_1430.pdf`)
- 페이지: A4
- 폰트: reportlab CID built-in `HYGothic-Medium` (한국어 무료 내장, 별도 파일 불필요)
- 마진: 20mm

---

## §3. API 계약

### 3.1 Hermes config.yaml 추가

```yaml
# config.yaml.template — STT 활성화
stt:
  enabled: true
  provider: openai
  openai:
    model: whisper-1
```

### 3.2 환경 변수 (Railway)

| Variable | Source | Notes |
|---|---|---|
| `OPENAI_API_KEY` | 사용자 직접 Railway Dashboard 입력 | Whisper API 호출용. 김실장 STT 키와 분리 권장 (전사 전용 키) |

### 3.3 Skill 호출 인터페이스

Hermes 자동 트리거 (사용자 액션 불필요):
- voice/audio 메시지 inbound + transcript 생성 → `wvb-meeting-memo` skill auto-fire

수동 트리거:
- `/memo` 명령
- "미팅 메모" 자연어

### 3.4 PDF 생성 함수 시그니처

```python
# skills/wvb/wvb-meeting-memo/scripts/md_to_pdf.py
def generate_memo_pdf(
    markdown: str,
    output_path: str,
    title: str = "미팅 메모",
    metadata: dict | None = None,
) -> str:
    """Markdown → PDF 변환. reportlab CID HYGothic-Medium.
    Returns: output_path (성공 시) or raises Exception.
    """
```

---

## §4. UI Wireframe (Telegram 화면)

### 4.1 Inbound (사용자)
```
┌─────────────────────────────────┐
│ 사용자                          │
│ 🎙️ Voice message               │
│ ▶ 0:47:23                       │
└─────────────────────────────────┘
```

### 4.2 Approval Prompt (Hermes)
```
┌─────────────────────────────────┐
│ Hermes Bot                      │
│ ⚠️ 미팅 메모 생성 — 비용 승인  │
│                                 │
│ 📊 음성 길이: 47분 23초         │
│ 💰 추정 비용: $0.28 (≈ ₩378)   │
│    - Whisper STT: $0.28         │
│                                 │
│ 진행하시겠습니까?               │
│                                 │
│ [✅ Allow Once]  [❌ Deny]      │
└─────────────────────────────────┘
```

### 4.3 In-Progress (Hermes)
```
┌─────────────────────────────────┐
│ Hermes Bot                      │
│ ✅ 승인됨. 전사 중...           │
│ ⏳ 예상 소요: 1-2분             │
└─────────────────────────────────┘
```

### 4.4 결과 (Hermes)
```
┌─────────────────────────────────┐
│ Hermes Bot                      │
│ 📎 meeting-memo_260518_1430.pdf │
│ (12.4 KB)                       │
│                                 │
│ ✅ 완료 — 47분 23초 음성        │
│ 💰 실제 비용: $0.28             │
│ 📄 페이지: 3                    │
└─────────────────────────────────┘
```

---

## §5. Dockerfile 추가 사항

```dockerfile
# 기존 USER root 단계에 추가
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    tzdata \
    gettext-base \
    fonts-noto-cjk \                          # 한국어 폰트 fallback (PDF 한글 보장)
    && rm -rf /var/lib/apt/lists/* \
    ...

# uv venv에 reportlab 추가
RUN /opt/hermes/.venv/bin/pip install reportlab==4.2.5
```

**reportlab 버전 fetch 검증** (build-then-verify §11): pypi.org/project/reportlab 확인 후 최신 안정 버전 pin.

**CID font 우선, 폰트 파일 fallback**:
- 1순위: reportlab built-in `HYGothic-Medium` (CID encoded, 별도 파일 불필요, 가벼움)
- 2순위: `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc` (apt-get 설치 후)

---

## §6. Railway PaaS Plan-tier 차이 (build-then-verify §11)

| 항목 | Hobby | Pro |
|---|---|---|
| Memory | 8GB | 32GB |
| Volume size | 5GB default (선택 불가) | 5/25/50/250GB 선택 |
| Bandwidth | 100GB/월 | 1TB/월 |
| **현재 wvb 운영** | Hobby (확인 필요) | — |

**영향**:
- PDF 생성 메모리 = 1h 미팅 transcript (~50KB) + memo MD (~20KB) → Hobby 8GB 충분
- Volume 5GB → /tmp PDF 임시 파일 (~수십 KB)로 무관
- OpenAI API outbound bandwidth = 1h 음성 ~30MB → 월 100GB 한도 무관

→ **Hobby plan 그대로 유지 가능**.

---

## §7. 미팅메모 v2 포맷 (Skill prompt 차용)

### 7.1 김실장 v2 구조 (메모리 `feedback_meeting_memo_v2_format` 차용)

```markdown
# MEETING MEMO — {회의명}

## Executive Summary
{1페이지 절대 한도 ~1,500자, 4개 미니 헤딩}
### 회의 목적·맥락
### 핵심 결정·합의
### 주요 논점·발견
### 액션·후속

## 1. {주제 1}
- {개조식 위주}

## 2. {주제 2}
- ...

## N+1. 핵심 인사이트

---

## 회의 정보
| 항목 | 내용 |
|------|------|
| 회의명 | ... |
| 날짜 | YYYY-MM-DD |
| 참석자 | ... |
| 회의 시간 | HH:MM |
| 미디어 | Telegram voice (XX분 XX초) |
| 생성 방식 | Hermes wvb-meeting-memo v1.0 |
| LLM | {Hermes 기본 모델} |
| STT | OpenAI Whisper-1 |

---
*CONFIDENTIAL — 본 메모는 WVB 내부용입니다. 외부 공유 금지.*
```

### 7.2 참석자·날짜 처리 (MVP 단순화)

김실장 v2는 사전 질문 강제하지만 **Hermes MVP는 다음 fallback**:
- 음성 메타에서 추출 불가능 → "참석자: 미확인", "날짜: {음성 전송일}" 자동
- 사용자가 메모 받은 후 별도 메시지로 수정 요청 가능
- 추후 enhancement로 음성 첨부 시 caption text로 참석자 명시하면 파싱

---

## §8. 보안 & 개인정보 (Personal Data Protection)

| 항목 | 처리 |
|---|---|
| 음성 파일 | Hermes 컨테이너 `/tmp/`에 cache. STT 완료 후 즉시 삭제 |
| Transcript | 메모 생성 즉시 삭제 (Hermes log에 본문 미저장) |
| PDF | `/tmp/memo-{uuid}.pdf`, 송신 후 즉시 삭제 |
| Hermes log | 메타만 (duration, cost, success/fail). transcript 본문·메모 본문 미저장 |
| 외부 노출 | OpenAI Whisper API 호출만 (audio bytes), LLM 호출 (transcript text). 둘 다 사용자 결정 (cost-guard 준수) |
| 송신 채널 | Telegram DM 1:1만. 그룹·채널 송신 0건 |

**Critical**: 미팅 내용은 인사·재무·M&A 등 민감 가능성 → 외부 노출 통로 절대 차단.

---

## §9. Error Handling (Graceful Degradation)

| 시나리오 | 처리 |
|---|---|
| 음성 25MB 초과 | "음성 파일이 25MB를 초과합니다. 분할 또는 압축 후 재시도해주세요." 답신 |
| OpenAI Whisper 호출 실패 | 에러 메시지 표시 + 비용 0 (호출 안 됐으면) |
| LLM 응답 실패 | 전사 텍스트만 .txt 파일로 답신 (사용자가 별도 메모 가능) |
| PDF 생성 실패 | Markdown 본문 그대로 텍스트 메시지로 답신 |
| 사용자 승인 60초 timeout | "승인 timeout. 다시 음성 전송하시면 재시도됩니다." 답신, 비용 0 |
| 사용자 Deny | "취소됨. 비용 0." 답신, transcript·cache 즉시 삭제 |

---

## §10. 검증 시나리오 (Check 단계 미리 정의)

| # | 시나리오 | Pass 기준 |
|---|---|---|
| 1 | 5분 음성 (간단 1:1 대화) | PDF 1페이지 도착, 비용 ~$0.03, Executive Summary 형식 |
| 2 | 30분 음성 (실제 미팅) | PDF 2-3페이지, 비용 ~$0.18, 본문 섹션 3-5개 |
| 3 | 1h 음성 (긴 미팅) | PDF 3-4페이지, 비용 ~$0.36, Executive Summary 1p 한도 준수 |
| 4 | 사용자 Deny | 비용 0, 전사·메모 안 됨, cleanup 확인 |
| 5 | 25MB 초과 음성 | 에러 메시지 답신, Whisper 호출 안 됨, 비용 0 |
| 6 | 음성 외 첨부 (이미지) | 기존 Hermes 동작 (메모 skill 미트리거) |

---

## §11. Phase Breakdown 상세 (Plan §7 참조)

### Do 1: Skill 작성
- 파일: `skills/wvb/wvb-meeting-memo/SKILL.md`
- 파일: `skills/wvb/wvb-meeting-memo/scripts/md_to_pdf.py`
- 파일: `skills/wvb/wvb-meeting-memo/scripts/estimate_cost.py`

### Do 2: Config
- `config.yaml.template` — `stt:` 섹션 추가
- Railway env — 사용자 OPENAI_API_KEY Dashboard 입력 (제가 진행 불가)

### Do 3: Dockerfile
- `apt-get install fonts-noto-cjk` 추가
- `pip install reportlab==4.2.5` 추가
- 빌드 검증 (Railway 자동 재배포)

### Do 4: Approval flow
- Skill 내부에서 cost estimate → `send_exec_approval` 호출 → 응답 대기 → 진행/취소

### Check: E2E
- §10 시나리오 6개 수행

### Act: 문서화
- `wiki/projects/hermes-meeting-memo.md` 운영 가이드
- `memory/feedback_*` RCA 패턴 (발견 시)

---

## §12. 사용자 결정 사항 (Design 단계 추가)

Plan §4의 5건은 그대로 유지. Design 단계에서 추가 결정 필요:

| # | 항목 | 권장 | 대안 |
|---|---|---|---|
| 6 | OPENAI_API_KEY 입력 방식 | 사용자가 Railway Dashboard 직접 입력 (권장 — 키 노출 0) | CLI로 제가 진행 (키 메시지 노출 위험) |
| 7 | reportlab 폰트 전략 | CID HYGothic-Medium (built-in, 가벼움) | Noto Sans CJK TTF (apt 설치, 무거움) |
| 8 | Approval prompt scope | Once + Deny 2-option only (Always 제거 — 비용 자동 승인 위험) | Hermes 표준 4-option 그대로 |
| 9 | 음성 25MB 초과 처리 | "분할/압축 후 재시도" 에러 메시지 | pydub로 자동 분할 (복잡도↑) |
| 10 | PDF 생성 실패 시 | Markdown 텍스트로 답신 fallback | 에러 메시지만 |

---

## §13. Approval

Design 승인 시 Do 1부터 진행. 승인 전 §12 추가 결정 확인 요청.

**Design 검토 포인트**:
1. §1 시퀀스 다이어그램 의도와 일치?
2. §4 UI 4단계 (inbound → approval → progress → result) OK?
3. §7 김실장 v2 포맷 차용 수준 적절? (MVP 단순화 OK?)
4. §8 보안 처리 (cache·log·송신) 충분?
5. §12 신규 결정 5건 권장안 OK?

---

*Created: 2026-05-18. Design owner = 사용자. Verifier = build-then-verify v1.10 §11 (외부 의존 사전 fetch 완료).*

**Fetch 완료 외부 의존** (Plan §8 외):
- `gateway/platforms/telegram.py:2108-2177` (send_exec_approval inline keyboard pattern)
- `gateway/platforms/telegram.py:3268-3316` (send_document for PDF)
- `Dockerfile:1-134` (base image, USER root, pip install pattern)
- `content/reports/generate_pdf.py:1-100` (reportlab 패턴 — Linux 폰트로 adapt 필요)
