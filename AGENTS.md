# Agents Configuration & Team Orchestration

본 프로젝트의 에이전트 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team hts` 실행 시 `hts`에 실제 프로젝트 prefix가 치환됩니다.
레거시 `herdr-team-setup` 명령도 100% 호환됩니다.)

> 전제: PM(`agy`)은 사용자 소통·상위 목표 수립만 담당하고, 파이프라인 오케스트레이션은 `hts-taskmanager`가 전담합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.

---

## 1. 소통 흐름 (Communication Flow) — 순차 파이프라인 (PM - Task Manager - Team)

병렬 팬아웃이 아닙니다. 기본 흐름은 순차이며, 리뷰 실패 시 `hts-worker`로 회귀합니다.
**Task Manager(`hts-taskmanager`)는 파이프라인 중계·드라이브를 전담하며 각 단계 완료 즉시 다음 단계를 끊김 없이 연결합니다.**

```
[ User ]
   │ 요청 / 최종 피드백
   ▼
[ PM (agy) ] ── 상위 목표 수립 / 최종 취합 보고
   │
   ▼
[ Task Manager (hts-taskmanager) ] ── 파이프라인 실시간 중계 & 드라이브 (코드 수정 금지)
   │
   ├─ 1) 명세 작성 지시 ──► [ hts-planner ] 기획/설계 명세 + Task Breakdown
   │        │                    │
   │        ▼ 명세 수령        완료 즉시 다음 연결
   ├─ 2) TDD 구현 지시 ────► [ hts-worker ] TDD 구현 + 단위 테스트 PASS
   │        │                    │
   │        ▼ 변경사항 전달    완료 즉시 다음 연결
   └─ 3) 검증/리뷰 지시 ───► [ hts-reviewer ] ── [APPROVE + 실행 로그] ──► Task Manager → PM 보고
                                │
                                └── [REQUEST CHANGES + 재현/로그] ──► hts-worker로 즉시 반송 (Task Manager 중재)
```

- **On-Demand 에이전트**: 상시 팀이 아니며 PM이 필요 시에만 기동합니다.
  - `hts-researcher`: 외부 리서치, 기술 조사, 라이브러리/SDK 내부 탐사 전담 (읽기·보고만, 코드 수정 금지).
  - `hts-ops`: 배포, 인프라, 비밀값·환경 변수 운영 대행 (PM 승인 범위 내에서만 실행).
- **사용자 ↔ PM**: 요구사항 전달, 상위 목표 수립, 진행 상황 보고 및 확인
- **PM ↔ Task Manager**: PM은 직접 코드를 쓰지 않고 목표만 전달하며, `hts-taskmanager`가 `herdr agent prompt`로 팀에 위임하고 `herdr agent read/list`로 취합합니다.
- **Team 간 직접 협업 금지**: worker ↔ reviewer는 서로 직접 prompt하지 않습니다. 모든 반송/승인은 Task Manager(필요 시 PM)를 경유합니다. on-demand 에이전트도 PM 경유 없이 팀에 직접 개입하지 않습니다.
- **수정 권한**: 코드를 직접 수정하는 것은 `hts-worker`뿐입니다. `hts-taskmanager`/`hts-reviewer`/`hts-researcher`는 수정하지 않고 보고서만 냅니다 (`hts-ops`는 승인된 운영 범위만 예외).

### 1.1 ⚠️ 가드레일 (Strict Guardrails for PM & Task Manager)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, `pytest`/`npm test`/`playwright`/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log`, 테스트 결과 로그 취합, 사용자 보고.
2. **역할 위임 고정**:
   - 기획/설계 → `hts-planner`, 구현/버그수정 → `hts-worker`, 실행 검증 겸 코드 리뷰(최종 게이트) → `hts-reviewer`.
   - 리서치/조사 → `hts-researcher` (on-demand), 배포/인프라/비밀값 → `hts-ops` (on-demand, 승인 범위 내).
