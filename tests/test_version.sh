#!/usr/bin/env bash
# tests/test_version.sh — VERSION 단일 정본 + 두 바이너리 버전 노출 TDD 검증
# 실행: bash tests/test_version.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
WATCH="$REPO/bin/herdr-watcher"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

assert_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}
assert_equal() { # $1=actual $2=expected $3=label
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got='$1', want='$2')"; fi
}

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

echo "== 1) VERSION 단일 정본 존재 + SemVer 형식 =="
if [[ -f "$REPO/VERSION" ]]; then ok "VERSION 파일 존재"; else bad "VERSION 파일 존재"; fi
VER_RAW="$(cat "$REPO/VERSION" 2>/dev/null || true)"
VER="$(printf '%s' "$VER_RAW" | tr -d '[:space:]')"
if [[ -n "$VER" ]] && printf '%s' "$VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok "VERSION SemVer 형식 ($VER)"
else
  bad "VERSION SemVer 형식 (got='$VER_RAW')"
fi

echo "== 2) herdr-team 버전 노출 (--version/-v/--help) =="
V_OUT="$("$BIN" --version 2>&1)"; V_RC=$?
assert_exit "$V_RC" 0 "herdr-team --version exit 0"
assert_equal "$V_OUT" "herdr-team v$VER" "herdr-team --version 문자열"
SV_OUT="$("$BIN" -v 2>&1)"; SV_RC=$?
assert_exit "$SV_RC" 0 "herdr-team -v exit 0"
assert_equal "$SV_OUT" "herdr-team v$VER" "herdr-team -v 문자열"
H_OUT="$("$BIN" --help 2>&1)"; H_RC=$?
assert_exit "$H_RC" 0 "herdr-team --help exit 0"
assert_equal "$(printf '%s\n' "$H_OUT" | head -n1)" "herdr-team v$VER" "herdr-team --help 첫 줄 버전"
assert_contains "$H_OUT" "-v, --version" "herdr-team --help: -v, --version 문서화"

echo "== 3) herdr-watcher 버전 노출 (--version/-v/--help) =="
WV_OUT="$("$WATCH" --version 2>&1)"; WV_RC=$?
assert_exit "$WV_RC" 0 "watcher --version exit 0"
assert_equal "$WV_OUT" "herdr-watcher v$VER" "watcher --version 문자열"
WSV_OUT="$("$WATCH" -v 2>&1)"; WSV_RC=$?
assert_exit "$WSV_RC" 0 "watcher -v exit 0"
assert_equal "$WSV_OUT" "herdr-watcher v$VER" "watcher -v 문자열"
WH_OUT="$("$WATCH" --help 2>&1)"; WH_RC=$?
assert_exit "$WH_RC" 0 "watcher --help exit 0"
assert_equal "$(printf '%s\n' "$WH_OUT" | head -n1)" "herdr-watcher v$VER" "watcher --help 첫 줄 버전(상단)"
assert_contains "$WH_OUT" "--version" "watcher --help: --version 문서화"

echo "== 4) 실행 배너 (watcher --all --max-iterations 1 / herdr-team --dry-run) =="
WRUN_OUT="$("$WATCH" --all --max-iterations 1 2>/dev/null)"
assert_equal "$(printf '%s\n' "$WRUN_OUT" | head -n1)" "herdr-watcher v$VER" "watcher 실행 첫 줄 버전"
assert_contains "$WRUN_OUT" "Herdr Agent Watcher 가동" "watcher 실행: 기존 가동 문구 유지"
BRUN_OUT="$("$BIN" test --dry-run --no-template --no-interactive 2>/dev/null)"; BRUN_RC=$?
assert_exit "$BRUN_RC" 0 "herdr-team --dry-run exit 0"
assert_equal "$(printf '%s\n' "$BRUN_OUT" | head -n1)" "herdr-team v$VER" "herdr-team --dry-run 첫 stdout 줄 버전"

echo "== 5) VERSION 부재 시 폴백 (두 바이너리 vunknown, exit 0) =="
NOV="$FIX/nover"
mkdir -p "$NOV/bin"
cp "$BIN" "$NOV/bin/herdr-team"
cp "$WATCH" "$NOV/bin/herdr-watcher"
chmod +x "$NOV/bin/herdr-team" "$NOV/bin/herdr-watcher"
rm -f "$NOV/VERSION"
NF_OUT="$("$NOV/bin/herdr-team" --version 2>&1)"; NF_RC=$?
assert_exit "$NF_RC" 0 "폴백: herdr-team --version exit 0"
assert_equal "$NF_OUT" "herdr-team vunknown" "폴백: herdr-team vunknown"
NFW_OUT="$("$NOV/bin/herdr-watcher" --version 2>&1)"; NFW_RC=$?
assert_exit "$NFW_RC" 0 "폴백: watcher --version exit 0"
assert_equal "$NFW_OUT" "herdr-watcher vunknown" "폴백: watcher vunknown"

echo "== 6) 두 바이너리 버전 문자열 == VERSION 정본 =="
assert_equal "$("$BIN" --version 2>&1)" "herdr-team v$(cat "$REPO/VERSION")" "herdr-team 버전 == VERSION"
assert_equal "$("$WATCH" --version 2>&1)" "herdr-watcher v$(cat "$REPO/VERSION")" "watcher 버전 == VERSION"

echo "== 7) 심볼릭 실행 시 실제 스크립트 경로 해석 (readlink -f) =="
SLBIN="$FIX/symbin"
mkdir -p "$SLBIN"
ln -sf "$BIN" "$SLBIN/herdr-team"
ln -sf "$WATCH" "$SLBIN/herdr-watcher"
SL_OUT="$("$SLBIN/herdr-team" --version 2>&1)"; SL_RC=$?
assert_exit "$SL_RC" 0 "심볼릭 herdr-team --version exit 0"
assert_equal "$SL_OUT" "herdr-team v$VER" "심볼릭 herdr-team 버전 해석"
SLW_OUT="$("$SLBIN/herdr-watcher" --version 2>&1)"; SLW_RC=$?
assert_exit "$SLW_RC" 0 "심볼릭 watcher --version exit 0"
assert_equal "$SLW_OUT" "herdr-watcher v$VER" "심볼릭 watcher 버전 해석"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
