## [기획/설계 명세서] — 프리셋 라인업 5종 확장/개편

> 본 문서는 **명세 전문**이며, Worker가 `docs/design/preset-lineup-5.md`로 저장소에 커밋한다(Task 0). Planner는 코드를 수정하지 않는다.

---

### 1. 요구사항 요약 & 목표

**목표**: 프리셋을 개발자 전용에서 **사용자 목적별 5종**(dev / research / biz / mkt / creator)으로 확장하고, `bin/herdr-team`의 프리셋 하드코딩을 **디렉토리 동적 열거**로 일반화한다.

**범위**
- 신규 프리셋 3종(research, mkt, creator) 추가 + 기존 biz 재정의.
- 기존 app은 **dev에 흡수(alias 유지)**.
- CLI/TUI/Windows 런처/README/테스트를 5종 기준으로 갱신.
- **신규 역할(role)은 만들지 않는다.** 5종 모두 기존 `orchestrator/planner/worker/researcher/reviewer`의 부분집합으로 구성 → `ROLE-*.md` 신규 파일 0개(문구 일반화만).

**현행 사실(코드 근거)**
- 프리셋 하드코딩: `bin/herdr-team` L162 `KNOWN_PRESETS="dev app biz"`, L195–217 TUI `case`, L262 에러 문자열, L53–54 help, L39–100 `usage()`.
- 역할은 이미 일반화됨: L301 `ROLES` 파싱 → L304 `ROLES=($PRESET_ROLES)` → L390/L449/L546 역할 루프. 즉 **템플릿 디렉토리만 추가하면 파이프라인은 동작**한다.
- 템플릿 해석 우선순위: `preset_dir()` L164(외부 `--template-dir` > 번들), `setup_templates` L383 `$src_base/agents`(프리셋 로컬 role 문서 오버라이드 가능), `setup_opencode_agents` L530 `$preset_base/opencode-agents` 우선.
- Windows 런처도 3종 하드코딩: `windows/start-team.bat` L57–64, `tests/test_windows_launcher.sh` L94–96.

**비목표(YAGNI)**: 5인 이상 팀(우측 컬럼 4+ 분할은 가독성 가이드 위반), 프리셋별 신규 role 타입, preset.conf 스키마 확장.

---

### 2. 아키텍처 & 데이터 흐름

```
CLI/ENV/TUI ──► preset_name ──► alias 해소(app→dev) ──► preset_dir() ──► preset.conf(PRESET_DESC/ROLES/LAYOUT)
                                                                   │
                    ROLES=($PRESET_ROLES) ◄────────────────────────┘
                            │
      ┌─────────────────────┼──────────────────────┐
      ▼                     ▼                      ▼
setup_templates()   setup_opencode_agents()   setup_panes()
(AGENTS.md+          (.opencode/agents/        (ROLES 순서대로
 agents/<p>-<r>.md)   <p>-<r>.md)               분할·라벨·start)
```

**preset 이름 해석 파이프라인 (변경 후)**
1. `--preset` > `HERDR_TEAM_PRESET` > TUI > 기본 `dev`.
2. `is_known_preset(name)` = **discover된 preset** ∪ **alias 테이블**.
3. alias(`app→dev`)면 canonical로 치환하고 stderr에 deprecated 경고.
4. `preset_dir(canonical)`로 템플릿 루트 확정.

**동적 열거 인터페이스(예시, 구현은 Worker)**

