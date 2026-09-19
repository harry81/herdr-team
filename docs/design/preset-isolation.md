## [기획/설계 명세서] — 프리셋별 문서 격리 (agents/<preset>/)

> Plan mode(읽기 전용)이므로 **파일을 생성/수정하지 않았습니다.** 아래는 Worker가 구현할 명세 전문입니다. 현행 코드 재확인 결과: `bin/herdr-team` 837행, `setup_templates()` L425–591, `setup_opencode_agents()` L593–630, 조기 return L434–441, 평면 출력 L460/L465/L513/L523.

---

### 1. 요구사항 요약 & 목표

**목표**: 프리셋 전환 시 역할 문서를 `agents/<preset>/`로 격리해, 프리셋 간 덮어쓰기/잔존 혼선을 없애고 **무손실 왕복 전환**(dev→mkt→dev에서 dev 커스텀 복원)을 보장한다.

**핵심 결정 요약**
| 결정 | 값 | 근거 |
|---|---|---|
| 역할 문서 경로 | `agents/<preset>/<PREFIX>-<role>.md` | 파일명 관례 유지 → `role_agent()`·테스트 파서 무변경 |
| 프리셋 정본 | `agents/<preset>/AGENTS.md` | 프리셋별 1개, 사용자 편집 대상 |
| 활성 상태 | `.herdr-team/preset` (canonical 이름 1줄) | 도구 네임스페이스 분리, `agents/` 의미 오염 방지 |
| 루트 `AGENTS.md` | **활성 뷰(write-back + activate)** | 전환 시 루트 수정분을 나가는 프리셋 정본으로 스냅샷 후, 들어오는 정본을 루트로 복사 |
| `.opencode/agents/*` | **생성물**(직접 편집 금지) | 전환 시 stale 삭제 + 활성 ROLES만 재생성 |
| 새 placeholder | `{{PRESET}}` 추가 | 템플릿 링크를 `agents/{{PRESET}}/{{PREFIX}}-<role>.md`로 표현(치환 1개 추가, 신규 스키마 없음) |
| `--force` | "**요청 프리셋 폴더만** 템플릿에서 재시딩 + 루트 강제 활성" | 기존 "전체 덮어쓰기" 의미 보존하되 타 프리셋은 불가침 |

**비목표(YAGNI)**: 해시/DB 기반 상태, 프리셋별 디렉토리 구조 스키마, 심볼릭 링크(Windows 금지), 신규 role.

---

### 2. 아키텍처 & 데이터 흐름

#### 2.1 최종 디렉토리 구조 트리

```
<target-project>/
├── AGENTS.md                        # [활성 뷰] 활성 프리셋 정본의 동기화 사본
├── .herdr-team/
│   └── preset                       # [상태] 활성 canonical preset 이름 1줄 (예: mkt)
├── agents/
│   ├── dev/                         # [비활성·보존]
│   │   ├── AGENTS.md                #   dev 정본 (루트 write-back 스냅샷)
│   │   ├── <prefix>-orchestrator.md
│   │   ├── <prefix>-planner.md
│   │   ├── <prefix>-worker.md
│   │   └── <prefix>-reviewer.md
│   ├── mkt/                         # [활성]
│   │   ├── AGENTS.md
│   │   └── <prefix>-{orchestrator,planner,researcher,reviewer}.md
│   ├── research/ …                  # [비활성·보존]
│   ├── biz/ …                       # [비활성·보존]
│   ├── creator/ …                   # [비활성·보존]
│   └── <prefix>-<role>.md           # [레거시 평면] 마이그레이션 원본(herdr-team 자신은 이 구조)
└── .opencode/agents/                # [생성물] 활성 프리셋 ROLES만
    └── <prefix>-<role>.md
```

**우선순위/소유권**
- 정본(canonical): `agents/<ACTIVE>/AGENTS.md` + `agents/<ACTIVE>/<prefix>-<role>.md` — 사용자 편집 가능.
- 활성 뷰: 루트 `AGENTS.md` — `activate` 시 정본에서 복사, 다음 전환 시 정본으로 write-back.
- 생성물: `.opencode/agents/*` — 재생성 대상.
- 레거시 평면 `agents/<prefix>-<role>.md`: **읽기 전용 import 소스**, 불변. 정본과 공존 시 `agents/<preset>/` 우선.

#### 2.2 프리셋 활성화 알고리즘 (setup_templates 재구성)

