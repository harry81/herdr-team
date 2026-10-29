# Spec: ht 실행화면 English Only 전환 + 카운트다운/프롬프트 레이아웃 + Fancy 첫 화면

- 작성: ht-planner / 2026-10-29
- 대상: `bin/herdr-team`(현재 1830행 내외), `templates/<preset>/preset.conf` 6개, `tests/test_tui_i18n.sh`(375행), 문서
- 이전 명세: `docs/specs/ht-tui-i18n-and-polish-spec.md` → 본 명세가 대체(스펙 파일 상단에 대체 표기 완료)
- 참조: `docs/specs/test-tiering-spec.md` (T1/T2/T3, blast radius)
- 회신 규약: 경로 + 1줄 요약

---

## 1. 문제 정의와 재현

1차 구현(대체 명세 기준)이 출하 기준을 못 넘었다. 사용자 실사용 피드백 3건:

| # | 증상 | 직접 원인 (코드 사실, 직접 확인) |
|---|---|---|
| F1 | 첫 화면 fancy 개선 체감 안 됨 — 배너가 프리셋 메뉴 뒤에 나옴 | `ht_banner` 호출이 L1814(precheck 직후)이고, `choose_preset_tui`는 L653 근처에서 **먼저** 실행됨 → 배너보다 메뉴가 먼저 렌더. 배너 자체도 `ht_box "herdr-team v$VERSION"` 3행 테두리라 존재감 낮음 |
| F2 | 카운트다운 겹침·Ctrl-C 잔존 (`6s remaining^Cresearch/biz...`) | (a) `preset.menu.prompt`가 개행 없는 부분 라인(`Select [1-6/...]: ` 후행 공백)으로 stderr 출력 (L563), (b) 직후 `countdown_start 10`이 **같은 stderr 라인**에 `\r  %ss remaining` 덮어쓰기 (L473), (c) `countdown_stop`의 `\r\033[K`가 그 라인 전체(프롬프트 텍스트 포함)를 지움 (L492), (d) INT trap이 `kill -INT $$`로 재발생하지만 터미널 드라이버가 찍은 `^C` 에코와 지워지지 않은 잔여 텍스트가 다음 출력과 혼선 |
| F3 | 프리셋 설명 한글 노출 | `preset_desc()`가 그대로 출력하는 `PRESET_DESC` 값에 한국어 괄호 병기 존재: `templates/{biz,creator,dev,mkt,pkm,research}/preset.conf` 2행 (예: `"Software Development (소프트웨어 개발·MVP, 4인 팀, orchestrator/planner/worker/reviewer)"`) |

추가 사실 (직접 확인):
- 카탈로그는 `_msg_en`(L98~157 근처) + `_msg_ko`(L159~216 근처) 두 벌, `ht_detect_locale`(L78)이 `HERDR_TEAM_LANG > LC_ALL > LANG > en` 분기.
- 콘솔로 나가는 한국어는 카탈로그 외에도 `log()` 계열 다수 잔존: L847, 850, 873, 880, 894, 896, 915, 920, 923, 944, 945, 949, 954, 956, 961, 970, 973, 1053, 1067, 1196, 1199, 1215, 1224, 1226, 1237, 1240, 1244, 1246, 1252, 1254, 1260, 1415, 1422, 1443, 1458, 1465, 1472, 1491, 1527, 1533, 1579, 1582, 1586, 1805 (`완료:`), 1828.
- `usage()`에 한국어 1행 힌트 존재 (L370, `한국어 안내: ... HERDR_TEAM_LANG=ko ...`).
- `tests/test_preset.sh` 등 `assert_contains` 그리프 대상 토큰은 전부 ASCII (`Software Development`, `deprecated`, `Select agent kind`, `preset=` 등) — **한국어 출력을 지워도 기존 assert 대상 토큰은 파괴되지 않음**(한국어는 assert 메시지 설명란에만 존재). 후속 기계 확인 명령은 task 2에 포함.

## 2. English Only 정책 (택1 확정 — 못박음)

**결정: ko 카탈로그 삭제 + 로케일 감지 제거. `HERDR_TEAM_LANG`은 조용히 무시(경고 출력하지 않음).**

- 구현: `_msg_ko` 전체 삭제, `ht_detect_locale`/`MSG_LOCALE`/`msg()의 ko 분기` 삭제 → `msg()`는 곧바로 `_msg_en` 위임(`msg` 호출부 인터페이스 유지로 호출부 무변경). `MSG_KEYS` 유지(패리티 테스트는 en 단일 벌 기준으로 계속 유효).
- `HERDR_TEAM_LANG` 처리: 파싱하지 않고 무시 — 어떤 값(`ko`, `fr`, 미지원)이든 출력·경고 0건. `LC_ALL`/`LANG`도 출력 언어에 영향 0.
- 근거(3줄):
  1. 단일 로케일 제품에서 두 벌 카탈로그는 유지 비용(패리티 테스트, 문안 drift)만 있고 가치가 없으며, 1차 출하에서 ko 번역이 실제로 출하 진행을 막았다.
  2. 경고 1회 출력은 CI/파이프 로그 오염을 만들고(테스트가 grep 하는 순수 출력에 노이즈 추가) 무시해야 할 환경변수에 지속적인 존재감을 준다 — 조용한 무시가 계약도 더 단순하다.
  3. `tests/test_agent_session.sh`, `test_pane_ready.sh` 등이 이미 `HERDR_TEAM_LANG=en`을 export 중 — 무시 정책이면 이 export가 no-op이 되어 **기존 테스트 무수정**이라 파괴 반경 최소.

### 2.1 비 ASCII 잔존 검사 규칙 (테스트로 강제)

