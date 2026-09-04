# Agents Configuration & Team Orchestration (preset: biz)

본 프로젝트의 기획/조사 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset biz` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 오케스트레이션만 담당합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.
> biz 프리셋은 코드 구현(worker) 대신 조사(researcher) 중심 3인 체제입니다:
> planner(기획) → researcher(조사) → reviewer(검증).

---

## 1. 소통 흐름 (Communication Flow) — 순차 DAG (3인 체제)

```
[ User ]
   │ 요청 / 최종 피드백
   ▼
[ PM (agy) ] ── 분석 → 분배 → 모니터링 → 취합 보고
   │
   ├─► [ {{PREFIX}}-planner ] 기획/요구사항 명세 + 조사 항목 분할
   │        │
   │        ▼ 명세 전달
   ├─► [ {{PREFIX}}-researcher ] 외부 리서치·기술 조사 + 근거 보고 (코드 수정 금지)
   │        │
   │        ▼ 리뷰 요청 (출처·재현 절차 포함)
   └─► [ {{PREFIX}}-reviewer ] ── [APPROVE + 검증 로그] ──► PM이 사용자에게 보고
            │
            └── [REQUEST CHANGES + 보완 항목] ──► {{PREFIX}}-researcher로 반송 (PM이 중재)
```

- **On-Demand 에이전트**: `{{PREFIX}}-worker`(구현), `{{PREFIX}}-ops`(배포·인프라)는
  PM이 필요 시에만 기동합니다 (승인 범위 내).
- **Team 간 직접 협업 금지**: researcher ↔ reviewer는 서로 직접 prompt하지 않습니다.
  모든 반송/승인은 PM을 경유합니다.
- **수정 권한**: biz 체제에서는 어떤 상시 멤버도 프로덕션 코드를 직접 수정하지 않습니다.
  조사 산출물(보고서·표·근거 링크)이 결과물이며, 구현이 필요하면 PM이 `{{PREFIX}}-worker`를 별도 기동합니다.

### 1.1 ⚠️ PM 가드레일 (Strict Guardrails for PM)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, 테스트/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log` 취합 보고.
2. **역할 위임 고정**:
   - 기획 → `{{PREFIX}}-planner`, 조사 → `{{PREFIX}}-researcher` (읽기·보고만),
     검증 겸 리뷰(최종 게이트) → `{{PREFIX}}-reviewer`.
3. **오케스트레이션 전담**: 요구사항 분석, 프롬프트 전송, 상태 모니터링, 결과 종합 보고.
