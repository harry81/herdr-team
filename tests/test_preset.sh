#!/usr/bin/env bash
# tests/test_preset.sh — preset(dev/research/biz/mkt/creator) + TUI 메뉴 TDD 검증
# 실행: bash tests/test_preset.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
WRAP="$REPO/bin/herdr-team-setup"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

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

# --- 0) 전제: 스크립트/템플릿 존재 ---
[[ -x "$BIN" ]] || { printf 'FAIL: %s not executable\n' "$BIN"; exit 1; }

echo "== 1) --help에 preset/TUI 옵션 문서화 =="
HELP_OUT="$("$BIN" --help 2>&1 || true)"
assert_contains "$HELP_OUT" "--preset" "help: --preset 문서화"
assert_contains "$HELP_OUT" "--layout" "help: --layout 문서화"
assert_contains "$HELP_OUT" "--list-presets" "help: --list-presets 문서화"
assert_contains "$HELP_OUT" "--no-interactive" "help: --no-interactive 문서화"

echo "== 2) --list-presets: 5종 나열 (app 미노출) =="
LIST_OUT="$("$BIN" --list-presets 2>&1)"; LIST_RC=$?
assert_exit "$LIST_RC" 0 "list_presets_5종_나열: exit 0"
for p in dev research biz mkt creator; do
  assert_contains "$LIST_OUT" "$p" "list_presets_5종_나열: $p"
done
assert_not_contains "$LIST_OUT" "app" "list_presets_app_미노출"
if [[ "$(printf '%s\n' "$LIST_OUT" | head -n1)" == dev* ]]; then ok "list_presets_순서_dev우선"; else bad "list_presets_순서_dev우선 (first: $(printf '%s\n' "$LIST_OUT" | head -n1))"; fi

echo "== 3) templates/{dev,research,biz,mkt,creator} 프리셋 템플릿 존재 =="
for p in dev research biz mkt creator; do
  if [[ -f "$REPO/templates/$p/preset.conf" ]]; then ok "templates_${p}_존재: preset.conf";
  else bad "templates_${p}_존재: preset.conf"; fi
  if [[ -f "$REPO/templates/$p/AGENTS.md" ]]; then ok "templates_${p}_존재: AGENTS.md";
  else bad "templates_${p}_존재: AGENTS.md"; fi
done
# preset.conf 역할 정의 검증
assert_contains "$(cat "$REPO/templates/dev/preset.conf" 2>/dev/null)" "planner" "dev preset roles에 planner"
assert_contains "$(cat "$REPO/templates/dev/preset.conf" 2>/dev/null)" "worker" "dev preset roles에 worker"
assert_contains "$(cat "$REPO/templates/dev/preset.conf" 2>/dev/null)" "orchestrator" "dev preset roles에 orchestrator"
assert_contains "$(cat "$REPO/templates/biz/preset.conf" 2>/dev/null)" "researcher" "biz preset roles에 researcher (역할 일반화 증거)"
assert_contains "$(cat "$REPO/templates/biz/preset.conf" 2>/dev/null)" "소상공인" "biz_desc_갱신"
assert_contains "$(cat "$REPO/templates/research/preset.conf" 2>/dev/null)" "researcher" "research preset roles에 researcher"
assert_contains "$(cat "$REPO/templates/mkt/preset.conf" 2>/dev/null)" "researcher" "mkt preset roles에 researcher"
assert_contains "$(cat "$REPO/templates/creator/preset.conf" 2>/dev/null)" "worker" "creator preset roles에 worker"

echo "== 4) --preset dev --dry-run (비대화형) =="
DEV_OUT="$("$BIN" test --preset dev --dry-run --no-template --no-interactive 2>&1)"; DEV_RC=$?
assert_exit "$DEV_RC" 0 "dev dry-run exit 0"
assert_contains "$DEV_OUT" "preset=dev" "dev dry-run에 preset=dev 표시"
assert_contains "$DEV_OUT" "test-orchestrator" "dev dry-run에 test-orchestrator"
assert_contains "$DEV_OUT" "test-planner" "dev dry-run에 test-planner"
assert_contains "$DEV_OUT" "test-worker" "dev dry-run에 test-worker"
assert_contains "$DEV_OUT" "test-reviewer" "dev dry-run에 test-reviewer"

echo "== 5) app alias → dev (deprecation 경고) =="
APP_OUT="$("$BIN" test --preset app --dry-run --no-template --no-interactive 2>&1)"; APP_RC=$?
assert_exit "$APP_RC" 0 "preset_app_alias_dev_실행: exit 0"
assert_contains "$APP_OUT" "preset=dev" "preset_app_alias_dev_실행: preset=dev"
assert_contains "$APP_OUT" "deprecated" "preset_app_deprecation_경고"
assert_contains "$APP_OUT" "test-worker" "preset_app_alias_dev_실행: dev worker 역할"
if [[ ! -e "$REPO/templates/app" ]]; then ok "templates_app_삭제됨"; else bad "templates_app_삭제됨 (잔존)"; fi

echo "== 6) --preset biz --dry-run (역할 일반화: researcher) =="
BIZ_OUT="$("$BIN" test --preset biz --dry-run --no-template --no-interactive 2>&1)"; BIZ_RC=$?
assert_exit "$BIZ_RC" 0 "biz dry-run exit 0"
assert_contains "$BIZ_OUT" "preset=biz" "biz dry-run에 preset=biz 표시"
assert_contains "$BIZ_OUT" "test-orchestrator" "biz dry-run에 test-orchestrator (일반화)"
assert_contains "$BIZ_OUT" "test-researcher" "biz dry-run에 test-researcher (일반화)"
assert_not_contains "$BIZ_OUT" "test-worker" "biz dry-run에 test-worker 없음 (일반화)"

echo "== 7) 잘못된 preset은 실패 =="
"$BIN" test --preset bogus --dry-run --no-template --no-interactive >/dev/null 2>&1; BAD_RC=$?
if [[ "$BAD_RC" -ne 0 ]]; then ok "invalid preset exit != 0"; else bad "invalid preset exit != 0 (rc=0)"; fi
BAD_OUT="$("$BIN" test --preset bogus --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$BAD_OUT" "bogus" "invalid preset 에러에 입력값 표시"
for p in dev research biz mkt creator; do
  assert_contains "$BAD_OUT" "$p" "invalid preset 에러에 5종($p) 표시"
done

echo "== 8) --no-interactive 무프리셋은 기본값(dev)으로 비대화형 진행 =="
DEF_OUT="$(printf '' | timeout 15 "$BIN" test --dry-run --no-template --no-interactive 2>&1)"; DEF_RC=$?
assert_exit "$DEF_RC" 0 "--no-interactive 기본 dry-run exit 0"
assert_contains "$DEF_OUT" "preset=dev" "--no-interactive 기본 preset=dev"