| 대상 | 규칙 | 검사 |
|---|---|---|
| 콘솔 출력 (stdout+stderr 캡처) | 한글 음절(Unicode U+AC00–U+D7A3) **0건** | `grep -cP '[\x{AC00}-\x{D7A3}]'` → `0` |
| `templates/**/preset.conf` | 한글 음절 0건 (PRESET_DESC 및 주석 포함) | 동일 |
| plain 모드 출력 | `\033`, `\r` 등 escape·커서제어 0건 (기존 하드제약 유지) | `grep -c $'\033\|\r'` → 0 |

비고: 검사 범위는 **콘솔 출력과 templates 설정 파일**뿐. `bin/herdr-team` 코드 주석, `tests/*.sh` 설명란, 시딩 결과물(`agents/<preset>/AGENTS.md` 생성 문서 본문 — §9 열린 질문 Q2)은 제외.

### 2.2 기존 ko 관련 테스트·문서 처리 방침 표

| 대상 | 현재 상태 | 처리 방침 |
|---|---|---|
| `tests/test_tui_i18n.sh` tc-2 (L111+, 로케일 결정 ko 케이스) | `HERDR_TEAM_LANG=ko→ko` 등 분기 검증 | **삭제**. 같은 자리에 "무시 검증": 임의 `HERDR_TEAM_LANG=ko`/`fr` 출력이 en과 100% 동일 + 경고 0건 |
| `tests/test_tui_i18n.sh` tc-2b (L128, 미지원 값 WARN) | `fr → en + WARN 1회` 검증 | **삭제 후 부정 검증으로 교체**: `fr` 출력에 `WARN` 부재 |
| `tests/test_tui_i18n.sh` tc-2c/d/f (L135~) — ko 지원 i18n 케이스 | en/ko 나란히 비교 | **en 절만 유지** + §2.1 한글 음절 0건 검사 추가 |
| `tests/test_safe_onboarding.sh` (L7 `export HERDR_TEAM_LANG=en`) | en 고정 export | **유지(무수정)** — 무시 정책에서 no-op, 행위 변경 0 |
| `tests/test_agent_session.sh` (L6 동일) | 동일 | **유지** |
| `tests/test_pane_ready.sh` | en 고정 export 없음(확인됨) | 유지(변경 없음) |
| `docs/specs/ht-tui-i18n-and-polish-spec.md` | 구 i18n 명세 | **완료**: 파일 상단에 대체 1줄 표기 추가됨. 본문은 역사 기록으로 미수정 |
| `README.md` / `README.ko.md` | ko 언어 안내 존재 | `README.md`: TUI 예시 갱신 + `--no-color`/언어 정책 문서화. `README.ko.md` 링크는 유지하되 스크립트는 한국어 출력 없음을 명시 (task 8) |
| `usage()` 내 한국어 힌트 (L370) | `한국어 안내: ...HERDR_TEAM_LANG=ko...` | **삭제** (그 자리에 정책 1행: `Language: English only -- no locale env vars` 추가) |

## 3. 카운트다운 레이아웃 설계 (구조적 겹침 금지)

### 3.1 2줄 레이아웃 (채택)

```text
라인 N   : Select [1-6/dev/research/biz/mkt/creator/pkm] (default: dev, 10s): <사용자 입력>\n   ← 프롬프트 라인: 개행으로 확정 출력 후 절대 재출력·재가공 없음
라인 N+1 : 8s [########--]\n                                                                   ← 상태 라인: \r + \033[2K 로만 갱신
```

핵심 변경 2건:
1. `preset.menu.prompt` / `kind.menu.prompt` 카탈로그 서식을 후행 `: \n`(개행 확정)으로 변경. 카운트다운 갱신은 **항상 라인 시작의 `\r`로 상태 라인만** 건드리고, 프롬프트 라인은 건드지 않는다 (현재 bug 원인이던 "커서가 프롬프트 꼬리에 있는 상태에서 `\r` 덮어쓰기" 구조가 물리적으로 발생 불가).
2. `kickoff` 이후 확정: `countdown_start` 서브셸 출력 → 상태 라인을 갱신하면서 커서는 상태 라인에서만 이동.

### 3.2 종료 규칙 (Ctrl-C / EOF / 타임아웃 / exit 공통)

| 상황 | 상태 라인 처리 | 후속 출력 위치 |
|---|---|---|
| 사용자 입력 출발 ("" 혹은 정상) | `\r\033[2K` 후 **개행 1회**, 상태 텍스트는 사라짐 | 프롬프트 라인 아래 새 라인 |
| EOF / `read -t 10` 타임아웃 | 동일 | 동일 |
| Ctrl-C (INT) | trap에서 동일 클리어 수행 후 `kill -INT $$` 재발신 | 동일 — 터미널 드라이버의 `^C` 에코는 상태 라인에 위치하므로 클리어로 제거됨 |
| TERM/EXIT (비정상 포함) | EXIT trap에서 동일 클리어 1회 (`|| true`로 실패 무시) | 동일 |

불변식 (테스트로 강제): "종료 후 stderr의 커서가 놓인 라인은 반드시 비어 있거나(클리어 후 개행) 또는 완전히 종료 — `remaining` 텍스트와 `^C` 표시가 다음 출력과 같은 라인에 섞이는 경우 0건."

### 3.3 줄 폭 규칙

