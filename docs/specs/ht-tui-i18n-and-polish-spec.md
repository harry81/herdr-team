# Spec: ht 실행화면 오픈소스화 대응 — TUI i18n 및 시각 개선

- 작성: ht-planner / 2026-10-29
- 대상: `bin/herdr-team` (단일 Bash 스크립트, 1577행) + 문서(README)
- 참조: `docs/specs/test-tiering-spec.md` (티어/T3 승격 규약)
- 회신 규약: 경로 + 1줄 요약

---

## 1. 문제 정의

herdr-team를 오픈소스로 공개하면 외국인 사용자가 `ht` 실행 직후 마주치는 대화형 콘솔 화면(preset/kind TUI 메뉴, 에러·경고 안내)이 한국어 위주이고 시각적으로 투박하다. 첫 30초 경험이 채택을 결정하는 오픈소스 특성상, 이 화면을 (a) 영문 기본 + 한국어 보조로 국제화하고 (b) 순수 Bash 범위에서 시각 완성도를 높인다.

목표:
1. i18n — 영문 기본 로케일, 한국어 보조. `HERDR_TEAM_LANG` + `LANG`/`LC_ALL` 자동 감지.
2. UI/UX — 배너·박스·색상·강조·카운트다운·진행 단계·성공/경고/에러 구분·최종 요약.
3. 모든 기존 CLI 계약(옵션, 타임아웃, EOF 폴백, 테스트 grep 문자열) 유지.

## 2. 현재 화면 인벤토리 (사실 — 행 번호 2026-10-29 기준)

| # | 지점 | 위치(행) | 현재 상태 |
|---|---|---|---|
| A | 인자 파싱 에러 | 241–250, 288, 441 | 한국어 (`알 수 없는 옵션`, `…에 값이 필요합니다`, `prefix는 1개만…`) |
| B | herdr precheck | 132–148 | 영/한 병기 heredoc + WARN 2행 병기 |
| C | usage / --help | 151–223 | 영문 (번역 대상 아님 — §3.5 결정) |
| D | preset TUI `choose_preset_tui` | 306–350 | 영문 헤더/프롬프트, 설명은 preset.conf `PRESET_DESC` (영문+괄호 한국어 병기), EOF/타임아웃→dev 폴백 |
| E | kind TUI `choose_kind_tui` | 357–388 | 영문 헤더/프롬프트, 아이템 한국어 혼재 (`(기본값)`), EOF/타임아웃→opencode 폴백 |
| F | preset 목록/미발견 | 121–127, 293–305 | 한국어 (`(없음)`, `(preset.conf 없음)`) |
| G | deprecated 경고 | 332, 399, 632, 1174 | 한국어 |
| H | 온보딩/파일시스템 에러 | 413–446, 533–581, 605, 736, 847 | 한국어 |
| I | 권한 시딩 경고 | 948–1006 | 한국어 |
| J | 세션/pane 에러 | 800–819, 1012–1050, 1439–1557 | 한국어 |
| K | 진행 로그 `log()` | 748 (`[herdr-team] …`) | 한국어 다수 |
| L | 시작/완료 | 1565 (`herdr-team v%s`), 1557 (`완료: prefix=…`) | 배너/요약 없음 |
| M | 타임아웃 | 324, 370 (`read -t 10`) | 남은 시간 표시 없음, read 동안 정적 |

### 테스트 하네스 grep 계약 (en 기본 로케일에서 절대 변경 금지)

출처 `tests/test_preset.sh`:
- `:130` `Select [1-6/dev/research/biz/mkt/creator/pkm]` — 프롬프트 형식 `Select [1-<N>/<joined>]` 유지
- `:181` `Select agent kind` — 고정
- `:76,115,186,376` `deprecated` — 경고 문구에 포함 유지
- `:91,295,342` `bogus` / `invalid_layout` / `preset=zzz` — 에러에 사용자 입력 원문 표시 유지
- `:125,127,130-131` `Software Development`, `Small Business` — PRESET_DESC 선두 영문 라벨 유지 (preset.conf는 번역 대상 아님)
- `:142-145` wrapper 출력 == 정본 출력 — 시각 요소는 **결정적**이어야 함 (환경에 따라 출력 공백 케이스 없음)
- 전반: dry-run 라인 포맷 `preset=`, `kind=`, `layout=`, `prefix=` 유지
- 파이프/논TTY 출력에 ANSI escape 코드와 `\r` 금지

