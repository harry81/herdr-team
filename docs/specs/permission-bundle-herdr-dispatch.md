# Spec: permission-bundle herdr-dispatch — `herdr agent prompt/wait` allow 정합화

- 작성: ht-planner / 2026-10-20
- 범위: `templates/permissions/bundle/herdr-read.json`, `templates/opencode-agents/ROLE-orchestrator.md`(정합 확인), 저장소 밖 `/home/hm/work/SecondBrain/.opencode/agents/sb-orchestrator.md`(수동 편집), `tests/test_permissions_merge.sh`
- 회신 규약: 경로 + 1줄 요약
- 배경: PM 지시. 오케스트레이터의 위임 프로토콜(`herdr agent prompt --wait` / `agent wait`)이 현재 권한 판정상 `ask`(baseline `"*"` ask)로 막혀 승인 팝업을 유발 → 번들 규칙으로 allow 확정.

---

## 0. 현행 조사 (사실, read-only 확인)

### 0.1 권한 엔진과 병합 순서
- `bin/herdr-team` `permissions_merge_role()`: **baseline permissions → 번들(profile includes 순) → 프로파일 permissions** 를 순차 배열로 합치고 `permissions_judge()` 가 **last-match-wins** 로 판정한다(`tests/test_permissions_merge.sh:26-46` 의 jq 기반 engine_fn 추출 방식으로 검증됨).
- `templates/permissions/baseline.json`: `herdr pane close*` / `herdr pane kill*` 는 **ask** 가 baseline 에도 존재. `herdr agent prompt*`/`wait*` 규칙은 어디에도 없어 현재 baseline `"*"` ask 로 판정된다.
- L3 policies(`shell:sudo *`, `shell:curl * | *` 등)는 prompt/wait 과 리소스가 겹치지 않는다 — 본 변경은 hard-deny 게이트와 무관.

