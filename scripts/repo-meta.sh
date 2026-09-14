#!/usr/bin/env bash
# scripts/repo-meta.sh — GitHub 저장소 메타데이터 원클릭 멱등 적용
#
# Description은 gh repo edit으로, Topics는 PUT /repos/{owner}/{repo}/topics 로
# 원자적 replace-all(선언 세트 수렴, 멱등)한다. topics 상한은 20개.
# gh 미설치 시에는 실행할 명령을 dry-run으로 출력하고 정상 종료한다.
#
# 사용법: bash scripts/repo-meta.sh [--repo OWNER/NAME] [--dry-run]
set -euo pipefail

REPO_SLUG="harry81/herdr-team"
DRY_RUN=0
DESC="Multi-agent orchestration for AI coding agents: one-command planner/worker/reviewer crew on the herdr terminal multiplexer. TDD, solo-app, small-biz presets."
TOPICS=(
  ai-agents multi-agent orchestration agent-orchestration coding-agents ai-agent
  opencode claude-code codex
  herdr terminal-multiplexer terminal tui cli
  developer-tools automation tdd shell windows wsl
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_SLUG="${2:?--repo에 owner/name이 필요합니다}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) printf 'Usage: repo-meta.sh [--repo OWNER/NAME] [--dry-run]\n'; exit 0 ;;
    *) echo "error: 알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done

# 사전 검증(guard): 원격 적용 전에 규칙 위반을 차단한다.
if (( ${#TOPICS[@]} > 20 )); then
  echo "error: topics 상한(20) 초과: ${#TOPICS[@]}개" >&2
  exit 1
fi
for t in "${TOPICS[@]}"; do
  if [[ ! "$t" =~ ^[a-z0-9-]{1,50}$ ]]; then
    echo "error: topic 규칙 위반(^[a-z0-9-]{1,50}\$): '$t'" >&2
    exit 1
  fi
done

print_plan() {
  printf '+ gh repo edit %s --description "%s"\n' "$REPO_SLUG" "$DESC"
  printf '+ gh api --method PUT repos/%s/topics' "$REPO_SLUG"
  printf ' -f "names[]=%s"' "${TOPICS[@]}"
  printf '\n'
  printf 'Description: %d자\n' "${#DESC}"
  printf 'Topics: %d개 (상한 20)\n' "${#TOPICS[@]}"
}

if [[ "$DRY_RUN" -eq 0 ]] && ! command -v gh >/dev/null 2>&1; then
  cat <<EOF
[repo-meta] 'gh' CLI가 없습니다. 아래 명령을 dry-run으로 출력합니다.
설치: https://cli.github.com/ → 'gh auth login' 후 재실행.

EOF
  print_plan
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_plan
else
  gh repo edit "$REPO_SLUG" --description "$DESC" >/dev/null
  put_args=()
  for t in "${TOPICS[@]}"; do
    put_args+=(-f "names[]=$t")
  done
  gh api --method PUT "repos/$REPO_SLUG/topics" "${put_args[@]}" >/dev/null
  printf '[repo-meta] 적용 완료: %s (description %d자, topics %d개 원자적 교체)\n' "$REPO_SLUG" "${#DESC}" "${#TOPICS[@]}"
fi
