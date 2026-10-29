#!/usr/bin/env bash
# tests/test_pane_ready.sh — agent_pane_busy(shell 미준비 race) 결정론 해소 검증
# 대상: bin/herdr-team의 wait_pane_ready() + start 루프 배선 + run() 무음 소실 제거
# 실행: bash tests/test_pane_ready.sh  (repo root에서)
#
# [R1 재현 근거 — live herdr 세션 실측, 2026-10-19, herdr 0.9.3]
#   - foreground 점유 pane(pane run sleep 15)에서 `herdr agent start` → 즉시 실패 (결정론 재현):
#     rc=1, {"error":{"code":"agent_pane_busy","message":"agent target pane w1Q:pX is not an available shell"}}
#   - process-info 스키마(실측): {foreground_processes[0].{name,pid}, shell_pid, foreground_process_group_id}
#     foreground pid != shell_pid(sleep) / == shell_pid(zsh, 분할 후 ms 단위에서 이미 확인됨)
#   - pane run: 즉시 반환(~4ms), rc=0, 명령은 pty 입력으로 큐잉/타이핑 에코 발생
#   - pane wait-output: 즉시 검색 후 폴링, --timeout 폐쇄, 정규식 지원, 기본 source=recent-unwrapped
#   - 오탐 발견: --match(리터럴)는 busy pane에서 타이핑 에코 라인("printf __HT_READY_MARKER2__")을
#     매치 → 명세 §3의 리터럴 매치 프로브는 false positive → 라인 시작 앵커 정규식으로 구현 (diff 사유)
#   - `$` 앵커 불안정(실측): 스냅샷 라인 공백 패딩 + 마커 뒤 프롬프트 평탄화(`__M__%<pad>/opencode ❯`)
#     를 같은 라인에 병합 → 라인 시작 앵커만으로 판정
#   - process-info gate(실측): foreground_process_group_id==shell_pid ⇔ ready(zsh), 불일치 ⇔ busy(sleep)
#   - R1 자연 race 재현 시도 15회(분할 직후 무간격 agent start): busy_hits=0/15
#     (본 환경 zsh 부팅이 ms 단위라 미발생 — busy-path는 foreground 점유로 결정론 재현됨)
#   - R2 라이브 검증(wait_pane_ready 삽입 전제): 분할 직후 → wait_pane_ready 20/20 PASS(avg 23ms) →
#     이어서 `herdr agent start` 성공(agent list 등록 확인) — 결정론 배선 실증
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

assert_contains() { if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
assert_equal()    { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 ($1 != $2)"; fi; }
assert_exit()     { if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi; }

# binary 대상 함수 추출: 유틸(log) + 대상 함수(run/run_team용 wait_pane_ready)
extract_fn() { sed -n "/^$1() {/,/^}/p" "$BIN" | head -40; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq 없음 → pane ready 검증 생략"
  printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
  exit 0
fi

FN_SRC="$(mktemp)"
trap 'rm -f "$FN_SRC"' EXIT
{
  extract_fn log
  extract_fn run
  extract_fn pane_shell_foreground
  extract_fn wait_pane_ready
  # 에러 문구는 i18n 카탈로그(msg/_msg_en)에서 온다 — 추출 하네스에도 함께 싣는다
  sed -n '/^msg() {/,/^}/p' "$BIN"
  sed -n '/^_msg_en() {/,/^}/p' "$BIN"
} > "$FN_SRC"
if [[ -s "$FN_SRC" ]]; then ok "help_fn_추출: wait_pane_ready 정의 존재"; else bad "help_fn_추출: wait_pane_ready 정의 존재"; fi

# wait_pane_ready 전용 stub herdr:
#   - HT_READY_CALLS 파일의 pane run 누적 호출수를 세고,
#   - HT_READY_THRESHOLD 도달 전까지 wait-output을 timeout(rc=1)으로 응답 (미성숙 shell 시뮬레이션)
make_stub() { # $1=STUBDIR
  mkdir -p "$1"
  cat > "$1/herdr" <<'STUBEOF'
#!/usr/bin/env bash
LOG_DIR="${HT_READY_LOG_DIR:?}"
case "${1:-}" in
  pane)
    case "${2:-}" in
      run)  n="$(( $(cat "$LOG_DIR/calls" 2>/dev/null || printf 0) + 1 ))"; printf '%s' "$n" > "$LOG_DIR/calls"; exit 0 ;;
      wait-output)
        n="$(cat "$LOG_DIR/calls" 2>/dev/null || printf 0)"
        if [[ "$n" -ge "${HT_READY_THRESHOLD:-1}" ]]; then
          printf '{"result":{"matched_line":"__HT_READY_MARKER__"}}\n'; exit 0
        fi
        printf '{"error":{"code":"timeout"}}\n'; exit 1 ;;
      process-info)
        if [[ "${HT_READY_GATE:-1}" == "1" ]]; then
          printf '{"result":{"process_info":{"shell_pid":42,"foreground_process_group_id":42,"foreground_processes":[{"name":"zsh","pid":42}]}}}\n'
        else
          printf '{"result":{"process_info":{"shell_pid":42,"foreground_process_group_id":99,"foreground_processes":[{"name":"sleep","pid":99}]}}}\n'
        fi ;;
      *)    printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n' ;;
    esac ;;
  agent)
    case "${2:-}" in
      list) exit 1 ;;
      start) printf '%s\n' "$*" >> "${HT_START_LOG:?}" ;;
    esac ;;
