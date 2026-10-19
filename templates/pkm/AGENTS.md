# Agents Configuration & Team Orchestration (preset: pkm)

본 프로젝트의 PKM 볼트 생산·정리 팀 구성과 Herdr 기반 오케스트레이션 정의서입니다.
(`herdr-team {{PREFIX}} --preset pkm` 실행 시 `{{PREFIX}}`에 실제 프로젝트 prefix가 치환됩니다.)

> 전제: PM(`agy`)은 사용자 소통·상위 목표 수립만 담당하고, 파이프라인 오케스트레이션은 `{{PREFIX}}-orchestrator`가 전담합니다. 아래 가드레일(`§1.1`)을 먼저 읽으세요.
> pkm 프리셋은 노트·볼트 페이지·지식 구조 생성/정리 작업을 순차 파이프라인으로 처리하는 5인 체제입니다:
> orchestrator(오케스트레이션) → planner(노트 명세) → (researcher: 출처 기반 수집, on-demand) → worker(노트·볼트 페이지 구현) → reviewer(규격·링크·중복·출처 검증).

---

## 1. 소통 흐름 (Communication Flow) — 순차 파이프라인 (PM - Orchestrator - Team)

병렬 팬아웃이 아닙니다. 기본 흐름은 순차이며, 리뷰 실패 시 `{{PREFIX}}-worker`로 즉시 회귀합니다.
**Orchestrator(`{{PREFIX}}-orchestrator`)는 파이프라인 중계·드라이브를 전담하며 각 단계 완료 즉시 다음 단계를 끊김 없이 연결합니다.**

```
[ User ]
   │ 요청 / 최종 피드백
   ▼
[ PM (agy) ] ── 상위 목표 수립 / 최종 취합 보고
   │
   ▼
[ Orchestrator ({{PREFIX}}-orchestrator) ] ── 파이프라인 실시간 중계 & 드라이브 (쓰기 금지)
   │
   ├─ 1) 명세 지시 ─────► [ {{PREFIX}}-planner ] 노트 규격·위치·링크 구조 명세 + Task Breakdown
   │        │                │      (외부 근거가 필요하면 researcher sub-question 발행)
   │        ▼ 명세 수령      │
   ├─ 2) 조사 지시 ─────► [ {{PREFIX}}-researcher ] 출처 기반 수집·요약 (읽기 전용, 볼트 쓰기 금지)
   │        │
   │        ▼ 산출물 전달  완료 즉시 다음 연결
   ├─ 3) 구현 지시 ─────► [ {{PREFIX}}-worker ] 노트/볼트 페이지 실제 작성 + 링크/규격 검산
   │        │                │
   │        ▼ 변경사항 전달 │
   └─ 4) 검증/리뷰 지시 ► [ {{PREFIX}}-reviewer ] 규격·링크·중복·출처 검증
                              │
                              ├ [APPROVE + 검증 로그] ──► Orchestrator → PM 보고
                              └ [REQUEST CHANGES + 보완 항목] ──► {{PREFIX}}-worker로 즉시 반송 (Orchestrator 중재)
```

- **On-Demand 에이전트**: `{{PREFIX}}-researcher`는 상시가 아니며, 플래너 명세에
  "조사 필요" 표기가 있을 때만 Orchestrator가 단계 2를 실행합니다. 없으면 1→3 바로 연결합니다(빈 단계 대기 금지).
- **Team 간 직접 협업 금지**: 모든 반송/승인은 Orchestrator(필요 시 PM)를 경유합니다.
- **역할별 쓰기 권한 범위 (Scoped Permissions)**:
  - `{{PREFIX}}-planner`: **문서 전용 쓰기 허용 (`docs/specs/*.md`)**. 노트·볼트 페이지 직접 작성 금지.
  - `{{PREFIX}}-researcher`: **쓰기 없음 (읽기 전용)**. 볼트 쓰기·노트 생성 금지.
  - `{{PREFIX}}-worker`: **구현 전용 쓰기**. 볼트 노트(`00-Inbox`~`08-TIL`, `06-Wiki`, `01-System`)와 스크립트·테스트를 직접 작성하는 **유일한 실질 쓰기 역할**.
  - `{{PREFIX}}-reviewer`: **검증 실행 전용 임시 쓰기 허용 (`10-temp`, 검증 산출물·로그)**. 프로덕션 코드·노트 직접 수정 금지(발견 즉시 REQUEST CHANGES 반송).
  - `{{PREFIX}}-orchestrator`: **쓰기 없음**. 파일 편집·노트 작성·테스트 실행·`git commit/push` 금지.
