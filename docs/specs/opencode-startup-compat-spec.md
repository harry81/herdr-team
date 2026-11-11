# opencode 시작 경로 호환 명세 (fix/windows-runtime-compat)

- 브랜치: `fix/windows-runtime-compat` (체크아웃 완료, HEAD `e774b35`)
- 대상 파일: `bin/herdr-team` (단일 스크립트), `tests/test_agent_session.sh`, `tests/test_tui_i18n.sh` 관련 MSG_KEYS
- 작성자: ht-planner (기획/설계 전용, 구현 없음)
- 상태: 구현 대기 (ht-worker 배정용)

---

## 0. 요약 & 목표

`e774b35` (win-fix)가 도입한 `opencode_supports_api` 문자열 grep 게이트가 실환경(opencode v2.1.4)에서
**오판정**을 내고, 그 결과 폴백 분기가 opencode 루트 대화형 TUI에 `--agent` 플래그를 전달해 시작이 깨진다.

목표:
1. api 지원 판별을 **실행 결과 + 종료 코드 기반**으로 재정의 (문자열 grep 폐지).
2. 시작 루프에서 **지원이 확인되지 않은 플래그를 대화형 TUI에 절대 전달하지 않는다** (불변식 I1).
3. 폴백 분기 제거 → 세션 사전생성 실패 시 fail-fast (기존 테스트 계약 복원).
4. `herdr agent start` 실패를 감지해 무한/긴 대기 없이 명시적으로 종료.
5. 기존 테스트 불변식 유지 + Windows Git-Bash 호환 유지.

**현재 베이스라인(구현 전, 실측):**
- `tests/test_agent_session.sh`: PASS=14 FAIL=13 (총 27)
- `tests/test_preset.sh`: PASS=447 FAIL=14 (총 461) — 전부 §38b perm_v2_* (V2 permissions 시딩이
  오판정으로 스킵되어 발생)
- 완료 기준: 두 스위트 0 FAIL + 타 스위트 신규 실패 0.

---

## 1. 진단 근거 (실측, 읽기 전용 명령)

### 1.1 실측 출력 (본 머신, opencode v2.1.4)

| 명령 | 결과 |
|---|---|
| `opencode --version` | `opencode v2.1.4` |
| `opencode --help` | SUBCOMMANDS에 `api   Make a request to the running server` (**`opencode api`라는 리터럴 없음, `api` 단독 토큰**). 루트 FLAGS: `--standalone --server --auto --continue --session --prompt` — **`--agent` 없음** |
| `opencode api --help` | 존재 확인됨. `USAGE: opencode api [flags] <operation \| method path...>`, FLAGS `--data/-d --header/-H --param` — **api 서브커맨드는 정상 지원**, 종료 코드 0 |
| `opencode run --help` | `--agent string`, `--session/-s`, `--model/-m` 지원 (비대화형 run 한정) |
| `opencode mini --help` | `--agent string`, `--session/-s`, `--model/-m` 지원 (mini TUI 한정) |
| `herdr agent start --help` | `--timeout <MS>` (기본 30000, 최대 300000). 성공 판정 = "expected agent was detected in the same terminal and is ready for input" |

### 1.2 버그 1 재현: 지원 판별 오판정

현재 구현(`bin/herdr-team:1446-1458`):
```bash
opencode_supports_api() {
  if [[ -z "$OPENCODE_API_SUPPORTED" ]]; then
    if opencode --help 2>/dev/null | grep -q 'opencode api'; then   # ← 문제
      OPENCODE_API_SUPPORTED=1
    else
      OPENCODE_API_SUPPORTED=0
    fi
  fi
  [[ "$OPENCODE_API_SUPPORTED" == "1" ]]
}
```

재현 절차 (읽기 전용):
1. `opencode --help 2>/dev/null | grep -q 'opencode api'; echo $?` → **rc=1** (help의 SUBCOMMANDS 행은
   `api` 단독 토큰으로 출력되어 리터럴 `opencode api`가 없음)