기타 회귀 소지 테스트: `tests/test_agent_session.sh`, `tests/test_pane_ready.sh`, `tests/test_herdr_precheck.sh`(precheck 출력 grep), `tests/test_safe_onboarding.sh`(guard 에러 문구 grep) — 각 태스크 T2에서 testmap 스위트로 확인.

## 3. i18n 설계

### 3.1 로케일 결정 규칙

```
1) HERDR_TEAM_LANG   (en|ko 외의 값 → en 폴백 + WARN 1회)
2) LC_ALL            (ko* → ko, 그 외 → en)
3) LANG              (ko* → ko, 그 외 → en)
4) 미설정            → en
```

매칭은 `case`문 prefix만 사용 (`ko*` — `ko_KR.UTF-8` 등 변형 수용). Bash 3.2 안전. 시작 시 1회 결정하여 `MSG_LOCALE` 확정, 실행 중 변경 없음.

### 3.2 카탈로그 방식 비교 및 선택

| 항목 | A: 스크립트 내부 Bash 함수 카탈로그 | B: `templates/i18n/` 데이터 파일 |
|---|---|---|
| 형태 | `_msg_en`/`_msg_ko` case문 함수 쌍 | 로케일별 TSV, 기동 시 로딩 |
| 배포 무결성 | ✅ 단일 파일 — install.sh 심링크 / Releases zip / 리포 클론 모두 안전 | ⚠️ 부분 복사·별도 배포 시 카탈로그 유실 → 폴백 경로 추가 필요 |
| 경로 해석 | 불필요 | symlink 해석 3단계 폴백(version_file이 이미 겪는 macOS 문제) 재구현 |
| 실패 모드 | 없음 | 파일 누락/인코딩 깨짐 추가 |
| 번역 기여 편의 | 스크립트 편집 필요 | 파일 편집만 가능 ✅ |

**채택: A(스크립트 내부 함수 카탈로그).** 근거: 배포 형태가 3종이고, macOS에서의 경로 해석이 이미 알려진 실패 지점(version_file의 readlink→realpath→python3 폴백). 단일 파일 무결성·실패 모드 제거가 우선. 외부 기여 접근성은 §3.4 언어 추가 절차 문서화로 절충.

### 3.3 카탈로그 인터페이스 (예시 — ht-worker가 최종 구현)

```bash
# 인터페이스 예시 (스펙 — 구현 코드 아님)
MSG_LOCALE=""   # en | ko, 시작 시 1회 결정
msg() {         # msg KEY [ARGS...] — 개행 없이 출력
  local r=""
  r="$(_msg_en "$@")"
  [[ "$MSG_LOCALE" == "ko" ]] && r="$(_msg_ko "$@")"
  printf '%s' "$r"
}
_msg_en() { case "$1" in
  preset.menu.title) printf 'Select AI team preset (1-%s or name, default: %s):\n' "$2" "$3" ;;
esac }
_msg_ko() { case "$1" in
  preset.menu.title) printf 'AI 팀 프리셋을 선택하세요 (1-%s 또는 이름, 기본: %s):\n' "$2" "$3" ;;
esac }
```

규칙:
- 개행 포함 여부는 각 키의 서식에 고정하고 호출부는 `msg x.y arg…` 사용. 서식 인자 개수는 en/ko 동일(패리티 검사 대상).
- 치환은 전부 `printf` 서식 — Bash 3.2 전용 기능(연관배열, `printf %q`, `${var,,}`, `readarray`, `=~` 재사용 회피) 금지.
- 에러 접두어는 **모든 로케일에서 `error: ` 유지**, 경고는 en `WARN: ` / ko 현행 `[herdr-team] 경고: ` 유지(테스트 판별 용이).
- 키 네이밍: `<block>.<subject>[.qual]` (예: `parse.opt.missing.kind`).
- `MSG_KEYS` 변수에 키 목록을 두고 en/ko 매칭 반영 여부를 테스트로 검증(§7 tc-1).

### 3.4 언어 추가 절차 (README 문서화 대상)

1. 본 스펙 §5 카탈로그 표의 영문 원문을 기준 문장으로 사용.
2. `bin/herdr-team`에 `_msg_<lang>()`을 추가 — `_msg_en`과 동일 키 집합·동일 서식 인자 개수.
3. §3.1 로케일 결정 룰에 언어 prefix 추가.
4. `tests/test_tui_i18n.sh` 패리티 테스트에 신규 로케일 포함 → PASS.
5. README 언어 절 링크 추가 (README.<lang>.md).

### 3.5 usage() / preset.conf 결정