echo "== 9) TUI 동적 메뉴 (숫자/이름/EOF/alias) =="
# 메뉴에서 2번(research) 선택 시뮬레이션. TUI가 stdin을 읽어야 함.
TUI_OUT="$(printf '2\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"; TUI_RC=$?
assert_exit "$TUI_RC" 0 "TUI 선택 dry-run exit 0"
assert_contains "$TUI_OUT" "preset=research" "TUI에서 2번 선택 → preset=research"
TUI5_OUT="$(printf '5\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$TUI5_OUT" "preset=creator" "tui_5선택_creator"
TUI_NAME_OUT="$(printf 'mkt\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$TUI_NAME_OUT" "preset=mkt" "tui_이름_mkt"
TUI_EOF_OUT="$(printf '' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$TUI_EOF_OUT" "preset=dev" "tui_EOF_dev기본"
TUI_APP_OUT="$(printf 'app\n3\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$TUI_APP_OUT" "preset=dev" "tui_app입력_dev경고: preset=dev"
assert_contains "$TUI_APP_OUT" "deprecated" "tui_app입력_dev경고: 경고 출력"

echo "== 10) 하위호환: 기존 옵션 조합 그대로 동작 =="
LEGACY_OUT="$(timeout 15 "$BIN" sd --dry-run --no-interactive 2>&1)"; LEGACY_RC=$?
assert_exit "$LEGACY_RC" 0 "legacy sd --dry-run exit 0"
assert_contains "$LEGACY_OUT" "prefix=sd" "legacy prefix=sd 유지"

echo "== 11) English-primary: help/TUI/LICENSE =="
assert_contains "$HELP_OUT" "Usage:" "help: English Usage header"
assert_contains "$HELP_OUT" "Presets" "help: English Presets section"
assert_contains "$HELP_OUT" "Software Development" "help: dev English label"
assert_contains "$HELP_OUT" "Deep Research" "help: research English label"
assert_contains "$HELP_OUT" "Small Business" "help: biz English label"
assert_contains "$HELP_OUT" "Local & SNS" "help: mkt English label"
assert_contains "$HELP_OUT" "Content Creation" "help: creator English label"
assert_contains "$TUI_OUT" "Select [1-5/dev/research/biz/mkt/creator]" "TUI: 동적 English-primary prompt"
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

# TUI 2단계: preset(app→dev alias) + kind(3=codex) 파이프 시뮬레이션
TUI_KIND_OUT2="$(printf 'app\n3\n' | timeout 15 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$TUI_KIND_OUT2" "preset=dev" "TUI 2단계: app→dev(alias) 선택"
assert_contains "$TUI_KIND_OUT2" "deprecated" "TUI 2단계: alias deprecation 경고"
assert_contains "$TUI_KIND_OUT2" "kind=codex" "TUI 2단계: codex 선택"

# 잘못된 kind 거부
BAD_KIND_OUT="$("$BIN" test --kind invalid_kind --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$BAD_KIND_OUT" "invalid_kind" "invalid kind 에러 출력"

echo "== 16) pane down 분할 균등 --ratio + resize JSON 누출 없음 =="
# 2col 기본값: dev(4역할: TM 좌측하단 + 우측 3역할: planner/worker/reviewer)
assert_contains "$DEV_OUT" "layout=2col" "dev 기본 layout=2col 표시"
assert_contains "$DEV_OUT" 'P_PLANNER=$(herdr pane split "$BASE" --direction right' "2col: 우측 첫 pane P_PLANNER"
assert_contains "$DEV_OUT" 'P_ORCHESTRATOR=$(herdr pane split "$BASE" --direction down --ratio 0.5' "2col: PM 하단 P_ORCHESTRATOR (0.5 균등)"
assert_contains "$DEV_OUT" 'P_WORKER=$(herdr pane split "$P_PLANNER" --direction down --ratio 0.333333' "2col: 우측 3개 중 1번째 down (1/3=0.333333)"
assert_contains "$DEV_OUT" 'P_REVIEWER=$(herdr pane split "$P_WORKER" --direction down --ratio 0.5' "2col: 우측 3개 중 2번째 down (1/2=0.5)"
# resize JSON stdout 누출/잔재 회귀: dry-run에는 resize 호출·best-effort 문구가 없어야 함
assert_not_contains "$DEV_OUT" "cli:pane:resize" "dry-run: cli:pane:resize JSON 누출 없음"
assert_not_contains "$DEV_OUT" "pane resize" "dry-run: herdr pane resize 호출 미표시"
assert_not_contains "$DEV_OUT" "균등화 best-effort" "dry-run: 기존 resize best-effort 문구 제거"
# help Layout도 설명 포함
assert_contains "$HELP_OUT" "--layout" "help: Layout 옵션 설명"

echo "== 17) opencode --agent 적용 (역할별 agent 강제) =="
# dev(4역할): herdr agent start ... -- --agent <prefix>-<role>
for r in orchestrator planner worker reviewer; do
  assert_contains "$DEV_OUT" "-- --agent test-$r" "dev: herdr agent start -- agent test-$r"
done
# biz: researcher는 --agent, worker는 없음 (역할 일반화 + kind 게이팅)
assert_contains "$BIZ_OUT" "-- --agent test-researcher" "biz: herdr agent start -- agent test-researcher"
assert_not_contains "$BIZ_OUT" "-- --agent test-worker" "biz: --agent test-worker 없음"
# creator: worker는 --agent, researcher는 없음 (창작 프리셋)
CREATOR_OUT="$("$BIN" test --preset creator --dry-run --no-template --no-interactive 2>&1)"; CREATOR_RC=$?
assert_exit "$CREATOR_RC" 0 "creator dry-run exit 0"
assert_contains "$CREATOR_OUT" "preset=creator" "dryrun_creator_worker: preset=creator"
assert_contains "$CREATOR_OUT" "-- --agent test-worker" "dryrun_creator_worker: --agent test-worker"
assert_not_contains "$CREATOR_OUT" "-- --agent test-researcher" "dryrun_creator_researcher없음"
# codex(미지원 kind): --agent 미사용
assert_not_contains "$KIND_ENV_OUT" "--agent" "codex: --agent 미사용(kind 게이팅)"

echo "== 18) opencode agent 템플릿 + {{PREFIX}} 치환 설치 =="
for r in orchestrator planner worker reviewer researcher; do
  if [[ -f "$REPO/templates/opencode-agents/ROLE-$r.md" ]]; then ok "templates/opencode-agents/ROLE-$r.md 존재";
  else bad "templates/opencode-agents/ROLE-$r.md 존재"; fi
