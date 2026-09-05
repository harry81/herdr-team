# Agents Configuration & Team Orchestration (preset: app)

본 프로젝트의 앱/서비스 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset app` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 사용자 소통·상위 목표 수립만 담당하고, 파이프라인 오케스트레이션은 `{{PREFIX}}-taskmanager`가 전담합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.
> app 프리셋은 dev와 동일한 4역할(taskmanager/planner/worker/reviewer)이지만,
> 배포·E2E 검증과 스토어/릴리스 심사를 강조합니다.

---

## 1. 소통 흐름 (Communication Flow) — 순차 파이프라인 (PM - Task Manager - Team)

병렬 팬아웃이 아닙니다. 기본 흐름은 순차이며, 리뷰 실패 시 `{{PREFIX}}-worker`로 회귀합니다.
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
   ├─ 1) 릴리스 기획 지시 ─► [ {{PREFIX}}-planner ] 릴리스 기획 + Task Breakdown (심사 대응 포함)
   │        │                    │
   │        ▼ 명세 수령        완료 즉시 다음 연결
   ├─ 2) TDD 구현 지시 ────► [ {{PREFIX}}-worker ] TDD 구현 + 단위 테스트 PASS
   │        │                    │
   │        ▼ 변경사항 전달    완료 즉시 다음 연결
   └─ 3) 검증/리뷰 지시 ───► [ {{PREFIX}}-reviewer ] ── [APPROVE + 실행 로그] ──► Task Manager → PM 보고
                                │
                                └── [REQUEST CHANGES + 재현/로그] ──► {{PREFIX}}-worker로 즉시 반송 (Task Manager 중재)
```

- **On-Demand 에이전트**: `{{PREFIX}}-ops`를 앱 프리셋에서는 적극 활용합니다
  (배포 파이프라인, 스토어 업로드, 비밀값·환경 변수 운영 대행 — PM 승인 범위 내).
  `{{PREFIX}}-researcher`는 SDK/플랫폼 스펙 조사 전담 (읽기·보고만).
- **Team 간 직접 협업 금지**: worker ↔ reviewer는 서로 직접 prompt하지 않습니다. 모든 반송/승인은 Task Manager(필요 시 PM)를 경유합니다.
- **수정 권한**: 코드를 직접 수정하는 것은 `{{PREFIX}}-worker`뿐입니다
  (`{{PREFIX}}-ops`는 승인된 운영 범위만 예외).

### 1.1 ⚠️ 가드레일 (Strict Guardrails for PM & Task Manager)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, 테스트/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log` 취합 보고.
2. **역할 위임 고정**:
   - 기획/설계 → `{{PREFIX}}-planner`, 구현 → `{{PREFIX}}-worker`,
     실행 검증 겸 리뷰(배포·E2E 포함) → `{{PREFIX}}-reviewer`,
     배포/인프라 → `{{PREFIX}}-ops` (on-demand, 승인 범위 내).
3. **오케스트레이션 전담 (Task Manager)**: 요구사항 분석, 프롬프트 전송(`herdr agent prompt`), 상태 모니터링(`herdr agent wait/read`), 산출물 중계, 결과 종합 보고.
4. **무방치 원칙 (Task Manager)**: 각 에이전트가 작업 완료 후 idle로 방치되지 않도록 완료 즉시 다음 단계를 연결합니다.