- 상태 라인 총 폭 고정 **14자** (`10s [########--]` = 3 + 공백 1 + bar 10). 갱신마다 전폭 동일(감소하는 숫자는 2자리 고정 `10s`→` 8s`가 아닌 `08s`? 아니오 — 남은 초는 10→1이므로 자리 이동을 막기 위해 2자리 고정: `10s`~`01s`). 폭 고정이라 깨질 일 없음이 기본 보장.
- TTY 진입 시 `tput cols`로 터미널 폭 취득(Bash 3.2 안전), 실패 시 폴백 80. 단 폭 고정 14 < 80이므로 어떤 환경에서도 상태 라인 자체는 줄바꿈을 유발하지 않음.
- 축소 규칙: `cols < 20`이면 bar 생략 폼(`8s`만, 3자)으로 폴백 — 동일 라인 `\r` 재갱신, 다음 라인 침범 금지.
- 일반 규칙: 어떤 갱신 문자열이든 렌더 전에 폭 검사(`strlen > cols-1 → 축소 폼`) — 줄바꿈 유발 렌더 금지.

### 3.4 표시 형식 (택1 확정: 괄호 바 진행바, 남은 초 삽입)

**`NNs [########--]`** — 앞에 남은 초(2자리 고정 `10s`…`01s`), 뒤에 대괄호 10칸 바. `read -t 10` 기준 1초 틱마다 초 감소·bar 채움 감소. (숫자 전용안은 시각성 목적에 못 미쳐 폐기. 형식 예: `10s [########--]`, `01s [#---------]`)

불변식: plain 모드(비TTY·`--no-color`·`CI`·`TERM=dumb`·`NO_COLOR`)에서는 카운트다운 **프로세스 0개, 출력 0바이트** (기존 제약 유지) + 실제 입력 블로킹(`read -r -t 10`)과 10초 타임아웃/EOF 폴백은 불변.

## 4. Fancy 첫 화면 (진짜 보이게)

### 4.1 렌더 순서 확정 (현재 문제 해결)

호출 순서 (main 흐름, 직접 확인된 현행):
```text
현행:  인자 파싱 → 스일 세션(ht_init_style, L405) → … preset/kind TUI(L638~700) → … → precheck(L1811) → ht_banner(L1814)   ← 배너가 마지막
신규:  인자 파싱 → ht_init_style → ht_banner (L405 직후로 이동) → (dry-run 아님일 때) precheck → preset/kind TUI → … 나머지 순서 유지
```

- plain 모드(비TTY/파이프/CI): 배너는 기존 1행 `herdr-team v%s` (§4.2 축소 규칙과 동일 포맷) — 위치만 앞당김, 포맷 불변.
- dry-run/templates-only/`--no-interactive`도 배너 먼저(1행) — 어느 경로든 첫 출력 라인이 배너.
- 유니코드 글립 허용 조건(§4.2)은 TTY 전용이므로 plain에 영향 0.

### 4.2 배너 박스 아트 (ASCII 기본)

```text
TTY (cols >= 40):
+--------------------------------------+
|   herdr-team v1.4.0                  |
|   One command. One AI agent team.    |
+--------------------------------------+
```
- TTY: 박스 아트(blue 테두리) + bold 타이틀 + cyan tagline. plain(비TTY·파이프·CI·`--no-color`): **기존 1행 `herdr-team v%s` 그대로** — 기존 출력 계약 유지, 박스 아트는 TTY 전용 확정.
- ASCII 폴백이 기본(`+--`, `|`). 유니코드 글립(`─ ╭╮│`)은 "TTY + UTF-8 로케일 + `HERDR_TEAM_ASCII` 미설정"에서 박스 테두리 문자만 교체 허용 — 이모지·복합 글립은 어떤 모드에서도 금지.
- 폭 축소 규칙: `tput cols` 실패 → 80 폴백. `cols < 40` → 박스 아트 생략, 1행 폴백. 박스 각 행은 cols-1 이내 — 초과 시 tagline 행 제거 → title행만 남김 → 그래도 초과하면 1행 폴백(3단 축소).
- `HERDR_TEAM_ASCII=1`: 글립만 off, 색상은 유지 — plain 모드와 독립된 밸브.

### 4.3 프리셋 목록 박스 렌더

TTY 모드에서 `choose_preset_tui`의 메뉴 본문(L557~563)을 박스 렌더로 교체:

```text
+--------------------------------------+
|  Select preset                       |
|--------------------------------------|
|  1) dev        Software Development  |
|  2) research   Deep Research & ...   |
|  3) biz        Small Business ...    |
+--------------------------------------+
Select [1-6/dev/research/biz/mkt/creator/pkm] (default: dev, 10s): 2⏎   ← 계약 토큰 유지 + 개행 확정
8s [########--]         ← 상태 라인 갱신 → 입력 도달 후 clear+개행
```
- 번호 하이라이트: 번호 bold(magenta), **기본값 항목 옆 `*` 마커 + 시각 강조**.
- 계약: 프롬프트 라인 텍스트 자체는 변경 0 — 박스는 프롬프트 **바로 위**에 렌더되는 부가 블록이고 프롬프트 라인 텍스트는 유지.
- 항목 설명: `preset_desc`의 §5.4 en only desc 사용. 박스 폭 = 최대 항목 폭 정렬, `cols` 초과 시 §4.2의 3단 축소 규칙.

### 4.4 에이전트(kind) 목록 박스

`choose_kind_tui`의 메뉴 본문(L607~612) 동일 규격 박스 렌더(§4.3 규정 동일: 테두리, 항목 bold, default `*`, 프롬프트 라인 계약 토큰 유지 + 개행 확정, 상태 라인 동일).

### 4.5 완료 안내·최종 요약

