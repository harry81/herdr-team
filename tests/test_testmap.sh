#!/usr/bin/env bash
# tests/test_testmap.sh — scripts/testmap.sh 수용 테스트 (명세 docs/specs/test-tiering-spec.md §e 9건 + 설정 파일 override)
# 실행: bash tests/test_testmap.sh  (repo root에서)
# fixture: 임시 git repo를 만들어 변경 파일 조합별 출력을 검증한다(네트워크·외부 도구 불사용).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TM="$REPO/scripts/testmap.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }
assert_contains() { if printf '%s' "$1" | grep -F -- "$2" >/dev/null; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
assert_not_contains() { if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi; }
assert_equal() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 ($1 != $2, want $3)"; fi; }
assert_exit() { if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi; }

if [[ ! -f "$TM" ]]; then
  bad "testmap_스크립트_존재: scripts/testmap.sh"
  printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; exit 1
fi
ok "testmap_스크립트_존재: scripts/testmap.sh"

# --- fixture git repo ---
mk_fixture() { # $1=dir  → 본 레포와 동일한 경로 레이아웃을 갖춘 git repo
  mkdir -p "$1"/{bin,scripts,tests,templates,docs,.github/workflows,src}
  for f in tests/test_preset.sh tests/test_agent_session.sh tests/test_pane_ready.sh tests/test_permissions_seed.sh tests/test_permissions_merge.sh tests/test_pkm_preset.sh tests/test_templates_only.sh tests/test_testmap.sh tests/test_template_sync.sh tests/test_watcher.sh tests/test_watcher_start.sh; do : > "$1/$f"; done
  : > "$1/bin/herdr-team"; : > "$1/bin/herdr-watcher"; : > "$1/scripts/build-zip.sh"; : > "$1/AGENTS.md"; : > "$1/src/app.ts"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm base )
}
run_tm() { # $1=fixture dir  [extra args...]
  local d="$1"; shift
  ( cd "$d" && bash "$TM" "$@" )
}

D1="$(mktemp -d)"; mk_fixture "$D1"
trap 'rm -rf "$D1" "$D2" "$D3" "$D4" "$D5"' EXIT

echo "== 1) 변경 없음 → 스위트 0, exit 0 =="
OUT="$(run_tm "$D1")"; RC=$?
assert_exit "$RC" 0 "nochange_exit_0"
assert_equal "$OUT" "" "nochange_스위트_0"

echo "== 2) bin/herdr-team 변경 → 기대 스위트 전부 출력 =="
printf 'v2\n' >> "$D1/bin/herdr-team"
OUT="$(run_tm "$D1")"
for s in tests/test_agent_session.sh tests/test_pane_ready.sh tests/test_preset.sh; do
  assert_contains "$OUT" "$s" "bin_change_기대스위트: $s"
done
assert_not_contains "$OUT" "unclassified" "bin_change_미분류_없음(bare 모드)"

echo "== 2b) bin/herdr-watcher 변경 → watcher 2스위트 매핑 (R-01) =="
printf 'v2\n' >> "$D1/bin/herdr-watcher"
OUT="$(run_tm "$D1")"
for s in tests/test_watcher.sh tests/test_watcher_start.sh; do
  assert_contains "$OUT" "$s" "watcher_change_기대스위트: $s"
done
assert_contains "$OUT" "tests/test_preset.sh" "watcher_change_bin와일드카드_회귀"

echo "== 3) 매핑된 파일 변경 → 그 파일 자체 스위트 =="
printf 'x\n' >> "$D1/tests/test_preset.sh"
OUT="$(run_tm "$D1")"
assert_contains "$OUT" "tests/test_preset.sh" "mapped_self_suite"

echo "== 4) 문서만 변경 → 스위트 0 + unclassified 기재 =="
( cd "$D1" && git add -A && git commit -qm prior-changes )   # 앞 단계 변경을 기준선으로 커밋(격리)
printf '# doc\n' > "$D1/docs/only-doc.md"
OUT_JSON="$(run_tm "$D1" --mode json)"
assert_contains "$OUT_JSON" '"suites":[]' "docs_only_suites_0"
assert_contains "$OUT_JSON" 'docs/only-doc.md' "docs_only_unclassified_기재"

echo "== 5) 매핑 표에 없는 파일 → fallback 스위트 + unclassified =="
printf 'zzz\n' > "$D1/weird.dat"
OUT_JSON="$(run_tm "$D1" --mode json)"
assert_contains "$OUT_JSON" 'weird.dat' "unknown_unclassified_기재"
FB="$(run_tm "$D1")"
assert_not_contains "$FB" 'weird.dat' "unknown_bare모드_경로미출력"
if printf '%s' "$FB" | grep -qE '^tests/'; then ok "unknown_fallback_스위트_출력"; else bad "unknown_fallback_스위트_출력"; fi
rm -f "$D1/weird.dat"

