#!/usr/bin/env bash
# tests/test_templates_only.sh — --templates-only 옵션 TDD 검증
# 실행: bash tests/test_templates_only.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
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

[[ -x "$BIN" ]] || { printf 'FAIL: %s not executable\n' "$BIN"; exit 1; }

echo "== 1) --help에 --templates-only 문서화 =="
HELP_OUT="$("$BIN" --help 2>&1 || true)"
assert_contains "$HELP_OUT" "--templates-only" "help: --templates-only 문서화"

echo "== 2) 파일 생성 확인 (templates + opencode agents + state) =="
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"; TMPCWD="$(mktemp -d)"
  cat > "$STUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$STUB/herdr"
  PATH="$STUB:$PATH" "$BIN" tmpl --preset dev --cwd "$TMPCWD" --template-dir "$REPO/templates" --no-interactive --templates-only >/dev/null 2>&1; T_RC=$?
  assert_exit "$T_RC" 0 "templates-only exit 0"
  if [[ -f "$TMPCWD/agents/dev/tmpl-worker.md" ]]; then ok "생성: agents/dev/tmpl-worker.md";
  else bad "생성: agents/dev/tmpl-worker.md"; fi
  if [[ -f "$TMPCWD/.opencode/agents/tmpl-worker.md" ]]; then ok "생성: .opencode/agents/tmpl-worker.md";
  else bad "생성: .opencode/agents/tmpl-worker.md"; fi
  if [[ -f "$TMPCWD/AGENTS.md" ]]; then ok "생성: AGENTS.md";
  else bad "생성: AGENTS.md"; fi
  if [[ "$(cat "$TMPCWD/.herdr-team/preset" 2>/dev/null)" == "dev" ]]; then ok "state: .herdr-team/preset=dev";
  else bad "state: .herdr-team/preset=dev"; fi
  rm -rf "$STUB" "$TMPCWD"
else
  echo "SKIP: jq 없음 → 파일 생성 테스트 생략"
fi

echo "== 3) Pane 분할 미호출 확인 =="
# 3a) --dry-run 출력에 pane split 계획 없음 (템플릿 계획은 있음)
DRY_OUT="$("$BIN" tmpl --preset dev --dry-run --no-interactive --templates-only 2>&1)"; DRY_RC=$?
assert_exit "$DRY_RC" 0 "templates-only dry-run exit 0"
assert_not_contains "$DRY_OUT" "herdr pane split" "templates-only dry-run: pane split 미표시"
assert_not_contains "$DRY_OUT" "herdr agent start" "templates-only dry-run: agent start 미표시"
assert_contains "$DRY_OUT" "agents/dev" "templates-only dry-run: 템플릿 계획 표시"
# 3b) 실제 실행 시 stub herdr 호출 로그에 pane split 없음
if command -v jq >/dev/null 2>&1; then
  STUB2="$(mktemp -d)"; TMPCWD2="$(mktemp -d)"; CALLLOG="$(mktemp)"
  cat > "$STUB2/herdr" <<STUBEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLLOG"
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$STUB2/herdr"
  PATH="$STUB2:$PATH" "$BIN" tmpl --preset dev --cwd "$TMPCWD2" --template-dir "$REPO/templates" --no-interactive --no-start --templates-only >/dev/null 2>&1
  if grep -q "pane split" "$CALLLOG" 2>/dev/null; then bad "templates-only 실행: pane split 미호출";
  else ok "templates-only 실행: pane split 미호출"; fi
  rm -rf "$STUB2" "$TMPCWD2" "$CALLLOG"
else
  echo "SKIP: jq 없음 → pane split 미호출 실행 테스트 생략"
fi

echo "== 4) --dry-run 연계: 쓰기 0 =="
TDRY="$(mktemp -d)"
DOUT="$("$BIN" tmpl --preset dev --cwd "$TDRY" --template-dir "$REPO/templates" --no-interactive --templates-only --dry-run 2>&1)"; DRC=$?
assert_exit "$DRC" 0 "templates-only --dry-run exit 0"
assert_contains "$DOUT" "agents/dev" "templates-only --dry-run: 격리 계획 로그"
if [[ ! -e "$TDRY/agents" && ! -e "$TDRY/.herdr-team" && ! -e "$TDRY/AGENTS.md" && ! -e "$TDRY/.opencode" ]]; then ok "templates-only --dry-run: 쓰기 0";
else bad "templates-only --dry-run: 쓰기 0"; fi
rm -rf "$TDRY"

echo "== 5) --force/--preset/--template-dir 호환 =="
if command -v jq >/dev/null 2>&1; then
  STUB3="$(mktemp -d)"; TF="$(mktemp -d)"
  cat > "$STUB3/herdr" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$STUB3/herdr"
  # --preset biz 호환 (researcher 정본)
  PATH="$STUB3:$PATH" "$BIN" tmpl --preset biz --cwd "$TF" --template-dir "$REPO/templates" --no-interactive --templates-only >/dev/null 2>&1; B_RC=$?
  assert_exit "$B_RC" 0 "templates-only --preset biz exit 0"
  if [[ -f "$TF/agents/biz/tmpl-researcher.md" ]]; then ok "biz 정본 생성";
  else bad "biz 정본 생성"; fi
  if [[ ! -f "$TF/agents/biz/tmpl-worker.md" ]]; then ok "biz worker 미생성";
  else bad "biz worker 미생성"; fi
  # --force 호환 (요청 프리셋만 재시딩)
  echo "FORCE-EDIT" >> "$TF/agents/biz/tmpl-planner.md"
  PATH="$STUB3:$PATH" "$BIN" tmpl --preset biz --cwd "$TF" --template-dir "$REPO/templates" --no-interactive --templates-only --force >/dev/null 2>&1; F_RC=$?
  assert_exit "$F_RC" 0 "templates-only --force exit 0"
  if ! grep -q "FORCE-EDIT" "$TF/agents/biz/tmpl-planner.md" 2>/dev/null; then ok "templates-only --force: 재시딩";
  else bad "templates-only --force: 재시딩"; fi
  # --template-dir 호환 (커스텀 preset 자동 발견)
  TCUSTOM="$(mktemp -d)"; mkdir -p "$TCUSTOM/zzz"
  printf 'PRESET_DESC="Zzz Custom"\nROLES="orchestrator planner worker reviewer"\nLAYOUT="2col"\n' > "$TCUSTOM/zzz/preset.conf"
  TFC="$(mktemp -d)"
  PATH="$STUB3:$PATH" "$BIN" tmpl --preset zzz --cwd "$TFC" --template-dir "$TCUSTOM" --no-interactive --templates-only >/dev/null 2>&1; C_RC=$?
  assert_exit "$C_RC" 0 "templates-only --template-dir 커스텀 exit 0"
  if [[ -f "$TFC/agents/zzz/tmpl-worker.md" ]]; then ok "커스텀 preset 정본 생성";
  else bad "커스텀 preset 정본 생성"; fi
  rm -rf "$STUB3" "$TF" "$TCUSTOM" "$TFC"
else
  echo "SKIP: jq 없음 → 호환 테스트 생략"
fi

echo "== 6) 미지정 시 기존 동작 유지 (pane split 계획 있음) =="
LEGACY_OUT="$("$BIN" tmpl --preset dev --dry-run --no-template --no-interactive 2>&1)"
assert_contains "$LEGACY_OUT" "herdr pane split" "기본 동작: pane split 계획 유지"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
