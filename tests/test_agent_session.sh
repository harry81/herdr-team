#!/usr/bin/env bash
# tests/test_agent_session.sh — opencode 세션 사전생성 + `-- --session` 바인딩 / fail-fast 검증
# 실행: bash tests/test_agent_session.sh  (repo root에서)
# fake herdr/opencode 셤으로 세션 생성 실패 경로를 결정적으로 재현한다.
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
    printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n' ;;
  agent)
    case "${2:-}" in
      list) exit 1 ;;  # 에이전트 없음 → start 진행
      start) printf '%s\n' "$*" >> "${HERDR_START_LOG:?}" ;;
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
esac
STUBEOF
chmod +x "$STUB/opencode"

# run_case <mode> <logdir> [extra args...] → stdout+stderr는 $dir/out, 종료코드는 전역 RC
run_case() {
  local mode="$1" dir="$2"; shift 2
  CWD_CASE="$(mktemp -d)"
  HERDR_START_LOG="$dir/herdr.log" OPENCODE_CALL_LOG="$dir/opencode.log" OPENCODE_MODE="$mode" \
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
assert_contains "$(cat "$D2/out")" "세션 생성 실패" "session_fail: 원인 메시지"
assert_contains "$(cat "$D2/out")" "이미 생성된 pane" "session_fail: 생성된 pane 정리 안내"
assert_not_contains "$(cat "$D2/herdr.log" 2>/dev/null)" "agent start" "session_fail: agent start 미실행"
rm -rf "$D2" "$CWD_CASE"

echo "== c) 잘못된 JSON 응답 → sid 파싱 실패 fail-fast =="
D3="$(mktemp -d)"; run_case badjson "$D3"
if [[ "$RC" -ne 0 ]]; then ok "session_badjson: exit != 0"; else bad "session_badjson: exit != 0 (rc=0)"; fi
assert_contains "$(cat "$D3/out")" "파싱 실패" "session_badjson: 원인 메시지"
assert_not_contains "$(cat "$D3/herdr.log" 2>/dev/null)" "agent start" "session_badjson: agent start 미실행"
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

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
