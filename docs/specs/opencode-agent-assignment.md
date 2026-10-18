# OpenCode 실행 시 agent 자동 할당 — 대안 분석 및 권고 아키텍처

- **상태**: 제안(Draft) — 구현 전
- **대상 버전**: OpenCode `v2.0.32` (V2 문서 기준), herdr CLI (integration opencode v13)
- **범위**: `herdr-team` 이 `herdr agent start <name> --kind opencode --pane <pane>` 로 pane 을 기동할 때,
  각 pane 이 **해당 역할의 opencode primary agent**(`<prefix>-<role>`)로 결정적으로 시작되도록 하는 방법.
- **비범위**: 권한 팝업 AUTO-ALLOW(`bin/herdr-watcher`) 정책 변경, 프리셋/역할 구성 변경, opencode 자체 패치.

---

## 1. 요구사항 요약 & 목표

| # | 요구사항 | 수용 기준(DoD) |
|---|---|---|
| R1 | pane 별 **다른** 역할 agent 로 기동 | dev 프리셋 4 pane 이 각각 orchestrator/planner/worker/reviewer 로 기동 |
| R2 | 결정적(deterministic) | 재실행 시 동일 결과. 순서/포커스/화면 상태에 의존하지 않음 |
| R3 | 무키 주입(no blind key injection) | agent 선택을 위해 `send-keys` 를 사용하지 않음 |
| R4 | 모드 오염 불가 | 기동 후 사용자/워처 입력으로 primary agent 가 순환되지 않음 |
| R5 | 실패는 조용히 넘어가지 않음 | agent 할당 실패 시 Build 로 조용히 떨어지지 않고 즉시 비정상 종료 + 원인 메시지 |
| R6 | 기존 계약 보존 | `--dry-run` 계획 출력, `--no-start`, kind 게이팅, pane/agent 네이밍, 테스트 §17 불변식 유지 |
| R7 | 최소 침습 | 사용자 프로젝트의 `opencode.json` 등 사용자 소유 설정을 수정하지 않음(가능하면) |

### 결론 (권고안 한 줄)

> **pane 별로 opencode 세션을 미리 생성할 때 `agent` 를 지정하고(`opencode api post /api/session`),
> `herdr agent start ... -- --session <sid>` 로 그 세션에 바인딩해 기동한다.**
> 키 주입 없음, 프로젝트 설정 파일 수정 없음, 백그라운드 서비스 토폴로지 유지, pane 별 역할 분리 가능.

---

## 2. 검증된 사실 (Evidence)

아래는 모두 **실측**이며, 표의 "판정"은 재현 명령 결과 기준이다. (추측은 §8 에서 별도 표기)

