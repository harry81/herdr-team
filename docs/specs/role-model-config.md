# 역할별 모델 구성 — planner = `opencode-go/glm-5.3-flash`, 나머지 역할 무지정

- **상태**: 제안(Draft) — 구현 전
- **대상 버전**: opencode `v2.0.32` (`/api` HttpApi v2 표면), herdr CLI, herdr-team `bin/herdr-team` (bash)
- **범위**: `herdr-team` 이 `kind=opencode` 로 역할 pane 을 기동할 때 **역할별 모델을 결정적으로 지정**한다.
  planner 역할만 `opencode-go/glm-5.3-flash`, 나머지 역할은 모델을 **지정하지 않아** 프로젝트 기본 모델을 그대로 쓴다.
- **비범위**: agent md frontmatter 개편, 프리셋/역할 목록 변경, 권한·워처 정책, 세션 누적 정책, opencode 자체 패치, `kind != opencode` 경로.

---

## 1. 요구사항 요약 & 목표

| # | 요구사항 | 수용 기준 (DoD) |
|---|---|---|
| R1 | planner 역할 pane 이 `opencode-go/glm-5.3-flash` 로 동작 | herdr-team 이 만든 planner 세션의 `model` 이 `{providerID:"opencode-go", id:"glm-5.3-flash"}` 이고, **실제 턴 응답의 모델도 동일** |
| R2 | 나머지 역할은 모델 무지정 | 세션 생성 payload 에 `model` 키가 **없음**. 유효 모델은 프로젝트 기본값 |
| R3 | 결정적·무키 주입 | 세션 생성 payload 로만 지정. `send-keys`/`shift+tab` 미사용. `-- --agent` 미사용 불변식 유지 |
| R4 | 기존 계약 보존 | `--dry-run` 계획 출력, `--no-start`, kind 게이팅, `tests/*` 기존 어서션 전부 유지 |
| R5 | 사용자 편집 보존 | 템플릿·생성물(`.opencode/agents/*.md`, `agents/**`, `AGENTS.md`) **무변경** → FORCE 재시딩·사용자 편집 리스크 0 |
| R6 | 실패는 조용히 넘어가지 않음 | 세션 생성/파싱 실패 시 기존 fail-fast(비정상 종료 + 원인 메시지) 유지 |
| R7 | 전파 | 모든 prefix·모든 preset(kind=opencode)에 스크립트 한 곳 수정으로 적용 |

### 결론 (한 줄)

> **모델은 agent md frontmatter 가 아니라 `bin/herdr-team` 의 세션 생성 payload(`opencode api post /api/session` 의 `model`)에 지정한다.**
> frontmatter `model` 은 opencode v2.0.32 실측에서 **세션에 반영되지 않는다**(§2 E7~E9). 역할별 모델 테이블(`role_model`)은 `bin/herdr-team` 한 곳에 두고,
> 지정이 없는 역할은 키 자체를 생략해 기본 모델을 그대로 상속한다.

---

## 2. 검증된 사실 (Evidence) — 모두 이 저장소/현재 머신에서 실측

