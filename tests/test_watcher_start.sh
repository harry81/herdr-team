#!/usr/bin/env bash
# tests/test_watcher_start.sh — herdr-team --watcher 옵트인 기동 (TC-WS 21~28)
# 명세: docs/specs/permission-fatigue-reduction-spec.md §3 / §4 (TC-WS)
# 실행: bash tests/test_watcher_start.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }
assert_contains() { if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
assert_not_contains() { if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi; }
assert_equal() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 ($1 != $2)"; fi; }
assert_exit() { if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq 없음 → watcher 기동 검증 생략"
  printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; exit 0
fi

STUB="$(mktemp -d)"; NO_WATCH_STUB="$(mktemp -d)"; ROOT="$(mktemp -d)"
ARGS="$STUB/watcher-args"
# 작업 디렉터리는 $ROOT 하위에 만들어 정리 시 pidfile 기준으로 stub watcher 를 종료한다
# (pkill 패턴은 테스트 자신의 셸 명령줄과 충돌할 수 있어 사용하지 않는다).
cleanup() {
  local pf pid
  for pf in "$ROOT"/*/.herdr-team/watcher.pid; do
    [[ -f "$pf" ]] || continue
    pid="$(tr -cd '0-9' < "$pf")"
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  done
  rm -rf "$STUB" "$NO_WATCH_STUB" "$ROOT"
}
trap cleanup EXIT

mk_herdr_stub() { # $1=dir — pane/agent 최소 stub (실제 start 경로용)
  cat > "$1/herdr" <<'STUBEOF'
#!/usr/bin/env bash
case "${1:-}" in
  pane)
    case "${2:-}" in
      process-info) printf '{"result":{"process_info":{"shell_pid":42,"foreground_process_group_id":42}}}\n' ;;
      *) printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n' ;;
    esac ;;
  agent)
    case "${2:-}" in
      list) exit 1 ;;
      start) printf '%s\n' "$*" >> "${HT_START_LOG:-/dev/null}" ;;
    esac ;;
esac
exit 0
STUBEOF
  chmod +x "$1/herdr"
}
mk_herdr_stub "$STUB"; mk_herdr_stub "$NO_WATCH_STUB"

# herdr-watcher stub: 인자를 기록하고 오래 살아있는 프로세스로 남는다(중복 기동 판정용)
cat > "$STUB/herdr-watcher" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${HT_WATCHER_ARGS:-/dev/null}"
trap 'exit 0' TERM INT
while :; do sleep 1; done
STUBEOF
chmod +x "$STUB/herdr-watcher"

mk_work() { mktemp -d "$ROOT/w.XXXXXX"; }
ht() { # $1=cwd [args...]
  local cwd="$1"; shift
  PATH="$STUB:$PATH" HT_WATCHER_ARGS="$ARGS" HT_START_LOG="$STUB/start.log" \
    "$BIN" wtest --preset dev --cwd "$cwd" --template-dir "$REPO/templates" --no-interactive --kind claude "$@" 2>&1
}
watcher_count() { local n; n="$(pgrep -fc "$STUB/herdr-watcher" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
wait_arg() { # $1=기대 인자 — watcher stub 기록은 비동기라 최대 3s 폴링 후 판정
  local i
  for i in $(seq 1 15); do
    grep -qF -- "$1" "$ARGS" 2>/dev/null && return 0
    sleep 0.2
  done
  return 0
}

echo "== TC-WS 21) --watcher --no-start → 기동 생략 + rc 0 =="
D="$(mk_work)"
OUT="$(ht "$D" --watcher --no-start)"; RC=$?
assert_exit "$RC" 0 "tc_ws_21_exit_0"
assert_contains "$OUT" "watcher 생략" "tc_ws_21_생략_log"
if [[ ! -f "$D/.herdr-team/watcher.pid" ]]; then ok "tc_ws_21_pidfile_미생성"; else bad "tc_ws_21_pidfile_미생성"; fi
assert_equal "$(watcher_count)" "0" "tc_ws_21_프로세스_0"
# --templates-only 도 동일하게 생략
D="$(mk_work)"
OUT="$(ht "$D" --watcher --templates-only)"; RC=$?
assert_exit "$RC" 0 "tc_ws_21b_templates_only_exit_0"
assert_contains "$OUT" "watcher 생략" "tc_ws_21b_templates_only_생략"

echo "== TC-WS 22) --watcher 기동: pidfile + 프로세스 + log =="
D="$(mk_work)"; : > "$ARGS"
OUT="$(ht "$D" --watcher)"; RC=$?
assert_exit "$RC" 0 "tc_ws_22_exit_0"
PIDFILE="$D/.herdr-team/watcher.pid"
if [[ -f "$PIDFILE" ]]; then ok "tc_ws_22_pidfile_생성"; else bad "tc_ws_22_pidfile_생성"; fi
WPID="$(tr -cd '0-9' < "$PIDFILE" 2>/dev/null)"
if [[ -n "$WPID" ]] && kill -0 "$WPID" 2>/dev/null; then ok "tc_ws_22_프로세스_가동"; else bad "tc_ws_22_프로세스_가동 (pid=$WPID)"; fi
if [[ -f "$D/.herdr-team/watcher.log" ]]; then ok "tc_ws_22_log_생성"; else bad "tc_ws_22_log_생성"; fi
wait_arg "--cwd $D"
assert_contains "$(cat "$ARGS" 2>/dev/null)" "--prefix wtest-" "tc_ws_28_prefix_전달"
assert_contains "$(cat "$ARGS" 2>/dev/null)" "--cwd $D" "tc_ws_28_cwd_전달"
assert_contains "$OUT" "L2 ask" "tc_ws_22_안전고지"

echo "== TC-WS 23) 중복 기동 방지: 재실행 → pidfile 동일 + 프로세스 1개 =="
PID_BEFORE="$(cat "$PIDFILE")"
OUT="$(ht "$D" --watcher)"; RC=$?
assert_exit "$RC" 0 "tc_ws_23_exit_0"
assert_equal "$(cat "$PIDFILE")" "$PID_BEFORE" "tc_ws_23_pidfile_동일"
assert_equal "$(watcher_count)" "1" "tc_ws_23_프로세스_1개"
assert_contains "$OUT" "이미 가동" "tc_ws_23_스킵_log"

echo "== TC-WS 24) stale pidfile → 갱신 후 정상 기동 =="
D="$(mk_work)"
OUT="$(ht "$D" --watcher)"; RC=$?
assert_exit "$RC" 0 "tc_ws_24_1회차_exit_0"
kill "$(tr -cd '0-9' < "$D/.herdr-team/watcher.pid")" 2>/dev/null
DEAD="$(bash -c 'echo $$')"   # 이미 종료된 PID
printf '%s\n' "$DEAD" > "$D/.herdr-team/watcher.pid"
OUT="$(ht "$D" --watcher)"; RC=$?
assert_exit "$RC" 0 "tc_ws_24_재기동_exit_0"
NEWPID="$(cat "$D/.herdr-team/watcher.pid")"
if [[ "$NEWPID" != "$DEAD" ]] && kill -0 "$NEWPID" 2>/dev/null; then ok "tc_ws_24_pidfile_갱신"; else bad "tc_ws_24_pidfile_갱신 (pid=$NEWPID dead=$DEAD)"; fi

echo "== TC-WS 25) --dry-run --watcher → 계획 1행 + 프로세스 0 =="
D="$(mk_work)"
OUT="$(ht "$D" --watcher --dry-run)"; RC=$?
assert_exit "$RC" 0 "tc_ws_25_exit_0"
assert_contains "$OUT" "+ watcher:" "tc_ws_25_계획_출력"
assert_equal "$(printf '%s\n' "$OUT" | grep -c '^+ watcher:')" "1" "tc_ws_25_계획_1행"
if [[ ! -f "$D/.herdr-team/watcher.pid" ]]; then ok "tc_ws_25_프로세스_0"; else bad "tc_ws_25_프로세스_0"; fi

echo "== TC-WS 26) 기동 실패(watcher 경로 없음) → 경고 + ht rc 불변 =="
ISO="$(mktemp -d "$ROOT/iso.XXXXXX")"; mkdir -p "$ISO/bin"
cp "$BIN" "$ISO/bin/herdr-team"
D="$(mk_work)"
OUT="$(PATH="$NO_WATCH_STUB:/usr/local/bin:/usr/bin:/bin" "$ISO/bin/herdr-team" wtest --preset dev \
  --cwd "$D" --template-dir "$REPO/templates" --no-interactive --kind claude --watcher 2>&1)"; RC=$?
assert_exit "$RC" 0 "tc_ws_26_비차단_rc0"
assert_contains "$OUT" "watcher" "tc_ws_26_경고_출력"
assert_contains "$OUT" "생략" "tc_ws_26_생략_문구"
if [[ ! -f "$D/.herdr-team/watcher.pid" ]]; then ok "tc_ws_26_pidfile_미생성"; else bad "tc_ws_26_pidfile_미생성"; fi

echo "== TC-WS 26b) 즉시 종료 watcher → 경고 1행 + pidfile 미기록 + rc 불변 (F-04) =="
XSTUB="$(mktemp -d "$ROOT/x.XXXXXX")"
cp "$STUB/herdr" "$XSTUB/herdr"
cat > "$XSTUB/herdr-watcher" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${HT_WATCHER_ARGS:-/dev/null}"
exit 3
STUBEOF
chmod +x "$XSTUB/herdr-watcher"
D="$(mk_work)"; : > "$ARGS"
OUT="$(PATH="$XSTUB:$PATH" HT_WATCHER_ARGS="$ARGS" "$BIN" wtest --preset dev --cwd "$D" \
  --template-dir "$REPO/templates" --no-interactive --kind claude --watcher 2>&1)"; RC=$?
assert_exit "$RC" 0 "tc_ws_26b_비차단_rc0"
assert_contains "$OUT" "기동 실패" "tc_ws_26b_경고_출력"
assert_not_contains "$OUT" "watcher 기동: pid=" "tc_ws_26b_성공로그_없음"
if [[ ! -f "$D/.herdr-team/watcher.pid" ]]; then ok "tc_ws_26b_pidfile_미기록"; else bad "tc_ws_26b_pidfile_미기록"; fi

echo "== TC-WS 27) pidfile 은 .herdr-team/ 내부 + gitignore 연동 =="
D="$(mk_work)"; git -C "$D" init -q
ht "$D" --watcher >/dev/null 2>&1
if [[ -f "$D/.herdr-team/watcher.pid" ]]; then ok "tc_ws_27_pidfile_경로"; else bad "tc_ws_27_pidfile_경로"; fi
if grep -qF '.herdr-team/' "$D/.gitignore" 2>/dev/null; then ok "tc_ws_27_gitignore_연동"; else bad "tc_ws_27_gitignore_연동"; fi

echo "== E7) --no-auto-allow 전파 (모니터링만) =="
D="$(mk_work)"; : > "$ARGS"
OUT="$(ht "$D" --watcher --no-auto-allow)"; RC=$?
assert_exit "$RC" 0 "e7_exit_0"
wait_arg "--no-auto-allow"
assert_contains "$(cat "$ARGS" 2>/dev/null)" "--no-auto-allow" "e7_no_auto_allow_전파"

echo "== 옵션 문서화 + 기본 off =="
HELP="$("$BIN" --help 2>&1)"
assert_contains "$HELP" "--watcher" "tc_ws_help_document"
D="$(mk_work)"
OUT="$(ht "$D")"; RC=$?
assert_exit "$RC" 0 "tc_ws_default_off_exit_0"
assert_not_contains "$OUT" "watcher 기동" "tc_ws_default_off"
if [[ ! -f "$D/.herdr-team/watcher.pid" ]]; then ok "tc_ws_default_off_pidfile_없음"; else bad "tc_ws_default_off_pidfile_없음"; fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
