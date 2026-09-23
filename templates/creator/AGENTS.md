# Agents Configuration & Team Orchestration (preset: creator)

본 프로젝트의 콘텐츠 창작·출판 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset creator` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 사용자 소통·상위 목표 수립만 담당하고, 파이프라인 오케스트레이션은 `{{PREFIX}}-orchestrator`가 전담합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.
> creator 프리셋은 집필(쓰기 권한)을 위해 `{{PREFIX}}-worker`를 상시 투입하는 체제입니다:
> orchestrator → planner(기획·목차) → worker(초안 집필) → reviewer(교정·교열·팩트체크).
> 출처 수집이 필요하면 PM 승인으로 `{{PREFIX}}-researcher`를 on-demand 기동합니다.

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
   ├─ 1) 기획 지시 ──────► [ {{PREFIX}}-planner ] 기획·목차·톤앤매너·분량
   │        │                    │
   │        ▼ 명세 수령        완료 즉시 다음 연결
   ├─ 2) 집필 지시 ──────► [ {{PREFIX}}-worker ] 초안 집필(비코드 산출물)
   │        │                    │
   │        ▼ 변경사항 전달    완료 즉시 다음 연결
   └─ 3) 검증/리뷰 지시 ──► [ {{PREFIX}}-reviewer ] ── [APPROVE + 검증 로그] ──► Orchestrator → PM 보고
                                │
                                └── [REQUEST CHANGES + 보완 항목] ──► {{PREFIX}}-worker로 즉시 반송 (Orchestrator 중재)
```

- **On-Demand 에이전트**: `{{PREFIX}}-researcher`(출처 수집), `{{PREFIX}}-ops`(인프라)는
  PM이 필요 시에만 기동합니다 (승인 범위 내).
- **Team 간 직접 협업 금지**: worker ↔ reviewer는 서로 직접 prompt하지 않습니다.
  모든 반송/승인은 Orchestrator(필요 시 PM)를 경유합니다.
- **수정 권한**: 집필·수정 반영은 `{{PREFIX}}-worker`가 담당합니다(작성 권한). `{{PREFIX}}-reviewer`는 교정·교열·팩트체크 판정만 하고 직접 수정하지 않습니다.
- **역할 강제**: 각 역할 pane은 `.opencode/agents/{{PREFIX}}-<role>.md` agent(`--agent {{PREFIX}}-<role>`)로 시작되어 규칙·권한이 시스템 프롬프트로 고정됩니다. 상세 지침 정본은 `agents/{{PRESET}}/{{PREFIX}}-<role>.md`.

### 1.1 ⚠️ 가드레일 (Strict Guardrails for PM & Orchestrator)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, 테스트/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log` 취합 보고.
2. **역할 위임 고정**:
   - 기획/목차 → `{{PREFIX}}-planner`, 집필/수정 반영 → `{{PREFIX}}-worker`,
     검증 겸 리뷰(교정·팩트체크) → `{{PREFIX}}-reviewer`.
3. **오케스트레이션 전담 (Orchestrator)**: 요구사항 분석, 프롬프트 전송(`herdr agent prompt`), 상태 확인(`herdr agent read`), 산출물 중계, 결과 종합 보고.
   - ❌ `sleep` 폴링 쉘 루프 작성 절대 금지.
   - ❌ `herdr` 명령 뒤에 `| tail`, `| head`, `| grep` 등 파이프라인 필터 절대 금지 (표준입력 EOF 누수로 서브쉘 무한 Hang 발생).
   - ⚠️ **절대 한 줄에 여러 명령어 실행 금지**: 세미콜론(`;`), `&&`, `||`, 파이프(`|`), 백그라운드(`&`)로 `herdr`를 다른 명령어와 엮지 말고 반드시 **한 줄에 오직 하나의 단독 명령어**로만 실행.
   - ✅ 반드시 1번에 1개의 `herdr` 명령만 단독 실행: `herdr agent prompt <TARGET> "..." --wait` (완료 동기화) 또는 `herdr agent wait <TARGET> --until idle` (비동기 프롬프트 전용, 예외 경로).
   - 🔁 **중복 대기 금지 (No Redundant Wait)**: `herdr agent prompt <TARGET> "..." --wait` 는 대상이 settle(idle/done/blocked)될 때까지 블로킹하는 완료 동기화다(반환 시점에 대상은 이미 settle). 그 직후 `herdr agent wait <TARGET> --until idle` 을 절대 호출하지 말고, 반환 즉시 `herdr agent read <TARGET> --lines <N>` 으로 산출물을 읽는다.
   - ✅ `herdr agent wait` 는 `--wait` 없이 보낸 비동기(fire-and-forget) 프롬프트에만 사용한다(예외 경로 전용). `--wait` 가 타임아웃으로 반환된 경우에도 `wait` 재호출 금지 — `herdr agent read` 로 현재 상태·원인을 확인한 뒤 재지시/중계한다.
   - ℹ️ 중복 대기 금지는 "절대 한 줄에 여러 명령어 실행 금지"(단일 명령 불변식)와 별개의 독립 규칙이며, 기존 규칙을 대체하지 않는다.
   - ⚠️ **`--until` 단일 상태값**: `--until` 은 상태 **하나만** 받는다. `--until idle,done` 처럼 콤마로 나열하면 `invalid agent status` 에러다. 여러 상태를 기다리려면 플래그를 반복(`--until idle --until done`)하거나 `--until` 을 생략한 `herdr agent wait <TARGET>`(기본: idle/done/blocked 매칭)을 쓴다.
4. **무방치 원칙 (Orchestrator)**: 각 에이전트가 작업 완료 후 idle로 방치되지 않도록 완료 즉시 다음 단계를 연결합니다.

---

## 2. 창작 파이프라인 역할

| 역할 | 담당 | 산출물 |
|---|---|---|
| `{{PREFIX}}-planner` | 기획 | 기획안, 목차, 톤앤매너, 분량·마감 |
| `{{PREFIX}}-worker` | 집필 | 초안 원고, 수정 반영 (비코드 산출물 — TDD/단위 테스트가 아닌 초안→피드백 반복) |
| `{{PREFIX}}-reviewer` | 검증 | 교정·교열, 팩트체크, 표현·표절 리스크, [APPROVE]/[REQUEST CHANGES] |
| `{{PREFIX}}-researcher` (on-demand) | 출처 수집 | 인용·근거 자료 |

---

## 3. 첫 프롬프트 예

1. "전자책 목차 잡고 1장 초안" → planner(목차/톤) → worker(초안) → reviewer(교정·팩트체크).
2. "연재 블로그 3편 교정·팩트체크" → worker(수정 반영) → reviewer(출처 검증/표절 리스크).