### 0.2 `templates/permissions/bundle/herdr-read.json` (전문 확인)
- `layer: "L0/L2"`, `description: "herdr 조회 allow, pane 종료·중단은 ask (L2)"`.
- 규칙 10건: `agent list/read/get*`, `pane list/read/current*`, `tab list*`, `worktree list*` allow + `pane close*`/`pane kill*` ask. **prompt/wait 규칙 없음.**
- **전 프리셋(dev/research/biz/mkt/creator/pkm) × 전 역할(orchestrator/planner/worker/reviewer/researcher)이 모두 herdr-read 를 includes** (profile/*.json 전수 확인). → 번들에 규칙을 추가하면 **모든 역할에 적용**된다(§2 리스크).

### 0.3 `templates/opencode-agents/ROLE-orchestrator.md`
- V1 frontmatter 권한 맵에 **`"herdr *": allow`** 가 이미 존재(:58) — OpenCode 가 직접 읽는 이 체계에서는 prompt/wait 포함 전 herdr 명령이 이미 allow.
- 본문 위임 프로토콜(:71-84)은 `herdr agent prompt ... --wait`/`agent wait` 사용법과 파이프·연쇄 금지를 이미 상세히 기술. **서술과 권한의 모순은 현재 없다.**
- 따라서 이 파일의 "동기화"는 구조 변경이 아니라 **정합 확인 + 최소 주석** 수준이다(§1-C).

### 0.4 `/home/hm/work/SecondBrain/.opencode/agents/sb-orchestrator.md` (저장소 밖)
- ⚠️ **이 파일은 herdr-team 생성물이 아니라 SecondBrain 프로젝트의 별도 산출물이다. `herdr-team` 시딩 파이프라인이 갱신·덮어쓰지 않으므로 ht-worker 가 직접 수동 편집하는 대상이다.** 템플릿 동기화·회귀 테스트 대상에서 제외된다.
- V2형 순차 배열(`permissions: [{action, resource, effect}]`, last-match wins): 선두 `"*"` ask(:5-7) 이후 개별 allow, **herdr-read 번들 내용의 하드카피 블록**(`herdr agent list*` … `worktree list*` allow, :180-201)과 `pane close*/kill*` ask(:204-207) 존재. **prompt/wait 규칙 없음 → 현재 승인(ask) 필요.**

---

## 1. 변경 설계 (기본안 — PM 지시 고정)

### A. 번들 규칙 추가 — `templates/permissions/bundle/herdr-read.json`
`permissions` 배열에 2건 추가(위치: `worktree list*` allow 직후, `pane close*` ask 이전 — 조회 allow 묶음 유지):
```json
{ "action": "shell", "resource": "herdr agent prompt*", "effect": "allow" },
{ "action": "shell", "resource": "herdr agent wait*", "effect": "allow" }
```
**메타데이터 갱신(정합 필수)**: 쓰기성 동작 포함으로 명칭·서술을 수정한다.
- `layer`: `"L0/L2"` → `"L0/L2 (dispatch 포함)"` — L0 순수 조회 아님을 표기.
- `description`: `"herdr 조회 allow, agent 구동(prompt/wait) 포함, pane 종료·중단은 ask (L2)"`.

### B. 저장소 밖 수동 편집 — `/home/hm/work/SecondBrain/.opencode/agents/sb-orchestrator.md`
- **위치**: herdr-read 하드카피 블록 말미(`herdr worktree list*` allow, :201 직후)에 아래 2건 추가. last-match-wins 이므로 선두 `"*"` ask 를 덮는다.
```yaml
  - action: shell
    resource: "herdr agent prompt*"
    effect: allow
  - action: shell
    resource: "herdr agent wait*"
    effect: allow
```
- 기존 `herdr pane close*/kill*` ask(:204-207)는 리소스가 달라 영향 없음 — 그대로 유지.
- 이 파일은 테스트·시딩 대상이 아니므로 검증은 편집 후 jq/yaml 파싱 가능 여부 수동 확인으로 대체한다.

### C. ROLE-orchestrator.md 정합 (최소)
- 조사 결과(:0.3) V1 맵 `"herdr *": allow` 와 본문 위임 프로토콜은 이미 prompt/wait 을 포괄 — **구조 변경 불필요**.
- 유일한 정합 포인트: 번들이 L0 "조회 전용" 명칭에서 벗어나므로, 본문 권한 근거 설명이 있다면 번들 description 변경과 충돌하지 않는지 확인. 필요 시 worker 가 주석 1행("권한 근거: core-read/git/herdr-read/opencode-api 번들, herdr agent prompt/wait dispatch 포함") 수준만 추가. 본문 절차(§4 위임 명령들) 변경 금지.

---

## 2. 보안 검토 (필수 — PM 지시 4)

### 2.1 명칭 모순: "herdr-**read**" 인데 사실상 쓰기성이다
- `herdr agent prompt <TARGET> "..."` 는 **다른 에이전트에 임의 지시를 주입**한다. 대상 에이전트는 자신의 권한으로 작업을 수행하므로, prompt 는 "그 에이전트의 권한을 빌려 실행하는 간접 실행 프리미티브"다. `agent wait` 은 상태 대기로 피해는 낮지만 프로세스 소비·데드락 유발 가능성이 있다(AGENTS.md 의 EOF 누수 경고).
- 현재 번들 이름 `herdr-read` + `layer: L0/L2` + description "조회 allow" 는 이 동작을 반영하지 못한다 → **기본안(PM 확정)**: 분리 없이 herdr-read 에 추가하고 §1-A 대로 layer/description 을 갱신해 명칭 모순을 제거한다.

### 2.2 대안 (기록용 — 이번에 구현하지 않음)
- **번들 분리**: `herdr-dispatch.json` 신설(prompt/wait allow + layer "L1(구동)"), orchestrator 프로파일만 includes, 그 외 역할 프로파일은 미포함. 장점: 최소 권한 경계 명확. 단점: 6 프리셋×프로파일 includes 수정 + 테스트 번들 목록(:121) 갱신 — 변경 비용이 크고 PM 지시와 불일치.
- **프로파일 오버라이드 완화**: worker/reviewer/researcher 프로파일에 `"herdr agent prompt*": ask` 를 프로파일 permissions 로 추가하면(번들이 프로파일보다 앞이므로) 오케스트레이터만 dispatch 허용이 된다. 필요 시 후속 과제로 채택 가능.

### 2.3 적용 범위 리스크 (반드시 명시 — 기본안의 수용 항목)
- herdr-read 를 includes 하는 **모든 역할(worker/planner/reviewer/researcher)이 임의 에이전트에게 prompt 를 보낼 수 있게 된다.** `templates/AGENTS.md` 의 "Team 간 직접 협업 금지(모든 반송/승인은 PM 경유)"와 "수정 권한은 worker 뿐" 원칙은 **서술상 규칙이지 권한 강제가 아니며**, 본 변경 후 권한은 이 원칙보다 넓다.
- 수용 근거: (a) dispatch 는 오케스트레이터 역할의 핵심 동작이고 ask 가 빈발하면 파이프라인 교착(기존 권한 명세 §a 의 병목 재발), (b) 대상 에이전트의 권한 자체는 여전히 각자의 permission 으로 제한되므로 prompt 로 권한 상승이 연쇄되지 않는다, (c) L3 hard-deny(sudo, curl|sh, force push 등)는 대상 에이전트에서도 유지된다.
- 잔여 리스크: 비오케스트레이터가 다른 역할 pane 에 지시를 주입해 "역할 경계 우회"를 시도할 수 있다. 이는 서술 원칙 위반으로 모니터링 대상이며, 문제가 실측되면 §2.2 의 프로파일 오버라이드로 축소한다.

---

## 3. 테스트 계획 — `tests/test_permissions_merge.sh` (기존 관례 준수)

기존 방식 확인: jq 존재 검사 → `sed` 로 `bin/herdr-team` 의 engine_fn(`permissions_merge_role`, `permissions_judge` 등) 추출해 source → `judge <preset> <role> shell <cmd>` 래퍼로 판정, `assert_equal` 비교(:24-46). **이 관례를 그대로 따른다.** 추가 위치는 기존 "2) 번들 확장" 섹션 뒤, 또는 "6) git push L2 ask 회귀" 스타일의 신규 섹션으로 삽입:

```
== N) herdr dispatch allow + pane 종료 ask 회귀 ==
assert_equal "$(judge dev orchestrator shell 'herdr agent prompt ht-worker "작업 지시" --wait --timeout 600000')" "allow" "herdr_dispatch: orchestrator prompt"
assert_equal "$(judge dev orchestrator shell 'herdr agent wait ht-worker --until idle --timeout 600000')" "allow" "herdr_dispatch: orchestrator wait"
assert_equal "$(judge dev worker shell 'herdr agent prompt ht-reviewer "직접 지시"')" "allow" "herdr_dispatch: worker prompt (범위 리스크 §2.3 회귀 고정)"
assert_equal "$(judge dev reviewer shell 'herdr pane close wT:p1')" "ask" "herdr_read_ask: reviewer pane close"
assert_equal "$(judge dev worker shell 'herdr pane kill wT:p1')" "ask" "herdr_read_ask: worker pane kill"
```
- prompt 인자에 따옴표·공백이 포함된 리소스 문자열도 glob 매칭(`herdr agent prompt*`)으로 allow 되는지가 핵심 판정.
- ask 회귀 2건은 baseline 과 번들 양쪽에 있는 close/kill ask 가 신규 allow 에 의해 덮이지 않음을 고정한다(리소스가 다르므로 정상이지만 회귀로 잠근다).
- 기존 전체 스위트(섹션 1-7)와 `tests/test_permissions_seed.sh` 도 T2 Scoped Regression 으로 실행해 영향 없음을 확인한다.

---

## 4. Task Breakdown (ht-worker — TDD)

| # | 태스크 | 산출 | 테스트 포인트 (TDD) | 기존 스위트 영향 |
|---|---|---|---|---|
| T1 | 번들 규칙 추가 | `herdr-read.json` 에 prompt*/wait* allow 2건 + layer/description 갱신(§1-A) | ① Red: 신규 judge 케이스(prompt/wait allow)가 먼저 실패 ② Green: 번들 수정 후 통과 ③ close/kill ask 회귀 통과 ④ jq 유효성(`jq -e '.permissions|length>0'`) 유지 | 없음 — 신규 assert 추가만. 기존 섹션 1-7 전량 green 유지 |
| T2 | ROLE-orchestrator 정합 확인 | §0.3 근거 기반 확인 결과 기록(주석 1행 이내, 구조 변경 금지) | 본문 위임 프로토콜 명령(`prompt --wait`, `agent wait`)이 번들 allow 로 근거화됨을 확인 — 텍스트 검증 케이스(`grep -F "herdr agent prompt" ROLE-orchestrator.md`) 1건으로 고정 | 없음 |
| T3 | sb-orchestrator 수동 편집 | SecondBrain 파일에 V2 배열 규칙 2건 추가(§1-B, 위치 :201 직후) | 편집 후 (a) YAML 파싱 성공 (b) 새 규칙이 `*` ask 뒤(더 뒤 인덱스)에 위치하는지 순서 확인 (c) close/kill ask 유지 확인 — 저장소 밖 파일이므로 임시 스크립트/수동 확인으로 기록, 회귀 테스트 대상 아님 | 없음 (회귀 대상 아님) |
| T4 | 회귀 테스트 커밋 | `tests/test_permissions_merge.sh` 에 §3 섹션 추가 | T1 의 Red→Green 을 이 파일로만 증명. `tests/test_permissions_seed.sh` 병행 실행해 시딩 산출 무영향 확인 | 없음 — 추가만 |

실행 규정: T1 Fast-Loop 로 신규 케이스 즉시 검증, 태스크 완료 시점에 T2 Scoped Regression(`scripts/testmap.sh` → `tests/test_permissions_merge.sh` + `tests/test_permissions_seed.sh`). blast radius 는 templates/permissions + tests → core.

---

## 5. 엣지 케이스 & 열린 질문
- **prompt 리소스 매칭 경계**: `herdr agent prompt --wait` 처럼 대상 이름이 빈 형태나 `herdr agent prompts`(오타)는 `herdr agent prompt*` glob 에 걸린다(전자는 실제로 매칭 의도, 후자는 미매칭 → ask fallback). 문제 없으나 패턴이 prompt 로 시작하는 미래 하위커맨드까지 포괄함을 인지할 것.
- **`agent wait` 의 무한 대기**: allow 되어도 파이프·연쇄 금지 규칙(AGENTS.md)은 서술상 그대로 — 권한과 운영 규칙은 별개.
- **역할 경계 우회 실측**: §2.3 — worker 가 reviewer 를 직접 prompt 하는 사례가 관측되면 프로파일 ask 오버라이드(§2.2)로 후속 축소. → 열린 질문: 오케스트레이터 전용 분리(herdr-dispatch 신설)를 언제 재검토할지 기준(예: 우회 사례 1건 실측 시).
