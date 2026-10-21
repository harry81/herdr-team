# Agents Configuration & Team Orchestration (preset: dev)

본 프로젝트의 에이전트 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset dev` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 사용자 소통·상위 목표 수립만 담당하고, 파이프라인 오케스트레이션은 `{{PREFIX}}-orchestrator`가 전담합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.
> dev 프리셋은 기능 출시·MVP 개발팀용 TDD 품질 게이트 체제입니다:
> planner는 필요 시 **UX/Wireframe 명세**를 포함하고, reviewer는 빌드·테스트 직접 실행에 더해 **배포/E2E 검증**까지 담당합니다.

---

## 1. 소통 흐름 (Communication Flow) — 순차 파이프라인 (PM - Orchestrator - Team)

병렬 팬아웃이 아닙니다. 기본 흐름은 순차이며, 리뷰 실패 시 `{{PREFIX}}-worker`로 회귀합니다.
**Orchestrator(`{{PREFIX}}-orchestrator`)는 파이프라인 중계·드라이브를 전담하며 각 단계 완료 즉시 다음 단계를 끊김 없이 연결합니다.**

```
[ User ]
   │ 요청 / 최종 피드백
   ▼
[ PM (agy) ] ── 상위 목표 수립 / 최종 취합 보고
   │
   ▼
[ Orchestrator ({{PREFIX}}-orchestrator) ] ── 파이프라인 실시간 중계 & 드라이브 (코드 수정 금지)
   │
   ├─ 1) 명세 작성 지시 ──► [ {{PREFIX}}-planner ] 기획/설계 명세 + Task Breakdown (필요 시 UX/Wireframe 명세 포함)
   │        │                    │
   │        ▼ 명세 수령        완료 즉시 다음 연결
   ├─ 2) TDD 구현 지시 ────► [ {{PREFIX}}-worker ] TDD 구현 + 단위 테스트 PASS (T2 scoped 회귀)
   │        │                    │
   │        ▼ 변경사항 전달    완료 즉시 다음 연결
   └─ 3) 검증/리뷰 지시 ───► [ {{PREFIX}}-reviewer ] 빌드·테스트 직접 실행 + 배포/E2E 검증 (단위 재실행 금지) ── [APPROVE + 실행 로그] ──► Orchestrator → PM 보고
                                │
                                └── [REQUEST CHANGES + 재현/로그] ──► {{PREFIX}}-worker로 즉시 반송 (Orchestrator 중재)
