# TUI i18n 스위트 CI 실패 분석·해결 명세 (fix/windows-runtime-compat)

- 브랜치: `fix/windows-runtime-compat` / CI 워크플로: `.github/workflows/ci.yml` (존재 확인)
- 대상: `tests/test_tui_i18n.sh` (382행, **테스트 전용 수정** — 제품 코드 `bin/herdr-team` 수정 없음)
- 로컬 베이스라인 (본 머신, 실측): `RESULT: PASS=342 FAIL=0` — CI의 10건은 로컬 미재현 (환경 의존)
- 작성자: ht-planner (문서 전용, 코드 수정 없음)

---

## 0. 요약

10건은 **하나의 원인이 아니라 5개 원인 그룹**이다. 모두 제품 버그가 아니라 **테스트 하니스가 CI 러너
환경(ubuntu-latest)의 상태에 의존**하기 때문이다. 검증된 원인:

| 그룹 | 원인 | 실패 단언 |
|---|---|---|
| G1 | 러너 PATH에 herdr CLI 없음 → 실모드 호출이 precheck에서 조기 종료 | tc2d_layout (1건) |
| G2 | 러너에 ko_KR.UTF-8 로케일 없음 → 자식 bash의 setlocale 경고가 캡처 출력에 섞임 | tc2_ko, tc2g 목록출력 (2건) |
| G3 | tc5 TTY 케이스의 `env -u CI -u NO_COLOR`에 `GITHUB_ACTIONS` 누락 → 러너에서 plain 모드 강제 | tc5 2건 |
| G4 | TTY 시뮬레이션 케이스가 TERM을 강제하지 않음 → 러너의 TERM 미설정/`dumb`로 컬러 모드 off | tc4_색상, tc7_TTY 3건, (tc5 2건에도 중복 기여) |
| G5 | 단언이 저장소 루트의 `.herdr-team/preset=dev` 상태(=gitignore된 로컬 아티팩트)에 의존 → CI 프레시 체크아웃에는 상태 없음 | tc7_계약_dryrun_isolation (1건) |

---

## 1. CI 러너 확인 (사실)

`.github/workflows/ci.yml`: `runs-on: ubuntu-latest` (Linux 러너, macOS 없음). 총 13개 스위트 step,
**herdr CLI 설치 step 없음** — 러너 PATH에 herdr는 없다. 로케일/TERM 설정 step도 없다.

러너 환경 사실(문서 근거):
- `CI=true`, `GITHUB_ACTIONS=true`는 러너가 모든 step에 주입한다(제품 `ht_init_style`의 plain 판정 인자).
- ubuntu-latest에 `script`(util-linux), `jq`, `mktemp`(GNU), `timeout`, `od`, `ps`, `tput` 모두 사전 설치됨
  (runner-images 사전 설치 소프트웨어 목록). 즉 **script 부재로 인한 SKIP은 러너에서 발생하지 않는다**.
- 로케일: hosted 러너 이미지의 비-C 로케일은 `en_US.utf8`뿐이고, actions-runner 컨테이너는
  LANG/LC_ALL 자체가 미설정(POSIX 폴백) — community discussion #149813 참조. **ko_KR.UTF-8은 없다**.
- TERM: 러너가 step에 TERM을 보장한다는 근거 없음 — 미설정 또는 `dumb` (**추측 표기**, 미확정.
  단 두 값 모두 제품 `ht_init_style`의 컬러 off 조건이므로 증상은 동일하고 수정안은 이 불확실성에
  영향받지 않는다).
- 러너는 Linux만 사용 → macOS/BSD mktemp·script 차이는 본 실패와 무관.

## 2. 10건 단언 분석 (tests/test_tui_i18n.sh)

스위트는 케이스 함수 없이 선형 블록이다. 단언 위치와 의존 환경:

