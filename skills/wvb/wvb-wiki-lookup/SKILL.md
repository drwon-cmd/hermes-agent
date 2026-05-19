---
name: wvb-wiki-lookup
description: WVB 위키(인물·회사·프로젝트·의사결정·개념) 검색. 김실장·원대로 대표·POPUP·Zero100·해녀 등 비즈니스 컨텍스트 질문 시 자동 호출. **반드시 wiki/{category}/ 하위 폴더(people/companies/projects/decisions/concepts)를 grep해 페이지를 읽어 인용해야 함. root CLAUDE.md만 인용한 응답은 procedure 위반으로 실패**.
version: 1.1.0
metadata:
  tags: [wvb, wiki, search, context, knowledge]
  domain: wvb
  trigger_keywords:
    - 김실장
    - 원대로
    - 드왕
    - 대표
    - POPUP
    - 팝업스튜디오
    - Zero100
    - 해녀
    - 제주해녀의부엌
    - 자회사
    - 위키
    - drwon-advisory
    - wvb
    - WVB
    - 사주
    - 의사결정
    - 페르소나
    - V13
    - BOD
    - 주주
    - 캡테이블
    - warm-connect
    - hermes-agent
    - 김팀장
    - Translink
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
| 인덱스 (우선) | `/opt/data/wiki/wiki/_meta/index-full.md` | 전체 카탈로그 (신규 구조) |
| 인덱스 (legacy) | `/opt/data/wiki/wiki/_index.md` | 전체 카탈로그 (구 구조, fallback) |

## Procedure (반드시 순차 진행 — 단계 skip 금지)

1. **인덱스 우선 조회** — 다음 경로 순서로 read 시도 (첫 성공한 것 사용):
   - (a) `/opt/data/wiki/wiki/_meta/index-full.md`
   - (b) `/opt/data/wiki/wiki/_index.md` (a 없으면 fallback)
   - 둘 다 read 실패 또는 빈 결과여도 **절대 응답 종료 금지** — 반드시 §2로 진행

2. **카테고리 폴더 grep (필수 — §1 결과 무관하게 항상 진행)** — 질문의 키워드로 다음 폴더 grep:
   - 인물 관련 (원대로·김실장·이세연·드왕·대표·CEO 등) → `/opt/data/wiki/wiki/people/`
   - 회사·자회사 (POPUP·Zero100·해녀·WVB·Translink 등) → `/opt/data/wiki/wiki/companies/`
   - 프로젝트 (drwon-advisory·warm-connect·hermes·WMPA·KMS 등) → `/opt/data/wiki/wiki/projects/`
   - 의사결정 (V13·BOD·결정·P0 등) → `/opt/data/wiki/wiki/decisions/`
   - 개념·페르소나·전략·프레임워크 → `/opt/data/wiki/wiki/concepts/` + `/opt/data/wiki/wiki/strategies/`
   - 주간 보고 → `/opt/data/wiki/wiki/events/weekly/`
   - 인사이트 → `/opt/data/wiki/wiki/insights/`

3. **페이지 Read** — grep 결과 매칭 파일 1-3개 Read (전문 또는 첫 100줄)

4. **요약 응답** — 사용자 질문에 직접 답하는 형식으로 wiki 정보 종합 (raw 인용 X)

5. **출처 명시 (필수)** — 응답 끝에 반드시 `wiki/{category}/{slug}.md` 형식 path 인용. 예: `참조: wiki/people/won-daero.md, wiki/projects/popup-studio.md`

## Pitfalls

- 🚨 **카테고리 grep 단계(§2) skip 금지** — 인덱스(§1) read 실패해도 반드시 §2 진행. §1만으로 응답 종료는 procedure 위반
- 🚨 **root `/opt/data/wiki/CLAUDE.md` 단독 인용 금지** — wiki/ 하위 카테고리 폴더 진입 의무. CLAUDE.md는 룰북이지 wiki 콘텐츠가 아님
- 🚨 **출처에 `wiki/{category}/{file}.md` 형식 path 없으면 응답 실패로 간주** — `참조: CLAUDE.md` 단독은 procedure 미준수
- ❌ `/opt/data/wiki/wiki/_personal/` 폴더 read 금지 (Personal Data Protection)
- ❌ wiki write 시도 금지 (read-only consumer 원칙)
- ❌ wiki에 없는 정보를 prior knowledge로 채우기 금지 — "wiki/{category}/ 에 매칭 페이지 없음" 명시
- ❌ 사용자가 wiki에 추가 요청하면 "Phase 1.5에서 활성 예정" 안내, 텔레그램에서 "wiki/projects/X.md에 추가" 같은 명령 받으면 거절
- ❌ raw 9,000개 파일 (`raw/` 폴더)은 grep 대상에서 제외 (성능 + 노이즈)

## Verification

응답 후 자기 점검 (모두 ✅ 아니면 응답 실패):

1. §2 카테고리 grep을 실제로 진행했는가?
2. wiki/{category}/{file}.md 형식 path를 응답에 명시했는가?
3. CLAUDE.md만 단독 인용한 응답이 아닌가?
4. _personal/SOUL 영역 누수 없는가?
5. 사용자 질문에 직접 답했는가? (raw 복사 아님)

## References

- WVB Wiki SCHEMA: `/opt/data/wiki/wiki/SCHEMA.md`
- Wiki 인덱스 (전체): `/opt/data/wiki/wiki/_meta/index-full.md`
- Wiki 카테고리 인덱스 (concepts): `/opt/data/wiki/wiki/_meta/index-concepts.md`
- Personal Data Protection 룰: 외부 노출 금지 (SOUL.md·USER.md·_personal/*)