2. `opencode api --help >/dev/null 2>&1; echo $?` → **rc=0** (api는 실제로 지원됨)
3. → `opencode_supports_api`가 **미지원(0)** 판정. `e774b35` 커멘트의 전제("1.18+에서 api 제거")는
   v2.1.4 실측과 반대다. v2.1.4는 api를 지원하며, help 포맷만 바뀌었다.

**틀리는 조건 (일반화):** `opencode --help` 출력에 리터럴 `opencode api`가 포함되지 않는 모든 버전/환경 —
help 포맷 변경, 터미널 폭에 의한 개행, 로케일/텍스트 모드 CRLF(Git-Bash), upstream 서식 변경 전부 오판정을 낸다.
문자열 grep은 계약 자체가 잘못된 것이다.

오판정 연쇄 (실측 확인):
- `bin/herdr-team:1360` `setup_permissions`의 v1_skip 게이트가 발동 → **V2 permissions 시딩 스킵** →
  `tests/test_preset.sh` §38b perm_v2_* 14건 FAIL (실측).
- `bin/herdr-team:1974` 시작 루프에서 폴백 분기 진입 (버그 2로 이어짐).

### 1.3 버그 2 재현: `--agent` 폴백 → TUI 에러 → 시작 대기 hang

현재 폴백 분기(`bin/herdr-team:1976-1984`):
```bash
else
  # 폴백: opencode api 미지원(1.18+)/세션 생성 실패 시 TUI에 역할 에이전트를 직접 지정.
  local -a oa_args=(--agent "$agent")
  ...
  run herdr agent start "$agent" --kind "$KIND" --pane "${PANE_IDS[$i]}" -- "${oa_args[@]}"
fi
```

재현 절차 (실환경):
1. v2.1.4에서 `herdr-team ht --preset dev` 실행 → 1.2의 오판정으로 폴백 분기 진입,
   stderr에 `WARN: opencode session pre-create unavailable ... starting with --agent/--model`.
2. pane에서 실행되는 실제 커맨드는 `opencode --agent ht-planner [--model ...]` 형태.
   **루트 대화형 TUI는 `--agent`를 플래그로 인식하지 않는다**(§1.1 루트 FLAGS 실측) → 즉시 에러로 종료.
3. `herdr agent start`의 성공 판정은 "pane에서 에이전트가 뜨고 입력 가능" 감지인데, 대상 프로세스가
   즉시 죽었으므로 감지 불가 → **`--timeout` 기본값(30000ms)까지 대기 후 실패**. 역할 4개면 수 분 대기.
4. `run()`이 rc를 전파하고 `set -euo pipefail`이므로 타임아웃 실패 시 setup 전체가 중간에 비정상 종료
   (일부 pane만 시작된 깨진 팀 상태).

비고: `--agent`는 `opencode run`/`opencode mini`에는 존재하지만, herdr kind `opencode`가 기동하는
루트 대화형 TUI에는 없다. `opencode mini`로 바꿔 기동하는 방식은 herdr 업스트림의 kind 정의
("canonical executable") 침해이므로 본 명세 범위에서 제외한다.

---

## 2. 수정 계약 (불변식)

- **I1 (플래그 안전)**: 대화형 TUI 기동 시 `opencode --help` 루트 FLAGS에 없는 플래그(현시점 `--agent`,
  `--model`)를 절대 전달하지 않는다. opencode kind의 시작 바인딩은 `-- --session <sid>` **단일 형식**만 허용한다.
- **I2 (판별 방법)**: api 지원 판별은 하드코딩 문자열 grep이 아니라 **실행 + 종료 코드** 기반으로 한다.
  프루브: `opencode api --help >/dev/null 2>&1`. `rc==0` → 지원. 그 외(rc!=0, 명령 부재, 실행 예외) →
  **안전 기본값 = 미지원(0)**.
  - 안전 기본값의 근거: 미지원 판정의 결과는 (a) permissions V2 시딩 스킵 + 경고(기존 사용자 config
    보존 — 파괴 없음), (b) 시작 루프는 어차피 세션 사전생성 자체가 실질 게이트(I3). 즉 오판 방향이
    "보수적 실패"로 수렴한다.
