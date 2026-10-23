# Spec: 권한 요청 팝업 피로 해소 — baseline 완화·core-dev 번들·watcher 자동 기동

- 상태: draft (ht-planner 산출물, `ht-worker` 구현 대기)
- 상위 명세: `docs/specs/permission-model-optimization-spec.md` (계층 L0~L3 + 번들 + 프로파일 조합, last-match-wins)
- 대상 코드: `templates/permissions/{baseline.json,bundle/,profile/}`, `bin/herdr-team` (`setup_permissions`, `permissions_merge_role`, `permissions_judge`), `bin/herdr-watcher`, `tests/`
- 회신 규약: 경로 + 1줄 요약

---

## 0. 현황 팩트 (조사 근거)

| 사실 | 근거 |
|---|---|
| baseline에 `shell "*"` 전역 ask fallback 존재 | `templates/permissions/baseline.json` L5 `{action:shell, resource:"*", effect:ask}` |
| L2 ask는 이미 위험군 한정(6종): git push / git reset --hard / git clean -fd / rm * / herdr pane close / herdr pane kill | baseline L6-11 |
| L3 policies hard-deny 7종: `sudo`, `curl \| *`, `wget \| *`, `rm -rf`, `rm -fr`, `chmod -R 777`, `git push --force` | baseline L13-21 |
| **V2에서 미매칭 기본값이 ask이므로 `shell "*"` ask 규칙은 결과적으로 중복** | `permissions_judge`는 매칭 없으면 `e="ask"` 반환 (merge 테스트 C3가 여전히 통과함 = 기본값 ask로 재현 확인) |
| worker edit은 광역 deny 후 `src/**`·`tests/**` 협소 allow — 본 repo(pure bash)처럼 코드가 `bin/`·`scripts/`·`tests/`에 있으면 모든 edit이 ask | `profile/dev/worker.json` includes + permissions |
| watcher는 python3 포그라운드 무한 루프, 자동 승인 트리거 = 화면 팝업 시그니처(`enter confirm` + Permission required), 기본 approve_keys=`enter`(Allow once), pidfile·불가침 데몬 기능 없음, `--max-iterations`는 테스트용 | `bin/herdr-watcher` L234-291, L303-312 |
| watcher 자동승인은 **L2 ask 팝업도 승인한다** — `detect_permission_popup`은 팝업 종류를 구분하지 않음 | herdr-watcher L106-129 |
| watcher 자동 기능 중 `clean_stuck_waits`(idle/done 상태인데 대기 중인 `herdr agent wait` 재정리)는 자동승인과 무관한 안정화 기능 | herdr-watcher L216-231 |
| `tests/test_preset.sh` §38은 V1 `permission:` 맵(awk `^permission:`) 기준 단언 — 시딩기(`setup_permissions` L658-672)는 생성물을 V2 `permissions:` YAML 배열로 교체 → 로컬 생성물 2파일×10단언 = **20건 baseline FAIL** | 실행 확인: `RESULT: PASS=441 FAIL=20` (정본 템플릿 2파일은 V1이라 통과, `.opencode/agents/ht-*.md`는 V2라 전부 FAIL) |
| worker 프로파일 보유 프리셋: dev·creator·pkm (biz/mkt/research는 worker 역할 없음) | profile/ 디렉터리 파일 나열 |
| 기존 병합 엔진 테스트 76 PASS / 시딩 테스트 56 PASS (변경 후 회귀 게이트) | 실행 확인 |

---

## 1. R1 — baseline 완화 + core-dev 번들 신설

### 1.1 baseline.json 변경

| 항목 | 채택 |
|---|---|
| `shell "*"` 전역 ask | **삭제**. 근거: V2 미매칭 기본값이 ask라 삭제해도 결과 동일(§0 팩트). 남겨두면 "ask가 선언적"이라는 희미한 이익 대비 1행 룰 유지비. 단, judge 기본값이 ask라는 사실을 baseline `note`에 명시(문서 역할 승계) |
| L2 ask 위험군 6종 | **전량 유지** (이미 위험군만 남아 있음 — `rm *`는 단건 rm도 복구 불가 삭제이므로 축소하지 않음, 각 항목 유지 이유 표) |