| # | 메커니즘 | 확인 방법 | 관측 결과 | 판정 |
|---|---|---|---|---|
| E1 | 두 모델 모두 실재·활성 | provider=`opencode-go` 모델 카탈로그 조회 | `opencode-go/glm-5.3-flash [active]`, `opencode-go/deepseek-v4.1-flash [active]` | **확정** |
| E2 | `POST /api/session` body 에 `model` 존재 | 실행 중 서버 `/openapi.json` (`opencode api get /openapi.json`) | body props: `id,parentID,title,agent,model(Model.Ref),location,metadata,permissions` | **확정** (기존 문서 `docs/specs/opencode-agent-assignment.md` 의 payload 목록에 `model` 누락 → OQ-7) |
| E3 | `Model.Ref` 형태 | 동 openapi `components.schemas` | `{id, providerID, variant?}` — `required:[id,providerID]`, `additionalProperties:false` | 확정 |
| E4 | 세션 생성 시 모델이 **저장**됨 | `POST /api/session -d '{"agent":...,"model":{"id":"glm-5.3-flash","providerID":"opencode-go"}}'` → `GET /api/session/{id}` | `session.model = {id:"glm-5.3-flash",providerID:"opencode-go",variant:"default"}` | **확정** |
| E5 | 그 모델로 **실제 턴이 돎** | E4 세션에 `POST /api/session/{id}/prompt` 후 `GET /api/session/{id}/message` | assistant 메시지 `.model = {id:"glm-5.3-flash",providerID:"opencode-go"}` (응답 정상) | **확정 (핵심)** |
| E6 | 모델 미지정 시 기본값 상속 | `model` 없이 세션 생성 후 턴 실행 | `session.model=null` → 턴은 해당 location 기본 모델 사용 | 확정 |
| E7 | **frontmatter `model` 은 세션 모델에 반영되지 않음** | 신규 location 에 `.opencode/agents/probe-x.md`(`model: opencode-go/glm-5.3-flash`, 본문은 "PINEAPPLE 만 답하라") 두고 `POST /api/session {agent:"probe-x"}` → prompt | 응답 텍스트 = `PINEAPPLE`(= **파일 로딩 확인**) 인데 assistant `.model = {id:"nemotron-3.5-super-vl-free",providerID:"opencode"}` (= location 기본값). `session.model` 은 계속 `null` | **확정 (기각 근거)** |
| E8 | 같은 실험 3회 반복 | E7 + 별도 location 2곳(`~/.cache/*`, `/tmp/opencode/*`) | 모두 모델은 location 기본값. `glm-5.3-flash` 로 실행된 케이스 0건 | 확정 |
| E9 | v2 문서의 명시 | `/v2/docs/agents` | *"A session stores its selected model separately. Selecting a primary agent by ID does not change that model."* / `model` 은 agent 의 "preference" | 확정 (E7·E8 과 일치) |
| E10 | project agent md 는 location 별로 **로딩되고 frontmatter 가 유효** | `permission.bash:{"*":deny}` 를 준 md 에게 bash 실행 요청 | 도구 카탈로그에 shell/bash **부재**(대조군 build 는 shell 실행 성공) | 확정 → E7 의 "파일 미로딩" 교란 배제 |
| E11 | 사후 모델 스위치 API | `POST /api/session/{sid}/model -d '{"model":{"id":"glm-5.3-flash","providerID":"opencode-go"}}'` → `GET /api/session/{sid}` | zero-body 응답 후 `session.model` 이 전환됨 | 확정 (단, 실행 중 TUI 반영은 미검증 → OQ-1) |
| E12 | 이 저장소 라이브 팀 baseline | `herdr agent get <agent>` → `agent_session.value` → `opencode api get /api/session/<sid>` | `ht-planner` = `{deepseek-v4.1-flash, opencode-go}`, `ht-orchestrator` = 동일, `ht-worker`/`ht-reviewer` = `null`(→기본값) | 확정 (before 상태) |
| E13 | 세션 생성 경로가 이미 코드에 존재 | `bin/herdr-team` `opencode_session_for()` (L541–563) | `{agent,title,location}` payload + `herdr agent start ... -- --session <sid>` | 확정 (수정 지점) |
| E14 | dry-run 계약 현재 출력 | `./bin/herdr-team ht --preset dev --dry-run --no-interactive` | `+ SID_PLANNER=$(opencode api post /api/session -d "$(jq -nc --arg a ht-planner --arg d <CWD> '{agent:$a,title:$a,location:{directory:$d}}')" | jq -r .data.id)` | 확정 (확장 대상) |
| E15 | 기존 테스트 어서션 | `tests/test_agent_session.sh` c~f, `tests/test_preset.sh` §17 | `-- --agent` 미사용 / `SID_PLANNER` / `-- --session` / kind 게이팅 — 현행 유지 필요 | 확정 (충돌 없음) |

> 추측(미검증)은 §10 에만 표기했다. §2 의 표는 전부 실측이다.
> 실측에 사용한 probe 세션/디렉터리는 모두 삭제했고, 워킹트리는 변경 전과 동일하다(`git status`: 기존 미커밋 4건만).

---

## 3. 결정: 세션 생성 경로 vs agent frontmatter

