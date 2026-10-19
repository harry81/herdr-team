#!/usr/bin/env bash
# tests/test_permissions_seed.sh — 시딩 통합: 프로파일 병합 결과가 OpenCode V2가 실제 소비하는 위치에 생성되는지 검증
#
# [실측 근거 — opencode v2.0.32, 2026-10-19]
#   - `opencode debug agents`: agent별 유효 권한 노출. agent md frontmatter의
#     `permissions:`(V2 배열)와 `permission:`(V1 map) **둘 다 소비**됨(v2probe/v1probe 각각 반영 확인).
#     frontmatter `policies:`는 request.body.policies로 전달됨(에스컬레이션 불가 L3 정책).
#   - 프로젝트 `.opencode/opencode.jsonc`도 config source로 소비됨(`opencode debug config`에 규칙 노출).
#   - 임의 파일명 `.opencode/agents/<prefix>-<role>.permissions.jsonc`는 소비되지 않음(리뷰어 지적 실측 확인)
#     → 시딩 경로 변경: (a) agent frontmatter V2 permissions/policies, (b) .opencode/opencode.jsonc(기존 파일 보존 병합)
#
# 실행: bash tests/test_permissions_seed.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }
assert_contains() { if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
assert_not_contains() { if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi; }
assert_equal()    { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 ($1 != $2, want $3)"; fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq 없음 → 시딩 통합 검증 생략"
  printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; exit 0
fi

strip_jsonc() { sed -e 's/^[[:space:]]*\/\/.*$//' "$1" | jq . 2>/dev/null; }

STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/herdr" <<'STUBEOF'
#!/usr/bin/env bash
case "${1:-}" in
  pane)
    case "${2:-}" in
      run|wait-output) printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n' ;;
      process-info) printf '{"result":{"process_info":{"shell_pid":42,"foreground_process_group_id":42}}}\n' ;;
      *) printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n' ;;
    esac ;;
  agent)
    case "${2:-}" in
      list) exit 1 ;;
      start) printf '%s\n' "$*" >> "${HT_START_LOG:-/dev/null}" ;;
    esac ;;
esac
exit 0
STUBEOF
chmod +x "$STUB/herdr"
cat > "$STUB/opencode" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"data":{"id":"ses_fake"}}\n'
STUBEOF
chmod +x "$STUB/opencode"

seed() { # $1=cwd  $2=preset  [extra args...]
  local cwd="$1" pre="$2"; shift 2
  PATH="$STUB:$PATH" "$BIN" pfx --preset "$pre" --cwd "$cwd" --template-dir "$REPO/templates" --no-interactive --no-start "$@" >/dev/null 2>&1
}

echo "== 1) 프로젝트 opencode.jsonc: 생성·JSONC 유효성·\$schema·L3 정책 =="
C1="$(mktemp -d)"; seed "$C1" dev
if [[ -f "$C1/.opencode/opencode.jsonc" ]]; then ok "seed_jsonc_생성"; else bad "seed_jsonc_생성"; fi
JSONC="$(cat "$C1/.opencode/opencode.jsonc" 2>/dev/null)"
assert_contains "$JSONC" '"$schema"' "seed_jsonc_schema_존재"
assert_contains "$JSONC" 'AUTO-GENERATED' "seed_jsonc_auto_gen_표시"
if strip_jsonc "$C1/.opencode/opencode.jsonc" >/dev/null 2>&1; then ok "seed_jsonc_유효성: JSON 파스 성공"; else bad "seed_jsonc_유효성"; fi
assert_contains "$(strip_jsonc "$C1/.opencode/opencode.jsonc" | jq -c '.policies' 2>/dev/null)" "sudo" "seed_jsonc_L3_policy_전역"

echo "== 2) 역할별 병합 → agent frontmatter(V2 permissions/policies) =="
for r in orchestrator planner worker reviewer; do
  f="$C1/.opencode/agents/pfx-$r.md"
  if [[ -f "$f" ]] && grep -q '^permissions:' "$f"; then ok "seed_frontmatter_permissions: pfx-$r.md"; else bad "seed_frontmatter_permissions: pfx-$r.md"; fi