- `ht_summary` (TTY): 박스 렌더 — 헤더 `Team ready`, 본문 `prefix/preset/kind/layout/agents` 각 행, 말미 `next: herdr agent list`. plain 모드: 현행 2행(`[done] ...`, `next: herdr agent list`) 유지 — 포맷 변경 0.
- `log "완료: ..."` (L1805) → `log "Done: prefix=… preset=… (…)"` 영문 전환 (§5.3; test_preset이 이 라인의 한국어 토큰을 grep하지 않음 — T2에서 확인).
- 성공/경고/에러 시각: plain은 `[ok]/[warn]/error:` 접두어 계약 유지, TTY는 green/yellow/red — 접두어 텍스트 자체는 유지.

### 4.6 색상 테마 (최대 8색 팔레트 확정)

| 용도 | ANSI 코드 | bg | 쓰이는 곳 |
|---|---|---|---|
| title/bold | `\033[1m` | — | 배너 타이틀, 프롬프트 bold |
| cyan | `\033[36m` | — | 배너 tagline, 박스 테두리 |
| blue | `\033[34m` | — | 배너 테두리, step 번호 |
| green | `\033[32m` | — | ok/step done `[ok]` 표시 |
| yellow | `\033[33m` | — | warn(`WARN: ` 뒤 본문) |
| red | `\033[31m` | — | error 본문(`error: ` 접두어 자체는 무색 유지 — grep 계약) |
| magenta | `\033[35m` | — | 메뉴 번호·default `*` 하이라이트 |
| dim | `\033[2m` | — | box 테두리(dim)·부 설명 |

규칙: fg 8색 + bold + dim만 사용. bright/256/true color 금지. `reset \033[0m` 필수(라인 개행 전 반드시 끄기). plain 모드는 모두 미출력 — `✖ ⚠` 기호는 plain에서 `[error]/[warn]/error:` 텍스트로 전부 치환(접근성 — 색상만으로 의미 전달 금지 유지).

## 5. 문자열 카탈로그 전면 개정표

### 5.1 정책 적용 (§2)

- `_msg_ko` 전체 삭제, `ht_detect_locale`/`MSG_LOCALE` 삭제, `msg()` → `_msg_en` 직행 (인터페이스·키 체계 불변).
- usage 한국어 힌트(L370) 삭제, 영문 정책 1행 추가.

### 5.2 prompt 서식 변경 (개행 확정)

| key | 현행 | 신규 |
|---|---|---|
| `preset.menu.prompt` | `Select [1-%s/%s] (default: %s, 10s): ` (개행 없음) | 동일 텍스트 + 후행 `\n` (토큰 유지) |
| `kind.menu.prompt` | `Select [1-4/opencode/claude/codex/agy] (default: opencode, 10s): ` | 동일 텍스트 + 후행 `\n` |

계약: `Select [1-6/...]: ` 텍스트 자체 변경 0 — 후행 개행만. (test_preset `:130` 등 기존 assert 그대로 통과.)

### 5.3 ko 잔존 → en 전환 카탈로그 신규 표 (콘솔 출력 대상 전부)

