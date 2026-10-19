#!/usr/bin/env bash
# tests/test_pkm_preset.sh — pkm 프리셋(templates/pkm/) 전용 TDD 검증
# 범위: 프리셋 발견 / preset.conf ROLE 파싱 / 시딩 gen 배선 (spec: docs/specs/pkm-preset-spec.md)
# 실행: bash tests/test_pkm_preset.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
PKM="$REPO/templates/pkm"
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

ROLES5="orchestrator planner researcher worker reviewer"

echo "== 1) 프리셋 발견: templates/pkm/preset.conf =="
if [[ -f "$PKM/preset.conf" ]]; then ok "pkm_preset_conf_존재"; else bad "pkm_preset_conf_존재"; fi
CONF="$(cat "$PKM/preset.conf" 2>/dev/null || true)"
assert_contains "$CONF" 'PRESET_DESC="PKM Vault Team' "pkm_conf_desc"
assert_contains "$CONF" "ROLES=\"$ROLES5\"" "pkm_conf_roles_5역할"
assert_contains "$CONF" 'LAYOUT="2col"' "pkm_conf_layout_2col"
LIST_OUT="$("$BIN" --list-presets 2>&1)"; LIST_RC=$?
assert_exit "$LIST_RC" 0 "pkm_list_presets_exit_0"
assert_contains "$LIST_OUT" "pkm" "pkm_list_presets_노출"
assert_contains "$LIST_OUT" "PKM Vault Team" "pkm_list_presets_desc_표시"
HELP_OUT="$("$BIN" --help 2>&1 || true)"
assert_contains "$HELP_OUT" "pkm" "pkm_help_노출"

echo "== 2) prefix 규칙: 프로젝트명 기반 ({{PREFIX}} 치환, pk- 하드코딩 금지) =="
if grep -rqF -- 'pk-' "$PKM" 2>/dev/null; then bad "pkm_prefix_pk_하드코딩_없음 (pk- 발견)"; else ok "pkm_prefix_pk_하드코딩_없음"; fi
if grep -rqF '{{PREFIX}}' "$PKM" 2>/dev/null; then ok "pkm_prefix_치환양식_사용"; else bad "pkm_prefix_치환양식_사용"; fi

echo "== 3) ROLE 파싱: dry-run에 5역할 에이전트 반영 =="
DRY_OUT="$("$BIN" pfx --preset pkm --dry-run --no-template --no-interactive 2>&1)"; DRY_RC=$?
assert_exit "$DRY_RC" 0 "pkm_dry_run_exit_0"
assert_contains "$DRY_OUT" "preset=pkm" "pkm_dry_run_preset_표시"
assert_contains "$DRY_OUT" "layout=2col" "pkm_dry_run_layout_반영"
for r in $ROLES5; do
  assert_contains "$DRY_OUT" "pfx-$r" "pkm_dry_run_role: $r"
done

echo "== 4) 정본 문서: templates/pkm/AGENTS.md (명세 구조 준용) =="
if [[ -f "$PKM/AGENTS.md" ]]; then ok "pkm_agents_md_존재"; else bad "pkm_agents_md_존재"; fi
AG="$(cat "$PKM/AGENTS.md" 2>/dev/null || true)"
assert_contains "$AG" "(preset: pkm)" "pkm_agents_md_preset_표기"
for r in $ROLES5; do
  assert_contains "$AG" "{{PREFIX}}-$r" "pkm_agents_md_5역할_표기: $r"
done
assert_contains "$AG" "agents/{{PRESET}}/{{PREFIX}}-" "pkm_agents_md_정본링크_양식"
assert_contains "$AG" "중복 대기 금지" "pkm_agents_md_가드레일_NRW"
assert_contains "$AG" "--until idle --until done" "pkm_agents_md_가드레일_until"

