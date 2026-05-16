---
name: wvb-cost-report
description: 매일 02:00 KST hermes 자체 비용 + 외부 API 사용량 리포트 — cost-guard 한도 모니터링. Cron 자동 + /cost 수동.
version: 1.0.0
metadata:
  tags: [wvb, cost, monitoring, cost-guard, cron]
  domain: wvb
  cron: "0 2 * * *"
  timezone: "Asia/Singapore"
  trigger_keywords:
    - 비용
    - cost
    - 사용량
    - /cost
    - 한도
---

# WVB Cost Report (02:00 KST 매일)

## When to Use

- **자동 트리거**: 매일 02:00 KST cron (Phase 1.5)
- **수동 트리거**: `/cost` 또는 "비용 리포트", "이번 달 사용량"

## Quick Reference (출력 형식)

```
💰 WVB Cost Report — 2026-05-16

🔹 Hermes (Railway hermes-agent service)
  - 이번 달 누적: $X.XX / $15 한도 (XX%)
  - 어제 사용: $X.XX
  - 7일 평균: $X.XX/일

🔹 LLM API (Gemini Flash via Google AI Studio)
  - 이번 달: X 요청 / 1,500 일별 한도
  - 어제: Y 요청
  - 비용: $0 (무료 티어)

🔹 검색 API (Tavily)
  - 이번 달: X 검색 / 1,000 한도 (XX%)
  - 어제: Y 검색

🔹 STT API (OpenAI Whisper) — Phase 1.5 활성 시
  - 이번 달: X 분 ($XXX)

🔹 Anthropic API (escalation only, Phase 1.5)
  - 이번 달: $X / $10 Hard Limit
  - 호출 횟수: X (escalation 키워드 매칭)

⚠️ 한도 도달 임박
  - {service}: {%} → 액션 권장

📊 권장 액션
  - {예: Tavily 80% 도달 → 검색 빈도 조절}
```

## Procedure

### Phase 1 (현재)
1. 사용자 알림: "Railway·Anthropic·Google billing API 통합은 Phase 6 후. 현재는 Gemini AI Studio quota 페이지·Tavily dashboard 수동 확인 안내"
2. 환경변수 `HERMES_COST_ALERT_THRESHOLD_USD` (10), `HERMES_COST_BLOCK_THRESHOLD_USD` (15) 정책 안내

### Phase 6 (완전 가동)
1. Railway billing API 또는 dashboard scrape — 이번 달 hermes-agent service 사용량
2. Google AI Studio API — Gemini Flash 요청 수 (gcloud command 또는 console API)
3. Tavily API — `/usage` endpoint 호출
4. Anthropic Console — Monthly spend 조회
5. OpenAI Console — Audio:Whisper 사용량
6. 종합 + 한도 대비 % 계산 + 80%+ 도달 시 alert

## Pitfalls

- ❌ 비용 정보를 외부 발신 (이메일·슬랙) 금지 — 텔레그램 admin 전용
- ❌ 사용량 데이터를 wiki에 저장 시도 금지 (read-only)
- ❌ 한도 도달 시 자동 차단 시도 금지 — alert만, 사용자 결정

## Verification

1. 각 service API 호출 1회씩만? (한도 보존)
2. 외부 발신 0건?
3. 한도 % 계산 정확?
4. Phase 6 미통합 영역 정직 알림?

## References

- cost-guard.md 룰 (`.claude/rules/cost-guard.md`)
- Plan §5 비용 추정
- Plan §7 CCO 게이트 (한도 알림 기준)
