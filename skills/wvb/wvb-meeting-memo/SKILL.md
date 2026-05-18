---
name: wvb-meeting-memo
description: Telegram 음성 첨부 → OpenAI Whisper 전사 → 김실장 v2 포맷 미팅메모 → PDF 변환 → Telegram PDF 답신. 1회당 비용 사전 승인 후 진행.
version: 1.0.0
metadata:
  tags: [wvb, meeting, memo, voice, pdf, cost-guard]
  domain: wvb
  trigger_keywords:
    - 미팅 메모
    - 미팅메모
    - 회의 정리
    - 회의 메모
    - meeting memo
    - /memo
  triggers_on_media:
    - audio/ogg
    - audio/mp3
    - audio/mpeg
    - audio/wav
---

# WVB Meeting Memo (Voice → PDF)

## When to Use

- **자동 트리거**: 사용자가 Telegram DM에 음성/audio 메시지 첨부 (`msg.voice` 또는 `msg.audio`)
- **수동 트리거**: `/memo` 명령 또는 "미팅 메모" 자연어 (이 경우 사용자에게 음성 파일 첨부 요청)

## Required Behavior

본 skill은 **비용 사전 승인이 필수**다. STT API 호출이 발생하므로 cost-guard 준수.

### 핵심 워크플로 (사용자에게 자연어로 안내하면서 진행)

1. **음성 메타 파악** — `event.media_urls`에서 cached audio path 확인. duration 추출.
2. **비용 추정 출력** — 사용자에게 자연어 메시지로 비용 + 진행 여부 묻기. **사용자 명시 응답 전에 절대 진행 금지**.
3. **사용자 응답 대기** — yes/yeah/네/진행/ok = 진행. no/cancel/취소 = abort + cache 삭제.
4. **STT 자동 전사** — Hermes config.yaml의 `stt.enabled: true` + `stt.provider: openai`로 자동 진행됨. transcript는 LLM context로 자동 주입.
5. **미팅 메모 작성** — 아래 §Memo Format 따라 markdown 생성. Hermes 기본 LLM이 처리.
6. **PDF 변환** — terminal로 `md_to_pdf.py` 호출. 출력 경로 `/tmp/meeting-memo-{YYMMDD-HHMM}.pdf`.
7. **Telegram 답신** — PDF를 `send_document` 도구로 첨부 답신. 본문에 "✅ 완료" + 실제 비용 + 페이지 수.
8. **Cleanup** — cache audio 파일 + PDF 파일 즉시 삭제 (`/tmp/`에 잔존 금지).

---

## Step 1: 음성 메타 파악

terminal 도구로 음성 파일 duration 추출:

```bash
/opt/hermes/.venv/bin/python "${HERMES_HOME:-/opt/data}/skills/wvb/wvb-meeting-memo/scripts/estimate_cost.py" \
    --audio-path "{event.media_urls[0]}"
```

출력 예시:
```json
{"duration_seconds": 2843, "duration_human": "47분 23초", "estimated_cost_usd": 0.28, "estimated_cost_krw": 378}
```

추출 실패 시 ffprobe fallback. 그래도 실패하면 사용자에게 "음성 메타 추출 실패. 길이 알려주시면 비용 추정 가능합니다." 응답.

## Step 2: 사용자 사전 승인 (필수 — 응답 전 진행 금지)

사용자에게 다음 형식으로 자연어 메시지 송신:

```
⚠️ 미팅 메모 생성 — 비용 사전 승인

📊 음성 길이: {duration_human}
💰 추정 비용: ${estimated_cost_usd} (≈ ₩{estimated_cost_krw})
   - OpenAI Whisper STT: ${estimated_cost_usd}

진행하려면 "네" 또는 "yes", 취소하려면 "취소" 또는 "no"를 응답해주세요.
```

**금지 규칙**:
- ❌ 사용자 응답 없이 다음 단계 자동 진행 금지
- ❌ Whisper 호출 후 비용 통지 금지 (사전 승인이 본질)
- ❌ "비용이 적으니 그냥 진행" 임의 판단 금지

## Step 3: 사용자 응답 수신

- "네" / "yes" / "yeah" / "진행" / "ok" / "go" → Step 4 진행
- "취소" / "no" / "abort" / "stop" → cache audio 삭제 + "취소됨. 비용 0." 응답 후 종료
- 60초 timeout (사용자 무응답) → "승인 timeout. 다시 음성 전송하시면 재시도됩니다." 응답 + cache 삭제

## Step 4: STT 자동 전사 (Hermes 내장)

본 skill은 STT를 **직접 호출하지 않는다**. Hermes의 `stt.enabled: true` 설정으로 음성 메시지가 자동으로 OpenAI Whisper로 전사되어 transcript text가 LLM context에 주입됨.

따라서 본 step에서는:
- LLM context에 transcript가 이미 있다는 가정으로 진행
- transcript가 비어 있거나 누락된 경우: "STT 전사 실패 — Hermes 로그 확인 필요" 응답 후 종료

## Step 5: 미팅 메모 작성 (김실장 v2 포맷)

transcript를 입력으로 다음 markdown 구조로 메모 작성:

```markdown
# MEETING MEMO — {회의명 추론, 불가시 "Untitled Meeting YYYY-MM-DD"}

## Executive Summary

### 회의 목적·맥락
{2-3문장. 회의 왜·맥락}

### 핵심 결정·합의
- {불릿 3-5개. 결정·합의된 사항}

### 주요 논점·발견
- {불릿 3-5개. 논쟁·인사이트}

### 액션·후속
- [ ] {action 1} — Owner: {참석자 또는 미정}
- [ ] {action 2}

## 1. {주제 1}
{개조식 본문}

## 2. {주제 2}
...

## N+1. 핵심 인사이트
{1-2문단. 메타 인사이트, 후속 영향}

---

## 회의 정보
| 항목 | 내용 |
|------|------|
| 회의명 | {추론} |
| 날짜 | {음성 전송일 또는 transcript 내 추출} |
| 참석자 | {transcript에서 추출, 불가시 "미확인"} |
| 회의 시간 | {duration_human} |
| 미디어 | Telegram voice |
| 생성 방식 | Hermes wvb-meeting-memo v1.0 |
| STT | OpenAI Whisper-1 |

---
*CONFIDENTIAL — 본 메모는 WVB 내부용입니다. 외부 공유 금지.*
```

### 작성 규칙

- **Executive Summary 1페이지 절대 한도** — 4개 미니 헤딩 합산 ~1,500자 이내
- **본문 개조식 위주** — 서술형 단락 최소화
- **참석자 미확인 시 "미확인" 명시** — 추측 금지
- **존댓말** (.claude/rules/korean-writing-style.md 준수 — 한국어 작성 시)
- **AI tell 패턴 회피** — "결론적으로 / 매우 중요하다 / ~라고 할 수 있다" 금지

## Step 6: PDF 변환

markdown을 임시 파일에 쓰고 PDF 변환 호출:

```bash
# 1) markdown 임시 저장
MEMO_MD="/tmp/meeting-memo-$(date +%y%m%d-%H%M).md"
# (메모 markdown을 위 경로에 write — terminal heredoc 또는 cat << EOF)

# 2) PDF 변환
MEMO_PDF="/tmp/meeting-memo-$(date +%y%m%d-%H%M).pdf"
/opt/hermes/.venv/bin/python "${HERMES_HOME:-/opt/data}/skills/wvb/wvb-meeting-memo/scripts/md_to_pdf.py" \
    --input "$MEMO_MD" \
    --output "$MEMO_PDF" \
    --title "Meeting Memo"
```

변환 실패 시 fallback: markdown 본문을 Telegram 텍스트 메시지로 그대로 답신 (사용자가 직접 변환 가능).

## Step 7: Telegram 답신

`send_document` 도구로 PDF 첨부:

```
send_document(
  chat_id=<current chat>,
  file_path=$MEMO_PDF,
  caption="✅ 완료 — {duration_human} 음성\n💰 실제 비용: ${actual_cost}\n📄 페이지: {page_count}"
)
```

## Step 8: Cleanup (필수)

```bash
rm -f "$MEMO_MD" "$MEMO_PDF"
# cache audio도 Hermes가 일정 시간 후 자동 정리하지만 명시 삭제 권장
rm -f "{event.media_urls[0]}"
```

---

## Pitfalls

- ❌ **사용자 사전 승인 없이 STT 호출 금지** — cost-guard 직접 위반
- ❌ **transcript 본문 Hermes log에 저장 금지** — 메타(duration, cost)만 log
- ❌ **메모 PDF 외 채널 송신 금지** — Telegram DM 1:1만. 그룹·채널 0건
- ❌ **참석자·날짜 추측 금지** — 미확인 시 "미확인" 명시
- ❌ **bare `python` 명령 금지** — 반드시 `/opt/hermes/.venv/bin/python` 절대경로
- ❌ **AI tell 패턴 사용 금지** — `.claude/rules/korean-writing-style.md` S1 결정적 패턴 회피
- ❌ **외부 발신 0건** — CCO 게이트
- ❌ **음성 25MB 초과 시 자동 분할 금지** — "분할/압축 후 재시도해주세요" 에러 메시지로 종료
- ❌ **PDF cleanup 누락 금지** — `/tmp/`에 잔존하면 Personal Data 보호 위반

## Verification (응답 전 자기 점검)

1. **Step 1 duration 추출** 실제 실행했는가? 추정 비용 출력?
2. **Step 2 사용자 승인 prompt** 송신했는가?
3. **Step 3 사용자 명시 응답** 수신 후 진행했는가? (자동 진행 0건)
4. **Step 5 메모** Executive Summary 1p 한도 + 본문 개조식 + 메타 하단 구조 준수?
5. **Step 7 PDF 답신** 성공 + 실제 비용 + 페이지 수 명시?
6. **Step 8 Cleanup** `/tmp/` PDF·MD·audio 삭제 확인?
7. 외부 발신 0건 (Telegram DM 외)?
8. transcript 본문 log 저장 0건?

## References

- Plan: `docs/plans/2026-05-18-meeting-memo-from-voice.md`
- Design: `docs/designs/2026-05-18-meeting-memo-from-voice.design.md`
- 김실장 v2 포맷 메모리: `memory/feedback_meeting_memo_v2_format.md`
- 한국어 작성 룰: `.claude/rules/korean-writing-style.md` S1·S2
- cost-guard 룰: `.claude/rules/cost-guard.md`
- Personal Data Protection: `.claude/rules/personal-data-protection.md`
- Hermes STT config: `cli-config.yaml.example:810-822`
- Telegram voice inbound: `gateway/platforms/telegram.py:4266-4285`
- Telegram send_document: `gateway/platforms/telegram.py:3268-3316`