```bash
# L162 대체
PRESET_ORDER="dev research biz mkt creator"   # 기본값/TUI 번호 안정용 힌트
PRESET_ROOTS=("$TEMPLATE_DIR" "$SCRIPT_DIR/../templates")

discover_presets() {           # <preset>/preset.conf 를 가진 디렉토리만, 중복 제거
  local root dir name seen=""
  for root in "${PRESET_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    for dir in "$root"/*/; do
      name="$(basename "$dir")"; [[ -f "$dir/preset.conf" ]] || continue
      case " $seen " in *" $name "*) continue ;; esac
      seen="$seen $name"; printf '%s\n' "$name"
    done
  done
}
ordered_presets() {            # PRESET_ORDER 먼저, 그 뒤 미등록 preset 추가
  local n
  for n in $PRESET_ORDER; do is_discovered "$n" && printf '%s\n' "$n"; done
  for n in $(discover_presets); do case " $PRESET_ORDER " in *" $n "*) ;; *) printf '%s\n' "$n";; esac; done
}
alias_target() { case "$1" in app) printf 'dev';; *) printf '%s' "$1";; esac; }
```

- `templates/agents/`, `templates/opencode-agents/`는 `preset.conf`가 없으므로 열거에서 자동 제외된다(별도 필터 불필요).
- `--template-dir`에 사용자 preset만 있어도 번들 preset은 유지된다(병합 열거). 동명이면 `preset_dir`의 우선순위 규칙대로 `--template-dir`이 이긴다.

---

### 3. 프리셋별 상세 명세 (5종)

공통: `LAYOUT="2col"`(좌 PM/Orchestrator, 우측 역할 N개 = 균등 ratio), `PRESET_DESC`는 한 줄(EN + KR), 역할 문서는 번들 공용 `ROLE-*.md` 재사용.

#### 3.1 `dev` — 소프트웨어 개발 & MVP
| 항목 | 값 |
|---|---|
| 목적/타깃 | 기능 출시·MVP 개발팀, 품질 게이트(TDD) 필요 |
| ROLES | `orchestrator planner worker reviewer` |
| 이유 | 코드 작성(worker) + 실행 검증(reviewer)이 상시 필요. 기존 체제 유지 |
| PRESET_DESC | `Software Development (소프트웨어 개발·MVP, 4인 팀, orchestrator/planner/worker/reviewer)` |
| 역할 정의 | orchestrator=파이프라인 중계 / planner=명세+Task Breakdown(**필요 시 UX/Wireframe 명세 포함**) / worker=TDD Red→Green / reviewer=빌드·테스트 직접 실행 후 판정 |

**첫 프롬프트 예**
1. "로그인 API와 화면을 추가해줘" → planner(API/데이터 흐름 명세+Task) → worker(TDD 구현) → reviewer(테스트 실행/APPROVE).
2. "결제 플로우 UX 와이어프레임 설계해줘" → planner(와이어프레임/상태 전이 명세) → worker(프로토타입) → reviewer(접근성/회귀 검증).

#### 3.2 `research` — 심층 조사·지식 탐색
| 항목 | 값 |
|---|---|
| 목적/타깃 | 시장/기술/문헌 조사, 비교 분석, 근거 있는 종합 리포트가 필요한 사용자 |
| ROLES | `orchestrator planner researcher reviewer` |
| 이유 | researcher를 **상시** 투입(조사가 본업). worker는 산출물 코드화가 필요할 때 on-demand |
| PRESET_DESC | `Deep Research & Knowledge Discovery (심층 조사·지식 탐색, orchestrator/planner/researcher/reviewer)` |
| 역할 정의 | planner=조사 설계(평가축·가설·범위) / researcher=출처 기반 수집·비교표·종합문서 / reviewer=출처·재현성·논리 일관성 검증 |

**첫 프롬프트 예**
1. "2026 국내 AI 코딩툴 5종 비교 리포트" → planner(평가축) → researcher(가격/기능/약관 출처 수집) → reviewer(출처·버전 재확인) → 종합 리포트.
2. "이 주제 선행연구 서베이" → planner(검색 범위·키워드) → researcher(논문별 요약표) → reviewer(인용 정확성 검증).

