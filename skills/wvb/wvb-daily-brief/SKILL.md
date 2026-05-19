---
name: wvb-daily-brief
description: 원대로 대표 매일 KST 07:00 일일 브리핑 — 오늘 일정·미수신 메시지·권장 초점. Cron 자동 발사 + 사용자 수동 호출 (/brief 또는 "일일 브리핑").
version: 2.3.0
metadata:
  tags: [wvb, daily, brief, executive, cron]
  domain: wvb
  cron: "0 6 * * *"
  timezone: "Asia/Singapore"
  trigger_keywords:
    - 일일 브리핑
    - 오늘 브리핑
    - 오늘 일정
    - 데일리
    - /brief
---

# WVB Daily Brief (KST 07:00)

## When to Use

- **자동 트리거**: 매일 KST 07:00 cron (컨테이너 TZ=Asia/Singapore → SGT 06:00, schedule `0 6 * * *`). 2026-05-18 사용자 결정: 원래 KST 06:00 의도 → KST 07:00으로 변경. 변경 이력: (1) `0 21 * * *` UTC 가정 오작성(5/17 RCA), (2) `0 5 * * *` SGT KST 06:00 정정(5/17), (3) `0 6 * * *` KST 07:00 사용자 변경(5/18).
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

  📥 Gmail ({N}건)
    - {발신자 이름} — {Subject}
    - ...

  📨 Outlook ({N}건)
    - {발신자 이름} — {Subject}
    - ...

  Slack #80-zero100: 미통합 (Phase 1.5)
  카톡 업무: 미통합 (Phase 1.5)

💡 오늘의 권장 초점
  - {위 정보 종합 1-2줄}
```

### 표시 규칙 (v2.3 추가)

1. **발신자 표기**: 이름만 (이메일 주소·꺽쇠 `<...>` 제거)
   - `"BackScoop" <team@backscoop.com>` → `BackScoop`
   - 이름 없으면 도메인 추출 (`team@backscoop.com` → `backscoop.com`)
2. **섹션 분리**: Gmail 📥 / Outlook 📨 별도 헤더, 카운트 명시
3. **건수가 0인 경우**: `(0건)` 표시하고 list 생략

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
    calendar list --max 20 \
    --start "$(TZ='Asia/Seoul' date '+%Y-%m-%dT00:00:00+09:00')" \
    --end "$(TZ='Asia/Seoul' date '+%Y-%m-%dT23:59:59+09:00')"
```

**CLI 시그니처 주의** (v2.3 검증): calendar list 인자는 `--start`/`--end`/`--max` (`--time-min`/`--time-max`/`--max-results` 아님). 출처: `skills/productivity/google-workspace/scripts/google_api.py:1096-1100`.

**Python 인터프리터 주의**: bare `python` 명령은 cron이 spawn한 서브프로세스 PATH에 없음. 반드시 절대경로 `/opt/hermes/.venv/bin/python` 사용 (Hermes Runtime Facts §Execution Environment).

도구 호출 실패 시 (OAuth 미인증 / 명령 오류) 출력 형식에 "(Google Calendar 호출 실패: {에러})" 명시.

### Step 3: Gmail 미수신 조회 (최근 24시간)

**스팸·뉴스레터·삭제·정크 자동 제외** (v2.3 사용자 결정 2026-05-19):

```bash
/opt/hermes/.venv/bin/python "${HERMES_HOME:-/opt/data}/skills/productivity/google-workspace/scripts/google_api.py" \
    gmail search \
    "is:unread newer_than:1d -category:promotions -category:social -category:updates -category:forums -in:spam -in:trash" \
    --max 20
```

**CLI 시그니처 주의** (v2.3 검증): `gmail search` 는 query를 positional arg로, max를 `--max` 로 받음 (`--query`·`--max-results` 아님). 출처: `skills/productivity/google-workspace/scripts/google_api.py:1058-1060`.

**후처리 필터 (Python·자연어 판단 둘 다 가능)**:
1. 발신자 도메인·이름이 **뉴스레터 패턴** 매칭 시 제외:
   - 도메인: `substack.com`, `beehiiv.com`, `mail.beehiiv.com`, `mailchimp.com`, `convertkit.com`, `sendgrid.net`
   - 이름·이메일에 포함: `newsletter`, `noreply`, `no-reply`, `marketing`, `digest`, `weekly`, `daily`