echo "== 6) git repo 이외 실행 → 명시적 에러 + exit 1 =="
D2="$(mktemp -d)"
OUT6="$( cd "$D2" && bash "$TM" 2>&1 )"; RC6=$?
assert_exit "$RC6" 1 "not_git_exit_1"
assert_contains "$OUT6" "git" "not_git_에러_메시지"

echo "== 7) 결정성: 3회 반복 출력 동일 =="
A="$(run_tm "$D1")"; B="$(run_tm "$D1")"; C="$(run_tm "$D1")"
assert_equal "$A" "$B" "determinism_run1_run2"
assert_equal "$B" "$C" "determinism_run2_run3"

echo "== 8) 성능: 1초 이내 =="
T0=$(date +%s%N); run_tm "$D1" >/dev/null 2>&1; T1=$(date +%s%N)
MS=$(( (T1-T0)/1000000 ))
if [[ "$MS" -lt 1000 ]]; then ok "perf_1s_이내 (${MS}ms)"; else bad "perf_1s_이내 (${MS}ms)"; fi

echo "== 9) json 모드: 키 고정 + 유효 JSON =="
J="$(run_tm "$D1" --mode json)"
assert_equal "$(printf '%s' "$J" | jq -r 'keys | sort | join(",")')" "suites,unclassified" "json_키_고정"
if printf '%s' "$J" | jq -e . >/dev/null 2>&1; then ok "json_유효성"; else bad "json_유효성"; fi

echo "== 10) --base REF: 커밋 범위 기준 매핑 =="
( cd "$D1" && git add -A && git commit -qm change1 )
printf 'y\n' >> "$D1/src/app.ts"   # 아직 커밋 전 → --base HEAD 범위에서 제외되어야 함
OUT10="$(run_tm "$D1" --base HEAD)"
assert_not_contains "$OUT10" "src/app.ts" "base_ref_범위_제한"
TM_JSON="$(run_tm "$D1" --base HEAD --mode json)"
assert_contains "$TM_JSON" '"suites"' "base_ref_json_형식"

echo "== 11) 설정 파일 override(.testmap.conf): 코어 필터 + 파일→스위트 추가 =="
D3="$(mktemp -d)"; mk_fixture "$D3"
cat > "$D3/.testmap.conf" <<'EOC'
# 프로젝트 로컬 매핑 확장
FALLBACK="tests/test_preset.sh"
CORE="src/ vendor/"
MAP="src/* -> tests/test_preset.sh, tests/test_testmap.sh"
EOC
printf 'z\n' >> "$D3/src/app.ts"
OUT11="$(run_tm "$D3")"
# 정확 비교: 콤마 구분 다중 스위트가 각각 한 줄로 정규화되어야 한다(반송2)
assert_equal "$(printf '%s' "$OUT11" | sort | tr '\n' ' ')" "tests/test_preset.sh tests/test_testmap.sh " "conf_map_정확목록"
assert_not_contains "$OUT11" "," "conf_map_콤마_잔재_없음"
J11="$(run_tm "$D3" --mode json)"
assert_equal "$(printf '%s' "$J11" | jq -c '.suites')" '["tests/test_preset.sh","tests/test_testmap.sh"]' "conf_map_json_정확목록"
OUT11B="$(run_tm "$D3" --mode json | jq -r '.suites as $s | "\($s|length)"')"
assert_equal "$OUT11B" "2" "conf_map_스위트_개수"
ERR11="$( cd "$D3" && bash "$TM" 2>&1 >/dev/null )"
assert_contains "$ERR11" "core" "conf_core_필터_승격안내(stderr)"

echo "== 12) 설정 파일 FALLBACK override 반영 =="
D4="$(mktemp -d)"; mk_fixture "$D4"
cat > "$D4/.testmap.conf" <<'EOC'
FALLBACK="tests/test_agent_session.sh"
EOC
printf 'q\n' > "$D4/mystery.bin"
OUT12="$(run_tm "$D4")"
assert_contains "$OUT12" "tests/test_agent_session.sh" "conf_fallback_override"

echo "== 13) stdout 순수성: core 안내는 stderr로만 =="
D5="$(mktemp -d)"; mk_fixture "$D5"
printf 'c\n' >> "$D5/bin/herdr-team"
assert_not_contains "$(run_tm "$D5" 2>/dev/null)" "core" "core_안내_stdout_미포함"
J5="$(run_tm "$D5" --mode json 2>/dev/null)"
if printf '%s' "$J5" | jq -e . >/dev/null 2>&1; then ok "core변경_json_유효성_유지"; else bad "core변경_json_유효성_유지"; fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
