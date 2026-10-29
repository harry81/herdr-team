#!/usr/bin/env bash
# tests/test_safe_onboarding.sh — 온보딩 안전성 (R1 gitignore 멱등 / R2 루트 AGENTS.md 보호 / R3 충돌 가드)
# 명세: docs/specs/safe-onboarding-spec.md §4 (TC-GI 1~10, TC-BA 11~18, TC-GD 19~25)
#       + 리뷰 반송 수정 고정: E1 심링크, E2 CRLF, E8 마커 문구, 루트만 존재, 정본 순수성
# 실행: bash tests/test_safe_onboarding.sh  (repo root에서)
# 인프라 계약 스위트: 로케일 고정(en). 로케일 커버리지는 tests/test_tui_i18n.sh 담당.
export HERDR_TEAM_LANG=en
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

assert_contains() { # $1=output $2=needle $3=label
  if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi
}
assert_not_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}
assert_equal() { # $1=actual $2=expected $3=label
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (outputs differ)"; fi
}

[[ -x "$BIN" ]] || { printf 'FAIL: %s not executable\n' "$BIN"; exit 1; }

TMPDIRS=()
cleanup() {
  local d
  for d in ${TMPDIRS+"${TMPDIRS[@]}"}; do chmod -R u+w "$d" 2>/dev/null; rm -rf "$d" 2>/dev/null; done
}
trap cleanup EXIT

mk_tmp() { local d; d="$(mktemp -d)"; TMPDIRS+=("$d"); printf '%s' "$d"; }
mk_git() { local d; d="$(mk_tmp)"; git -C "$d" init -q; printf '%s' "$d"; }

# 실제 실행(템플릿 단계만: pane 분할/precheck 생략). 출력은 stdout+stderr.
iso_pre() { # $1=preset $2=cwd [extra...]
  local pre="$1" cwd="$2"; shift 2
  "$BIN" iso --preset "$pre" --cwd "$cwd" --template-dir "$REPO/templates" \
    --no-interactive --templates-only "$@" 2>&1
}
iso() { local cwd="$1"; shift; iso_pre dev "$cwd" "$@"; }

