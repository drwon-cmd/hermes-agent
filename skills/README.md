# WVB Hermes Skills (Mirror)

Phase 4에서 작성 예정. 현재는 빈 폴더 + 본 README만 존재.

## 작성 예정 Skill (Plan §6 Phase 4)

| Skill | 역할 | 의존 wiki/memory 경로 |
|---|---|---|
| `daily-brief/` | 매일 06:00 일일 브리핑 (캘린더 + biz list + Slack 미수신) | `wiki/projects/`, `wiki/people/`, `memory/projects/` |
| `weekly-signal/` | 매주 일 18:00 주간 시그널 종합 | `wiki/decisions/`, `wiki/projects/` |
| `biz-list-review/` | 매주 금 17:00 biz list pipeline review | `wiki/projects/biz-list-2026.md` |
| `calendar-prep/` | 매일 21:00 내일 미팅 prep | 캘린더 MCP (Phase 4 결정) |
| `wiki-lookup/` | 일반 wiki/ 검색 (브레인-first lookup) | `wiki/`, `memory/` 전체 (read-only) |
| `cost-report/` | 매일 02:00 비용 집계 | Hermes 내장 routing log |

## 작성 원칙

1. **Read-only**: wiki/·memory/ 에 write 시도 금지 (CCO 차단)
2. **존댓말**: 모든 응답 한국어 존댓말 (`korean-writing-style.md` S1)
3. **Brain-first lookup**: 외부 검색 전 wiki/ 먼저 (`brain-first-lookup.md`)
4. **Build-then-verify**: 각 skill에 First Valid Invocation 시나리오 포함
5. **External send block**: 이메일·슬랙 발신 skill 절대 안 작성 (CCO disabled 모드)

## 작성 절차 (Phase 4 시작 시)

```bash
# 1. 별도 세션에서
/pdca do hermes-agent --scope skill-mirror

# 2. 각 skill을 Hermes 표준 형식으로 작성
#    참고: https://hermes-agent.nousresearch.com/docs/user-guide/skills

# 3. config.yaml의 skills.enabled 목록에 등록 (이미 6개 미리 등록됨)
```