esac
exit 0
STUBEOF
  chmod +x "$1/herdr"
}

BASE_STUB="$(mktemp -d)"; make_stub "$BASE_STUB"
ready_run() { # $1=threshold $2=S_dir $3=pseudo pane $4=timeout_s [$5=HT_READY_GATE]
  PATH="$BASE_STUB:$PATH" HT_READY_THRESHOLD="$1" HT_READY_LOG_DIR="$2/log" \
    HERDR_TEAM_READY_TIMEOUT_S="$4" HT_READY_GATE="${5:-1}" \
    bash -c 'source "$1"; wait_pane_ready "$2"' _ "$FN_SRC" "$3" 2>&1
}
make_stub_opencode() { # $1=STUBDIR (세션 생성 stub)
  cat > "$1/opencode" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"data":{"id":"ses_fake"}}\n'
exit 0
STUBEOF
  chmod +x "$1/opencode"
}

echo "== R-recovery) 미준비 shell에서 프로브 반복 → 준비 즉시 성공 (재시도 폐쇄 변형) =="
S1="$(mktemp -d)"; mkdir -p "$S1/log"; printf 0 > "$S1/log/calls"
OUT="$(ready_run 1 "$S1" wT:pX 20)"; R="$?"
assert_exit "$R" 0 "ready_미준비후_회복: rc=0"
assert_equal "$(cat "$S1/log/calls")" "1" "ready_프로브_1회성공"

echo "== R-bounded) 준비 지연(N회 후) → 재시도 후 성공 =="
S2="$(mktemp -d)"; mkdir -p "$S2/log"; printf 0 > "$S2/log/calls"
OUT="$(ready_run 3 "$S2" wT:pY 20)"; R="$?"
assert_exit "$R" 0 "ready_지연_회복: rc=0"
assert_equal "$(cat "$S2/log/calls")" "3" "ready_지연_회복: 프로브 3회(조건 충족 직전까지)"

echo "== R3 폐쇄-a) 영구 busy(foreground 점유) → 명시적 실패로 종료(무한 대기 없음) =="
S3="$(mktemp -d)"; mkdir -p "$S3/log"; printf 0 > "$S3/log/calls"
T0=$(date +%s)
OUT="$(ready_run 999 "$S3" wT:pZ 2 0)"; R="$?"
assert_exit "$R" 1 "ready_폐쇄-a: 영구 busy rc=1"
assert_contains "$OUT" "ready wait exceeded" "ready_폐쇄-a: 원인 명시 에러"
T1=$(date +%s)
ELAPSED=$((T1-T0))
if [[ "$ELAPSED" -lt 12 ]]; then ok "ready_폐쇄-a: 폐쇄(${ELAPSED}s < 12s)"; else bad "ready_폐쇄-a: 폐쇄($ELAPSED s)"; fi