| # | 단언 (행) | 블록 (행) | 단언 내용 | 의존 환경 요인 |
|---|---|---|---|---|
| 1 | `tc2_ko환경_출력_en과_동일` (121) | tc-2 (117-128) | ko env 출력 == C locale 기출력 (`assert_equal`) | **로케일**: ko 쪽에 `LC_ALL=ko_KR.UTF-8` → 러너에서 미설치 로케어 → 자식 bash setlocale 경고가 `2>&1` 캡처에 포함 → base와 달라짐 |
| 2 | `tc2d_layout` (166) | tc-2d (158-168) | `test --layout bogus_layout --no-interactive` 출력에 `error: unknown layout` 토큰 | **dry-run 아님**(실모드) → `precheck_deps`(bin:799-801) 실행 → herdr 부재 러너에서 exit 127, 레이아웃 에러 도달 전 종료 |
| 3 | `tc2g_ko환경_목록출력_동일` (229) | tc-2g (220-229) | ko env `--list-presets` 출력 == C locale 기출력 | G2와 동일 메커니즘 |
| 4 | `tc5_TTY_카운트다운_표시` (285) | tc-5 TTY (283-305) | pty 출력에 카운트다운 `s [` 토큰 | 카운트다운 렌더는 `HT_STYLE_COLOR=1` 요구(bin:525) → `env -u CI -u NO_COLOR`만으로 **GITHUB_ACTIONS 누출**(284) + TERM 미강제 |
| 5 | `tc5_BSD_mktemp_카운트다운_표시` (300) | 〃 (288-302) | BSD mktemp 스텁 하 카운트다운 표시 | 284와 동일(299의 env 누출) |
| 6 | `tc7_계약_dryrun_isolation` (312) | tc-7 (307-320) | dry-run 출력에 `(dry-run isolation)` 토큰 | 토큰은 `active == PRESET`일 때만 출력(bin:1637-1642) → 저장소 루트 `.herdr-team/preset=dev` 상태 의존 (gitignore:2) |
| 7 | `tc4_TTY_색상_활성` (341) | tc-7 TTY (339-346) | pty 출력에 ESC(0x1b) 존재 | 컬러 모드 요구 → 340행은 CI/GITHUB_ACTIONS/NO_COLOR만 unset, **TERM 미강제** |
| 8 | `tc7_TTY_배너_박스` (342) | 〃 | TTY 배너 박스 `+---` | 〃 (배너 박스는 `HT_STYLE_COLOR=1`, bin:430) |
| 9 | `tc7_TTY_배너_tagline` (344) | 〃 | tagline 텍스트 | 〃 |
| 10 | `tc7_TTY_step_done` (345) | 〃 | step `[ok]/done` 마커 | 〃 |

공통 하위 의존성 (제품 코드 판정 로직, bin:417-425 `ht_init_style`): 컬러 모드 =
`NO_COLOR_MODE=0 ∧ stderr가 TTY(-t 2) ∧ TERM 비어있지 않고 dumb 아님 ∧ NO_COLOR 미설정 ∧ CI 미설정 ∧
GITHUB_ACTIONS 미설정`. 카운트다운(bin:522-546)과 배너 박스(bin:428-446)는 `HT_STYLE_COLOR=1`을 요구한다.
stty/tput은 `/dev/tty` 조회 + 실패 시 80 폴백(bin:498-508)이라 러너에서 안전.

## 3. 재현 실험 기록 (로컬, 실측)

