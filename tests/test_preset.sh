#!/usr/bin/env bash
# tests/test_preset.sh — preset(dev/app/biz) + TUI 메뉴 TDD 검증
# 실행: bash tests/test_preset.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
WRAP="$REPO/bin/herdr-team-setup"
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
assert_equal() { # $1=actual $2=expected $3=label
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (outputs differ)"; fi
}

# --- 0) 전제: 스크립트/템플릿 존재 ---
[[ -x "$BIN" ]] || { printf 'FAIL: %s not executable\n' "$BIN"; exit 1; }

echo "== 1) --help에 preset/TUI 옵션 문서화 =="
HELP_OUT="$("$BIN" --help 2>&1 || true)"
assert_contains "$HELP_OUT" "--preset" "help: --preset 문서화"
assert_contains "$HELP_OUT" "--list-presets" "help: --list-presets 문서화"
assert_contains "$HELP_OUT" "--no-interactive" "help: --no-interactive 문서화"

echo "== 2) --list-presets: dev/app/biz 나열 =="
LIST_OUT="$("$BIN" --list-presets 2>&1)"; LIST_RC=$?
assert_exit "$LIST_RC" 0 "--list-presets exit 0"
assert_contains "$LIST_OUT" "dev" "--list-presets에 dev"
assert_contains "$LIST_OUT" "app" "--list-presets에 app"
assert_contains "$LIST_OUT" "biz" "--list-presets에 biz"

echo "== 3) templates/{dev,app,biz} 프리셋 템플릿 존재 =="
for p in dev app biz; do
  if [[ -f "$REPO/templates/$p/preset.conf" ]]; then ok "templates/$p/preset.conf 존재";
  else bad "templates/$p/preset.conf 존재"; fi
  if [[ -f "$REPO/templates/$p/AGENTS.md" ]]; then ok "templates/$p/AGENTS.md 존재";
  else bad "templates/$p/AGENTS.md 존재"; fi
done
# preset.conf 역할 정의 검증
assert_contains "$(cat "$REPO/templates/dev/preset.conf" 2>/dev/null)" "planner" "dev preset roles에 planner"
assert_contains "$(cat "$REPO/templates/dev/preset.conf" 2>/dev/null)" "worker" "dev preset roles에 worker"
assert_contains "$(cat "$REPO/templates/dev/preset.conf" 2>/dev/null)" "taskmanager" "dev preset roles에 taskmanager"
assert_contains "$(cat "$REPO/templates/biz/preset.conf" 2>/dev/null)" "researcher" "biz preset roles에 researcher (역할 일반화 증거)"

echo "== 4) --preset dev --dry-run (비대화형) =="
DEV_OUT="$("$BIN" test --preset dev --dry-run --no-template --no-interactive 2>&1)"; DEV_RC=$?
assert_exit "$DEV_RC" 0 "dev dry-run exit 0"
assert_contains "$DEV_OUT" "preset=dev" "dev dry-run에 preset=dev 표시"
assert_contains "$DEV_OUT" "test-taskmanager" "dev dry-run에 test-taskmanager"
assert_contains "$DEV_OUT" "test-planner" "dev dry-run에 test-planner"
assert_contains "$DEV_OUT" "test-worker" "dev dry-run에 test-worker"
assert_contains "$DEV_OUT" "test-reviewer" "dev dry-run에 test-reviewer"

echo "== 5) --preset app --dry-run =="
APP_OUT="$("$BIN" test --preset app --dry-run --no-template --no-interactive 2>&1)"; APP_RC=$?
assert_exit "$APP_RC" 0 "app dry-run exit 0"
assert_contains "$APP_OUT" "preset=app" "app dry-run에 preset=app 표시"
assert_contains "$APP_OUT" "test-taskmanager" "app dry-run에 test-taskmanager"
assert_contains "$APP_OUT" "test-planner" "app dry-run에 test-planner"

echo "== 6) --preset biz --dry-run (역할 일반화: researcher) =="
BIZ_OUT="$("$BIN" test --preset biz --dry-run --no-template --no-interactive 2>&1)"; BIZ_RC=$?
assert_exit "$BIZ_RC" 0 "biz dry-run exit 0"
assert_contains "$BIZ_OUT" "preset=biz" "biz dry-run에 preset=biz 표시"
assert_contains "$BIZ_OUT" "test-taskmanager" "biz dry-run에 test-taskmanager (일반화)"
assert_contains "$BIZ_OUT" "test-researcher" "biz dry-run에 test-researcher (일반화)"
assert_not_contains "$BIZ_OUT" "test-worker" "biz dry-run에 test-worker 없음 (일반화)"

