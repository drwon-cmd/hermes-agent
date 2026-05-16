---
name: wvb-daily-brief
description: 원대로 대표 매일 06:00 KST 일일 브리핑 — 오늘 일정·biz list 변경·미수신 메시지·우선순위 P0. Cron 자동 발사 + 사용자 수동 호출 (/brief 또는 "일일 브리핑").
version: 1.0.0
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

# WVB Daily Brief (06:00 KST)

## When to Use

- **자동 트리거**: 매일 06:00 KST cron (config.yaml의 cron 섹션, Phase 1.5에서 활성)
- **수동 트리거**: 사용자가 `/brief` 또는 "일일 브리핑" / "오늘 일정 정리" 자연어 호출

## Quick Reference (Phase 1 출력 형식)

```
📋 WVB Daily Brief — 2026-05-16 (금)

🕐 오늘 일정 (KST)
  - 10:00 미팅 X (장소·자료 준비 상태)
  - 14:00 콜 Y
  - 17:00 biz list 리뷰

📊 Biz List 변화 (어제 → 오늘)
  - 신규 진입: 2건
  - Won: 1건
  - At Risk: 3건 → 후속 액션 필요

📬 미수신 (24h)
  - Slack #80-zero100: 5개 (긴급 표시 1)
  - Gmail: 12개 (P0 분류 2)
  - 카톡 업무: 정리 필요 (Phase 1.5 자동화)

🚨 P0 의사결정 대기
  - {wiki/decisions 검색 결과}

💡 오늘의 권장 초점
  - {AI 종합 1줄}
```

## Procedure

### Phase 1 (현재) — 부분 가동
1. **wiki/decisions/ 조회** — P0 pending 의사결정 list (wvb-wiki-lookup skill 호출)
2. **wiki/events/weekly/ 최근 리포트** — 진행 중 큰 작업 컨텍스트
3. **사용자에게 정직히 알림**: "Google Calendar·Gmail·Slack·biz list 통합은 Phase 6에서 활성화 예정. 현재는 wiki 기반 컨텍스트만 제공"

### Phase 6 (Google APIs 통합 후) — 완전 가동
1. Google Calendar 조회 (`google_calendar_list_events` 도구) — 오늘 일정
2. Gmail unread search (`google_gmail_search` 도구, 라벨 `INBOX is:unread`) — 24h 미수신
3. Google Sheets biz list 비교 (어제 vs 오늘 snapshot) — 변화 추출
4. Slack `#80-zero100` 채널 unread (Phase 1.5에서 Slack 통합 후)
5. wiki/decisions/ 조회 — P0 pending (wvb-wiki-lookup)
6. 위 정보 종합 → Quick Reference 형식으로 출력

## Pitfalls

- ❌ Phase 1에서 "오늘 일정" 거짓 응답 금지 — Google Calendar 미통합 명시
- ❌ 메일 본문 그대로 인용 금지 — 발신자 + 한 줄 요약만
- ❌ 미수신 메시지를 *읽음 처리* 시도 금지 (read-only)
- ❌ Slack 자동 응답 금지 (CCO 외부 발신 게이트)
- ❌ biz list 자동 수정 금지 (read-only consumer)

## Verification

1. wiki/decisions/ 실제 Read 했는가?
2. Phase 6 미통합 영역을 정직히 명시했는가?
3. 외부 발신 0건인가?
4. 응답 분량 800자 이내 (텔레그램 가독성)?

## References

- Plan §3.4 채널 정책 (`docs/planning/01-plan/features/hermes-agent-deployment.plan.md`)
- 데이터 소스 제외 룰 (`memory/feedback_data_source_exclusions.md`)
- CCO 외부 발신 게이트 (Plan §7)
