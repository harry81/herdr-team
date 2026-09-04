#!/usr/bin/env bash
# install.sh — herdr-team-setup 쉬운 설치 (심볼릭 링크 + PATH 등록)
#
# 수행 내용:
#   1) ~/bin/herdr-team-setup -> <repo>/bin/herdr-team-setup
#   2) ~/bin/hts              -> <repo>/bin/herdr-team-setup (단축 명령어)
#   3) ~/templates/agent-team -> <repo>/templates
#      (스크립트 기본 TEMPLATE_DIR이 ~/templates/agent-team 이므로,
#       이 링크 하나로 외부 템플릿 복사 경로가 바로 동작합니다.)
#   4) ~/.bashrc, ~/.zshrc에 ~/bin PATH 등록 (marker 주석, 멱등)
#
# 사용법:
#   ./install.sh                        # 저장소 클론 후 실행
#   curl -fsSL <url>/install.sh | bash  # 온라인 원라이너 (아래 Env 참조)
#
# 환경변수:
#   HERDR_TEAM_REPO      저장소 경로 강제 지정 (파이프 설치 시 권장)
#   HERDR_TEAM_REPO_URL  저장소가 없을 때 자동 클론할 git URL (원라이너용)
set -euo pipefail

DEFAULT_DEST="$HOME/work/projects/herdr-team-setup"

# 저장소 디렉토리 감지: 명시 env > 스크립트 위치 > 자동 클론 순.
# curl|bash 파이프 실행 시 BASH_SOURCE가 비어 있으므로 env/클론 경로가 필수다.
resolve_repo() {
  if [[ -n "${HERDR_TEAM_REPO:-}" && -f "${HERDR_TEAM_REPO}/bin/herdr-team-setup" ]]; then
    printf '%s' "${HERDR_TEAM_REPO}"
    return 0
  fi
  local src="${BASH_SOURCE[0]:-}"
  if [[ -n "$src" && -f "$src" ]]; then
    local d
    d="$(cd "$(dirname "$src")" && pwd)"
    if [[ -f "$d/bin/herdr-team-setup" ]]; then
      printf '%s' "$d"
      return 0
    fi
  fi
  local dest="${HERDR_TEAM_REPO:-$DEFAULT_DEST}"
  if [[ -n "${HERDR_TEAM_REPO_URL:-}" ]]; then
    if [[ ! -f "$dest/bin/herdr-team-setup" ]]; then
      printf '[install] cloning %s -> %s\n' "$HERDR_TEAM_REPO_URL" "$dest" >&2
      git clone --depth 1 "$HERDR_TEAM_REPO_URL" "$dest" >&2
    fi
    if [[ -f "$dest/bin/herdr-team-setup" ]]; then
      printf '%s' "$dest"
      return 0
    fi
  fi
  return 1
}

REPO="$(resolve_repo || true)"
if [[ -z "$REPO" ]]; then
  cat >&2 <<'EOF'
[install] error: herdr-team-setup 저장소를 찾을 수 없습니다.
  - 파일 설치: 클론한 저장소에서 ./install.sh 실행, 또는
  - 파이프 설치: HERDR_TEAM_REPO=/path/to/repo curl ... | bash, 또는
  - HERDR_TEAM_REPO_URL 지정 시 자동 클론합니다.
EOF
  exit 1
fi

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

MARKER="# herdr-team-setup: add ~/bin to PATH"
ensure_path() {
  local rc="$1"
  if [[ ! -f "$rc" ]]; then
    : > "$rc"
  fi
  if grep -qF "$MARKER" "$rc" 2>/dev/null; then
    printf '[install] PATH 이미 등록됨: %s\n' "$rc"
    return
  fi
  {
    printf '\n%s\n' "$MARKER"
    printf 'case ":$PATH:" in *":$HOME/bin:"*) ;; *) export PATH="$HOME/bin:$PATH" ;; esac\n'
  } >> "$rc"
  printf '[install] PATH 등록: %s\n' "$rc"
}

link "$REPO/bin/herdr-team-setup" "$HOME/bin/herdr-team-setup"
link "$REPO/bin/herdr-team-setup" "$HOME/bin/hts"
link "$REPO/templates" "$HOME/templates/agent-team"

ensure_path "$HOME/.bashrc"
ensure_path "$HOME/.zshrc"

printf '[install] 완료. 확인: herdr-team-setup --help (또는 단축 명령: hts --help)\n'