| 축 | S: 세션 생성 payload `model` (채택) | F: agent md frontmatter `model` (기각) |
|---|---|---|
| 이 버전에서 실제로 먹히는가 | **예** (E4·E5 — 턴 응답 모델까지 일치) | **아니오** (E7·E8·E9 — 설정된 것처럼 보이지만 턴은 기본 모델) |
| 역할별 분리 | 예 (payload 는 pane/역할 단위) | 이론상 예, 실측 아니오 |
| 수정 지점 | `bin/herdr-team` 1곳 (`role_model` + payload) | `templates/opencode-agents/ROLE-planner.md` 1줄 |
| 전파 | 스크립트 설치/업데이트만으로 전 prefix·preset 적용 | 템플릿 전파는 되지만 **동작하지 않음** |
| 기존 생성물 | 무변경 (FORCE 재시딩·사용자 편집 리스크 0) | 이미 생성된 `.opencode/agents/ht-planner.md` 는 재실행으로 갱신되지 않아 **수동 갱신/드리프트** 발생 |
| 검증 | payload 문자열 + 턴 모델까지 자동 검증 가능(hermetic) | 무효과라 검증 불가 (거짓 통과 위험) |
| 실패 모드 | 없음(현재 구현) | **조용한 오답**: "설정했다"고 믿지만 기본 모델로 동작 |

**채택: S.** F 는 "설정은 있는데 동작하지 않는" 최악의 형태(E9 조용한 폴백과 동급)라 채택하지 않는다.
**재검토 트리거**: opencode 가 primary agent 의 `model` 을 세션 모델로 승격하는 동작을 도입하거나(E9 문구 변경), herdr-team 이 세션 사전생성 경로를 쓰지 않게 되는 버전업 시 F 를 병기할 수 있다.

> 참고: `templates/opencode-agents/ROLE-*.md` 에 `model:` 을 **문서 목적만으로** 추가하지 않는다(무효 + 오해 유발).

---

## 4. 아키텍처 / 데이터 흐름 (변경 후)

```
herdr-team ht --preset dev (kind=opencode, layout=2col)
  │
  ├─ (1) setup_templates         ← 무변경 (역할 문서/프리셋 시딩)
  ├─ (2) setup_opencode_agents   ← 무변경 (.opencode/agents/<prefix>-<role>.md, prune)
  ├─ (3) pane split × N          ← 무변경
  └─ (4) 역할 루프 (무변경 구조, payload 만 확장)
         │   m="$(role_model "<role>")"          ← 신규: 역할별 모델 테이블
         │   payload = {agent,title,location} (+ {model:{providerID,id}} if m != "")
         │   sid = opencode api post /api/session -d "$payload" | jq -r .data.id
         └─ herdr agent start <prefix>-<role> --kind opencode --pane <P> -- --session "$sid"

  결과: planner 세션 model = opencode-go/glm-5.3-flash
        worker/reviewer/orchestrator 세션 model = (키 없음) → 프로젝트 기본 모델
        권한/역할 강제는 기존 agent md 그대로 (변경 없음)
```

---

## 5. 대상 파일과 변경 요지

| 파일 | 변경 | 요지 |
|---|---|---|
| `bin/herdr-team` | **수정** | (a) `role_model(role)` 신설(역할→"provider/model", 미지정은 빈 문자열), (b) `opencode_session_for()` 페이로드에 모델 조건부 추가, (c) 같은 함수의 dry-run 계획 라인에 모델 반영 |
| `tests/test_agent_session.sh` | **수정** | 케이스 g/h/i 추가 (payload·dry-run·비플래너 무지정) |
| `README.md`, `README.ko.md` | **수정** | "Team model / 팀 모델" 절에 역할별 모델 1–2줄 (§11) |
| `templates/**`, `agents/**`, `AGENTS.md`, `.opencode/**` | **무변경** | 역할 문서·프리셋·생성물은 손대지 않는다 (R5) |

### 5.1 인터페이스 예시 (구현 아님 — 계약)

```sh
# (1) 역할별 모델 테이블: 값이 비면 opencode 기본 모델을 그대로 쓴다(무지정).
# 근거: docs/specs/role-model-config.md (frontmatter model 은 v2.0.32 에서 세션에 반영되지 않음)
# shortcut: "#variant" 접미사 미지원, 필요해지면 split("#") 확장
role_model() {
  case "$1" in
    planner) printf 'opencode-go/glm-5.3-flash' ;;
    *) printf '' ;;
  esac
}

# (2) opencode_session_for(): 역할 접두 제거는 기존 관례 재사용
opencode_session_for() {
  local agent="$1" var role m mp payload out sid
  role="${agent#"$PREFIX"-}"
  var="SID_$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')"
  m="$(role_model "$role")"
  mp=""                                   # dry-run 표시용 접미
  [[ -n "$m" ]] && mp=",model:{providerID:\"${m%%/*}\",id:\"${m#*/}\"}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ %s=$(opencode api post /api/session -d "$(jq -nc --arg a %s --arg d %q %s)" | jq -r .data.id)\n' \
      "$var" "$agent" "$CWD" "'{agent:\$a,title:\$a${mp},location:{directory:\$d}}'"
    return 0
  fi
  if ! payload="$(jq -nc --arg a "$agent" --arg d "$CWD" --arg m "$m" \
      '{agent:$a,title:$a,location:{directory:$d}} + (if $m=="" then {} else {model:($m|split("/")|{providerID:.[0],id:.[1]})} end)')"; then
    ...  # 기존 실패 처리 유지
  fi
  ...    # 이후 로직 무변경
}
```

