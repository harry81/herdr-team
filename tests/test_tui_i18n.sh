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

echo "== tc-1) 카탈로그 패리티 (MSG_KEYS ↔ _msg_en/_msg_ko) =="
MSG_KEYS_SRC="$(grep -m1 '^MSG_KEYS=' "$BIN" || true)"
if [[ -z "$MSG_KEYS_SRC" ]]; then
  bad "tc1_MSG_KEYS_정의"
else
  ok "tc1_MSG_KEYS_정의"
  eval "$MSG_KEYS_SRC"
  CAT_SRC="$(mktemp)"
  {
    sed -n '/^_msg_en() {/,/^}/p' "$BIN"
    sed -n '/^_msg_ko() {/,/^}/p' "$BIN"
  } > "$CAT_SRC"
  if [[ -s "$CAT_SRC" ]]; then ok "tc1_카탈로그_추출"; else bad "tc1_카탈로그_추출"; fi
  for k in $MSG_KEYS; do
    EN_K="$(bash -c 'source "$1"; _msg_en "$2" A B C D' _ "$CAT_SRC" "$k" 2>/dev/null)"
    KO_K="$(bash -c 'source "$1"; _msg_ko "$2" A B C D' _ "$CAT_SRC" "$k" 2>/dev/null)"
    if [[ -n "$EN_K" ]]; then ok "tc1_en_$k"; else bad "tc1_en_$k (empty)"; fi
    if [[ -n "$KO_K" ]]; then ok "tc1_ko_$k"; else bad "tc1_ko_$k (empty)"; fi
    case "$EN_K$KO_K" in
      *%s*|*%d*) bad "tc1_서식_미치환_$k ($EN_K|$KO_K)" ;;
      *) ok "tc1_서식_해소_$k" ;;
    esac
  done
  rm -f "$CAT_SRC"
fi

echo "== tc-2) 로케일 결정 규칙 =="
LOC_SRC="$(mktemp)"
sed -n '/^ht_detect_locale() {/,/^}/p' "$BIN" > "$LOC_SRC"
if [[ -s "$LOC_SRC" ]]; then ok "tc2_ht_detect_locale_추출"; else bad "tc2_ht_detect_locale_추출"; fi
loc_of() { # $@=NAME=VALUE (지정 안 한 변수는 unset)
  ( unset HERDR_TEAM_LANG LC_ALL LANG
    local a; for a in "$@"; do export "$a"; done
    . "$LOC_SRC"; ht_detect_locale ) 2>/dev/null
}
assert_equal "$(loc_of)"                                   "en" "tc2_무설정_en"
assert_equal "$(loc_of HERDR_TEAM_LANG=ko)"                "ko" "tc2_HERDR_TEAM_LANG_ko"
assert_equal "$(loc_of LANG=ko_KR.UTF-8)"                  "ko" "tc2_LANG_ko"
assert_equal "$(loc_of LC_ALL=ko_KR.UTF-8 LANG=en_US.UTF-8)" "ko" "tc2_LC_ALL_ko_우선"
assert_equal "$(loc_of HERDR_TEAM_LANG=ko LANG=en_US.UTF-8)" "ko" "tc2_HERDR_TEAM_LANG_우선"
assert_equal "$(loc_of HERDR_TEAM_LANG=fr)"                "en" "tc2_미지원_값_en폴백"
assert_equal "$(loc_of LANG=en_US.UTF-8)"                  "en" "tc2_LANG_en"

echo "== tc-2b) 미지원 HERDR_TEAM_LANG → en 폴백 + WARN 1회 (e2e) =="
FR_OUT="$(HERDR_TEAM_LANG=fr timeout 20 "$BIN" --version 2>&1)"; FR_RC=$?
assert_exit "$FR_RC" 0 "tc2b_미지원로케일_exit0"
assert_contains "$FR_OUT" "WARN" "tc2b_미지원로케일_WARN"
assert_equal "$(printf '%s\n' "$FR_OUT" | grep -c 'WARN')" "1" "tc2b_WARN_1회"
assert_contains "$FR_OUT" "herdr-team v" "tc2b_version_정상"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