echo "== 7) 잘못된 preset은 실패 =="
"$BIN" test --preset bogus --dry-run --no-template --no-interactive >/dev/null 2>&1; BAD_RC=$?
if [[ "$BAD_RC" -ne 0 ]]; then ok "invalid preset exit != 0"; else bad "invalid preset exit != 0 (rc=0)"; fi
BAD_OUT="$("$BIN" test --preset bogus --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$BAD_OUT" "bogus" "invalid preset 에러에 입력값 표시"

echo "== 8) --no-interactive 무프리셋은 기본값(dev)으로 비대화형 진행 =="
DEF_OUT="$(printf '' | timeout 15 "$BIN" test --dry-run --no-template --no-interactive 2>&1)"; DEF_RC=$?
assert_exit "$DEF_RC" 0 "--no-interactive 기본 dry-run exit 0"
assert_contains "$DEF_OUT" "preset=dev" "--no-interactive 기본 preset=dev"

echo "== 9) TUI 메뉴: stdin 선택으로 preset 결정 (비TTY 파이프) =="
# 메뉴에서 2번(app) 선택 시뮬레이션. TUI가 stdin을 읽어야 함.
TUI_OUT="$(printf '2\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"; TUI_RC=$?
assert_exit "$TUI_RC" 0 "TUI 선택 dry-run exit 0"
assert_contains "$TUI_OUT" "preset=app" "TUI에서 2번 선택 → preset=app"

echo "== 10) 하위호환: 기존 옵션 조합 그대로 동작 =="
LEGACY_OUT="$(timeout 15 "$BIN" sd --dry-run --no-interactive 2>&1)"; LEGACY_RC=$?
assert_exit "$LEGACY_RC" 0 "legacy sd --dry-run exit 0"
assert_contains "$LEGACY_OUT" "prefix=sd" "legacy prefix=sd 유지"

echo "== 11) English-primary: help/TUI/LICENSE =="
assert_contains "$HELP_OUT" "Usage:" "help: English Usage header"
assert_contains "$HELP_OUT" "Presets" "help: English Presets section"
assert_contains "$HELP_OUT" "Software Development" "help: dev English label"
assert_contains "$HELP_OUT" "Solo App" "help: app English label"
assert_contains "$HELP_OUT" "Small Business" "help: biz English label"
assert_contains "$TUI_OUT" "Select [1-3/dev/app/biz]" "TUI: English-primary prompt"
assert_contains "$TUI_OUT" "Software Development" "TUI: dev English label"
if [[ -f "$REPO/LICENSE" ]]; then ok "LICENSE 존재"; else bad "LICENSE 존재"; fi
assert_contains "$(cat "$REPO/LICENSE" 2>/dev/null)" "MIT License" "LICENSE: MIT"
assert_contains "$(cat "$REPO/LICENSE" 2>/dev/null)" "Herdr Team Contributors" "LICENSE: copyright holder"
if [[ -f "$REPO/README.ko.md" ]]; then ok "README.ko.md 존재"; else bad "README.ko.md 존재"; fi
assert_contains "$(head -5 "$REPO/README.md" 2>/dev/null)" "herdr-team" "README.md: English primary doc"

echo "== 12) 레거시 래퍼 하위호환 (herdr-team-setup → herdr-team) =="
if [[ -x "$WRAP" ]]; then ok "래퍼 존재·실행가능: bin/herdr-team-setup"; else bad "래퍼 존재·실행가능: bin/herdr-team-setup"; fi
WRAP_HELP="$("$WRAP" --help 2>&1 || true)"
assert_contains "$WRAP_HELP" "herdr-team" "wrapper help: 정본 언급"
WRAP_OUT="$(printf '' | timeout 15 "$WRAP" test --preset dev --dry-run --no-template --no-interactive 2>&1)"; WRAP_RC=$?
assert_exit "$WRAP_RC" 0 "wrapper dry-run exit 0"
CANON_OUT="$(printf '' | timeout 15 "$BIN" test --preset dev --dry-run --no-template --no-interactive 2>&1)"
assert_equal "$WRAP_OUT" "$CANON_OUT" "wrapper 출력 == 정본 출력"