done
# dry-run(템플릿 단계 포함)에 .opencode/agents 설치 계획 출력
GEN_DRY="$("$BIN" test --preset dev --dry-run --no-interactive --no-start 2>&1)"
assert_contains "$GEN_DRY" ".opencode/agents/test-orchestrator.md" "dry-run: .opencode/agents 설치 계획"
# 실제 생성 (herdr stub + 임시 CWD, jq 필요)
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"; TMPCWD="$(mktemp -d)"; TMPCWD2="$(mktemp -d)"; TMPCWD3="$(mktemp -d)"
  cat > "$STUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$STUB/herdr"
  PATH="$STUB:$PATH" "$BIN" testteam --preset dev --cwd "$TMPCWD" --template-dir "$REPO/templates" --no-interactive --no-start >/dev/null 2>&1
  for r in orchestrator planner worker reviewer; do
    if [[ -f "$TMPCWD/.opencode/agents/testteam-$r.md" ]]; then ok "생성: .opencode/agents/testteam-$r.md";
    else bad "생성: .opencode/agents/testteam-$r.md"; fi
    if [[ -f "$TMPCWD/agents/dev/testteam-$r.md" ]]; then ok "iso_seed_agents_preset_dir: agents/dev/testteam-$r.md";
    else bad "iso_seed_agents_preset_dir: agents/dev/testteam-$r.md"; fi
  done
  if [[ ! -f "$TMPCWD/agents/testteam-worker.md" ]]; then ok "평면 agents/testteam-worker.md 미생성"; else bad "평면 agents/testteam-worker.md 미생성"; fi
  if [[ "$(cat "$TMPCWD/.herdr-team/preset" 2>/dev/null)" == "dev" ]]; then ok "state: .herdr-team/preset=dev"; else bad "state: .herdr-team/preset=dev"; fi
  if [[ -f "$TMPCWD/.opencode/agents/testteam-orchestrator.md" ]]; then
    TM="$(cat "$TMPCWD/.opencode/agents/testteam-orchestrator.md")"
    assert_contains "$TM" "mode: primary" "agent frontmatter: mode primary"
    assert_contains "$TM" "testteam-planner" "agent 본문: {{PREFIX}} 치환됨"
    assert_not_contains "$TM" "{{PREFIX}}" "opencode_agent_placeholder_없음"
    assert_not_contains "$TM" "{{PRESET}}" "iso_subst_preset_placeholder: {{PRESET}} 미치환 없음"
  fi
  if [[ -f "$TMPCWD/agents/dev/testteam-worker.md" ]]; then
    CW="$(cat "$TMPCWD/agents/dev/testteam-worker.md")"
    assert_not_contains "$CW" "{{PREFIX}}" "iso_no_unsubstituted_placeholder: {{PREFIX}}"
    assert_not_contains "$CW" "{{PRESET}}" "iso_no_unsubstituted_placeholder: {{PRESET}}"
    assert_contains "$CW" "testteam-worker" "iso_seed_agents_preset_dir: 역할명 치환"
  fi
  # biz: researcher agent 생성, worker agent 미생성
  PATH="$STUB:$PATH" "$BIN" testbiz --preset biz --cwd "$TMPCWD2" --template-dir "$REPO/templates" --no-interactive --no-start >/dev/null 2>&1
  if [[ -f "$TMPCWD2/.opencode/agents/testbiz-researcher.md" ]]; then ok "biz: researcher agent 생성";
  else bad "biz: researcher agent 생성"; fi
  if [[ -f "$TMPCWD2/agents/biz/testbiz-researcher.md" ]]; then ok "biz: agents/biz 정본 생성";
  else bad "biz: agents/biz 정본 생성"; fi
  if [[ ! -f "$TMPCWD2/.opencode/agents/testbiz-worker.md" ]]; then ok "biz: worker agent 미생성";
  else bad "biz: worker agent 미생성"; fi
  # creator: worker agent 생성, researcher agent 미생성 (프리셋별 임시 CWD 격리)
  PATH="$STUB:$PATH" "$BIN" testcreator --preset creator --cwd "$TMPCWD3" --template-dir "$REPO/templates" --no-interactive --no-start >/dev/null 2>&1
  if [[ -f "$TMPCWD3/.opencode/agents/testcreator-worker.md" ]]; then ok "creator: worker agent 생성";
  else bad "creator: worker agent 생성"; fi
  if [[ -f "$TMPCWD3/agents/creator/testcreator-worker.md" ]]; then ok "creator: agents/creator 정본 생성";
  else bad "creator: agents/creator 정본 생성"; fi
  if [[ -f "$TMPCWD3/.opencode/agents/testcreator-orchestrator.md" ]]; then
    assert_not_contains "$(cat "$TMPCWD3/.opencode/agents/testcreator-worker.md")" "{{PREFIX}}" "creator worker agent: placeholder 없음"
  fi
  if [[ ! -f "$TMPCWD3/.opencode/agents/testcreator-researcher.md" ]]; then ok "creator: researcher agent 미생성";
  else bad "creator: researcher agent 미생성"; fi
  rm -rf "$STUB" "$TMPCWD" "$TMPCWD2" "$TMPCWD3"
else
  echo "SKIP: jq 없음 → opencode agent 생성 기능 테스트 생략"
fi

echo "== 19) --layout 옵션 (2col 기본값 vs right-stack 스택 모드) =="
# --layout right-stack 명시적 테스트
RS_OUT="$("$BIN" test --preset dev --layout right-stack --dry-run --no-template --no-interactive 2>&1)"
assert_contains "$RS_OUT" "layout=right-stack" "--layout right-stack 반영"
assert_contains "$RS_OUT" 'P_ORCHESTRATOR=$(herdr pane split "$BASE" --direction right' "right-stack: 첫 pane P_ORCHESTRATOR right"
assert_contains "$RS_OUT" "--ratio 0.25" "right-stack down split #1 --ratio 0.25 (1/4 균등)"
assert_contains "$RS_OUT" "--ratio 0.333333" "right-stack down split #2 --ratio 0.333333 (1/3 균등)"
assert_contains "$RS_OUT" "--ratio 0.5" "right-stack down split #3 --ratio 0.5 (1/2 균등)"

# HERDR_TEAM_LAYOUT 환경변수 반영
ENV_RS_OUT="$(HERDR_TEAM_LAYOUT=right-stack "$BIN" test --dry-run --no-template --no-interactive 2>&1)"
assert_contains "$ENV_RS_OUT" "layout=right-stack" "ENV: HERDR_TEAM_LAYOUT=right-stack 반영"

# 잘못된 layout 에러
BAD_LAYOUT_OUT="$("$BIN" test --layout invalid_layout --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$BAD_LAYOUT_OUT" "invalid_layout" "invalid layout 에러 출력"