```text
setup_templates():
  if NO_TEMPLATE: log skip; return
  P        = PRESET (canonical; app→dev alias는 상위 L322-336에서 이미 해소)
  ACTIVE   = active_preset()            # .herdr-team/preset, 없으면 ""
  CANON    = "$CWD/agents/$P"
  LEGACY   = top-level agents/<prefix>-<role>.md (role ∈ known regex, L433 재사용)

  # (1) 정본 시딩 — 누락 파일만 생성 (없으면 템플릿: preset-local > 공용)
  ensure_dir("$CANON")
  for role in ROLES:
    dst=canon/<prefix>-<role>.md
    if missing(dst) or FORCE:
       src = templates/<P>/agents/ROLE-<role>.md  ||  templates/agents/ROLE-<role>.md
       if LEGACY has <prefix>-<role>.md and !FORCE:   # (2) 레거시 import(복사)
          cp LEGACY -> dst           (치환 없음, 원본 보존)
       else: sed {{PREFIX}},{{PRESET}} src -> dst

  # (3) 정본 AGENTS.md
  if missing(canon/AGENTS.md) or FORCE:
     if root AGENTS.md exists and !FORCE: cp root -> canon/AGENTS.md   # 무손실 import
     else: sed templates/<P>/AGENTS.md -> canon/AGENTS.md

  # (4) 루트 활성화 (write-back + activate)
  if exists(root) and ACTIVE != "" and !FORCE:  cp root -> agents/<ACTIVE>/AGENTS.md   # 아웃고잉 스냅샷
  if missing(root) or FORCE or ACTIVE != P:     cp canon/AGENTS.md -> root             # 인커밍 활성화
  # ACTIVE == P && !FORCE → 루트가 곧 정본, 무변경(멱등)

  # (5) 상태 기록 — 반드시 마지막 (실패 시 이전 상태 유지)
  set_active_preset(P)              # dry-run: '+ printf P > .herdr-team/preset'만 출력

setup_opencode_agents():
  known = {orchestrator,planner,worker,researcher,reviewer}
  desired = ROLES ∩ known
  # (6) stale 정리 — 현재 prefix + known role 한정, 그 외 prefix/에이전트 불가침
  for f in .opencode/agents/<prefix>-<role>.md where role ∉ desired: rm -f f
  # (7) 활성 role 생성/동기화
  for role in desired:
     if missing(f) or FORCE or ACTIVE != P:  sed templates[/<P>]/opencode-agents/ROLE-<role>.md -> f
  # 같은 프리셋·비FORCE·기존 파일 → 사용자 편집 보존 (기존 L623 관용 유지)
```

**함수 구성(최소 분리)** — `setup_templates`를 얇은 오케스트레이터로 두고 헬퍼 추가:
| 함수 | 역할 | 위치 |
|---|---|---|
| `preset_state_file()` | `printf '%s/.herdr-team/preset' "$CWD"` | `role_agent()`(L379) 직후 |
| `active_preset()` | 상태 파일 read (없으면 빈값) | 동일 |
| `set_active_preset()` | dry-run 인지 상태 기록 | 동일 |
| `canonical_dir()` | `printf '%s/agents/%s' "$CWD" "$PRESET"` | 동일 |
| `subst_tpl()` | `sed -e "s/{{PREFIX}}/$PREFIX/g" -e "s/{{PRESET}}/$PRESET/g"` | 동일 (중복 sed 통합) |
| `legacy_role_docs()` | 평면 role 문서 탐색 (L433 regex 재사용) | 동일 |
| `sync_root_agents()` | (4) write-back/activate | 신규 |
| `prune_opencode_agents()` | (6) stale 삭제 | setup_opencode_agents 내 |

> L434–441의 **조기 return 제거**가 핵심. 기존 "팀 문서 존재 → 생략" 로직은 전환 sync를 막으므로, "이미 존재하면 누락만 보완 + 루트/opencode sync"로 대체한다.

#### 2.3 하위호환 매트릭스