echo "== 13) README 랜딩 가드레일 (Hero/QuickStart/Advanced) =="
if [[ "$(head -1 "$REPO/README.md")" == "# herdr-team" ]]; then ok "README L1: # herdr-team"; else bad "README L1: # herdr-team"; fi
assert_contains "$(cat "$REPO/README.md")" "## Quick Start" "README: ## Quick Start"
assert_contains "$(cat "$REPO/README.md")" "## Advanced" "README: ## Advanced"
assert_contains "$(cat "$REPO/README.md")" "start-team.bat" "README: start-team.bat 토큰"
assert_contains "$(cat "$REPO/README.md")" "curl" "README: curl 토큰"
assert_contains "$(cat "$REPO/README.md")" "hts" "README: hts 토큰"

echo "== 14) GitHub SEO 가드레일 (배지·실URL·헬스파일) =="
README_TXT="$(cat "$REPO/README.md")"
assert_contains "$README_TXT" "shields.io" "README: shields.io 배지"
assert_contains "$README_TXT" "license" "README: License 배지"
assert_contains "$README_TXT" "PRs Welcome" "README: PRs Welcome 배지"
assert_contains "$README_TXT" "https://raw.githubusercontent.com/harry81/herdr-team/main/install.sh" "README: 실제 install.sh URL"
assert_contains "$(cat "$REPO/README.ko.md")" "https://raw.githubusercontent.com/harry81/herdr-team/main/install.sh" "README.ko: 실제 install.sh URL"
for hf in ".github/workflows/ci.yml" ".github/ISSUE_TEMPLATE/bug_report.yml" ".github/ISSUE_TEMPLATE/feature_request.yml" ".github/PULL_REQUEST_TEMPLATE.md" "CONTRIBUTING.md" "SECURITY.md" "scripts/repo-meta.sh"; do
  if [[ -f "$REPO/$hf" ]]; then ok "존재: $hf"; else bad "존재: $hf"; fi
done

echo "== 15) 에이전트 종류(Kind) TUI 및 CLI/ENV 테스트 =="
# --kind 옵션 반영
KIND_OPT_OUT="$("$BIN" test --kind claude --dry-run --no-template --no-interactive 2>&1)"
assert_contains "$KIND_OPT_OUT" "kind=claude" "CLI: --kind claude 반영"
assert_contains "$KIND_OPT_OUT" "--kind claude" "CLI: herdr agent start에 --kind claude"

# HERDR_TEAM_KIND 환경변수 반영
KIND_ENV_OUT="$(HERDR_TEAM_KIND=codex "$BIN" test --dry-run --no-template --no-interactive 2>&1)"
assert_contains "$KIND_ENV_OUT" "kind=codex" "ENV: HERDR_TEAM_KIND=codex 반영"
assert_contains "$KIND_ENV_OUT" "--kind codex" "ENV: herdr agent start에 --kind codex"

# TUI 2단계: preset(1=dev) + kind(2=claude) 파이프 시뮬레이션
TUI_KIND_OUT="$(printf '1\n2\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$TUI_KIND_OUT" "preset=dev" "TUI 2단계: dev 선택"
assert_contains "$TUI_KIND_OUT" "kind=claude" "TUI 2단계: claude 선택"
assert_contains "$TUI_KIND_OUT" "Select agent kind" "TUI: kind 프롬프트 출력"

# TUI 2단계: preset(app) + kind(3=codex) 파이프 시뮬레이션
TUI_KIND_OUT2="$(printf 'app\n3\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$TUI_KIND_OUT2" "preset=app" "TUI 2단계: app 선택"
assert_contains "$TUI_KIND_OUT2" "kind=codex" "TUI 2단계: codex 선택"

# 잘못된 kind 거부
BAD_KIND_OUT="$("$BIN" test --kind invalid_kind --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$BAD_KIND_OUT" "invalid_kind" "invalid kind 에러 출력"

