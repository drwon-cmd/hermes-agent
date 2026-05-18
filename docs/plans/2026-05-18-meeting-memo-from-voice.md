# Plan: Meeting Memo from Voice (Telegram Voice → PDF Memo)

**Date**: 2026-05-18
**Owner**: WVB (드왕대 → 원대로 대표)
**PDCA Route**: 옵션 2 main 직접 PDCA (cto-lead-routing.md v3, 외부 OSS + Docker 통합 도메인)
**Status**: Plan draft — 사용자 승인 대기

---

## §1. Goal

사용자가 **Telegram bot(`@drwon_assistant_bot` 또는 wvb 전용 봇)에 미팅 음성 파일을 첨부**하면:
1. Hermes가 자동으로 STT 전사 (OpenAI Whisper API, $0.006/분)
2. **사전 비용 추정 + 사용자 1회 승인** 후 진행
3. 김실장 미팅메모 v2 포맷으로 메모 작성
4. Markdown → PDF 변환
5. 같은 Telegram 대화방에 **PDF 파일로 답신**

### Success Criteria (검증 가능)

- [ ] 1h 미팅 음성 → 5분 이내 PDF 답신 도착
- [ ] 미팅메모 PDF가 김실장 v2 포맷 준수 (Executive Summary 1p 상단 + 본문 + 메타 하단)
- [ ] STT 비용이 사전 추정 ±20% 이내 정확
- [ ] 외부 노출 0건 (메모 내용은 Telegram bot ↔ 사용자 1:1 DM만)

---

## §2. Why

### 사용자 페인포인트
- 미팅 직후 데스크톱 CC(`/meeting-memo`) 실행이 불편 (이동 중·점심·외근)
- 폰만으로 음성 → 메모 받고 싶음
- 현재 옵션: (a) 메모리 + 직접 받아쓰기 (느림·누락) / (b) 음성만 저장 후 데스크톱 가서 처리 (지연·잊힘)

### 비즈니스 가치
- 미팅 후속 액션 누락률 감소 (Executive Summary 즉시 받음)
- biz list·decisions 업데이트 시계열 데이터 자동 축적 (장기)
- CEO 시간 보존 (메모 정리 시간 0)

---

## §3. Alternatives (외부 시스템 native 지원 사전 검증 완료)

### Alt 1 — Telegram → Hermes auto STT → 자체 미팅메모 skill → PDF (채택)

**검증 결과**:
- Telegram voice inbound: ✓ `gateway/platforms/telegram.py:4266-4285` — `msg.voice` / `msg.audio` 자동 다운로드 → `event.media_urls` cached_path
- STT 자동 실행: ✓ `cli-config.yaml.example:810-822` — `stt.enabled: true` + provider 선택 시 voice 메시지 자동 전사 (`Automatically transcribe voice messages on messaging platforms`)
- OpenAI Whisper 지원: ✓ `stt.openai.model: "whisper-1"` (cli-config L820), env `OPENAI_API_KEY`
- send_document PDF 송신: ✓ `telegram.py:3268` `async def send_document`
- LLM (미팅메모 작성): ✓ Hermes 기본 모델 (OpenRouter 경유, `model.default` in `~/.hermes/config.yaml`)

**장점**: 모든 컴포넌트 native 지원. 코드 신규 작성 최소 (skill 1개 + 비용 가드 1개).

### Alt 2 — Telegram → 외부 webhook → 별도 backend (Python FastAPI 등) → Telegram answer

**기각 사유**:
- Hermes 외에 별도 백엔드 운영 필요 (Railway 1개 추가 비용)
- Telegram bot 이중 등록 충돌 (한 bot은 한 webhook만)
- Hermes의 LLM/모델 라우팅·OpenRouter 통합 재구현 필요

### Alt 3 — Telegram → Hermes → 데스크톱 CC에 webhook → `/meeting-memo` 실행 → 결과 회신

**기각 사유**:
- 데스크톱 CC가 항상 켜져 있어야 함 (페인포인트와 모순)
- CC ↔ Hermes 양방향 통신 인프라 신규 필요
- 사용자 의도 (폰만으로 완결)에 부합 안 함

---

## §4. 사용자 결정 사항 (2026-05-18 확정)

| # | 결정 항목 | 사용자 선택 | 근거 |
|---|---|---|---|
| 1 | 미팅메모 엔진 | **B. Hermes 자체 skill + 기본 LLM** | 김실장 스킬은 CC 전용. 포맷·프롬프트만 차용 |
| 2 | STT provider | **OpenAI Whisper API** ($0.006/분) | Groq 무료 옵션 있지만 한국어 정확도 우선 |
| 3 | 비용 한도 | **1회당 사전 승인 명시** (월 결제 제한 없음) | cost-guard 준수, 고가 패턴 (3h+) 사용자 검토 |
| 4 | LLM | **Hermes 기본 모델 그대로** | 별도 설정 없이 일관성 유지. 현재 deployed model 확인 필요 (Plan §5 Risk) |
| 5 | PDCA 진행 | **옵션 2 main 직접** | 외부 OSS + Docker 통합 — main 직접이 안전 |

**원칙적 약속** (사용자 결정 정신):
- 미팅 내용은 외부 발신 0건 (Telegram DM만)
- 비용은 매번 사전 추정 + 승인. silent 호출 금지
- Hermes 기본 모델로 일관성 — 별도 paid model 호출 안 함 (사용자 별도 결정 없는 한)

---

## §5. Risks & Mitigations