| key(신규) | 현행 한국어(위치) | 신규 en 문안 |
|---|---|---|
| `log.gitignore.skip_opt` (847) | `gitignore 보강 생략(--no-gitignore)` | `skip: gitignore augmentation (--no-gitignore)` |
| `log.gitignore.skip_nonrepo` (850) | `git 저장소가 아니므로 .gitignore 보강 생략: %s` | `skip: gitignore augmentation (not a git repo): %s` |
| `log.gitignore.already` (858) | `+ gitignore: 이미 있음 → %s` | `+ gitignore: already present -> %s` |
| `log.gitignore.append` (873) | `gitignore 보강: %s → %s` | `gitignore append: %s -> %s` |
| `log.active_preset.unknown` (880/1422) | `[herdr-team] 경고: 알 수 없는 active preset '%s' → write-back 생략, '%s'로 활성화` | `[herdr-team] WARN: unknown active preset '%s' -> write-back skipped, activating '%s'` |
| `log.writeback` (894) | `write-back: AGENTS.md → agents/%s/AGENTS.md (관리 섹션 내부만)` | `write-back: AGENTS.md -> agents/%s/AGENTS.md (managed section only)` |
| `log.writeback.skip` (896) | `write-back 생략: AGENTS.md 에 관리 섹션이 없습니다 (사용자 본문은 루트에 유지)` | `write-back skipped: AGENTS.md has no managed section (user content stays at root)` |
| `log.backup` (915/920) | `백업: %s` | `backup: %s` |
| `log.activate` (923) | `activate: agents/%s/AGENTS.md → AGENTS.md (관리 섹션 치환, 사용자 본문 보존)` | `activate: agents/%s/AGENTS.md -> AGENTS.md (managed replacement, user content preserved)` |
| `log.watcher.skip_start` (944) | `watcher 생략: --no-start (감시할 agent 없음)` | `watcher skipped: --no-start (no agents to watch)` |
| `log.watcher.skip_split` (945) | `watcher 생략: --templates-only (pane 미분할)` | `watcher skipped: --templates-only (no pane split)` |
| `log.watcher.missing` (949) | `WARN: herdr-watcher 를 찾을 수 없습니다 → watcher 기동 생략` | `WARN: herdr-watcher not found -> watcher not started` |
| `log.watcher.skip_py` (954) | `WARN: python3 없음 → watcher 기동 생략` | `WARN: python3 not found -> watcher not started` |
| `log.watcher.running` (956) | `watcher 이미 가동 중 (pid=%s, pidfile %s) → 생략` | `watcher already running (pid=%s, pidfile %s) -> skipped` |
| `log.watcher.logfail` (961) | `WARN: watcher 로그를 쓸 수 없습니다 (%s) → watcher 기동 생략` | `WARN: cannot write watcher log (%s) -> watcher not started` |
| `log.watcher.fail` (970) | `WARN: watcher 기동 실패(즉시 종료) → 계속 진행 (종료코드 불변)` | `WARN: watcher start failed (immediate exit) -> continuing (exit code unchanged)` |
| `log.watcher.started` (973) | `watcher 기동: pid=%s prefix=%s- (L2 ask 팝업도 Allow once 자동 승인됩니다 — 취소: kill %s)` | `watcher started: pid=%s prefix=%s- (L2 asks auto-approved via Allow once — stop: kill %s)` |
| `log.pane.foreground_wait` (1053) | `pane %s shell foreground 대기 중 (attempt %s)` | `pane %s waiting for shell foreground (attempt %s)` |
| `log.pane.ready_wait` (1067) | `pane %s ready 대기 중 (attempt %s)` | `pane %s ready wait (attempt %s)` |
| `log.perm.skip_opt` (1196) | `권한 시딩 생략(--no-template)` | `permissions seeding skipped (--no-template)` |
| `log.perm.no_tpl` (1199) | `permissions 템플릿 없음 → 권한 시딩 생략` | `permissions template not found -> seeding skipped` |
| `log.perm.merge` (1224) | `권한 병합: .opencode/opencode.jsonc (사용자 키 보존 + baseline L0/L2/L3)` | `permissions merge: .opencode/opencode.jsonc (user keys preserved + baseline L0/L2/L3)` |
| `log.perm.parse_fail` (1226) | `경고: 기존 .opencode/opencode.jsonc JSON 파싱 실패 → 원본 유지(백업만 생성)` | `WARN: existing .opencode/opencode.jsonc JSON parse failed -> keeping original (backup only)` |
| `log.perm.create` (1237) | `권한 생성: .opencode/opencode.jsonc (baseline: L0/L2 + L3 hard-deny)` | `permissions created: .opencode/opencode.jsonc (baseline: L0/L2 + L3 hard-deny)` |
| `log.perm.deny_scope` (1240) | `경고: edit deny-list 는 edit 도구 한정 — shell(sed -i/cp/mv/echo >) 우회는 차단하지 않습니다(best-effort).` | `WARN: edit deny-list covers the edit tool only — shell bypasses (sed -i/cp/mv/echo >) are NOT blocked (best-effort)` |
| `log.perm.no_profile` (1244) | `경고: 권한 프로파일 없음 → skip: profile/%s/%s.json` | `WARN: no permission profile -> skip: profile/%s/%s.json` |
| `perm.err.merge_fail` (1246) | `error: 권한 병합 실패: %s/%s` | `error: permission merge failed: %s/%s` |
| `log.perm.inject` (1252) | `권한 주입: .opencode/agents/%s.md frontmatter (V2 permissions/policies)` | `permissions injected: .opencode/agents/%s.md frontmatter (V2 permissions/policies)` |
| `log.perm.no_agent` (1254) | `경고: agent 정의 없음 → 권한 주입 skip: .opencode/agents/%s.md` | `WARN: no agent definition -> permissions injection skipped: .opencode/agents/%s.md` |
| `err.need_cmd` (1260) | `error: '%s' 명령을 찾을 수 없습니다.` | `error: command not found: %s` |
| `log.step.skip_tpl` (1415/1527) | `템플릿 단계 생략(--no-template)` / `opencode agent 단계 생략(--no-template)` | `templates step skipped (--no-template)` / `opencode agent step skipped (--no-template)` |
| `log.transition` (1443) | `preset=%s active=%s (전환 감지)` | `preset=%s active=%s (switch detected)` |
| `log.seed_preset` (1458/1465) | `+ seed(내장): agents/%s/%s-%s.md` / `+ canonical(내장): agents/%s/AGENTS.md` | `+ seed (bundled): agents/%s/%s-%s.md` / `+ canonical (bundled): agents/%s/AGENTS.md` |
| `log.backup_dryrun` (1472) | `+ backup: AGENTS.md → .herdr-team/backup/ (타임스탬프)` | `+ backup: AGENTS.md -> .herdr-team/backup/ (timestamped)` |
| `log.import_legacy` (1491) | `import(legacy): agents/%s-%s.md → agents/%s/%s-%s.md (원본 보존)` | `import(legacy): agents/%s-%s.md -> agents/%s/%s-%s.md (originals preserved)` |
| `log.oa.no_tpl` (1533) | `opencode agent 템플릿 없음 → 설치 생략` | `opencode agent template not found -> install skipped` |
| `log.oa.no_role` (1579) | `경고: ROLE-%s.md 없음 → skip` | `WARN: ROLE-%s.md not found -> skip` |
| `log.oa.exists` (1582) | `opencode agent 존재 → 생략: .opencode/agents/%s.md` | `opencode agent exists -> skipped: .opencode/agents/%s.md` |
| `log.oa.created` (1586) | `opencode agent 생성: .opencode/agents/%s.md` | `opencode agent created: .opencode/agents/%s.md` |
| `log.done` (1805) | `완료: prefix=%s preset=%s (%s)` | `Done: prefix=%s preset=%s (%s)` |
| `log.templates_only_done` (1828) | `templates-only: 템플릿 설치 완료 (pane 분할 생략)` | `templates-only: templates installed (pane split skipped)` |
| `log.prefix.legacy` (기타 개별) | 나머지 상시 log 중 한국어 병기된 `log "agent %s 시작 생략"` 등 | 동일 규칙 — worker가 전수 grep 후 이 표 형식으로 1:1 문안 첨부하여 PR 본문에 나열 |

참고: `_msg_en` 5.A~5.E 전체는 현행 그대로 유지 — 문안 개정 없음 (본 스펙의 변경은 ko 제거·prompt 개행·위 표 신규 key뿐). em dash/·/→ 등 비한글 특수문자의 ASCII 대체는 열린 질문 Q1.