- `usage()`는 이미 영문 정적 텍스트 → **번역하지 않고 영문 유지**. 한국어 사용자는 기존 `Korean guide: README.ko.md` 자기참조. 맨 아래 한국어 1행 힌트 추가만 허용.
- `preset.conf`의 `PRESET_DESC`는 설정 데이터이며 테스트가 영문 라벨을 grep → **번역 대상 아님**(현행 영문+괄호 한국어 병기 유지).
- `SUPPORTED_KINDS`, preset/kind 이름·별칭: 식별자 — 번역 금지.

## 4. UI/UX 설계

### 4.1 스타일 세션 (색상 — 시작 시 1회 결정)

```text
HT_STYLE_COLOR = 1 iff  다음 모두 만족:
  - stderr 가 TTY ([[ -t 2 ]])          # TUI는 stderr 렌더이므로 기준도 stderr
  - TERM 이 dumb 이 아니고, 정상적으로 정의되어 있을 것 (`TERM != dumb`)
  - NO_COLOR 미설정 (no-color.org 규약)
  - --no-color 미지정
  - CI / GITHUB_ACTIONS 미설정          # 하드제약 3 보강
```

- 색상 기법: `tput setaf <n>` 시도, 실패 시 `printf '\033[..m'` 직접. **plain 모드에서는 어떤 escape·커서제어도 출력 금지.**
- 그래픽: 기본 **ASCII** (`+--`, `|`, `[ ]`). 유니코드 박스글립은 "TTY + UTF-8 로케일 + `HERDR_TEAM_ASCII=1` 미설정"에서만 허용 — 기본 ASCII 확정(CJK 폭 계산·다양한 터미널 커버).

### 4.2 화면 요소 매핑

| 요소 | TTY 모드 | plain 모드 |
|---|---|---|
| 시작 배너 (L1565 교체) | 박스 `+-- herdr-team v1.x.x --+` + 색상 | 기존 1행 `herdr-team v%s` 유지 |
| 구분선/박스 (`ht_rule`, `ht_box`) | dim 색상 라인 | ASCII `-----` |
| 번호 선택지 강조 | 번호 bold, 설명 dim | 기존 텍스트 동일 |
| 현재 선택값 표시 | 프롬프트 이하 `[default: dev]` dim 강조 | 텍스트에 이미 포함 — 추가 출력 없음 |
| 카운트다운 | §4.3 | 표시 없음(기존 `(default: dev, 10s)` 텍스트만) |
| 초기화 진행 단계 | `[1/4] templates` 갱신(`\r`) | `[1/4] templates ...` 증분 한 줄(log 유지) |
| 성공/경고/에러 | `ok:` 초록/`warn:` 노랑/`error:` 빨강 + 기호 | `[ok]`/`[warn]`/`error:` — 접두어 계약 유지 |
| 최종 요약 | §4.5 | §4.5 plain 행 |

접근성(하드제약 7): 색상만으로 의미 전달 금지 — 모든 상태는 텍스트 접두어를 동반. ASCII 폴백은 기본값이고 `HERDR_TEAM_ASCII=1`은 유니코드를 강제 끄는 추가 안전 밸브.

### 4.3 카운트다운 표시 (하드제약 6)

현행 `read -r -t 10 ans`의 입력 대기 동안 남은 시간 표시.

1. **표시 조건**: §4.1 TTY 모드에서만. plain이면 현행과 100% 동일(테스트 하네스 회귀 없음).
2. **구조**: 백그라운드 서브셸이 표시를 갱신하고 포그라운드에서 기존 `read -r -t 10`을 그대로 유지 — **입력 블로킹 동작 변경 없음**.

```text
# 인터페이스 예시 (스펙)
countdown_start: ( 갱신 루프: printf '\r… %ss' >&2 ; sleep 1 ; i-- ) & → HT_CNT_PID
countdown_stop:  kill $HT_CNT_PID || true ; wait $HT_CNT_PID 또는 kill -9 후 wait ; 클리어행 1회
```

3. **시그널 정리 (명문화)**:
   - `countdown_start` 직전에 EXIT/INT/TERM trap 설정. trap 내에서 `exit` 금지, `$?` 변조 금지(스크립트 종료코드 계약 보존) — 형태: `trap 'countdown_stop' EXIT INT TERM` + `countdown_stop`이 내부적으로 전부 `|| true`.
   - `read` 복귀 즉시 `countdown_stop()`: `kill` → `wait`(좀비 재확보) → grace 후에도 미종료 시 `kill -9` → `wait` → 줄 정리.
   - `INT`(Ctrl+C): trap은 정리 후 기존 시그널 종료 흐름 유지 — 시그널 swallow 금지.
   - kill/read 경합: read 타임아웃과 서브셸 1초 틱이 동시에 도달해도 kill 이후 출력이 발생하지 않도록, 서브셸은 틱마다 자신이 아직 유효한지(부모의 계속 플래그/종료 검사) 확인 후 출력.
   - plain 모드에서는 `countdown_start` 자체를 호출하지 않음(프로세스 0개).