block_of() { awk '/herdr-team:managed BEGIN/{f=1;next} /herdr-team:managed END/{f=0} f' "$1"; }
backup_count() { if [[ -d "$1/.herdr-team/backup" ]]; then ls -1 "$1/.herdr-team/backup" | wc -l | tr -d ' '; else printf '0'; fi; }
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }
# 모든 프리셋 정본에서 사용자 토큰 등장 수 합계 (정본 오염 검출: 파일 전체 기준)
canon_occurrences() { grep -cF -- "$2" "$1"/agents/*/AGENTS.md 2>/dev/null | awk -F: '{s+=$2} END{print s+0}'; }

echo "== TC-GI 1) .gitignore 부재 → 생성 (마커 + 2항목) =="
D="$(mk_git)"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "gi1_exit_0"
if [[ -f "$D/.gitignore" ]]; then ok "gi1_파일_생성"; else bad "gi1_파일_생성"; fi
assert_equal "$(cat "$D/.gitignore" 2>/dev/null)" $'# herdr-team\n.herdr-team/\n.opencode/' "gi1_3행_마커+2항목"
assert_equal "$(wc -l < "$D/.gitignore" 2>/dev/null | tr -d ' ')" "3" "gi1_정확히_3행"

echo "== TC-GI 2) 기존 .gitignore 보존 + 부족분만 append =="
D="$(mk_git)"; printf 'node_modules/\n' > "$D/.gitignore"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "gi2_exit_0"
assert_equal "$(head -n1 "$D/.gitignore")" "node_modules/" "gi2_기존_행_보존"
assert_equal "$(cat "$D/.gitignore")" $'node_modules/\n# herdr-team\n.herdr-team/\n.opencode/' "gi2_신규_3행_append"
assert_equal "$(tail -c1 "$D/.gitignore" | od -An -c | tr -d ' ')" '\n' "gi2_끝개행_정상"

echo "== TC-GI 3) 멱등: 2회 실행해도 항목별 1회 =="
D="$(mk_git)"; printf 'node_modules/\n' > "$D/.gitignore"
iso "$D" >/dev/null 2>&1; iso "$D" >/dev/null 2>&1
assert_equal "$(grep -cF '# herdr-team' "$D/.gitignore")" "1" "gi3_마커_1회"
assert_equal "$(grep -cF '.herdr-team/' "$D/.gitignore")" "1" "gi3_herdr-team_1회"
assert_equal "$(grep -cF '.opencode/' "$D/.gitignore")" "1" "gi3_opencode_1회"
assert_equal "$(cat "$D/.gitignore")" $'node_modules/\n# herdr-team\n.herdr-team/\n.opencode/' "gi3_2회차_무변경"

echo "== TC-GI 4) 후행 슬래시 없는 기존 항목(.opencode)은 중복 추가 없음 =="
D="$(mk_git)"; printf '.opencode\n' > "$D/.gitignore"
iso "$D" >/dev/null 2>&1
assert_equal "$(grep -cE '^\.opencode/?$' "$D/.gitignore")" "1" "gi4_opencode_중복없음"
assert_equal "$(grep -cF '.herdr-team/' "$D/.gitignore")" "1" "gi4_herdr-team_추가"

echo "== TC-GI 5) 끝 개행 없는 파일 → 기존 바이트 보존 + 개행 보강 =="
D="$(mk_git)"; printf 'x' > "$D/.gitignore"
iso "$D" >/dev/null 2>&1
assert_equal "$(cat "$D/.gitignore")" $'x\n# herdr-team\n.herdr-team/\n.opencode/' "gi5_바이트보존_개행보강"

echo "== TC-GI 6) --dry-run: 계획만 출력, 쓰기 0 =="
D="$(mk_git)"
OUT="$(iso "$D" --dry-run)"
assert_contains "$OUT" "+ gitignore:" "gi6_계획_라인"
assert_contains "$OUT" "append" "gi6_append_계획"
if [[ ! -e "$D/.gitignore" ]]; then ok "gi6_dryrun_미생성"; else bad "gi6_dryrun_미생성"; fi

echo "== TC-GI 7) dry-run 계획 ↔ 실실행 일치 =="
D="$(mk_git)"; printf '# herdr-team\n.herdr-team/\n.opencode/\n' > "$D/.gitignore"
GI_BEFORE="$(cat "$D/.gitignore")"
OUT="$(iso "$D" --dry-run)"
assert_contains "$OUT" "이미 있음" "gi7_이미있음_표시"
assert_not_contains "$OUT" "gitignore: append" "gi7_append_미출력"
iso "$D" >/dev/null 2>&1
assert_equal "$(cat "$D/.gitignore")" "$GI_BEFORE" "gi7_실실행_무변경"
D="$(mk_git)"; : > "$D/.gitignore"
OUT="$(iso "$D" --dry-run)"
assert_contains "$OUT" "gitignore: append" "gi7_부족분_append_계획"
iso "$D" >/dev/null 2>&1
assert_equal "$(grep -cF '.herdr-team/' "$D/.gitignore")" "1" "gi7_실실행_append_일치"

echo "== TC-GI 8) 비 git 디렉터리 → 보강 생략 =="
D="$(mk_tmp)"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "gi8_exit_0"
assert_contains "$OUT" "생략" "gi8_생략_log"
if [[ ! -e "$D/.gitignore" ]]; then ok "gi8_gitignore_미생성"; else bad "gi8_gitignore_미생성"; fi

echo "== TC-GI 9) --no-gitignore =="
D="$(mk_git)"
OUT="$(iso "$D" --no-gitignore)"; RC=$?
assert_exit "$RC" 0 "gi9_exit_0"
if [[ ! -e "$D/.gitignore" ]]; then ok "gi9_무시등록_없음"; else bad "gi9_무시등록_없음"; fi
HELP="$("$BIN" --help 2>&1)"
assert_contains "$HELP" "--no-gitignore" "gi9_help_문서화"
assert_contains "$HELP" "--no-backup" "gi9_help_no_backup_문서화"

echo "== TC-GI 10) 쓰기 불가 디렉터리 → 명확 에러 + 원본 무손상 =="
D="$(mk_git)"; printf 'keep\n' > "$D/.gitignore"; chmod 500 "$D"
OUT="$(iso "$D")"; RC=$?
chmod 700 "$D"
if [[ "$RC" -ne 0 ]]; then ok "gi10_에러_exit≠0"; else bad "gi10_에러_exit≠0 (rc=0)"; fi
assert_contains "$OUT" ".gitignore" "gi10_에러_경로_명시"
assert_equal "$(cat "$D/.gitignore")" "keep" "gi10_원본_무손상"

echo "== TC-GI 11) E1: .gitignore 심링크 → 링크 보존 + 대상 파일 기록 =="
D="$(mk_git)"; mkdir -p "$D/dot"
printf 'MINE/\n' > "$D/dot/gitignore"; ln -s dot/gitignore "$D/.gitignore"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "gi11_exit_0"
if [[ -L "$D/.gitignore" ]]; then ok "gi11_심링크_보존"; else bad "gi11_심링크_보존"; fi
assert_equal "$(head -n1 "$D/dot/gitignore")" "MINE/" "gi11_대상_기존내용_보존"
assert_equal "$(grep -cF '.herdr-team/' "$D/dot/gitignore")" "1" "gi11_대상파일_기록"
assert_equal "$(grep -cF '.opencode/' "$D/dot/gitignore")" "1" "gi11_대상파일_기록_opencode"
assert_equal "$(ls -A "$D" | grep -c 'herdr-team.tmp' || true)" "0" "gi11_tmp_잔여물_없음"

echo "== TC-GI 12) 기존 파일 권한 보존 (0600) =="
D="$(mk_git)"; printf 'x/\n' > "$D/.gitignore"; chmod 600 "$D/.gitignore"
iso "$D" >/dev/null 2>&1
assert_equal "$(file_mode "$D/.gitignore")" "600" "gi12_권한_보존"

echo "== TC-GI 13) 선행 공백 항목 → 중복 추가 없음 (E3) =="
D="$(mk_git)"; printf '  .opencode   \n' > "$D/.gitignore"
iso "$D" >/dev/null 2>&1
assert_equal "$(grep -cF '.opencode' "$D/.gitignore")" "1" "gi13_선행공백_중복없음"
assert_equal "$(grep -cF '.herdr-team/' "$D/.gitignore")" "1" "gi13_부족분_추가"

echo "== TC-GI 14) E2: 기존 CRLF 보존 + append 는 LF =="
D="$(mk_git)"; printf 'node_modules/\r\n' > "$D/.gitignore"
iso "$D" >/dev/null 2>&1
assert_equal "$(head -n1 "$D/.gitignore" | od -An -c | tr -d ' ')" 'node_modules/\r\n' "gi14_기존행_바이트보존"
assert_equal "$(grep -c $'\r' "$D/.gitignore")" "1" "gi14_CRLF_1행만"
assert_equal "$(tail -n3 "$D/.gitignore" | grep -c $'\r' || true)" "0" "gi14_append_LF"

echo "== TC-GI 15) F-04: .gitignore 가 디렉터리 → 명확 에러 + 쓰기 0 =="
D="$(mk_git)"; mkdir "$D/.gitignore"
OUT="$(iso "$D")"; RC=$?
if [[ "$RC" -ne 0 ]]; then ok "gi15_디렉터리_exit≠0"; else bad "gi15_디렉터리_exit≠0 (rc=0)"; fi
assert_contains "$OUT" "$D/.gitignore" "gi15_경로_명시"
assert_contains "$OUT" "is not a regular file" "gi15_에러문구"
assert_equal "$(ls -A "$D/.gitignore" | wc -l | tr -d ' ')" "0" "gi15_잔여물_없음"
assert_not_contains "$OUT" "gitignore 보강:" "gi15_성공로그_없음"

echo "== TC-BA 11) 신규 설치: 마커로 감싼 canon, 백업 없음 =="
D="$(mk_tmp)"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "ba11_exit_0"
ROOT_TXT="$(cat "$D/AGENTS.md" 2>/dev/null)"
assert_contains "$ROOT_TXT" "<!-- herdr-team:managed BEGIN (preset=dev) -->" "ba11_begin_마커"
assert_contains "$ROOT_TXT" "<!-- herdr-team:managed END -->" "ba11_end_마커"
if cmp -s "$D/AGENTS.md" "$D/agents/dev/AGENTS.md"; then ok "ba11_루트==canon"; else bad "ba11_루트==canon"; fi
assert_equal "$(backup_count "$D")" "0" "ba11_백업_없음"

echo "== TC-BA 12) 사용자 본문 보존 + 관리 섹션 삽입 (active 없음) =="
D="$(mk_tmp)"; mkdir -p "$D/agents/dev"
printf 'USER-BODY-LINE\n' > "$D/AGENTS.md"
printf 'CANON-STALE-LINE\n' > "$D/agents/dev/AGENTS.md"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "ba12_exit_0"
ROOT_TXT="$(cat "$D/AGENTS.md")"
assert_contains "$ROOT_TXT" "USER-BODY-LINE" "ba12_사용자본문_보존"
assert_contains "$ROOT_TXT" "<!-- herdr-team:managed BEGIN (preset=dev) -->" "ba12_관리섹션_삽입"
assert_equal "$(block_of "$D/AGENTS.md")" "CANON-STALE-LINE" "ba12_블록은_canon_내용"
assert_equal "$(grep -cF 'USER-BODY-LINE' "$D/AGENTS.md")" "1" "ba12_사용자본문_중복없음"

echo "== TC-BA 13) 덮어쓰기 케이스 → 타임스탬프 백업 = 실행 전 원본 (독립 픽스처) =="
D="$(mk_tmp)"; mkdir -p "$D/agents/dev"
printf 'USER-BODY-LINE\n' > "$D/AGENTS.md"
printf 'CANON-STALE-LINE\n' > "$D/agents/dev/AGENTS.md"
ROOT_BEFORE="$(cat "$D/AGENTS.md")"
iso "$D" >/dev/null 2>&1
assert_equal "$(backup_count "$D")" "1" "ba13_백업_1개"
BAK="$(ls -1 "$D/.herdr-team/backup"/AGENTS.md.*.bak 2>/dev/null | head -n1)"
if [[ -n "$BAK" ]]; then ok "ba13_백업_명명규칙"; else bad "ba13_백업_명명규칙"; fi
assert_equal "$(cat "$BAK" 2>/dev/null)" "$ROOT_BEFORE" "ba13_백업==실행전_루트"

echo "== TC-BA 14) 재실행(같은 preset) → 루트 바이트 동일, 백업 추가 없음 =="
D="$(mk_tmp)"
iso "$D" >/dev/null 2>&1
cp "$D/AGENTS.md" "$D/.root.snapshot"
iso "$D" >/dev/null 2>&1
if cmp -s "$D/AGENTS.md" "$D/.root.snapshot"; then ok "ba14_루트_불변"; else bad "ba14_루트_불변"; fi
assert_equal "$(grep -cF '<!-- herdr-team:managed BEGIN' "$D/AGENTS.md")" "1" "ba14_마커_1쌍"
assert_equal "$(backup_count "$D")" "0" "ba14_백업_추가없음"

echo "== TC-BA 15) preset 전환: 관리 섹션 내부만 write-back + 왕복 복원 =="
D="$(mk_tmp)"
iso "$D" >/dev/null 2>&1
DEV_BLOCK_BEFORE="$(block_of "$D/agents/dev/AGENTS.md")"
printf 'USER-BODY-LINE\n' >> "$D/AGENTS.md"
OUT="$(iso_pre mkt "$D")"; RC=$?
assert_exit "$RC" 0 "ba15_전환_exit_0"
assert_equal "$(grep -cF 'USER-BODY-LINE' "$D/agents/dev/AGENTS.md")" "0" "ba15_dev정본_본문_미오염"
assert_equal "$(block_of "$D/agents/dev/AGENTS.md")" "$DEV_BLOCK_BEFORE" "ba15_dev정본_내부_보존"
assert_contains "$(cat "$D/AGENTS.md")" "USER-BODY-LINE" "ba15_루트본문_유지"
assert_contains "$(cat "$D/AGENTS.md")" "managed BEGIN (preset=mkt)" "ba15_mkt_블록_치환"
iso_pre dev "$D" >/dev/null 2>&1
assert_equal "$(block_of "$D/agents/dev/AGENTS.md")" "$DEV_BLOCK_BEFORE" "ba15_왕복_정본_복원"
assert_contains "$(cat "$D/AGENTS.md")" "USER-BODY-LINE" "ba15_왕복_본문_유지"

echo "== TC-BA 16) --force: 백업 선행 후 재시딩 =="
D="$(mk_tmp)"
iso "$D" >/dev/null 2>&1
printf 'USER-BODY-LINE\n' >> "$D/AGENTS.md"
ROOT_BEFORE="$(cat "$D/AGENTS.md")"
OUT="$(iso "$D" --force)"; RC=$?
assert_exit "$RC" 0 "ba16_force_exit_0"
assert_equal "$(backup_count "$D")" "1" "ba16_force_백업_선행"
assert_equal "$(cat "$D/.herdr-team/backup"/AGENTS.md.*.bak 2>/dev/null)" "$ROOT_BEFORE" "ba16_백업==실행전_루트"
assert_contains "$(cat "$D/AGENTS.md")" "USER-BODY-LINE" "ba16_force_본문_보존"

echo "== TC-BA 17) --no-backup: 백업 없이 병합 =="
D="$(mk_tmp)"; mkdir -p "$D/agents/dev"
printf 'USER-BODY-LINE\n' > "$D/AGENTS.md"
printf 'CANON-STALE-LINE\n' > "$D/agents/dev/AGENTS.md"
iso "$D" --no-backup >/dev/null 2>&1
assert_equal "$(backup_count "$D")" "0" "ba17_백업_없음"
assert_contains "$(cat "$D/AGENTS.md")" "USER-BODY-LINE" "ba17_병합_진행"

echo "== TC-BA 18) 마커 2쌍 → exit 2 + 쓰기 0 =="
D="$(mk_tmp)"; mkdir -p "$D/agents/dev"
printf 'CANON\n' > "$D/agents/dev/AGENTS.md"
cat > "$D/AGENTS.md" <<'EOF'
<!-- herdr-team:managed BEGIN (preset=dev) -->
A
<!-- herdr-team:managed END -->
<!-- herdr-team:managed BEGIN (preset=mkt) -->
B
<!-- herdr-team:managed END -->
EOF
cp "$D/AGENTS.md" "$D/.root.snapshot"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 2 "ba18_exit_2"
assert_contains "$OUT" "managed-section marker" "ba18_경고_마커"
if cmp -s "$D/AGENTS.md" "$D/.root.snapshot"; then ok "ba18_쓰기0"; else bad "ba18_쓰기0"; fi
assert_equal "$(backup_count "$D")" "0" "ba18_백업_없음"

echo "== TC-BA 19) F-05: 루트만 존재(canon 부재) → 관리 섹션 삽입 + 정본 순수 =="
D="$(mk_tmp)"; printf 'USER BODY ORIGINAL\n' > "$D/AGENTS.md"
ROOT_BEFORE="$(cat "$D/AGENTS.md")"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "ba19_루트만_exit_0"
assert_equal "$(grep -cF 'USER BODY ORIGINAL' "$D/AGENTS.md")" "1" "ba19_본문_1회보존"
assert_equal "$(grep -cxF '<!-- herdr-team:managed BEGIN (preset=dev) -->' "$D/AGENTS.md")" "1" "ba19_관리섹션_삽입"
assert_contains "$(cat "$D/agents/dev/AGENTS.md")" "managed BEGIN (preset=dev)" "ba19_정본_마커시딩"
assert_equal "$(canon_occurrences "$D" 'USER BODY ORIGINAL')" "0" "ba19_정본_본문_미오염"
assert_equal "$(backup_count "$D")" "1" "ba19_백업_생성"
assert_equal "$(cat "$D/.herdr-team/backup"/AGENTS.md.*.bak)" "$ROOT_BEFORE" "ba19_백업_원본"
assert_equal "$(block_of "$D/AGENTS.md")" "$(block_of "$D/agents/dev/AGENTS.md")" "ba19_블록==정본내부"

echo "== TC-BA 20) F-02: 전환 후 정본 전체 파일에 사용자 본문 없음 =="
D="$(mk_tmp)"
iso "$D" >/dev/null 2>&1
printf 'LOCAL-ONLY-BODY\n' >> "$D/AGENTS.md"
iso_pre mkt "$D" >/dev/null 2>&1
assert_equal "$(canon_occurrences "$D" 'LOCAL-ONLY-BODY')" "0" "ba20_정본_오염없음"
assert_equal "$(grep -cF 'LOCAL-ONLY-BODY' "$D/AGENTS.md")" "1" "ba20_루트_본문_1회"
assert_equal "$(grep -cxF '<!-- herdr-team:managed BEGIN (preset=mkt) -->' "$D/AGENTS.md")" "1" "ba20_mkt_마커_1쌍"
assert_equal "$(canon_occurrences "$D" 'LOCAL-ONLY-BODY')" "0" "ba20_재확인_오염없음"

echo "== TC-BA 21) F-07: 변경 없는 --force 도 백업 선행 =="
D="$(mk_tmp)"
iso "$D" >/dev/null 2>&1
assert_equal "$(backup_count "$D")" "0" "ba21_사전_백업없음"
iso "$D" --force >/dev/null 2>&1
assert_equal "$(backup_count "$D")" "1" "ba21_force_무변경_백업생성"

echo "== TC-BA 22) E5/F-01: 루트 AGENTS.md 심링크 보존 + 대상 갱신 =="
D="$(mk_tmp)"
iso "$D" >/dev/null 2>&1
mkdir -p "$D/dot"; mv "$D/AGENTS.md" "$D/dot/AGENTS.md"; ln -s dot/AGENTS.md "$D/AGENTS.md"
printf 'DOTFILE NOTE\n' >> "$D/dot/AGENTS.md"
iso_pre mkt "$D" >/dev/null 2>&1; RC=$?
assert_exit "$RC" 0 "ba22_심링크_전환_exit_0"
if [[ -L "$D/AGENTS.md" ]]; then ok "ba22_심링크_보존"; else bad "ba22_심링크_보존"; fi
assert_contains "$(cat "$D/dot/AGENTS.md")" "DOTFILE NOTE" "ba22_대상_본문보존"
assert_contains "$(cat "$D/dot/AGENTS.md")" "managed BEGIN (preset=mkt)" "ba22_대상_블록치환"
assert_equal "$(canon_occurrences "$D" 'DOTFILE NOTE')" "0" "ba22_정본_오염없음"

echo "== TC-GD 19) AGENTS.md + agents.md 공존 → exit 2 + 쓰기 0 =="
D="$(mk_tmp)"
printf 'root\n' > "$D/AGENTS.md"
printf 'lower\n' > "$D/agents.md"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 2 "gd19_exit_2"
assert_contains "$OUT" "$D/AGENTS.md" "gd19_경로_AGENTS.md_명시"
assert_contains "$OUT" "$D/agents.md" "gd19_경로_agents.md_명시"
if [[ ! -e "$D/agents" && ! -e "$D/.herdr-team" && ! -e "$D/.opencode" ]]; then ok "gd19_어떤_쓰기도_없음"; else bad "gd19_어떤_쓰기도_없음"; fi
assert_equal "$(cat "$D/AGENTS.md")" "root" "gd19_루트_무변경"

echo "== TC-GD 20) 원인 제거 후 재실행 정상 =="
rm "$D/agents.md"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "gd20_재실행_exit_0"
if [[ -d "$D/agents/dev" ]]; then ok "gd20_정상_시딩"; else bad "gd20_정상_시딩"; fi

echo "== TC-GD 21) agents 가 일반 파일 → exit 2 + 명확 메시지 =="
D="$(mk_tmp)"; printf 'blocker\n' > "$D/agents"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 2 "gd21_exit_2"
assert_contains "$OUT" "$D/agents is not a directory" "gd21_절대경로_문구"
assert_not_contains "$OUT" "mkdir:" "gd21_원시_mkdir_에러_없음"

echo "== TC-GD 22) agents/<preset> 이 일반 파일 → exit 2 =="
D="$(mk_tmp)"; mkdir -p "$D/agents"; printf 'blocker\n' > "$D/agents/dev"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 2 "gd22_exit_2"
assert_contains "$OUT" "$D/agents/dev is not a directory" "gd22_경로_문구"

echo "== TC-GD 23) .herdr-team 이 일반 파일 → exit 2 =="
D="$(mk_tmp)"; printf 'blocker\n' > "$D/.herdr-team"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 2 "gd23_exit_2"
assert_contains "$OUT" "$D/.herdr-team is not a directory" "gd23_경로_문구"

echo "== TC-GD 24) agents 심링크-디렉터리 → 정상 통과 =="
D="$(mk_tmp)"; mkdir -p "$D/real-agents"; ln -s real-agents "$D/agents"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "gd24_심링크_exit_0"
if [[ -f "$D/real-agents/dev/iso-worker.md" ]]; then ok "gd24_심링크_경유_시딩"; else bad "gd24_심링크_경유_시딩"; fi

echo "== TC-GD 25) dry-run 가드 검출: exit 2 + 쓰기 0 =="
D="$(mk_tmp)"; printf 'blocker\n' > "$D/.herdr-team"
OUT="$(iso "$D" --dry-run)"; RC=$?
assert_exit "$RC" 2 "gd25_dryrun_exit_2"
if [[ ! -e "$D/agents" && ! -e "$D/.opencode" ]]; then ok "gd25_dryrun_쓰기0"; else bad "gd25_dryrun_쓰기0"; fi

echo "== TC-GD 26) E8/F-03: 마커 문구 언급·문서 예시는 마커로 오인하지 않음 =="
D="$(mk_tmp)"; iso "$D" >/dev/null 2>&1
printf '\n관리 섹션은 <!-- herdr-team:managed BEGIN (preset=dev) --> 로 시작합니다.\n' >> "$D/AGENTS.md"
printf '```\n예시: <!-- herdr-team:managed BEGIN (preset=dev) --> ... <!-- herdr-team:managed END -->\n```\n' >> "$D/AGENTS.md"
CP="$(cat "$D/AGENTS.md")"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 0 "gd26_문구언급_exit_0"
assert_equal "$(cat "$D/AGENTS.md")" "$CP" "gd26_문서예시_무시_무변경"
assert_equal "$(grep -cxF '<!-- herdr-team:managed BEGIN (preset=dev) -->' "$D/AGENTS.md")" "1" "gd26_마커_1쌍"
assert_not_contains "$OUT" "2쌍" "gd26_오탐_경고없음"

echo "== TC-GD 27) F-03: BEGIN/END 불일치 → exit 2 + 쌍 안내 =="
D="$(mk_tmp)"; mkdir -p "$D/agents/dev"
printf 'CANON\n' > "$D/agents/dev/AGENTS.md"
printf 'BODY\n<!-- herdr-team:managed BEGIN (preset=dev) -->\n' > "$D/AGENTS.md"
cp "$D/AGENTS.md" "$D/.root.snapshot"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 2 "gd27_불일치_exit_2"
assert_contains "$OUT" "mismatched managed-section markers" "gd27_불일치_안내"
if cmp -s "$D/AGENTS.md" "$D/.root.snapshot"; then ok "gd27_쓰기0"; else bad "gd27_쓰기0"; fi

echo "== TC-GD 28) F-06: 소문자 agents.md 만 존재 → 1회차 선제 차단 (2회차 데드락 방지) =="
D="$(mk_tmp)"; printf 'lower body\n' > "$D/agents.md"
OUT="$(iso "$D")"; RC=$?
assert_exit "$RC" 2 "gd28_1회차_차단_exit_2"
assert_contains "$OUT" "$D/agents.md" "gd28_경로_명시"
if [[ ! -e "$D/AGENTS.md" ]]; then ok "gd28_AGENTS_md_미생성"; else bad "gd28_AGENTS_md_미생성"; fi
if [[ ! -e "$D/agents" ]]; then ok "gd28_agents_미생성"; else bad "gd28_agents_미생성"; fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