### 5.4 preset.conf PRESET_DESC 개정 (F3 직접 수정)

| 파일 | 신규 PRESET_DESC (en only) |
|---|---|
| `templates/dev/preset.conf` | `Software Development (MVP teams, TDD; orchestrator/planner/worker/reviewer)` |
| `templates/research/preset.conf` | `Deep Research & Knowledge Discovery (sourced comparison, verified report)` |
| `templates/biz/preset.conf` | `Small Business Operations (support programs, CS, ops automation)` |
| `templates/mkt/preset.conf` | `Local & SNS Marketing (keyword/competitor analysis, compliant copy)` |
| `templates/creator/preset.conf` | `Content Creation & Publishing (outline, draft, proofread)` |
| `templates/pkm/preset.conf` | `PKM Vault Team (note/vault-page pipeline, researcher on-demand)` |

- 테스트 계약: 선두 영문 라벨 유지 (`Software Development` 등 — test_preset `:125,127,130-131` 토큰 계속 통과).
- 같은 파일의 한국어 주석(L1 `# preset: …` 병기)도 정리: `# preset: dev — Software Development team (default)` 처럼 영문만.

### 5.5 코드주석·문서 생성물 처리 (경계)

- `bin/herdr-team` 코드 주석 한국어 유지(기반 코드 문해력 유지 — 검사 범위 외).
- 템플릿/생성 문서(`templates/agents/*.md`, bash-generates AGENTS.md 내부 한국어 본문)는 **콘솔 출력이 아님** → 본 스펙 범위 밖 — 후속 task 별도 승인 (열린 질문 Q2).

## 6. 파일별 변경 계획

| 파일 | 변경 | 성격 |
|---|---|---|
| `bin/herdr-team` | (a) `_msg_ko`·`ht_detect_locale`·ko 분기 삭제 + `HERDR_TEAM_LANG` 무시, (b) prompt 개행 확정(§5.2), (c) `countdown_start/stop` 2줄 레이아웃 개편 + 폭 규칙(§3.3) + 종료 규칙(§3.2), (d) `ht_banner` 이동(L1814 → `ht_init_style` 직후) 및 박스 아트 확장(§4.2), (e) preset/kind 메뉴 박스 렌더(§4.3/4.4), (f) `ht_summary` 박스 + §5.3 log 영문 전환표 적용, (g) 신규 옵션 없음(기존 옵션 동작 계약 유지) | **core** |
| `templates/{dev,research,biz,mkt,creator,pkm}/preset.conf` | PRESET_DESC en only + 주석 en화 | core 경로 (`templates/**` — test-tiering 매핑: `test_preset.sh`, `test_permissions_seed.sh` 스위트 대응) |
| `tests/test_tui_i18n.sh` | tc-2/2b/2c/d/f ko 관련 케이스 삭제/교체 + 한글 음절 0건 검사 + plain모드 ESC/CR 0건·status 라인 분리 검증 | 신규/수정 테스트 |
| `tests/test_tui_layout.sh` | 신규 — F2 전용: 논TTY 카운트다운 0 바이트/프로세스 0개, prompt 라인 통합(출력 뒤 토큰 `Select [` 라인 개행 존재), 넓이 규칙 | 신규 테스트 |
| `tests/test_preset.sh` | **예외 1행 허용**: `:58` 의 `소상공인` grep 토큰만 신규 영문 문안 토큰 `support programs` 로 교체(English Only 강제). 나머지 460개 단언은 불변 | 1행 수정 + T2 검증 |
| `README.md` / `README.ko.md` | TUI 예시 갱신(박스 아트+영어 only 배너), `--no-color`, 언어 정책 1행 | docs (surface) |
| `docs/specs/ht-tui-i18n-and-polish-spec.md` | 완료 — 대체 1줄 표기 | 문서 |

## 7. Task Breakdown (ht-worker TDD — 티어는 test-tiering-spec)

공통: blast radius `bin/herdr-team` + `templates/**` 둘 다 test-tiering §c 매핑 **core** → 모든 태스크 tier=T2 종료, push/CI에서 T3 승격.
T1 = `bash tests/test_tui_layout.sh && bash tests/test_tui_i18n.sh` (편집 루프마다).
T2 = `bash scripts/testmap.sh`가 출력한 스위트 전부 — 즉 `bash tests/test_agent_session.sh && bash tests/test_pane_ready.sh && bash tests/test_preset.sh && bash tests/test_permissions_seed.sh`(templates 변경 포함 태스크). 각 태스크는 독립 커밋(롤백 단위).

