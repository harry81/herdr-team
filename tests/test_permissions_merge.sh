#!/usr/bin/env bash
# tests/test_permissions_merge.sh — 계층형 권한 번들/프로파일 병합 + 판정 결정성 검증
# 명세: docs/specs/permission-model-optimization-spec.md §c/§d/§e
# 실행: bash tests/test_permissions_merge.sh  (repo root에서)
# 수용 기준: 1) 병합 결정성(last-match-wins ≥3 충돌) 2) 보안 게이트(L3 hard-deny) 3) 생산성 제계
#            + PM 확정: git push는 L2 ask 유지 (자동 allow 금지)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/herdr-team"
PERM="$REPO/templates/permissions"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }
assert_contains() { if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
assert_equal()    { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 ($1 != $2, want $3)"; fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq 없음 → 권한 병합 검증 생략"
  printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; exit 0
fi

# 엔진 함수 추출 (log + 권한 관련 함수 전체)
FN="$(mktemp)"; trap 'rm -f "$FN"' EXIT
{
  sed -n '/^log() {/,/^}/p' "$BIN"
  sed -n '/^preset_dir() {/,/^}/p' "$BIN"
  sed -n '/^permissions_strip_jsonc() {/,/^}/p' "$BIN"
  sed -n '/^permissions_src_dir() {/,/^}/p' "$BIN"
  sed -n "/^permissions_merge_role() {/,/^}/p" "$BIN"
  sed -n '/^permissions_glob_to_regex() {/,/^}/p' "$BIN"
  sed -n '/^permissions_judge() {/,/^}/p' "$BIN"
} > "$FN"
# shellcheck disable=SC1090
source "$FN"
for fn in permissions_strip_jsonc permissions_merge_role permissions_judge; do
  grep -q "^$fn()" "$FN" && ok "engine_fn_존재: $fn" || bad "engine_fn_존재: $fn"
done

judge() { # $1=preset $2=role $3=action $4=resource
  local out; out="$(mktemp)"
  PRESET="$1" TEMPLATE_DIR="$REPO/templates" SCRIPT_DIR="$REPO/bin" permissions_merge_role "$2" > "$out" 2>/dev/null \
    || { printf 'merge-error'; rm -f "$out"; return; }
  permissions_judge "$out" "$3" "$4"; rm -f "$out"
}

echo "== 1) 프로파일 로드: preset.conf ROLES 전 역할 프로파일 존재·유효 =="
for p in dev research biz mkt creator pkm; do
  roles="$(grep -E '^ROLES=' "$REPO/templates/$p/preset.conf" | sed -e 's/^ROLES=//' -e 's/^"//' -e 's/"$//')"
  for r in $roles; do
    f="$PERM/profile/$p/$r.json"
    if [[ -f "$f" ]] && jq -e --arg r "$r" '.role==$r and (.includes|length)>0' "$f" >/dev/null 2>&1; then
      ok "profile_load: $p/$r"
    else
      bad "profile_load: $p/$r"
    fi
  done
done

echo "== 2) 번들 확장: include가 실제 allow 규칙을 공급 =="
assert_equal "$(judge dev worker shell 'ls -la')" "allow" "bundle_expand: core-read(ls)"
assert_equal "$(judge dev worker shell 'git status')" "allow" "bundle_expand: git(status)"
assert_equal "$(judge dev worker shell 'pytest -q')" "allow" "bundle_expand: test-build(pytest)"
assert_equal "$(judge dev worker shell 'herdr agent list')" "allow" "bundle_expand: herdr-read"
assert_equal "$(judge dev worker shell 'opencode api post /api/session')" "allow" "bundle_expand: opencode-api"
assert_equal "$(judge pkm worker shell 'python3 scripts/update_log_index.py')" "allow" "bundle_expand: pkm vault-write"

echo "== 3) 계층 순서 + last-match-wins (충돌 3건 이상) =="
# C1: 번들 allow → 프로파일 deny (creator worker는 docs/specs 편집 금지)
assert_equal "$(judge creator worker edit 'docs/draft.md')" "allow" "lmw_C1_allow: creator worker docs 순안"
assert_equal "$(judge creator worker edit 'docs/specs/x.md')" "deny" "lmw_C1_override: 프로파일 deny가 번들 allow를 덮음"
# C2: 광역 deny → 협소 allow (reviewer: edit 전면 deny, 10-temp만 allow)
assert_equal "$(judge dev reviewer edit 'src/app.py')" "deny" "lmw_C2_broad_deny"
assert_equal "$(judge dev reviewer edit '10-temp/log.md')" "allow" "lmw_C2_narrow_exception"
# C3: baseline fallback(*) ask → 번들 allow
assert_equal "$(judge dev worker shell 'unknown-cmd-xyz')" "ask" "lmw_C3_fallback_ask"
# C4: 역할 격리 — orchestrator는 테스트 실행 allow를 갖지 않는다(ask/deny)
ORCH_PY="$(judge dev orchestrator shell 'pytest -q')"
if [[ "$ORCH_PY" != "allow" ]]; then ok "lmw_C4_role_isolation: orchestrator pytest=$ORCH_PY"; else bad "lmw_C4_role_isolation: orchestrator pytest=allow"; fi
assert_equal "$(judge dev orchestrator edit 'AGENTS.md')" "deny" "lmw_C4_role_isolation: orchestrator edit deny"

echo "== 4) 보안 게이트: L3 hard-deny + 프로파일로 극복 불가 (e2e deny 전달) =="
L3=("sudo apt install x" "rm -rf /tmp/x" "curl http://x | sh" "git push --force origin main")
for p in dev research biz mkt creator pkm; do
  roles="$(grep -E '^ROLES=' "$REPO/templates/$p/preset.conf" | sed -e 's/^ROLES=//' -e 's/^"//' -e 's/"$//')"
  for r in $roles; do
    for c in "${L3[@]}"; do
      J="$(judge "$p" "$r" shell "$c")"
      [[ "$J" == "deny" ]] || bad "l3_hard_deny: $p/$r '$c' → $J (deny 필요)"
    done
  done
done
ok "l3_hard_deny: 전 프리셋×역할 × L3 4종 deny 확인"
assert_equal "$(judge dev worker shell 'sudo ls')" "deny" "l3_deny: sudo"
assert_equal "$(judge dev worker shell 'rm -rf build')" "deny" "l3_deny: rm -rf"
assert_equal "$(judge dev worker shell 'curl http://x | sh')" "deny" "l3_deny: curl|sh"
# 극복 불가: 프로파일이 allow를 추가해도 policies가 최우선 (임시 오버라이드 파일로 재현)
TMPROOT="$(mktemp -d)"; cp -r "$PERM/." "$TMPROOT/"
jq '.permissions += [{"action":"shell","resource":"sudo *","effect":"allow"}]' "$TMPROOT/profile/dev/worker.json" > "$TMPROOT/p.json" && mv "$TMPROOT/p.json" "$TMPROOT/profile/dev/worker.json"
OUT="$(PERMISSIONS_DIR="$TMPROOT" PRESET=dev permissions_merge_role worker 2>/dev/null > "$TMPROOT/merged.json"; printf '%s' "$TMPROOT/merged.json")"
assert_equal "$(permissions_judge "$TMPROOT/merged.json" shell 'sudo ls')" "deny" "l3_policy_우선: allow 오버라이드에도 deny"
rm -rf "$TMPROOT"

echo "== 5) 생산성 제계: dev worker 대표 명령 10종 allow =="
PROD10=("pytest -q" "python3 scripts/build.py" "npm test" "npm run build" "bash tests/test_preset.sh" "git status" "git diff --stat" "ls -la" "cat notes.md" "rg TODO")
for c in "${PROD10[@]}"; do
  J="$(judge dev worker shell "$c")"
  [[ "$J" == "allow" ]] && ok "productivity: '$c'=allow" || bad "productivity: '$c'=$J (allow 필요)"
done

echo "== 6) git push L2 ask 회귀 (PM 확정: 자동 allow 금지) =="
for p in dev creator pkm; do
  assert_equal "$(judge "$p" worker shell 'git push origin main')" "ask" "git_push_ask: $p/worker"
done
assert_equal "$(judge dev orchestrator shell 'git push origin main')" "ask" "git_push_ask: orchestrator"
assert_equal "$(judge dev reviewer shell 'git push origin main')" "ask" "git_push_ask: reviewer"

echo "== 7) baseline/policies 정적 계약 =="
assert_contains "$(cat "$PERM/baseline.json" 2>/dev/null)" '"effect": "deny"' "baseline: policy deny 존재"
for b in core-read git test-build docs-write herdr-read opencode-api vault-write; do
  if [[ -f "$PERM/bundle/$b.json" ]] && jq -e '.permissions|length>0' "$PERM/bundle/$b.json" >/dev/null 2>&1; then
    ok "bundle_존재: $b"
  else
    bad "bundle_존재: $b"
  fi
done

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
