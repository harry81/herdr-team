#!/usr/bin/env bash
# tests/test_template_sync.sh — 테스트 티어링 문구의 4위치 정본 동시 반영 검증 (명세 §f/G4)
# 대상: AGENTS.md 루트, agents/dev/ht-worker.md, agents/dev/ht-reviewer.md,
#       templates/agents/ROLE-worker.md, templates/agents/ROLE-reviewer.md
# 실행: bash tests/test_template_sync.sh  (repo root에서)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }
assert_contains() { if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
assert_not_contains() { if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi; }
assert_equal() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 ($1 != $2)"; fi; }

# 정본 위치(§f + 반송1 확장): 루트 AGENTS.md + worker/reviewer 정본 문서 + ROLE 템플릿(agents/, opencode-agents/)
AGENTS_DOC="$REPO/AGENTS.md"
WORKER_DOC="$REPO/agents/dev/ht-worker.md"
REVIEWER_DOC="$REPO/agents/dev/ht-reviewer.md"
ROLE_WORKER="$REPO/templates/agents/ROLE-worker.md"
ROLE_REVIEWER="$REPO/templates/agents/ROLE-reviewer.md"
OA_WORKER="$REPO/templates/opencode-agents/ROLE-worker.md"
OA_REVIEWER="$REPO/templates/opencode-agents/ROLE-reviewer.md"

TIER_MARK='**테스트 티어링 (Fast Loop 원칙)**'
FILES=("$AGENTS_DOC" "$WORKER_DOC" "$REVIEWER_DOC" "$ROLE_WORKER" "$ROLE_REVIEWER" "$OA_WORKER" "$OA_REVIEWER")

echo "== 1) 4위치 파일 존재 =="
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then ok "tier_doc_존재: ${f#$REPO/}"; else bad "tier_doc_존재: ${f#$REPO/}"; fi
done

echo "== 2) 교체 문구 존재 + 기존 조항 삭제 =="
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  T="$(cat "$f")"
  assert_contains "$T" "$TIER_MARK" "tier_문구_존재: ${f#$REPO/}"
  assert_contains "$T" 'T1 Fast-Loop' "tier_T1_명시: ${f#$REPO/}"
  assert_contains "$T" 'T2 Scoped Regression' "tier_T2_명시: ${f#$REPO/}"
  assert_contains "$T" 'T3 Full Regression' "tier_T3_명시: ${f#$REPO/}"
  assert_contains "$T" 'scripts/testmap.sh' "tier_testmap_근거: ${f#$REPO/}"
  assert_contains "$T" 'docs/specs/test-tiering-spec.md' "tier_명세참조: ${f#$REPO/}"
  assert_contains "$T" '[T2 scoped] ' "tier_고지형식: ${f#$REPO/}"
  assert_contains "$T" '재실행 1회' "tier_T2_재실행예산: ${f#$REPO/}"
  # 기존 조항 삭제(전체 회귀 완료 직전 1회 강제 / [full-regression] 고지 형식)
  assert_not_contains "$T" '전체 회귀는 완료 직전 1회만 실행' "tier_구조항_삭제: ${f#$REPO/}"
  assert_not_contains "$T" '[full-regression] 결과를 고지' "tier_구고지_삭제: ${f#$REPO/}"
done

echo "== 3) 4위치 문구 동일성 (문구 라인 md5) =="
HASHES=()
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  LINE="$(grep -F -- "$TIER_MARK" "$f" | head -n1 | sed -e 's/^[0-9]*\. //' -e 's/^[[:space:]]*//' -e 's/^- //')"
  H="$(printf '%s' "$LINE" | md5sum | awk '{print $1}')"
  HASHES+=("$H")
  if [[ -n "$LINE" ]]; then ok "tier_문구라인_추출: ${f#$REPO/}"; else bad "tier_문구라인_추출: ${f#$REPO/}"; fi
done
FIRST="${HASHES[0]:-}"
for i in "${!HASHES[@]}"; do
  assert_equal "${HASHES[$i]}" "$FIRST" "tier_문구_동일성(위치 $((i+1)))"
done

echo "== 4) worker/reviewer 역할 문구 계약 =="
for f in "$WORKER_DOC" "$ROLE_WORKER" "$AGENTS_DOC"; do
  T="$(cat "$f")"
  assert_contains "$T" 'worker의 임의 T3 실행 금지' "worker_T3금지: ${f#$REPO/}"
  assert_contains "$T" '지시 없으면 T1만' "worker_무지시_규약: ${f#$REPO/}"
done
for f in "$REVIEWER_DOC" "$ROLE_REVIEWER" "$AGENTS_DOC"; do
  T="$(cat "$f")"
  assert_contains "$T" 'T3 노드에서만 full regression' "reviewer_T3노드: ${f#$REPO/}"
done

echo "== 4b) 시딩 원본·런타임 사용 지점의 구 조항 제거 (반송1) =="
for f in "$OA_WORKER" "$OA_REVIEWER"; do
  T="$(cat "$f")"
  assert_not_contains "$T" '전체 회귀(pytest -q)는 최종 완료 직전 1회만 실행' "opencode_role_구조항_삭제: ${f#$REPO/}"
  assert_not_contains "$T" '전체 회귀는 최종 완료 직전 1회만 실행' "opencode_role_구조항2_삭제: ${f#$REPO/}"
  assert_not_contains "$T" '최종 완료 직전 전체 회귀 1회' "opencode_role_구조항3_삭제: ${f#$REPO/}"
  assert_not_contains "$T" '[full-regression] pytest -q' "opencode_role_구고지_삭제: ${f#$REPO/}"
  assert_not_contains "$T" '전체 회귀 1회 + DoD 대조' "opencode_role_reviewer_구조항_삭제: ${f#$REPO/}"
  assert_not_contains "$T" '전체 회귀(`pytest -q`) 1회 실행' "opencode_role_reviewer_구조항2_삭제: ${f#$REPO/}"
  assert_not_contains "$T" '[full-regression] 1줄' "opencode_role_구고지1_삭제: ${f#$REPO/}"
  assert_not_contains "$T" 'worker `[full-regression]` 수치' "opencode_role_구고지2_삭제: ${f#$REPO/}"
done
# 런타임 생성물(.opencode/agents/*)은 .gitignore 산출물 → 존재 시에만 검증(시딩 재생성 반영 확인)
for f in "$REPO/.opencode/agents/ht-worker.md" "$REPO/.opencode/agents/ht-reviewer.md"; do
  if [[ -f "$f" ]]; then
    assert_contains "$(cat "$f")" "$TIER_MARK" "runtime_agent_티어문구: ${f#$REPO/}"
    assert_not_contains "$(cat "$f")" '[full-regression] 1줄' "runtime_agent_구고지_삭제: ${f#$REPO/}"
    assert_not_contains "$(cat "$f")" '[full-regression] pytest -q' "runtime_agent_구고지2_삭제: ${f#$REPO/}"
  else
    echo "SKIP: ${f#$REPO/} 부재(.opencode 생성물)"
  fi
done

echo "== 5) 파이프라인 다이어그램 문구 정합(구 '전체 회귀 1회' 잔재 제거) =="
for f in "$AGENTS_DOC" "$REPO/agents/dev/AGENTS.md" "$REPO/templates/dev/AGENTS.md"; do
  [[ -f "$f" ]] || { echo "SKIP: ${f#$REPO/} 부재"; continue; }
  assert_not_contains "$(cat "$f")" '단위 테스트 PASS (전체 회귀 1회)' "diagram_구문구_삭제: ${f#$REPO/}"
done

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