| # | 메커니즘 | 확인 방법 | 관측 결과 | 판정 |
|---|---|---|---|---|
| E1 | 루트 CLI 에 `--agent` 없음 | `opencode --help` | 플래그: `--standalone --server --auto --continue(-c) --session(-s) --prompt` 만 존재 | **확정** (v2.0.32) |
| E2 | `opencode run --agent` 존재 | `opencode run --help` | `--agent string` (단, 비대화형 실행) | 확정 |
| E3 | `--session` 은 "없으면 생성"까지 허용 | `opencode --help` | `--session, -s string  Session ID to continue, or to create if it does not exist` | 확정 |
| E4 | 프로젝트 로컬 설정 `default_agent` 가 TUI 에 반영 | `/tmp` 임시 프로젝트에 `opencode.json {"default_agent":"plan"}` 두고 TUI 기동(PTY) | footer 가 `Plan·DeepSeek V4.1 Flash` | **확정** |
| E5 | 무설정 대조군 | 설정 없는 디렉터리에서 TUI 기동 | footer 가 `Build·DeepSeek V4.1 Flash` | 확정 |
| E6 | 프로젝트 로컬 `.opencode/agents/<id>.md` + `default_agent` | `.opencode/agents/probe-planner.md`(기존 ROLE-planner 템플릿) + `default_agent:"probe-planner"` | footer 가 `Probe-Planner` | **확정**(=herdr-team 산출물 패턴 그대로 동작) |
| E7 | **세션 사전 생성 + `--session`** | `opencode api post /api/session -d '{"agent":"plan","location":{"directory":"<cwd>"}}'` → `opencode --session <sid>` | footer 가 `Plan` (프로젝트 설정 없음) | **확정 (권고안 핵심)** |
| E8 | 세션 agent 우선순위 | `default_agent=probe-planner` 디렉터리에서 `agent=plan` 세션을 `--session` 으로 개방 | footer 가 `Plan` (세션 agent 가 이김) | 확정 |
| E9 | 무효 `default_agent` 는 조용히 build 폴백 | `default_agent:"nonexistent-role-xyz"` | TUI 정상 기동, footer `Build` (오류 표면화 없음) | 확정 → R5 위반 |
| E10 | 실행 중 TUI 에 대한 외부 `session.switchAgent` | TUI(`Build`) 실행 중 `opencode api post /api/session/<sid>/agent -d '{"agent":"plan"}'` | API 는 성공(rc=0)하나 **footer 는 계속 `Build`** | **기각 근거** |
| E11 | `session.create` 는 agent 존재를 검증하지 않음 | `-d '{"agent":"nonexistent-role-xyz"}'` | 200 + `agent:"nonexistent-role-xyz"` 로 생성됨 | 확정 (사전 검증 필요) |
| E12 | `GET /api/agent/<id>` 는 검증한다 | 위 id 조회 | `404 AgentNotFoundError` | 확정 |
| E13 | env 기반 설정은 `--standalone` 에서만 유효 | `OPENCODE_CONFIG=<file>` / `OPENCODE_CONFIG_CONTENT` 로 TUI 기동 | `--standalone` → `Plan` 반영 / 공유 백그라운드 서비스 → `Build`(env 무시) | 확정 |
| E14 | `OPENCODE_SESSION_ID` | TUI 기동 시 env 주입 | footer `Build` (효과 없음) | 확정(음성) |
| E15 | prompt 레벨 agent 첨부 | `POST /api/session/<sid>/prompt -d '{"text":"@plan hi","agents":[{"name":"plan"}],"resume":false}'` | 세션 `agent` 미설정(키 부재) | 확정(음성, 문맥상 per-turn 첨부) |
| E16 | TUI 키바인드(V2 기본값) | V2 keybinds 문서 | `agent.cycle`=**shift+tab**, `agent.list`=**`<leader>a`**(leader=`ctrl+x`), `dialog.select.submit`=return | 확정 → TIL 의 `tab` 가정은 V1 기준 |
| E17 | herdr 의 인자 전달/환경 주입 표면 | `herdr agent start --help` / `herdr pane split --help` | `herdr agent start <NAME> --kind <KIND> --pane <ID> [OPTIONS] [-- [AGENT_ARG]...]`, `herdr pane split ... --env <KEY=VALUE>` | 확정(표면 존재) / **실사용은 미검증(§8 OQ-1)** |
| E18 | herdr 은 이미 pane↔opencode 세션을 안다 | `herdr agent list` | 각 pane 에 `agent_session {kind:"id", source:"herdr:opencode", value:"ses_..."}` | 확정 |
| E19 | 세션 위치 기본값 | `opencode api post /api/session` 을 임의 cwd 에서 실행 | `location.directory = /home/hm` (cwd 아님) | 확정 → **location 명시 필수** |
| E20 | dry-run 테스트 계약 | `tests/test_preset.sh` §17 | `-- --agent` 미사용을 어서션 | 확정(불변식 유지 대상) |

보조 관측: `opencode api get /openapi.json` 에 `POST /api/session` (body 에 `agent`/`location`/`metadata`/`permissions`), `POST /api/session/{id}/agent`(description: *"Switch the agent used by subsequent provider turns"*), `GET /api/agent`(+`location` query) 등이 존재.

---

## 3. 아키텍처 / 데이터 흐름 (권고안)