- **I3 (fail-fast)**: 세션 사전생성 실패/파싱 실패 시 폴백 없이 `agent.err.session_abort`로 즉시 중단,
  종료 코드 0 아님. (기존 메시지 키 `agent.err.session_abort` 재사용 — `e31c479` 이전 동작 복원)
- **I4 (타임아웃 + 명시 종료)**: `herdr agent start`에 `--timeout`을 명시 전달하고, 실패 시
  신규 메시지 `agent.err.start_fail` 출력 후 `exit 1`.
- **I5 (테스트 불변식 유지)**: `tests/test_preset.sh` §17(`-- --agent` 미사용 3건 + codex `--agent` 미사용),
  `tests/test_agent_session.sh` 전체 어서션(구분자 `--` 뒤 `--agent` 미사용 포함)은 절대 깨뜨리지 않는다.
  현재 RED인 13+14건은 **녹이는** 방향으로만 변경한다.

프루브 구현 예시(인터페이스, `bin/herdr-team:1446-1458` 교체):
```bash
# opencode api 서브커맨드 지원 판별(1회 캐시). 문자열 grep 금지 — 실행 결과+종료코드 기반(I2).
# 판별 불가/미지원 → 0 (안전 기본값: permissions는 v1_skip 보존, 시작은 세션 사전생성 fail-fast가 실질 게이트).
OPENCODE_API_SUPPORTED=""
opencode_supports_api() {
  if [[ -z "$OPENCODE_API_SUPPORTED" ]]; then
    opencode api --help >/dev/null 2>&1 && OPENCODE_API_SUPPORTED=1 || OPENCODE_API_SUPPORTED=0
  fi
  [[ "$OPENCODE_API_SUPPORTED" == "1" ]]
}
```

시작 루프 교체 예시(`bin/herdr-team:1968-1990` 내 opencode 분기, 폴백 1976-1984 삭제):
```bash
if [[ "$KIND" == "opencode" ]]; then
  if ! sid="$(opencode_session_for "$agent")"; then
    msg agent.err.session_abort "$agent" "${#PANE_IDS[@]}" >&2
    exit 1
  fi
  if ! run herdr agent start "$agent" --kind "$KIND" --timeout "$HT_AGENT_START_TIMEOUT_MS" \
      --pane "${PANE_IDS[$i]}" -- --session "$sid"; then
    msg agent.err.start_fail "$agent" "${PANE_IDS[$i]}" >&2
    exit 1
  fi
else
  run herdr agent start "$agent" --kind "$KIND" --pane "${PANE_IDS[$i]}"
fi
```
- `--timeout`은 `--pane` **앞**에 둔다. `tests/test_preset.sh` §39 어서션이
  `--pane "$P_ORCHESTRATOR" -- --session "$SID_..."` 부분 문자열 매칭이므로 `--pane` 뒤에 끼우면 깨진다.
- dry-run에서 `run()`은 계획 라인만 출력하고 0을 반환하므로 `if ! run ...` 형태도 dry-run 계약을 유지한다.

---

## 3. 역할 에이전트 고정 — 대안 경로 확정

| 후보 | 근거 | 판정 |
|---|---|---|
| **A. 세션 사전생성 후 `--session` 전달** (현행 primary) | v2.1.4 루트 TUI가 `--session, -s` 공식 지원(§1.1 실측). `opencode api post /api/session` 실측 동작. `tests/test_agent_session.sh` a/g/h/i와 `test_preset.sh` §39가 이 경로를 정본으로 단언. 역할↔pane↔session 1:1 결정론 | **채택 (유일 경로)** |
| B. 에이전트 파일 자동 로드 규칙 활용 (`.opencode/agents/*.md`) | 시딩기가 역할 md를 설치하는 것은 사실. 그러나 자동 로드는 "사용 가능한 agent 목록 등록"일 뿐, 모든 pane이 동일 cwd를 공유해 **pane별로 다른 역할을 자동 선택하는 규칙이 없다**. 루트 TUI에 선택용 플래그도 없음(§1.1). 결정론 상실 | 기각 |
| C. 폴백 분기 제거 후 기본 에이전트 기동 | 폴백은 (1) 오판정 게이트에 의존하고 (2) 미지원 플래그를 TUI에 전달해 I1 위반, (3) hang을 유발. `tests/test_agent_session.sh` b/c(세션 실패 시 fail-fast, agent start 미실행)가 애초에 폴백 부정 계약. 제거 시 버그 2 소멸 | **채택 (A와 결합)** |