#### 3.3 `biz` — 소상공인/자영업 사업 운영
| 항목 | 값 |
|---|---|
| 목적/타깃 | 행정·정부지원사업, CS 매뉴얼, 운영 자동화가 필요한 비개발 운영자 |
| ROLES | `orchestrator planner researcher reviewer` (기존 유지) |
| 이유 | 조사·문서가 본업. 구현/자동화는 PM 승인 시 worker on-demand. 기존 biz 구조 최소 변경 |
| PRESET_DESC | `Small Business Operations (소상공인 사업 운영, orchestrator/planner/researcher/reviewer)` |
| 역할 정의 | planner=과제 정의·자격요건 체크리스트 / researcher=공고·정책·사례 조사·비교 / reviewer=요건·마감·수치 검증 |

**첫 프롬프트 예**
1. "우리 업종이 받을 수 있는 정부지원사업 찾아 신청 준비" → planner(자격 체크리스트) → researcher(공고 수집·요건 비교) → reviewer(마감/요건 검증).
2. "단골 CS 응대 매뉴얼 만들어줘" → planner(목차/정책) → researcher(사례·약관) → reviewer(표현·법적 리스크) → (필요 시 worker가 문서 자동화).

#### 3.4 `mkt` — 로컬 & SNS 마케팅
| 항목 | 값 |
|---|---|
| 목적/타깃 | 키워드/상권 분석, 홍보 카피, 블로그·SNS 포스팅이 필요한 자영업/1인 마케터 |
| ROLES | `orchestrator planner researcher reviewer` |
| 이유 | 반복 병목이 **분석(키워드·상권·경쟁)** 이고 리스크가 **표현/광고 규정 위반**. researcher를 상시 투입하고, 생산(포스팅/카피)은 worker on-demand로 처리(기존 biz의 research-first 패턴 재사용, 신규 role 0개) |
| PRESET_DESC | `Local & SNS Marketing (로컬·SNS 마케팅, orchestrator/planner/researcher/reviewer)` |
| 역할 정의 | planner=캠페인 전략·콘텐츠 캘린더·카피 브리프 / researcher=키워드·상권·경쟁 분석·소재 수집 / reviewer=근거·표현·광고 컴플라이언스 검증 / worker(on-demand)=카피·포스팅 초안 |

**첫 프롬프트 예**
1. "이 동네 카페 인스타 3주 플랜" → planner(캠페인/캘린더) → researcher(키워드·경쟁계정 분석) → reviewer(표현 검증) → worker(on-demand 포스팅 초안).
2. "블로그 상위노출 키워드 뽑고 글 써줘" → researcher(키워드·검색의도) → planner(구조·CTA) → worker(초안) → reviewer(팩트·금칙어).

#### 3.5 `creator` — 콘텐츠 창작·출판
| 항목 | 값 |
|---|---|
| 목적/타깃 | 전자책/블로그/뉴스레터 등 기획→집필→교정 파이프라인이 필요한 창작자 |
| ROLES | `orchestrator planner worker reviewer` |
| 이유 | **집필은 쓰기 권한이 필요**(유일한 write role = worker). researcher(읽기 전용)는 팩트 소스 수집 시 on-demand. app 흡수로 비게 되는 worker 활용처 확보 |
| PRESET_DESC | `Content Creation & Publishing (콘텐츠 창작·출판, orchestrator/planner/worker/reviewer)` |
| 역할 정의 | planner=기획·목차·톤앤매너·분량 / worker=초안 집필(비코드 산출물) / reviewer=교정·교열·팩트체크 / researcher(on-demand)=출처 수집 |

**첫 프롬프트 예**
1. "전자책 목차 잡고 1장 초안" → planner(목차/톤) → worker(초안) → reviewer(교정·팩트체크).
2. "연재 블로그 3편 교정·팩트체크" → worker(수정 반영) → reviewer(출처 검증/표절 리스크).