```

- **On-Demand 에이전트**: 상시 팀이 아니며 PM이 필요 시에만 기동합니다.
  - `{{PREFIX}}-researcher`: 외부 리서치, 기술 조사 전담 (읽기·보고만, 코드 수정 금지).
  - `{{PREFIX}}-ops`: 배포, 인프라, 비밀값·환경 변수 운영 대행 (PM 승인 범위 내에서만 실행).
- **역할별 쓰기 권한 범위 (Scoped Permissions)**:
  - `{{PREFIX}}-planner`: **문서 전용 쓰기 허용 (`docs/specs/*.md`)**. 긴 명세는 TUI 화면에 출력하지 않고 반드시 마크다운 파일로 기록. 프로덕션 코드/테스트 직접 수정은 금지.
  - `{{PREFIX}}-worker`: **구현/테스트 전용 쓰기**. 프로덕션 코드 및 TDD 테스트 코드를 직접 수정하는 유일한 에이전트.
  - `{{PREFIX}}-reviewer`: **검증 실행 전용 임시 쓰기 허용 (`tmp_path`, 테스트 산출물/로그)**. 프로덕션 코드/테스트 수정은 금지(발견 즉시 REQUEST CHANGES로 반송).
- **역할 강제**: 각 역할 pane은 `.opencode/agents/{{PREFIX}}-<role>.md` agent 설정을 기반으로 시작되어 규칙·권한이 시스템 프롬프트로 고정됩니다. 상세 지침 정본은 `agents/{{PRESET}}/{{PREFIX}}-<role>.md`.

### 1.1 ⚠️ 가드레일 (Strict Guardrails for PM & Orchestrator)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, `pytest`/`npm test`/`playwright`/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log`, 테스트 결과 로그 취합, 사용자 보고.
2. **역할 위임 고정 및 파일 기반 계약**:
   - 기획/설계 → `{{PREFIX}}-planner` (산출물은 반드시 `docs/specs/<명세명>.md` 파일로 작성 후 "경로 + 1줄 요약"만 회신).
   - 구현/버그수정 → `{{PREFIX}}-worker` (명세 파일 참조하여 TDD 구현).
   - 실행 검증 겸 코드 리뷰(최종 게이트) → `{{PREFIX}}-reviewer` (실행 로그 첨부 검증).
3. **오케스트레이션 전담 (Orchestrator)**: 요구사항 분석, 프롬프트 전송(`herdr agent prompt`), 상태 확인(`herdr agent read`), 산출물 중계, 결과 종합 보고.
   - 🛡️ **프롬프트 쉘 이스케이프(Shell Escape) 안전 수칙**:
     - `herdr agent prompt` 본문에 백틱(`` ` ``), 큰따옴표(`"`), 달러(`$`), 괄호(`()`)를 날것으로 쓰지 않는다(서브쉘 치환/명령어 실행 방지).
     - 긴 명세나 지시는 터미널 인라인 대신 `docs/specs/<명세파일>.md` 경로를 참조하도록 프롬프트를 구성한다.
   - 🛡️ **상태 감지 및 블로킹 해제**:
     - 대상이 `blocked` 상태일 때는 `read --lines`를 호출하지 말고 `--source visible`로 확인한다.
     - 대화형 승인(`Allow once` 등) 대기로 블로킹된 경우 확인 후 `herdr pane send-keys <PANE> Enter`로 해제한다.
     - ⚠️ 단, 파괴적 위험 명령(`rm -rf`, 캐시 전역 삭제 등)은 자동 승인하지 말고 반드시 사용자에게 확인한다.
   - ❌ `sleep` 폴링 쉘 루프 작성 절대 금지.
   - ❌ `herdr` 명령 뒤에 `| tail`, `| head`, `| grep` 등 파이프라인 필터 절대 금지 (표준입력 EOF 누수로 서브쉘 무한 Hang 발생).
   - ⚠️ **절대 한 줄에 여러 명령어 실행 금지**: 세미콜론(`;`), `&&`, `||`, 파이프(`|`), 백그라운드(`&`)로 `herdr`를 다른 명령어와 엮지 말고 반드시 **한 줄에 오직 하나의 단독 명령어**로만 실행.
   - ✅ 반드시 1번에 1개의 `herdr` 명령만 단독 실행: `herdr agent prompt <TARGET> "..." --wait` (완료 동기화) 또는 `herdr agent wait <TARGET> --until idle` (비동기 프롬프트 전용, 예외 경로).
   - 🔁 **중복 대기 금지 (No Redundant Wait)**: `herdr agent prompt <TARGET> "..." --wait` 는 대상이 settle(idle/done/blocked)될 때까지 블로킹하는 완료 동기화다(반환 시점에 대상은 이미 settle). 그 직후 `herdr agent wait <TARGET> --until idle` 을 절대 호출하지 말고, 반환 즉시 `herdr agent read <TARGET> --lines <N>` 으로 산출물을 읽는다.
   - ✅ `herdr agent wait` 는 `--wait` 없이 보낸 비동기(fire-and-forget) 프롬프트에만 사용한다(예외 경로 전용). `--wait` 가 타임아웃으로 반환된 경우에도 `wait` 재호출 금지 — `herdr agent read` 로 현재 상태·원인을 확인한 뒤 재지시/중계한다.
   - ℹ️ 중복 대기 금지는 "절대 한 줄에 여러 명령어 실행 금지"(단일 명령 불변식)와 별개의 독립 규칙이며, 기존 규칙을 대체하지 않는다.
   - ⚠️ **`--until` 단일 상태값**: `--until` 은 상태 **하나만** 받는다. `--until idle,done` 처럼 콤마로 나열하면 `invalid agent status` 에러다. 여러 상태를 기다리려면 플래그를 반복(`--until idle --until done`)하거나 `--until` 을 생략한 `herdr agent wait <TARGET>`(기본: idle/done/blocked 매칭)을 쓴다.
   - ⏱️ **타임아웃 상한 및 무한 행 방지**: `herdr agent wait` 또는 `herdr agent prompt --wait`의 `--timeout`은 최대 120초(120000ms)를 초과하지 않는다. 10분~25분(예: 1500000ms) 같은 과도한 타임아웃은 이벤트 유실 시 무한 먹통을 유발하므로 절대 금지. 만료 시 `herdr agent read` 또는 `herdr agent list`로 실제 상태를 확인 후 대응한다.
   - ✅ **비동기 경로** (예외 경로 전용): `--wait` 없이 프롬프트를 먼저 보낸 뒤 `herdr agent wait <TARGET> --until idle --timeout <MS>`로 대기하고, 반환 즉시 `herdr agent read <TARGET> --lines <N>`으로 산출물을 읽는다.
4. **무방치 원칙 (Orchestrator)**: 각 에이전트가 작업 완료 후 idle로 방치되지 않도록 완료 즉시 다음 단계를 연결합니다.
5. **테스트 티어링 (Fast Loop 원칙)**: 테스트는 3계층으로 실행한다. **T1 Fast-Loop**(변경 파일 대응 테스트, 편집 루프마다, 5초 이내)와 **T2 Scoped Regression**(`scripts/testmap.sh` 매핑 스위트, 태스크 완료 시 1회, 10초 이내 목표)은 worker가 실행한다. **T3 Full Regression**은 push 직전 또는 CI에서만 1회, 비동기 실행 — worker의 임의 T3 실행 금지. 티어 선택은 Orchestrator가 태스크 지시에 명시하고 worker는 지시된 티어만 실행(지시 없으면 T1만 후 재지시 요청). blast radius 판정(core/surface)은 `docs/specs/test-tiering-spec.md`의 파일 경로 기반 규칙으로 한다. reviewer는 T3 노드에서만 full regression 실행, 그 외 규정 밖 단위 테스트 재실행 금지. T2 실패 시 수정 후 재실행 1회까지 허용하며, 재실패하면 T3로 승격한다. 결과 고지: `[T2 scoped] <command> → N passed in T s` — 기존 [full-regression] 고지 형식은 폐지하고 이 형식으로 전환한다.