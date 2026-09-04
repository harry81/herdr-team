#!/usr/bin/env bash
# scripts/repo-meta.sh — GitHub 저장소 메타데이터 원클릭 멱등 적용
#
# gh repo edit으로 160자 최적화 Description + Topics 14개를 적용한다.
# topics는 add-only(덧셈)라 재실행해도 안전하고, description은 동일 값이라 멱등하다.
# gh 미설치 시에는 실행할 명령을 dry-run으로 출력하고 정상 종료한다.
#
# 사용법: bash scripts/repo-meta.sh [--repo harry81/herdr-team] [--dry-run]
set -euo pipefail

REPO_SLUG="harry81/herdr-team"
DRY_RUN=0
DESC="One-command 4-pane AI crew for your terminal: plan, build and gate-check every change. Presets for solo apps, small biz ops, and TDD teams."
TOPICS=(
  ai-agents multi-agent orchestration terminal cli shell bash
  automation tdd developer-tools side-project small-business
  windows wsl
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_SLUG="${2:?--repo에 owner/name이 필요합니다}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) printf 'Usage: repo-meta.sh [--repo OWNER/NAME] [--dry-run]\n'; exit 0 ;;
    *) echo "error: 알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done

topic_args() {
  local t
  for t in "${TOPICS[@]}"; do printf ' --add-topic %s' "$t"; done
}

if [[ "$DRY_RUN" -eq 0 ]] && ! command -v gh >/dev/null 2>&1; then
  cat <<EOF
[repo-meta] 'gh' CLI가 없습니다. 아래 명령을 dry-run으로 출력합니다.
설치: https://cli.github.com/ → 'gh auth login' 후 재실행.

  gh repo edit ${REPO_SLUG} --description "${DESC}"$(topic_args)

Description: ${#DESC}자 (GitHub 권장 ≤160자)
Topics (${#TOPICS[@]}개): ${TOPICS[*]}
EOF
  exit 0
fi

# shellcheck disable=SC2086
if [[ "$DRY_RUN" -eq 1 ]]; then
  # shellcheck disable=SC2086
  printf '+ gh repo edit %s --description %s' "$REPO_SLUG" "$DESC"
  printf ' --add-topic %s' "${TOPICS[@]}"
  printf '\n'
else
  gh repo edit "$REPO_SLUG" --description "$DESC" >/dev/null
  for t in "${TOPICS[@]}"; do
    gh repo edit "$REPO_SLUG" --add-topic "$t" >/dev/null
  done
  printf '[repo-meta] 적용 완료: %s (topics %d개)\n' "$REPO_SLUG" "${#TOPICS[@]}"
fi