### 4.4 진행 단계 표시

`setup_templates` → `setup_opencode_agents` → `setup_permissions` → `setup_panes` 4단계. 각 단계 시작/종료에 `step_begin <name>` / `step_end` 1회:
- plain: `[1/4] templates` + 기존 상세 log 유지 (log 감추기 아님).
- TTY: 동일 텍스트 + 색상, 종료 시 `[1/4] templates done ✔`(plain에선 `[ok]`).
- dry-run 라인(`log "prefix=… (dry-run isolation)"` 등)은 그대로 유지 — 테스트 계약.

### 4.5 최종 요약 화면

성공 종료 직전(L1557 근처)에 **부가 블록 추가** (기존 `완료: prefix=… preset=…` log 라인은 유지 — 제거 아님):
- plain: `[done] prefix=… preset=… kind=… layout=… agents=<n>` + 다음 단계 힌트 1행 (`herdr agent list`).
- TTY: 박스 — prefix / preset / kind / layout / roles. 모두 ASCII 글립.
- 결정성: dry-run/real-run, `--no-*` 조합에 따라 포함 내용만 다르고 포맷은 고정 (wrapper 출력 동일성 테스트 보호).

### 4.6 신규 옵션

| 옵션 | 의미 |
|---|---|
| `--no-color` | 색상·커서제어 강제 off(plain). `NO_COLOR`, `TERM=dumb`와 동등. usage에 신규 추가 |

이 외 신규 옵션 없음. `--no-interactive`, 타임아웃 10s 기본값, EOF 기본값 폴백은 완전 불변(하드제약 5).

## 5. 문자열 카탈로그 표 (번역 대상 전체 목록)

> `en` = 영문 원문(기본 로케일 출력), `ko` = 한국어. 계약 문자열은 ✱ 표기.

### 5.A 인자 파싱 (L241–250, 288, 441)

| key | en | ko |
|---|---|---|
| `parse.opt.missing.kind` | `error: --kind requires a value` | `error: --kind에 값이 필요합니다` |
| `parse.opt.missing.layout` | `error: --layout requires a value (2col or right-stack)` | `error: --layout에 값이 필요합니다 (2col\|right-stack)` |
| `parse.opt.missing.cwd` | `error: --cwd requires a value` | `error: --cwd에 값이 필요합니다` |
| `parse.opt.missing.template_dir` | `error: --template-dir requires a value` | `error: --template-dir에 값이 필요합니다` |
| `parse.opt.missing.preset` | `error: --preset requires a value (list: --list-presets)` | `error: --preset에 값이 필요합니다 (목록: --list-presets)` |
| `parse.opt.unknown` | `error: unknown option: %s (--help)` | `error: 알 수 없는 옵션: %s (도움말: --help)` |
| `parse.prefix.multiple` | `error: prefix must be given once: %s` | `error: prefix는 1개만 지정 가능합니다: %s` |
| `parse.prefix.invalid` | `error: cannot determine a valid prefix` | `error: 유효한 prefix를 결정할 수 없습니다.` |
| `layout.unknown` | `error: unknown layout: %s (choose 2col or right-stack)` | `error: 알 수 없는 layout: %s (2col\|right-stack 중 선택)` |

### 5.B herdr precheck (`precheck_herdr`, L132–148)

| key | en | ko |
|---|---|---|
| `precheck.warn.skip` | `WARN: herdr CLI not found, continuing anyway (HERDR_TEAM_SKIP_CHECK=1)` | `WARN: herdr CLI 를 찾을 수 없지만 HERDR_TEAM_SKIP_CHECK=1 로 계속 진행합니다.` |
| `precheck.err.title` | `ERROR herdr CLI not found — herdr-team runs on top of herdr.` | `ERROR herdr CLI 를 찾을 수 없습니다.` |
| `precheck.install.cmd` | URL 라인 — 로케일 공통 (번역 없음) | 공통 |
| `precheck.verify` | `Verify: herdr --version` | `확인: herdr --version` |
| `precheck.bypass` | `Bypass: HERDR_TEAM_SKIP_CHECK=1` | `우회: HERDR_TEAM_SKIP_CHECK=1` |

