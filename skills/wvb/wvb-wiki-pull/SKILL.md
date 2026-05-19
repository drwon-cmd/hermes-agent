---
name: wvb-wiki-pull
description: WVB wiki(drwon-cmd/wvb-ai-workspace) 자동 git pull. 부팅 시 1회 clone 이후 stale 문제 해결. Script-only cron 매 4시간 발사 권장 (KST 04·08·12·16·20·24시). wvb-wiki-lookup·wvb-daily-brief·wvb-calendar-prep 등 wiki 의존 skill의 prerequisite.
version: 1.0.0
metadata:
  tags: [wvb, wiki, cron, automation, prerequisite]
  domain: wvb
  cron: "0 */4 * * *"
  timezone: "Asia/Singapore"
  mode: "script-only"
  trigger_keywords:
    - wiki pull
    - wiki 갱신
    - wiki 업데이트
    - 위키 동기화
---

# WVB Wiki Pull (Script-Only Cron)

## When to Use

- **자동 트리거 (권장)**: Hermes cronjob에 script-only 매 4시간 등록. 컨테이너 TZ=Asia/Singapore → SGT 00·04·08·12·16·20시 발사 (KST 01·05·09·13·17·21시 보정 후 — 본 skill은 SGT 기준 `0 */4 * * *`).
- **수동 트리거**: 사용자가 봇에 "wiki pull 해줘" / "위키 동기화" / "wiki 갱신" 자연어 호출

## Why This Exists

Hermes entrypoint.sh는 부팅 시 wiki를 git clone (depth 1) 한 번만 실행. 부팅 후 사용자가 wvb-ai-workspace에 push해도 컨테이너 wiki는 stale 상태. 다른 wiki 의존 skill (wvb-wiki-lookup·wvb-daily-brief 등)이 outdated 정보 인용.

본 skill은 그 격차를 자동 git pull로 메꾸는 prerequisite 인프라.

## Script Location

스크립트 본체: `/opt/data/skills/wvb/wvb-wiki-pull/scripts/pull.sh`

Hermes script-only cron은 `~/.hermes/scripts/` 디렉토리를 accept하므로, 봇이 cron 등록 시 다음 중 하나 선택:
- **(A)** `~/.hermes/scripts/wvb-wiki-pull.sh` 에 본 SKILL의 pull.sh 내용 복사 후 cronjob 등록 (권장)
- **(B)** cronjob의 script 인자에 직접 `/opt/data/skills/wvb/wvb-wiki-pull/scripts/pull.sh` absolute path 전달 (가능 시)

## Setup Procedure (봇에게 자연어로 한 번만 요청)

사용자가 봇에 다음 메시지 발송:

```
wvb-wiki-pull skill을 script-only cron으로 매 4시간 등록해줘.
- 스크립트: /opt/data/skills/wvb/wvb-wiki-pull/scripts/pull.sh 의 내용을 ~/.hermes/scripts/wvb-wiki-pull.sh 로 복사
- schedule: "0 */4 * * *"  (SGT 매 4시간)
- no_agent: true
- deliver: telegram (출력 비어있으면 silent, pull 결과만 알림)
- name: wvb-wiki-pull
```

봇은 다음 두 도구 호출 수행:
1. `write_file(path="~/.hermes/scripts/wvb-wiki-pull.sh", content=<pull.sh 내용>)`
2. `cronjob(action="create", schedule="0 */4 * * *", script="wvb-wiki-pull.sh", no_agent=true, deliver="telegram", name="wvb-wiki-pull")`

## Script Behavior

`pull.sh`는 다음 동작:
1. `/opt/data/wiki/` 디렉토리 존재 확인 (없으면 skip — entrypoint clone 실패 케이스)
2. `git -C /opt/data/wiki pull --rebase --quiet` 실행
3. 결과 판정:
   - **Already up to date**: stdout 비움 (silent tick)
   - **새 파일 fetch**: stdout에 `[wiki-pull] N files updated: ...` 출력 → 텔레그램 알림
   - **에러**: stdout에 `[wiki-pull] ERROR: <메시지>` 출력 → 텔레그램 알림
4. Personal data scrub 재실행 (entrypoint와 동일 패턴):
   - `wiki/_personal/` 디렉토리 제거
   - `SOUL.md`·`USER.md`·`ACCESS_POLICY.md`·`HEARTBEAT.md` 파일 제거

## Pitfalls

- ❌ **`~/.hermes/scripts/wvb-wiki-pull.sh` 직접 git pull 안 함** — 컨테이너의 git 명령은 hermes user 권한이라 /opt/data/wiki 소유권 OK
- ❌ **`git push` 절대 금지** — 본 skill은 read-only consumer. pull만, push 안 함
- ❌ **WIKI_REPO_URL envvar 직접 echo 금지** — secret leak 방지 (entrypoint.sh:39 사고 박제)
- ❌ **pull 충돌 시 force overwrite 금지** — `--rebase` 옵션으로 안전 처리, conflict 시 ERROR 메시지로 보고
- ❌ **Personal data scrub skip 금지** — pull로 _personal/·SOUL/ 다시 들어올 가능성 있어 scrub 필수

## Verification

cron 등록 후 작동 확인:

1. **수동 발사 테스트**: 텔레그램에 "wiki pull 해줘" → 봇이 즉시 pull.sh 실행 + 결과 응답
2. **cron 등록 확인**: 텔레그램에 "/cron list" 또는 "cron 등록된 job 보여줘" → wvb-wiki-pull 등장 확인
3. **다음 4시간 후 자동 발사 확인**: Hermes cron logs 또는 텔레그램 알림 (pull 결과 있으면)
4. **wvb-wiki-lookup 작동 확인**: 새 wiki commit 후 4시간 내 봇이 새 내용 인용 가능한지

## References

- Hermes cron-script-only docs: `website/docs/guides/cron-script-only.md`
- Hermes cron internals: `website/docs/developer-guide/cron-internals.md`
- WVB wiki repo: `drwon-cmd/wvb-ai-workspace` (private, GitHub PAT via WIKI_REPO_URL)
- entrypoint.sh 부팅 clone 로직: `scripts/entrypoint.sh` Step 3 §Wiki submodule 초기화
- Personal Data Protection 룰: `wiki/_personal/`·SOUL/USER 외부 노출 금지
