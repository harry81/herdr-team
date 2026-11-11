#!/usr/bin/env bash
# tests/test_agent_session.sh — opencode 세션 사전생성 + `-- --session` 바인딩 / fail-fast 검증
# 실행: bash tests/test_agent_session.sh  (repo root에서)
# fake herdr/opencode 셤으로 세션 생성 실패 경로를 결정적으로 재현한다.
# 로케일 고정(en) — 로케일 커버리지는 tests/test_tui_i18n.sh 담당.
export HERDR_TEAM_LANG=en
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

assert_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi
}
assert_not_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq 없음 → opencode 세션 바인딩 테스트 생략"
  printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
  exit 0
fi

STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT

cat > "$STUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
case "${1:-}" in
  pane)
    case "${2:-}" in
      run|wait-output) printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n' ;;  # probe/페이싱: ready로 응답
      process-info) printf '{"result":{"process_info":{"shell_pid":42,"foreground_process_group_id":42}}}\n' ;;
      *) printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n' ;;
    esac ;;
  agent)
    case "${2:-}" in
      list) exit 1 ;;  # 에이전트 없음 → start 진행
      start) printf '%s\n' "$*" >> "${HERDR_START_LOG:?}"; exit "${HERDR_START_RC:-0}" ;;
    esac ;;
esac
exit 0
STUBEOF
chmod +x "$STUB/herdr"

cat > "$STUB/opencode" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${OPENCODE_CALL_LOG:?}"
case "${OPENCODE_MODE:-ok}" in
  ok)      printf '{"data":{"id":"ses_fake"}}\n' ;;
  fail)    echo "opencode service unavailable" >&2; exit 1 ;;
  badjson) printf 'not-json\n' ;;
  helpv2)  # v2.1.4 재현: help 에 'opencode api' 리터럴 없음(서브커맨드는 'api' 단독 토큰)
    case "${1:-}" in
      --help) printf 'SUBCOMMANDS\n  api       Make a request to the running server\n' ;;
      *)      printf '{"data":{"id":"ses_fake"}}\n' ;;
    esac ;;
esac
STUBEOF
chmod +x "$STUB/opencode"

# run_case <mode> <logdir> [extra args...] → stdout+stderr는 $dir/out, 종료코드는 전역 RC
run_case() {
  local mode="$1" dir="$2"; shift 2
  CWD_CASE="$(mktemp -d)"
  HERDR_START_LOG="$dir/herdr.log" OPENCODE_CALL_LOG="$dir/opencode.log" OPENCODE_MODE="$mode" \
    HERDR_START_RC="${HERDR_START_RC:-0}" \
    HERDR_TEAM_AGENT_START_TIMEOUT_MS="${HERDR_TEAM_AGENT_START_TIMEOUT_MS:-}" \
    PATH="$STUB:$PATH" "$BIN" t --preset dev --cwd "$CWD_CASE" \
    --template-dir "$REPO/templates" --no-interactive "$@" >"$dir/out" 2>&1
  RC=$?
}

echo "== a) 정상: 세션 생성 후 -- --session ses_fake 로 시작 =="
D1="$(mktemp -d)"; run_case ok "$D1"
assert_exit "$RC" 0 "session_ok: exit 0"
assert_contains "$(cat "$D1/opencode.log" 2>/dev/null)" "api post /api/session" "session_ok: 세션 생성 호출"
assert_contains "$(cat "$D1/herdr.log" 2>/dev/null)" "-- --session ses_fake" "session_ok: -- --session 바인딩"
assert_not_contains "$(cat "$D1/herdr.log" 2>/dev/null)" "-- --agent" "session_ok: --agent 미사용"
rm -rf "$D1" "$CWD_CASE"