```
herdr-team ht (preset=dev, kind=opencode, layout=2col)
  │
  ├─ (1) setup_templates / setup_opencode_agents      ← 기존: .opencode/agents/<prefix>-<role>.md 생성
  ├─ (2) pane split × N (--cwd <CWD> --no-focus)      ← 기존
  └─ (3) role 루프 (신규: kind=opencode 한정)
         │
         │  sid = opencode api post /api/session
         │        -d '{"agent":"<prefix>-<role>","title":"<prefix>-<role>","location":{"directory":"<CWD>"}}'
         │        | jq -r .data.id                      ← 역할 고정 지점
         │
         └─ herdr agent start <prefix>-<role> --kind opencode --pane <P> -- --session "$sid"
                                                            ↑ pane 별 세션 바인딩

  이후:
   - TUI footer = <Role> (역할 가시화), 권한은 agent md 대로 강제
   - herdr plugin(v13) 이 pane→ses_... 보고 (E18) → `herdr agent prompt <name>` 정상 동작
   - bin/herdr-watcher AUTO-ALLOW(enter) 정책 변경 없음
```

**실패 정책(권고)**: `opencode` 미설치 / `opencode api` 실패 / `sid` 파싱 실패 / 생성된 agent id 부재 → **즉시 비정상 종료**(R5).
`--dry-run` 과 `--no-start` 는 면제. (E9 같이 Build 로 조용히 떨어지는 경로를 만들지 않는다.)

---

## 4. 대안 분석

| # | 대안 | 방식 | 장점 | 단점 / 리스크 | 판정 |
|---|---|---|---|---|---|
| A | **키 주입(send-keys)** | 기동 후 `shift+tab`(`agent.cycle`) 또는 `<leader>a`(`agent.list`)로 원하는 agent 순환/선택 | CLI 플래그 불필요 | ① 순환 개수·시작 인덱스를 화면에서 추정해야 함(비결정적) ② 팝업/다이얼로그가 키를 소비 ③ **실사고 선례**: stray `tab` 주입으로 primary agent 오염·편집 불가(TIL 2026-09-23), 워처는 이미 fail-closed 로 `tab` 자동 발화를 금지 ④ V2 순환 키는 `shift+tab` 이라 기존 `tab` 가정 자체가 부적합 ⑤ `agent.list` 다이얼로그는 UI 변경에 취약 | **기각** (권한 승인용 `enter` 경로만 유지) |
| B | **세션 사전생성 연동** | `session.create(agent=...)` → `--session <sid>` | pane 별 상이 역할 가능, 결정적, 키 없음, 프로젝트 설정 파일 무수정, 공유 서비스 토폴로지 유지, 세션 agent 가 설정보다 우선(E8) | ① 기동 시 API 호출 1회/ pane ② 세션 행 N개 누적 ③ 세션 생성이 agent 존재를 검증하지 않음(E11) → 자체 검증 필요 ④ `--session` 이 다른 location 세션을 열 때의 동작 미확인(OQ-6) ⑤ `herdr ... -- --session` 전달 실사용 미검증(OQ-1) | **채택(권고)** |
| C | **설정 레벨(`default_agent`)** | 프로젝트 `opencode.json(c)` / `.opencode/opencode.json(c)` 에 `default_agent` | 1줄, 런타임 호출 없음, 세션 누적 없음, 문서화된 공식 필드 | ① **프로젝트당 값 1개** → pane 별 역할 분리 불가(모든 프리셋이 3~4역할) ② 사용자 소유 설정 파일 수정 필요(머지/보존 책임) ③ 무효 id 는 조용히 build 폴백(E9) → 프리셋 전환 prune 과 결합 시 회귀 위험 ④ 사용자가 이미 `default_agent` 를 쓰면 충돌 | **부분 채택**: opencode 역할이 1개뿐인 구성/보조용. 다역할 pane 의 주 수단으로는 부적합 |
| D | **프로젝트 설정 + pane 별 cwd** | pane 마다 하위 디렉터리를 cwd 로 주고 그 아래 config 로 `default_agent` 분기 | 파일만으로 분기 | ① pane cwd 가 프로젝트 루트가 아니게 됨(상대경로/지침서/빌드 산출물 위치 왜곡) ② 상위 `.opencode/opencode.json` 이 있으면 우선순위 역전(V2 병합 규칙) ③ 요구사항 R7·기존 동작 보존과 상충 | 기각 |
| E | **env 설정 + `--standalone`** | `herdr pane split --env OPENCODE_CONFIG_CONTENT=...` + `opencode --standalone` | pane 별 분기, 파일 무수정, 세션 누적 없음, standalone 에서 동작 확인(E13) | ① pane 마다 **전용 서버 프로세스**(메모리·DB 동시 쓰기·로그 분산) ② opencode 기본 토폴로지(공유 서비스)와 이탈 → herdr 통합/감지 회귀 위험 ③ `--env` 전달 자체 미검증(OQ-2) ④ 진단 복잡도 증가(로그 role=server 다중) | **차선(백업)**: A 가 현장에서 실패할 때만 |
| F | **TUI 플러그인 레벨** | 전역 `cli.json` 에 CLI 플러그인 등록 + pane env(예: 역할 변수) 로 읽어 `keymap.dispatch("agent.select", ...)` | 키 주입 없음, 세션 누적 없음 | ① CLI 플러그인은 `cli.json` 전역만(프로젝트 로컬 CLI 설정 없음) → 전 사용자 전역 설치/업데이트 부담 ② `agent.select` 가 agent id 입력을 받는지 미확인(OQ-5) ③ 플러그인 실패 시 조용히 Build → R5 위반 ④ herdr-team 이 플러그인 배포·버전 관리를 떠안음 | 보류(장기) |
| G | **`opencode run --agent` 시딩** | 세션을 `run --agent X` 로 만들고 TUI 로 이어받기 | `--agent` 플래그 존재 | 모델 턴이 1회 실행됨(비용·부작용), 결국 A 와 동일 결과를 더 비싸게 얻음 | 기각(A 로 흡수) |
| H | **프롬프트 멘션 주입** | 초기 프롬프트에 `@<agent>` 첨부 | 추가 배선 최소 | 세션 agent 로 확정되지 않음(E15). per-turn 첨부로 보이며 footer/권한 강제가 역할 고정을 보장하지 못함 | 기각 |
| I | **외부 API 사후 스위치** | 기동 후 `POST /api/session/<sid>/agent` | 배선 단순 | 실행 중 TUI 의 agent 표시/선택이 바뀌지 않음(E10). 서버 턴과 TUI 상태가 어긋남 | 기각 |

