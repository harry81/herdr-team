#!/usr/bin/env bash
# tests/test_install.sh — install.sh 쉬운 설치 지원 TDD 검증
# 실행: bash tests/test_install.sh  (repo root에서)
# 임시 HOME fixture에서 실행하므로 실제 홈을 건드리지 않는다.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INST="$REPO/install.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

assert_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3 (missing: $2)"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}
assert_link() { # $1=link $2=target $3=label
  if [[ -L "$1" && "$(readlink "$1")" == "$2" ]]; then ok "$3";
  else bad "$3 (link=$1 -> $(readlink "$1" 2>/dev/null || echo MISSING), want=$2)"; fi
}

[[ -x "$INST" || -f "$INST" ]] || { printf 'FAIL: %s 없음\n' "$INST"; exit 1; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home"
mkdir -p "$HOME"

echo "== 1) 링크 생성 (herdr-team-setup, hts, templates) =="
HOME="$FIX/home" bash "$INST" >/dev/null 2>&1; INST_RC=$?
assert_exit "$INST_RC" 0 "install exit 0"
assert_link "$HOME/bin/herdr-team-setup" "$REPO/bin/herdr-team-setup" "link: ~/bin/herdr-team-setup"
assert_link "$HOME/bin/hts" "$REPO/bin/herdr-team-setup" "link: ~/bin/hts 단축 명령어"
assert_link "$HOME/templates/agent-team" "$REPO/templates" "link: ~/templates/agent-team"

echo "== 2) 셸 PATH 등록 멱등성 (.bashrc/.zshrc 1회만) =="
touch "$HOME/.bashrc" "$HOME/.zshrc"
HOME="$FIX/home" bash "$INST" >/dev/null 2>&1
HOME="$FIX/home" bash "$INST" >/dev/null 2>&1
for rc in .bashrc .zshrc; do
  n="$(grep -c 'herdr-team-setup' "$HOME/$rc" 2>/dev/null || true)"
  if [[ "$n" -eq 1 ]]; then ok "marker 1회: ~/$rc"; else bad "marker 1회: ~/$rc (count=$n)"; fi
done
# shellcheck disable=SC2016
assert_contains "$(cat "$HOME/.bashrc")" '$HOME/bin' 'PATH에 $HOME/bin 포함 (.bashrc)'

echo "== 3) 온라인 원라이너 파이프 실행 안전성 (curl | bash) =="
rm -rf "$FIX/pipehome" && mkdir -p "$FIX/pipehome"
# $0=bash 파이프 환경 시뮬레이션: 스크립트 본문을 stdin으로 주입
cat "$INST" | HOME="$FIX/pipehome" HERDR_TEAM_REPO="$REPO" bash >/dev/null 2>&1; PIPE_RC=$?
assert_exit "$PIPE_RC" 0 "pipe install exit 0"
assert_link "$FIX/pipehome/bin/herdr-team-setup" "$REPO/bin/herdr-team-setup" "pipe: ~/bin/herdr-team-setup"
assert_link "$FIX/pipehome/bin/hts" "$REPO/bin/herdr-team-setup" "pipe: ~/bin/hts"

echo "== 4) 배포 zip 빌드 (GitHub Releases용) =="
ZIP_OUT="$FIX/hts-pkg.zip"
bash "$REPO/scripts/build-zip.sh" --out "$ZIP_OUT" >/dev/null 2>&1; ZIP_RC=$?
assert_exit "$ZIP_RC" 0 "build-zip exit 0"
if [[ -f "$ZIP_OUT" ]]; then ok "zip 생성: $ZIP_OUT"; else bad "zip 생성: $ZIP_OUT"; fi
ZIP_LIST="$(python3 -m zipfile -l "$ZIP_OUT" 2>/dev/null || true)"
assert_contains "$ZIP_LIST" "bin/herdr-team-setup" "zip: 실행 스크립트 포함"
assert_contains "$ZIP_LIST" "windows/start-team.bat" "zip: Windows 런처 포함"
assert_contains "$ZIP_LIST" "README.md" "zip: README 포함"
assert_contains "$ZIP_LIST" "LICENSE" "zip: LICENSE 포함"
if printf '%s' "$ZIP_LIST" | grep -qE '(^|/)\.git/'; then bad "zip: .git 제외"; else ok "zip: .git 제외"; fi
if printf '%s' "$ZIP_LIST" | grep -qE '(^|/)tests/'; then bad "zip: tests 제외"; else ok "zip: tests 제외"; fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
