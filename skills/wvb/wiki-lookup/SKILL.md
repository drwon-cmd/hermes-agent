---
name: wvb-wiki-lookup
description: WVB 위키(인물·회사·프로젝트·의사결정·개념) 검색. 김실장·원대로 대표·POPUP·Zero100·해녀 등 비즈니스 컨텍스트 질문 시 자동 호출.
version: 1.0.0
metadata:
  tags: [wvb, wiki, search, context, knowledge]
  domain: wvb
  trigger_keywords:
    - 김실장
    - 원대로
    - POPUP
    - Zero100
    - 해녀
    - 자회사
    - 위키
    - drwon-advisory
    - wvb
    - 사주
    - 의사결정
    - 페르소나
---

# WVB Wiki Lookup

## When to Use

다음 트리거 시 즉시 본 skill 호출:

- 사용자가 WVB의 인물(원대로 대표·김실장·이세연 등)·자회사(POPUP·Zero100·해녀)·프로젝트(drwon-advisory·warm-connect·hermes-agent)·의사결정·전략·개념을 질문할 때
- "위키에서 X 찾아줘", "X에 대해 알려줘" 같은 자연어 lookup
- 사용자 컨텍스트 모호 시 wiki/people/·wiki/projects/·wiki/decisions/ 사전 조회

## Quick Reference

| Wiki 영역 | 경로 | 용도 |
|---|---|---|
| 인물 프로필 | `/opt/data/wiki/wiki/people/` | 직원·advisor·외부 인물 |
| 회사·파트너 | `/opt/data/wiki/wiki/companies/` | 자회사·파트너·고객사 |
| 프로젝트 상태 | `/opt/data/wiki/wiki/projects/` | drwon-advisory·해녀·WMPA·warm-connect 등 |
| 의사결정 기록 | `/opt/data/wiki/wiki/decisions/` | P0 의사결정·V13 시리즈 |
| 개념·프레임워크 | `/opt/data/wiki/wiki/concepts/` | 비즈니스 방법론 |
| 위클리 보고서 | `/opt/data/wiki/wiki/events/weekly/` | 주간 보고 누적 |
| 인사이트·Q&A | `/opt/data/wiki/wiki/insights/` | 발견·비교 분석 |
| 인덱스 | `/opt/data/wiki/wiki/_meta/index-full.md` | 전체 카탈로그 |

## Procedure

1. **인덱스 우선 조회** — `/opt/data/wiki/wiki/_meta/index-full.md` Read하여 관련 페이지 후보 식별 (제목 + 태그 기반)
2. **카테고리 폴더 grep** — 식별 안 되면 해당 카테고리 폴더에서 키워드 grep
3. **페이지 Read** — 매칭 페이지 Read (보통 1-3개)
4. **요약 응답** — 사용자 질문에 직접 답하는 형식으로 wiki 정보 종합 (raw 인용 X)
5. **출처 명시** — 응답 끝에 참조한 wiki 페이지 path 명시 (예: `참조: wiki/people/won-daero.md`)

## Pitfalls

- ❌ `/opt/data/wiki/wiki/_personal/` 폴더 read 금지 (Personal Data Protection)
- ❌ wiki write 시도 금지 (read-only consumer 원칙, Plan §3.5)
- ❌ wiki에 없는 정보를 prior knowledge로 채우기 금지 — "wiki에 명시 없음" 명시
- ❌ 사용자가 wiki에 추가 요청하면 "Phase 1.5에서 활성 예정" 안내, 텔레그램에서 "wiki/projects/X.md에 추가" 같은 명령 받으면 거절
- ❌ raw 9,000개 파일 (raw/ 폴더)은 grep 대상에서 제외 (성능 + 노이즈)

## Verification

응답 후 자기 점검:

1. wiki 페이지를 실제 Read 했는가? (path 인용 가능?)
2. 사용자 질문에 직접 답했는가? (raw 복사 아님)
3. 출처 명시 했는가?
4. _personal/SOUL 영역 누수 없는가?

## References

- WVB Wiki SCHEMA: `/opt/data/wiki/wiki/SCHEMA.md`
- Wiki 인덱스 (전체): `/opt/data/wiki/wiki/_meta/index-full.md`
- Wiki 카테고리 인덱스 (concepts): `/opt/data/wiki/wiki/_meta/index-concepts.md`
- Personal Data Protection 룰: 외부 노출 금지 (SOUL.md·USER.md·_personal/*)