---

## 5. 권고 아키텍처 상세

### 5.1 호출 계약 (인터페이스 예시 — 구현 아님)

```sh
# (1) 역할 agent 를 가진 세션 생성 (agent id 는 herdr-team 이 방금 생성한 정의와 동일)
#     - location 을 반드시 명시한다 (미지정 시 $HOME 로 귀속됨: E19)
#     - JSON 은 jq -n 으로 구성해 경로 내 공백/특수문자를 안전 처리
opencode api post /api/session \
  -d "$(jq -nc --arg a "$agent" --arg t "$agent" --arg d "$CWD" \
        '{agent:$a,title:$t,location:{directory:$d}}')"
# 응답: {"data":{"id":"ses_...","agent":"<a>","location":{"directory":"<CWD>"}, ...}}

# (2) 그 세션으로 pane 기동
herdr agent start "$agent" --kind opencode --pane "$pane" -- --session "$sid"
```

### 5.2 사전 검증(필수)

- `KIND == "opencode"` 이고 실제로 start 하는 경우에 한해:
  - `need_cmd opencode`
  - 역할 agent 정의 파일 존재 확인: `.opencode/agents/<prefix>-<role>.md` (herdr-team 이 생성하므로 신뢰 가능한 근거)
  - (선택) `opencode api get /api/agent/<id>` 로 존재 확인 — 단 조회 location 파라미터 동작이 미확인(OQ-3)이므로 파일 검사를 1차 근거로 사용
- `KIND != "opencode"` → **완전 무변경**(기존 동작/테스트 불변식 유지)

### 5.3 실패 처리