echo "== 19b) T7 문서 일반화 (dev UX/Wireframe, role 비코드/유형별 검증) =="
DEV_AG="$(cat "$REPO/templates/dev/AGENTS.md" 2>/dev/null)"
assert_contains "$DEV_AG" "UX" "dev_agents_ux_wireframe: UX"
assert_contains "$DEV_AG" "Wireframe" "dev_agents_ux_wireframe: Wireframe"
assert_contains "$DEV_AG" "배포" "dev_agents_ux_wireframe: 배포/E2E"
assert_contains "$(cat "$REPO/templates/agents/ROLE-worker.md" 2>/dev/null)" "비코드" "role_worker_비코드모드"
assert_contains "$(cat "$REPO/templates/opencode-agents/ROLE-worker.md" 2>/dev/null)" "문서" "opencode ROLE-worker 일반화"
assert_contains "$(cat "$REPO/templates/agents/ROLE-reviewer.md" 2>/dev/null)" "팩트" "role_reviewer_유형별검증: 팩트체크"
assert_contains "$(cat "$REPO/templates/agents/ROLE-reviewer.md" 2>/dev/null)" "출처" "role_reviewer_유형별검증: 출처"
assert_contains "$(cat "$REPO/templates/opencode-agents/ROLE-reviewer.md" 2>/dev/null)" "edit: deny" "role_reviewer_edit_deny_유지"

echo "== 19c) README 2종 프리셋 표 5종 + TUI 1-5 =="
README_EN="$(cat "$REPO/README.md" 2>/dev/null)"
README_KO="$(cat "$REPO/README.ko.md" 2>/dev/null)"
for p in dev research biz mkt creator; do
  assert_contains "$README_EN" "| \`$p\`" "readme_preset표_5종: $p"
  assert_contains "$README_KO" "| \`$p\`" "readme_ko_preset표_5종: $p"
done
assert_contains "$README_EN" "Select [1-5" "readme_tui_1-5"
assert_not_contains "$README_EN" "| \`app\`" "readme_preset표_app_미노출"
assert_contains "$README_EN" "app" "README: app→dev alias 문구"
assert_contains "$README_EN" "agents/dev/" "readme_isolation_tree: agents/dev/"
assert_contains "$README_EN" ".herdr-team/preset" "readme_isolation_tree: .herdr-team/preset"
assert_contains "$README_EN" "requested preset folder" "readme_force_semantics"
assert_contains "$README_KO" "agents/dev/" "readme_ko_isolation_tree"

echo "== 20) 동적 열거: 커스텀 --template-dir preset 자동 발견 =="
TMPT="$(mktemp -d)"
mkdir -p "$TMPT/zzz"
cat > "$TMPT/zzz/preset.conf" <<'EOF'
PRESET_DESC="Zzz Custom (커스텀 프리셋)"
ROLES="orchestrator planner worker reviewer"
LAYOUT="2col"
EOF
LIST_CUSTOM="$("$BIN" --template-dir "$TMPT" --list-presets 2>&1)"
assert_contains "$LIST_CUSTOM" "zzz" "list_presets_커스텀preset_자동발견"
ZZZ_OUT="$("$BIN" test --template-dir "$TMPT" --preset zzz --dry-run --no-template --no-interactive 2>&1)"; ZZZ_RC=$?
assert_exit "$ZZZ_RC" 0 "커스텀 preset dry-run exit 0"
assert_contains "$ZZZ_OUT" "preset=zzz" "커스텀 preset dry-run 실행"
rm -rf "$TMPT"

echo "== 21) --help에 5종 preset 이름 모두 노출 =="
for p in dev research biz mkt creator; do
  assert_contains "$HELP_OUT" "$p" "help preset 노출: $p"
done

echo "== 22) 빈 discovery(dev 부재) → 명시 에러, 원시 grep 노출 없음 (엣지 #4) =="
SIM_BIN="$(mktemp -d)"; SIM_CUSTOM="$(mktemp -d)"
mkdir -p "$SIM_BIN/bin" "$SIM_CUSTOM/zzz"
cp "$BIN" "$SIM_BIN/bin/herdr-team"; chmod +x "$SIM_BIN/bin/herdr-team"
printf 'PRESET_DESC="Zzz Custom"\nROLES="orchestrator planner worker reviewer"\nLAYOUT="2col"\n' > "$SIM_CUSTOM/zzz/preset.conf"
EMPTY_OUT="$(HERDR_TEAM_TEMPLATE_DIR="$SIM_CUSTOM" "$SIM_BIN/bin/herdr-team" zz --dry-run --no-interactive 2>&1)"; EMPTY_RC=$?
assert_exit "$EMPTY_RC" 2 "empty_discovery_dev부재: exit 2"
assert_contains "$EMPTY_OUT" "dev" "empty_discovery_dev부재: preset 이름 안내"
assert_contains "$EMPTY_OUT" "preset.conf" "empty_discovery_dev부재: preset.conf 안내"
assert_not_contains "$EMPTY_OUT" "No such file or directory" "empty_discovery_dev부재: 원시 grep 에러 없음"
# 완전 빈 discovery(커스텀 preset도 없음) → 깨진 "사용 가능: ." 없이 안내
SIM_EMPTY="$(mktemp -d)"
EMPTY2_OUT="$(HERDR_TEAM_TEMPLATE_DIR="$SIM_EMPTY" "$SIM_BIN/bin/herdr-team" zz --dry-run --no-interactive 2>&1)"; EMPTY2_RC=$?
assert_exit "$EMPTY2_RC" 2 "empty_discovery_완전빈: exit 2"
assert_contains "$EMPTY2_OUT" "preset.conf" "empty_discovery_완전빈: 안내 문구"
assert_not_contains "$EMPTY2_OUT" "사용 가능: ." "empty_discovery_완전빈: 깨진 문구 없음"
rm -rf "$SIM_BIN" "$SIM_CUSTOM" "$SIM_EMPTY"

echo "== 23) alias shadow: 커스텀 app/ 있어도 alias 우선 (엣지 #3) =="
SHADOW="$(mktemp -d)"; mkdir -p "$SHADOW/app"
printf 'PRESET_DESC="Custom App"\nROLES="orchestrator planner worker reviewer"\nLAYOUT="2col"\n' > "$SHADOW/app/preset.conf"
SHADOW_LIST="$("$BIN" --template-dir "$SHADOW" --list-presets 2>&1)"
assert_not_contains "$SHADOW_LIST" "app" "alias_shadow: 커스텀 app 미노출"
SHADOW_OUT="$("$BIN" test --template-dir "$SHADOW" --preset app --dry-run --no-template --no-interactive 2>&1)"; SHADOW_RC=$?
assert_exit "$SHADOW_RC" 0 "alias_shadow: app exit 0"
assert_contains "$SHADOW_OUT" "preset=dev" "alias_shadow: app→dev 해소"
assert_contains "$SHADOW_OUT" "deprecated" "alias_shadow: deprecation 경고"
rm -rf "$SHADOW"

