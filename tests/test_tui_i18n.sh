#!/usr/bin/env bash
# tests/test_tui_i18n.sh — ht 실행화면 i18n + TUI 시각 개선 검증
# 명세: docs/specs/ht-tui-i18n-and-polish-spec.md (§7 tc-1..tc-7)
# 실행: bash tests/test_tui_i18n.sh  (repo root에서)
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
assert_equal() { # $1=actual $2=expected $3=label
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (outputs differ)"; fi
}
assert_exit() { # $1=actual $2=expected $3=label
  if [[ "$1" -eq "$2" ]]; then ok "$3"; else bad "$3 (exit=$1, want=$2)"; fi
}
has_byte() { # $1=text $2=hex byte (1b/0d) — od 사용 (macOS/GNU 공통, pipefail 안전)
  local hex
  hex="$(printf '%s' "$1" | od -An -tx1 | tr -s ' ' '\n')"
  [[ $'\n'"$hex"$'\n' == *$'\n'"$2"$'\n'* ]]
}
assert_no_esc() { # $1=output $2=label — pty 환경(CR은 pty가 붙임)에서 ESC만 검사
  if has_byte "$1" 1b; then bad "$2 (ESC 0x1b found)"; else ok "$2"; fi
}
assert_plain_bytes() { # $1=output $2=label — plain 모드: ESC(0x1b)·CR(0x0d) 부재
  if has_byte "$1" 1b; then bad "$2 (ESC 0x1b found)";
  elif has_byte "$1" 0d; then bad "$2 (CR 0x0d found)";
  else ok "$2"; fi
}

[[ -x "$BIN" ]] || { printf 'FAIL: %s not executable\n' "$BIN"; exit 1; }

echo "== tc-3) 논TTY/파이프 회귀: ESC·CR 부재 + 계약 토큰 유지 =="
TUI_PIPE="$(printf '1\n1\n' | timeout 20 "$BIN" test --dry-run --no-template 2>&1)"; PIPE_RC=$?
assert_exit "$PIPE_RC" 0 "tc3_파이프_dryrun_exit0"
assert_plain_bytes "$TUI_PIPE" "tc3_파이프_escape_CR_부재"
assert_contains "$TUI_PIPE" "Select agent kind" "tc3_계약토큰_Select_agent_kind"
assert_contains "$TUI_PIPE" "Select AI team preset" "tc3_계약토큰_Select_AI_team_preset"
assert_contains "$TUI_PIPE" "preset=dev" "tc3_계약토큰_preset=dev"

CI_PIPE="$(CI=1 printf '1\n1\n' | CI=1 timeout 20 "$BIN" test --dry-run --no-template 2>&1)"
assert_plain_bytes "$CI_PIPE" "tc3_CI_escape_CR_부재"

KO_PIPE="$(printf '1\n1\n' | HERDR_TEAM_LANG=ko timeout 20 "$BIN" test --dry-run --no-template 2>&1)"
assert_plain_bytes "$KO_PIPE" "tc3_ko_escape_CR_부재"
assert_contains "$KO_PIPE" "AI 팀 프리셋을 선택하세요" "tc3_ko_프리셋_메뉴_제목"

echo "== tc-1) 카탈로그 패리티 (MSG_KEYS ↔ _msg_en/_msg_ko) =="
MSG_KEYS_SRC="$(grep -m1 '^MSG_KEYS=' "$BIN" || true)"
if [[ -z "$MSG_KEYS_SRC" ]]; then
  bad "tc1_MSG_KEYS_정의"
else
  ok "tc1_MSG_KEYS_정의"
  eval "$MSG_KEYS_SRC"
  CAT_SRC="$(mktemp)"
  {
    sed -n '/^_msg_en() {/,/^}/p' "$BIN"
    sed -n '/^_msg_ko() {/,/^}/p' "$BIN"
  } > "$CAT_SRC"
  if [[ -s "$CAT_SRC" ]]; then ok "tc1_카탈로그_추출"; else bad "tc1_카탈로그_추출"; fi
  for k in $MSG_KEYS; do
    EN_K="$(bash -c 'source "$1"; _msg_en "$2" A B C D' _ "$CAT_SRC" "$k" 2>/dev/null)"
    KO_K="$(bash -c 'source "$1"; _msg_ko "$2" A B C D' _ "$CAT_SRC" "$k" 2>/dev/null)"
    if [[ -n "$EN_K" ]]; then ok "tc1_en_$k"; else bad "tc1_en_$k (empty)"; fi
    if [[ -n "$KO_K" ]]; then ok "tc1_ko_$k"; else bad "tc1_ko_$k (empty)"; fi
    case "$EN_K$KO_K" in
      *%s*|*%d*) bad "tc1_서식_미치환_$k ($EN_K|$KO_K)" ;;
      *) ok "tc1_서식_해소_$k" ;;
    esac
  done
  rm -f "$CAT_SRC"
