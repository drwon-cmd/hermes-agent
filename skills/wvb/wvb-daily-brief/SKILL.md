---
name: wvb-daily-brief
description: 원대로 대표 매일 KST 06:00 일일 브리핑 — 오늘 일정·미수신 메시지·권장 초점. Cron 자동 발사 + 사용자 수동 호출 (/brief 또는 "일일 브리핑").
version: 2.1.1
metadata:
  tags: [wvb, daily, brief, executive, cron]
  domain: wvb
  cron: "0 5 * * *"
  timezone: "Asia/Singapore"
  trigger_keywords:
    - 일일 브리핑
    - 오늘 브리핑
    - 오늘 일정
    - 데일리
    - /brief
---

# WVB Daily Brief (KST 06:00)

## When to Use

- **자동 트리거**: 매일 KST 06:00 cron (컨테이너 TZ=Asia/Singapore → SGT 05:00, schedule `0 5 * * *`). 2026-05-17 정정: 이전 `0 21 * * *`는 작성자가 UTC 해석을 가정했으나 Hermes는 컨테이너 TZ로 cron parse — SGT 21:00 = KST 22:00 잘못 fire.
- **수동 트리거**: 사용자가 `/brief` 또는 "일일 브리핑" / "오늘 일정 정리" 자연어 호출

## Required Skills (cron 생성 시 함께 preload 필수)

본 스킬 단독으로는 작동 못 함. cron `skills` 배열에 다음을 반드시 포함:

```
skills: ['wvb-daily-brief', 'google-workspace']
```

추가로 다음 MCP 도구는 Hermes에 자동 등록되어 있어 별도 preload 불필요:
- `mcp_ms365_*` — Outlook mail (List/Search). 단 현재 `--preset mail`만 활성이라 Outlook Calendar/OneDrive는 미활성

## Output Format

```
📋 WVB Daily Brief — {YYYY-MM-DD} ({요일})

🕐 오늘 일정 (KST)
  - {Google Calendar 결과 — 없으면 "(0건)"}

📬 미수신 (24h)
  - Gmail unread: {N건, 발신자 + subject 한 줄}
  - Outlook unread: {N건, 발신자 + subject 한 줄}
  - Slack #80-zero100: 미통합 (Phase 1.5)
  - 카톡 업무: 미통합 (Phase 1.5)

💡 오늘의 권장 초점
  - {위 정보 종합 1-2줄}
```

**제거된 섹션** (v2.1 사용자 결정 2026-05-17):
- ~~Biz List 변화~~: biz list Sheets를 사용 안 함
- ~~P0 의사결정 대기~~: wiki/decisions/ 파일 list가 사용자에게 무용

## Procedure

### Step 1: 정확한 날짜·요일 확보 (필수, prior knowledge 금지)

**terminal 도구로 다음 명령을 반드시 실행한 후 결과를 사용하라:**

```bash
TZ='Asia/Seoul' date '+%Y-%m-%d %A (%a)'
```

예상 출력: `2026-05-17 일요일 (일)`

**금지 규칙**:
- 위 명령 실행 없이 prior knowledge로 요일 추측 ❌
- "2026-05-17이라면 금요일일 것" 같은 추론 ❌
- 반드시 date 명령 실제 호출 → 출력 그대로 인용 ✅

### Step 2: Google Calendar 오늘 일정 조회

terminal 도구로 google-workspace skill의 google_api.py 호출:

```bash
/opt/hermes/.venv/bin/python "${HERMES_HOME:-/opt/data}/skills/productivity/google-workspace/scripts/google_api.py" \
    calendar list --max-results 20 \
    --time-min "$(TZ='Asia/Seoul' date '+%Y-%m-%dT00:00:00+09:00')" \
    --time-max "$(TZ='Asia/Seoul' date '+%Y-%m-%dT23:59:59+09:00')"
```

