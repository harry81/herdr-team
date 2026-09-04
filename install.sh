#!/usr/bin/env bash
# install.sh — herdr-team-setup 심볼릭 링크 설치
#
# 수행 내용:
#   1) ~/bin/herdr-team-setup -> <repo>/bin/herdr-team-setup
#   2) ~/templates/agent-team -> <repo>/templates
#      (스크립트 기본 TEMPLATE_DIR이 ~/templates/agent-team 이므로,
#       이 링크 하나로 외부 템플릿 복사 경로가 바로 동작합니다.)
#
# 사용법: ./install.sh  (이 저장소 클론/복사 후 1회 실행)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/bin" "$HOME/templates"

link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    printf '[install] 이미 설치됨: %s\n' "$dst"
    return
  fi
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    printf '[install] 기존 실파일 백업: %s -> %s.bak\n' "$dst" "$dst"
    mv "$dst" "$dst.bak"
  fi
  ln -sfn "$src" "$dst"
  printf '[install] 링크 생성: %s -> %s\n' "$dst" "$src"
}

link "$REPO/bin/herdr-team-setup" "$HOME/bin/herdr-team-setup"
link "$REPO/templates" "$HOME/templates/agent-team"

printf '[install] 완료. 확인: herdr-team-setup --help\n'