#### 3.6 기존 `app` 프리셋 처리 — **dev에 흡수 (alias 유지)**
**결정**: `templates/app/` 삭제. `--preset app` / `HERDR_TEAM_PRESET=app`은 `dev`로 해소하고 deprecation 경고 출력.
**근거**
- app은 dev와 **ROLES/LAYOUT이 완전 동일**하고 AGENTS.md의 강조점(deploy/E2E)만 다르다 → 별도 디렉토리는 중복.
- dev의 planner 명세에 UX/Wireframe, reviewer에 배포/E2E 검증을 이미 포함할 수 있어 기능 손실이 없다.
- 사용자 요구가 정확히 5종이며, alias로 기존 스크립트/문서의 `--preset app`을 깨지 않는다.
- `--list-presets`와 TUI에는 app을 **노출하지 않는다**(canonical 5종만). alias는 조용히 동작.

---

### 4. 파일 단위 변경 명세

**생성**

| 경로 | 내용 |
|---|---|
| `templates/research/preset.conf` | PRESET_DESC/ROLES/LAYOUT (§3.2) |
| `templates/research/AGENTS.md` | pipeline + 역할표 + 첫 프롬프트 예 |
| `templates/mkt/preset.conf` | §3.4 |
| `templates/mkt/AGENTS.md` | §3.4 |
| `templates/creator/preset.conf` | §3.5 |
| `templates/creator/AGENTS.md` | §3.5 |
| `docs/design/preset-lineup-5.md` | 본 명세 전문(Task 0) |

**수정**

| 경로 | 변경 |
|---|---|
| `bin/herdr-team` | L162 동적 열거 대체, L177–194 list/is_known 일반화, L195–217 TUI 동적 메뉴, L116/L262 에러 문자열, L39–100 `usage()` 프리셋 블록 동적화, alias 해소(L257–274), 주석의 `dev app biz` 문구 |
| `templates/dev/preset.conf` | PRESET_DESC 문구 갱신(§3.1) |
| `templates/dev/AGENTS.md` | planner UX/Wireframe, reviewer 배포/E2E 명시 |
| `templates/biz/preset.conf` | PRESET_DESC §3.3 |
| `templates/biz/AGENTS.md` | 행정/CS/운영 자동화 중심으로 재정의, worker on-demand 문구 |
| `templates/agents/ROLE-worker.md` | "TDD"를 코드 작업 한정으로 일반화 + 비코드(문서/콘텐츠) 모드 절 추가 |
| `templates/agents/ROLE-reviewer.md` | 산출물 유형별 실행 검증(코드=빌드/테스트, 문서=교정·팩트체크, 조사=출처/재현성) |
| `templates/opencode-agents/ROLE-worker.md` | "## 구현 방식" 일반화(코드=TDD, 문서=초안→피드백) |
| `templates/opencode-agents/ROLE-reviewer.md` | 검증 대상 일반화(권한 `edit: deny` 유지) |
| `README.md` | Preset Summary 표 5종, "Why" 3→5, TUI 스니펫, repo tree, `--preset` CLI 표, How-it-works(2. Preset, 3. Templates) |
| `README.ko.md` | 위와 동일(한국어) |
| `windows/start-team.bat` | L5/L7 usage·env 문자열, L57–64 메뉴 5종(`choice /c 12345`), errorlevel 매핑(5→creator,4→mkt,3→biz,2→research) |
| `tests/test_preset.sh` | §8 테스트 전략 참조 |
| `tests/test_windows_launcher.sh` | L93–96 English label 5종 + `Select [1-5` |

**삭제**

| 경로 | 사유 |
|---|---|
| `templates/app/preset.conf`, `templates/app/AGENTS.md` (디렉토리 포함) | dev 흡수(§3.6) |

> 변경 없음: `bin/herdr-team-setup`(포워딩 래퍼), `scripts/build-zip.sh`(디렉토리 전체 포함), `templates/AGENTS.md`, `templates/agents/ROLE-{orchestrator,planner,researcher}.md`, `templates/opencode-agents/ROLE-{orchestrator,planner,researcher}.md`.