**Python 인터프리터 주의**: bare `python` 명령은 cron이 spawn한 서브프로세스 PATH에 없음. 반드시 절대경로 `/opt/hermes/.venv/bin/python` 사용 (Hermes Runtime Facts §Execution Environment).

도구 호출 실패 시 (OAuth 미인증 / 명령 오류) 출력 형식에 "(Google Calendar 호출 실패: {에러})" 명시.

### Step 3: Gmail 미수신 조회 (최근 24시간)

```bash
/opt/hermes/.venv/bin/python "${HERMES_HOME:-/opt/data}/skills/productivity/google-workspace/scripts/google_api.py" \
    gmail search --query "is:unread newer_than:1d" --max-results 10
```

발신자 + Subject 1줄로 요약. 본문 인용 금지.

### Step 4: Outlook 미수신 조회

mcp_ms365 도구 호출 (자동 등록):

```
mcp_ms365_list_mail_messages 또는 mcp_ms365_search_messages
filter: "isRead eq false"
top: 10
select: "from,subject,receivedDateTime"
```

### Step 5: 종합 출력

위 Step 1-4 결과를 Output Format 그대로 출력. 권장 초점은 일정 + 미수신 종합하여 1-2줄로 작성.

**Graceful degradation 원칙**:
- 도구 호출 실패한 영역은 "(호출 실패: {1줄 이유})" 명시
- 데이터 없는 영역 (예: 오늘 일정 없음)은 "(0건)" 명시
- 한 영역 실패해도 다른 영역은 계속 진행

## Pitfalls

- ❌ **Step 1 date 명령 없이 요일 추측 금지** (2026-05-17 v2.0 fix 사고 RCA)
- ❌ **wiki/decisions/ 실제 read 없이 "어렵습니다" 환각 금지** (v2.0 fix)
- ❌ 메일 본문 그대로 인용 금지 — 발신자 + Subject 한 줄 요약만
- ❌ 미수신 메시지를 *읽음 처리* 시도 금지 (read-only)
- ❌ **외부 발신 (Gmail send / Outlook send / Slack send) 0건** — CCO 게이트
- ❌ biz list 자동 수정 금지 (read-only consumer)
- ❌ `wiki/_personal/`, `SOUL.md`, `USER.md`, `ACCESS_POLICY.md`, `HEARTBEAT.md` 접근 금지 (Personal Data Protection)
- ❌ Gemini 환각 패턴: `default_api.x()` Python code execution 형식 금지 — Hermes는 자연어 + 자율 tool 호출
- ❌ **bare `python` 명령 금지** (2026-05-18 cron RCA): cron이 spawn한 tool 서브프로세스 PATH에 venv 미포함 → "python 명령어를 찾을 수 없음" 실패. 반드시 절대경로 `/opt/hermes/.venv/bin/python` 사용

## Verification (응답 전 자기 점검)

1. **Step 1 date 명령 실제 실행했는가?** 출력 라인 인용 가능?
2. Step 2-4 중 **최소 2개 도구 호출 실제 시도**했는가? (성공/실패 무관)
3. 외부 발신 0건인가?
4. 응답 분량 1500자 이내 (텔레그램 가독성)?
5. Personal Data 영역 (`_personal`, SOUL 등) 누수 없는가?

## References

- Phase 6 완료 기록: `docs/planning/01-plan/features/hermes-google-mcp.plan.md` v1.5 (2026-05-16)
- Plan §3.4 채널 정책: `docs/planning/01-plan/features/hermes-agent-deployment.plan.md`
- google-workspace skill: `/opt/data/skills/productivity/google-workspace/SKILL.md`
- ms365 MCP 활성 도구: `mcp_servers.ms365 --preset mail` (Outlook mail만, Calendar/Files 비활성)
- 데이터 소스 제외 룰: `memory/feedback_data_source_exclusions.md`
- CCO 외부 발신 게이트: Plan §7
- Personal Data Protection: `.claude/rules/personal-data-protection.md`