echo "== 23b) 템플릿 {{PRESET}} 링크 (T7) =="
if grep -rqF 'agents/{{PRESET}}/{{PREFIX}}-' "$REPO/templates"; then ok "templates_preset_links"; else bad "templates_preset_links"; fi
if ! grep -rqE '(^|[^./])agents/\{\{PREFIX\}\}-' "$REPO/templates"; then ok "templates_no_flat_agent_links"; else bad "templates_no_flat_agent_links"; fi

echo "== 24~35) 프리셋별 문서 격리 (agents/<preset>/) =="
if command -v jq >/dev/null 2>&1; then
  ISTUB="$(mktemp -d)"
  cat > "$ISTUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$ISTUB/herdr"
  iso_run() { # $1=prefix $2=preset $3=cwd [extra...]
    local pfx="$1" pre="$2" cwd="$3"; shift 3
    PATH="$ISTUB:$PATH" "$BIN" "$pfx" --preset "$pre" --cwd "$cwd" --template-dir "$REPO/templates" --no-interactive --no-start "$@" >/dev/null 2>&1
  }
  iso_dry() { # like iso_run but captures output and appends --dry-run
    local pfx="$1" pre="$2" cwd="$3"; shift 3
    PATH="$ISTUB:$PATH" "$BIN" "$pfx" --preset "$pre" --cwd "$cwd" --template-dir "$REPO/templates" --no-interactive --no-start --dry-run "$@" 2>&1
  }

  # --- 24·25·26: dev→mkt→dev 무손실 왕복 / activate / write-back ---
  I1="$(mktemp -d)"
  iso_run iso dev "$I1"
  echo "CUSTOM-DEV-MARKER" >> "$I1/agents/dev/iso-worker.md"
  echo "ROOT-DEV-EDIT" >> "$I1/AGENTS.md"
  iso_run iso mkt "$I1"
  if grep -q "CUSTOM-DEV-MARKER" "$I1/agents/dev/iso-worker.md" 2>/dev/null; then ok "iso_roundtrip_lossless: dev 정본 마커 보존";
  else bad "iso_roundtrip_lossless: dev 정본 마커 보존"; fi
  if cmp -s "$I1/AGENTS.md" "$I1/agents/mkt/AGENTS.md"; then ok "iso_switch_activate_root: 루트==agents/mkt/AGENTS.md";
  else bad "iso_switch_activate_root: 루트==agents/mkt/AGENTS.md"; fi
  if cmp -s "$I1/AGENTS.md" "$I1/agents/mkt/AGENTS.md"; then ok "switch_activate_incoming";
  else bad "switch_activate_incoming"; fi
  if grep -q "ROOT-DEV-EDIT" "$I1/agents/dev/AGENTS.md" 2>/dev/null; then ok "iso_writeback_root_edit: 루트 편집→dev 정본";
  else bad "iso_writeback_root_edit: 루트 편집→dev 정본"; fi
  if grep -q "ROOT-DEV-EDIT" "$I1/agents/dev/AGENTS.md" 2>/dev/null; then ok "switch_writeback_outgoing";
  else bad "switch_writeback_outgoing"; fi
  iso_run iso dev "$I1"
  if cmp -s "$I1/AGENTS.md" "$I1/agents/dev/AGENTS.md" && grep -q "ROOT-DEV-EDIT" "$I1/AGENTS.md"; then ok "iso_roundtrip_lossless: 루트 복원";
  else bad "iso_roundtrip_lossless: 루트 복원"; fi
  assert_equal "$(cat "$I1/.herdr-team/preset" 2>/dev/null)" "dev" "iso_roundtrip_lossless: state=dev"
  rm -rf "$I1"

  # --- 27: 레거시 평면 마이그레이션(복사, 원본 불변) + 루트 import ---
  I2="$(mktemp -d)"; mkdir -p "$I2/agents"
  printf 'ROOT-ORIG\n' > "$I2/AGENTS.md"
  printf 'FLAT-WORKER-ORIG\n' > "$I2/agents/iso-worker.md"
  printf 'FLAT-PLANNER-ORIG\n' > "$I2/agents/iso-planner.md"
  iso_run iso dev "$I2"
  assert_equal "$(cat "$I2/agents/iso-worker.md")" "FLAT-WORKER-ORIG" "migrate_flat_preserves_originals: 평면 원본 불변"
  assert_equal "$(cat "$I2/agents/dev/iso-worker.md")" "FLAT-WORKER-ORIG" "migrate_flat_role_docs: 정본으로 복사"
  assert_equal "$(cat "$I2/agents/dev/AGENTS.md")" "ROOT-ORIG" "migrate_root_agents_canonical: 루트→정본 import"
  assert_equal "$(cat "$I2/AGENTS.md")" "ROOT-ORIG" "migrate_root_agents_canonical: 루트 무변경"
  assert_equal "$(cat "$I2/.herdr-team/preset" 2>/dev/null)" "dev" "migrate: state=dev"
  rm -rf "$I2"

  # --- 28: 평면+격리 공존 시 격리 우선 ---
  I3="$(mktemp -d)"; mkdir -p "$I3/agents/dev"
  printf 'CANON-CONTENT\n' > "$I3/agents/dev/iso-worker.md"
  printf 'CANON-AGENTS\n' > "$I3/agents/dev/AGENTS.md"
  printf 'FLAT-CONTENT\n' > "$I3/agents/iso-worker.md"
  iso_run iso dev "$I3"
  assert_equal "$(cat "$I3/agents/dev/iso-worker.md")" "CANON-CONTENT" "coexist_priority_preset_dir: 정본 우선(평면 미적용)"
  assert_equal "$(cat "$I3/agents/dev/iso-worker.md")" "CANON-CONTENT" "coexist_preset_dir_wins"
  assert_equal "$(cat "$I3/agents/iso-worker.md")" "FLAT-CONTENT" "coexist_priority_preset_dir: 평면 원본 보존"
  rm -rf "$I3"

  # --- 부분 프리셋 폴더: 누락 role만 시딩, 기존 파일 무변경 (엣지 #1) ---
  I3b="$(mktemp -d)"; mkdir -p "$I3b/agents/dev"
  printf 'PARTIAL-WORKER\n' > "$I3b/agents/dev/iso-worker.md"
  iso_run iso dev "$I3b"
  assert_equal "$(cat "$I3b/agents/dev/iso-worker.md")" "PARTIAL-WORKER" "partial_preset_dir_preserve"
  if [[ -f "$I3b/agents/dev/iso-planner.md" ]]; then ok "partial_preset_dir_seed_missing";
  else bad "partial_preset_dir_seed_missing"; fi
  rm -rf "$I3b"

  # --- 29: opencode stale prune + 활성 role gen + 타 prefix 불가침 ---
  I4="$(mktemp -d)"
  iso_run iso dev "$I4"
  iso_run iso mkt "$I4"
  if [[ ! -f "$I4/.opencode/agents/iso-worker.md" ]]; then ok "opencode_prune_stale_role: worker prune";
  else bad "opencode_prune_stale_role: worker prune"; fi
  if [[ -f "$I4/.opencode/agents/iso-researcher.md" ]]; then ok "opencode_gen_active_only: researcher 생성";
  else bad "opencode_gen_active_only: researcher 생성"; fi
  printf 'x\n' > "$I4/.opencode/agents/other-worker.md"
  iso_run iso mkt "$I4"
  if [[ -f "$I4/.opencode/agents/other-worker.md" ]]; then ok "opencode_other_prefix_untouched";
  else bad "opencode_other_prefix_untouched"; fi
  rm -rf "$I4"

  # --- 30: 같은 프리셋 재실행 시 opencode 편집 보존 ---
  I5="$(mktemp -d)"
  iso_run iso dev "$I5"
  echo "USER-EDIT" >> "$I5/.opencode/agents/iso-worker.md"
  ROOT_BEFORE="$(cat "$I5/AGENTS.md")"
  iso_run iso dev "$I5"
  if grep -q "USER-EDIT" "$I5/.opencode/agents/iso-worker.md"; then ok "opencode_same_preset_preserve";
  else bad "opencode_same_preset_preserve"; fi
  assert_equal "$(cat "$I5/AGENTS.md")" "$ROOT_BEFORE" "same_preset_root_untouched"
  rm -rf "$I5"

  # --- 31: --force 요청 프리셋만 재시딩, 타 프리셋 불가침 ---
  I6="$(mktemp -d)"
  iso_run iso dev "$I6"
  echo "DEV-EDIT" >> "$I6/agents/dev/iso-worker.md"
  iso_run iso mkt "$I6"
  echo "MKT-EDIT" >> "$I6/agents/mkt/iso-planner.md"
  iso_run iso mkt "$I6" --force
  if grep -q "DEV-EDIT" "$I6/agents/dev/iso-worker.md"; then ok "force_preserve_other_presets";  else bad "force_preserve_other_presets"; fi
  if ! grep -q "MKT-EDIT" "$I6/agents/mkt/iso-planner.md"; then ok "force_reseed_requested_only";
  else bad "force_reseed_requested_only"; fi
  assert_equal "$(cat "$I6/.herdr-team/preset" 2>/dev/null)" "mkt" "force_scoped_reseed: state=mkt"
  rm -rf "$I6"

  # --- 32: 상태 파일 1줄 canonical + 실패 시 이전 ACTIVE 유지 ---
  I7="$(mktemp -d)"
  iso_run iso dev "$I7"
  if [[ "$(wc -l < "$I7/.herdr-team/preset")" -eq 1 && "$(cat "$I7/.herdr-team/preset")" == "dev" ]]; then ok "state_written_last: 1줄 canonical";
  else bad "state_written_last: 1줄 canonical"; fi
  if [[ "$(wc -l < "$I7/.herdr-team/preset")" -eq 1 && "$(cat "$I7/.herdr-team/preset")" == "dev" ]]; then ok "set_active_last_write";
  else bad "set_active_last_write"; fi
  printf 'blocker' > "$I7/agents/mkt"
  iso_run iso mkt "$I7"; STATERC=$?
  if [[ "$STATERC" -ne 0 && "$(cat "$I7/.herdr-team/preset")" == "dev" ]]; then ok "state_written_last: 실패 시 이전 ACTIVE 유지";
  else bad "state_written_last: 실패 시 이전 ACTIVE 유지 (rc=$STATERC)"; fi
  # 상태 손상: 알 수 없는 값 → 경고 후 요청 프리셋으로 활성화, 상태 정정 (엣지 #12)
  printf 'weird\n' > "$I7/.herdr-team/preset"
  iso_run iso dev "$I7"
  assert_equal "$(cat "$I7/.herdr-team/preset")" "dev" "state_corrupt_activate_requested"
  rm -rf "$I7"

  # --- 33: --no-template 은 격리/상태 전체 생략 ---
  I8="$(mktemp -d)"
  iso_run iso dev "$I8" --no-template
  if [[ ! -e "$I8/agents/dev" && ! -e "$I8/.herdr-team/preset" && ! -e "$I8/AGENTS.md" ]]; then ok "no_template_skips_isolation";
  else bad "no_template_skips_isolation"; fi
  rm -rf "$I8"

  # --- 34: dry-run 은 쓰기 0 + 격리 계획 로그 ---
  I9="$(mktemp -d)"
  DOUT="$(iso_dry iso dev "$I9")"
  assert_contains "$DOUT" ".herdr-team/preset" "dryrun_isolation_plan_logged: state 계획"
  assert_contains "$DOUT" "agents/dev" "dryrun_isolation_plan_logged: 정본 경로"
  assert_contains "$DOUT" "activate:" "dryrun_isolation_plan_logged: activate 계획"
  assert_contains "$DOUT" ".opencode/agents/iso" "dryrun_isolation_plan_logged: opencode gen 계획"
  assert_contains "$DOUT" "active=<none>" "active_preset_초기빈값"
  if [[ ! -e "$I9/agents" && ! -e "$I9/.herdr-team" && ! -e "$I9/AGENTS.md" && ! -e "$I9/.opencode" ]]; then ok "dryrun_no_writes";
  else bad "dryrun_no_writes"; fi
  if [[ ! -e "$I9/.herdr-team/preset" ]]; then ok "dryrun_state_미기록";
  else bad "dryrun_state_미기록"; fi
  rm -rf "$I9"

  # --- 35: 자기 저장소 유형(평면 agents/hts-*, 루트 링크) 무손상 ---
  I10="$(mktemp -d)"; mkdir -p "$I10/agents"
  printf 'ROOT LINK agents/iso-planner.md\n' > "$I10/AGENTS.md"
  printf 'FLAT-PLANNER\n' > "$I10/agents/iso-planner.md"
  printf 'FLAT-WORKER\n' > "$I10/agents/iso-worker.md"
  iso_run iso dev "$I10"
  if [[ -f "$I10/agents/iso-planner.md" && "$(cat "$I10/agents/iso-planner.md")" == "FLAT-PLANNER" ]]; then ok "legacy_self_repo: 평면 원본 무손상";
  else bad "legacy_self_repo: 평면 원본 무손상"; fi
  if grep -q "agents/iso-planner.md" "$I10/AGENTS.md"; then ok "legacy_self_repo: 루트 링크 유효";
  else bad "legacy_self_repo: 루트 링크 유효"; fi
  rm -rf "$I10"

  # --- 36: 커스텀 preset 이름의 sed replacement 메타문자(&) 이스케이프 ---
  ATPL="$(mktemp -d)"; mkdir -p "$ATPL/a&b/agents"
  cp "$REPO/templates/dev/AGENTS.md" "$ATPL/a&b/AGENTS.md"
  cp "$REPO/templates/agents/ROLE-planner.md" "$ATPL/a&b/agents/ROLE-planner.md"
  printf 'PRESET_DESC="Amp"\nROLES="orchestrator planner worker reviewer"\nLAYOUT="2col"\n' > "$ATPL/a&b/preset.conf"
  ACWD="$(mktemp -d)"
  PATH="$ISTUB:$PATH" "$BIN" aa --template-dir "$ATPL" --cwd "$ACWD" --preset "a&b" --no-interactive --no-start >/dev/null 2>&1; A_RC=$?
  assert_exit "$A_RC" 0 "subst_preset_ampersand_escaping: exit 0"
  AG="$ACWD/agents/a&b/AGENTS.md"
  if [[ -f "$AG" ]] && ! grep -qF "{{PRESET}}" "$AG" && grep -qF "agents/a&b/aa-<role>.md" "$AG"; then
    ok "subst_preset_ampersand_escaping: 리터럴 잔존 없음 + 실제 preset 치환"
  else
    bad "subst_preset_ampersand_escaping: 리터럴 잔존 없음 + 실제 preset 치환"
  fi
  rm -rf "$ATPL" "$ACWD"

  rm -rf "$ISTUB"