| 상황 | 동작 |
|---|---|
| `opencode` 없음 / 서비스 미기동으로 API 실패 | stderr 에 원인 + 우회 안내 후 `exit != 0` (`--dry-run`, `--no-start` 면제) |
| 응답에서 `sid` 파싱 실패 | 동일(fail-fast) |
| pane split 은 성공했는데 세션 생성 실패 | 종료 전 로그에 "이미 생성된 pane N개" 명시(사용자가 직접 정리 가능하도록) |
| 이미 같은 이름 agent 존재(pane 재사용) | 기존 로직(herdr agent list 확인 후 존재 시 생략) 유지 |

### 5.4 dry-run 계획 출력 (기존 계약 확장)

```text
+ SID_WORKER=$(opencode api post /api/session -d '{...}' | jq -r .data.id)
+ herdr agent list | grep -q ht-worker || herdr agent start ht-worker --kind opencode --pane "$P_WORKER" -- --session "$SID_WORKER"
```

---

## 6. Task Breakdown (ht-worker 즉시 구현 가능)

> 규율: 대상 파일 전용 단위 테스트로 TDD 루프, 완료 직전 전체 회귀 1회([full-regression] 고지).
> 현재 테스트 자산: `tests/test_preset.sh`(dry-run 문자열 계약 + 프리셋/격리), `tests/test_watcher.sh`(fake herdr 셤 + `HERDR_FIX`), `tests/test_install.sh`, `tests/test_templates_only.sh`.

### TB-1 — `bin/herdr-team`: opencode 한정 세션 사전생성 + `-- --session` 바인딩 (right-stack 경로)
- **파일**: `bin/herdr-team` (`run()` 옆에 capture 헬퍼 추가, `setup_panes` 의 right-stack start 루프 ≈ L991–1000)
- **변경 요지**
  1. `run_capture()` 신설: `DRY_RUN=1` 이면 `+ <cmd>` 출력 + placeholder id 반환, 실모드면 실행 후 stdout 반환(실패 시 비정상 종료).
  2. `opencode_session_for(agent)` 신설: §5.1 페이로드로 세션 생성, `.data.id` 반환.
  3. start 루프: `KIND == "opencode"` 이면 `sid` 를 얻어 `-- --session "$sid"` 를 붙인다. 그 외 kind 는 기존 명령 그대로.
  4. 사전 점검: `KIND == "opencode" && NO_START == 0 && DRY_RUN == 0` 에서 `need_cmd opencode`.
- **완료 기준**
  - `ht --preset dev --dry-run --no-template --no-interactive` 출력에 세션 생성 라인과 `-- --session` 이 role 수만큼 존재.
  - `-- --agent` 는 **여전히 미출력**(E20 불변식 유지).
  - `KIND != opencode`(예: `--kind codex --dry-run`)에서 신규 라인 0줄.
- **TDD 대상**: `tests/test_preset.sh` §17 확장 — (a) dev/biz/creator dry-run 에 `-- --session` 존재, (b) `-- --agent` 미존재, (c) codex kind 에서 세션 라인 미존재, (d) 세션 생성 라인에 `location` 포함(E19 회귀 방지).

### TB-2 — `bin/herdr-team`: 2col 레이아웃 경로 정합
- **파일**: `bin/herdr-team` (`setup_panes` 의 2col dry-run 블록 ≈ L878–883 + 실기동 루프 ≈ L991 이전 분기)
- **완료 기준**: 2col(pane 매핑이 ROLES 순서와 다름)에서도 **역할↔세션↔pane 3자 매핑**이 어긋나지 않음. dry-run 출력에서 `SID_<ROLE>` 와 pane 변수명이 동일 역할을 가리킴.
- **TDD 대상**: 2col dry-run 출력에서 `SID_PLANNER` 가 planner pane 변수(`P_PLANNER`)와 같은 라인/순서로 등장.

