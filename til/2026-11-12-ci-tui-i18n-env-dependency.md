# 2026-11-12 Today I Learned: CI에서만 실패하는 TUI i18n 스위트 — 테스트 하니스의 환경 의존

## 1. 배경 및 문제 상황

`ubuntu-latest` CI에서 `tests/test_tui_i18n.sh` 10건이 실패했으나 로컬(Linux 개발 머신)에서는
`PASS=342 FAIL=0`으로 재현되지 않았다. 원인을 추적한 결과 **제품 코드 버그는 0건**이었고,
10건은 하나의 원인이 아니라 **테스트 하니스가 러너 환경 상태에 의존**한 5개 그룹이었다.
제품 판정 로직(CI/GITHUB_ACTIONS/TERM/NO_COLOR → plain 모드, precheck fail-fast, fresh-state
transition 메시지, English-only)은 모두 의도된 동작이었다.

## 2. 원인 5그룹

| 그룹 | 원인 | 실패 단언 | 하니스 결함 |
|---|---|---|---|
| G1 | 러너 PATH에 `herdr` CLI 없음 → 실모드 호출이 precheck에서 조기 종료 | `tc2d_layout` | 레이아웃 검증이 파싱 단계인데도 precheck를 통과해야 하는 실모드로 실행 |
| G2 | 러너에 `ko_KR.UTF-8` 로케일 없음 → 자식 bash의 setlocale 경고가 캡처 출력에 혼입 | `tc2_ko환경_출력_en과_동일`, `tc2g_ko환경_목록출력_동일` | 비교 대상 출력에 러너 인프라 노이즈를 그대로 포함 |
| G3 | tc5 TTY 케이스의 env prefix에 `-u GITHUB_ACTIONS` 누락 → 러너에서 plain 모드 강제 | `tc5_TTY_카운트다운_표시`, `tc5_BSD_mktemp_카운트다운_표시` | 스타일 판정 env를 케이스마다 손으로 나열 |
| G4 | TTY 시뮬레이션이 `TERM`을 고정하지 않음 → 러너 TERM 미설정/`dumb`에서 컬러 모드 off | `tc4_TTY_색상_활성`, `tc7_TTY_배너_박스`/`tagline`/`step_done` (+G3와 중복 기여) | pty 강제만 하고 TERM 계약은 고정하지 않음 |
| G5 | 단언이 저장소 로컬 아티팩트 `.herdr-team/preset=dev`(gitignore 대상) 상태에 의존 | `tc7_계약_dryrun_isolation` | 프레시 체크아웃에는 상태가 없어 `(switch detected)` 분기로 빠짐 |

## 3. 로컬 재현 명령과 실측 수치

| 실험 | 명령 | 결과 |
|---|---|---|
| R1 (G3) | `GITHUB_ACTIONS=1 bash tests/test_tui_i18n.sh` | `PASS=340 FAIL=2` (tc5 2건) |
| R2 (G4) | `env -u TERM bash tests/test_tui_i18n.sh` | `PASS=336 FAIL=6` (tc5 2건 + tc4_색상 + tc7_TTY 3건) |
| R3 (G1) | `env PATH=/usr/bin:/bin bin/herdr-team test --layout bogus_layout --no-interactive` | `ERROR herdr CLI not found`만 출력 — 레이아웃 에러 토큰 **부재** |
| R4 (G1 해소) | 동일 명령 + `--dry-run` | `error: unknown layout: bogus_layout` 정상 출력(precheck 생략) |
| R5/R6/R7 (G2) | `LC_ALL=xx_YY.UTF-8 bash -c 'echo hi'` / `LANG=xx_YY.UTF-8 bash -c 'echo hi'` / `locale -a` | LC_ALL만 setlocale 경고 발생, LANG 단독은 무경고. 로컬에 `ko_KR.utf8` 존재 → 로컬 미재현 설명 |
| R8/R9 (G5) | 프레시 임시 cwd에서 `--cwd` 실행 / `.herdr-team/preset=dev` 시드 후 실행 | 시드 전 `(switch detected)`(isolation 토큰 부재) → 시드 후 `(dry-run isolation)` 출력 |

수정 후 동일 명령 재실행:

- `GITHUB_ACTIONS=1` → `PASS=343 FAIL=0 SKIP=0`
- `env -u TERM` → `PASS=343 FAIL=0 SKIP=0`
- `env -u TERM GITHUB_ACTIONS=1` → `PASS=343 FAIL=0 SKIP=0`
- `env PATH=/usr/bin:/bin`(herdr 부재 흉내) → `PASS=343 FAIL=0 SKIP=0`
- 기본 실행 → `PASS=343 FAIL=0 SKIP=0` (기존 342 + 정규화 단위 가드 1건)
- `bash tests/test_preset.sh` → `PASS=461 FAIL=0`

## 4. 해결 요약 (테스트 파일 1개만 수정, 제품 코드·워크플로 무변경)

- **`ht_tty` 헬퍼 통합**: `env -u CI -u GITHUB_ACTIONS -u NO_COLOR
  TERM="${HERDR_TEST_TTY_TERM:-xterm-256color}" script -qec ...` — 7개 `script` 호출부를 모두 헬퍼 경유로
  치환(G3 + G4 동시 해소). 케이스별 env 오버라이드는 "가변 env 배정 + 마지막 인자 = 커맨드" 형태로 유지.
- **`strip_locale_noise`**: `sed -E '/^(bash: )?warning: setlocale:/d'` — base/ko/fr/list 비교 5곳에 적용.
  단언 자체는 유지하고 러너 인프라 노이즈만 제거. ko_KR 미설치 감지 시 1회 `NOTICE` 출력.
- **tc2d_layout `--dry-run` 화**: 레이아웃 검증은 파싱 단계에서 dry-run과 무관하게 동일 수행되므로
  precheck(herdr 부재)의 영향을 제거.
- **tc7-iso 상태 시드**: 임시 cwd + `.herdr-team/preset=dev` 시드 + `--cwd` 실행 + `trap` 정리 →
  프레시 체크아웃/개발 머신 양쪽에서 결정론적.
- **SKIP/NOTICE 규약**: `SKIP_N` 카운터 + `skip()` 헬퍼, 요약행 `RESULT: PASS=n FAIL=n SKIP=n`,
  `SKIP>0 && FAIL=0`이면 결과 직전 `NOTICE: N assertion(s) skipped (coverage gap): ...`, exit 판정은 FAIL 기준.

## 5. 재발 방지 규약

1. **CI 실패를 제품 버그로 단정하지 말 것** — 먼저 "로컬에서 재현되는가"를 확인하고, 재현되지 않으면
   러너 환경 변수(도구 설치 여부·로케일·TERM·gitignore된 로컬 상태)를 의심한다.
   변수별 시뮬레이션으로 각 단언의 실패 메커니즘을 개별 실증하면 원인 그룹이 분리된다.
2. **테스트는 스타일 판정·로케일·도구 존재를 명시적으로 고정한다** — pty 케이스는 `CI`/`GITHUB_ACTIONS`/
   `NO_COLOR`를 unset하고 `TERM`을 강제, 로케일 비교는 인프라 경고를 정규화, 외부 도구가 필요한 단언은
   부재 시 조용히 사라지지 않게 처리한다.
3. **skip은 도구/환경 부재에만** — 단언 로직 회피용 skip 금지. 발생하면 `RESULT`의 `SKIP=n`과 `NOTICE`로
   가시화해 커버리지 손실이 조용히 누적되지 않게 한다(CI는 녹색 유지하되 로그에서 검색 가능).
4. **gitignore된 로컬 아티팩트에 의존하는 단언 금지** — 상태가 필요한 케이스는 임시 cwd에 시드해서
   프레시 체크아웃과 개발 머신에서 동일 결과를 내도록 만든다.

## 6. 미검증 항목

- 실제 `ubuntu-latest` 러너의 조합 환경(herdr 부재 + ko_KR 부재 + TERM 미보장 + 프레시 체크아웃)은
  로컬에서 원커맨드로 재현 불가 — 각 메커니즘을 변수별로만 검증했다. 최종 판정은 CI(reviewer T3) 몫.
- 러너의 실제 `TERM` 값은 미확정(추측). 수정안은 `TERM` 강제라 이 불확실성에 독립적이지만,
  `TERM`을 이해하지 못하는 극소 셈을 위해 `HERDR_TEST_TTY_TERM` override만 제공한다.
- macOS(BSD `sed`/bash 3.2) 실기 실행은 하지 않았다. `${!#}`·`${@:1:$#-1}`·`sed -E`·`timeout` 부재 분기는
  문법·조건 수준에서만 확인.
- `script`가 없는 환경에서는 TTY 7건이 `SKIP=2`로 집계된다(가시화되지만 CI 커버리지는 비게 됨 — 명세 허용 범위).
