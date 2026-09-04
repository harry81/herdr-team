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

CANON="$REPO/bin/herdr-team"

echo "== 1) 링크 생성 (herdr-team, ht, hts, herdr-team-setup) =="
HOME="$FIX/home" bash "$INST" >/dev/null 2>&1; INST_RC=$?
assert_exit "$INST_RC" 0 "install exit 0"
for name in herdr-team ht hts herdr-team-setup; do
  assert_link "$HOME/bin/$name" "$CANON" "link: ~/bin/$name"
done
assert_link "$HOME/templates/agent-team" "$REPO/templates" "link: ~/templates/agent-team"

echo "== 2) 셸 PATH 등록 멱등성 (.bashrc/.zshrc 1회만) =="
touch "$HOME/.bashrc" "$HOME/.zshrc"
HOME="$FIX/home" bash "$INST" >/dev/null 2>&1
HOME="$FIX/home" bash "$INST" >/dev/null 2>&1
for rc in .bashrc .zshrc; do
  n="$(grep -cF '# herdr-team:' "$HOME/$rc" 2>/dev/null || true)"
  if [[ "$n" -eq 1 ]]; then ok "marker 1회: ~/$rc"; else bad "marker 1회: ~/$rc (count=$n)"; fi
done
# shellcheck disable=SC2016
assert_contains "$(cat "$HOME/.bashrc")" '$HOME/bin' 'PATH에 $HOME/bin 포함 (.bashrc)'

echo "== 2b) 레거시 마커 마이그레이션 (herdr-team-setup → herdr-team) =="
rm -rf "$FIX/mig" && mkdir -p "$FIX/mig"
printf '# herdr-team-setup: add ~/bin to PATH\nexport PATH="$HOME/bin:$PATH"\n' > "$FIX/mig/.bashrc"
touch "$FIX/mig/.zshrc"
HOME="$FIX/mig" bash "$INST" >/dev/null 2>&1; MIG_RC=$?
assert_exit "$MIG_RC" 0 "migration install exit 0"
mig_new="$(grep -cF '# herdr-team:' "$FIX/mig/.bashrc" 2>/dev/null || true)"
mig_old="$(grep -c 'herdr-team-setup' "$FIX/mig/.bashrc" 2>/dev/null || true)"
if [[ "$mig_new" -eq 1 ]]; then ok "migration: 신 마커 1회"; else bad "migration: 신 마커 1회 (count=$mig_new)"; fi
if [[ "$mig_old" -eq 0 ]]; then ok "migration: 구 마커 제거"; else bad "migration: 구 마커 제거 (count=$mig_old)"; fi

echo "== 3) 온라인 원라이너 파이프 실행 안전성 (curl | bash) =="
rm -rf "$FIX/pipehome" && mkdir -p "$FIX/pipehome"
# $0=bash 파이프 환경 시뮬레이션: 스크립트 본문을 stdin으로 주입
cat "$INST" | HOME="$FIX/pipehome" HERDR_TEAM_REPO="$REPO" bash >/dev/null 2>&1; PIPE_RC=$?
assert_exit "$PIPE_RC" 0 "pipe install exit 0"
for name in herdr-team ht hts herdr-team-setup; do
  assert_link "$FIX/pipehome/bin/$name" "$CANON" "pipe: ~/bin/$name"
done

echo "== 4) 배포 zip 빌드 (GitHub Releases용) =="
ZIP_OUT="$FIX/hts-pkg.zip"
bash "$REPO/scripts/build-zip.sh" --out "$ZIP_OUT" >/dev/null 2>&1; ZIP_RC=$?
assert_exit "$ZIP_RC" 0 "build-zip exit 0"
if [[ -f "$ZIP_OUT" ]]; then ok "zip 생성: $ZIP_OUT"; else bad "zip 생성: $ZIP_OUT"; fi
ZIP_LIST="$(python3 -m zipfile -l "$ZIP_OUT" 2>/dev/null || true)"
assert_contains "$ZIP_LIST" "bin/herdr-team" "zip: 정본 스크립트 포함"
assert_contains "$ZIP_LIST" "bin/herdr-team-setup" "zip: 레거시 래퍼 포함"
assert_contains "$ZIP_LIST" "windows/start-team.bat" "zip: Windows 런처 포함"
assert_contains "$ZIP_LIST" "README.md" "zip: README 포함"
assert_contains "$ZIP_LIST" "LICENSE" "zip: LICENSE 포함"
if printf '%s' "$ZIP_LIST" | grep -qE '(^|/)\.git/'; then bad "zip: .git 제외"; else ok "zip: .git 제외"; fi
if printf '%s' "$ZIP_LIST" | grep -qE '(^|/)tests/'; then bad "zip: tests 제외"; else ok "zip: tests 제외"; fi

echo "== 4b) 기본 산출물명 herdr-team.zip 계열 =="
mkdir -p "$FIX/zipdef" && rm -f "$FIX/zipdef"/herdr-team-*.zip
(cd "$FIX/zipdef" && bash "$REPO/scripts/build-zip.sh" >/dev/null 2>&1); DEF_RC=$?
assert_exit "$DEF_RC" 0 "build-zip 기본 실행 exit 0"
if ls "$FIX/zipdef"/herdr-team-*.zip >/dev/null 2>&1; then ok "기본 산출물: herdr-team-*.zip"; else bad "기본 산출물: herdr-team-*.zip"; fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