fi

echo "== tc-2) 로케일 결정 규칙 =="
LOC_SRC="$(mktemp)"
sed -n '/^ht_detect_locale() {/,/^}/p' "$BIN" > "$LOC_SRC"
if [[ -s "$LOC_SRC" ]]; then ok "tc2_ht_detect_locale_추출"; else bad "tc2_ht_detect_locale_추출"; fi
loc_of() { # $@=NAME=VALUE (지정 안 한 변수는 unset)
  ( unset HERDR_TEAM_LANG LC_ALL LANG
    local a; for a in "$@"; do export "$a"; done
    . "$LOC_SRC"; ht_detect_locale ) 2>/dev/null
}
assert_equal "$(loc_of)"                                   "en" "tc2_무설정_en"
assert_equal "$(loc_of HERDR_TEAM_LANG=ko)"                "ko" "tc2_HERDR_TEAM_LANG_ko"
assert_equal "$(loc_of LANG=ko_KR.UTF-8)"                  "ko" "tc2_LANG_ko"
assert_equal "$(loc_of LC_ALL=ko_KR.UTF-8 LANG=en_US.UTF-8)" "ko" "tc2_LC_ALL_ko_우선"
assert_equal "$(loc_of HERDR_TEAM_LANG=ko LANG=en_US.UTF-8)" "ko" "tc2_HERDR_TEAM_LANG_우선"
assert_equal "$(loc_of HERDR_TEAM_LANG=fr)"                "en" "tc2_미지원_값_en폴백"
assert_equal "$(loc_of LANG=en_US.UTF-8)"                  "en" "tc2_LANG_en"

echo "== tc-2b) 미지원 HERDR_TEAM_LANG → en 폴백 + WARN 1회 (e2e) =="
FR_OUT="$(HERDR_TEAM_LANG=fr timeout 20 "$BIN" --version 2>&1)"; FR_RC=$?
assert_exit "$FR_RC" 0 "tc2b_미지원로케일_exit0"
assert_contains "$FR_OUT" "WARN" "tc2b_미지원로케일_WARN"
assert_equal "$(printf '%s\n' "$FR_OUT" | grep -c 'WARN')" "1" "tc2b_WARN_1회"
assert_contains "$FR_OUT" "herdr-team v" "tc2b_version_정상"

echo "== tc-2c) preset/kind TUI·에러 i18n (§5.C/§5.D) =="
EN_TUI="$(printf '2\n1\n' | HERDR_TEAM_LANG=en timeout 20 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$EN_TUI" "Select AI team preset (1-6 or name, default: dev):" "tc2c_en_프리셋_제목"
assert_contains "$EN_TUI" "Select [1-6/dev/research/biz/mkt/creator/pkm] (default: dev, 10s):" "tc2c_en_프리셋_프롬프트_계약"
assert_contains "$EN_TUI" "Select agent kind (1-4 or name, default: opencode):" "tc2c_en_kind_제목_계약"
assert_contains "$EN_TUI" "preset=research" "tc2c_en_선택_동작_불변"
KO_TUI="$(printf '2\n1\n' | HERDR_TEAM_LANG=ko timeout 20 "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$KO_TUI" "AI 팀 프리셋을 선택하세요 (1-6 또는 이름, 기본: dev):" "tc2c_ko_프리셋_제목"
assert_contains "$KO_TUI" "Select [1-6/dev/research/biz/mkt/creator/pkm] (default: dev, 10s):" "tc2c_ko_프리셋_프롬프트_en고정"
assert_contains "$KO_TUI" "Select agent kind (1-4 or name, default: opencode):" "tc2c_ko_kind_제목_en고정_계약"
assert_contains "$KO_TUI" "preset=research" "tc2c_ko_선택_동작_불변"

