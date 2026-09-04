#!/usr/bin/env bash
# tests/test_windows_launcher.sh — Windows 일반 사용자 원클릭 런처 TDD 검증
# 실행: bash tests/test_windows_launcher.sh  (repo root에서)
# (.bat은 Linux에서 실행 불가 → 구조 토큰/CRLF/인용 검증 + 전달 명령 시뮬레이션 실행)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team-setup"
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
has_crlf() { # $1=file → CRLF 포함 시 0
  grep -q $'\r' "$1" 2>/dev/null
}

CORE="$REPO/windows/start-team.bat"
SHORTCUT="$REPO/windows/create-shortcut.bat"
ROOT_CORE="$REPO/start-team.bat"

echo "== 1) windows/ 런처 영문 파일명만 존재 (한글 파일명 제거) =="
for f in "$CORE" "$SHORTCUT"; do
  if [[ -f "$f" ]]; then ok "존재: ${f#$REPO/}"; else bad "존재: ${f#$REPO/}"; fi
done
if [[ ! -e "$REPO/windows/AI-팀-시작하기.bat" ]]; then ok "삭제 확인: windows/AI-팀-시작하기.bat 없음"; else bad "삭제 확인: windows/AI-팀-시작하기.bat 없음 (잔존)"; fi
if [[ -z "$(ls "$REPO/windows" | grep -P '[^\x00-\x7F]' 2>/dev/null)" ]]; then ok "windows/: 비ASCII 파일명 없음"; else bad "windows/: 비ASCII 파일명 없음"; fi

echo "== 2) 루트 바로가기/래퍼 존재 (사용자 가시성) =="
if [[ -f "$ROOT_CORE" ]]; then ok "존재: ${ROOT_CORE#$REPO/}"; else bad "존재: ${ROOT_CORE#$REPO/}"; fi
if [[ ! -e "$REPO/AI-팀-시작하기.bat" ]]; then ok "삭제 확인: AI-팀-시작하기.bat 없음"; else bad "삭제 확인: AI-팀-시작하기.bat 없음 (잔존)"; fi
assert_contains "$(cat "$ROOT_CORE" 2>/dev/null)" 'windows\start-team.bat' "루트 start-team.bat → windows/ 위임"

echo "== 3) CRLF 개행 (cmd.exe 한글/배치 안정성) =="
for f in "$CORE" "$SHORTCUT" "$ROOT_CORE"; do
  if [[ -f "$f" ]] && has_crlf "$f"; then ok "CRLF: ${f#$REPO/}"; else bad "CRLF: ${f#$REPO/}"; fi
done

echo "== 4) 토큰 전달 (preset/인자/env 패스스루) =="
CORE_TXT="$(cat "$CORE" 2>/dev/null)"
assert_contains "$CORE_TXT" "--preset" "core: --preset 토큰"
assert_contains "$CORE_TXT" "%*" "core: %* 인자 패스스루"
assert_contains "$CORE_TXT" "HERDR_TEAM_PRESET" "core: HERDR_TEAM_PRESET env"
assert_contains "$CORE_TXT" "HERDR_TEAM_DRYRUN" "core: 시뮬레이션(HERDR_TEAM_DRYRUN) 분기"
assert_contains "$CORE_TXT" "HERDR_TEAM_NOPAUSE" "core: HERDR_TEAM_NOPAUSE 분기"
assert_contains "$CORE_TXT" "chcp 65001" "core: UTF-8 코드페이지"
assert_contains "$CORE_TXT" "wsl" "core: WSL 경유 실행"
assert_contains "$CORE_TXT" "wslpath" "core: wslpath 경로 변환 (수동 매핑 금지)"
SHORT_TXT="$(cat "$SHORTCUT" 2>/dev/null)"
assert_contains "$SHORT_TXT" "powershell" "shortcut: powershell 사용"
assert_contains "$SHORT_TXT" "WScript.Shell" "shortcut: WScript.Shell"
assert_contains "$SHORT_TXT" "CreateShortcut" "shortcut: CreateShortcut"
assert_contains "$SHORT_TXT" "start-team.bat" "shortcut: start-team 대상"
assert_not_contains "$SHORT_TXT" "AI-팀-시작하기" "shortcut: 한글 파일명 참조 없음"

echo "== 5) 인용 (공백/한글 경로 안정성) =="
assert_contains "$CORE_TXT" '"%~dp0' "core: %~dp0 인용"
assert_contains "$CORE_TXT" 'set "' "core: 안전 대입(set \"VAR=...\")"
assert_not_contains "$CORE_TXT" 'C:\Users\' "core: 하드코딩 사용자 경로 없음"
assert_contains "$SHORT_TXT" 'USERPROFILE' "shortcut: USERPROFILE 기반 경로"

echo "== 6) 시뮬레이션: 런처가 구성하는 전달 명령이 유효함 =="
# 런처는 최종적으로 `bin/herdr-team-setup [--preset P] [args...] --dry-run`을 구성한다.
# Linux에서는 동일 명령을 직접 실행해 유효성을 검증한다.
SIM_OUT="$("$BIN" wintest --preset biz --dry-run --no-template --no-interactive 2>&1)"; SIM_RC=$?
assert_exit "$SIM_RC" 0 "sim: biz dry-run exit 0"
assert_contains "$SIM_OUT" "preset=biz" "sim: preset=biz 전달"
assert_contains "$SIM_OUT" "wintest-researcher" "sim: biz 역할 토큰"
SIM2_OUT="$(printf '' | "$BIN" wintest --dry-run --no-template --no-interactive 2>&1)"; SIM2_RC=$?
assert_exit "$SIM2_RC" 0 "sim: 기본 preset dry-run exit 0"
assert_contains "$SIM2_OUT" "preset=dev" "sim: 기본 preset=dev"

echo "== 7) English-primary: bat 메뉴/프롬프트 =="
assert_contains "$CORE_TXT" "Software Development" "core: dev English label"
assert_contains "$CORE_TXT" "Solo App" "core: app English label"
assert_contains "$CORE_TXT" "Small Business" "core: biz English label"
assert_contains "$CORE_TXT" "Select [1-3" "core: English-primary prompt"

echo "== 8) 의존성 점검 위저드 (Git/WSL 부재 시) =="
assert_contains "$CORE_TXT" "winget" "core: winget 설치 유도"
assert_contains "$CORE_TXT" "HERDR_TEAM_SKIP_CHECK" "core: HERDR_TEAM_SKIP_CHECK 플래그"
assert_contains "$CORE_TXT" "wsl --install" "core: wsl --install 안내"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