2. **이미 삭제·읽음 처리한 메일은 검색에 안 잡힘** (`is:unread` + `-in:trash` 명시로 안전)
3. 후처리 결과 최대 10건만 표시 (초과 시 "외 N건" 추가)

발신자 표기: 이름만. `"BackScoop" <team@backscoop.com>` → `BackScoop`.

### Step 4: Outlook 미수신 조회

**삭제·정크·Connected Account(Gmail forward) 제외** (v2.3 사용자 결정 2026-05-19):

mcp_ms365 도구 호출 시 다음 필터 강제:

```
mcp_ms365_list_mail_messages
parent_folder: "inbox"  # well-known folder name. deleteditems·junkemail 자동 제외
filter: "isRead eq false"
top: 20
select: "from,subject,receivedDateTime,parentFolderId"
orderby: "receivedDateTime desc"
```

**후처리 필터**:
1. **Gmail dedup** (Outlook에 Gmail Connected Account/forwarding 설정으로 Gmail 메일이 중복 표시되는 사례 다발):
   - Step 3 Gmail 결과의 (발신자 이메일·Subject) 쌍 수집
   - Outlook 결과에서 동일 (발신자 이메일·Subject) 쌍 매칭 시 제외
   - Subject 정규화: 앞 공백·`Re:`·`Fwd:`·이모지 무시한 substring 80% 매칭
2. **뉴스레터 패턴 제외** (Step 3 Gmail 후처리와 동일):
   - 도메인·이름 패턴: substack/beehiiv/mailchimp/sendgrid/newsletter/noreply 등
3. **순수 Outlook 메일만 출력**:
   - 발신자가 사용자 본인 Gmail 주소(`drwon@wiltcm.com`)로 forward된 흔적 있으면 제외
   - parentFolderId가 `inbox` 가 아닌 항목 모두 제외
4. 후처리 결과 최대 10건만 표시

발신자 표기는 Gmail과 동일 규칙. `from.emailAddress.name` 우선, 없으면 도메인.

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
- ❌ **이메일 주소 노출 금지** (v2.3): `발신자명 <email@domain>` 형식 X. 이름만 표시
- ❌ **Outlook에 Gmail dedup 누락 금지** (v2.3): Outlook Connected Account/forwarding으로 Gmail 메일 중복 다발. Step 4 후처리 필터 필수
- ❌ **뉴스레터·스팸 필터 누락 금지** (v2.3): Gmail은 category 필터, Outlook은 도메인 패턴 매칭으로 사전 제외

## Verification (응답 전 자기 점검)

1. **Step 1 date 명령 실제 실행했는가?** 출력 라인 인용 가능?
2. Step 2-4 중 **최소 2개 도구 호출 실제 시도**했는가? (성공/실패 무관)
3. 외부 발신 0건인가?
4. 응답 분량 1500자 이내 (텔레그램 가독성)?
5. Personal Data 영역 (`_personal`, SOUL 등) 누수 없는가?
6. **이메일 주소·꺽쇠 `<...>` 출력에 0건인가?** (발신자 이름만)
7. **Gmail/Outlook 섹션 분리 + 카운트 명시했는가?**
8. **Outlook 결과에 Gmail forward 중복 dedup 적용했는가?**
9. **뉴스레터 패턴 (substack/beehiiv/noreply/newsletter) 필터링 했는가?**

## References

- Phase 6 완료 기록: `docs/planning/01-plan/features/hermes-google-mcp.plan.md` v1.5 (2026-05-16)
- Plan §3.4 채널 정책: `docs/planning/01-plan/features/hermes-agent-deployment.plan.md`
- google-workspace skill: `/opt/data/skills/productivity/google-workspace/SKILL.md`
- ms365 MCP 활성 도구: `mcp_servers.ms365 --preset mail` (Outlook mail만, Calendar/Files 비활성)
- 데이터 소스 제외 룰: `memory/feedback_data_source_exclusions.md`
- CCO 외부 발신 게이트: Plan §7
- Personal Data Protection: `.claude/rules/personal-data-protection.md`