| 실험 | 명령 | 결과 | 근거 그룹 |
|---|---|---|---|
| R1 | `GITHUB_ACTIONS=1 bash tests/test_tui_i18n.sh` | **PASS=340 FAIL=2** — tc5 2건만 FAIL. 284/299행이 `-u GITHUB_ACTIONS` 없어 누출 확인 | G3 |
| R2 | `env -u TERM bash tests/test_tui_i18n.sh` | **PASS=336 FAIL=6** — tc5 2건 + tc4_색상 + tc7_TTY 3건. TERM이 컬러 모드 결정 확인 | G4(+tc5 중복 기여) |
| R3 | `env PATH=/usr/bin:/bin bin/herdr-team test --layout bogus_layout --no-interactive` | 출력 = `ERROR herdr CLI not found...`, 레이아웃 에러 토큰 **없음** → tc2d FAIL 메커니즘 재현 | G1 |
| R4 | `env PATH=/usr/bin:/bin bin/herdr-team test --layout bogus_layout --no-interactive --dry-run` | 레이아웃 에러 토큰 **정상 출력** (dry-run은 precheck 생략, bin:799 게이트) | G1 해소 근거 |
| R5 | `LC_ALL=xx_YY.UTF-8 bash -c 'echo hi'` | `bash: warning: setlocale: LC_ALL: cannot change locale` 출력 확인 (ko_KR 미설치 러너 시나리오 시뮬레이션) | G2 메커니즘 |
| R6 | `LANG=xx_YY.UTF-8 bash -c 'echo hi'` | **경고 없음** — LANG 단독은 경고 안 냄 → CI에서 `tc2_fr`(LANG만, 122행)이 실패 리스트에 없은 것과 정합 | G2 정합성 |
| R7 | 로컬 `locale -a` | `ko_KR.utf8` **존재** → 로컬에서 R5 시나리오가 실제로 발생하지 않아 tc2/tc2g 로컬 미재현이 설명됨 | G2 |
| R8 | `--cwd` 프레시 임시 dir로 `test --preset dev --dry-run --template-dir ...` | 출력에 `(switch detected)` — `(dry-run isolation)` **없음** | G5 |
| R9 | R8 + 임시 dir에 `.herdr-team/preset=dev` 시드 | `[herdr-team] prefix=test preset=dev (dry-run isolation)` **정상 출력** | G5 해소 근거 |
| R10 | `GITHUB_ACTIONS=1`+`env -u TERM` 조합 | R1∪R2 = 8건. 나머지 tc2 2건은 R5/R7, tc2d는 R3, tc7-iso는 R8 → **10건 전부 설명 완료** | 전체 |

재현 불가 사실(정확히): CI 러너 자체의 조합 환경(herdr 부재 + ko locale 부재 + TERM 미보장 +
프레시 체크아웃)은 로컬에서 원커맨드로 완전 재현할 수 없다. 대신 위처럼 **변수별 시뮬레이션으로
각 단언의 실패 메커니즘을 개별 검증**했고, 각 메커니즘은 실측으로 확인되었다. 러너 TERM 실측값만
미확정(추측)이며, 수정안은 이에 독립적이다.

## 4. 근본 원인 판정

- **판정: 복수 원인 (5그룹)**. "10건 = 1원인" 가설은 기각 — R1(2건)/R2(6건)로 상이한 부분집합이
  재현되고, 나머지 4건은 G1/G2/G5로 각각 다른 환경 변수에서 재현된다.
- **tc2 계열(G2)과 tc5/tc4/tc7-TTY 계열(G3/G4)은 서로 다른 원인** — 로케일 경고 vs 스타일 세션
  판정 env. tc2d_layout(G1)은 또 다른 원인(도구 부재), tc7-iso(G5)는 상태 의존.
- 제품 코드 관찰: 제품의 판정 로직(CI/GITHUB_ACTIONS/TERM/NO_COLOR → plain, precheck fail-fast,
  fresh-state transition 메시지, English-only 로케일 무시)은 **모두 의도된 동작**이며 버그 없음.
  **제품 코드 수정 항목: 0건.** 전부 테스트 하니스 수정으로 해소한다.

## 5. 해결 설계

### 5.1 방향 판정: TTY 강제(방향 B) 채택 — skip(방향 A) 채택 안 함