EN_DEP="$(HERDR_TEAM_LANG=en "$BIN" test --preset app --dry-run --no-template --no-interactive 2>&1)"
assert_contains "$EN_DEP" "WARN: preset 'app' is deprecated; use 'dev' instead. (app merged into dev)" "tc2c_en_deprecated_문구"
assert_contains "$EN_DEP" "deprecated" "tc2c_en_deprecated_토큰"
KO_DEP="$(HERDR_TEAM_LANG=ko "$BIN" test --preset app --dry-run --no-template --no-interactive 2>&1)"
assert_contains "$KO_DEP" "경고: preset 'app'는 deprecated입니다." "tc2c_ko_deprecated_문구"

EN_BAD="$(HERDR_TEAM_LANG=en "$BIN" test --preset bogus --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$EN_BAD" "error: unknown preset: bogus" "tc2c_en_미지원_preset_에러"
assert_contains "$EN_BAD" "--list-presets" "tc2c_en_미지원_preset_목록안내"
KO_BAD="$(HERDR_TEAM_LANG=ko "$BIN" test --preset bogus --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$KO_BAD" "error: 알 수 없는 preset: bogus" "tc2c_ko_미지원_preset_에러"
for p in dev research biz mkt creator; do
  assert_contains "$EN_BAD" "$p" "tc2c_en_미지원_preset_가능목록($p)"
done
EN_KBAD="$(HERDR_TEAM_LANG=en "$BIN" test --kind invalid_kind --dry-run --no-template --no-interactive 2>&1 || true)"
assert_contains "$EN_KBAD" "error: unknown agent kind: invalid_kind" "tc2c_en_미지원_kind_에러"
assert_contains "$EN_KBAD" "supported: opencode" "tc2c_en_미지원_kind_지원목록"

SIM="$(mktemp -d)"; EMPTY_TPL="$(mktemp -d)"
mkdir -p "$SIM/bin"; cp "$BIN" "$SIM/bin/herdr-team"; chmod +x "$SIM/bin/herdr-team"
EN_CONF="$(HERDR_TEAM_LANG=en HERDR_TEAM_TEMPLATE_DIR="$EMPTY_TPL" "$SIM/bin/herdr-team" test --dry-run --no-interactive 2>&1 || true)"
assert_contains "$EN_CONF" "preset.conf for 'dev' not found" "tc2c_en_preset_conf_미발견"
assert_contains "$EN_CONF" "templates/<preset>/preset.conf is required" "tc2c_en_preset_conf_경로안내"
KO_CONF="$(HERDR_TEAM_LANG=ko HERDR_TEAM_TEMPLATE_DIR="$EMPTY_TPL" "$SIM/bin/herdr-team" test --dry-run --no-interactive 2>&1 || true)"
assert_contains "$KO_CONF" "preset.conf를 찾을 수 없습니다" "tc2c_ko_preset_conf_미발견"
rm -rf "$EMPTY_TPL" "$SIM"

echo "== tc-2d) 인자 파싱·precheck i18n (§5.A/§5.B) =="
EN_PARSE="$(HERDR_TEAM_LANG=en "$BIN" --kind 2>&1 || true)"
assert_contains "$EN_PARSE" "error: --kind requires a value" "tc2d_en_kind_값누락"
KO_PARSE="$(HERDR_TEAM_LANG=ko "$BIN" --kind 2>&1 || true)"
assert_contains "$KO_PARSE" "error: --kind에 값이 필요합니다" "tc2d_ko_kind_값누락"
MISS_RC="$(HERDR_TEAM_LANG=en "$BIN" --preset 2>/dev/null; echo $?)"
assert_exit "$MISS_RC" 2 "tc2d_값누락_exit2"
EN_UNK="$(HERDR_TEAM_LANG=en "$BIN" --bogus-option 2>&1 || true)"
assert_contains "$EN_UNK" "error: unknown option: --bogus-option (--help)" "tc2d_en_미지원옵션"
KO_UNK="$(HERDR_TEAM_LANG=ko "$BIN" --bogus-option 2>&1 || true)"
assert_contains "$KO_UNK" "error: 알 수 없는 옵션: --bogus-option" "tc2d_ko_미지원옵션"
EN_LAYOUT="$(HERDR_TEAM_LANG=en "$BIN" test --layout bogus_layout --no-interactive 2>&1 || true)"
assert_contains "$EN_LAYOUT" "error: unknown layout: bogus_layout" "tc2d_en_layout"
EN_MULTI="$(HERDR_TEAM_LANG=en "$BIN" aa bb 2>&1 || true)"
assert_contains "$EN_MULTI" "error: prefix must be given once: bb" "tc2d_en_prefix_중복"