3. **오케스트레이션 전담 (Task Manager)**: 요구사항 분석, 프롬프트 전송(`herdr agent prompt`), 상태 모니터링(`herdr agent wait/read`), 산출물 중계, 결과 종합 보고.
4. **무방치 원칙 (Task Manager)**: 각 에이전트가 작업 완료 후 idle로 방치되지 않도록 완료 즉시 다음 단계를 연결합니다.

---

## 2. 에이전트 역할 및 세부 지침

각 에이전트의 책임, 행동 원칙, 산출물 양식은 아래 문서를 정본으로 합니다. Pane ID는 세션마다 바뀌므로 문서에 고정값을 적지 않습니다.

| 에이전트 명 | 역할 (Role) | 엔진 | 상세 지침 문서 | 주요 업무 |
|------------|------------|------|----------------|----------|
| **PM** | 총괄 프로젝트 매니저 | `agy` | 본 문서 | 사용자 소통, 상위 목표 수립, 최종 취합 보고 |
| **hts-taskmanager** | 파이프라인 오케스트레이터 | `opencode` | [`hts-taskmanager.md`](agents/hts-taskmanager.md) | 순차 파이프라인 중계·드라이브, 위임·모니터링·산출물 중계 |
| **hts-planner** | 기획 및 아키텍처 설계 | `opencode` | [`hts-planner.md`](agents/hts-planner.md) | 기능 명세, 데이터 흐름 설계, Task Breakdown |
| **hts-worker** | 개발 및 단위 테스트 구현 | `opencode` | [`hts-worker.md`](agents/hts-worker.md) | TDD 기반 구현, 비즈니스 로직 작성, 단위 테스트 통과 |
| **hts-reviewer** | 실행 검증 겸 코드 리뷰 (최종 게이트) | `opencode` | [`hts-reviewer.md`](agents/hts-reviewer.md) | 빌드/단위/통합·E2E·회귀 직접 실행, [APPROVE]/[REQUEST CHANGES] 판정 |
| *`hts-researcher`* (on-demand) | 기술 조사·외부 리서치 | `opencode` | PM 지시 시 기동 | 읽기·보고만, 코드 수정 금지 |
| *`hts-ops`* (on-demand) | 배포·인프라·비밀값 운영 | `opencode` | PM 승인 범위 내 기동 | 배포/인프라 운영 대행 |

> `hts-qa.md`는 삭제됨. 통합/E2E/회귀 검증은 `hts-reviewer`의 실행 검증 의무로 통합.

> 역할 주입: Task Manager가 각 에이전트에게 첫 prompt를 보낼 때 반드시 `agents/hts-*.md를 읽고 그 형식을 따라라`고 지시합니다 (템플릿은 §5 참조). 에이전트 시작만으로는 역할이 고정되지 않습니다.

> 작업 디렉토리 주의: 4인 체제라도 동일 `$PWD`에 동시 쓰기를 두면 파일 충돌·테스트 간섭이 발생합니다. 기본은 **순차 실행**(한 번에 1명만 쓰기)으로 운용하고, 병렬이 필요하면 `herdr worktree create`로 분리합니다.

---

## 3. Herdr 환경 구성 (Setup — 복사-붙여넣기용)

원칙:
- `wD:p2` 같은 고정 Pane ID 사용 금지. `herdr pane/tab/agent list`로 조회합니다.
- `herdr agent start`는 **빈 shell prompt pane**에서만 성공합니다. 이미 에이전트가 뜬 pane에 재실행하지 않습니다.
- 4인 균등 분할 권장: 새 탭을 만들고 1열(Task Manager) + 2행(Planner/Worker/Reviewer) 혼합으로 균등 배치합니다. 한 컬럼에 3개 이상 `down` 분할 금지 (가독성 붕괴).
- 원클릭 셋업: `herdr-team hts` (상세는 [README](../README.md) 참조).

