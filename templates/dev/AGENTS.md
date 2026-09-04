# Agents Configuration & Team Orchestration (preset: dev)

본 프로젝트의 에이전트 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset dev` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 오케스트레이션만 담당합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.

---

## 1. 소통 흐름 (Communication Flow) — 순차 DAG (3인 체제)

병렬 팬아웃이 아닙니다. 기본 흐름은 순차이며, 리뷰 실패 시 `{{PREFIX}}-worker`로 회귀합니다.

```
[ User ]
   │ 요청 / 최종 피드백
   ▼
[ PM (agy) ] ── 분석 → 분배 → 모니터링 → 취합 보고
   │
   ├─► [ {{PREFIX}}-planner ] 기획/설계 명세 + Task Breakdown
   │        │
   │        ▼ 명세 전달
   ├─► [ {{PREFIX}}-worker ] TDD 구현 + 단위 테스트 PASS
   │        │
   │        ▼ 리뷰 요청 (실행 검증 포함)
   └─► [ {{PREFIX}}-reviewer ] ── [APPROVE + 실행 로그] ──► PM이 사용자에게 보고
            │
            └── [REQUEST CHANGES + 재현/로그] ──► {{PREFIX}}-worker로 반송 (PM이 중재)
```

- **On-Demand 에이전트**: 상시 팀이 아니며 PM이 필요 시에만 기동합니다.
  - `{{PREFIX}}-researcher`: 외부 리서치, 기술 조사 전담 (읽기·보고만, 코드 수정 금지).
  - `{{PREFIX}}-ops`: 배포, 인프라, 비밀값·환경 변수 운영 대행 (PM 승인 범위 내에서만 실행).
- **Team 간 직접 협업 금지**: worker ↔ reviewer는 서로 직접 prompt하지 않습니다. 모든 반송/승인은 PM을 경유합니다.
- **수정 권한**: 코드를 직접 수정하는 것은 `{{PREFIX}}-worker`뿐입니다.

### 1.1 ⚠️ PM 가드레일 (Strict Guardrails for PM)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, `pytest`/`npm test`/`playwright`/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log`, 테스트 결과 로그 취합, 사용자 보고.
2. **역할 위임 고정**:
   - 기획/설계 → `{{PREFIX}}-planner`, 구현/버그수정 → `{{PREFIX}}-worker`, 실행 검증 겸 코드 리뷰(최종 게이트) → `{{PREFIX}}-reviewer`.
3. **오케스트레이션 전담**: 요구사항 분석, 프롬프트 전송(`herdr agent prompt`), 상태 모니터링(`herdr agent wait/read`), 결과 종합 보고.