done
FW="$(cat "$C1/.opencode/agents/pfx-worker.md" 2>/dev/null)"
assert_contains "$FW" 'resource: "pytest*"' "seed_frontmatter_rule: worker pytest allow"
assert_contains "$FW" 'resource: "git push*"' "seed_frontmatter_rule: worker git push ask"
assert_contains "$(printf '%s' "$FW" | grep -A1 'resource: "git push\*"')" 'effect: ask' "seed_frontmatter_effect: git push=ask"
assert_contains "$(cat "$C1/.opencode/agents/pfx-orchestrator.md" 2>/dev/null)" 'effect: deny' "seed_frontmatter_boundary: orchestrator deny"
# 로더 계약: agent 설정 스키마(Config.AgentEncoded)에 policies 키가 없으므로 frontmatter에 두지 않는다(실측)
assert_not_contains "$FW" 'policies:' "loader_contract: frontmatter policies 미사용(스키마 미지원)"
FW_KEYS="$(awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^[a-zA-Z_]+:/{sub(/:.*/,"");print}' "$C1/.opencode/agents/pfx-worker.md" | sort -u | tr '\n' ' ')"
assert_equal "$FW_KEYS" "description mode permissions " "loader_contract: frontmatter 키 = 스키마 허용 집합"
# L3 정책은 프로젝트 opencode.jsonc top-level에만 존재(스키마: action tool.use, effect deny)
POL="$(strip_jsonc "$C1/.opencode/opencode.jsonc" | jq -c '.policies')"
assert_contains "$POL" '{"action":"tool.use","resource":"shell:sudo *","effect":"deny"}' "policy_contract: sudo deny"
assert_contains "$POL" '{"action":"tool.use","resource":"shell:rm -rf *","effect":"deny"}' "policy_contract: rm -rf deny"
BADACTION="$(strip_jsonc "$C1/.opencode/opencode.jsonc" | jq -r '[.policies[] | select((.action=="tool.use" or .action=="provider.use" or .action=="integration.use") and (.effect=="allow" or .effect=="deny") | not)] | length')"
assert_equal "$BADACTION" "0" 'policy_contract: 스키마 enum 준수(action/effect)'
assert_not_contains "$FW" 'permission:' "seed_frontmatter_v1_제거: V1 permission 블록 미사용"
if [[ ! -e "$C1/.opencode/agents/pfx-worker.permissions.jsonc" ]]; then ok "seed_ineffective_artifact_제거: .permissions.jsonc 미생성"; else bad "seed_ineffective_artifact_제거"; fi

