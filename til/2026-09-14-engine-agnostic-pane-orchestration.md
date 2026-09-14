# TIL: 페인 라벨 기반 팀원 식별과 엔진 독립적 오케스트레이션 (2026-09-14)

## 1. 이기종 멀티 에이전트(Heterogeneous Multi-Agent) 환경에서의 정체성(Identity) 식별 문제

멀티 에이전트 협업 시스템에서 팀원 식별을 특정 에이전트 런타임의 CLI 도구(`herdr agent list` 등)에만 의존할 경우 다음과 같은 한계가 발생한다:
1. **런타임 결합(Coupling)**: 팀원의 실행 엔진이 `opencode`에서 `agy`, `claude-code`, 기타 커스텀 TUI 에이전트로 전환되거나 혼용될 때 에이전트 등록/조회 인터페이스가 달라져 오케스트레이터가 혼선을 겪음.
2. **상태 불일치(State Desynchronization)**: 에이전트 데몬이나 서브프로세스가 재시작되거나 비정상 종료 후 복구될 때 세션 식별자가 유실되거나 달라질 위험이 있음.

### 해결책: 하위 터미널 페인 라벨(Pane Label)을 1차 식별자로 활용

| 계층 | 식별 기준 | 특징 및 역할 |
| :--- | :--- | :--- |
| **인프라 계층 (Herdr / Pane)** | **`herdr pane list` 페인 라벨** (예: `hts-planner`, `hts-worker`) | • **1차 식별자 (Source of Truth)**<br>• 실행 엔진 종류와 무관하게 고정된 역할 정체성 부여<br>• 엔진이 교체되거나 TUI가 바뀌어도 터미널 페인은 유지됨 |
| **런타임 계층 (Agent Engine)** | `herdr agent list` 에이전트 세션 | • 2차 보조 수단<br>• 실행 상태, 프롬프트 전송 인터페이스 연결에 활용 |

---

## 2. 엔진 독립적 오케스트레이션 (Engine Agnostic Orchestration) 가드레일

* **식별 기준 일원화**:
  * Task Manager는 작업을 지시하거나 상태를 확인할 때 페인의 라벨(Label)을 기준으로 각 팀원(Planner, Worker, Reviewer)을 매핑한다.
* **엔진 전환 대응성(Flexibility)**:
  * 특정 팀원이 `opencode` 대신 `agy`나 다른 AI CLI 엔진으로 구동되더라도, Task Manager는 페인 라벨을 신뢰하고 각 엔진의 인터페이스(TUI 큐, 프롬프트 입력창 등)에 맞춰 작업을 위임한다.
* **결합도 완화**:
  * 오케스트레이션 규칙(`AGENTS.md`, `hts-taskmanager.md`)에 Engine Agnostic 원칙을 명시함으로써, 팀 구성 변경 시 오케스트레이션 파이프라인의 수정 없이 엔진 교체가 가능해짐.