| # | 태스크 | DoD | 검증 명령 |
|---|---|---|---|
| 0 | 테스트 골격: `tests/test_tui_layout.sh` 신규 + `tests/test_tui_i18n.sh`에 한글 음절 0건 검사(콘솔 대상·templates 대상) 추가 — **Red** (현행은 한글 있음) | Hangul-0건 검사가 Red로 잡힘 | T1 (의도된 Red) |
| 1 | English Only 전환: `_msg_ko`·`ht_detect_locale`·MSG_LOCALE ko분기 삭제, `HERDR_TEAM_LANG` 무시(경고 0), `usage` L370 한국어 힌트 삭제→영어 정책 1행 | tc-2 교체 케이스 Green: 임의 env 출력==en 동일+WARN 부재; 패리티 en 단일 벌 | T1; T2 |
| 2 | 카탈로그 ko 잔존 전환 (§5.3 표 전체, log 계열) | 콘솔 캡처 한글 음절 0건 테스트 Green (tc-3 확장) | T1; T2 |
| 3 | preset.conf 6파일 PRESET_DESC·주석 en only (§5.4) | templates 한글 0건 검사 Green; test_preset 라벨 계약 통과 | T1; T2 (templates 스위트 포함) |
| 4 | 카운트다운 2줄 레이아웃: prompt 개행 확정 · `countdown_start/stop` 상태라인 `\r\033[2K`·종료 규칙(§3.2)·Ctrl-C 시그널·폭 규칙(§3.3)·bar 형식(§3.4) | tc-layout: plain 0바이트·0프로세스, 종료 후 residual 0건, `remaining`과 프롬프트 텍스트 동일 라인 부재 | T1 + `bash tests/test_herdr_precheck.sh`; T2 |
| 5 | 배너 이동 + 박스 아트 + 폭 축소 규칙 (§4.1/4.2) | TTY 캡처에서 `Select AI team preset`보다 배너 박스 먼저; plain 1행 유지; cols<40 축소 케이스 | T1; T2 |
| 6 | preset/kind 메뉴 박스 렌더 + 번호 하이라이트 + default 표시 (§4.3/4.4) | 계약 토큰 `Select [1-N/…`, `Select agent kind` 유지 — test_preset 통과; plain은 박스 없이 목록·토큰 동등 | T1; T2 |
| 7 | `ht_summary` 박스 + `완료→Done` 등 마무리 라인 (§4.5) | plain `[done]`/`next:` 2행 동일 유지, dry-run 스위트 전부 Green | T1; T2 |
| 8 | 문서: README/README.ko TUI 예시 갱신 + 언어 정책 1행 + `--no-color` 문서화 | test_preset README 섹션 통과 | `bash tests/test_preset.sh` |

## 8. 테스트 계획 + TTY 캡처 검증 절차 (reviewer 강화)

### 8.1 신규/수정 테스트 체계

- `tests/test_tui_layout.sh` — F2 전용 regression (초고속, 논TTY): 카운트다운 0바이트·0프로세스, prompt 라인 개행 확정, 종료 후 residual 0건, 폭 규칙.
- `tests/test_tui_i18n.sh` — 유지/신설 3건: (tc-3) 토큰 고정 검증 유지, (H-1) 콘솔 출력 한글 음절 0건 — 6종 시나리오(preset/kind/parse/precheck/가드 오류/dry-run) 각각, (H-2) `templates/*.conf` 한글 음절 0건.
- `tests/test_tui_review_checks.sh` — 신규 검 보조: §8.2의 기계 5건 논리를 reviewer 스크립트로 재사용 (raw 캡처 파일 경로를 인자로 받아 pass/fail 리포트).
- 기존 유지 불변: test_preset/agent_session/pane_ready/safe_onboarding/precheck의 assert 설명란 한국어는 grep 대상 아님 — 테스트 로직 무수정.

### 8.2 TTY 캡처 절차 (reviewer 전용, 임시 쓰기 허용)

**캡처 아티팩트 경로 규칙**: reviewer는 승인 시 `mktemp -d` 기반 임시 디렉터리 하부 `$TMP/ht-tty-qa/<scenario>.log`로 캡처(파기성). **레포 커밋 금지.** 리뷰 보고서에 아티팩트 경로 첨부:

```text
$TMP/ht-tty-qa/preset-select.log   ← raw bytes (ANSI 포함)
$TMP/ht-tty-qa/kind-select.log
$TMP/ht-tty-qa/ctrlc-interrupt.log
```

명령 (터미널 폭 100 고정: `stty cols 100` 또는 `-qec` 前 COLUMNS export — 캡처 재현성 위해):
```sh
1) script -qec 'sh -c "printf \"2\\n1\\n\" | timeout 25 bash bin/herdr-team test --dry-run --no-template"'    "$T/preset-select.log"
2) script -qec 'sh -c "printf \"1\\n2\\n\" | timeout 25 bash bin/herdr-team test --dry-run --no-template"'    "$T/kind-select.log"
3) setsid script -qec 'exec bash bin/herdr-team test --no-template'                                           "$T/ctrlc-interrupt.log"
   # 3초 후 kill -INT -(PGID) — setsid로 만든 프로세스 그룹에 INT 전달 → 타이머 틱 도중 시그널 경로 검증
```

**5건 검사 항목 (기계적으로 pass/fail)**:
1. **라인 분리**: 프롬프트 라인(`Select [1-` 토큰)의 라인이 `\n`로 확정하고, 그 다음 라인에 `[##...--]` 상태 라인이 시작 — 동일 라인에서 토큰과 `remaining`이 섞인 라인 **0건** (grep `Select \[1-.*remaining` → 0).
2. **CR 이후 라인**: 어떤 CR(`\r`) 이후 세그먼트에도 프롬프트 텍스트(`Select [`) 재출력 없음 — 캡처 전체에서 `Select \[1-` 발생 횟수는 박스 프리젠터 제외하고 프롬프트 라인당 **정확 1회** (갱신 루프가 이를 덧쓰지 않음을 의미).
3. **Ctrl-C 잔존 0건**: ctrlc 시나리오 캡처 tail — INT 전송 지점 이후 `remaining`/`^C` 잔여 **0건** (캡처를 INT 마커 시점 기준 tail에서 `grep -c 'remaining\|\^C'` → 0).
4. **한글 음절 0건**: 3개 캡처 모두 `grep -cP '[\x{AC00}-\x{D7A3}]'` → 0.
5. **배너 최상단**: 캡처에서 첫 출력 라인 블록이 배너 박스(plain의 경우 `herdr-team v`)이고 그 이후 프리셋 메뉴 — `head -c` 기준 배너 토큰이 `Select AI team preset`보다 **먼저** 등장.