echo "== 3) 실측 증거: opencode debug agents에 시딩 권한 반영 =="
if command -v opencode >/dev/null 2>&1; then
  printf '{"dependencies":{}}\n' > "$C1/.opencode/package.json"   # project agent 로딩 요건(실측: package.json)
  ( cd "$C1" && git init -q . ) >/dev/null 2>&1                        # project 감지 요건(실측: git repo)
  # 실측: 시딩 직후 첫 호출은 프로젝트 agent 인덱싱이 끝나기 전이라 비어 있을 수 있음 → bounded 재시도(워밍업)
  DA_JSON=""
  for _i in 1 2 3 4 5 6; do
    DA_JSON="$(cd "$C1" && opencode debug agents 2>/dev/null)"
    [[ "$(printf '%s' "$DA_JSON" | jq -r '[.[].id | select(startswith("pfx"))] | length' 2>/dev/null)" != "0" ]] && break
    sleep 1
  done
  WR_EFF="$(printf '%s' "$DA_JSON" | jq -c '.[] | select(.id=="pfx-worker") | [.permissions[] | select(.resource=="pytest*" or .resource=="git push*" or (.action=="edit" and .resource=="*"))]' 2>/dev/null)"
  assert_contains "$WR_EFF" '{"action":"shell","resource":"pytest*","effect":"allow"}' "debug_agents_evidence: worker pytest=allow(유효 권한)"
  assert_contains "$WR_EFF" '{"action":"shell","resource":"git push*","effect":"ask"}' "debug_agents_evidence: worker git push=ask(유효 권한)"
  assert_contains "$WR_EFF" '{"action":"edit","resource":"*","effect":"deny"}' "debug_agents_evidence: worker edit 경계"
  # frontmatter policies는 스키마 미지원 → agent request.body에 정책이 실리지 않아야 함(권한 블록 붕괴 방지)
  assert_equal "$(printf '%s' "$DA_JSON" | jq -r '.[] | select(.id=="pfx-worker") | (.request.body.policies // "none")')" "none" "debug_agents_evidence: agent policies 미전달(스키마 준수)"
  # 역할 격리: orchestrator 유효 권한에는 pytest allow 규칙이 없고 edit deny 경계만 있다
  OR_EFF="$(printf '%s' "$DA_JSON" | jq -c '.[] | select(.id=="pfx-orchestrator") | [.permissions[] | select((.action=="edit" and .resource=="*") or (.action=="shell" and .resource=="pytest*"))]' 2>/dev/null)"
  assert_contains "$OR_EFF" '{"action":"edit","resource":"*","effect":"deny"}' "debug_agents_evidence: orchestrator edit=deny"
  assert_not_contains "$OR_EFF" 'pytest*' "debug_agents_evidence: orchestrator pytest≠allow(역할 격리)"
  # L3 정책 소비 위치: 프로젝트 .opencode/opencode.jsonc가 config source로 로드되고 top-level policies를 보유
  SRC="$(cd "$C1" && opencode debug config 2>/dev/null | jq -c --arg p "$C1/.opencode/opencode.jsonc" '.[] | select(.path==$p) | .info.policies' 2>/dev/null)"
  assert_contains "$SRC" '"resource":"shell:sudo *"' "e2e_evidence: jsonc policies 로더 소비(sudo deny)"
  assert_contains "$SRC" '"resource":"shell:rm -rf *"' "e2e_evidence: jsonc policies 로더 소비(rm -rf deny)"
else
  echo "SKIP: opencode 부재 → debug agents 실측 생략"
fi

echo "== 4) 하위 호환: 기존 .opencode/agents/*.md 시딩 유지 =="
for r in orchestrator planner worker reviewer; do
  f="$C1/.opencode/agents/pfx-$r.md"
  if [[ -f "$f" ]] && grep -q 'mode: primary' "$f"; then ok "backcompat_agent_md: pfx-$r.md"; else bad "backcompat_agent_md: pfx-$r.md"; fi
done
if [[ "$(cat "$C1/.herdr-team/preset" 2>/dev/null)" == "dev" ]]; then ok "backcompat_state: .herdr-team/preset=dev"; else bad "backcompat_state"; fi
if [[ -f "$C1/agents/dev/pfx-worker.md" ]]; then ok "backcompat_canonical: agents/dev/pfx-worker.md"; else bad "backcompat_canonical"; fi

echo "== 5) pkm(5역할) 시딩 =="
C2="$(mktemp -d)"; seed "$C2" pkm
for r in orchestrator planner researcher worker reviewer; do
  f="$C2/.opencode/agents/pfx-$r.md"
  if [[ -f "$f" ]] && grep -q '^permissions:' "$f"; then ok "seed_pkm_frontmatter: $r"; else bad "seed_pkm_frontmatter: $r"; fi
done
assert_contains "$(cat "$C2/.opencode/agents/pfx-worker.md" 2>/dev/null)" 'resource: "06-Wiki/*"' "seed_pkm_domain: vault 경로 allow 규칙"

