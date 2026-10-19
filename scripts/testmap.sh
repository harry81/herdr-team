#!/usr/bin/env bash
# scripts/testmap.sh — git diff 변경 파일 → 실행할 테스트 스위트 매핑 (T2 Scoped Regression)
# 명세: docs/specs/test-tiering-spec.md §e (매핑 스크립트 인터페이스)
#
# 사용법: scripts/testmap.sh [--base REF] [--mode bare|json]
#   - git repo 루트에서 실행. repo 밖/비 git → 명시적 에러 + exit 1
#   - bare(기본): 한 줄당 스위트 경로 / json: {"suites":[...],"unclassified":[...]}
#   - --base REF: REF..HEAD 커밋 범위만 대상(미지정 시 워킹트리 변경 + 미추적 파일)
#   - 설정 파일 override: <repo root>/.testmap.conf
#       FALLBACK="tests/test_preset.sh"     # 미분류 파일 발생 시 기본 스위트
#       CORE="src/ vendor/"                 # 코어 경로 필터(공백 구분 접두/글롭) — stderr로 T3 승격 안내
#       MAP="src/* -> tests/test_foo.sh, tests/test_bar.sh"   # 파일→스위트 추가(반복 가능)
#   - exit 1은 쉘/환경 오류(비 git repo)에만 사용. 미분류가 있어도 exit 0.
set -uo pipefail

MODE="bare"; BASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "error: 알 수 없는 인자: $1" >&2; exit 1 ;;
  esac
done
case "$MODE" in bare|json) ;; *) echo "error: --mode 는 bare|json 만 허용: $MODE" >&2; exit 1 ;; esac

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "error: git 저장소가 아닙니다 — git repo 루트에서 실행하세요 (scripts/testmap.sh)" >&2
  exit 1
fi

# --- 매핑 표(레포 내장) ---
# 출력: 스위트 목록(공백 구분). "__NO_SUITE__"는 표면 변경(스위트 없음, 미분류 기록만).
map_builtin() {
  case "$1" in
    bin/herdr-team)
      printf '%s' "tests/test_agent_session.sh tests/test_pane_ready.sh tests/test_preset.sh tests/test_templates_only.sh tests/test_permissions_seed.sh tests/test_permissions_merge.sh tests/test_pkm_preset.sh" ;;
    bin/*|lib/*|src/*|schemas/*) printf '%s' "tests/test_preset.sh" ;;
    scripts/testmap.sh) printf '%s' "tests/test_testmap.sh" ;;
    scripts/build-zip.sh) printf '%s' "tests/test_install.sh" ;;
    scripts/*) printf '%s' "tests/test_preset.sh" ;;
    templates/*) printf '%s' "tests/test_preset.sh tests/test_pkm_preset.sh tests/test_template_sync.sh tests/test_permissions_seed.sh" ;;
    agents/*) printf '%s' "tests/test_template_sync.sh tests/test_preset.sh" ;;
    AGENTS.md) printf '%s' "tests/test_template_sync.sh tests/test_preset.sh" ;;
    README.md|README.ko.md) printf '%s' "tests/test_preset.sh" ;;
    .github/workflows/*) printf '%s' "tests/test_preset.sh tests/test_install.sh" ;;
    tests/*) printf '%s' "$1" ;;
    install.sh|windows/*|start-team.bat|hts.bat|htw.bat) printf '%s' "tests/test_install.sh tests/test_windows_launcher.sh" ;;
    docs/*) printf '%s' "__NO_SUITE__" ;;
    *) printf '' ;;
  esac
}

# --- 설정 파일 override (.testmap.conf) ---
FALLBACK="tests/test_preset.sh"
CORE_EXTRA=""
MAP_EXTRA=()
CONF="$ROOT/.testmap.conf"
if [[ -f "$CONF" ]]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"
    case "$key" in
      FALLBACK) [[ -n "$val" ]] && FALLBACK="$val" ;;
      CORE) CORE_EXTRA="$val" ;;
      MAP) MAP_EXTRA+=("$val") ;;
    esac
  done < "$CONF"
fi

# 코어 경로 필터(내장 + 설정): 매칭 시 stderr로 T3 승격 안내
is_core() {
  local p="$1" pat
  for pat in bin/ lib/ src/ schemas/ scripts/ bin/herdr-team $CORE_EXTRA; do
    [[ -n "$pat" ]] || continue
    case "$p" in $pat|$pat*) return 0 ;; esac
  done
  return 1
}

# 설정 MAP 조회: "pattern -> s1, s2" (콤마/공백 구분 다중 스위트 정규화, 마지막 매칭 우선)
map_conf() {
  local p="$1" spec pat out=""
  for spec in ${MAP_EXTRA+"${MAP_EXTRA[@]}"}; do
    pat="${spec%%->*}"; pat="$(printf '%s' "$pat" | tr -d ' ')"
    [[ -n "$pat" ]] || continue
    case "$p" in
      $pat) out="$(printf '%s' "${spec#*->}" | tr -d ' ' | tr ',' ' ')" ;;
    esac
  done
  printf '%s' "$out"
}

# --- 변경 파일 수집 ---
if [[ -n "$BASE" ]]; then
  FILES="$(git -C "$ROOT" diff --name-only "$BASE" HEAD 2>/dev/null || true)"
else
  FILES="$( { git -C "$ROOT" diff --name-only HEAD 2>/dev/null; git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null; } )"
fi
FILES="$(printf '%s\n' "$FILES" | sed '/^$/d' | sort -u)"

SUITES=""
UNCLASS=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  m="$(map_builtin "$p")"
  c="$(map_conf "$p")"
  if [[ -n "$c" ]]; then
    if [[ "$m" == "__NO_SUITE__" ]]; then m="$c"; else m="$m $c"; fi
  fi
  if is_core "$p"; then
    printf '# core-change: %s → push/CI 노드에서 T3 승격\n' "$p" >&2
  fi
  case "$m" in
    "")            UNCLASS="$UNCLASS$p"$'\n'; SUITES="$SUITES$FALLBACK"$'\n' ;;
    "__NO_SUITE__") UNCLASS="$UNCLASS$p"$'\n' ;;
    *)             for s in $m; do SUITES="$SUITES$s"$'\n'; done ;;
  esac
done <<< "$FILES"

SUITES="$(printf '%s' "$SUITES" | sed '/^$/d' | sort -u)"
UNCLASS="$(printf '%s' "$UNCLASS" | sed '/^$/d' | sort -u)"

if [[ "$MODE" == "json" ]]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n -c --arg s "$SUITES" --arg u "$UNCLASS" \
      '{suites: ($s | split("\n") | map(select(length>0))), unclassified: ($u | split("\n") | map(select(length>0)))}'
  else
    to_json_arr() { printf '%s' "$1" | sed '/^$/d' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/"/' | paste -sd, -; }
    printf '{"suites":[%s],"unclassified":[%s]}\n' "$(to_json_arr "$SUITES")" "$(to_json_arr "$UNCLASS")"
  fi
else
  [[ -n "$SUITES" ]] && printf '%s\n' "$SUITES"
fi
exit 0