echo "== tc-2e) precheck 로케일별 1세트 (§5.B) =="
NO_HERDR="$(mktemp -d)"
for d in /usr/local/bin /usr/bin /bin; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*; do
    b="${f##*/}"; [[ "$b" == "herdr" ]] && continue
    [[ -e "$NO_HERDR/$b" ]] || ln -s "$f" "$NO_HERDR/$b" 2>/dev/null || true
  done
done
EN_PRE="$(HERDR_TEAM_LANG=en PATH="$NO_HERDR" timeout 20 "$BIN" --precheck 2>&1)"; EN_PRE_RC=$?
assert_exit "$EN_PRE_RC" 127 "tc2e_en_precheck_exit127"
assert_contains "$EN_PRE" "ERROR herdr CLI not found" "tc2e_en_ERROR_문구"
assert_contains "$EN_PRE" "https://herdr.dev/install.sh" "tc2e_en_설치URL"
assert_contains "$EN_PRE" "https://herdr.dev/install.ps1" "tc2e_en_윈도우URL"
assert_contains "$EN_PRE" "HERDR_TEAM_SKIP_CHECK=1" "tc2e_en_우회플래그"
assert_not_contains "$EN_PRE" "찾을 수 없습니다" "tc2e_en_한국어_미출력"
KO_PRE="$(HERDR_TEAM_LANG=ko PATH="$NO_HERDR" timeout 20 "$BIN" --precheck 2>&1)"; KO_PRE_RC=$?
assert_exit "$KO_PRE_RC" 127 "tc2e_ko_precheck_exit127"
assert_contains "$KO_PRE" "ERROR herdr CLI 를 찾을 수 없습니다." "tc2e_ko_ERROR_문구"
assert_contains "$KO_PRE" "https://herdr.dev/install.sh" "tc2e_ko_설치URL"
assert_not_contains "$KO_PRE" "Install:" "tc2e_ko_en라벨_미출력"
SKIP_OUT="$(HERDR_TEAM_LANG=en HERDR_TEAM_SKIP_CHECK=1 PATH="$NO_HERDR" timeout 20 "$BIN" --precheck 2>&1)"; SKIP_RC=$?
assert_exit "$SKIP_RC" 0 "tc2e_skip_exit0"
assert_contains "$SKIP_OUT" "WARN: herdr CLI not found, continuing anyway" "tc2e_skip_WARN"
rm -rf "$NO_HERDR"

echo "== tc-2f) §5.E 키화 후에도 계약 문구 유지 (en 기본) =="
GD="$(mktemp -d)"
printf 'blocker\n' > "$GD/agents"
GD_OUT="$(HERDR_TEAM_LANG=en "$BIN" iso --cwd "$GD" --template-dir "$REPO/templates" --no-interactive --templates-only 2>&1 || true)"
assert_contains "$GD_OUT" "$GD/agents 가 디렉터리가 아닙니다" "tc2f_guard_not_a_dir_계약"
rm -rf "$GD"
GD2="$(mktemp -d)"
cat > "$GD2/AGENTS.md" <<'EOF'
<!-- herdr-team:managed BEGIN (preset=dev) -->
A
<!-- herdr-team:managed END -->
<!-- herdr-team:managed BEGIN (preset=mkt) -->
B
<!-- herdr-team:managed END -->
EOF
GD2_OUT="$(HERDR_TEAM_LANG=en "$BIN" iso --cwd "$GD2" --template-dir "$REPO/templates" --no-interactive --templates-only 2>&1 || true)"
assert_contains "$GD2_OUT" "마커" "tc2f_guard_marker_계약"
rm -rf "$GD2"
GD3="$(mktemp -d)"; git -C "$GD3" init -q; mkdir "$GD3/.gitignore"
GD3_OUT="$(HERDR_TEAM_LANG=en "$BIN" iso --cwd "$GD3" --template-dir "$REPO/templates" --no-interactive --templates-only 2>&1 || true)"
assert_contains "$GD3_OUT" "일반 파일이 아닙니다" "tc2f_gitignore_계약"
rm -rf "$GD3"