| 프로젝트 유형 | 같은 프리셋 재실행 | 다른 프리셋 전환 | `--force` |
|---|---|---|---|
| **신규**(루트·agents 없음) | 정본·루트·opencode 생성, state=P | 정본 생성, 루트=신규 정본, opencode prune+gen, state=P2 | 템플릿 재시딩→루트→opencode 재생성 |
| **레거시 평면**(루트+`agents/<p>-<role>.md`, state 없음) | 루트→canon import, 평면→canon 복사, 루트 무변경, state=P | **(요청 P2로 import)** 루트=canon(P2)=원래 루트, 평면 원본 보존, state=P2 | import 생략, 템플릿 재시딩, 평면 원본 보존 |
| **이미 격리**(state 존재) | 루트 write-back→canon, 루트 무변경, opencode 누락분만 | 아웃고잉 write-back → 인커밍 activate → prune+gen, state=P2 | 요청 폴더만 재시딩, 타 프리셋 불가침, 루트 강제 |

- 평면+격리 **공존**: `agents/<preset>/` 우선, 평면은 import 소스로만 사용(파괴 안 함).
- 레거시 래퍼 `bin/herdr-team-setup`: 인자 포워딩 그대로 → 신규 동작 자동 상속(수정 불필요).
- `--no-template`: 격리/동기화 전체 생략, state 미변경(의도적). `--dry-run`: 아래 2.4만 출력.
- herdr-team 저장소 자신: `agents/hts-*.md`(평면)는 불변 유지, `agents/dev/`로 **복사** import → 루트 AGENTS.md 링크(`agents/hts-*.md`)가 계속 유효 → 자기 저장소 무손상.

#### 2.4 dry-run 출력(신규 동작 노출)

```
[herdr-team] preset=mkt active=dev (전환 감지)
+ mkdir -p <cwd>/agents/mkt <cwd>/.herdr-team
+ seed: templates/mkt/agents/ROLE-plan.js… (없음) → templates/agents/ROLE-planner.md → agents/mkt/<p>-planner.md
+ import(legacy): agents/<p>-worker.md → agents/mkt/<p>-worker.md
+ write-back: AGENTS.md → agents/dev/AGENTS.md
+ activate: agents/mkt/AGENTS.md → AGENTS.md
+ prune: rm .opencode/agents/<p>-worker.md (stale: mkt ROLES에 없음)
+ gen: templates/opencode-agents/ROLE-researcher.md → .opencode/agents/<p>-researcher.md
+ printf 'mkt\n' > .herdr-team/preset
```

---

### 3. 파일 단위 변경 명세

| 경로 | 작업 | 내용 |
|---|---|---|
| `bin/herdr-team` | 수정 | 헬퍼 7종 추가(`preset_state_file`/`active_preset`/`set_active_preset`/`canonical_dir`/`subst_tpl`/`legacy_role_docs`/`sync_root_agents`), `setup_templates` L425–591 재작성(조기 return 제거·canon 경로·import·write-back·activate·state), `setup_opencode_agents` L593–630 재작성(prune+gen), 내장 AGENTS 문서 링크 L513 `agents/%s/%s.md`(PRESET 반영), help `--force` 문구, dry-run 출력 확장 |
| `templates/AGENTS.md` | 수정 | `agents/{{PREFIX}}-<role>.md` → `agents/{{PRESET}}/{{PREFIX}}-<role>.md`, `.opencode/agents/...` 주석 유지, 프롬프트 예시 경로 동기화 |
| `templates/dev/AGENTS.md` | 수정 | L42 정본 경로 `agents/{{PRESET}}/...` |
| `templates/biz/AGENTS.md` | 수정 | L44 동일 |
| `templates/mkt/AGENTS.md` | 수정 | L43 동일 |
| `templates/research/AGENTS.md` | 수정 | L43 동일 |
| `templates/creator/AGENTS.md` | 수정 | L43 동일 |
| `templates/opencode-agents/ROLE-orchestrator.md` | 수정 | L19 `agents/{{PRESET}}/{{PREFIX}}-orchestrator.md` |
| `templates/opencode-agents/ROLE-planner.md` | 수정 | L18 동일 |
| `templates/opencode-agents/ROLE-worker.md` | 수정 | L9 동일 |
| `templates/opencode-agents/ROLE-reviewer.md` | 수정 | L10 동일 |
| `templates/opencode-agents/ROLE-researcher.md` | 수정 | L10 동일 |
| `tests/test_preset.sh` | 수정 | §4·17·18 경로 검증을 `agents/<preset>/`·`.herdr-team/preset` 기준으로 갱신, 무손실 왕복/마이그레이션/공존/정리/force 케이스 추가(§8 테스트 전략) |
| `tests/test_windows_launcher.sh` | 수정 | §6에 프리셋 전환 dry-run 시뮬레이션(격리 로그 토큰) 1건 추가, 기존 불변 |
| `README.md` | 수정 | 저장소 레이아웃에 `agents/<preset>/`·`.herdr-team/preset`, `--force` 재정의, 마이그레이션/무손실 전환 절 |
| `README.ko.md` | 수정 | 동일(한국어) |
| `windows/start-team.bat` | 수정(주석만) | L5 usage에 격리 안내, 기능 로직 불변(CRLF 유지) |
| `.gitignore`(선택) | 수정 | `.herdr-team/` 무시 권장(강제 아님) |