**생성되는 payload (실모드, planner)** — 키 순서는 jq 삽입 순서:

```json
{"agent":"ht-planner","title":"ht-planner","location":{"directory":"<CWD>"},"model":{"providerID":"opencode-go","id":"glm-5.3-flash"}}
```

**worker/reviewer/orchestrator** — `"model"` 키 자체가 없다:

```json
{"agent":"ht-worker","title":"ht-worker","location":{"directory":"<CWD>"}}
```

**dry-run 계획 라인 (planner)** — 모델 값이 계획 문자열에 그대로 보인다:

```text
+ SID_PLANNER=$(opencode api post /api/session -d "$(jq -nc --arg a ht-planner --arg d <CWD> '{agent:$a,title:$a,model:{providerID:"opencode-go",id:"glm-5.3-flash"},location:{directory:$d}}')" | jq -r .data.id)
```

> `role_model` 은 `opencode_session_for` 바로 위에 두고, **다른 어떤 파일에도** 모델 문자열을 복제하지 않는다(단일 정본). `kind != opencode` 분기에는 손대지 않는다(세션 경로 자체가 없음).

---

## 6. 이 저장소의 라이브 팀(ht-planner pane) 반영 및 기존 생성물 갱신 절차

### 6.1 파일 갱신: **없음**

- `templates/opencode-agents/ROLE-planner.md` 와 이미 생성된 `.opencode/agents/ht-planner.md` 는 **바꾸지 않는다**(모델이 이 파일들에서 오지 않음).
- 따라서 `--force` 재시딩, agent md 재생성, `for` 루프 수동 실행 **불필요**.
- `setup_opencode_agents` 의 "같은 프리셋·비FORCE면 기존 파일 보존" 정책과 **충돌하지 않는다**(파일이 안 바뀌므로).

### 6.2 라이브 세션 반영: 재실행만으로는 안 바뀐다 (중요)

이유 2가지 (실측):
1. 모델은 **세션에 저장**된다(E4·E11) — 세션을 새로 만들거나 스위치하지 않으면 기존 세션은 옛 모델로 계속 돈다.
2. `herdr-team` 은 `herdr agent list | grep -q <agent>` 로 **이미 존재하는 agent 는 start 를 생략**한다. 게다가 재실행은 pane 분할을 다시 수행한다.

따라서 다음 중 하나로 planner 세션을 **새로 바인딩**한다.

```sh
# (0) 현재 planner 세션 확인
herdr agent get ht-planner                       # → result.agent.agent_session.value = ses_...
opencode api get /api/session/<SID>              # → data.model 확인 (before: opencode-go/deepseek-v4.1-flash)

# (A) 권장 1차: 사후 스위치 (E11 로 검증됨, 컨텍스트 보존)
opencode api post /api/session/<SID>/model -d '{"model":{"id":"glm-5.3-flash","providerID":"opencode-go"}}'
#   → 다음 턴 응답의 모델로 검증:
#   opencode api get /api/session/<SID>/message   # 최신 assistant 메시지의 .model
#   ※ 실행 중 TUI footer 즉시 갱신 여부는 미검증 (OQ-1). 턴 모델이 안 바뀌면 (B) 로.

# (B) 결정적: 새 세션 + pane 재바인딩 (planner 컨텍스트는 초기화됨)
#   planner pane 에서 TUI 종료(빈 shell 로 복귀) 후:
#   NEW=$(opencode api post /api/session -d "$(jq -nc --arg d "$PWD" \
#     '{agent:"ht-planner",title:"ht-planner",location:{directory:$d},model:{providerID:"opencode-go",id:"glm-5.3-flash"}}')" | jq -r .data.id)
#   herdr agent start ht-planner --kind opencode --pane <planner pane id> -- --session "$NEW"

# (C) 최후: 팀 전체 재기동 (herdr-team ht --preset dev) — 새 pane/새 세션 생성
```