| 항목 | A. CI에서 TTY 의존 단언 skip | **B. pty 강제 + env 고정 (채택)** |
|---|---|---|
| 커버리지 | TTY 카운트다운·배너·컬러 7건이 CI에서 영구 미검증 — 배너/카운트다운 회귀가 CI를 통과 | **유지** (러너에서도 항상 검증) |
| flakiness | 낮으나 skip 사이트가 늘어날수록 조용한 커버리지 손실 축적 | 헬퍼 1곳으로 env 고정 → 결정론적. 잔여 위험: `script`의 OS별 옵션 차이(이미 BSD/macOS 호환이 `script -qec` 계약) |
| 구현 비용 | 낮음 | 낮음 — 헬퍼 1개 + 호출부 치환 |

채택 근거: `script`는 ubuntu-latest와 로컬 Linux·macOS 모두 존재(실측: util-linux 2.39.3), TTY 시뮬레이션
케이스의 실패 원인이 전부 "env 미고정"이라 고정하면 결정론적이 된다(로컬 R1/R2가 반증 가능한 형태).

### 5.2 수정 설계 (테스트 전용)

1. **TTY 헬퍼 통합 + TERM 강제** (`tests/test_tui_i18n.sh:240-254, 283-305, 339-346`):
   기존 `tty_run`(241-243)을 전체 스위트 공용으로 승격하고 8개 script 호출부를 모두 헬퍼 경유로 치환.
   ```bash
   ht_tty() { # $1=script -e 인자 — pty 강제 + CI 스타일 판정 env 고정 (TERM은 러너 의존 제거)
     env -u CI -u GITHUB_ACTIONS -u NO_COLOR TERM="${HERDR_TEST_TTY_TERM:-xterm-256color}" \
       script -qec "$1" /dev/null 2>&1
   }
   ```
   - `-u GITHUB_ACTIONS` 추가가 G3 해소, `TERM=` 강제가 G4 해소.
   - tc5의 입력 파이프형(`( sleep 2; printf ... ) | ht_tty ...`)은 기존 구조 유지, env prefix만 헬퍼로 이동.
2. **로케일 노이즈 정규화** (`118-124, 227-229`): base/ko/fr/list 비교 전에 setlocale 경고 라인 제거.
   ```bash
   strip_locale_noise() { sed -E '/^(bash: )?warning: setlocale:/d'; }
   # KO_ENV_OUT="$(... 2>&1 | strip_locale_noise)"  # BASE/FR/LIST_* 동일 적용
   ```
   - skip이 아니라 **단언 유지**(제품 출력 동일성 계약은 보존, 러너 인프라 노이즈만 제외).
   - ko_KR 미설치 러너임을 감지하면 1회 `NOTICE` 출력(§5.4 규약).
   - tc2_fr은 LANG 단독이라 경고가 없어(로컬 R6 실측) 불변이지만 동일 정규화 적용으로 통일.
3. **tc2d_layout dry-run화** (`165`): 명령에 `--dry-run` 추가.
   근거: 레이아웃 검증은 `bin:848-853`에서 setup 이전 파싱 단계로 수행되고 dry-run 여부와 무관하게
   동일 에러·exit 2 — 로컬 R4로 토큰 출력 확인. precheck(bin:799 게이트) 생략으로 러너 herdr 부재와 무관해짐.
4. **tc7-iso 상태 시드** (`308-312`): 임시 cwd에 `.herdr-team/preset=dev` 시드 후 `--cwd`로 실행.
   근거: R9에서 시드 상태에서 `(dry-run isolation)` 출력 확인. 프레시 체크아웃/로컬 저장소 상태
   양쪽에서 결정론적. (기존에는 **로컬 개발머신이 herdr-team을 실행해본 적 있어야만 통과하는 잠재
   비결정론**이었음 — 이 수정으로 제거.) `--dry-run`이므로 precheck 무관.
5. **skip 규약** (§5.4): 본 수정으로 skip 0이 목표지만, 향후 도구 부재형 skip을 위한 규약 정식화.

### 5.3 제품 코드 수정 필요성 판정