유지 이유: `git push*`(원격 영구 반영) / `git reset --hard*`(로컬 변경 소실) / `git clean -fd*`(무시 파일 포함 삭제) / `rm *`(복구 불가) / `herdr pane close*`(팀 문서 손실) / `herdr pane kill*`(프로세스 강제 종료). sudo는 L3 deny라 L2에 없는 것이 정상.

추가 L3 신규 후보 (glob 표현 가능·조사 선행, 채택 시 policies에 추가):

| 후보 | 위험 | 검증 필요 |
|---|---|---|
| `dd*of=/dev/*` (조합에 공백 유무 변형) | 디스크 덮어쓰기 | glob 매칭이 `dd if=... of=/dev/sda` 텍스트에 걸리는지 e2e |
| `mkfs*` | 파일시스템 포맷 | 동일 e2e |
| `* > /dev/*` \| `*> /dev/sd*` 경로 리다이렉트 | 디바이스 파괴 | 리다이렉트 텍스트가 resource 문자열에 포함되는지(opencode 명령 정규화 방식) 확인 |
| `git push --mirror*` / `git push --delete*` | 원격 전체 덮어쓰기/참조 삭제 | glob 우선순위(`git push*` ask보다 나중에 배치해 deny) |
| 백틱/`$()` 커맨드 치환 포함 명령 전체 | 서브쉘 우회 | 리소스 텍스트에 치환이 남는지 사전 조사 필요 — 문자 클래스 glob으로는 정밀 검출 불가, **후보 유지(미채택)** |

**채택안: 4종(dd / mkfs / `>/dev/` 리다이렉트 / git push --mirror·--delete)은 TC-BL-9 e2e 판정 후 policies에 추가, 커맨드 치환은 조사 과제(TB-3)로 분리.** 검증 실패 시 미채택 사유 기록.

### 1.2 신설 bundle/core-dev.json (L1, 일반 개발 쓰기)

```jsonc
{ "name": "core-dev", "layer": "L1",
  "description": "일반 개발 명령 allow — core-read와 중복 재선언 금지",
  "permissions": [
    { "action": "shell", "resource": "mkdir *",  "effect": "allow" },
    { "action": "shell", "resource": "touch *",  "effect": "allow" },
    { "action": "shell", "resource": "sed *",    "effect": "allow" },
    { "action": "shell", "resource": "cp *",     "effect": "allow" },
    { "action": "shell", "resource": "mv *",     "effect": "allow" },
    { "action": "shell", "resource": "git add*", "effect": "allow" },
    { "action": "shell", "resource": "git commit*", "effect": "allow" },
    { "action": "shell", "resource": "git mv*",  "effect": "allow" },
    { "action": "shell", "resource": "git restore --staged*", "effect": "allow" }
  ] }
```

- **`ls`·`cat`·`grep`·`find` 재선언 금지** — core-read가 이미 allow. core-dev는 상기 9종만.
- `git restore --staged*`만 허용(색인 해제는 안전). 워크트리 복원(`git restore <경로>` / `git checkout -- *`)은 변경 소실이므로 git 번들 기존 ask 유지.

### 1.3 last-match-wins 순서 제약 (병합 시 횡단 불변식)

병합 순서(`permissions_merge_role`): `baseline(asks) → bundles(includes 선언 순) → profile(역할 오버라이드)`. 제약:

1. **broad allow 뒤에 narrow deny/ask가 와야 함** — `edit "*" allow → 민감경로 deny`, baseline `git push*` ask는 git 번들 앞단에서 이미 선언되며 core-dev의 allow는 push와 안 겹침.
2. **includes 선언 순서 계약**: `[core-read, core-dev, git, test-build, herdr-read, opencode-api]` — core-dev는 core-read 뒤(읽기→쓰기 순), 도메인 L2 ask 포함 번들(git·herdr-read)은 core-dev 뒤(ask가 allow를 이겨야 하는 항목 없음이지만 순서 고정으로 회귀 방지).
3. L3 policies는 배치 순서 무관 최우선(이미 그렇게 판정됨) — 신규 deny 후보도 policies에만 추가.

---

## 2. R2 — 역할별 재정비

### 2.1 worker (dev·creator·pkm 프로파일)

shell: 기존 includes에 `core-dev` 추가 + src/tests 경로 edit 권한 자율화.

**edit 방식 비교 (채택: 민감 경로 deny 목록)**

| 방식 | 안전성 | 피로 | 유지비 | 실패 모드 | 판정 |
|---|---|---|---|---|---|
| A. 현행: `edit "*": deny` → 협소 allow (src/tests/**) | fail-closed | 높음 — 코드가 bin/scripts/lib에 있는 repo는 매 edit ask | 경로 열거 지옥(프로젝트마다 재설정) | 화이트리스트 누락 → 반복 승인 → 피로 승인(Allow always 난발) 모델 붕괴 | ✗ |
| B. 민감 경로 deny 목록: `edit "*": allow` → 민감 경로 deny (last-match-wins) | fail-open이지만 L3 policies + shell L2 ask가 파괴 방어의 주력. **프로젝트별 경로 재설정 불필요(범용)** | 낮음 | deny 목록 1벌만 유지 | 미지정 민감 파일 편집 가능 — deny 목록으로 봉쇄 | ✅ 채택 |

채택 근거: 피로의 주원인은 edit ask 반복. worker의 파괴성은 edit보다 shell(L2 ask·L3 deny)에서 실제 발생하며 edit은 git으로 복구 가능. **자기 권한 상향(권한 설정 파일 편집)이 최대 리스크이므로 반드시 deny 포함.**

worker 프로파일 신규 edit 블록 (순서 계약: allow 먼저, deny 뒤):

```jsonc
"permissions": [
  { "action": "edit", "resource": "*",              "effect": "allow" },
  { "action": "edit", "resource": ".env*",          "effect": "deny" },
  { "action": "edit", "resource": "**/.env*",       "effect": "deny" },
  { "action": "edit", "resource": "**/*.pem",       "effect": "deny" },
  { "action": "edit", "resource": "**/*.key",       "effect": "deny" },
  { "action": "edit", "resource": "**/id_rsa*",     "effect": "deny" },
  { "action": "edit", "resource": "**/*credential*", "effect": "deny" },
  { "action": "edit", "resource": ".ssh/**",         "effect": "deny" },
  { "action": "edit", "resource": ".git/**",         "effect": "deny" },
  { "action": "edit", "resource": ".opencode/**",    "effect": "deny" },
  { "action": "edit", "resource": ".herdr-team/**",  "effect": "deny" },
  { "action": "shell", "resource": "git push*",      "effect": "ask" }
]
```

- `.opencode/**`·`.herdr-team/**` deny는 **권한 설정 자기 변조 방지**(worker가 자기 frontmatter/jsonc의 deny를 지우는 공격 차단) — 명세상 필수.
- `.env*`는 `.env`·`.env.local`·`.env.production` 전부 커버.

### 2.2 planner·reviewer·orchestrator 경계 (약화 금지)

| 역할 | 변경 | 유지 |
|---|---|---|
| planner | **변경 없음** | `edit * deny` + docs 협소 allow, core-read/git/herdr-read 그대로 |
| reviewer | **변경 없음** | `edit * deny` + 10-temp/tmp만 allow, test-build 실행 가능 유지 |
| orchestrator | **변경 없음** | `edit * deny`, pytest 등 생산 명령 비allow(역할 격리 C4 회귀 유지) |

R2의 피로 완화는 worker edit·core-dev로 충분하며, 3역할의 "수정 권한 분리" 계약(`templates/AGENTS.md` §1)을 해치지 않음.

---

## 3. R3 — herdr-team 실행 시 watcher 자동 백그라운드 기동

### 3.1 방식 비교

| # | 방식 | 피로 해소 | 안전 | 결정 |
|---|---|---|---|---|
| A | 기본 자동 기동(auto-allow on) | ◎ | ✗ — L2 ask(git push 등)를 인지 없이 자동 Allow once → 최소권한 모델을 조용히 무력화 | 기각 |
| B | 기본 자동 기동(`--no-auto-allow`로 모니터링만) | ✗ (승인 개입 없음, stuck-wait 정리만) | ○ | 기각 |
| C | **opt-in `--watcher` 플래그 + auto-allow 명시 경고 + 비차단 백그라운드** | ◎ (사용자가 자동승인을 요청한 것이므로 합의 위) | ○ (L3는 deny라 팝업 자체 없음. L2 자동승인은 플래그=동의) | **✅ 채택 — 안전해 opt-in으로 구현 과제 포함** |
| D | MCP/데몬 통합 등 구조 변경 | ◎ | ○ | 범위 초과 — 미채택(향후) |

### 3.2 채택안 세부 (표)

| 항목 | 채택안 |
|---|---|
| 기동 방식 | `nohup herdr-watcher --prefix "$PREFIX-" --cwd "$CWD" > "$CWD/.herdr-team/watcher.log" 2>&1 &` — ht 종료와 독립 수명(감시 대상은 pane들). spawn은 단일 배경 명령 1행(watcher 경로는 PATH 부재 시 `$SCRIPT_DIR/../bin/herdr-watcher` 폴백) |
| 중복 기동 방지 | pidfile `$CWD/.herdr-team/watcher.pid`: ① pid 존재(`kill -0`) ② `/proc/<pid>/cmdline`에 `herdr-watcher` 포함 → 스킵(log 1행). stale pidfile(PID 재사용 오탐 방지용 ②검사 실패) → 갱신 후 기동 |
| prefix·cwd 일치 | `--prefix "$PREFIX-"`(ht에서 계산한 치환 prefix), `--cwd "$CWD"` — watcher의 자체 auto_prefix 재계산 불일치 방지 |
| dry-run | 실기동 없이 `+ watcher: start --prefix <p> → .herdr-team/watcher.log (pidfile <path>)` 계획 1행 출력 |
| --no-start / --templates-only | 생략 + log 1행 (감시할 agent가 없음/pane 미분할) |
| --no-interactive | 변함 없음 — `--watcher`는 명시 플래그라서 상호작용 불필요 |
| 종료 정책 | watcher는 ht 종료 후에도 유지. 종료 수단: `kill "$(cat .herdr-team/watcher.pid)"` — usage 1줄 문서화. pidfile은 기동 시 갱신. ht는 watcher의 프로세스를 소유 추적하지 않음(고아 허용, 명시 설계) |
| 비차단 원칙 | watcher 기동 실패(nohup 오류·python3 부재 등) → 경고 1행 출력 후 **ht 종료코드 불변** (기동 결과를 rc에 절대 반영하지 않음) |
| 안전 고지 | 기동 성공 log에 "L2 ask 팝업도 Allow once 자동 승인됩니다 — 취소: kill $(cat pid)" 포함 |
| python3 의존 | `command -v python3` 없으면 스킵 + log 1행 (herdr/jq 사전점검 파일 동일 패턴) |

### 3.3 구현 포함 근거

opt-in이므로 자동승인은 사용자 명시 동의 하에 작동하고, L3 hard-deny는 팝업 자체가 발생하지 않아 우회 불가. dry-run·no-start 배제와 비차단 원칙으로 ht 본 동작 회귀 영향 0. → **구현 과제 TB-5로 포함**.

---

## 4. TDD 테스트 케이스 목록

신규 스위트: `tests/test_watcher_start.sh` (herdr-watcher 기동 연동). 기존 스위트 정정/확장: `test_permissions_merge.sh`, `test_permissions_seed.sh`, `test_preset.sh` §38.

### R1 (TC-BL)
1. baseline `note`에 "미매칭 shell = ask(기본값)" 명시, `permissions[0]`가 `shell "*"` ask가 아님(삭제 회귀)
2. `judge dev worker shell 'unknown-cmd-xyz'` → **ask 유지**(기본값 경로 — 기존 C3 그대로 PASS)
3. L2 6종 ask 전량 유지: git push·reset --hard·clean -fd·rm·pane close·pane kill (전 프리셋×역할)
4. L3 7종 deny 전량 유지 (기존 §4 그대로 PASS + 후보 채택 시 신규 종 추가)
5. `judge dev worker shell 'mkdir -p x'`·`touch f`·`sed -i 's/a/b/' f`·`cp a b`·`mv a b` → allow
6. `git add -A`·`git commit -m x`·`git mv a b`·`git restore --staged f` → allow
7. **`git restore note.md`(워크트리 복원) → ask 유지** (복구 불가 변경 소실의 무차별 allow 방지)
8. core-read 중복 선언 없음: `jq -e '[.permissions[].resource] | has("ls *")|not' bundle/core-dev.json` (ls/cat/grep/find 미선언)
9. 신규 L3 후보 채택 시: `dd if=... of=/dev/sda`·`mkfs.ext4 /dev/sdb` → deny + `l3_policy_우선` 오버라이드 불가성 재검증
10. creator/pkm worker도 위 5~6 전부 allow (core-dev 공용)

### R2 (TC-WK)
11. `judge dev worker edit 'src/x.py'`·`'tests/x.sh'`·`'bin/herdr-team'`·`'scripts/p.sh'` → allow
12. `edit '.env'`·`'.env.production'`·`'sub/.env'` → deny
13. `edit '.git/config'`·`'.opencode/agents/pfx-worker.md'`·`'.herdr-team/preset'` → deny (**자기 변조 방지 회귀 고정**)
14. 순서 계약: 병합 결과에서 `edit "*" allow`가 민감경로 deny보다 **먼저** 위치 —— deny가 이긴다는 last-match-wins 단언(재현: `edit .env` 결과가 deny로 통과하면 순서 정합)
15. planner 경계 무약화: `judge dev planner edit 'doc.md'` → deny, `'docs/specs/x.md'` → allow (기존)
16. reviewer 경계: `edit 'src/x'` deny, `'tmp/x'` allow (기존 C2)
17. orchestrator 격리: `pytest` allow 아님 + `edit '*'` deny (기존 C4)
18. git push ask 유지(전 worker, 기존 §6)
19. worker 병합 YAML에서 frontmatter 키 집합 `description mode permissions` 불변 (seed §2 loader 계약 유지)
20. 시딩 후 worker frontmatter에 `core-dev` allow 규칙 존재(`resource: "git add*"`) + 민감 deny 존재

### R3 (TC-WS) — tests/test_watcher_start.sh
21. `--watcher --no-start`(stub PATH) → watcher 프로세스 미기동, log에 생략 1행, ht rc 0
22. `--watcher`(stub PATH, tmp CWD) → pidfile 생성 + 프로세스 가동 + log 기록, ht rc 0
23. 중복 기동 방지: 22 직후 재실행 → pidfile 동일 + 프로세스 정확 1개
24. stale pidfile(죽은 PID 기록) → 정상 기동, pidfile 갱신
25. `--dry-run --watcher` → `+ watcher:` 계획 1행, 프로세스 0
26. `--watcher` + 기동 실패 유발(망가진 watcher 경로) → 경고 1행, **ht rc 0 유지**
27. pidfile이 `.herdr-team/` 안에 생성(.gitignore 보강 영향 연동 확인)
28. `--prefix` 인자에 `$PREFIX-` 형태(ht·같은 치환 결과) 전달 확인 — 기동 log/기록 파일에 전달된 prefix 반영 검증

### V1→V2 정정 (TC-§38) — test_preset.sh §38
29. `perm_key_lines` 재작성: V1 `permission:` 맵과 V2 `permissions:` YAML 배열 **양식 모두**에서 `action/resource/effect` 정규화 3-tuple 집합 추출
30. 생성물(`.opencode/agents/ht-*.md`) 단언을 V2 기준으로 재작성: `shell "*"` ask 존재(`resource: "*"` ask), `edit "*" deny` 존재, `ls *`/`git status*`/`herdr agent list*`/`rg *`/`python* --version*` allow 존재 — **V2는 `task` 규칙이 없으므로 task 단언은 정본 V1 템플릿 전용**
31. ask-first 순서 단언 유지(폴링 쿨다운 전제 아님 — frontmatter 상단 첫 allow 이전에 ask 위치)
32. 두 파일 간 key-set 동일성 유지 (같은 시딩기 산출 → 실측 동일)
33. 정본 템플릿 2파일: 기존 V1 단언 유지(변경 없음 회귀) + 신규 V2 정규화 함수가 V1도 파스하는 것은 29에서 커버
34. 전체 20건 FAIL 소멸: `bash tests/test_preset.sh → RESULT FAIL=0`

---

## 5. 엣지 케이스 표

| # | 상황 | 기대 동작 |
|---|---|---|
| E1 | 권한 대상 CWD에 permission 템플릿이 다른 `--template-dir` 커스텀 | core-dev 부재 로컬 템플릿이면 `permissions_src_dir` 폴백 순서(preset-local > template-dir > 번들) 유지 → 번들 없으면 기존 `bundle 없음` 에러 경로 그대로(커스텀 템플릿 사용자에게 안내) |
| E2 | worker edit `allow "*"`과 orchestrator `deny "*"` 병합 오동작 | 프로파일이 role 단위라 병합 경로 분리 — judge C4로 회귀 고정 |
| E3 | `.env*` deny와 `touch .env.example` (working 파일 상) | deny — 민감 경로 우선. `.example` 예외는 열린 질문 |
| E4 | 사용자가 opencode.jsonc에 `shell "*": allow` 수동 병합 | permissions_merge_project_file의 user-preserve가 그대로 살림 — 이때 L2 ask 방어는 사용자 책임(자기 방어 해제) — seed 문서에 경고 1줄 추가 |
| E5 | watcher pidfile 의 PID가 타 프로세스로 재사용 | cmdline에 `herdr-watcher` 확인 후 기동(②검사), 오탐 방지 |
| E6 | watcher 스폰 시 herdr 세션 종료 | 고아 수명 허용(명시 설계) — 종료 수단은 pidfile kill 문서화 |
| E7 | `--watcher`와 `--no-auto-allow` 조합 | watcher에 `--no-auto-allow` 전파 — 사용자가 승인 안 하고 감시만 가능 |
| E8 | watcher.log 동시 기록(다른 세션에서 watcher 재기동) | append 모드 — 기존 로그 유실 없음 |
| E9 | mkdir/sed/cp/mv allow 후 `sed '-i'`가 임의 파일 수정 | sed는 worker 자율 범위(요구사항 명시) — 민감 파일은 edit deny가 아니라 shell이므로 방어 한계는 문서 경고(best-effort)에 명시 |
| E10 | creator/pkm worker가 vault 경로 외 임의 edit | allow-all deny-list 판정 — 특수 preset의 도메인 edit 체계와 충돌 여부는 사용 후 재검토(열린 질문 4) |

---

## 6. 변경 파일 목록

| 파일 | 변경 |
|---|---|
| `templates/permissions/baseline.json` | `shell "*"` ask 삭제 + note 갱신 + (검증 후) L3 후보 4종 |
| `templates/permissions/bundle/core-dev.json` | **신설** |
| `templates/permissions/profile/{dev,creator,pkm}/worker.json` | core-dev include + edit deny-list 재조직 |
| `bin/herdr-team` | `--watcher` 플래그 + 파싱 + `start_watcher()`(pidfile/비차단) + usage 1줄 |
| `bin/herdr-watcher` | 변경 없음 (기존 옵션 재사용) |
| `tests/test_watcher_start.sh` | **신설** (TC-WS 8건) |
| `tests/test_permissions_merge.sh` | TC-BL/TC-WK 반영 (§2 번들 확장, §5 생산성, 신규 §9 edit 경계) |
| `tests/test_permissions_seed.sh` | worker frontmatter core-dev/deny 규칙 단언 추가 |
| `tests/test_preset.sh` | §38 V1→V2 정정 (20건 소멸) |
| `scripts/testmap.sh` | L37/L42 mapping에 신규/권한 스위트 반영 확인 |

---

## 7. Task Breakdown (ht-worker, TDD — 티어 지시자 확인 필수)

| Task | 내용 | 완료 기준 |
|---|---|---|
| **TB-1** | baseline 편집(`"*"` ask 제거 + note) + core-dev.json 신설 | TC-BL 1~10 PASS. `test_permissions_merge.sh` 전체 PASS (기존 76건 회귀 무약화) |
| **TB-2** | worker 프로파일 3종 재조직(core-dev include, edit deny-list) | TC-WK 11~20 PASS, planner·reviewer·orchestrator 경계 단언(15~17) PASS |
| **TB-3** | L3 신규 후보 e2e 판정(리소스 텍스트 실측) — 채택 종만 policies에 반영, 불채택 종은 미채택 근거 기록 | TC-BL 9 + 미채택 사유 문서 3~5줄(명세 코멘트) |
| **TB-4** | test_preset.sh §38 V1→V2 정정 | 기존 20건 소멸, `test_preset.sh` FAIL=0 |
| **TB-5** | `--watcher` + `start_watcher()`(pidfile·비차단·prefix/cwd 전달) + usage 문서 | TC-WS 21~28 PASS, `test_install.sh`·`test_watcher.sh` 회귀 PASS |
| **TB-6** | testmap 등록/확인 + T2 scoped 회귀(`scripts/testmap.sh`) 고지 | 권한/시딩/프리셋/watcher 4스위트 전부 FAIL=0 |

- 실행 티어: 편집 루프 T1(작업 파일 대응 스위트), 태스크 완료 시 T2(`[T2 scoped] <command> → N passed in T s` 고지). `templates/permissions/*`은 testmap L42가 `test_permissions_seed·merge·preset` 매핑 — 신규 `test_watcher_start.sh` 매핑 등록 필요.
- **기존 스위트 회귀 게이트**: `test_permissions_merge.sh`(76), `test_permissions_seed.sh`(56), `test_preset.sh`(441+20→461), `test_watcher.sh`, `test_install.sh` — 전부 FAIL=0.
- 구현 힌트: worker가 TC-WK 13(`.opencode/agents/*.md edit deny`)을 Red로 먼저 만들고 구현(자기 변조 방지 우선).

---

## 8. 열린 질문 (PM)

1. `.env.example` 등 비밀 아닌 민감 유사 파일 예외 deny 예외 처리할지 (TC-WK 12 통과 기준 현재 deny 전체).
2. L3 후보 중 커맨드 치환(백틱/`$()`) 방어 — 정밀 탐지 가능해지면 policies 추가 여부(조사 과제 TB-3).
3. watcher opt-in 기본값 절충안: `--watcher`는 auto-allow on이지만 "L2 ask"만 필터링해 승인하는 watcher 기능이 herdr 측 팝업 분류로 가능해지면 재검토.
4. creator/pkm worker에도 edit deny-list가 잘 맞는지(2 preset의 도메인 파일 체계 가정) — ~1주 사용 후 번들 갱신 루프(per 상위 명세 §d-3).