### 8.3 대표 시나리오 3종 — 기대 와이어프레임 (고정)

**S1 — 프리셋 정상 입력 (TTY, cols>=40, `printf '2\n1\n' |`, TTY 캡처)**
```text
+--------------------------------------+
|   herdr-team v1.4.0                  |
|   One command. One AI agent team.    |
+--------------------------------------+
+--------------------------------------+
|  Select preset                       |
|--------------------------------------|
|  1) dev *     Software Development   |
|  2) research  Deep Research & ...    |
|  3) biz        Small Business ...    |
|                                      |
|  -> default: dev                     |
+--------------------------------------+
Select [1-6/dev/research/biz/mkt/creator/pkm] (default: dev, 10s): 2
8s [########--]         ← 상태 라인 갱신 → 입력 도달 후 clear+개행
... (kind 메뉴 동일 규격)
[done] prefix=test preset=research kind=opencode layout=2col agents=4   (dry-run·plain의 경우)
next: herdr agent list
```
**plain/파이프**(논TTY): 박스/상태 없음 — 기존 계약 토큰 1행 스트리밍 그대로 (프롬프트는 후행 개행).

**S2 — 에이전트(kind) 정상 입력** (plain/파이프: 박스·상태 라인 없이 기존 계약 토큰 1행 스트리밍 — 프롬프트 후행 개행만 추가)
```text
+--------------------------------------+
|  Select agent kind                   |
|--------------------------------------|
|  1) opencode    OpenCode Interpreter |
|  2) claude      Anthropic Claude Code|
|  3) codex       OpenAI Codex / CLI   |
|  4) agy         Google Antigravity   |
+--------------------------------------+
Select [1-4/opencode/claude/codex/agy] (default: opencode, 10s): 2
(상태 라인 갱신 → clear+개행)
```
**S3 — 카운트다운 도중 Ctrl-C** (stdin 미제공, 3초 뒤 INT)
```text
... 배너·박스·프롬프트 동일
6s [######----]           ← 상태 라인 갱신 중
(사용자 Ctrl-C)
→ INT trap → 상태 라인 `\r\033[2K`\+개행 → 종료(130)
→ 화면 잔존: 0건 (`remaining`·`^C` 잔여 미출력 — 터미널 에코 `^C`는 클리어로 제거)
```

## 9. 엣지 케이스

1. **INT 재발신(`kill -INT $$`)과 trap 중복 실행**: trap 핸들러 재입 방지 1회성 가드(예: `HT_CNT_DONE` 플래그) — 현재 flag-file 방식을 유지하되 1회성은 명시적.
2. **mktemp 실패 환경(TMPDIR read-only)**: `HT_CNT_FLAG` 공백 → 카운트다운 서브셸 즉시 종료, 부모는 `read -t 10` 그대로 — 실패해도 기능 저하 없음.
3. **tput cols 실패/0 반환** → 80 폴백 2단계 규칙 (§3.3).
4. **CJK 폭**: 상태 라인·배너·메뉴 모두 ASCII 확정 — 셀 폭 계산 문제 없음 (`HERDR_TEAM_ASCII=1`은 TTY에서 유니코드 글립만 off, plain은 원래 ASCII).
5. **clear/개행 경합**: `countdown_stop`은 정확히 `printf '\r\033[2K\n'` 1회(clear + newline 한 덩어리) — stop이 여러 경로(INPUT/timeout/Ctrl-C/EXIT)에서 불리는 중복 실행은 1회성 가드로 방지.
6. **`HERDR_TEAM_LANG` 기존 스크립트**: 무시 정책 — 기존 스크립트에 값이 남아 있으면 그대로 출력 영향 0. 문서화 명시.
7. **plain 모드 캡처 조합**: `script -qec`에서 `--no-color`/`NO_COLOR` 조합도 캡처 1회 추가 — plain 회귀가 캡처에서도 동일하게 잡힘 확인.
8. **Bash 3.2**: 내부 구현은 현재 코드가 이미 3.2 안전(재귀/연관배열 미사용) — 신규 기능도 동일 규칙. `countdown` 폭 취득은 `tput cols`만 사용(`$COLUMNS`는 non-interactive에서 미정).
9. **dry-run의 카운트다운**: `--dry-run`도 TUI는 동작하므로 TTY에서 상태 라인 렌더 — 논TTY만 plain. E2E 명령은 `timeout 25` 상한 유지.

### 열린 질문 (PM 확정 필요)

- **Q1**: en 문안의 em dash(—)/·/→/① 등 비한글 특수문자를 ASCII(`-`, `*`, `->`)로 전면 교체할지 — 카탈로그 en에 이미 em dash 다수. (권장: 교체 — 오픈소스 최대 호환성, 단 테스트 grep 토큰과 무충돌 확인 후.)
- **Q2**: 시딩 문서 본문(`templates/agents/*.md`, bash 생성 AGENTS.md 내부 한국어)의 en 전환은 본 스펙 범위 밖 — 후속 명세 필요 여부.

## 10. 롤백

- 태스크 0~8 각각 독립 커밋 → 개별 `git revert`. 런타임 영구 상태 추가 없음(countdown flag file은 mktemp 임시).
- 런타임 완화책: `--no-color`/`NO_COLOR`(시각 요소 전면 off = 기존 plain 흐름과 동등). 영문 전환·배너 이동은 revert로만 되돌림 — 기존 plain 1행 배너·`[done]` 계약은 유지되므로 revert 없는 완화도 출력 계약은 준수.
- 계약 안전망: H-1/H-2 한글 0건, tc-3 "plain escape·CR 0건", test_preset 전체(계약 토큰·라벨) — 위반 커밋은 reviewer REQUEST CHANGES 사유.