**확정:** 폴백 분기는 삭제한다(C). opencode kind의 역할 고정은 오직 "세션 사전생성 → `-- --session <sid>`"(A)으로
수행하며, 세션 생성 실패는 fail-fast 중단이다. 역할 고정의 실체는 세션 생성 payload의 `agent` 필드
(`opencode_session_for`, `bin/herdr-team:1460-1486`)이며 이는 무변경 유지한다.

---

## 4. 타임아웃 설계 (herdr agent start 실패 감지)

- 신규 변수: `HT_AGENT_START_TIMEOUT_MS="${HERDR_TEAM_AGENT_START_TIMEOUT_MS:-15000}"` (클램프 상한
  300000 — herdr `--timeout` 최대값). env로 상향 가능, 하향은 상한 내 자유.
- 근거: herdr 기본 30000ms는 폴백 hang 수준의 대기(역할당 30초 × 4역할)를 유발한다. TUI가 정상 기동되면
  수 초 내 readiness 감지되므로 15s는 정상 경로에 충분 (근거: pane ready 프로브 `READY_TIMEOUT_S=20`과
  동일 급의 실험적 기본값, 실측 데이터 없음 — **추측 명시**, PM 승인 대상).
- 실패 경로: `if ! run herdr agent start ...` → `agent.err.start_fail "(%s) agent start failed/timed out (pane %s) - pane left at shell; re-run or start manually" → exit 1`.
  - `run()`의 `run.err.cmd_fail`(원인 커맨드 전문)과 병행 출력(2단 구조: 원인 + 안내).
  - 이전 역할이 이미 시작됐을 수 있으므로 메시지에 pane id를 남겨 수동 복구 가능하게 한다.
  - 세션 실패 중단(`session_abort`)과 동일하게 "panes already created" 맥락은 pane id로 충분 (메시지 1줄 정책).

---

## 5. 기존 테스트 불변식 (유지 대상)

| 위치 | 불변식 |
|---|---|
| `tests/test_preset.sh:207-216` (§17) | dry-run 출력에 `-- --agent` 없음(dev/biz/creator), codex kind에 `--agent` 없음 |
| `tests/test_agent_session.sh:80` | 세션 성공 시 herdr.log에 `-- --agent` 없음 |
| `tests/test_agent_session.sh:88,95` | 세션 실패/파싱 실패 시 agent start 미실행 + fail-fast exit!=0 |
| `tests/test_agent_session.sh:79,109` | `-- --session ses_fake` 바인딩 / dry-run `-- --session` 계획 |
| `tests/test_preset.sh:830-841` (§39) | dry-run `opencode api post /api/session` 계획 + `--pane "$P_X" -- --session "$SID_X"` 정합 (→ `--timeout`은 `--pane` 앞에 삽입) |
| `tests/test_tui_i18n.sh:75-114` | MSG_KEYS ↔ `_msg_en` 키집합/키수 일치 (키 추가/제거는 3곳 동시 변경) |

---

## 6. Windows Git-Bash 호환 고려

- **프루브에 파이프/grep 없음**: `opencode api --help >/dev/null 2>&1` — Git-Bash grep의 CRLF·로케일·
  help 개행(폭 래핑) 문제를 원천 회피. 기존 `opencode --help | grep -q` 제거로 부수 해소.
- **mktemp**: 신규 코드는 임시 파일을 만들지 않는다. 기존 관행 유지 — mktemp 사용 시 템플릿 필수
  (`"${TMPDIR:-/tmp}/ht-cnt.XXXXXX"` 패턴, `bin/herdr-team:516` 참조).
- **jq.exe**: sid 파싱은 기존 `jq_text`(`tr -d '\r'`, `bin/herdr-team:242-243`)만 사용. 신규 코드에서
  `jq` 직접 호출/프로세스 치환 금지 (win-fix에서 확립된 규칙).