echo "== b) 세션 생성 실패(비정상 종료) → fail-fast =="
D2="$(mktemp -d)"; run_case fail "$D2"
if [[ "$RC" -ne 0 ]]; then ok "session_fail: exit != 0"; else bad "session_fail: exit != 0 (rc=0)"; fi
assert_contains "$(cat "$D2/out")" "session creation failed" "session_fail: 원인 메시지"
assert_contains "$(cat "$D2/out")" "panes already created" "session_fail: 생성된 pane 정리 안내"
assert_not_contains "$(cat "$D2/herdr.log" 2>/dev/null)" "agent start" "session_fail: agent start 미실행"
assert_not_contains "$(cat "$D2/herdr.log" 2>/dev/null)" "--agent" "session_fail: --agent 미사용"
assert_not_contains "$(cat "$D2/herdr.log" 2>/dev/null)" "--model" "session_fail: --model 미사용"
rm -rf "$D2" "$CWD_CASE"

echo "== c) 잘못된 JSON 응답 → sid 파싱 실패 fail-fast =="
D3="$(mktemp -d)"; run_case badjson "$D3"
if [[ "$RC" -ne 0 ]]; then ok "session_badjson: exit != 0"; else bad "session_badjson: exit != 0 (rc=0)"; fi
assert_contains "$(cat "$D3/out")" "session id parse failed" "session_badjson: 원인 메시지"
assert_not_contains "$(cat "$D3/herdr.log" 2>/dev/null)" "agent start" "session_badjson: agent start 미실행"
assert_not_contains "$(cat "$D3/herdr.log" 2>/dev/null)" "--agent" "session_badjson: --agent 미사용"
assert_not_contains "$(cat "$D3/herdr.log" 2>/dev/null)" "--model" "session_badjson: --model 미사용"
rm -rf "$D3" "$CWD_CASE"

echo "== d) --no-start 면제: 세션 생성 호출 없음, exit 0 =="
D4="$(mktemp -d)"; run_case fail "$D4" --no-start
assert_exit "$RC" 0 "session_no_start: exit 0"
if [[ ! -f "$D4/opencode.log" ]]; then ok "session_no_start: opencode 미호출"; else bad "session_no_start: opencode 미호출"; fi
rm -rf "$D4" "$CWD_CASE"

echo "== e) --dry-run 면제: 실행 없이 계획만, exit 0 =="
D5="$(mktemp -d)"; run_case fail "$D5" --dry-run
assert_exit "$RC" 0 "session_dryrun: exit 0"
if [[ ! -f "$D5/opencode.log" ]]; then ok "session_dryrun: opencode 미호출"; else bad "session_dryrun: opencode 미호출"; fi
assert_contains "$(cat "$D5/out")" "SID_PLANNER" "session_dryrun: SID 계획 출력"
assert_contains "$(cat "$D5/out")" "-- --session" "session_dryrun: 세션 바인딩 계획"
rm -rf "$D5" "$CWD_CASE"

echo "== f) kind 게이팅: opencode 아닌 kind는 세션 생성 없음 =="
D6="$(mktemp -d)"; run_case fail "$D6" --kind codex
assert_exit "$RC" 0 "session_kind_gate: exit 0"
if [[ ! -f "$D6/opencode.log" ]]; then ok "session_kind_gate: opencode 미호출"; else bad "session_kind_gate: opencode 미호출"; fi
assert_not_contains "$(cat "$D6/out")" "api post /api/session" "session_kind_gate: 세션 계획 미출력"
rm -rf "$D6" "$CWD_CASE"

echo "== g) 실모드 planner payload: model 지정 =="
D7="$(mktemp -d)"; run_case ok "$D7"
assert_exit "$RC" 0 "model_payload: exit 0"
LOG7="$(cat "$D7/opencode.log" 2>/dev/null)"
assert_contains "$(printf '%s' "$LOG7" | grep -F 't-planner')" \
  '"model":{"providerID":"opencode-go","id":"glm-5.3-flash"}' "model_payload: planner model 지정"
rm -rf "$D7" "$CWD_CASE"