### TB-3 — 실패 경로 테스트(fail-fast, R5)
- **파일**: `tests/test_preset.sh` (또는 신규 `tests/test_agent_session.sh`)
- **방법**: `PATH` 앞단에 `opencode` 셤 스크립트를 두고 (i) 정상 id 반환, (ii) 비정상 종료, (iii) 잘못된 JSON 세 케이스 검증. fake `herdr` 셤 기법은 `tests/test_watcher.sh` 의 `HERDR_FIX` 패턴 재사용.
- **완료 기준**: (i) 기동 명령에 `-- --session ses_fake` 포함, (ii)/(iii) 비정상 종료 + 원인 메시지(조용한 Build 폴백 0건).
- **TDD 대상**: 위 3케이스 + `--no-start`/`--dry-run` 면제 케이스.

### TB-4 — 문서 정정 (stale `--agent`)
- **파일**: `README.md`, `README.ko.md` (L127, L164 부근: `--agent <prefix>-<role>` 서술), 필요 시 `docs/` 동반 문서
- **완료 기준**: V2 에 존재하지 않는 `--agent` 플래그 서술 제거, 권고안(세션 바인딩) 1문단 + dry-run 예시 반영. `templates/` 내 문서에 동일 문구가 있으면 함께 정정.
- **TDD 대상**: `tests/test_preset.sh` 에 `README 에 "-- --agent 로 시작"` 류 문구 부재 어서션 1건(문서 회귀 방지).

### TB-5 — 워처 help 문구의 V1 키 가정 정정 (코드 변경 없음)
- **파일**: `bin/herdr-watcher` (`--approve-keys`/`--fallback-keys` help 문구 ≈ L303–305), 필요 시 TIL 후속 노트
- **완료 기준**: "tab 이 primary agent 를 순환시킨다"는 서술을 **V2 기준 `shift+tab`(`agent.cycle`)·`<leader>a`(`agent.list`)** 로 정정. 기본값·동작은 불변(fail-closed 유지).
- **TDD 대상**: `tests/test_watcher.sh` 기존 케이스 a~i 전부 PASS 유지(동작 불변 증명) + help 문자열에 `shift+tab` 포함.

### TB-6 — 라이브 게이트(수동, ops/PM 승인 범위)
- 4 pane 기동 후 **각 pane footer 가 해당 역할명**을 표시하는지 육안 확인 + `herdr agent prompt` 1턴 왕복 + `herdr agent list` 에서 `agent_session.value` 가 pane 별로 상이한지 확인.
- 여기서 **OQ-1(herdr 인자 전달)** 을 최종 확정한다.

---

## 7. 엣지 케이스

1. **프리셋 전환으로 역할 agent 가 prune 된 경우** — `setup_opencode_agents` 가 start 보다 먼저 실행되므로 start 시점의 `.md` 존재 검사가 유효. stale `default_agent` 류 조용한 폴백(E9) 위험은 세션 방식에서 발생하지 않음.
2. **세션 누적** — 기동마다 pane 당 1세션 증가. 제목을 `<prefix>-<role>` 로 고정해 식별 가능하게 하고, 정리 자동화는 범위 외(§8 OQ-7).
3. **pane 재기동(`herdr` 재시작/`agent restart`)** — 기록된 명령 재실행 시 동일 `sid` 로 재개될 수 있어 히스토리가 누적된다. 역할 고정은 유지되지만 컨텍스트 격리는 약화(§8 OQ-8). 신규 런치(`ht` 재실행)는 항상 새 세션.
4. **location 미지정** — `$HOME` 귀속(E19). 반드시 `location.directory = <CWD>` 명시. 경로 공백/한글은 `jq -nc --arg` 로 회피.
5. **`--kind` 가 opencode 계열이 아닌 경우** — 신규 로직 진입 금지(현행 명령/테스트 불변).
6. **opencode 버전 드리프트** — `--session`/`POST /api/session.agent` 는 버전 의존 표면이므로, 최소 버전 게이트(또는 실패 시 명확한 메시지)를 권장. `opencode --version` 검사는 옵션.
7. **Windows 런처 경로** — `hts.bat`/`windows/start-team.bat` 는 `bin/herdr-team` 을 호출하므로 코드 변경 영향은 없으나, `opencode`·`jq` 의존성이 새로 늘어난다(`windows/install.bat` 점검 필요 여부는 §8 OQ-9).
8. **동시 기동** — herdr-team 은 pane 분할을 순차 실행하므로 세션 생성도 순차. 병렬화하지 않는다(경합 회피).
9. **사용자가 이미 `default_agent` 를 설정한 프로젝트** — 권고안은 그 값을 덮어쓰지 않으며, 세션 agent 가 우선하므로(E8) 회귀 없음. 단 pane 에서 `default_agent` 가 여전히 유효하다는 점을 문서화.