- **경로 구분자**: 시작 바인딩 인자(`--session <sid>`, `--timeout <ms>`)에 경로 없음. pane cwd는
  win-fix의 cygpath 변환(`CWD_HERDR`) 유지.
- **종료 코드 전파**: Git-Bash에서 opencode가 `.cmd` 셈으로 설치된 경우 rc 전파가 셈에 의존한다는
  잔여 리스크가 있으나, I2의 안전 기본값(보수적 미지원) + I3 세션 fail-fast가 실질 게이트라 잘못된
  시작으로 이어지지 않는다.

---

## 7. Task Breakdown (TDD 순서, ht-worker용)

공통: 각 태스크 종료 시 T2 = `bash scripts/testmap.sh`가 매핑한 스위트 실행
(`bin/herdr-team` 변경 → testmap 9 스위트; 본 태스크에서 의미 있는 최소 집합은
`tests/test_agent_session.sh tests/test_preset.sh tests/test_pane_ready.sh tests/test_permissions_seed.sh`).
고지 형식: `[T2 scoped] bash tests/test_agent_session.sh && bash tests/test_preset.sh → N passed in T s`.

### TB-1 — api 지원 판별을 rc 기반으로 재정의 (버그 1)
- **RED**: `tests/test_agent_session.sh`에 신규 케이스 j) — stub `opencode`가 `--help` 호출에 rc=0으로
  응답하되 출력에 `opencode api` 리터럴 없음(v2.1.4 재현), `api post /api/session` 호출엔
  `{"data":{"id":"ses_fake"}}` 반환. 기대: herdr.log에 `-- --session ses_fake` 존재, `-- --agent` 부재,
  opencode.log 내 `--help` 프루브 호출 **1회**(캐시 확인). (기존 case a가 동일 성격의 RED — 현재 FAIL)
- **구현**: `bin/herdr-team:1446-1458` → §2 예시로 교체. 주석 전제("1.18+ api 제거")를 실측 사실로 수정.
- **T2**: `bash tests/test_agent_session.sh` (case a/j GREEN) + `bash tests/test_preset.sh`
  (§38b perm_v2 14건 GREEN — 게이트가 오판정하지 않으므로 시딩 정상화).

### TB-2 — 시작 루프 폴백 제거 + fail-fast 복원 (버그 2)
- **RED**: `tests/test_agent_session.sh` case b/c에 추가 단언 — 세션 실패 모드에서 herdr.log에
  `--agent`와 `--model`이 **절대 없음**(현재 RED: 폴백이 agent start 실행).
- **구현**: `bin/herdr-team:1968-1990`에서 1976-1984 폴백 분기 삭제, §2 예시의 세션 실패
  `session_abort` + exit 1 복원(`e31c479:1785-1792` 패턴). `need_cmd opencode`(1965) 유지.
- **T2**: `bash tests/test_agent_session.sh` (b/c GREEN, 총 27 PASS) + `bash tests/test_preset.sh` §17/§39.

### TB-3 — `--timeout` 주입 + 시작 실패 명시 종료 (요구 4)
- **RED**: 신규 케이스 k) — stub `herdr agent start`가 rc=1 반환 시 (i) bin 종료 코드 != 0,
  (ii) stderr에 `agent start failed/timed out` 포함, (iii) herdr.log에 `--timeout 15000 --pane` 부분
  문자열 존재(`--pane` 앞 배치 검증).
- **구현**: `HT_AGENT_START_TIMEOUT_MS` 정의(클램포트: `[[ $HT_AGENT_START_TIMEOUT_MS -gt 300000 ]] && HT_AGENT_START_TIMEOUT_MS=300000`) +
  시작 호출에 `--timeout "$HT_AGENT_START_TIMEOUT_MS"` (`--pane` 앞) + `if ! run ...` → `agent.err.start_fail` + exit 1.
- **T2**: `bash tests/test_agent_session.sh && bash tests/test_preset.sh`.

### TB-4 — permissions 게이트 프루브 실행 조건 정비
- **RED**: 기존 case d(`--no-start` 시 opencode 미호출)/e(`--dry-run` 시 opencode 미호출)가 현재 RED —
  `bin/herdr-team:1360` 게이트가 `--no-start`/`--dry-run`에서도 `opencode --help` 프루브를 실행하기 때문.