echo "== R3 폐쇄-b) gate 통과·프로브 미매칭 지속 → 명시적 실패로 종료 =="
S3b="$(mktemp -d)"; mkdir -p "$S3b/log"; printf 0 > "$S3b/log/calls"
OUT="$(ready_run 999 "$S3b" wT:pZ 2 1)"; R="$?"
assert_exit "$R" 1 "ready_폐쇄-b: 영구 미매칭 rc=1"
assert_contains "$OUT" "ready wait exceeded" "ready_폐쇄-b: 원인 명시 에러"
rm -rf "$S1" "$S2" "$S3" "$S3b"

echo "== run() 개선: 실패 시 무음 소실 제거 =="
RUN_OUT="$(DRY_RUN=0 bash -c 'source "$1"; run bash -c "echo ERRMSG >&2; exit 5"' _ "$FN_SRC" 2>&1)"; R="$?"
assert_exit "$R" 5 "run_개선: 종료코드 전파"
assert_contains "$RUN_OUT" "command failed" "run_개선: 실패 명시 에러"
assert_contains "$RUN_OUT" "ERRMSG" "run_개선: subcommand stderr 보존"

echo "== R4 dry-run 배선: start 직전 wait_pane_ready 계획 출력 =="
DRY_A="$("$BIN" dryfix --preset dev --dry-run --no-interactive 2>&1)"
assert_contains "$DRY_A" 'wait_pane_ready "$P_ORCHESTRATOR"' "dryrun_ready_line: orchestrator"
assert_contains "$DRY_A" 'wait_pane_ready' "dryrun_ready_line: 존재(kernel)"
N_READY="$(printf '%s\n' "$DRY_A" | grep -c 'wait_pane_ready')"
N_START="$(printf '%s\n' "$DRY_A" | grep -c 'herdr agent start')"
if [[ "$N_READY" -eq "$N_START" && "$N_START" -gt 0 ]]; then ok "dryrun_ready_line: start 수와 동일(${N_START})"; else bad "dryrun_ready_line: start(${N_START}) vs ready(${N_READY})"; fi
# start 라인이 wait_pane_ready 라인 "직후"에 오는지(배선 순서) — line index 비교
I_READY="$(printf '%s\n' "$DRY_A" | grep -nF 'wait_pane_ready "$P_ORCHESTRATOR"' | head -n1 | cut -d: -f1)"
I_START="$(printf '%s\n' "$DRY_A" | grep -nF 'herdr agent start dryfix-orchestrator' | head -n1 | cut -d: -f1)"
if [[ -n "$I_READY" && -n "$I_START" && "$I_READY" -lt "$I_START" ]]; then ok "dryrun_ready_order: ready-before-start"; else bad "dryrun_ready_order: ready-before-start (ready=$I_READY start=$I_START)"; fi
# non-opencode kind 분기도 동일 배선
DRY_B="$("$BIN" dryfix --preset dev --dry-run --kind codex --no-interactive 2>&1)"
assert_contains "$DRY_B" 'wait_pane_ready' "dryrun_kind_gate: codex 분기도 ready 배선"

echo "== R 분할→시작 통과 배선(E2E stub): 각 start 직전에 1회 wait-output 대기 =="
STUB="$(mktemp -d)"; make_stub "$STUB"; make_stub_opencode "$STUB"
TCWD="$(mktemp -d)"; DLOG="$(mktemp -d)"; mkdir -p "$DLOG/log"; printf 0 > "$DLOG/log/calls"
HT_READY_THRESHOLD=1 HT_READY_LOG_DIR="$DLOG/log" HT_START_LOG="$DLOG/start.log" \
  PATH="$STUB:$PATH" "$BIN" e2e --preset dev --cwd "$TCWD" --template-dir "$REPO/templates" --no-interactive >/dev/null 2>&1
RC=$?
assert_exit "$RC" 0 "e2e_ready: 실행 exit 0"
N_START_LOG="$(wc -l < "$DLOG/start.log" 2>/dev/null)"
N_WO_LOG="$(cat "$DLOG/log/calls")"
if [[ "${N_START_LOG:-0}" -gt 0 && "$N_WO_LOG" -eq "$N_START_LOG" ]]; then ok "e2e_ready: start ${N_START_LOG}회 = 대기 ${N_WO_LOG}회"; else bad "e2e_ready: start(${N_START_LOG}) vs 대기(${N_WO_LOG})"; fi
rm -rf "$STUB" "$TCWD" "$DLOG"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