else
  echo "SKIP: jq 없음 → 프리셋 격리 테스트 생략"
fi

echo "== 36) run(): stdout(JSON) 억제 / stderr 보존 / 종료코드 전파 / dry-run 불변 =="
# bin/herdr-team은 하단 실행문이 있어 그냥 source하면 위험 → run() 정의만 추출해 단위 검증
RUN_SRC_FILE="$(mktemp)"
sed -n '/^run() {/,/^}/p' "$BIN" > "$RUN_SRC_FILE"
if [[ -s "$RUN_SRC_FILE" ]]; then
  # (a) 성공 시 stdout 억제 + 종료코드 0 전파
  RUN_A_OUT="$(DRY_RUN=0 bash -c 'source "$1"; run bash -c "echo JSONLEAK; exit 0"' _ "$RUN_SRC_FILE" 2>&1)"; RUN_A_RC=$?
  assert_exit "$RUN_A_RC" 0 "run_unit: 성공 종료코드 0 전파"
  assert_not_contains "$RUN_A_OUT" "JSONLEAK" "run_unit: 성공 시 stdout 미노출"
  # (b) stderr는 그대로 노출
  RUN_B_OUT="$(DRY_RUN=0 bash -c 'source "$1"; run bash -c "echo ERRKEEP >&2; exit 0"' _ "$RUN_SRC_FILE" 2>&1)"
  assert_contains "$RUN_B_OUT" "ERRKEEP" "run_unit: stderr 보존"
  # (c) 비정상 종료코드 전파 (조용한 성공 위장 금지)
  DRY_RUN=0 bash -c 'source "$1"; run bash -c "exit 7"' _ "$RUN_SRC_FILE" >/dev/null 2>&1; RUN_C_RC=$?
  assert_exit "$RUN_C_RC" 7 "run_unit: 비정상 종료코드 전파"
  # (d) --dry-run '+ 명령' 출력 불변
  RUN_D_OUT="$(DRY_RUN=1 bash -c 'source "$1"; run echo hello world' _ "$RUN_SRC_FILE" 2>&1)"
  assert_equal "$RUN_D_OUT" "+ echo hello world" "run_unit: dry-run '+ 명령' 출력 불변"