echo "== Q2) usage 말미 한국어 힌트 1행 =="
HELP_TXT="$("$BIN" --help 2>&1)"
assert_contains "$HELP_TXT" "HERDR_TEAM_LANG=ko" "q2_help_한국어_힌트"
assert_contains "$HELP_TXT" "README.ko.md" "q2_help_한국어_가이드_링크"
assert_contains "$HELP_TXT" "Usage:" "q2_help_영문_유지"

echo "== tc-4) NO_COLOR/TERM=dumb/--no-color (TTY 시뮬레이션: script) =="
assert_contains "$("$BIN" --help 2>&1)" "--no-color" "tc4_help_no_color_문서화"
if command -v script >/dev/null 2>&1; then
  tty_run() { # $@=env prefix assignments / command extras
    env -u CI -u GITHUB_ACTIONS -u NO_COLOR "$@" script -qec "$BIN test --preset dev --dry-run --no-template --no-interactive" /dev/null 2>&1
  }
  TTY_NOCOLOR="$(tty_run NO_COLOR=1)"
  assert_no_esc "$TTY_NOCOLOR" "tc4_TTY_NO_COLOR_escape_부재"
  TTY_DUMB="$(tty_run TERM=dumb)"
  assert_no_esc "$TTY_DUMB" "tc4_TTY_TERM_dumb_escape_부재"
  TTY_FLAG="$(env -u CI -u GITHUB_ACTIONS -u NO_COLOR script -qec "$BIN test --preset dev --dry-run --no-template --no-interactive --no-color" /dev/null 2>&1)"
  assert_no_esc "$TTY_FLAG" "tc4_TTY_no_color_플래그_escape_부재"
  TTY_CI="$(env -u NO_COLOR CI=1 script -qec "$BIN test --preset dev --dry-run --no-template --no-interactive" /dev/null 2>&1)"
  assert_no_esc "$TTY_CI" "tc4_TTY_CI_escape_부재"
else
  echo "SKIP: script 명령 없음 → TTY 시뮬레이션 생략"
fi

echo "== tc-6) 결정성: 동일 입력 2회 실행 출력 동일 =="
DET1="$(printf '1\n2\n' | "$BIN" test --dry-run --no-template 2>&1)"
DET2="$(printf '1\n2\n' | "$BIN" test --dry-run --no-template 2>&1)"
assert_equal "$DET1" "$DET2" "tc6_동일입력_출력동일"
assert_plain_bytes "$DET1" "tc6_plain_escape_CR_부재"
assert_contains "$DET1" "preset=dev" "tc6_plain_계약_preset"
assert_contains "$DET1" "kind=claude" "tc6_plain_계약_kind"

echo "== tc-5) 카운트다운 라이프사이클 (지연 입력/EOF/고아 프로세스) =="
ps_count() { # $1=pattern → 현재 매칭 프로세스 수 (자기 자신 제외)
  ps -eo args= 2>/dev/null | grep -F -- "$1" | grep -v -F 'grep -F' | wc -l | tr -d ' '
}
T0=$SECONDS
DELAYED_OUT="$(( sleep 2; printf '1\n1\n' ) | timeout 20 "$BIN" test --dry-run --no-template 2>&1)"; DELAYED_RC=$?
ELAPSED=$((SECONDS-T0))
assert_exit "$DELAYED_RC" 0 "tc5_지연입력_exit0"
assert_contains "$DELAYED_OUT" "preset=dev" "tc5_지연입력_정상선택"
if [[ "$ELAPSED" -lt 8 ]]; then ok "tc5_지연입력_8초미만(${ELAPSED}s)"; else bad "tc5_지연입력_8초미만(${ELAPSED}s)"; fi
assert_equal "$(ps_count "$BIN")" "0" "tc5_고아프로세스_0건"
T1=$SECONDS
EOF_OUT="$(printf '' | timeout 20 "$BIN" test --dry-run --no-template 2>&1)"; EOF_RC=$?
EOF_ELAPSED=$((SECONDS-T1))
assert_exit "$EOF_RC" 0 "tc5_EOF_exit0"
assert_contains "$EOF_OUT" "preset=dev" "tc5_EOF_dev기본"
if [[ "$EOF_ELAPSED" -lt 8 ]]; then ok "tc5_EOF_즉시복귀(${EOF_ELAPSED}s)"; else bad "tc5_EOF_즉시복귀(${EOF_ELAPSED}s)"; fi
assert_plain_bytes "$EOF_OUT" "tc5_EOF_escape_CR_부재"
assert_equal "$(ps_count "$BIN")" "0" "tc5_EOF_고아프로세스_0건"
if command -v script >/dev/null 2>&1; then
  TTY_CNT="$( ( sleep 2; printf '1\n1\n' ) | env -u CI -u NO_COLOR timeout 20 script -qec "$BIN test --dry-run --no-template" /dev/null 2>&1)"
  assert_contains "$TTY_CNT" "s remaining" "tc5_TTY_카운트다운_표시"
  assert_contains "$TTY_CNT" "preset=dev" "tc5_TTY_선택_정상"
  assert_equal "$(ps_count "$BIN")" "0" "tc5_TTY_고아프로세스_0건"