---

### 5. `bin/herdr-team` 하드코딩 일반화 — 구체 방안

| 위치 | 현행 | 변경 |
|---|---|---|
| L162 | `KNOWN_PRESETS="dev app biz"` | `PRESET_ORDER` + `discover_presets()` + `ordered_presets()` + `is_discovered()` + alias 테이블 |
| L177–189 `list_presets()` | `for name in $KNOWN_PRESETS` | `for name in $(ordered_presets)` (동명 중복 자동 제거) |
| L190–194 `is_known_preset()` | 목록 비교만 | `is_discovered(name) \|\| is_alias(name)` |
| L195–217 `choose_preset_tui()` | `case "$ans" in 1\|dev 2\|app 3\|biz` | `names=($(ordered_presets))`, 숫자→`names[n-1]`, 이름→`is_known_preset`, 기본=`names[0]`, 프롬프트 `Select [1-N/…]` |
| L257–274 preset 해소 | alias 없음, TUI 경로는 정규화 없음 | 두 경로 모두 `PRESET="$(alias_target "$PRESET")"` + `[[ 원본 != canonical ]] && stderr 경고` |
| L116 | `--preset에 값이 필요합니다 (dev\|app\|biz)` | `(… 목록: --list-presets)` |
| L262 | `사용 가능: dev, app, biz` | `사용 가능: $(ordered_presets \| tr '\n' ' ')` |
| L39–100 `usage()` | 단일 quoted heredoc에 3종 정적 | heredoc을 2개로 분리하고 사이에 `print_preset_usage()`(= `ordered_presets` 루프 + `preset_desc`) 호출 |

---

### 6. 하위 호환성

- `--preset dev|biz`: 동작·ROLES 변화 없음(문구만 갱신). `biz`는 researcher 체제 유지.
- `--preset app` / `HERDR_TEAM_PRESET=app` / TUI `app` 입력: **exit 0**, `preset=dev`로 실행 + deprecation 경고. 기존 자동화 스크립트 무중단.
- `herdr-team-setup`(레거시 래퍼): `bin/herdr-team`으로 인자 전달 구조 그대로 → 모든 신규/alias 동작 자동 상속. 래퍼 수정 불필요.
- `--list-presets`/TUI에서 app 미노출(의도적). README의 app 예시는 dev로 교체하되 "app→dev alias" 한 줄 명시.
- 커스텀 `--template-dir`: 기존 `preset_dir` 우선순위 유지. 사용자 디렉토리의 `app/`이 있어도 alias가 우선(예약어로 문서화).
- `NUMERALS=(② ③ ④ ⑤ ⑥)`은 5역할까지 지원 → 신규 4역할 모두 안전.

---

### 7. 작업 분할 (Task Breakdown) — Worker TDD 순서