else
  bad "run_unit: run() 정의 추출 실패"
fi
rm -f "$RUN_SRC_FILE"

# (e) 실제 스크립트 구동: fake herdr JSON stdout 누출 없음 / stderr 보존 / 종료코드 전파
if command -v jq >/dev/null 2>&1; then
  RSTUB="$(mktemp -d)"; RCWD="$(mktemp -d)"; RCWD2="$(mktemp -d)"
  cat > "$RSTUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "pane" && "${2:-}" == "rename" ]]; then
  printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
  printf 'RENAME-STDERR-MARK\n' >&2
  exit "${HERDR_STUB_RENAME_RC:-0}"
fi
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$RSTUB/herdr"
  RUN_E_OUT="$(PATH="$RSTUB:$PATH" "$BIN" testrun --preset dev --cwd "$RCWD" --template-dir "$REPO/templates" --no-interactive --no-start 2>/dev/null)"; RUN_E_RC=$?
  assert_exit "$RUN_E_RC" 0 "run_e2e: exit 0"
  assert_not_contains "$RUN_E_OUT" '"pane_id"' "run_e2e: pane rename JSON stdout 미노출"
  assert_not_contains "$RUN_E_OUT" '{"result"' "run_e2e: herdr JSON stdout 미노출"
  RUN_E_ERR="$(PATH="$RSTUB:$PATH" "$BIN" testrun --preset dev --cwd "$RCWD" --template-dir "$REPO/templates" --no-interactive --no-start 2>&1 >/dev/null)"
  assert_contains "$RUN_E_ERR" "RENAME-STDERR-MARK" "run_e2e: stderr 보존"
  HERDR_STUB_RENAME_RC=3 PATH="$RSTUB:$PATH" "$BIN" testrun --preset dev --cwd "$RCWD2" --template-dir "$REPO/templates" --no-interactive --no-start >/dev/null 2>&1; RUN_E_FAIL_RC=$?
  assert_exit "$RUN_E_FAIL_RC" 3 "run_e2e: pane rename 실패 종료코드 전파"
  rm -rf "$RSTUB" "$RCWD" "$RCWD2"
fi

echo "== 37) 중복 대기 금지 (No Redundant Wait) 정본 반영 =="
NRW_DOCS=(
  "AGENTS.md"
  "agents/dev/AGENTS.md"
  "templates/AGENTS.md"
  "templates/dev/AGENTS.md"
  "templates/mkt/AGENTS.md"
  "templates/biz/AGENTS.md"
  "templates/creator/AGENTS.md"
  "templates/research/AGENTS.md"
  "templates/agents/ROLE-taskmanager.md"
  "templates/opencode-agents/ROLE-orchestrator.md"
  "agents/hts-taskmanager.md"
)
for d in "${NRW_DOCS[@]}"; do
  if [[ ! -f "$REPO/$d" ]]; then
    echo "SKIP: $d 부재(untracked) -> §37 해당 항목 건너뜀"
    continue
  fi
  NRW_TXT="$(cat "$REPO/$d")"
  assert_contains "$NRW_TXT" "중복 대기 금지" "nrw_중복대기금지문구: $d"
  assert_contains "$NRW_TXT" "No Redundant Wait" "nrw_NoRedundantWait문구: $d"
  assert_not_contains "$NRW_TXT" '장시간 작업은 `wait` + `read`로 폴링' "nrw_폴링유도문구_제거: $d"