정책: 현행 영/한 병기 heredoc → 로케일별 1세트만 출력 (정보 이중화 해소). `tests/test_herdr_precheck.sh`의 grep 토큰을 T2에서 확인 후 계약 유지.

### 5.C preset TUI (`choose_preset_tui`, L306–350)

| key | en | ko |
|---|---|---|
| `preset.menu.title` | `Select AI team preset (1-%s or name, default: %s):` | `AI 팀 프리셋을 선택하세요 (1-%s 또는 이름, 기본: %s):` |
| `preset.menu.item` | (현행 서식 동일 — 번역 없음) | 동일 |
| `preset.menu.prompt` ✱✱ | `Select [1-%s/%s] (default: %s, 10s):` — **en 고정(계약), 번역 금지** | 동일(en 고정) |
| `preset.warn.deprecated` (332, 399, 632, 1174) | `[herdr-team] WARN: preset '%s' is deprecated; use '%s' instead. (app merged into dev)` — `deprecated` 토큰 유지(계약) | 현행 문구 유지 |
| `preset.err.unknown.name` | `error: unknown preset choice: %s (available: %s)` | `error: 알 수 없는 preset 선택: %s (사용 가능: %s)` |
| `preset.err.unknown.number` | `error: unknown preset choice: %s (1-%s or name)` | `error: 알 수 없는 preset 선택: %s (1-%s 또는 이름)` |
| `preset.err.cli.unknown` | `error: unknown preset: %s (available: %s. list: --list-presets)` | `error: 알 수 없는 preset: %s (사용 가능: %s. 목록: --list-presets)` |
| `preset.err.conf.missing` | `error: preset.conf for '%s' not found. templates/<preset>/preset.conf is required (search: %s, %s).` | 현행 문구 |
| `preset.err.conf.missing.found` | `error: preset.conf for '%s' not found (discovered: %s; search: %s, %s).` | 현행 문구 |
| `preset.usage.none` (126) | `(none)` | `(없음)` |
| `preset.list.noconf` (302) | `(preset.conf missing)` | `(preset.conf 없음)` |

### 5.D kind TUI (`choose_kind_tui`, L357–388)

| key | en | ko |
|---|---|---|
| `kind.menu.title` ✱ | `Select agent kind (1-4 or name, default: opencode):` — **en 고정(계약)** | `에이전트 종류를 선택하세요 (1-4 또는 이름, 기본: opencode):` |
| `kind.menu.item1` | `  1) opencode - OpenCode Interpreter` | `  1) opencode - OpenCode Interpreter (기본값)` |
| `kind.menu.item2–4` | 제품명 라인 — 공통 | 공통 |
| `kind.menu.prompt` | 현행 영문 그대로 (계약 스타일) | 동일 |
| `kind.err.unknown` | `error: unknown agent kind choice: %s` | `error: 알 수 없는 agent kind 선택: %s` |
| `kind.err.unknown.cli` (424) | `error: unknown agent kind: %s (supported: opencode, claude, codex, agy, pi, gemini, cursor, ...)` | `error: 알 수 없는 agent kind: %s (지원 목록: opencode, claude, codex, agy, pi, gemini, cursor 등)` |

### 5.E 온보딩·파일시스템·pane·세션 에러 (446, 533–581, 605, 736, 800–819, 847, 1012–1050, 1439–1557)