**런타임 생성(커밋 대상 아님)**: `agents/<preset>/{AGENTS.md,<prefix>-<role>.md}`, `.herdr-team/preset`.
**삭제 파일 없음** (레거시 평면은 보존).

---

### 4. 작업 분할 (Task Breakdown)

| # | 대상 파일 | 변경 | 완료 기준 / 테스트 케이스명 |
|---|---|---|---|
| T0 | (문서) 본 명세 | 필요 시 `docs/preset-isolation.md` 커밋 | 문서 존재 |
| T1 | `bin/herdr-team` | 상태/경로 헬퍼 7종 | `active_preset_초기빈값`, `set_active_last_write`, `dryrun_state_미기록` |
| T2 | `bin/herdr-team`(setup_templates 1단) | `agents/<preset>/` 시딩 + `{{PRESET}}` 치환 | `iso_seed_agents_preset_dir`, `iso_subst_preset_placeholder`, `iso_no_unsubstituted_placeholder` |
| T3 | `bin/herdr-team`(2·3단) | 레거시 import + 정본 AGENTS import | `migrate_flat_role_docs`, `migrate_root_agents_canonical`, `coexist_preset_dir_wins` |
| T4 | `bin/herdr-team`(4단) | root write-back/activate | `switch_writeback_outgoing`, `switch_activate_incoming`, `same_preset_root_untouched` |
| T5 | `bin/herdr-team`(opencode) | prune stale + gen active | `opencode_prune_stale_role`, `opencode_gen_active_only`, `opencode_other_prefix_untouched` |
| T6 | `bin/herdr-team` | `--force` 재정의 + dry-run 로그 | `force_reseed_requested_only`, `force_preserve_other_presets`, `dryrun_isolation_plan_logged` |
| T7 | `templates/**`(11파일) | `{{PRESET}}` 링크 갱신 | `templates_preset_links`, `templates_no_flat_agent_links` |
| T8 | `README.md`,`README.ko.md`,`windows/start-team.bat` | 문서/주석 | `readme_isolation_tree`, `readme_force_semantics`, `win_bat_crlf_유지` |
| T9 | `tests/test_preset.sh`,`test_windows_launcher.sh` | §8 케이스 추가/수정 | 전 케이스 PASS |
| T10 | 전체 | 회귀 | `test_preset.sh`/`test_install.sh`/`test_windows_launcher.sh` 모두 `FAIL=0` |

**순서**: T1→T2→T3→T4→T5→T6(bin) → T7(templates) → T8(docs) → T9→T10. 각 Task는 Red(테스트 기대값) 먼저.

---

### 5. 테스트 전략 (`tests/test_preset.sh`)

**수정**
- §4·§17·§18: 생성 경로 단언을 `agents/<preset>/<prefix>-<role>.md`로 변경, 루트 평면 미생성 확인.
- §18: opencode `mode: primary`/치환 검증 유지 + `{{PRESET}}` 미치환 없음 추가.