- (A)는 되돌리기 쉬움(다시 기본 모델로 스위치 가능). **ops/orchestrator 승인 하에** 실행한다(라이브 팀 상태 변경).
- (B)/(C) 는 새 세션이므로 `model` 을 반드시 함께 넣는다.

### 6.3 검증(리뷰어/PM용)

| 시점 | 명령 | 기대 |
|---|---|---|
| before | `opencode api get /api/session/<planner SID>` | `.data.model = {id:"deepseek-v4.1-flash",providerID:"opencode-go"}` (E12) |
| after | 동일 | `.data.model = {id:"glm-5.3-flash",providerID:"opencode-go"}` |
| after | `opencode api get /api/session/<planner SID>/message` | 최신 assistant 메시지 `.model` 이 glm-5.3-flash |
| after | 동일 (worker/reviewer/orchestrator SID) | `.data.model` 이 `null` 또는 기본값(변경 없음) |

---

## 7. 다른 prefix 프로젝트로의 전파 범위 & 편집 보존 정책

### 7.1 전파

- 정본은 **스크립트**다: `bin/herdr-team` 이 `~/bin/herdr-team` 심볼릭/복사되는 설치 구조(`install.sh`)이므로, 스크립트 배포본이 갱신되면
  **모든 prefix 프로젝트·모든 preset**(planner 를 가진 dev/biz/creator/mkt/research)에 자동 적용된다. 프로젝트별 파일 편집이 필요 없다.
- `preset.conf` 에 모델을 두지 않는 이유: 이미 복사된 `~/templates/agent-team/<preset>/preset.conf` 가 낡으면 반영이 갈라진다. 역할 고정값은 스크립트 1곳이 맞다.
- `--template-dir` 로 사용자 커스텀 템플릿을 쓰는 프로젝트도 동일하게 적용된다(모델이 템플릿과 무관).

### 7.2 사용자 편집 보존

- 기존 정책(같은 프리셋 + 비FORCE + 파일 존재 → **보존**)은 그대로다. 이번 변경은 그 정책이 지키던 파일을 **아예 건드리지 않는다**.
- 사용자가 `.opencode/agents/ht-planner.md` 를 커스터마이즈해도 모델은 세션 payload 에서 오므로 서로 간섭하지 않는다.
- 사용자가 자기 프로젝트의 `opencode.json`/`default_agent`/모델 설정을 어떻게 두었든 이 변경은 그것을 덮어쓰지 않는다(파일 미수정). 단 planner 세션만 모델이 고정된다.

### 7.3 프리셋 전환 prune 영향 (요구사항 6)

| 시나리오 | 영향 |
|---|---|
| dev → biz 전환 | `setup_opencode_agents` 는 ROLES 기준으로 `<prefix>-worker.md` 등을 prune 한다. 모델 변경은 **파일 증감이 없어** prune 결과에 영향 없음 |
| biz → dev 복귀 | 잘린 역할 파일만 재생성(기존 동작). 모델은 payload 에서 오므로 재생성 파일 내용과 무관 |
| planner 가 없는 preset | planner 세션이 없으니 모델 지정도 발생하지 않음 (실패·경고 없음) |
| 잔재/정리 | 모델 설정은 **어떤 파일에도 저장되지 않는다**(세션 단위 상태뿐) → prune 대상·stale 설정 없음 |

**결론: prune 정책 변경 불필요.**

---

## 8. Task Breakdown (ht-worker 즉시 구현 가능)

> 규율: 대상 파일 전용 단위 테스트로 TDD 루프(Red→Green→Refactor), 완료 직전 전체 회귀 1회 + `[full-regression]` 고지.
> 현재 테스트 자산: `tests/test_agent_session.sh`(fake herdr+opencode 셤, 세션/바인딩/fail-fast), `tests/test_preset.sh`(프리셋·격리·dry-run 계약), `tests/test_templates_only.sh`, `tests/test_herdr_precheck.sh`.

### TB-1 — `bin/herdr-team`: 역할별 모델 테이블 + 세션 payload 확장
- **파일**: `bin/herdr-team` — `role_model()` 신설(`opencode_session_for` 바로 위, L541 근처), `opencode_session_for()` L541–563 수정
- **변경 요지**
  1. `role_model()`: `planner` → `opencode-go/glm-5.3-flash`, 그 외 → `''`. (호출부는 `"${agent#"$PREFIX"-}"` 로 얻은 role)
  2. 실모드 payload: `... + (if $m=="" then {} else {model:($m|split("/")|{providerID:.[0],id:.[1]})} end)` — 무지정 역할은 **키 생략**.
  3. dry-run 계획 라인: 모델이 있으면 payload 리터럴에 `,model:{providerID:"<p>",id:"<m>"}` 를 넣어 계획만 보고도 식별 가능하게.
  4. 기존 실패 처리(jq 실패/sid 파싱 실패/fail-fast 메시지)·`--no-start`/`--dry-run` 면제·kind 게이팅 **불변**.
