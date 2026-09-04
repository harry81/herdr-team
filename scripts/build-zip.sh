#!/usr/bin/env bash
# scripts/build-zip.sh — GitHub Releases용 배포 아카이브 생성
#
# 일반 사용자가 압축만 풀면 바로 쓸 수 있는 패키지를 만든다.
# 제외: .git (버전 관리), tests (개발용 테스트)
#
# 사용법: bash scripts/build-zip.sh [--out dist/herdr-team-setup.zip]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
OUT="herdr-team-setup-$(date +%Y%m%d).zip"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:?--out에 경로가 필요합니다}"; shift 2 ;;
    -h|--help) printf 'Usage: build-zip.sh [--out PATH]\n'; exit 0 ;;
    *) echo "error: 알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done

case "$OUT" in
  /*) ;; # absolute
  *) OUT="$PWD/$OUT" ;;
esac
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

if command -v zip >/dev/null 2>&1; then
  (cd "$REPO" && zip -qr "$OUT" . -x '.git/*' 'tests/*')
else
  # zip 미설치 환경 폴백 (python3 내장 zipfile)
  python3 - "$REPO" "$OUT" <<'EOF'
import os, sys, zipfile
repo, out = sys.argv[1], sys.argv[2]
skip = ('.git/', 'tests/')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(repo):
        rel = os.path.relpath(root, repo)
        if rel == '.':
            rel = ''
        else:
            rel += '/'
        if rel.startswith(skip):
            dirs[:] = []
            continue
        dirs[:] = sorted(d for d in dirs if (rel + d + '/') not in skip and not (rel + d).startswith('.git'))
        for f in sorted(files):
            p = os.path.join(root, f)
            z.write(p, rel + f)
EOF
fi

printf '[build-zip] 패키지 생성: %s\n' "$OUT"
