#!/usr/bin/env bash
# tests/test_herdr_precheck.sh — bin/herdr-team herdr 사전 점검 TDD 검증
# 실행: bash tests/test_herdr_precheck.sh  (repo root에서)
# herdr 부재 환경은 표준 PATH의 실행 파일을 심볼릭하되 herdr만 제외한 shim PATH로 만든다.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
BASH_BIN="$(command -v bash)"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

assert_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3 (missing: $2)"; fi
}
assert_not_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}

# herdr 부재 PATH shim: PATH상 모든 실행 파일을 심볼릭하되 herdr 이름은 제외.
make_no_herdr_path() {
  local d dir f base
  d="$(mktemp -d)"
  local oldifs="$IFS"; IFS=':'
  for dir in $PATH; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*; do
      [[ -e "$f" && -x "$f" ]] || continue
      base="${f##*/}"
      [[ "$base" == "herdr" ]] && continue
      [[ -e "$d/$base" ]] || ln -s "$f" "$d/$base"
    done
  done
  IFS="$oldifs"
  printf '%s' "$d"
}

NO_HERDR="$(make_no_herdr_path)"
STUB="$(mktemp -d)"
CWD_A="$(mktemp -d)"
CWD_B="$(mktemp -d)"
CWD_C="$(mktemp -d)"
trap 'rm -rf "$NO_HERDR" "$STUB" "$CWD_A" "$CWD_B" "$CWD_C"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$STUB/herdr"; chmod +x "$STUB/herdr"

echo "== 1) herdr 부재 + --precheck → exit 127 + 안내(stderr) =="
OUT="$(PATH="$NO_HERDR" "$BASH_BIN" "$BIN" --precheck 2>&1)"; RC=$?
assert_exit "$RC" 127 "herdr 부재 precheck exit 127"
assert_contains "$OUT" "herdr" "안내: herdr 언급"
assert_contains "$OUT" "https://herdr.dev/install.sh" "안내: Unix 설치 URL"
assert_contains "$OUT" "https://herdr.dev/install.ps1" "안내: Windows 설치 URL"
assert_contains "$OUT" "HERDR_TEAM_SKIP_CHECK" "안내: 우회 플래그"

echo "== 2) herdr 스텁 PATH + --precheck → exit 0 (ERROR 없음) =="
OUT2="$(PATH="$STUB:$PATH" "$BASH_BIN" "$BIN" --precheck 2>&1)"; RC2=$?
assert_exit "$RC2" 0 "herdr 존재 precheck exit 0"
assert_not_contains "$OUT2" "ERROR" "herdr 존재 시 ERROR 없음"

echo "== 3) HERDR_TEAM_SKIP_CHECK=1 + herdr 부재 → exit 0 + WARN =="
OUT3="$(HERDR_TEAM_SKIP_CHECK=1 PATH="$NO_HERDR" "$BASH_BIN" "$BIN" --precheck 2>&1)"; RC3=$?
assert_exit "$RC3" 0 "SKIP_CHECK 우회 exit 0"
assert_contains "$OUT3" "WARN" "SKIP_CHECK 우회 시 WARN"

echo "== 4) --dry-run / --templates-only --dry-run + herdr 부재 → exit 0 =="
OUT4="$(PATH="$NO_HERDR" "$BASH_BIN" "$BIN" --cwd "$CWD_B" --preset dev --no-interactive --dry-run 2>&1)"; RC4=$?
assert_exit "$RC4" 0 "dry-run herdr 부재 exit 0"
OUT5="$(PATH="$NO_HERDR" "$BASH_BIN" "$BIN" --cwd "$CWD_C" --preset dev --no-interactive --templates-only --dry-run 2>&1)"; RC5=$?
assert_exit "$RC5" 0 "templates-only dry-run herdr 부재 exit 0"

echo "== 5) 비-dry-run + herdr 부재(--no-start) → exit 127 + 쓰기 0 =="
OUT6="$(PATH="$NO_HERDR" "$BASH_BIN" "$BIN" --cwd "$CWD_A" --preset dev --no-interactive --no-start 2>&1)"; RC6=$?
assert_exit "$RC6" 127 "비-dry-run herdr 부재 fail-fast 127"
if [[ ! -e "$CWD_A/agents" && ! -e "$CWD_A/.herdr-team" && ! -e "$CWD_A/AGENTS.md" ]]; then
  ok "fail-fast: 임시 CWD 쓰기 0 (agents/ .herdr-team/ AGENTS.md 미생성)"
else
  bad "fail-fast: 임시 CWD 쓰기 0 (생성물 발견)"
fi

echo "== 6) --help 에 --precheck 문서화 =="
OUT7="$("$BASH_BIN" "$BIN" --help 2>&1)"
assert_contains "$OUT7" "--precheck" "help: --precheck 문서화"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