**불필요.** 근거: (1) plain 모드 강제(CI/GITHUB_ACTIONS/TERM/NO_COLOR)는 제품 명세(bin:415 주석)대로
동작 — TTY 시뮬레이션이 러너에서 plain으로 빠진 것은 테스트가 env를 못 고정한 탓. (2) precheck
fail-fast는 herdr 부재 러너에서 올바른 동작이며, tc2d가 그걸 우회하지 않은 것은 테스트 설계 결함.
(3) fresh-state transition 메시지는 dry-run isolation 계약(bin:1637-1642)의 정상 분기. 제품 회귀
가능성은 TB-1~TB-4 GREEN 후 기존 342 PASS가 유지되는 것으로 재확인한다.

### 5.4 skip 규약 (향후용, 본 수정에서는 skip 0)

- skip은 **도구/환경 부재**(`command -v script` 실패 등)에만 허용. 단언 로직 회피용 skip 금지.
- 발생 시: `SKIP: <사유> → <label>` 1행 출력 + 전역 `SKIP_N++`.
- 요약행에 반드시 표기: `RESULT: PASS=n FAIL=n SKIP=n` — FAIL=0이어도 `SKIP>0`이면
  `NOTICE: N assertion(s) skipped (coverage gap): <라벨 목록>`을 결과 직전에 두드려 눈에 띄게 한다.
- CI에서 skip은 실패로 만들지 않되(녹색 유지), NOTICE가 step 로그에 남아 상위에서 검색 가능.
  (커버리지 손실의 조용한 축적 방지 — 코드 리뷰 시 NOTICE 유무 확인)

## 6. 테스트 티어 규율 (Fast Loop 원칙)

- **T1 Fast-Loop**: 편집 루프마다 해당 케이스 블록만 손봤을 때는 `bash tests/test_tui_i18n.sh` 전체를
  실행(로컬 실측 ~수 초~1분, tc5 sleep 포함 — 5초 초과 시 해당 블록만 수동 추출 실행). 변경 파일 =
  테스트 파일 자체이므로 T1 대상 스위트는 본 스위트 단독.
- **T2 Scoped Regression**: 태스크 완료 시 1회 — `bash scripts/testmap.sh` 매핑 스위트
  (`tests/*` → 자기 스위트; bin/herdr-team 미변경이므로 최소 집합:
  `bash tests/test_tui_i18n.sh && bash tests/test_preset.sh`).
- **T3 Full Regression**: push 직전, reviewer 노드 전용(워커 임의 실행 금지) — ci.yml 전체 step.
  고지 형식: `[T2 scoped] <command> → N passed in T s`.

## 7. Task Breakdown (TDD 순서, ht-worker용)

### TB-1 (P0) — TTY 헬퍼 통합 + TERM 강제 + GITHUB_ACTIONS unset  [G3+G4, 7건]
- **재현/RED(이미 확보)**: `GITHUB_ACTIONS=1 bash tests/test_tui_i18n.sh` → tc5 2건 FAIL(로컬 실측),
  `env -u TERM bash tests/test_tui_i18n.sh` → 6건 FAIL(로컬 실측). 테스트 수정 전제이므로 RED는
  이 두 재현 명령이 성공 기준이 된다.
- **구현**: `tests/test_tui_i18n.sh:238-254`의 `tty_run`을 `ht_tty`로 일반화(TERM 강제) →
  244/246/248/250 호출부 치환, `283-305`(284/299 env prefix 교체), `339-346`(340 교체).
- **GREEN 판정**: 위 RED 재현 명령 2개가 모두 `FAIL=0`.
- **T2**: `bash tests/test_tui_i18n.sh && bash tests/test_preset.sh`.