| # | Task | 완료 기준 (DoD) | TDD 대상(테스트 케이스명) |
|---|---|---|---|
| T0 | 본 명세 커밋 | `docs/design/preset-lineup-5.md` 존재, 저장소 규칙 준수 | (문서) `test_preset.sh` 무관 |
| T1 | preset 동적 발견 | `--list-presets`가 5종을 안정 순서로 출력; 임의 `preset.conf` 디렉토리 추가 시 자동 노출 | `list_presets_5종_나열`, `list_presets_커스텀preset_자동발견`, `list_presets_순서_dev우선` |
| T2 | app 흡수 + alias | `--preset app` exit 0, `preset=dev` + deprecation 경고, `templates/app` 부재 | `preset_app_alias_dev_실행`, `preset_app_deprecation_경고`, `templates_app_삭제됨`, `list_presets_app_미노출` |
| T3 | TUI 동적 메뉴 | 숫자 1..N·이름 입력·EOF 기본값 모두 동작, 프롬프트가 `Select [1-5/…]` | `tui_5선택_creator`, `tui_이름_mkt`, `tui_EOF_dev기본`, `tui_app입력_dev경고` |
| T4 | research 프리셋 | 파일 2종 존재, dry-run에 `test-researcher` 있고 `test-worker` 없음 | `templates_research_존재`, `dryrun_research_researcher`, `dryrun_research_worker없음` |
| T5 | mkt 프리셋 | 파일 2종 존재, dry-run 파이프라인 정상 | `templates_mkt_존재`, `dryrun_mkt_researcher` |
| T6 | creator 프리셋 | 파일 2종 존재, dry-run에 `test-worker` 있고 `test-researcher` 없음 | `templates_creator_존재`, `dryrun_creator_worker`, `dryrun_creator_researcher없음` |
| T7 | dev/biz 문서 + role 문구 일반화 | dev AGENTS에 UX/Wireframe·배포/E2E 문구; worker/reviewer 문서에 비코드 모드 존재; `{{PREFIX}}` 미치환 없음 | `dev_agents_ux_wireframe`, `biz_desc_갱신`, `role_worker_비코드모드`, `role_reviewer_유형별검증`, `opencode_agent_placeholder_없음` |
| T8 | README 2종 | 표에 5종, TUI 스니펫 5종, CLI 표 `dev\|research\|biz\|mkt\|creator`, tree 갱신 | `readme_preset표_5종`, `readme_ko_preset표_5종`, `readme_tui_1-5` |
| T9 | Windows 런처 | 메뉴 5종·`choice /c 12345`·errorlevel 매핑, CRLF 유지 | `win_core_English_label_5종`, `win_core_select_1-5`, `win_core_errorlevel_creator` |
| T10 | 전체 회귀 | `test_preset.sh`, `test_install.sh`, `test_windows_launcher.sh` 전부 PASS | `RESULT: FAIL=0` ×3 |

> 순서 규칙: T1→T2→T3(bin) 후 T4–T6(templates), T7–T9(문서/런처), T10(회귀). 각 Task는 Red 테스트를 먼저 추가/수정한 뒤 Green.

---

### 8. 테스트 전략 (`tests/test_preset.sh`)

| § | 변경/추가 | 케이스 |
|---|---|---|
| §2 | 수정 | `--list-presets`에 dev/research/biz/mkt/creator 포함, **app 미포함** |
| §3 | 수정 | `for p in dev research biz mkt creator`; `research/mkt`에 researcher, `creator`에 worker 토큰 확인 |
| §5 | 수정(교체) | app dry-run → alias 테스트: exit 0, `preset=dev`, deprecation 문구, `templates/app` 부재 |
| §7 | 수정 | 미지원 preset 에러 메시지에 5종 목록 표시 |
| §9 | 수정 | `2`→research, 신규 `5`→creator, `mkt`(이름)→mkt, EOF→dev |
| §11 | 수정 | English label: `Deep Research`/`Local & SNS`/`Content Creation`; TUI `Select [1-5/dev/research/biz/mkt/creator]` |
| §15 | 수정 | `printf 'app\n3\n'` → alias 경고 + `preset=dev`(또는 `research\n3\n`으로 교체) |
| §17 | 추가 | creator dry-run에 `-- --agent test-worker` 존재, researcher agent 부재 |
| §18 | 추가 | `templates/opencode-agents/ROLE-{orchestrator,planner,worker,researcher,reviewer}.md` 5종 존재(기존), creator worker agent 생성 |
| 신규 §20 | 추가 | **동적 열거**: temp `--template-dir`에 `zzz/preset.conf` 생성 → `--list-presets`에 zzz, `--preset zzz --dry-run` exit 0 |
| 신규 §21 | 추가 | `--help`에 5종 preset 이름 모두 노출 |