- **완료 기준**
  - `./bin/herdr-team ht --preset dev --dry-run --no-interactive` 의 planner 세션 라인에 `glm-5.3-flash` 포함, worker/reviewer/orchestrator 세션 라인에는 미포함.
  - 실모드(셤) payload: planner 에만 `"model":{"providerID":"opencode-go","id":"glm-5.3-flash"}` 존재.
  - `--kind codex` / `--no-start` / `--dry-run` 경로에서 신규 동작 없음(세션 생성 호출 0회 유지).
  - `-- --agent` 미사용 유지(E15).
- **TDD 대상**: `tests/test_agent_session.sh` 케이스 g·h·i (아래 TB-2). 먼저 실패를 보고 green 으로.

### TB-2 — `tests/test_agent_session.sh`: 모델 케이스 3종 추가
- **파일**: `tests/test_agent_session.sh` (기존 셤/`run_case` 재사용, prefix `t`)
- **케이스**
  - **g) 실모드 planner payload**: `run_case ok` 의 `opencode.log` 에서 prefix `t-planner` 호출 라인이
    `"model":{"providerID":"opencode-go","id":"glm-5.3-flash"}` 를 포함.
    (셤이 `$*` 를 기록하므로 `-d` 뒤 **해석된 JSON** 이 그대로 남는다. jq 출력은 공백 없는 compact JSON → 문자열 어서션 가능)
  - **h) 실모드 비플래너 무지정**: 같은 로그에서 `t-worker`/`t-reviewer`/`t-orchestrator` 라인은 `"model"` 을 포함하지 않는다.
    (= `has("model") | not` 동등. jq 프로그램 텍스트가 아니라 **payload** 를 보는 것이 핵심 — 셤 로그에는 jq 프로그램이 안 남는다)
  - **i) dry-run 계획**: `run_case fail --dry-run`(또는 ok) 출력에서
    `SID_PLANNER` 라인은 `glm-5.3-flash` 포함, `SID_WORKER` 라인은 `glm-5.3-flash` **미포함**.
    기존 e) 의 `SID_PLANNER`/`-- --session` 어서션은 그대로 통과해야 한다.
- **완료 기준**: a~i 전부 PASS, 케이스 g·h·i 가 TB-1 이전에는 FAIL(Red) 이었음을 커밋 메시지/보고에 남김.
- **실행**: `bash tests/test_agent_session.sh`

### TB-3 — 문서: `README.md` + `README.ko.md` 1–2줄
- **파일**: `README.ko.md` "팀 모델" 절(≈L302), `README.md` "Team model" 절(≈L313)
- **변경 요지(예)**
  - ko: `- 역할별 모델: planner(기획)는 opencode-go/glm-5.3-flash, 나머지 역할은 모델 미지정 → 프로젝트 opencode 기본 모델. (kind=opencode 세션에 적용)`
  - en: `- Per-role model: planner runs on opencode-go/glm-5.3-flash; other roles leave the model unspecified and inherit the project default. (kind=opencode sessions)`
- **완료 기준**: 두 문서에 위 문구 존재, 금지 문자열(`--agent`) 유입 없음(`tests/test_preset.sh` §17 계열 어서션 영향 0), 링크/마크다운 파손 없음.
- **TDD 대상**: 문서 어서션은 신설하지 않는다(과잉). 회귀는 `bash tests/test_preset.sh` 로 확인.

### TB-4 — (ops, 선택) 라이브 리바인드 + 라이브 게이트
- §6.2 (A)→(B) 절차로 이 저장소 `ht-planner` pane 을 glm-5.3-flash 로 전환하고 §6.3 표로 검증.
- 라이브 게이트 항목: ① pane 에서 새로 보낸 턴의 assistant `.model` 이 glm-5.3-flash ② worker/reviewer/orchestrator 는 기본값 유지 ③ TUI footer 표기(OQ-1) ④ `herdr agent prompt ht-planner` 1턴 왕복 정상.
- **승인 필요**: 라이브 세션 상태 변경이므로 PM/orchestrator 승인 하에만. 코드/테스트 변경 없음.

