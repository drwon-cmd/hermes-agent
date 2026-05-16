---
name: wvb-weekly-signal
description: 매주 일요일 18:00 KST 주간 시그널 종합 — 지난주 의사결정·biz list 변화·외부 이슈·다음주 P0. Cron 자동 + /weekly 수동.
version: 1.0.0
metadata:
  tags: [wvb, weekly, signal, executive, cron]
  domain: wvb
  cron: "0 18 * * 0"
  timezone: "Asia/Singapore"
  trigger_keywords:
    - 주간 시그널
    - 주간 종합
    - 위클리
    - 지난주
    - /weekly
---

# WVB Weekly Signal Digest (일요일 18:00 KST)

## When to Use

- **자동 트리거**: 매주 일요일 18:00 KST cron (Phase 1.5)
- **수동 트리거**: `/weekly` 또는 "주간 시그널", "지난주 정리", "이번 주 종합" 자연어

## Quick Reference

```
📊 WVB Weekly Signal — 2026 W20 (5/12~5/18)

🎯 지난주 P0 의사결정 (wiki/decisions)
  - {수}건 — 핵심 3건 요약

📈 Biz List 변화 (W19 → W20)
  - 신규 진입: X건
  - Won: Y건 ($Z amount)
  - Lost: A건
  - 다음 주 후속 액션: B건

💼 자회사 KPI 변화
  - POPUP: ...
  - Zero100: ...
  - 해녀: ...
  - drwon-advisory: ...

🌐 외부 시그널 (Tavily 검색)
  - WVB 영역 관련 뉴스 3-5건
  - 경쟁사·시장 변화

🎯 다음 주 P0 (예측)
  - 일정 기반 + 미해결 의사결정
```

## Procedure

### Phase 1 (현재)
1. **wiki/decisions/ 지난 7일 신규 파일** — 의사결정 변화 (wvb-wiki-lookup)
2. **wiki/events/weekly/ 지난주 보고서** — 작업 컨텍스트
3. **Tavily 검색** — "WVB / venture studio / AI native" 관련 외부 시그널
4. **사용자 알림**: "biz list·자회사 KPI는 Phase 6 (Google Sheets·자회사 데이터 통합) 후 가동"

### Phase 6 (완전 가동)
1. wiki/decisions 지난 7일 파일 list (mtime > 7d ago)
2. Google Sheets biz list 변화 (W-1 vs W) — 신규/won/lost
3. 자회사 KPI 시트 변화
4. Tavily 검색 (WVB 관련 키워드 5개)
5. 다음 주 캘린더 미팅 + 미해결 의사결정 종합
6. AI 종합 (Gemini Flash) → 1-2 파라그래프 핵심 요약

## Pitfalls

- ❌ Tavily 1,000/월 한도 — 한 weekly digest당 5-10 검색만 (한도 보존)
- ❌ 외부 뉴스 raw 인용 금지 — 1줄 요약 + URL
- ❌ 자회사 민감 KPI를 텔레그램에 평문 노출 금지 — 변화 방향(↑/↓/→)만
- ❌ 다음 주 예측을 *확정 정보*처럼 작성 금지 — "예측·후보" 명시

## Verification

1. wiki/decisions 실제 7일 mtime 비교 했는가?
2. Tavily 검색 1회 이내인가?
3. 외부 시그널 URL 인용 있는가?
4. Phase 6 미통합 영역 정직히 알림 했는가?

## References

- wvb-wiki-lookup skill (전제 의존)
- Plan §6 Phase 5 Cron jobs
- 주간보고 풀소스 게이트 (`memory/feedback_weekly_report_full_source.md`)
- 보고서 압축 포맷 (`memory/feedback_weekly_report_format_default.md`)
