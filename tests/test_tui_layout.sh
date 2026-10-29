#!/usr/bin/env bash
# tests/test_tui_layout.sh — ht 첫 화면/카운트다운 레이아웃 regression (F2)
# 명세: docs/specs/ht-tui-english-fancy-spec.md §3 (카운트다운 2줄), §4.1 (배너 최상단), §8.1
# 실행: bash tests/test_tui_layout.sh  (repo root에서)
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
assert_not_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi
}
assert_equal() { # $1=actual $2=expected $3=label
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (differ: [$1] != [$2])"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}
has_byte() { # $1=text $2=hex byte
  local hex
  hex="$(printf '%s' "$1" | od -An -tx1 | tr -s ' ' '\n')"
  [[ $'\n'"$hex"$'\n' == *$'\n'"$2"$'\n'* ]]
}
assert_plain_bytes() { # $1=output $2=label
  if has_byte "$1" 1b; then bad "$2 (ESC 0x1b found)";
  elif has_byte "$1" 0d; then bad "$2 (CR 0x0d found)";
  else ok "$2"; fi
}
ps_count() { # $1=pattern
  ps -eo args= 2>/dev/null | grep -F -- "$1" | grep -v -F 'grep -F' | wc -l | tr -d ' '
}

[[ -x "$BIN" ]] || { printf 'FAIL: %s not executable\n' "$BIN"; exit 1; }

echo "== L1) 프롬프트 라인 개행 확정 (plain/파이프) =="
PROMPT_OUT="$(printf '1\n1\n' | timeout 20 "$BIN" test --dry-run --no-template 2>&1)"; PROMPT_RC=$?
assert_exit "$PROMPT_RC" 0 "l1_파이프_exit0"
PROMPT_LINE="$(printf '%s\n' "$PROMPT_OUT" | grep -F 'Select [1-' || true)"
if [[ -n "$PROMPT_LINE" ]]; then ok "l1_프롬프트_라인_존재"; else bad "l1_프롬프트_라인_존재"; fi
if [[ "$PROMPT_LINE" =~ \(default:\ [a-z]+,\ 10s\):$ ]]; then
  ok "l1_프롬프트_라인_개행확정"
else
  bad "l1_프롬프트_라인_개행확정 (['"$PROMPT_LINE"'])"
fi
KIND_PROMPT_LINE="$(printf '%s\n' "$PROMPT_OUT" | grep -F 'Select [1-4/' || true)"
if [[ "$KIND_PROMPT_LINE" =~ \(default:\ opencode,\ 10s\):$ ]]; then
  ok "l1_kind_프롬프트_라인_개행확정"
else
  bad "l1_kind_프롬프트_라인_개행확정 (['"$KIND_PROMPT_LINE"'])"
fi

echo "== L2) plain 모드: 카운트다운 0바이트·프로세스 0개 =="
assert_not_contains "$PROMPT_OUT" "remaining" "l2_plain_remaining_부재"
assert_plain_bytes "$PROMPT_OUT" "l2_plain_escape_CR_부재"
assert_equal "$(ps_count "$BIN")" "0" "l2_plain_고아프로세스_0건"

echo "== L3) EOF/타임아웃 폴백 + 잔여 문자열 0건 =="
T0=$SECONDS
EOF_OUT="$(printf '' | timeout 20 "$BIN" test --dry-run --no-template 2>&1)"; EOF_RC=$?
EOF_ELAPSED=$((SECONDS-T0))
assert_exit "$EOF_RC" 0 "l3_EOF_exit0"
assert_contains "$EOF_OUT" "preset=dev" "l3_EOF_dev기본"
assert_not_contains "$EOF_OUT" "remaining" "l3_EOF_잔여_remaining_0건"
assert_not_contains "$EOF_OUT" "^C" "l3_EOF_잔여_CTRLC_0건"
if [[ "$EOF_ELAPSED" -lt 8 ]]; then ok "l3_EOF_즉시복귀(${EOF_ELAPSED}s)"; else bad "l3_EOF_즉시복귀(${EOF_ELAPSED}s)"; fi
assert_equal "$(ps_count "$BIN")" "0" "l3_EOF_고아프로세스_0건"

echo "== L4) TTY: 상태 라인 분리 + 폭 규칙 + Ctrl-C 잔존 0건 =="
if command -v script >/dev/null 2>&1; then
  TTY_OUT="$( ( sleep 2; printf '1\n1\n' ) | env -u CI -u NO_COLOR timeout 25 script -qec "stty cols 100; $BIN test --dry-run --no-template" /dev/null 2>&1)"
  assert_contains "$TTY_OUT" "s [" "l4_TTY_상태라인_bar"
  MIXED="$(printf '%s\n' "$TTY_OUT" | grep -E 'Select \[1-.*remaining' || true)"
  assert_equal "$MIXED" "" "l4_프롬프트_상태_동일라인_0건"
  STATUS_N="$(printf '%s' "$TTY_OUT" | od -An -c | grep -c '\\r' || true)"
  if [[ "${STATUS_N:-0}" -ge 1 ]]; then ok "l4_TTY_상태라인_CR_갱신"; else bad "l4_TTY_상태라인_CR_갱신 (CR 0)"; fi
  assert_equal "$(ps_count "$BIN")" "0" "l4_TTY_고아프로세스_0건"
else
  echo "SKIP: script 없음 → TTY 레이아웃 검증 생략"
fi

echo "== L5) 배너 최상단 (plain/파이프) =="
BANNER_FIRST="$(printf '%s\n' "$PROMPT_OUT" | grep -n -E 'herdr-team v|Select AI team preset' | head -n2)"
FIRST_KIND="$(printf '%s\n' "$BANNER_FIRST" | head -n1 | sed 's/:.*//')"
SECOND_KIND="$(printf '%s\n' "$BANNER_FIRST" | tail -n1 | sed 's/:.*//')"
if [[ -n "$FIRST_KIND" && "$(printf '%s\n' "$PROMPT_OUT" | sed -n "${FIRST_KIND}p")" == herdr-team* ]]; then
  ok "l5_배너_최상단"
else
  bad "l5_배너_최상단 (first=$FIRST_KIND second=$SECOND_KIND)"
fi

echo "== L6) Ctrl-C: 상태 라인 클리어 + 잔존 remaining/^C 0건 =="
if command -v script >/dev/null 2>&1 && command -v stty >/dev/null 2>&1; then
  CTRL_LOG="$(mktemp)"
  ( sleep 3; printf '\003'; sleep 1 ) | timeout 25 script -qec "stty cols 100; exec $BIN test --dry-run --no-template" "$CTRL_LOG" >/dev/null 2>&1
  CTRL_RC=$?
  if [[ "$CTRL_RC" -ne 0 ]]; then ok "l6_INT_비정상종료(rc=$CTRL_RC)"; else bad "l6_INT_비정상종료(rc=$CTRL_RC)"; fi
  assert_equal "$(grep -ac 'remaining' "$CTRL_LOG" || true)" "0" "l6_INT_remaining_잔존0"
  assert_equal "$(grep -ac '\^C' "$CTRL_LOG" || true)" "0" "l6_INT_CTRLC_잔존0"
  TAIL_BYTE="$(tail -c 1 "$CTRL_LOG" | od -An -c | tr -d ' ')"
  if [[ "$TAIL_BYTE" == '\n' ]]; then ok "l6_INT_마지막바이트_개행"; else bad "l6_INT_마지막바이트_개행 ($TAIL_BYTE)"; fi
  rm -f "$CTRL_LOG"
else
  echo "SKIP: script/stty 없음 → Ctrl-C 검증 생략"
fi

echo "== L7) 폭 축소 규칙 (cols<20 → bar 생략) =="
if command -v script >/dev/null 2>&1; then
  NARROW_LOG="$(mktemp)"
  ( sleep 2; printf '1\n1\n' ) | timeout 25 script -qec "stty cols 15; exec $BIN test --dry-run --no-template" "$NARROW_LOG" >/dev/null 2>&1
  assert_equal "$(grep -ac 's \[' "$NARROW_LOG" || true)" "0" "l7_좁은폭_bar_생략"
  if grep -aq 's ' "$NARROW_LOG"; then ok "l7_좁은폭_초_표시"; else bad "l7_좁은폭_초_표시"; fi
  rm -f "$NARROW_LOG"
else
  echo "SKIP: script 없음 → 폭 축소 검증 생략"
fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