---

## 9. 엣지 케이스

1. **모델 문자열 오타·미존재 모델** — opencode 는 세션 생성 시 agent 존재를 검증하지 않았고(E11 류), 모델도 검증되지 않는다. 즉 오타는 **조용히 기본 모델로 폴백**한다. 완화: TB-2 g 가 payload 를 **정확한 문자열로** 어서션하므로 상수 오타는 테스트에서 즉시 잡힌다(별도 런타임 검증 불필요).
2. **이미 존재하는 pane/agent 재실행** — `herdr agent list | grep -q` 로 start 생략 → 세션도 새로 안 만들어져 모델이 갱신되지 않는다(§6.2). 코드 변경으로 풀 문제가 아니고 **운영 절차**로 다룬다.
3. **세션 모델의 지연 materialize** — 유효 모델은 턴에서 확정된다. `session.model=null` 인 세션(worker/reviewer, E12)도 턴은 기본 모델을 쓴다 → "무지정 = 기본값" 요구와 일치. 테스트에서 `session.model` 의 null/값 차이를 실패로 보지 않는다.
4. **기본 모델의 로케이션 의존성** — location 기본 모델은 로케이션 상태에 따라 달라질 수 있다(실측: 이 저장소는 `opencode-go/deepseek-v4.1-flash`, `/tmp` 신규 로케이션은 `opencode/nemotron-3.5-super-vl-free`). 따라서 "나머지 역할 = 무지정"은 요구대로지만, **구체적 기본 모델은 프로젝트에 따라 다르다**(문서 문구를 "opencode 기본값"으로 쓰고 특정 모델로 못박지 않는다).
5. **`kind != opencode`**(claude/codex/…) — 세션 경로가 없어 모델 지정 자체가 없다. 기존 동작 불변(명시적 비범위).
6. **`--no-start` / `--dry-run`** — 면제 유지. dry-run 은 계획에 모델이 보이지만 호출은 하지 않는다.
7. **planner 없는 preset** — `role_model` 이 호출되지 않아 무해.
8. **provider 자격증명 부재** — opencode-go 접근이 불가한 환경에서 planner 세션은 모델 해석 실패로 턴이 실패할 수 있다(무지정이었다면 기본 모델로 동작). 이는 요구된 동작의 본질적 대가(§10 OQ-6).
9. **모델 variant(`#`)** — `provider/model#variant` 문법은 미지원(`shortcut:` 주석). 필요 시 `split("#")` 확장.
10. **prefix/역할명 위생** — prefix 는 이미 위생 처리되며 role 은 preset ROLES 값이라 셸 인젝션 표면이 늘지 않는다. `role_model` 은 `case` 매칭만 한다.
11. **`jq` 부재** — 기존과 동일(셤/`need_cmd` 경로). payload 생성 실패는 기존 fail-fast 메시지로 처리.

---

## 10. 열린 질문 / 미검증 항목

| ID | 항목 | 상태 | 확인 방법 |
|---|---|---|---|
| OQ-1 | `POST /api/session/{sid}/model` 사후 스위치가 **실행 중 TUI** 모델/턴에 반영되는가 | 미검증(세션 레코드 반영은 검증 E11. agent 스위치 유사 사례는 "TUI 미반영"이었음) | §6.2 (A) 실행 후 `GET /api/session/{sid}/message` 로 다음 턴 모델 확인, 실패 시 (B) |
| OQ-2 | TUI footer 에 `glm-5.3-flash` 가 표시되는가 | 미검증 | 라이브 게이트(TB-4 ③) |
| OQ-3 | location 기본 모델의 결정 출처(프로젝트 상태 vs 전역) | 미확정(`~/.local/state/opencode/model.json` 는 최근 목록만 보유) | 기본 모델이 다른 신규 프로젝트에서 `herdr agent` 턴 모델 관측 |
| OQ-4 | 비플래너 역할의 기본 모델을 저장소 문서에 같이 못박을지 | 미정(§9-4 이유로 비권장) | PM 결정 |
| OQ-5 | 연구자/ops 등 on-demand 역할에 모델을 정할지 | 범위 외(요구는 planner 한정) | PM 결정 시 `role_model` 에 케이스 추가 |
| OQ-6 | opencode-go 접근 불가 프로젝트에서 planner 핀 고정이 실패로 이어질지, 기본값으로 폴백할지 | 미검증 | 자격증명 없는 환경에서 planner 턴 1회 |
| OQ-7 | `docs/specs/opencode-agent-assignment.md` 의 세션 payload 목록에 `model` 누락 | 확인됨 | (선택) 1줄 정정 — 필수 아님 |