- **역할 강제**: 각 역할 pane은 `.opencode/agents/{{PREFIX}}-<role>.md` agent 설정을 기반으로 시작되어 규칙·권한이 시스템 프롬프트로 고정됩니다. 상세 지침 정본은 `agents/{{PRESET}}/{{PREFIX}}-<role>.md`.

### 1.1 ⚠️ 가드레일 (Strict Guardrails for PM & Orchestrator)

1. **쓰기 금지, 읽기 허용**:
   - ❌ 금지(쓰기): 파일 편집, 노트 작성, 테스트 실행, `git commit/push`, 에이전트 pane에서의 직접 코딩.
   - ✅ 허용(읽기): `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log` 취합 보고.
2. **역할 위임 고정 및 파일 기반 계약**:
   - 노트 명세 → `{{PREFIX}}-planner` (산출물은 반드시 `docs/specs/<명세명>.md` 파일로 작성 후 "경로 + 1줄 요약"만 회신).
   - 조사/수집 → `{{PREFIX}}-researcher` (읽기·보고만, on-demand),
     구현 → `{{PREFIX}}-worker`, 검증 겸 리뷰(최종 게이트) → `{{PREFIX}}-reviewer`.
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

## 2. PKM 파이프라인 역할

| 역할 | 담당 | 산출물 |
|---|---|---|
| `{{PREFIX}}-planner` | 노트 명세 | 목적·대상 폴더, 노트 제목/파일명 규칙, frontmatter 필드(YAML), 링크/태그 구조, 출처 요구, Task Breakdown |
| `{{PREFIX}}-researcher` | 출처 기반 수집 (on-demand) | 명세 파일 `## 근거` 섹션 추가 또는 별도 수집 노트 (모든 주장에 출처 URL·버전·발췌) |
| `{{PREFIX}}-worker` | 노트·볼트 페이지 구현 | 실제 노트(`00-Inbox`, `06-Wiki`, `08-TIL` 등) + 필요 시 스크립트 (볼트 문서규격·템플릿 준수, 위키링크 `[[...]]` 유효성) |
| `{{PREFIX}}-reviewer` | 검증 | 검증 로그(임시) + 판정 (규격 준수, 링크 유효성, 중복/파편화, 출처 정확성) |

그 외 도메인 작업 유형: 노트 정리·리팩터링(인박스 소화), 인덱스/대시보드 갱신(기존 스크립트 활용), 템플릿·규격 문서 개정.

---

## 3. 역할별 DoD 및 최종 승인 게이트

| 역할 | DoD |
|---|---|
| planner | 명세 파일 경로 회신 + 1줄 요약 / Task Breakdown 포함 / 볼트 폴더·규격 참조 명시 |
| researcher | 모든 주장에 출처 URL·버전·발췌 / 재현 가능한 검색어 기록 / 볼트 쓰기 0건 |
| worker | 명세 DoD 충족 노트 작성 / 링크·frontmatter 검산 통과 / 생성 파일 경로 목록 회신 |
| reviewer | 실제 검증 실행 로그 첨부 / [APPROVE] 또는 [REQUEST CHANGES(+재현 방법)] 판정 / 노트·코드 미수정 |
| orchestrator | 각 단계 완료 즉시 연결 / 최종 보고(명세·구현 목록·판정 로그 요약) |

**최종 승인 게이트 (reviewer)**:
1. 규격 준수: 볼트 문서규격 및 명세의 frontmatter/템플릿 요구 충족.
2. 링크 유효성: 새 노트의 `[[위키링크]]` 전부 실존 파일·노트로 해석됨.
3. 중복·파편화: 기존 볼트에 동일 주제 노트가 없거나, 있으면 링크로 통합됨.
4. 출처 정확성(조사 포함 작업): researcher 근거와 본문 주장 불일치 없음.
5. 범위 준수: 명세 범위 외 파일 생성/수정 0건.
→ 5항목 전부 충족 시 [APPROVE], 하나라도 실패 시 [REQUEST CHANGES]로 worker 반송 (Orchestrator 중재). 반송 후 재검증은 동일 게이트 기준 1회 재판정, 2회 반복 실패 시 PM에 에스컬레이션.

---

## 4. 첫 프롬프트 예

1. "오늘 배운 것 TIL 노트 작성" → planner(노트 규격·위치 명세) → worker(노트 작성 + 링크 검산) → reviewer(규격·링크 검증).
2. "인박스 소화: 00-Inbox 노트 정리" → planner(이동·통합 계획 명세) → worker(노트 이동·링크 정리, 삭제는 10-temp 보관 후 이동) → reviewer(중복·링크·범위 검증).