```bash
# 0. 현황 조회 (고정 ID 가정 금지)
herdr agent list
herdr tab list
herdr pane list

# 1. 팀용 새 탭 생성 (workspace는 현재 프로젝트의 ID로 교체, 예: wD)
herdr tab create --cwd "$PWD" --label "hts-team" --no-focus
# -> TAB_ID 확인 (herdr tab list)

# 2. 4인 균등 분할: BASE → right(Task Manager) → down(Planner) → down(Worker) → down(Reviewer)
# herdr pane split [PANE_ID] --direction right|down --cwd "$PWD" --no-focus
P_TASK=$(herdr pane split <BASE_PANE> --direction right --cwd "$PWD" --no-focus)
P_PLANNER=$(herdr pane split $P_TASK --direction down --cwd "$PWD" --no-focus)
P_WORKER=$(herdr pane split $P_PLANNER --direction down --cwd "$PWD" --no-focus)
P_REVIEWER=$(herdr pane split $P_WORKER --direction down --cwd "$PWD" --no-focus)
# 우측 컬럼이 좁으면 BASE 하단에 down 분할로 2x2 유사 배치도 가능. on-demand(researcher/ops)는 별도 탭 또는 reviewer 완료 후 pane 재사용 (동시 쓰기 방지)

# 3. 빈 pane에만 에이전트 시작 (멱등: list에 있으면 start 생략)
herdr agent list | grep -q hts-taskmanager || herdr agent start hts-taskmanager --kind opencode --pane "$P_TASK"
herdr agent list | grep -q hts-planner || herdr agent start hts-planner --kind opencode --pane "$P_PLANNER"
herdr agent list | grep -q hts-worker || herdr agent start hts-worker --kind opencode --pane "$P_WORKER"
herdr agent list | grep -q hts-reviewer || herdr agent start hts-reviewer --kind opencode --pane "$P_REVIEWER"
# on-demand(researcher/ops)도 필요 시점에 동일 패턴으로 시작

# 4. 표시용 라벨 (pane label과 agent 이름은 별개)
herdr pane rename "$P_TASK" "② Task Manager (hts-taskmanager)"
herdr pane rename "$P_PLANNER" "③ Planner (hts-planner)"
herdr pane rename "$P_WORKER" "④ Worker (hts-worker)"
herdr pane rename "$P_REVIEWER" "⑤ Reviewer (hts-reviewer)"
herdr agent rename hts-taskmanager "hts-taskmanager"
herdr agent rename hts-planner "hts-planner"
herdr agent rename hts-worker "hts-worker"
herdr agent rename hts-reviewer "hts-reviewer"
```

---

## 4. Task Manager의 에이전트 제어 (Herdr CLI + 프롬프트 템플릿)

타임아웃 가이드 (기존 일괄 120초는 worker/reviewer에 부족):
- planner: `--timeout 180000`
- worker: `--timeout 600000` (구현 분량에 따라 연장)
- reviewer (실행 검증 포함): `--timeout 600000`

`--wait`는 상태 변화를 한 번만 감지하므로, 장시간 작업은 `wait` + `read`로 폴링합니다.

```bash
# 작업 지시 (역할 문서 주입을 첫 줄에 포함)
herdr agent prompt hts-planner "agents/hts-planner.md를 읽고 그 산출물 형식을 따르라. ..." --wait --timeout 180000
herdr agent prompt hts-worker "agents/hts-worker.md를 따르라. TDD Red→Green→Refactor, ... " --wait --timeout 600000
herdr agent prompt hts-reviewer "agents/hts-reviewer.md를 따르라. [APPROVE]/[REQUEST CHANGES]로 판정, ..." --wait --timeout 600000

# 상태 확인 / 출력 읽기 / 대기
herdr agent list
herdr agent read hts-worker --lines 100
herdr agent wait hts-worker --timeout 600000

# 실패 시 패턴 (timeout / blocked)
herdr agent read hts-worker --lines 200   # 원인 확인 후
herdr agent prompt hts-worker "이어서 계속하라. ..." --wait --timeout 600000
```

프롬프트 템플릿 (Task Manager → Team 공통):

```
agents/<role>.md를 읽고 그 역할·산출물 형식을 따르라.
[배경] ... (요구사항, 관련 파일 경로)
[작업] ... (할 일 N개, 완료 기준 명시)
[제약] ... (수정 가능 범위, TDD/보고 형식)
[출력] ... (해당 role 문서의 Report Format 그대로)
```