**(참고) `test_windows_launcher.sh`**: §7 label 5종 + `Select [1-5`, §6 시뮬레이션에 `--preset mkt`/`creator` 1건 추가.
**(참고) `test_install.sh`**: 변경 불필요(설치/래퍼/zip 가드레일은 프리셋 비의존).

---

### 9. 주의사항 & 엣지 케이스

1. **PRESET_DESC 파싱**: `grep -E '^PRESET_DESC='` 단일 행 전제 → EN+KR 한 줄 유지, `#` 주석 줄과 분리.
2. **TUI 번호/기본값 안정성**: `discover_presets`는 정렬하지 않고 `PRESET_ORDER`를 먼저 출력 → dev=1 기본값 보존. 미등록 preset은 뒤에 append.
3. **alias 그림자**: 사용자 `--template-dir`에 실제 `app/`이 있어도 alias가 우선 → 문서화 필요(엣지).
4. **빈 discovery**: templates 부재/권한 오류 시 `KNOWN_PRESETS`가 비면 메뉴·검증이 붕괴 → `dev` 폴백 + 명시적 에러.
5. **Windows `choice /c`**: 1–5 매핑에서 errorlevel은 **높은 값 우선** 순서로 비교(5→4→3→2).
6. **creator worker 의미 충돌**: 공용 ROLE-worker의 "TDD/단위 테스트" 문구가 창작 프리셋에서 오해를 유발 → T7에서 비코드 모드 절 필수. opencode `ROLE-worker`의 write 권한은 유지(집필 필요).
7. **reviewer 권한 불변**: `edit: deny` 유지(교정도 "판정·제안"이지 직접 수정 아님). 팩트체크는 researcher on-demand.
8. **테스트 격리**: §18 실제 생성 테스트는 `mkt`/`creator` 추가 시 임시 CWD를 프리셋별로 분리(기존 `TMPCWD2` 패턴).
9. **README 정합성**: `README.md` L111/L117 등 role 목록 주석, tree의 `templates/app` 제거, `app` alias 문구 1줄 추가.
10. **Dry-run 계획 문자열**: ROLES 순서만 바뀌면 자동 반영되므로 mkt/research의 우측 pane 순서(planner→researcher→reviewer)가 의도대로인지 T4–T6에서 스냅샷 확인.

---

### 10. 열린 질문

1. **mkt 역할 확정**: 현재 안은 research-first(planner/researcher/reviewer + worker on-demand). "포스팅 생산량"이 많으면 `worker`를 상시로 올린 `orchestrator planner worker reviewer`(+researcher on-demand)가 나을 수 있음 → PM 판단 필요.
2. **creator reviewer 전문화**: 교정/교열 강도를 위해 `templates/creator/agents/ROLE-reviewer.md` 로컬 오버라이드를 둘지(현재는 공용 문구 일반화로 대체).
3. **app 완전 제거 시점**: alias 경고를 1개 릴리스 유지 후 제거할지, 영구 유지할지.
4. **docs/ vs til/**: 본 명세를 `docs/design/`에 둘지, 기존 관례대로 `til/`에 둘지(`til/`은 이론 기록, 설계 명세와 성격이 다름 — `docs/design/` 권장).

---

### 산출물 요약

- **프리셋 5종**: dev(4인 TDD, UX/Wireframe 포함) / research(조사) / biz(운영) / mkt(마케팅) / creator(창작). 전부 기존 5개 role의 부분집합 → 신규 role 문서 0.
- **app = dev 흡수 + `app` alias(경고)**, `templates/app/` 삭제.
- **동적 열거**: `KNOWN_PRESETS` 상수 → `discover_presets()`/`ordered_presets()`/alias 테이블, TUI·검증·usage 일반화.
- **생성 7 / 수정 14 / 삭제 1(디렉토리)**.
- **T0–T10** TDD 태스크 및 `test_preset.sh` §2·3·5·7·9·11·15·17·18 수정 + §20·21 신규, Windows 테스트 동반 갱신.