| key | en (신규 영문) | ko (현행 = 카탈로그 이행) |
|---|---|---|
| `fs.err.symlink.resolve` (533) | `error: cannot resolve symlink target: %s` | `error: 심링크 대상 해석 실패: %s` |
| `fs.err.is_directory` (536) | `error: %s is a directory — cannot replace with a file` | 현행 |
| `fs.err.write_denied` (542) | `error: cannot write: %s (check directory write permission)` | 현행 |
| `fs.err.write_fail` / `replace_fail` (544/546) | `error: write failed: %s` / `error: replace failed: %s` | 현행 |
| `fs.err.backup_mkdir` / `backup_cp` (550/554) | `error: failed to create backup directory: %s` / `error: backup failed: %s` | 현행 |
| `guard.err.agentsmd_lower` (561–564) | `error: lowercase agents.md exists — root team doc is AGENTS.md (case conflict)` + 안내 2행 | 현행 |
| `guard.err.not_a_dir` (570) | `error: %s is not a directory — %s seeding fails. Clean up and re-run.` | 현행 |
| `guard.err.marker.multi` / `broken` (578/581) | `error: more than one managed-section marker pair in %s …` / `error: mismatched managed-section markers in %s (BEGIN/END) …` | 현행 |
| `gitignore.err.not_file` (605) | `error: %s is not a regular file — gitignore registration fails` | 현행 |
| `run.err.cmd_fail` (736) | `error: command failed: %s` | 현행 |
| `pane.err.ready_timeout` (800/814) | `error: pane %s ready wait exceeded (%ss)` | 현행 |
| `pane.err.foreground` (801/815) | `error: a foreground process (e.g. vim) holds the pane shell — close it and re-run` | 현행 |
| `bundle.err.missing` (847) | `error: bundle missing: %s (%s)` | 현행 |
| `roles.err.empty` (446) | `error: preset '%s' has empty ROLES (check %s/preset.conf)` | 현행 |
| `pane.err.no_base` (1439) | `error: cannot determine current pane id. Run inside a Herdr session` | 현행 |
| `pane.err.parse` (1457/1468/1484/1516) | `error: failed to parse pane_id from %s split output: %s` | 현행 |
| `agent.err.session_json` / `session_fail` / `session_parse` (1041/1045/1050) | `error: session request JSON failed (%s)` / `error: session creation failed (%s) — check opencode install/background service` / `error: session id parse failed (%s): %s` | 현행 |
| `agent.err.start_abort` (1540) | `error: %s start aborted (pane %s shell not ready)` | 현행 |
| `agent.log.exists` (1550) | `[herdr-team] %s already exists — start skipped` | 현행 |

비고: 본 표의 ko 컬럼이 현재 문장 전체이며, worker는 카탈로그 키로 함수화만 수행(문구 변경 없음). 열린 질문 Q1 참조 — 5.E는 "키화 우선, en 번역 문안은 worker 제안 → reviewer 승인" 2단계로 진행 가능.

### 5.F 번역 제외 (en 고정 목록)

- `usage()` 전체 (§3.5) — 단, 말미 한국어 1행 힌트 추가 허용
- `preset.conf` PRESET_DESC, SUPPORTED_KINDS, preset/kind 식별자, layout 이름
- URL 라인들 (install cmd), `herdr pane rename` 라벨(①PM 등 — pane UI는 herdr 소유)
- 내부 디버그 성격 log (`write-back:`, `activate:`, `import(legacy):`, prune/sync 상세 로그) — en 고정, 카탈로그 키화만 선택적으로(문구 불변)

## 6. 파일별 변경 계획

| 파일 | 변경 | 성격 |
|---|---|---|
| `bin/herdr-team` | 카탈로그(msg/`_msg_en`/`_msg_ko`+`MSG_KEYS`), 로케일 결정, 스타일 세션(`HT_STYLE_COLOR`), `ht_rule`/`ht_box`/`ok`/`warn`/`err` 시각 헬퍼, `countdown_start/stop`, `step_begin/end`, 요약 블록, 호출부 치환, `--no-color` 파싱, usage에 `--no-color` 문서 | **core** (test-tiering §c 매핑: `bin/herdr-team` → 코어 경로 필터) |
| `tests/test_tui_i18n.sh` | 신규 — i18n + TUI 시각 + TTY/논TTY + 카탈로그 패리티 | 신규 테스트 |
| `tests/test_preset.sh` | 변경 원칙: **수정하지 않는다**. 계약 문자열이 en에서 유지되므로 기존 assert 전부 통과해야 함. (ko 로케일에 대한 신규 assert는 test_tui_i18n.sh로 분리) | 불변 (T2로 검증) |
| `README.md` / `README.ko.md` | TUI 메뉴 출력 예시 갱신(L228 부근), `--no-color`, `HERDR_TEAM_LANG`, 언어 추가 절차(§3.4) 문서화 | docs (surface) |
| `AGENTS.md` 등 정본 | 변경 없음 | — |

## 7. 테스트 계획

### 신규 테스트: `tests/test_tui_i18n.sh`