| Risk | 영향 | Mitigation |
|------|------|-----------|
| R1. Whisper 25MB 파일 제한 (Telegram voice 자체는 50MB까지) | 30분+ 고품질 녹음 일부 실패 가능 | Hermes 내장 audio split 기능 확인 또는 `pydub`로 분할 |
| R2. 사용자 1회 사전 승인 흐름 — Hermes의 confirmation pattern | Hermes에 `confirm` skill 패턴 있는지 미확인 | Plan 승인 후 Design 단계에서 검증 (build-then-verify §11 fetch) |
| R3. 현재 deployed Hermes LLM 모델 미확인 | 한국어 미팅메모 품질 보장 안 됨 | Plan 승인 직후 Railway env에서 `model.default` 확인. 만약 free Llama 등이면 사용자에게 paid 옵션 별도 결정 받기 |
| R4. 미팅 음성 = 민감 정보 (인사·재무·M&A 등) | 외부 노출 시 큰 사고 | Telegram DM 외 0개 전송. PDF 임시 파일 경로 `/tmp/` 처리 + 송신 후 삭제. STT 결과 Hermes log에도 본문 미저장 (메타만) |
| R5. Hermes upgrade 시 stt/skill 호환성 깨질 가능 | 미팅 메모 도구 갑작스럽게 멈춤 | wvb skill로 격리 (`skills/wvb/wvb-meeting-memo/SKILL.md`). git pin |
| R6. 1회당 사전 승인이 사용자 부담될 수 있음 | UX 마찰 | 추정 비용이 $1 미만이면 묵시 진행, $1 이상만 승인 prompt 옵션 검토 (사용자 별도 결정) |
| R7. PDF 생성 라이브러리 (reportlab/weasyprint) Hermes 이미지 미포함 | 첫 실행 실패 | Dockerfile에 `pip install reportlab` 추가. Pretendard 폰트는 PPT가 아니라 PDF니까 system font fallback 허용 |

---

## §6. Out of Scope (이 Plan 비포함)

- ❌ Summary PPT 자동 생성 (김실장 v2의 PPT 기능) — MVP는 PDF만
- ❌ 참석자·날짜 사전 질문 인터랙티브 (Telegram 텍스트로 후처리 가능, MVP는 음성 메타에서 추출 못하면 "참석자: 미확인" 명시)
- ❌ MD·DOCX·PPTX 다중 출력 (PDF 1개만)
- ❌ 김실장의 PPT 자동 생성 (`pptx_style_kit` 차용) — 별도 PRD 필요 시 후속
- ❌ 미팅메모 DB 저장 (`wiki/meetings/` 자동 저장) — MVP는 Telegram DM 1회성
- ❌ 다국어 자동 감지 — 한국어 디폴트만
- ❌ 화자 분리 (Whisper-1은 화자 미분리). 화자 분리 필요 시 사용자 별도 결정

---

## §7. Phase Breakdown (Plan 승인 후)

| Phase | 작업 | 검증 |
|-------|------|------|
| **Design** | Hermes의 confirm pattern·skill trigger·PDF 생성 흐름 정밀 fetch | Design.md 작성 |
| **Do 1** | `skills/wvb/wvb-meeting-memo/SKILL.md` 작성 (김실장 v2 포맷 차용) | Hermes skill_view로 trigger 검증 |
| **Do 2** | Hermes config.yaml에 `stt.openai.model: whisper-1` 추가 + env `OPENAI_API_KEY` Railway 설정 | Telegram 음성 1회 테스트 |
| **Do 3** | PDF 생성 모듈 (reportlab) + Dockerfile 업데이트 | Sample MD → PDF 변환 검증 |
| **Do 4** | 1회당 사전 승인 흐름 (Hermes의 confirm pattern 활용) | 음성 첨부 → 비용 추정 prompt 응답 → 진행 |
| **Check** | E2E 시나리오 — 5분 / 30분 / 1h 미팅 3개 샘플로 검증 | PDF 도착 + 포맷 검증 + 비용 정확성 |
| **Act** | wiki/projects/에 운영 가이드 + memory에 RCA 패턴 | 정기 점검 자동화 |

---

## §8. 검증 약속 (build-then-verify §11 준수)

Plan 작성 시점에 사전 fetch 완료한 외부 의존:
- `gateway/platforms/telegram.py:4266-4285` (voice inbound)
- `gateway/platforms/telegram.py:3268` (send_document)
- `cli-config.yaml.example:810-822` (STT auto-transcribe)
- `.env.example:5-15` (OpenRouter LLM)

Design 단계에 추가 fetch 의무:
- Hermes의 confirm/approval skill pattern (sample skill 확인)
- Hermes Dockerfile의 base image + pip install 흐름
- Railway env update 방법 (CLI 또는 dashboard)
- reportlab 한국어 폰트 fallback 동작 (Pretendard 없으면)

---

## §9. Approval

Plan 승인 시 Design 단계 진행. 승인 전 본 문서 §4 사용자 결정 사항 변경 원하시면 말씀.

**Plan 검토 포인트** (사용자 확인 요청):
1. §1 Success Criteria 4개 적절한가?
2. §3 Alt 1 채택에 동의?
3. §5 Risks 중 추가로 우려되는 것?
4. §6 Out of Scope 중 MVP에 포함해야 할 것?
5. §7 Phase 순서 OK?

---

*Created: 2026-05-18 by main direct PDCA (cto-lead 위임 없음). Plan owner = 사용자. Verifier = build-then-verify v1.10 §11.*