---

## 8. 열린 질문 / 미검증 항목

| ID | 항목 | 상태 | 확인 방법(권장) |
|---|---|---|---|
| OQ-1 | `herdr agent start ... -- --session <sid>` 전달 및 readiness 판정 | **미검증(추측 아님, 표면만 확인 E17)** | TB-6 라이브 게이트 1회 |
| OQ-2 | `herdr pane split --env KEY=VALUE` 가 셸/자식에 전달되는지 | 미검증 | 옵션 E 채택 시에만 필요 |
| OQ-3 | `opencode api ... --param location=<dir>` 가 실제로 location 을 바꾸는지 | 미검증(현재는 무시되고 `$HOME` 사용) | API 검증 경로를 쓰려면 필요, 파일 검사로 대체 가능 |
| OQ-4 | 프롬프트 `@mention`(TUI)과 `agents` 첨부의 실제 의미(세션 agent 변경 여부) | 미검증(E15 는 음성 증거) | 세션 agent 재조회 실험 |
| OQ-5 | CLI 플러그인 `keymap.dispatch("agent.select", <id>)` 가 id 입력을 받는지 | 미검증 | 옵션 F 채택 시에만 필요 |
| OQ-6 | `--session` 으로 다른 location 세션을 열 때 부작용 | 부분 검증(동작은 함) | 프로젝트 교차 시나리오 라이브 확인 |
| OQ-7 | 세션 누적 정책(정리 명령/보존 기간) | 미정 | 운영 정책 결정(PM) |
| OQ-8 | 동일 `sid` 재기동 시 컨텍스트 누적 허용 여부 | 미정 | 역할 격리 기대치와 함께 결정 |
| OQ-9 | Windows 환경 `opencode`/`jq` 의존성 처리 | 미정 | `windows/install.bat` 점검 |

---

## 9. 부록

### 9.1 재현 스크립트 (검증에 사용한 PTY 관측 방식)

```sh
# 임시 프로젝트에서 TUI 를 PTY 로 띄워 footer 의 agent 표기를 관측
mkdir -p /tmp/opencode/probe && cd /tmp/opencode/probe
printf '{"default_agent":"plan"}' > opencode.json
python3 - <<'PY'   # pty.fork → opencode 실행 → 12초 수집 → ANSI 제거 후 footer 확인
# (요점) footer 의 "<Agent>·<Model>" 문자열로 실제 선택 agent 를 판정한다
PY
```

### 9.2 오프슈트 사실 (본 이슈와 별개, 기록용)

- TIL `2026-09-23-watcher-stray-key-agent-mode-pollution.md` 의 "`tab` 이 primary agent 순환 키" 전제는 **V1 기준**이다. V2 기본값은 `agent.cycle = shift+tab`, `agent.list = <leader>a` (leader=`ctrl+x`). 워처의 fail-closed(자동 `tab` 금지) 정책은 그대로 타당하나 문구 정정이 필요(TB-5).
- `README*.md` 의 `--agent <prefix>-<role>` 서술은 V2 에 존재하지 않는 플래그다(TB-4).
- `tests/test_preset.sh` §17 의 `-- --agent` 미사용 어서션은 **유지**해야 한다(권고안은 `-- --session` 을 쓴다).

### 9.3 권고 요약 카드

| 상황 | 선택 |
|---|---|
| 기본(모든 프리셋, 다역할 pane) | **B: 세션 사전생성 + `--session`** |
| opencode 역할이 1개뿐인 구성 | C: 프로젝트 `default_agent` (+ 파일 존재 검증) |
| B 가 라이브에서 실패(OQ-1) | E: `--standalone` + `pane split --env` (per-pane 서버 비용 감수) |
| 절대 금지 | A(키 순환), I(사후 API 스위치), H(멘션 의존) |
