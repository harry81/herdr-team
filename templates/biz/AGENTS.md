# Agents Configuration & Team Orchestration (preset: biz)

본 프로젝트의 기획/조사 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset biz` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 사용자 소통·상위 목표 수립만 담당하고, 파이프라인 오케스트레이션은 `{{PREFIX}}-taskmanager`가 전담합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.
> biz 프리셋은 코드 구현(worker) 대신 조사(researcher) 중심 체제입니다:
> taskmanager(오케스트레이션) → planner(기획) → researcher(조사) → reviewer(검증).

---

## 1. 소통 흐름 (Communication Flow) — 순차 파이프라인 (PM - Task Manager - Team)

병렬 팬아웃이 아닙니다. 기본 흐름은 순차이며, 리뷰 실패 시 `{{PREFIX}}-researcher`로 회귀합니다.
**Task Manager(`{{PREFIX}}-taskmanager`)는 파이프라인 중계·드라이브를 전담하며 각 단계 완료 즉시 다음 단계를 끊김 없이 연결합니다.**

```
[ User ]
   │ 요청 / 최종 피드백
   ▼
[ PM (agy) ] ── 상위 목표 수립 / 최종 취합 보고
   │
   ▼
[ Task Manager ({{PREFIX}}-taskmanager) ] ── 파이프라인 실시간 중계 & 드라이브 (코드 수정 금지)
   │
   ├─ 1) 기획 지시 ──────► [ {{PREFIX}}-planner ] 기획/요구사항 명세 + 조사 항목 분할
   │        │                    │
   │        ▼ 명세 수령        완료 즉시 다음 연결
   ├─ 2) 조사 지시 ──────► [ {{PREFIX}}-researcher ] 외부 리서치·기술 조사 + 근거 보고 (코드 수정 금지)
   │        │                    │
   │        ▼ 결과물 전달    완료 즉시 다음 연결
   └─ 3) 검증/리뷰 지시 ──► [ {{PREFIX}}-reviewer ] ── [APPROVE + 검증 로그] ──► Task Manager → PM 보고
                                │
                                └── [REQUEST CHANGES + 보완 항목] ──► {{PREFIX}}-researcher로 즉시 반송 (Task Manager 중재)
```

- **On-Demand 에이전트**: `{{PREFIX}}-worker`(구현), `{{PREFIX}}-ops`(배포·인프라)는
  PM이 필요 시에만 기동합니다 (승인 범위 내).
- **Team 간 직접 협업 금지**: researcher ↔ reviewer는 서로 직접 prompt하지 않습니다.
  모든 반송/승인은 Task Manager(필요 시 PM)를 경유합니다.
- **수정 권한**: biz 체제에서는 어떤 상시 멤버도 프로덕션 코드를 직접 수정하지 않습니다.
  조사 산출물(보고서·표·근거 링크)이 결과물이며, 구현이 필요하면 PM이 `{{PREFIX}}-worker`를 별도 기동합니다.

### 1.1 ⚠️ 가드레일 (Strict Guardrails for PM & Task Manager)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, 테스트/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log` 취합 보고.
2. **역할 위임 고정**:
   - 기획 → `{{PREFIX}}-planner`, 조사 → `{{PREFIX}}-researcher` (읽기·보고만),
     검증 겸 리뷰(최종 게이트) → `{{PREFIX}}-reviewer`.
3. **오케스트레이션 전담 (Task Manager)**: 요구사항 분석, 프롬프트 전송(`herdr agent prompt`), 상태 모니터링(`herdr agent wait/read`), 산출물 중계, 결과 종합 보고.
4. **무방치 원칙 (Task Manager)**: 각 에이전트가 작업 완료 후 idle로 방치되지 않도록 완료 즉시 다음 단계를 연결합니다.