done
# (c) 기존 유도용 예시 wait 라인 제거
assert_not_contains "$(cat "$REPO/AGENTS.md" 2>/dev/null)" "herdr agent wait hts-worker --timeout 600000" "nrw_레거시wait예시_제거: AGENTS.md"
if [[ -f "$REPO/agents/dev/AGENTS.md" ]]; then
  assert_not_contains "$(cat "$REPO/agents/dev/AGENTS.md")" "herdr agent wait hts-worker --timeout 600000" "nrw_레거시wait예시_제거: agents/dev/AGENTS.md"
else
  echo "SKIP: agents/dev/AGENTS.md 부재(untracked) -> §37 해당 항목 건너뜀"
fi
assert_not_contains "$(cat "$REPO/templates/AGENTS.md" 2>/dev/null)" "herdr agent wait {{PREFIX}}-worker --timeout 600000" "nrw_레거시wait예시_제거: templates/AGENTS.md"
# (d) 펜스 내 prompt --wait 직후 agent wait 재호출 탐지 (POSIX awk, grep -P 미사용)
for d in "AGENTS.md" "agents/dev/AGENTS.md" "templates/AGENTS.md"; do
  if [[ ! -f "$REPO/$d" ]]; then
    echo "SKIP: $d 부재(untracked) -> §37 해당 항목 건너뜀"
    continue
  fi
  NRW_VIOL="$(awk '
    /^```/ { f = !f; pw = 0; next }
    !f { next }
    /herdr agent prompt/ && /--wait/ {
      if ($0 ~ /herdr agent wait/ && $0 !~ /비동기/) print NR": "$0
      pw = 1; next
    }
    pw && /herdr agent wait/ {
      if ($0 ~ /비동기/) { pw = 0; next }
      print NR": "$0
    }
  ' "$REPO/$d")"
  if [[ -z "$NRW_VIOL" ]]; then ok "nrw_중복대기_펜스검출: $d"; else bad "nrw_중복대기_펜스검출: $d ($NRW_VIOL)"; fi
done
# (e) 성공/타임아웃/비동기 경로 문서화
assert_contains "$(cat "$REPO/AGENTS.md" 2>/dev/null)" "herdr agent read" "nrw_read경로_문서화: AGENTS.md"
assert_contains "$(cat "$REPO/AGENTS.md" 2>/dev/null)" "타임아웃" "nrw_타임아웃경로_문서화: AGENTS.md"
assert_contains "$(cat "$REPO/AGENTS.md" 2>/dev/null)" "비동기 경로" "nrw_비동기경로_문서화: AGENTS.md"
assert_contains "$(cat "$REPO/templates/AGENTS.md" 2>/dev/null)" "herdr agent read" "nrw_read경로_문서화: templates/AGENTS.md"
assert_contains "$(cat "$REPO/templates/AGENTS.md" 2>/dev/null)" "타임아웃" "nrw_타임아웃경로_문서화: templates/AGENTS.md"
assert_contains "$(cat "$REPO/templates/AGENTS.md" 2>/dev/null)" "비동기 경로" "nrw_비동기경로_문서화: templates/AGENTS.md"
# (f) Block A 4줄 문자 단위 동일성 (md5; md5sum → md5 -q → openssl md5 폴백, 전무 시 SKIP)
NRW_BA_FILES=(
  "AGENTS.md"
  "agents/dev/AGENTS.md"
  "templates/AGENTS.md"
  "templates/dev/AGENTS.md"
  "templates/mkt/AGENTS.md"
  "templates/biz/AGENTS.md"
  "templates/creator/AGENTS.md"
  "templates/research/AGENTS.md"
  "templates/agents/ROLE-taskmanager.md"
  "agents/hts-taskmanager.md"
)
NRW_BA_EXPECT="275ab1dc6d92263da9dbe6676af0082d"
nrw_md5() {
  if command -v md5sum >/dev/null 2>&1; then md5sum | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  elif command -v openssl >/dev/null 2>&1; then openssl md5 | awk '{print $NF}'
  else :; fi
}
if ! command -v md5sum >/dev/null 2>&1 && ! command -v md5 >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
  echo "SKIP: md5 도구(md5sum/md5/openssl) 부재 -> §37 Block A 동일성 검사 건너뜀"
else
  for d in "${NRW_BA_FILES[@]}"; do
    if [[ ! -f "$REPO/$d" ]]; then
      echo "SKIP: $d 부재(untracked) -> §37 Block A 동일성 검사 건너뜀"
      continue
    fi
    NRW_BA_HASH="$(awk '/반드시 1번에 1개의 `herdr` 명령만 단독 실행/{c=4} c{print; c--}' "$REPO/$d" | nrw_md5)"
    if [[ "$NRW_BA_HASH" == "$NRW_BA_EXPECT" ]]; then ok "nrw_BlockA_동일성: $d"; else bad "nrw_BlockA_동일성: $d (hash=$NRW_BA_HASH)"; fi
  done
fi
# (g) `--until` 단일 상태값 경고(Canonical WARN) 정본 반영 + 콤마 나열 금지
NRW_WARN_MARK='⚠️ **`--until` 단일 상태값**'
for d in "${NRW_DOCS[@]}"; do
  if [[ ! -f "$REPO/$d" ]]; then
    echo "SKIP: $d 부재(untracked) -> §37 해당 항목 건너뜀"
    continue
  fi
  NRW_TXT="$(cat "$REPO/$d")"
  assert_contains "$NRW_TXT" "$NRW_WARN_MARK" "nrw_until단일상태값_경고: $d"
  assert_contains "$NRW_TXT" "invalid agent status" "nrw_until에러문구_문서화: $d"
  assert_contains "$NRW_TXT" '상태 **하나만** 받는다' "nrw_until단일값주장_문안: $d"
  assert_contains "$NRW_TXT" '--until idle --until done' "nrw_until대안_플래그반복: $d"
  assert_contains "$NRW_TXT" 'idle/done/blocked 매칭' "nrw_until대안_생략기본매칭: $d"
  NRW_COMMA="$(grep -E -- '--until[[:space:]]+[a-z]+,[[:space:]]*[a-z]+' "$REPO/$d" | grep -vE -- '^[[:space:]]*- ⚠️')"
  if [[ -z "$NRW_COMMA" ]]; then ok "nrw_until콤마나열_금지: $d"; else bad "nrw_until콤마나열_금지: $d ($NRW_COMMA)"; fi
done

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