echo "== 6) 기존 사용자 opencode.jsonc 보존 병합 + 백업 =="
C3="$(mktemp -d)"; mkdir -p "$C3/.opencode"
cat > "$C3/.opencode/opencode.jsonc" <<'EOUSR'
{
  // 사용자 수동 설정 (보존되어야 함)
  "model": "custom/model-x",
  "theme": "user-theme",
  "permissions": [
    { "action": "shell", "resource": "my-custom-cmd*", "effect": "allow" }
  ]
}
EOUSR
seed "$C3" dev
if [[ -f "$C3/.opencode/opencode.jsonc.bak" ]]; then ok "user_merge_backup: .bak 생성"; else bad "user_merge_backup: .bak 생성"; fi
assert_contains "$(cat "$C3/.opencode/opencode.jsonc.bak" 2>/dev/null)" "my-custom-cmd" "user_merge_backup: 원본 내용 보존"
MER="$(cat "$C3/.opencode/opencode.jsonc")"
assert_contains "$MER" '"model": "custom/model-x"' "user_merge_preserve: 사용자 키(model) 보존"
assert_contains "$MER" '"theme": "user-theme"' "user_merge_preserve: 사용자 키(theme) 보존"
assert_contains "$MER" 'my-custom-cmd' "user_merge_preserve: 사용자 권한 규칙 보존"
assert_contains "$MER" 'sudo' "user_merge_preserve: L3 정책 병합"
assert_contains "$MER" '$schema' "user_merge_preserve: \$schema 보강"
if strip_jsonc "$C3/.opencode/opencode.jsonc" >/dev/null 2>&1; then ok "user_merge_valid: 병합 결과 JSON 유효"; else bad "user_merge_valid"; fi
# 멱등성: 재시딩해도 중복 규칙 없음
seed "$C3" dev
DUP=$(printf '%s' "$(strip_jsonc "$C3/.opencode/opencode.jsonc" | jq -c '[.permissions[] | select(.resource=="my-custom-cmd*")] | length')")
assert_equal "$DUP" "1" "user_merge_idempotent: 중복 규칙 없음"
SUDON=$(printf '%s' "$(strip_jsonc "$C3/.opencode/opencode.jsonc" | jq -c '[.policies[] | select(.resource=="shell:sudo *")] | length')")
assert_equal "$SUDON" "1" "user_merge_idempotent: policies 중복 없음"
# 사용자 파일이 깨진 JSON이면: 백업만 하고 원본 유지(덮어쓰기 금지)
C3b="$(mktemp -d)"; mkdir -p "$C3b/.opencode"
printf '{ "model": "x", BROKEN' > "$C3b/.opencode/opencode.jsonc"
seed "$C3b" dev
if grep -q 'BROKEN' "$C3b/.opencode/opencode.jsonc"; then ok "user_merge_invalid: 원본 보존(덮어쓰기 금지)"; else bad "user_merge_invalid: 원본 보존"; fi
if [[ -f "$C3b/.opencode/opencode.jsonc.bak" ]]; then ok "user_merge_invalid: 백업 생성"; else bad "user_merge_invalid: 백업 생성"; fi

echo "== 7) dry-run: 계획 출력 + 쓰기 0 =="
C4="$(mktemp -d)"
DRY_OUT="$(PATH="$STUB:$PATH" "$BIN" pfx --preset dev --cwd "$C4" --template-dir "$REPO/templates" --no-interactive --no-start --dry-run 2>&1)"
assert_contains "$DRY_OUT" ".opencode/opencode.jsonc" "dryrun_jsonc_계획"
assert_contains "$DRY_OUT" "permissions" "dryrun_profile_계획"
if [[ ! -e "$C4/.opencode/opencode.jsonc" ]]; then ok "dryrun_쓰기0: jsonc 미생성"; else bad "dryrun_쓰기0"; fi

echo "== 8) --no-template: 권한 시딩 생략 =="
C5="$(mktemp -d)"; seed "$C5" dev --no-template
if [[ ! -e "$C5/.opencode/opencode.jsonc" ]]; then ok "no_template_생략"; else bad "no_template_생략"; fi

rm -rf "$C1" "$C2" "$C3" "$C3b" "$C4" "$C5"

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
