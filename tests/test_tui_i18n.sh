#!/usr/bin/env bash
# tests/test_tui_i18n.sh — ht 실행화면 i18n + TUI 시각 개선 검증
# 명세: docs/specs/ht-tui-i18n-and-polish-spec.md (§7 tc-1..tc-7)
# 실행: bash tests/test_tui_i18n.sh  (repo root에서)
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
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (outputs differ)"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}
has_byte() { # $1=text $2=hex byte (1b/0d) — od 사용 (macOS/GNU 공통)
  printf '%s' "$1" | od -An -tx1 | tr ' ' '\n' | grep -qx -- "$2"
}
assert_plain_bytes() { # $1=output $2=label — plain 모드: ESC(0x1b)·CR(0x0d) 부재
  if has_byte "$1" 1b; then bad "$2 (ESC 0x1b found)";
  elif has_byte "$1" 0d; then bad "$2 (CR 0x0d found)";
  else ok "$2"; fi
}

[[ -x "$BIN" ]] || { printf 'FAIL: %s not executable\n' "$BIN"; exit 1; }

echo "== tc-3) 논TTY/파이프 회귀: ESC·CR 부재 + 계약 토큰 유지 =="
TUI_PIPE="$(printf '1\n1\n' | timeout 20 "$BIN" test --dry-run --no-template 2>&1)"; PIPE_RC=$?
assert_exit "$PIPE_RC" 0 "tc3_파이프_dryrun_exit0"
assert_plain_bytes "$TUI_PIPE" "tc3_파이프_escape_CR_부재"
assert_contains "$TUI_PIPE" "Select agent kind" "tc3_계약토큰_Select_agent_kind"
assert_contains "$TUI_PIPE" "Select AI team preset" "tc3_계약토큰_Select_AI_team_preset"
assert_contains "$TUI_PIPE" "preset=dev" "tc3_계약토큰_preset=dev"

CI_PIPE="$(CI=1 printf '1\n1\n' | CI=1 timeout 20 "$BIN" test --dry-run --no-template 2>&1)"
assert_plain_bytes "$CI_PIPE" "tc3_CI_escape_CR_부재"

KO_PIPE="$(printf '1\n1\n' | HERDR_TEAM_LANG=ko timeout 20 "$BIN" test --dry-run --no-template 2>&1)"
assert_plain_bytes "$KO_PIPE" "tc3_ko_escape_CR_부재"
assert_contains "$KO_PIPE" "AI 팀 프리셋을 선택하세요" "tc3_ko_프리셋_메뉴_제목"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