- **구현**: `bin/herdr-team:1360` 조건을
  `if [[ "$KIND" == "opencode" && "$DRY_RUN" -eq 0 && "$NO_START" -eq 0 ]] && ! opencode_supports_api` 로 변경.
  - 효과: `test_permissions_seed.sh`류의 `--no-start` 실행이 실환경 opencode 설치 유무와 무관하게
    결정론화(§38b도 여기에 종속되지 않음). 부작용: `--no-start` 실행 시 V1 판별 스킵 → V2 시딩 진행.
    `shortcut: --no-start 에서는 V1 판별 생략(V2 시딩), V1 사용자가 --no-start 로 config 만들 때 문제 — 실시작 런에서 재시딩 또는 수동 점검으로 회수`.
- **T2**: `bash tests/test_agent_session.sh && bash tests/test_permissions_seed.sh && bash tests/test_preset.sh`.

### TB-5 — 메시지 키 정리 (I4 메시지)
- **RED**: `bin/herdr-team:76` MSG_KEYS에 `agent.err.start_fail` 추가 + `agent.warn.session_fallback` 제거 →
  `bash tests/test_tui_i18n.sh` tc1 키집합 불일치로 FAIL 확인.
- **구현**: `_msg_en`(141 부근)에 `agent.err.start_fail` 항목 추가, `agent.warn.session_fallback` 항목 제거.
  MSG_KEYS/`_msg_en` 동시 반영 → GREEN. (ko 카탈로그는 존재하지 않음 — en 단일 카탈로그, `bin/herdr-team:77-80`)
- **T2**: `bash tests/test_tui_i18n.sh`.

### TB-6 — 최종 회귀 (T3, push 직전 / reviewer 실행)
- `bash scripts/testmap.sh` 전체 스위트 실행 + `bash tests/test_preset.sh` (기대 461 PASS) +
  `bash tests/test_agent_session.sh` (기대 27 PASS). worker의 임의 T3 실행 금지 — 지시 시에만.

---

## 8. 엣지 케이스

1. **opencode 미설치 + 시작 모드**: permissions 단계(시작 루프보다 선행)에서 프루브 rc!=0 → v1_skip 경고 +
   시딩 스킵, 이후 `need_cmd opencode`(1965)에서 exit 127로 명확히 죽는다. 동작 수용 (경고 → 명확한 실패).
2. **opencode 백그라운드 서비스 미기동**: `opencode api post` 실패 → `session_fail` 원인 메시지 +
   `session_abort` fail-fast. 기존 메시지("check opencode install/background service")가 안내 담당.
3. **V1(1.x) 잔여 리스크**: yargs 계열은 미지원 서브커맨드에서 rc=0 + help 출력 가능(구 코드 주석의 전제).
   rc 기반 프루브도 이 경우 오판(지원)할 수 있으나, 시작 경로는 세션 생성 실패로 fail-fast되므로
   잘못된 시작 없음. permissions만 V2 시딩 시도 후 V1 거부 가능 — 알려된 잔여 리스크로 문서화, V1
   지원이 필요해지면 별도 명세.
4. **동시 setup 실행 / 캐시**: `OPENCODE_API_SUPPORTED`는 프로세스 로컬 캐시 — 기존과 동일, 무변경.
5. **`opencode run/mini`의 `--agent`**: 존재하지만 herdr kind `opencode`의 canonical 실행은 루트 TUI라
   사용 불가(§1.3 비고). kind 정의 변경은 범위 외.

## 9. 열린 질문 (PM 확인 대상)

1. herdr 업스트림이 "TUI 즉시 종료"를 readiness 실패로 즉시 반환할 수 있는지 — 가능하면
   `--timeout 15000`은 임시 완화에 불과하고 상향 조정 여지가 있음 (추측, herdr 소스 확인 필요).
2. `HT_AGENT_START_TIMEOUT_MS` 기본값 15000ms 승인 여부 (근거 데이터 없음 — 실측 후 조정 권장).
3. opencode V1(1.x) 사용자에 대한 공식 지원 방침 (본 명세는 V2 전제 + fail-fast 안내).