---

## 11. 프리셋 전환 prune·문서 갱신 필요 여부 (요구사항 6 요약)

- **prune**: 변경 불필요(§7.3 — 파일 증감 없음, 저장되는 모델 상태 없음).
- **README**: **갱신 권장(1–2줄)** — TB-3. 역할 표에 모델 컬럼을 추가하는 방식은 쓰지 않는다(표 재배치 = 리뷰/문서 충돌 비용, 그리고 `templates/AGENTS.md` 는 재시딩 없이는 기존 프로젝트에 반영되지 않는다).
- **템플릿 AGENTS.md / 역할 문서**: **갱신하지 않는다**(재시딩 필요 + 사용자 편집 파일 리스크 = R5 위반 소지).

---

## 12. 워커 주의사항 — 현재 워킹트리 미커밋 변경 보존 (필수)

현재 커밋되지 않은 변경 4건:

```
 M AGENTS.md
 M agents/dev/AGENTS.md
 M agents/dev/ht-planner.md
 M agents/dev/ht-reviewer.md
```

- 이 4개 파일은 **이번 작업의 변경 대상이 아니다.** 생성·재시딩(`--force`, `setup_templates`)·되돌리기(`git checkout --`), 포맷터 일괄 적용 등 **어떤 경로로도 덮어쓰지 않는다.**
- 커밋/스테이징도 하지 않는다(사용자 편집분). 작업 전후 `git status --short` 를 비교해 **동일한 4건 + 신규 변경(bin/herdr-team, tests/test_agent_session.sh, README*.md)만** 있는지 확인한다.
- 테스트가 저장소를 오염시키지 않는지 실측 확인됨: 모든 비-dry-run 실행은 `--cwd <temp>` 를 넘긴다(`tests/test_agent_session.sh:64`, `tests/test_preset.sh:234/257/265/386/542/593`, `tests/test_templates_only.sh:37/68/94/102/110`, `tests/test_herdr_precheck.sh:70/72/76`). `--cwd` 없는 호출(`test_preset.sh:64/73/81/…`)은 전부 `--dry-run`(쓰기 0). **그래도 회귀 1회 후 `git status` 를 확인**한다.
- `git add -A` / `git stash` / `git commit` 금지(미커밋 사용자 편집 손실 위험).

---

## 13. 부록 — 재현·검증 명령 모음

```sh
# 모델 실재 확인 (opencode-go)
#   provider=opencode-go, query: glm-5.3 / deepseek-v4.1 → 둘 다 [active]

# 세션 payload 스펙 확인
opencode api get /openapi.json   # POST /api/session body.model = Model.Ref{id,providerID,variant?}

# 모델 지정이 실제 턴에 반영되는지 (핵심 실험)
S=$(opencode api post /api/session -d "$(jq -nc --arg d "$PWD" \
    '{agent:"ht-planner",title:"probe",location:{directory:$d},model:{providerID:"opencode-go",id:"glm-5.3-flash"}}')" | jq -r .data.id)
opencode api post "/api/session/$S/prompt" -d '{"text":"Reply with exactly: OK"}'
opencode api get  "/api/session/$S/message"      # 최신 assistant .model == glm-5.3-flash
opencode api delete "/api/session/$S"

# frontmatter model 이 무효임을 재확인 (반증 실험)
#   신규 location 에 .opencode/agents/probe-x.md(model: opencode-go/glm-5.3-flash, 본문 "PINEAPPLE") 생성
#   → POST /api/session {agent:"probe-x"} + prompt → 응답 PINEAPPLE(로딩됨) 인데 .model 은 location 기본값

# dry-run 계약
./bin/herdr-team ht --preset dev --dry-run --no-interactive

# 회귀
bash tests/test_agent_session.sh && bash tests/test_preset.sh && bash tests/test_templates_only.sh \
  && bash tests/test_herdr_precheck.sh && bash tests/test_install.sh && bash tests/test_version.sh
```

**되돌리기**: 코드는 `bin/herdr-team` 의 `role_model` 호출 1곳 + payload 조건 제거로 원복. 세션은 사후 스위치(E11)로 기본 모델 복귀 가능. 파일 산출물이 없으므로 정리할 잔재도 없다.