echo "== 5) 5역할 ROLE 정의문 존재 + PKM 도메인 규칙 =="
for r in $ROLES5; do
  if [[ -f "$PKM/agents/ROLE-$r.md" ]]; then ok "pkm_role_doc_존재: ROLE-$r.md"; else bad "pkm_role_doc_존재: ROLE-$r.md"; fi
  ROLE_TXT="$(cat "$PKM/agents/ROLE-$r.md" 2>/dev/null || true)"
  assert_contains "$ROLE_TXT" "볼트" "pkm_role_doc_PKM도메인: ROLE-$r.md"
done
assert_contains "$(cat "$PKM/agents/ROLE-worker.md" 2>/dev/null || true)" "10-temp" "pkm_worker_삭제보관규칙"
assert_contains "$(cat "$PKM/agents/ROLE-planner.md" 2>/dev/null || true)" "docs/specs/" "pkm_planner_문서전용쓰기"
assert_contains "$(cat "$PKM/agents/ROLE-researcher.md" 2>/dev/null || true)" "읽기" "pkm_researcher_읽기전용"

echo "== 6) gen 배선: 시딩 산출물 (prefix=sb — SecondBrain 시나리오) =="
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"; CWD="$(mktemp -d)"
  cat > "$STUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$STUB/herdr"
  PATH="$STUB:$PATH" "$BIN" sb --preset pkm --cwd "$CWD" --template-dir "$REPO/templates" --no-interactive --no-start >/dev/null 2>&1
  GEN_RC=$?
  assert_exit "$GEN_RC" 0 "pkm_gen_exit_0"
  for r in $ROLES5; do
    if [[ -f "$CWD/agents/pkm/sb-$r.md" ]]; then ok "pkm_gen_정본_role: agents/pkm/sb-$r.md"; else bad "pkm_gen_정본_role: agents/pkm/sb-$r.md"; fi
    if [[ -f "$CWD/.opencode/agents/sb-$r.md" ]]; then ok "pkm_gen_opencode_agent: sb-$r.md"; else bad "pkm_gen_opencode_agent: sb-$r.md"; fi
  done
  if [[ "$(cat "$CWD/.herdr-team/preset" 2>/dev/null)" == "pkm" ]]; then ok "pkm_gen_state_활성화"; else bad "pkm_gen_state_활성화"; fi
  if [[ -f "$CWD/AGENTS.md" && -f "$CWD/agents/pkm/AGENTS.md" ]] && cmp -s "$CWD/AGENTS.md" "$CWD/agents/pkm/AGENTS.md"; then
    ok "pkm_gen_루트_활성화: AGENTS.md == agents/pkm/AGENTS.md"
  else
    bad "pkm_gen_루트_활성화: AGENTS.md == agents/pkm/AGENTS.md"
  fi
  # 치환 잔존 없음 + preset-local ROLE 문서 우선 적용(공용 템플릿 아닌 pkm 전용 내용)
  SEEDED="$(cat "$CWD/agents/pkm/sb-worker.md" 2>/dev/null || true)"
  assert_not_contains "$SEEDED" "{{PREFIX}}" "pkm_gen_치환잔존_없음"
  assert_contains "$SEEDED" "볼트" "pkm_gen_preset_local_role_우선"
  ROOT_AG="$(cat "$CWD/AGENTS.md" 2>/dev/null || true)"
  assert_contains "$ROOT_AG" "preset: pkm" "pkm_gen_root_preset_표기"
  assert_not_contains "$ROOT_AG" "{{PRESET}}" "pkm_gen_root_치환잔존_없음"
  # frontmatter 구조 검사 (T5 자가검증: YAML 헤더 형식)
  OA="$(cat "$CWD/.opencode/agents/sb-worker.md" 2>/dev/null || true)"
  assert_contains "$OA" "mode: primary" "pkm_gen_frontmatter_mode"
  rm -rf "$STUB" "$CWD"
else
  echo "SKIP: jq 없음 → gen 배선 테스트 생략"
fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