섹션(각각 독립):
- (tc-1) 카탈로그 패리티: `MSG_KEYS`의 모든 키가 `_msg_en`/`_msg_ko` 양쪽에서 서식 실패 없이 resolve. 신규 로케일 추가 시 같은 체계.
- (tc-2) 로케일 결정: `HERDR_TEAM_LANG=ko`→ko 문구, `LANG=ko_KR.UTF-8`→ko, `LC_ALL=ko_KR.UTF-8`(LANG=en)→ko, `HERDR_TEAM_LANG=ko LANG=en`→ko(우선순위), `HERDR_TEAM_LANG=fr`→en+WARN, 무설정→en.
- (tc-3) 논TTY 회귀: 파이프 stdin/stdout/stderr로 `--dry-run` 실행 → 출력에 ESC(`\033`)·`\r` **부재**. `CI=1`에서도 동일. 기존 계약 토큰(`Select agent kind` 등) 존재.
- (tc-4) NO_COLOR/TERM=dumb: TTY 시뮬레이션(`script -qec` — 없으면 SKIP)에서도 escape 부재, `--no-color` 동등.
- (tc-5) 카운트다운 라이프사이클: 지연 입력(`( sleep 2; printf '1\n' ) |`) 실행 → 정상 select. 실행 후 고아/좀비 미잔존(ps로 countdown 서브셸 마커 검색 0건). EOF 즉시 복귀 시에도 프로세스 0건. 실측시간 10s 초과·8s 미만 경계 확인.
- (tc-6) 결정성: 동일 입력 2회 실행 출력 동일(§2 wrapper 동등성 계약).
- (tc-7) `--no-interactive`/타임아웃/EOF 폴백이 로케일 무관하게 동일 동작(ko 로케일 + 파이프 EOF → dev/opencode).

### 기존 tests 영향도

- `tests/test_preset.sh` — **수정 금지 목표**. 문자열 유지 + 결정성 유지로 통과 예상. 실패 시 원인은 카탈로그 계약 위배로 간주하고 worker 수정(테스트가 아니라 코드 수정).
- `tests/test_herdr_precheck.sh` — precheck 출력 토큰 grep. §5.B en 고정 유지로 통과 예상. T2에서 확인.
- `tests/test_safe_onboarding.sh` — guard 에러 문구 grep(agents.md 관련). T2에서 확인.
- `scripts/testmap.sh` — `bin/herdr-team` 변경이 매핑 스위트(`test_agent_session.sh`, `test_pane_ready.sh`, `test_preset.sh`)를 출력함 이미 확정(매핑 표 변경 불필요).


## 8. Task Breakdown (ht-worker TDD — 티어 규약은 test-tiering-spec §b–§d)

공통 규칙:
- blast radius → **blast radius: core** (`bin/herdr-team`는 test-tiering §c 코어 경로 필터 직항 — 근거: 단일 스크립트이며 모든 소비(consumer) 프로젝트가 참조하는 공유 정본 파일). 따라서 모든 태스크 `tier=T2`로 종료하고 push/CI 노드에서 T3 승격.
- T1 = `bash tests/test_tui_i18n.sh`(신규 파일, 태스크 0이 먼저 생성). T2 = `scripts/testmap.sh`가 출력한 스위트 전부 (예상: `bash tests/test_agent_session.sh && bash tests/test_pane_ready.sh && bash tests/test_preset.sh`).
- 각 태스크는 **커밋 단위 롤백 가능**(§9)이도록 독립 커밋.

| # | 태스크 | 완료 기준 (DoD) | 검증 명령 |
|---|---|---|---|
| 0 | `tests/test_tui_i18n.sh` 스켈레톤 (ok/bad assert + tc-3 논TTY 회귀 최소 1건 — **Red: 구현 전 실패 확인**) | tc-3가 실패 상태로 잡힘(Red) | T1 `bash tests/test_tui_i18n.sh` (의도된 Red) |
| 1 | 로케일 결정 + `msg`/`_msg_en` 골격 + `MSG_KEYS` (행동 중립: en 출력 = 현행 문자열 그대로) | tc-1, tc-2 Green; 기존 스위트 무영향 | T1 `bash tests/test_tui_i18n.sh`; T2 (§8 공통) |
| 2 | §5.C/D 이행: preset/kind TUI + 관련 에러 호출부 `msg` 치환 (en 출력 불변, ko 신규) | tc-2 ko 케이스 Green; test_preset 전부 통과 | T1 + `bash tests/test_preset.sh`; T2 |
| 3 | §5.A 인자 파싱 + §5.B precheck 이행 | 동일 + precheck 관련 토큰 계약 유지 | T1 + `bash tests/test_herdr_precheck.sh`; T2 |
| 4 | §5.E 에러/경고 키화 (문구 불변, **en 신규 문안은 ko 문장의 직역 제안**) | tc-1 패리티 갱신; guard/precheck/pane 토큰 계약 유지 | T1 + `bash tests/test_safe_onboarding.sh` + `bash tests/test_pane_ready.sh`; T2 |
| 5 | 스타일 세션 + `--no-color` + NO_COLOR/TERM=dumb/CI 판정 + `ht_rule`/`ht_box`/`ok`/`warn`/`err` 헬퍼 (plain 출력 바이트 동등) | tc-3, tc-4, tc-6 Green; dry-run 파이프 출력이 태스크 4 이전과 동일(golden 비교) | T1; T2 |
| 6 | 카운트다운 렌더러 + trap/시그널 정리 (§4.3 명세 전문 반영; plain 모드 프로세스 0개) | tc-5 Green; 논TTY에서 카운트다운 부재 | T1; T2 |
| 7 | 배너 교체(L1565) + 진행 단계(`[i/4]`) + 최종 요약 블록(§4.4/4.5) | tc-6 Green; dry-run 계약 라인(`preset=`/`kind=`/`layout=`) 불변 | T1 + `bash tests/test_preset.sh` + `bash tests/test_templates_only.sh`; T2 |
| 8 | 문서: README/README.ko TUI 예시 + `--no-color` + `HERDR_TEAM_LANG` + 언어 추가 절차(§3.4) | README 계약 토큰(§2, test_preset §13–14) 유지 | `bash tests/test_preset.sh` (docs는 unclassified — T2 사실상 스위트 0, 문서 검증 위 테스트로 커버) |