echo "== h) 실모드 비플래너 payload: model 키 생략 =="
D8="$(mktemp -d)"; run_case ok "$D8"
LOG8="$(cat "$D8/opencode.log" 2>/dev/null)"
for _r in worker reviewer orchestrator; do
  assert_not_contains "$(printf '%s' "$LOG8" | grep -F "t-$_r")" '"model"' "model_payload: t-$_r 무지정"
done
rm -rf "$D8" "$CWD_CASE"

echo "== i) dry-run 계획: planner 모델 표시, 비플래너 미표시 =="
D9="$(mktemp -d)"; run_case fail "$D9" --dry-run
OUT9="$(cat "$D9/out")"
assert_contains "$(printf '%s' "$OUT9" | grep -F 'SID_PLANNER')" "glm-5.3-flash" "model_dryrun: planner 모델 표시"
assert_not_contains "$(printf '%s' "$OUT9" | grep -F 'SID_WORKER')" "glm-5.3-flash" "model_dryrun: worker 모델 미표시"
rm -rf "$D9" "$CWD_CASE"

echo "== j) api 지원 판별은 실행 rc 기반: help 포맷에 'opencode api' 리터럴 없어도 지원 =="
D10="$(mktemp -d)"; run_case helpv2 "$D10"
assert_exit "$RC" 0 "api_probe: exit 0"
LOG10="$(cat "$D10/opencode.log" 2>/dev/null)"
assert_contains "$LOG10" "api post /api/session" "api_probe: 세션 생성 호출"
assert_contains "$(cat "$D10/herdr.log" 2>/dev/null)" "-- --session ses_fake" "api_probe: -- --session 바인딩"
assert_not_contains "$(cat "$D10/herdr.log" 2>/dev/null)" "-- --agent" "api_probe: --agent 미사용"
PROBE_N="$(printf '%s\n' "$LOG10" | grep -c -- '--help')"
assert_exit "$PROBE_N" 1 "api_probe: --help 프루브 1회(캐시)"
rm -rf "$D10" "$CWD_CASE"

echo "== k) herdr agent start 실패 → --timeout 명시 + 명시 종료 =="
D11="$(mktemp -d)"; HERDR_START_RC=1 run_case ok "$D11"
if [[ "$RC" -ne 0 ]]; then ok "start_fail: exit != 0"; else bad "start_fail: exit != 0 (rc=0)"; fi
assert_contains "$(cat "$D11/out")" "agent start failed/timed out" "start_fail: 안내 메시지"
assert_contains "$(cat "$D11/herdr.log" 2>/dev/null)" "--timeout 15000 --pane" "start_fail: --timeout 은 --pane 앞"
rm -rf "$D11" "$CWD_CASE"

echo "== l) 시작 타임아웃 env 검증: 비숫자/소수는 기본값, 0/음수는 하한 클램프 =="
for _t in abc 1.5 0 -5; do
  case "$_t" in abc|1.5) _want=15000 ;; *) _want=1 ;; esac
  D12="$(mktemp -d)"
  HERDR_TEAM_AGENT_START_TIMEOUT_MS="$_t" run_case ok "$D12"
  assert_exit "$RC" 0 "timeout_env: $_t exit 0"
  assert_contains "$(cat "$D12/herdr.log" 2>/dev/null)" "--timeout $_want --pane" "timeout_env: $_t -> $_want"
  assert_not_contains "$(cat "$D12/out")" "syntax error" "timeout_env: $_t stderr 무오염"
  assert_not_contains "$(cat "$D12/out")" "unbound variable" "timeout_env: $_t unbound 없음"
  rm -rf "$D12" "$CWD_CASE"
done
VER_OUT="$(HERDR_TEAM_AGENT_START_TIMEOUT_MS=abc "$BIN" --version 2>&1)"; VER_RC=$?
assert_exit "$VER_RC" 0 "timeout_env: --version exit 0 (비숫자)"
assert_contains "$VER_OUT" "herdr-team v" "timeout_env: --version 정상 출력"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
