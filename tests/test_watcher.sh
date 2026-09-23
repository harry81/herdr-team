#!/usr/bin/env bash
# tests/test_watcher.sh — herdr-watcher AUTO-ALLOW 무중복/무stray 키 회귀 검증
# 실행: bash tests/test_watcher.sh  (repo root에서)
# fake herdr 셰임 + HERDR_FIX fixture로 팝업/전송을 결정적으로 재현한다.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WATCH="$REPO/bin/herdr-watcher"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

assert_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi
}
assert_not_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi
}
assert_equal() { # $1=actual $2=expected $3=label
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got=$1, want=$2)"; fi
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 없음 → herdr-watcher 회귀 테스트 생략"
  printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
  exit 0
fi

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/bin"

cat > "$FIX/bin/herdr" <<'STUBEOF'
#!/usr/bin/env bash
FIX="${HERDR_FIX:?}"
case "${1:-}" in
  agent)
    case "${2:-}" in
      list) cat "$FIX/agents.json" ;;
      read)
        n=0; [ -f "$FIX/read_count" ] && n=$(cat "$FIX/read_count"); n=$((n+1)); echo "$n" > "$FIX/read_count"
        case "$(cat "$FIX/screen_mode" 2>/dev/null || echo none)" in
          popup_bottom)      echo "Permission required"; echo "Allow once  Allow always  Reject"; echo "enter confirm" ;;
          transcript)        echo "Permission required"; echo "Allow once  Allow always  Reject"; echo "enter confirm"; echo "이후 대화 기록 계속"; echo "normal" ;;
          transcript_bottom) echo "Permission required"; echo "Allow once  Allow always  Reject"; echo "enter confirm"; echo "이후 대화 기록 계속"; echo "Permission required"; echo "Allow once  Allow always  Reject"; echo "enter confirm" ;;
          once)  if [ -f "$FIX/send.log" ]; then echo "normal"; else echo "Permission required"; echo "Allow once  Allow always  Reject"; echo "enter confirm"; fi ;;
          *)     echo "normal" ;;
        esac ;;
    esac ;;
  pane)
    case "${2:-}" in send-keys) echo "$*" >> "$FIX/send.log" ;; esac ;;
esac
STUBEOF
chmod +x "$FIX/bin/herdr"

set_status()  { printf '{"result":{"agents":[{"name":"t-worker","agent_status":"%s","pane_id":"wT:p1","terminal_title":"","cwd":".","interactive_ready":true}]}}\n' "$1" > "$FIX/agents.json"; }
set_status blocked

reset_fix()   { rm -f "$FIX/read_count" "$FIX/send.log"; }
set_screen()  { printf '%s\n' "$1" > "$FIX/screen_mode"; }
run_watch_case() { # $1=max_iterations, rest=extra opts
  local iters="$1"; shift
  PATH="$FIX/bin:$PATH" HERDR_FIX="$FIX" "$WATCH" --prefix t- --interval 0 --max-iterations "$iters" "$@" >/dev/null 2>&1
}
send_lines() { if [ -f "$FIX/send.log" ]; then grep -c . "$FIX/send.log"; else echo 0; fi; }

echo "== a) 팝업 없음 + blocked → 승인 키 미전송 (stray 0) =="
reset_fix; set_screen none
run_watch_case 1
assert_equal "$(send_lines)" "0" "watcher_a_팝업없음_stray0"

echo "== b) 팝업 확인 → enter 1회 승인, tab 미포함 =="
reset_fix; set_screen popup_bottom
run_watch_case 1
SEND_B="$(cat "$FIX/send.log" 2>/dev/null || true)"
assert_equal "$(send_lines)" "1" "watcher_b_승인1회"
assert_contains "$SEND_B" "enter" "watcher_b_enter포함"
assert_not_contains "$SEND_B" "tab" "watcher_b_tab미포함"

echo "== c) 팝업이 승인 후 소멸 → 정확히 1회 (무디바운스/재발사 회귀) =="
reset_fix; set_screen once
run_watch_case 5
assert_equal "$(send_lines)" "1" "watcher_c_1회만"

echo "== d) 팝업 유지 + --fallback-keys 옵트인 → max-attempts 2, 2번째는 fallback(tab enter) =="
reset_fix; set_screen popup_bottom
run_watch_case 5 --retry-after 0 --max-attempts 2 --fallback-keys "tab enter"
assert_equal "$(send_lines)" "2" "watcher_d_최대2회"
SECOND="$(awk 'NR==2' "$FIX/send.log" 2>/dev/null || true)"
assert_contains "$SECOND" "tab enter" "watcher_d_2번째_fallback"

echo "== e) --no-auto-allow → 미전송 =="
reset_fix; set_screen popup_bottom
run_watch_case 2 --no-auto-allow
assert_equal "$(send_lines)" "0" "watcher_e_no_auto_allow_미전송"

echo "== f) --approve-keys 커스텀(right enter) → 키 시퀀스 반영 =="
reset_fix; set_screen popup_bottom
run_watch_case 1 --approve-keys "right enter"
SEND_F="$(cat "$FIX/send.log" 2>/dev/null || true)"
assert_equal "$(send_lines)" "1" "watcher_f_1회"
assert_contains "$SEND_F" "right enter" "watcher_f_right_enter"

echo "== g) --allow-on-blocked 옵트인 → 레거시 복원(1회) =="
reset_fix; set_screen none
run_watch_case 1 --allow-on-blocked
assert_equal "$(send_lines)" "1" "watcher_g_allow_on_blocked"

echo "== h) status=working + 화면 마커가 중간에만(transcript, 오탐) → 전송 0건 (오탐 차단) =="
reset_fix; set_status working; set_screen transcript
run_watch_case 5
assert_equal "$(send_lines)" "0" "watcher_h_working_오탐_전송0"

echo "== i) blocked + popup(유지) + 기본 fallback → enter 만, tab 0건 (fail-closed) =="
reset_fix; set_status blocked; set_screen popup_bottom
run_watch_case 5 --retry-after 0
SEND_I="$(cat "$FIX/send.log" 2>/dev/null || true)"
assert_equal "$(send_lines)" "1" "watcher_i_enter만1회"
assert_not_contains "$SEND_I" "tab" "watcher_i_기본fallback_tab0"

echo "== j) status=idle + 화면 맨 아래 진짜 팝업(popup_bottom) → 승인 1회 (상태신호 사망 시에도 동작) =="
reset_fix; set_status idle; set_screen popup_bottom
run_watch_case 5
SEND_J="$(cat "$FIX/send.log" 2>/dev/null || true)"
assert_equal "$(send_lines)" "1" "watcher_j_idle_팝업승인1회"
assert_contains "$SEND_J" "enter" "watcher_j_enter포함"
assert_not_contains "$SEND_J" "tab" "watcher_j_tab미포함"

echo "== k) transcript 중간 마커 + 맨 아래 진짜 팝업 동시 → 정확히 1회, enter 만 =="
reset_fix; set_status idle; set_screen transcript_bottom
run_watch_case 5
SEND_K="$(cat "$FIX/send.log" 2>/dev/null || true)"
assert_equal "$(send_lines)" "1" "watcher_k_정확히1회"
assert_contains "$SEND_K" "enter" "watcher_k_enter포함"
assert_not_contains "$SEND_K" "tab" "watcher_k_tab미포함"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