이행 순서 의존성: 0 → 1 → (2,3 병렬 가능) → 4 → 5 → 6 → 7 → 8.  5~7은 1~4와 독립(시각은 카탈로그와 분리된 헬퍼층).

## 9. 엣지 케이스·열린 질문

### 엣지 케이스 (구현 시 반드시 처리)

1. **리포 외 심링크 실행**(`~/bin/ht -> repo/bin/herdr-team`): 카탈로그는 파일 내부라 무영향. i18n 데이터 파일 방안(B)이 이 실패 지점으로 탈락했음을 유지.
2. **동시성**: 카운트다운 서브셸과 read 타임아웃 경합(§4.3-3).
3. **`set -euo pipefail`과 trap**: EXIT trap에서 실패 종료 원인을 삼키지 않도록 `|| true`만 사용. 카운트다운 kill 실패가 `set -e`로 전파 금지.
4. **`MSG_KEYS` 누락 키**: 패리티 테스트가 컴파일 타임에 잡음(런타임 KEY 누락 = en 원문 노출).
5. **PIPESTATUS**: 파이프 입력 테스트 환경에서 read가 SIGPIPE를 만들지 않도록 서브셸 write가 stderr 전용.
6. 로케일이 `ko`이면서 `HERDR_TEAM_LANG=undefined 값` → WARN 1회 + en (무반복).
7. UTF-8 로케일에서 한국어 폭 — plain에서는 문제 없음(텍스트만), 박스는 ASCII라 안전.
8. Bash 3.2: `read -t`는 macOS bash 3.2 지원(현행 사용 중). `${!arr[@]}`나 `&>()` 등 4.x 기능 신규 사용 금지.

### 열린 질문 (PM 확정 필요)

- **Q1 (5.E 번역 승인 절차)**: 5.E의 en 문안은 worker 직역 제안 → reviewer 승인 구조로 갈지, 이 명세에서 en을 확정할지. (요청: 2단계 — 스펙은 키와 ko 고정만 확정, en은 태스크 4에서 제안+승인.)
- **Q2 (usage 한국어 힌트)**: `--help` 말미 한국어 1행 추가할지. (요청: 추가 — 1행 변경이 사용자 이해에 최대 효율.)
- **Q3 (기타 프리셋)**: dev 외 preset(biz/mkt 등) 템플릿 안 문서(agents/<preset>/AGENTS.md 내부 한국어 안내)는 본 명세 제외 — 후속 명세 필요 여부.
- **Q4 (카운트다운 표시 시작 임계)**: 남은 시간을 처음부터 표시할지 3초 이하부터 표시할지. (요청: 처음부터 10→1 표시.)

## 10. 롤백

- **커밋 단위**: 태스크 0–8 각각 독립 커밋 → 개별 `git revert` 가능. 상태 파일·캐시를 새로 만들지 않으므로 코드 revert만으로 완전 복구.
- **런타임 우회 (revert 전 완화책)**: `HERDR_TEAM_LANG=en`(모든 문구가 카탈로그되지 않은 내부 log 포함 현행 유지) + `--no-color`/`NO_COLOR`(시각 요소 완전 off = 현행 plain 흐름과 동등).
- **계약 안전망**: §7 tc-3의 "논TTY ANSI 부재"·tc-6 "출력 결정성" 항목이 회귀를 확실하게 잡는다. 이 규칙을 위반하는 커밋은 reviewer REQUEST CHANGES 사유.
