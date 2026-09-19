# Agents Configuration & Team Orchestration (preset: mkt)

본 프로젝트의 로컬·SNS 마케팅 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset mkt` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 사용자 소통·상위 목표 수립만 담당하고, 파이프라인 오케스트레이션은 `{{PREFIX}}-orchestrator`가 전담합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.
> mkt 프리셋은 분석(키워드·상권·경쟁)과 표현 리스크(광고 규정)를 researcher가 상시 담당하는 research-first 체제입니다:
> orchestrator → planner(캠페인 전략) → researcher(분석·소재) → reviewer(근거·표현 검증).
> 포스팅/카피 생산량이 많으면 PM 승인으로 `{{PREFIX}}-worker`를 on-demand로 올려 초안을 맡깁니다.

---

## 1. 소통 흐름 (Communication Flow) — 순차 파이프라인 (PM - Orchestrator - Team)

병렬 팬아웃이 아닙니다. 기본 흐름은 순차이며, 리뷰 실패 시 `{{PREFIX}}-researcher`로 회귀합니다.
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
   ├─ 1) 캠페인 기획 지시 ─► [ {{PREFIX}}-planner ] 전략·콘텐츠 캘린더·카피 브리프
   │        │                    │
   │        ▼ 명세 수령        완료 즉시 다음 연결
   ├─ 2) 분석 지시 ──────► [ {{PREFIX}}-researcher ] 키워드·상권·경쟁 분석·소재 수집 (코드 수정 금지)
   │        │                    │
   │        ▼ 결과물 전달    완료 즉시 다음 연결
   └─ 3) 검증/리뷰 지시 ──► [ {{PREFIX}}-reviewer ] ── [APPROVE + 검증 로그] ──► Orchestrator → PM 보고
                                │
                                └── [REQUEST CHANGES + 보완 항목] ──► {{PREFIX}}-researcher로 즉시 반송 (Orchestrator 중재)
```

- **On-Demand 에이전트**: `{{PREFIX}}-worker`(카피·포스팅 초안), `{{PREFIX}}-ops`(인프라)는
  PM이 필요 시에만 기동합니다 (승인 범위 내).
- **Team 간 직접 협업 금지**: researcher ↔ reviewer는 서로 직접 prompt하지 않습니다.
  모든 반송/승인은 Orchestrator(필요 시 PM)를 경유합니다.
- **수정 권한**: 상시 멤버는 프로덕션 코드를 직접 수정하지 않습니다. 분석·기획 산출물이 결과물이며, 생산(초안)은 PM이 `{{PREFIX}}-worker`를 별도 기동합니다.
- **역할 강제**: 각 역할 pane은 `.opencode/agents/{{PREFIX}}-<role>.md` agent(`--agent {{PREFIX}}-<role>`)로 시작되어 규칙·권한이 시스템 프롬프트로 고정됩니다. 상세 지침 정본은 `agents/{{PRESET}}/{{PREFIX}}-<role>.md`.

### 1.1 ⚠️ 가드레일 (Strict Guardrails for PM & Orchestrator)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, 테스트/빌드 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log` 취합 보고.
2. **역할 위임 고정**:
   - 캠페인 기획 → `{{PREFIX}}-planner`, 분석/소재 → `{{PREFIX}}-researcher` (읽기·보고만),
     검증 겸 리뷰(최종 게이트) → `{{PREFIX}}-reviewer`, 생산 초안 → `{{PREFIX}}-worker` (on-demand, 승인 범위 내).
3. **오케스트레이션 전담 (Orchestrator)**: 요구사항 분석, 프롬프트 전송(`herdr agent prompt`), 상태 모니터링(`herdr agent wait/read`), 산출물 중계, 결과 종합 보고.
   - ❌ `sleep` 폴링 쉘 루프 작성 절대 금지.
   - ✅ `herdr agent prompt <TARGET> "..." --wait` 또는 `herdr agent wait <TARGET> --until idle,done`만 사용.
4. **무방치 원칙 (Orchestrator)**: 각 에이전트가 작업 완료 후 idle로 방치되지 않도록 완료 즉시 다음 단계를 연결합니다.

---

## 2. 마케팅 파이프라인 역할

| 역할 | 담당 | 산출물 |
|---|---|---|
| `{{PREFIX}}-planner` | 캠페인 전략 | 캠페인 목표, 콘텐츠 캘린더, 카피 브리프, 채널별 톤 |
| `{{PREFIX}}-researcher` | 분석·소재 | 키워드·검색의도, 상권/경쟁 계정 분석, 소재 수집 (출처 포함) |
| `{{PREFIX}}-reviewer` | 검증 | 근거·수치, 표현/금칙어·광고 컴플라이언스, [APPROVE]/[REQUEST CHANGES] |
| `{{PREFIX}}-worker` (on-demand) | 생산 | 카피·포스팅 초안 |

---

## 3. 첫 프롬프트 예

1. "이 동네 카페 인스타 3주 플랜" → planner(캠페인/캘린더) → researcher(키워드·경쟁계정 분석) → reviewer(표현 검증) → worker(on-demand 포스팅 초안).
2. "블로그 상위노출 키워드 뽑고 글 써줘" → researcher(키워드·검색의도) → planner(구조·CTA) → worker(초안) → reviewer(팩트·금칙어).