else
  echo "SKIP: script 없음 → TTY 카운트다운 검증 생략"
fi

echo "== tc-7) 배너·진행 단계·최종 요약 (plain 계약 불변) =="
BANNER_OUT="$(printf '1\n1\n' | "$BIN" test --dry-run --no-template 2>&1)"
assert_contains "$BANNER_OUT" "herdr-team v" "tc7_plain_배너"
assert_contains "$BANNER_OUT" "herdr-team v$(tr -d '[:space:]' < "$REPO/VERSION")" "tc7_plain_배너_버전"
ISO_OUT="$(printf '1\n1\n' | "$BIN" test --preset dev --dry-run --template-dir "$REPO/templates" 2>&1)"
assert_contains "$ISO_OUT" "(dry-run isolation)" "tc7_계약_dryrun_isolation"
assert_plain_bytes "$ISO_OUT" "tc7_계약_dryrun_escape_CR_부재"
assert_contains "$BANNER_OUT" "[1/4] templates" "tc7_진행단계_1"
assert_contains "$BANNER_OUT" "[2/4] opencode-agents" "tc7_진행단계_2"
assert_contains "$BANNER_OUT" "[3/4] permissions" "tc7_진행단계_3"
assert_contains "$BANNER_OUT" "[4/4] panes" "tc7_진행단계_4"
assert_contains "$BANNER_OUT" "[ok] templates" "tc7_plain_step_ok"
assert_contains "$BANNER_OUT" "preset=dev" "tc7_계약_preset"
assert_contains "$BANNER_OUT" "layout=2col" "tc7_계약_layout"

if command -v jq >/dev/null 2>&1; then
  S="$(mktemp -d)"; SC="$(mktemp -d)"
  cat > "$S/herdr" <<'STUBEOF'
#!/usr/bin/env bash
printf '{"result":{"pane":{"pane_id":"wT:p1"}}}\n'
STUBEOF
  chmod +x "$S/herdr"
  SUM_OUT="$(PATH="$S:$PATH" HERDR_TEAM_LANG=en "$BIN" sm --preset dev --cwd "$SC" --template-dir "$REPO/templates" --no-interactive --no-start 2>&1)"; SUM_RC=$?
  assert_exit "$SUM_RC" 0 "tc7_실행_exit0"
  assert_contains "$SUM_OUT" "[done] prefix=sm preset=dev kind=opencode layout=2col agents=4" "tc7_요약_plain"
  assert_contains "$SUM_OUT" "next: herdr agent list" "tc7_요약_다음단계힌트"
  assert_contains "$SUM_OUT" "[4/4] panes" "tc7_실행_진행단계"
  assert_contains "$SUM_OUT" "완료: prefix=sm preset=dev" "tc7_기존_완료로그_유지"
  assert_plain_bytes "$SUM_OUT" "tc7_실행_escape_CR_부재"
  rm -rf "$S" "$SC"
fi

if command -v script >/dev/null 2>&1; then
  TTY_BANNER="$(env -u CI -u GITHUB_ACTIONS -u NO_COLOR script -qec "$BIN test --dry-run --no-template --no-interactive" /dev/null 2>&1)"
  if has_byte "$TTY_BANNER" 1b; then ok "tc4_TTY_색상_활성"; else bad "tc4_TTY_색상_활성 (ESC 없음)"; fi
  assert_contains "$TTY_BANNER" "+-------------------+" "tc7_TTY_배너_박스"
  assert_contains "$TTY_BANNER" "herdr-team v" "tc7_TTY_배너_텍스트"
  assert_contains "$TTY_BANNER" "done" "tc7_TTY_step_done"
fi

echo "-----------------------------"
printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
