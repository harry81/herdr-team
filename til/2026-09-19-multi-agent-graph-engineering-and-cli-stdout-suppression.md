# Today I Learned: 멀티에이전트 그래프 엔지니어링(Graph Engineering)과 CLI stdout 억제 패턴

- **날짜**: 2026-09-19
- **작성자**: PM / Orchestration Team
- **범위**: `herdr-team` (`bin/herdr-team`, `tests/test_preset.sh`, 팀 아키텍처 이론)

---

## 1. 이론: Multi-Agent 시스템에서의 Graph Engineering

### 1) 왜 이 구조가 Graph Engineering인가?
Herdr 팀의 5인 체제(`PM` – `Orchestrator` – `Planner` – `Worker` – `Reviewer`)는 단순 일자형(Linear) 파이프라인이 아니라, 명확한 노드(Node), 에지(Edge), 상태(State), 조건부 루프(Cycle)를 갖춘 **유향 순환 그래프(Directed Cyclic Graph, DCG)**입니다.

| 그래프 구성 요소 | Herdr 에이전트 팀 구현체 | 설명 |
| :--- | :--- | :--- |
| **Node (실행 단위)** | `PM`, `Orchestrator`, `Planner`, `Worker`, `Reviewer` | 고유한 역할(System Prompt)과 권한을 지닌 독립 격리 노드 |
| **Controller Node (중앙 라우터)** | `Orchestrator` | 노드 간 상태 전이와 산출물 중계를 총괄하는 Supervisor 노드 |
| **Directed Edge (방향 에지)** | 팀원 간 단계별 핸드오프 흐름 | `PM → Orchestrator → Planner → Worker → Reviewer` |
| **Conditional Edge (조건부 분기)** | `Reviewer`의 판정 결과 | 검증 성공(`[APPROVE]`) 또는 실패(`[REQUEST CHANGES]`)에 따른 전이 |
| **Cycle / Feedback Loop (회귀 루프)** | Reviewer ➔ Orchestrator ➔ Worker | 검증 불합격 시 수정 사항을 가지고 Worker 노드로 되돌아가는 자가 치유 루프 |
| **State (전역 상태)** | Git 작업 트리, 명세 및 검증 로그 | 각 노드가 갱신하고 참조하는 공유 컨텍스트 |

### 2) 인메모리 그래프(LangGraph) vs OS/터미널 분산 그래프(Herdr)
* **LangGraph / LlamaIndex Workflow**: 단일 Python 프로세스 메모리 상에서 함수나 LLM 호출을 상태 머신으로 엮음.
* **Herdr Multi-Agent Graph**: 실제 OS 터미널 및 프로세스 레벨에서 다양한 엔진(`agy`, `opencode` 등)을 물리적 노드로 배치하고, 셸 IPC와 TUI 이벤트로 결합한 **분산 멀티에이전트 그래프 아키텍처**.

### 3) 일반 사용자(범용 업무) 확장 가능성
개발 도메인뿐 아니라 보고서 작성, 시장 조사, 마케팅, 법률/세무 검토 등 일반 지식 노동 업무에서도 **기획(Planner) ➔ 실행(Worker) ➔ 감수/검증(Reviewer)** 프로세스를 Supervisor(Orchestrator)가 주도함으로써 단일 LLM의 조기 종료와 환각(Hallucination)을 원천 차단할 수 있음.

---

## 2. 실무: CLI 안전 실행을 위한 stdout 억제 패턴 (`run_quiet`)

### 1) 문제 상황
`ht`(`herdr-team`) 구동 시, 내부에서 호출하는 `herdr pane rename` 명령의 성공 JSON 출력이 표준 출력(stdout)으로 여과 없이 터미널에 노출됨:
```json
{"id":"cli:pane:rename","result":{"pane":{"agent_status":"unknown","cwd":"/home/hm/work/projects/herdr-team","label":"① PM", ...}},"type":"pane_info"}
```
사용자에게 불필요한 CLI 내부 프로토콜 JSON이 노출되어 시각적 노이즈 및 혼란을 유발함.

### 2) 해결 및 최소 Diff 원칙
별도의 새로운 함수 추상화(`run_quiet`)를 늘리기보다, 모든 명령어 실행의 단일 창구인 `bin/herdr-team`의 `run()` 함수를 수정하여 최소한의 diff(1줄)로 해결함.

- **As-Is**:
  ```bash
  run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '+ %s\n' "$*"
    else
      "$@"
    fi
  }
  ```
- **To-Be**:
  ```bash
  run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '+ %s\n' "$*"
    else
      "$@" >/dev/null
    fi
  }
  ```

### 3) 안전성 보장 핵심 포인트
1. **stdout 억제**: 정상 실행 시의 장황한 JSON 출력을 숨김.
2. **stderr 보존**: `>/dev/null`은 표준 출력만 억제하므로, 오류 발생 시 `stderr`는 터미널에 그대로 노출되어 디버깅 가능.
3. **종료 코드(Exit Code) 전파**: 래퍼가 종료 코드를 가로채지 않아 에러 발생 시 `set -e` 정책에 따라 스크립트가 안전하게 중단됨.
4. **`--dry-run` 불변**: `DRY_RUN=1`일 때의 `+ <명령>` 출력 시맨틱 유지.

---

## 3. 검증 (TDD)
[`tests/test_preset.sh`](../tests/test_preset.sh)에 섹션 36을 추가하여:
1. `run()` 단위 테스트: 성공 시 stdout 미노출, stderr 출력 보존, 비정상 exit code 전파, dry-run 출력 검증.
2. Fake `herdr` 스텁 기반 E2E 검증: `pane rename` 시 JSON 미노출 및 stderr 마커 검출 확인.
3. 기존 3개 테스트 스위트 전체 회귀 검증: **PASS=371, FAIL=0**.
