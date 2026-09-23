# TIL: prompt --wait 직후 agent wait 중복 호출 금지 (No Redundant Wait)

- **날짜**: 2026-09-23
- **작성자**: PM / Orchestration Team
- **범위**: `herdr-team` (root `AGENTS.md`, `agents/dev/AGENTS.md`, 5종 프리셋 템플릿, `templates/agents/ROLE-taskmanager.md`, `templates/opencode-agents/ROLE-orchestrator.md`, `agents/hts-taskmanager.md`)
- **관련 TIL**: [`2026-09-19-herdr-agent-wait-syntax-and-ghost-process-unblock.md`](2026-09-19-herdr-agent-wait-syntax-and-ghost-process-unblock.md), [`2026-09-21-herdr-single-command-invariant.md`](2026-09-21-herdr-single-command-invariant.md)

---

## 1. 문제 현상

Orchestrator가 `herdr agent prompt <TARGET> "..." --wait` 로 하위 에이전트 작업을 지시한 뒤, 반환 직후 `herdr agent wait <TARGET> --until idle` 를 이어서 호출하면 대상 에이전트가 이미 작업을 끝냈음에도 타임아웃까지 멈춰 서는(Stuck) 현상이 발생했다.

```
[Planner 작업 완료 → idle 전이] ──► [prompt --wait 반환] ──► [agent wait 재호출 → 무한 대기(Stuck)]
```

- `prompt --wait` 가 이미 완료 동기화를 수행했는데도, 문서의 예시/유도 문구를 그대로 따라 `agent wait` 를 중복 호출하면서 파이프라인이 불필요하게 블로킹되었다.
- 문서 자체가 "장시간 작업은 `wait` + `read`로 폴링", "`prompt --wait` 다음 줄에 `agent wait`" 같은 예시로 중복 대기를 유도하고 있었다. **주범은 개별 에이전트의 실수가 아니라 가이드 문서였다.**

---

## 2. 근본 원인 & 메커니즘

`herdr agent prompt <TARGET> "..." --wait` 는 대상이 settle(idle/done/blocked)될 때까지 **블로킹하는 완료 동기화**다.

1. 프롬프트를 전송하고, 대상이 settle 상태로 전이될 때까지 소켓 이벤트를 기다린다.
2. 대상이 idle/done/blocked 로 전이하면 즉시 반환한다.
3. 따라서 **반환 시점에 대상은 이미 settle 상태**이며, 그 직후의 `herdr agent wait <TARGET> --until idle` 은 "새로운 idle 전이 이벤트"를 기다린다.
4. 통상 완료(idle/done)로 settle 되어 반환된 경우에는 **이미 settle 이므로 추가 전이 이벤트가 발생하지 않고**, 소켓은 이벤트가 오지 않아 타임아웃까지(또는 무기한) Hang 한다. 단, `blocked`(transient)로 반환된 경우를 제외하면 항상 참은 아니다 — `blocked` 로 반환된 뒤 에이전트가 계속 작업해 `idle` 로 전이하면 `agent wait` 는 정상 반환될 수 있다.

즉, `--wait` 반환 뒤의 `agent wait` 는 "이미 도착한 이벤트"를 "다시 오기를 기다리는" 논리적 중복 대기이며, 이벤트 기반 대기의 특성상 통상 완료(idle/done) settle 경로에서는 다음 전이가 없어 영원히 풀리지 않는다.

---

## 3. 규칙

### 3.1 정규 규칙 (R1~R5)

**R1.** `herdr agent prompt <TARGET> "..." --wait` 는 대상이 settle(idle/done/blocked)될 때까지 블로킹하는 완료 동기화다. 반환 시점에 대상은 이미 settle 상태(idle/done/blocked)다.
**R2.** `prompt --wait` 반환 직후에는 `herdr agent wait <TARGET> --until idle` 을 절대 호출하지 않는다. 반환 즉시 `herdr agent read <TARGET> --lines <N>` 으로 산출물을 읽는다.
**R3.** `herdr agent wait` 는 `--wait` 없이 보낸 비동기(fire-and-forget) 프롬프트에만 사용한다(예외 경로 전용).
**R4.** `--wait` 가 타임아웃으로 반환된 경우에도 `herdr agent wait` 을 재호출하지 않고 `herdr agent read` 로 현재 상태·원인을 확인한 뒤 재지시 또는 중계한다.
**R5.** 기존 단일 명령 불변식(파이프/체인/백그라운드 금지)은 삭제하지 않고 병기한다. 중복 대기 금지는 단일 명령 불변식과 별개의 독립 규칙이다.

### 3.2 권장 패턴

```bash
# 성공 경로: 완료 동기화(--wait) → 반환 즉시 read (중복 wait 금지)
herdr agent prompt <TARGET> "..." --wait --timeout 600000
herdr agent read <TARGET> --lines 100
```

```bash
# 비동기 경로(예외): --wait 없이 전송한 뒤에만 agent wait 사용
herdr agent prompt <TARGET> "..."
herdr agent wait <TARGET> --until idle --timeout 600000
herdr agent read <TARGET> --lines 100
```

---

## 4. 기존 TIL 과의 관계

- **`2026-09-19` (유령 대기 프로세스 자동 해소)**: 이미 settle 된 대상에 물린 `agent wait` 유령 프로세스를 `bin/herdr-watcher.clean_stuck_waits` 가 감지해 kill 하는 **자가치유 안전망**이다. 본 TIL 은 그와 동일한 근본원인을 문서 차원에서 제거하는 것으로, `2026-09-19` 는 **증상 완화**, 본 TIL 은 **발생 억제**다. 둘은 중복이 아니라 상호보완이다. (안전망은 그대로 유지한다.)
- **`2026-09-21` (단일 명령 불변식)**: 파이프(`| tail`)·체인(`;`, `&&`)으로 인한 **셸 수준(표준입력 EOF) 데드락** 축으로 원인 지점이 다르다. 따라서 두 규칙은 서로를 대체하지 않고 병기한다(R5).

| 구분 | 축 | 원인 지점 | 대응 |
|---|---|---|---|
| 2026-09-21 단일 명령 불변식 | 셸 파이프/체인 | 표준입력 EOF 미수신 | 한 줄 1개 단독 명령 |
| 본 TIL 중복 대기 금지 | 이벤트 대기 | 이미 settle → 새 전이 없음 | `--wait` 후 `read` |

---

## 5. 검증

- `tests/test_preset.sh` 에 §37 "중복 대기 금지 (No Redundant Wait) 정본 반영" 회귀 섹션을 추가했다.
  - (a) 11개 정본 문서에 `중복 대기 금지` + `No Redundant Wait` 문구 존재.
  - (b) 폴링 유도 문구("장시간 작업은 `wait` + `read`로 폴링") 0건.
  - (c) 기존 유도용 `agent wait ... --timeout 600000` 예시 라인 제거.
  - (d) 펜스 상태머신(POSIX awk)으로 `prompt --wait` 이후 같은 펜스 내 `agent wait` 재호출, 및 동일 라인 체인(`prompt --wait` + `agent wait`) 탐지(비동기 예외 허용).
  - (e) 성공/타임아웃/비동기 경로 문서화 확인.
  - (f) Block A 4줄 문자 단위 동일성(md5, 10개 파일) 확인.
  - untracked 파일(`agents/dev/AGENTS.md`) 부재 시 해당 항목은 SKIP(존재 가드).
- 결과: `bash tests/test_preset.sh` → `RESULT: PASS=320 FAIL=0`.
