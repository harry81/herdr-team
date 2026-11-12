# pane-ready 재시도 로직 테스트 결정적 실패 분석·해결 명세 (fix/tui-i18n-ci-env)

- 분석 트리: `fix/tui-i18n-ci-env` @ `55827a6` (PR #2, "ci-fix: TUI i18n 스위트의 CI 환경 의존 10건 해소")
- 대상: `tests/test_pane_ready.sh` (수정 주체) + `bin/herdr-team` `wait_pane_ready` 계약 문서화 (제품 코드
  수정 **불필요** — §4 판정)
- 작성자: ht-planner (문서 전용; 진단용 읽기 전용 실행만 수행)

---

## 0. 요약

4건 실패는 **환경 flake가 아니라 테스트 하니스 드리프트**다. 커밋 `e774b35`(win-fix)가 제품
`pane_shell_foreground`의 jq 호출을 `jq -r` → `jq_text`(CRLF 방어 래퍼, bin:252)로 교체했는데
`tests/test_pane_ready.sh`의 함수 추출 하니스(44-54행)가 `jq_text`를 함께 싣지 않아,
추출 환경에서 `jq_text: command not found` → `pane_shell_foreground`가 **항상 실패** → R-recovery/
R-bounded가 게이트 루프에서 타임아웃까지 회전 → rc=1 + `calls=0`. **로컬에서 3회 연속 동일
(PASS=16 FAIL=4, ~44s)** — 결정적 실패 확인.

보너스 발견: 현재 44s 소요의 정체 = R-recovery(20s) + R-bounded(20s) + 폐쇄-a(2s) + 폐쇄-b(2s) = 44s —
정상이면 즉시 성공해야 할 recovery 케이스 2개가 타임아웃 전액을 태우고 있다. 수정 시 스위트는 ~5s로 단축된다.

## 1. 실패 단언 분석 (tests/test_pane_ready.sh)

| 단언 | 행 | 구성 |
|---|---|---|
| `ready_미준비후_회복: rc=0` (FAIL: exit=1) | 112 | `ready_run 1 "$S1" wT:pX 20` (95-99행 헬퍼: stub-PATH + 임계값/게이트/타임아웃 주입, `bash -c 'source FN; wait_pane_ready pane'`) |
| `ready_프로브_1회성공` (FAIL: 0 != 1) | 113 | stub `pane run` 호출 카운터 파일(`$S1/log/calls`, stub 62-92행의 `run` 분기) |
| `ready_지연_회복: rc=0` (FAIL: exit=1) | 118 | `ready_run 3 "$S2" wT:pY 20` — 3번째 프로브에서 성공 시나리오 |
| `ready_지연_회복: 프로브 3회` (FAIL: 0 != 3) | 119 | 같은 카운터 — 최초 2회 wait-output timeout, 3회째 매칭 기대 |

스텁 계약(62-92행): `pane run` → calls++ 후 rc=0 / `pane wait-output` → calls ≥ HT_READY_THRESHOLD면
`matched_line` JSON rc=0, 아니면 `{"error":{"code":"timeout"}}` rc=1 / `pane process-info` →
HT_READY_GATE=1이면 shell ready(pid 일치), 0이면 busy(pid 불일치).
관련 나머지 블록: 폐쇄-a(121-129), 폐쇄-b(131-135), run() 개선(138-142), R4 dry-run 배선(144-157),
E2E(159-169 — 실제 `$BIN`을 쓰므로 현재도 PASS).

## 2. 대상 제품 코드 (bin/herdr-team, 현재 라인)

- `jq_text()` 252: `jq -r "$@" | tr -d '\r'` — Windows 네이티브 jq.exe CRLF 방어 (e774b35 도입).
- `READY_TIMEOUT_S` 1198: 기본 20s (`HERDR_TEAM_READY_TIMEOUT_S` override).
- `HT_READY_MARKER` 1199: `__HT_READY_MARKER__`.
- `pane_shell_foreground()` 1200-1206: `herdr pane process-info` → `jq_text`로 `shell_pid`/`foreground_process_group_id` 추출(1203-1204) → 일치 ⇔ shell ready. **이 jq_text가 하니스에 없음(§3).**
- `wait_pane_ready()` 1207-1234:
  1. **게이트 루프** 1209-1219: `until pane_shell_foreground` — 실패 시 시간 체크(1210-1214, 초과 시
     `pane.err.ready_timeout` + `pane.err.foreground` + return 1) → `_n++` 로그 → 페이싱
     (`wait-output --match "${HT_READY_MARKER}:no-op" --timeout 500`, 1218 — 매칭 불가 패턴으로 0.5s 대기).
  2. **프로브 루프** 1224-1233: `pane run echo $MARKER && pane wait-output --regex "(?m)^[ \t]*MARKER" --timeout 1500` —
     실패 시 동일 시간 체크(1226-1230) → 로그 → 재시도. 프로브는 Windows pane 기본 셸(PowerShell) 호환 위해 `echo` 사용.

## 3. 재현 (로컬 실측, 결정적)

```
$ bash tests/test_pane_ready.sh
FAIL: ready_미준비후_회복: rc=0 (exit=1, want=0)
FAIL: ready_프로브_1회성공 (0 != 1)
FAIL: ready_지연_회복: rc=0 (exit=1, want=0)
FAIL: ready_지연_회복: 프로브 3회(조건 충족 직전까지) (0 != 3)
RESULT: PASS=16 FAIL=4
44.04s total (21.39s user)
```
- 3회 연속 실행: `PASS=16 FAIL=4` ×3 동일 — **결정적** (CI와 동일 수치).
- 하니스 환경 직접 검증: 테스트와 동일 추출(35-54행 로직)로 FN_SRC를 만들어
  `type -t jq_text` → **공백(미정의)**, `jq_text .x` → `bash: jq_text: command not found`,
  `pane_shell_foreground wT:pX` → **rc=1**(게이트가 항상 실패).
- 소요시간 산술 검증: 20(R-recovery)+20(R-bounded)+2(폐쇄-a)+2(폐쇄-b) ≈ 44.04s — recovery 2개가
  20s 타임아웃 전액 소진(정상이면 ms 단위).

## 4. 근본 원인 판정: 테스트 드리프트 (제품 버그 아님)

**git 증거** (`git log -L 1200,1206:bin/herdr-team`):
- `cc83b83` (pane-ready 결정론 도입): `pane_shell_foreground` 신설, 당시 `jq -r` 직접 호출 —
  하니스에 `jq`만 필요 → 테스트 GREEN.
- `e774b35` (win-fix): 같은 함수의 jq 호출을 `jq_text`로 교체 — **tests/test_pane_ready.sh 무변경**.
  추출 하니스(46-54행: log/run/pane_shell_foreground/wait_pane_ready/msg/_msg_en)에 `jq_text` 누락.
- 이후 모든 라운드에서 4건 지속 (기존 실패로 분류·방치된 경위와 일치).

**제품이 정상임의 근거**: E2E 케이스(159-169행)는 실제 `$BIN`(jq_text 포함)을 구동 →
`start 4회 = 대기 4회` PASS — 실제 배선에서 `wait_pane_ready`가 정상 동작한다.
(제품 버그 여지 점검도 완료: 스텁 JSON 형태/필드명 불일치·카운터 초기화·조기 종료 후보는 전부
§3의 "jq_text 미정의" 단일 사실로 소명 — 스텁은 `process_info` 스키마를 제품 기대대로 준다.)

**부수 결함(같은 드리프트의 2차 증상)**: 폐쇄-b(131-135)는 "게이트 통과 후 프로브 미매칭"을 검증하려
했으나 현재는 게이트 루프에서 타임아웃되어 **프로브 루프를 한 번도 실행하지 않는다** — 즉 vacuous green.
`calls` 단언이 없어 드리프트를 잡지 못했다.

## 5. 회복 로직 계약 (명문화 — 테스트 단언의 기준)

1. **미준비 → 회복**: 게이트 실패는 페이싱(0.5s 내장 폴링) 후 재평가하며, 게이트 통과 직후 첫 프로브
   (pane run 1회 + wait-output 1회)가 성공하면 즉시 rc=0. stub 임계값 T=1 → **pane run 호출 1회**.
2. **지연 회복**: wait-output 미매칭은 프로브 루프 반복 — stub T=3 → run 3회 후 매칭 → **calls==3,
   rc=0**. 프로브 루프의 실패 대기는 wait-output `--timeout 1500` 내장 폴링.
3. **최대 재시도 = 시간 기반**: `SECONDS - _start < HERDR_TEAM_READY_TIMEOUT_S`(기본 20s) — 호출 횟수
   기반 상한은 없음(문서화). 초과 시 `pane.err.ready_timeout` + `pane.err.foreground` + return 1
   (무한 대기 없음).
4. **경로 분리**: 폐쇄-a(게이트 영구 실패) → **프로브 미실행**(calls==0). 폐쇄-b(게이트 통과·프로브
   미매칭) → **프로브 루프 진입**(calls>0) 후 타임아웃 rc=1. 둘의 구분이 단언되어야 vacuous green 방지.
5. **결정론**: stub은 카운터 파일 기반으로 시간 의존 0 — 유일한 시간 요소는 제품 내부 페이싱(0.5s/1.5s)
   이며 폐쇄 케이스는 `HERDR_TEAM_READY_TIMEOUT_S=2`로 상한 봉인.

## 6. 해결 설계 (테스트 전용)

1. **하니스에 `jq_text` 추출 추가** (`tests/test_pane_ready.sh:46-54` 블록) — 근본 수정.
2. **vacuous-green 방지 단언**: 폐쇄-a에 `calls == 0`, 폐쇄-b에 `calls > 0` 단언 추가 (121-135행) —
   게이트 루프/프로브 루프 경로 분리를 봉인. (현재 상태에서 폐쇄-b의 calls>0 단언은 FAIL → 진짜 RED)
3. **런타임 단축**: TB-1만으로 recovery 2개가 즉시 복귀 → 스위트 ~44s → **~5s**(폐쇄 2+2s + 나머지).
   추가 여지(선택): 폐쇄 타임아웃 `ready_run ... 2` → 1(SECONDS 정수 그레인상 1회 이상 반복 보장,
   ~3s 총) — 단, 하한은 `HERDR_TEAM_READY_TIMEOUT_S=1`이 최소(0은 즉시 타임아웃)로 문서화.
   스위트 상한 목표: **≤ 15s**(회귀 감지용 기준선, 이후 스위트가 이를 초과하면 시간 의존 재점검 트리거).
4. **flake 재발 방지 절차**: 수정 후 `for i in 1 2 3; do bash tests/test_pane_ready.sh; done` →
   3회 모두 `PASS=N FAIL=0` 동일 + 요약행 동일. CI(ci.yml의 pane ready step)는 push마다 실행되므로
   재발 시 CI와 로컬이 동시에 붉어진다(본 건은 로컬도 붉었으므로 조기 탐지됨).
5. **제품 코드 수정: 없음.** 계약(§5)은 현 구현이 이미 충족 — 테스트가 그 계약을 검증하지 못하게 된
   것이 전부.

## 7. 테스트 티어 규율

- **T1 Fast-Loop**(편집 루프마다): `bash tests/test_pane_ready.sh` (수정 후 ~5s — 5초 이내 목표와 정합).
- **T2 Scoped Regression**(태스크 완료 시 1회): `bash scripts/testmap.sh` 매핑 — 본 태스크 변경 파일이
  `tests/test_pane_ready.sh`뿐이므로 `bash tests/test_pane_ready.sh`; e2e stub 계약을 공유하는
  `tests/test_agent_session.sh`를 인접 스위트로 함께 실행. 고지: `[T2 scoped] <command> → N passed in T s`.
- **T3 Full Regression**: push 직전, reviewer 노드 전용(worker 임의 실행 금지) — ci.yml 전체 step.
  PR #2 머지 전 reviewer가 T3로 본 스위트 재확인.

## 8. Task Breakdown (TDD 순서, ht-worker용)

### TB-1 — 경로 분리 단언 추가 (RED)  `tests/test_pane_ready.sh:121-135`
- **RED**: 폐쇄-a에 `assert_equal "$(cat "$S3/log/calls")" "0" "폐쇄-a: 게이트 루프만(프로브 0회)"`,
  폐쇄-b에 `if [[ "$(cat "$S3b/log/calls")" -gt 0 ]]; then ok "폐쇄-b: 프로브 루프 진입"; else bad ...; fi`
  추가 → 현재 상태에서 **폐쇄-b 단언 FAIL**(calls=0, vacuous green 노출) 확인. 폐쇄-a는 PASS(0 유지).
- **T2**: `bash tests/test_pane_ready.sh` (기존 16/4 + 신규 RED 1 → FAIL=5 상태 기록).

### TB-2 — jq_text 추출 추가 (GREEN, 근본 수정)  `tests/test_pane_ready.sh:46-54`
- **구현**: 추출 블록에 `extract_fn jq_text` 1행 추가. (`jq_text()`는 bin:252 단일 라인 — sed 범위
  `/^jq_text() {/,/^}/p`는 한 줄 함수라 닫는 `^}`가 없어 끝까지 읽는 문제가 있으므로
  `extract_fn() { sed -n "/^$1() {/,/^}/p" "$BIN" | head -40; }`의 범위 한계를 우회해
  `sed -n '/^jq_text() {/p' "$BIN"` 단일 행 추출로 넣는다.)
- **GREEN**: 스위트 전체 FAIL=0, R-recovery rc=0+calls=1, R-bounded rc=0+calls=3, 폐쇄-b calls>0 GREEN.
- **런타임 검증**: `time bash tests/test_pane_ready.sh` → **≤ 15s**(예상 ~5s; 44s 대비).
- **T2**: `bash tests/test_pane_ready.sh && bash tests/test_agent_session.sh`.

### TB-3 — (선택) 폐쇄 케이스 타임아웃 단축  `tests/test_pane_ready.sh:124,133`
- **RED/구현**: `ready_run ... 2` → `1` (2곳) — 폐쇄-a/b 각 ~1s. 판정: 하한 계약(§5-3)상
  `HERDR_TEAM_READY_TIMEOUT_S=1`에서도 ≥1회 반복 후 타임아웃이 보장되는지 확인(SECONDS 정수 그레인:
  진입 시 0s, 페이싱 0.5s 후 1s 시점에 타임아웃 — 결정론). 애매하면 2s 유지(현재 스위트 ~5s로
  이미 상한 내라 이 태스크는 optional).
- **T2**: `bash tests/test_pane_ready.sh`.

### TB-4 — flake 재발 방지 절차 수행 (검증 단계)
- 3회 반복: `for i in 1 2 3; do bash tests/test_pane_ready.sh; done` → 3회 모두 `PASS=N FAIL=0` 동일
  (본 진단에서 3회 연속 `PASS=16 FAIL=4` 동일 확인 절차와 동일 방식). 결과를 커밋 메시지/PR 본문에 고지.
- **T3**: push 직전 reviewer 노드 — `bash scripts/testmap.sh` 전체 + PR #2 CI green 확인.

## 9. 엣지 케이스 / 유의점

1. `extract_fn log`: `log()`가 한 줄 함수(`log() { printf ...; }`)라 sed 범위가 닫히지 않아 다음
   `^}`까지 + head -40 캡으로 잡동사니를 포함한다(현행 FN_SRC는 문법적으로 유효해 소스 가능 — 실측).
   `shortcut: 한 줄 함수는 단일 행 추출로 교체 가능, 하니스가 깨질 때 재검토`.
2. 폐쇄-b의 calls 단언은 stub이 `pane run`마다 카운트하므로 ≥1만으로 안전(정확 횟수는 타이밍 의존 —
   미매칭 루프 반복 횟수는 페이싱에 좌우되므로 `> 0`만 단언).
3. recovery 케이스는 수정 후 수 ms 만에 끝나므로 `ELAPSED` 상한 단언(기존 폐쇄-a의 <12s 스타일)을
   추가할 필요 없음 — rc/calls 단언으로 충분.
4. PR #2는 TUI i18n CI 수정 브랜치 — 본 명세의 수정은 **별도 커밋**으로 올려 스코프를 분리 권장.