echo "== 16) pane down 분할 균등 --ratio + resize JSON 누출 없음 =="
# dev(4역할) dry-run: down 분할 ratio 수열 1/(N-k+1) = 0.25 / 0.333333 / 0.5 (N=4)
assert_contains "$DEV_OUT" "--ratio 0.25" "dev down split #1 --ratio 0.25 (1/4 균등)"
assert_contains "$DEV_OUT" "--ratio 0.333333" "dev down split #2 --ratio 0.333333 (1/3 균등)"
assert_contains "$DEV_OUT" "--ratio 0.5" "dev down split #3 --ratio 0.5 (1/2 균등)"
# biz(4역할, researcher)도 동일 ratio 일반화
assert_contains "$BIZ_OUT" "--ratio 0.25" "biz down split #1 --ratio 0.25 (역할 일반화)"
assert_contains "$BIZ_OUT" "--ratio 0.333333" "biz down split #2 --ratio 0.333333 (역할 일반화)"
assert_contains "$BIZ_OUT" "--ratio 0.5" "biz down split #3 --ratio 0.5 (역할 일반화)"
# resize JSON stdout 누출/잔재 회귀: dry-run에는 resize 호출·best-effort 문구가 없어야 함
assert_not_contains "$DEV_OUT" "cli:pane:resize" "dry-run: cli:pane:resize JSON 누출 없음"
assert_not_contains "$DEV_OUT" "pane resize" "dry-run: herdr pane resize 호출 미표시"
assert_not_contains "$DEV_OUT" "균등화 best-effort" "dry-run: 기존 resize best-effort 문구 제거"
# help Layout도 ratio 기반 설명으로 갱신
assert_contains "$HELP_OUT" "--ratio" "help: Layout에 균등 --ratio 설명"

echo "== 17) opencode --agent 적용 (역할별 agent 강제) =="
# dev(4역할): herdr agent start ... -- --agent <prefix>-<role>
for r in taskmanager planner worker reviewer; do
  assert_contains "$DEV_OUT" "-- --agent test-$r" "dev: herdr agent start -- agent test-$r"
done
# biz: researcher는 --agent, worker는 없음 (역할 일반화 + kind 게이팅)
assert_contains "$BIZ_OUT" "-- --agent test-researcher" "biz: herdr agent start -- agent test-researcher"
assert_not_contains "$BIZ_OUT" "-- --agent test-worker" "biz: --agent test-worker 없음"
# codex(미지원 kind): --agent 미사용
assert_not_contains "$KIND_ENV_OUT" "--agent" "codex: --agent 미사용(kind 게이팅)"

echo "== 18) opencode agent 템플릿 + {{PREFIX}} 치환 설치 =="
for r in taskmanager planner worker reviewer researcher; do
  if [[ -f "$REPO/templates/opencode-agents/ROLE-$r.md" ]]; then ok "templates/opencode-agents/ROLE-$r.md 존재";
  else bad "templates/opencode-agents/ROLE-$r.md 존재"; fi
done
# dry-run(템플릿 단계 포함)에 .opencode/agents 설치 계획 출력
GEN_DRY="$("$BIN" test --preset dev --dry-run --no-interactive --no-start 2>&1)"
assert_contains "$GEN_DRY" ".opencode/agents/test-taskmanager.md" "dry-run: .opencode/agents 설치 계획"
# 실제 생성 (herdr stub + 임시 CWD, jq 필요)
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"; TMPCWD="$(mktemp -d)"; TMPCWD2="$(mktemp -d)"
  cat > "$STUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$STUB/herdr"
  PATH="$STUB:$PATH" "$BIN" testteam --preset dev --cwd "$TMPCWD" --template-dir "$REPO/templates" --no-interactive --no-start >/dev/null 2>&1
  for r in taskmanager planner worker reviewer; do
    if [[ -f "$TMPCWD/.opencode/agents/testteam-$r.md" ]]; then ok "생성: .opencode/agents/testteam-$r.md";
    else bad "생성: .opencode/agents/testteam-$r.md"; fi
  done
  if [[ -f "$TMPCWD/.opencode/agents/testteam-taskmanager.md" ]]; then
    TM="$(cat "$TMPCWD/.opencode/agents/testteam-taskmanager.md")"
    assert_contains "$TM" "mode: primary" "agent frontmatter: mode primary"
    assert_contains "$TM" "testteam-planner" "agent 본문: {{PREFIX}} 치환됨"
    assert_not_contains "$TM" "{{PREFIX}}" "agent 본문: 미치환 placeholder 없음"
  fi
  # biz: researcher agent 생성, worker agent 미생성
  PATH="$STUB:$PATH" "$BIN" testbiz --preset biz --cwd "$TMPCWD2" --template-dir "$REPO/templates" --no-interactive --no-start >/dev/null 2>&1
  if [[ -f "$TMPCWD2/.opencode/agents/testbiz-researcher.md" ]]; then ok "biz: researcher agent 생성";
  else bad "biz: researcher agent 생성"; fi
  if [[ ! -f "$TMPCWD2/.opencode/agents/testbiz-worker.md" ]]; then ok "biz: worker agent 미생성";
  else bad "biz: worker agent 미생성"; fi
  rm -rf "$STUB" "$TMPCWD" "$TMPCWD2"
else
  echo "SKIP: jq 없음 → opencode agent 생성 기능 테스트 생략"
fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
