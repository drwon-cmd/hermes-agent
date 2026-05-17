---
name: wvb-calendar-prep
description: 매일 21:00 KST 내일 일정 prep — 미팅별 자료·참석자·사전 준비 사항 정리. Cron 자동 + /prep 수동.
version: 1.0.0
metadata:
  tags: [wvb, calendar, prep, evening, cron]
  domain: wvb
  cron: "0 20 * * *"
  timezone: "Asia/Singapore"
  trigger_keywords:
    - 내일 일정
    - 캘린더 prep
    - 미팅 준비
    - /prep
    - 내일 미팅
---

# WVB Calendar Prep (21:00 KST 매일)

## When to Use

- **자동 트리거**: 매일 21:00 KST (잠들기 전 내일 미팅 prep)
- **수동 트리거**: `/prep` 또는 "내일 일정 정리해줘", "내일 미팅 준비"

## Quick Reference (출력 형식)

```
🌙 내일 일정 (2026-05-17 토) — 사전 준비 체크

📅 10:00-11:00 미팅 X
  📍 {장소·zoom·offline}
  👥 참석자: {이름·소속}
  📋 사전 준비:
    - 자료: {wiki·biz list·이전 미팅 메모 위치}
    - 어젠다: {3-5 항목}
    - 핵심 결정 사항: {1-2개}

📅 14:00-15:00 콜 Y
  ...

🎯 내일 전체 흐름 1줄
  - "오전 X미팅 → 점심 Y → 오후 Z콜로 마무리"

⚠️ 주의 사항
  - 시차 (X미팅이 외부 client SGT 기준?)
  - 자료 미준비 (위 list 중 fetch 안 된 것)
```

## Procedure

### Phase 1 (제한 가동)
1. 사용자 알림: "Google Calendar 통합은 Phase 6 후. 현재는 이전 미팅 메모 wiki/events/meetings/ 조회만 가능"
2. wiki/events/meetings/ 조회 (있다면)

### Phase 6 (완전 가동)
1. Google Calendar 내일 일정 list (`google_calendar_list_events` 도구, time_min/max = 내일 00:00-23:59 KST)
2. 각 미팅별:
   - 참석자 이메일 → wiki/people/ 조회 (배경 정보)
   - 이전 미팅 메모 (wiki/events/meetings/{slug}.md)
   - 관련 biz list 항목 (client 매칭)
   - 사전 자료 (Google Drive 검색 또는 wiki)
3. 어젠다 추출 (이전 미팅 후 약속한 사항 + 변화 사항)
4. 핵심 결정 사항 (미해결 의사결정)
5. 전체 흐름 1줄 요약

## Pitfalls

- ❌ 미팅 자료 자동 다운로드 + 텔레그램 첨부 금지 (보안)
- ❌ 참석자 개인 정보 (전화번호·주소) 노출 금지 (wiki/people/에 있어도 텔레그램에 평문 X)
- ❌ 캘린더 자동 수정 금지 (read-only)
- ❌ Phase 1에서 "내일 X 미팅 있어요" 거짓 응답 금지

## Verification

1. Google Calendar API 호출 횟수 (한도 보존)?
2. 참석자 개인 정보 평문 노출 없는가?
3. wiki 미팅 메모 실제 Read?
4. 자동 수정 0건?

## References

- Plan §3.4 채널 정책
- Google Calendar 데이터 소스 (`memory/feedback_data_source_exclusions.md`)
- 미팅 메모 v2 (`memory/feedback_meeting_memo_v2_format.md`)
