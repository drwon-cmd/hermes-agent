---
name: wvb-biz-list-review
description: WVB biz list 2026 pipeline 리뷰 — 신규 진입·진행·Won·Lost·At Risk 분류 + 후속 액션. Cron 매주 금요일 17:00 KST + /biz 수동.
version: 1.0.0
metadata:
  tags: [wvb, biz-list, pipeline, sales, cron]
  domain: wvb
  cron: "0 17 * * 5"
  timezone: "Asia/Singapore"
  trigger_keywords:
    - biz list
    - 비즈리스트
    - 파이프라인
    - pipeline
    - /biz
---

# WVB Biz List Pipeline Review (금요일 17:00 KST)

## When to Use

- **자동 트리거**: 매주 금요일 17:00 KST cron (Phase 1.5)
- **수동 트리거**: `/biz` 또는 "biz list 리뷰", "파이프라인 어떻게 되고 있어"

## Quick Reference (출력 형식)

```
💼 Biz List Pipeline Review — 2026-05-16 (금)

🎯 단계별 현황
  - Lead: X건 (지난주 +Y)
  - Qualified: X건
  - Proposal: X건 (총 $XXX)
  - Won (이번 주): X건 ($XXX)
  - Lost (이번 주): X건 (사유: ...)
  - At Risk: X건 → 후속 액션 필요

🔴 At Risk 상세 (1-3건)
  - {client}: {상태} → {권장 액션}

🎯 다음 주 우선 액션
  - {client}: {액션} by {일정}
```

## Procedure

### Phase 1 (현재) — 제한된 가동
1. **wiki/companies/ 또는 wiki/projects/ 조회** — biz 컨텍스트 (wvb-wiki-lookup)
2. **사용자 정직 알림**: "biz list 2026 스프레드시트(Google Sheets)는 Phase 6 통합 후 가동. 현재는 wiki/companies 기반 컨텍스트만 제공"

### Phase 6 (완전 가동)
1. Google Sheets biz list 2026 read (sheet ID는 Variables에 등록)
2. 단계별 분류 (Lead / Qualified / Proposal / Won / Lost / At Risk)
3. 이번 주 변화 (지난주 snapshot 대비)
4. At Risk 항목 후속 액션 추출 (메모 컬럼 + 마지막 contact 일자)
5. 다음 주 우선 액션 list

## Pitfalls

- ❌ biz list 자동 수정 금지 (read-only consumer)
- ❌ 클라이언트 이름 평문 노출 신중 — 일부 민감한 client는 코드명 사용
- ❌ Won 금액을 외부 노출 가능한 곳(슬랙·이메일 자동 발송)에 보내기 금지 (CCO 게이트)
- ❌ At Risk 사유를 추측으로 채우기 금지 — sheet 메모 컬럼만 인용

## Verification

1. wiki/companies/·wiki/projects/ 실제 Read 했는가?
2. Phase 6 미통합 영역 정직히 알림?
3. 자동 수정·외부 발신 0건?
4. 응답 분량 1000자 이내 (텔레그램)?

## References

- biz list 자동화 룰 (`.claude/instructions/biz-list-update.md`)
- bizlist-manager agent (`.claude/agents/agency/popup/bizlist-manager.md`)
- 데이터 소스 제외 룰 (`memory/feedback_data_source_exclusions.md`)