**신규**
| § | 케이스명 | 내용 |
|---|---|---|
| 24 | `iso_roundtrip_lossless` | dev→mkt→dev 왕복: `agents/dev/<p>-worker.md` 커스텀 마커 보존, 루트 복원 |
| 25 | `iso_switch_activate_root` | 전환 시 루트 AGENTS.md == `agents/mkt/AGENTS.md` |
| 26 | `iso_writeback_root_edit` | 루트 편집 후 전환 → `agents/<old>/AGENTS.md`에 반영, 복귀 시 루트 복원 |
| 27 | `migrate_flat_preserves_originals` | 평면 `agents/<p>-*.md` 불변 + `agents/<preset>/`로 복사 |
| 28 | `coexist_priority_preset_dir` | 평면+격리 공존 시 격리 우선 |
| 29 | `opencode_prune_stale` | dev→mkt 전환 후 `.opencode/agents/<p>-worker.md` 부재, researcher 존재 |
| 30 | `opencode_same_preset_preserve` | 같은 프리셋 재실행 시 opencode 편집 보존(비FORCE) |
| 31 | `force_scoped_reseed` | `--preset mkt --force`가 `agents/dev/` 불변, mkt만 재시딩 |
| 32 | `state_written_last` | 상태 파일이 canonical 이름 1줄, 실패 경로에서 미갱신 |
| 33 | `no_template_skips_isolation` | `--no-template` 시 `agents/<preset>/`·state 미생성 |
| 34 | `dryrun_no_writes` | dry-run 후 파일/상태 무변경 + 격리 계획 로그 존재 |
| 35 | `legacy_self_repo` | `agents/hts-*.md` 평면 존재 시 루트 AGENTS.md 링크 유효(무손상) |

---

### 6. 주의사항 & 엣지 케이스

1. **부분 프리셋 폴더**: `agents/mkt/`에 일부 role만 존재 → 누락분만 시딩, 기존 파일 무변경.
2. **템플릿에서 사라진 프리셋**(예: 향후 biz 제거): `preset_dir()` 실패 → L339 검증에서 명시 에러(기존 로직 유지), 기존 `agents/biz/`는 보존.
3. **전환 중 실패/롤백**: 상태 파일을 **마지막**에 기록 → 실패 시 이전 ACTIVE 유지, 재실행 멱등. 트랜잭션 없음(문서화).
4. **커스텀 `--template-dir`**: 정본 시딩 소스만 교체, 상태/경로 규칙 동일. 프리셋별 로컬 오버라이드(`<dir>/<preset>/agents/`) 우선순위 유지.
5. **prefix 다중**: 관리 대상은 현재 sanitized `PREFIX-*`뿐. 타 prefix 파일은 불가침(스테일 방치, 문서화).
6. **빈 디렉토리**: `agents/`만 있고 role 없음 → 누락 시딩. `.opencode/agents` 빈 경우 생성만.
7. **권한 오류**: `mkdir`/`sed` 실패 시 `set -e`로 중단, 상태 미기록. 부분 산출물은 재실행으로 복구.
8. **dry-run**: 쓰기 0, 계획만 출력(2.4). 상태/정본/opencode 전부 미변경.
9. **공존 구조**: `agents/<preset>/` > 평면. 평면은 import 소스로 1회 사용 후 불활성.
10. **심볼릭 링크 입력**: `agents/<preset>`가 심링크여도 **복사/갱신은 따라감**(추가 심링크 생성 안 함). Windows 호환 위해 링크 생성 금지.
11. **CRLF/Windows**: `.bat` CRLF 유지, 파일 내용은 LF 유지(기존 관례). `cp`/`sed`는 바이너리/개행 불변.
12. **상태 파일 손상/공백**: `active_preset()`이 trim, 미지의 값이면 write-back 건너뛰고 경고 후 요청 프리셋으로 활성화.
13. **`--no-start`/`--no-interactive`**: 격리 동작 불변, pane 단계만 영향.
14. **역할 문서가 템플릿에 없음**: `경고: ROLE-<role>.md 없음 → skip`(기존 L621 관용) + 나머지 role 계속.
15. **herdr-team 자기 저장소**: 평면 `agents/hts-*.md` 보존이 필수 — import는 복사이며, 루트 AGENTS.md 링크가 평면을 가리켜도 유효.

---

**열린 질문**
1. 레거시 평면 import 대상을 "요청 프리셋"으로 두는 안(T3) — 과거 프리셋 라벨을 정확히 알 수 없어 요청값으로 귀속. 정확 분류가 필요하면 최초 1회 `--migrate-as <preset>` 같은 명시 옵션이 필요하나 YAGNI로 보류.
2. `.opencode/agents/*`를 "생성물(직접 편집 금지)"로 확정해도 되는지 — 정본은 `agents/<preset>/*`이며 opencode 정의는 템플릿 기반 재생성. 필요 시 정본 → opencode frontmatter 병합 생성으로 확장 가능.

현재까지 파일 변경은 없습니다. 이 명세로 진행하려면 plan mode 해제(또는 `hts-worker` 위임)를 지시해 주세요.