### TB-2 (P0) — 로케일 노이즈 정규화  [G2, 2건]
- **재현/RED**: 로컬에서 ko_KR 존재로 직접 재현 불가(로컬 R7). 검증 절차: (a) CI 관측 사실(2건 FAIL)을
  기준으로, (b) 신규 가드 단언을 tc-2 블록(117-128)에 추가 — `strip_locale_noise`가 setlocale 경고를
  제거하는지 단위 확인: `printf 'bash: warning: setlocale: LC_ALL: cannot change locale (ko_KR.UTF-8)\nhi\n' | strip_locale_noise` → `hi`만 남음. 이 가드는 R5 메커니즘과 대응.
- **구현**: `118-124`(BASE/KO/FR), `227-229`(LIST_BASE/LIST_KO)에 정규화 파이프 적용 + ko_KR 부재 감지 NOTICE.
- **T2**: `bash tests/test_tui_i18n.sh && bash tests/test_tui_i18n.sh`(가드 재실행) — 정규화 후 기존 342 PASS 유지.

### TB-3 (P1) — tc2d_layout dry-run화  [G1, 1건]
- **재현/RED**: `env PATH=/usr/bin:/bin bin/herdr-team test --layout bogus_layout --no-interactive`
  → 에러 토큰 부재(로컬 R3 실측).
- **구현**: `tests/test_tui_i18n.sh:165` 명령에 `--dry-run` 추가(+주석: precheck 생략 의도).
- **GREEN**: `env PATH=/usr/bin:/bin bash -c`로 동일 명령(마지막 `--dry-run` 포함) → 토큰 출력 확인(로컬 R4 실측).
- **T2**: `bash tests/test_tui_i18n.sh && bash tests/test_preset.sh`(§tc2d 주변 회귀).

### TB-4 (P1) — tc7-iso 상태 시드  [G5, 1건]
- **재현/RED**: 프레시 cwd에서 R8 — `(dry-run isolation)` 부재, `(switch detected)` 출력(로컬 실측).
- **구현**: `tests/test_tui_i18n.sh:308-312` — 임시 dir 생성 + `.herdr-team/preset=dev` 시드 +
  `--cwd "$TMPISO"`로 실행(기존 파이프 입력/플래그 유지), `trap rm -rf` 정리. 기존 313행 이후
  ISO_OUT 의존 단언(312-313)은 그대로 통과되도록 출력 동일성 유지(R9에서 isolation 토큰 출력 확인).
- **T2**: `bash tests/test_tui_i18n.sh && bash tests/test_preset.sh`.

### TB-5 (P2) — skip 규약 정식화  [예방, 0건]
- **RED**: `SKIP_N` 미정의 상태에서 SKIP 출력 케이스(tc4/tc5의 `echo SKIP` 분기)가 요약에 반영 안 됨 —
  새 규약에 맞는 가드 단언: script를 stub로 가리켜 SKIP 경로를 강제 실행 → `RESULT: PASS=n FAIL=n SKIP=n`
  + NOTICE 출력 단언.
- **구현**: `tests/test_tui_i18n.sh:11`(카운터), 253/304(SKIP 지점), 380-382(요약/NOTICE/exit 판정).
- **T2**: `bash tests/test_tui_i18n.sh`.

### TB-6 — 최종 회귀 (T3, reviewer 노드 전용)
- CI green 판정: `.github/workflows/ci.yml`의 TUI i18n step 0 FAIL(제품/워크플로 변경 없이 해소).
  필요 시 워크플로 `env: TERM: xterm` 추가는 금지 — 헬퍼가 TERM을 강제하므로 이중 관리(스킵).

## 8. 우선순위 & 최소 수정안

- 최소 수정안 = TB-1~TB-4 (10건 전부 해소, 테스트 파일 1개만 수정, 제품/워크플로 무변경).
- TB-5는 규율 보강(별도 커밋 가능), TB-6은 reviewer 노드.
- 리스크: `script` 미존재 환경에서 TTY 계열이 skip으로 빠짐(기존 SKIP 분기 유지 — 동작 변화 없음);
  `TERM=xterm-256color`를 이해 못 하는 극소 셈 → `HERDR_TEST_TTY_TERM` override 제공.
