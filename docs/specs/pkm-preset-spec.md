# Spec: SecondBrain용 5인 PKM 프리셋 신규 도입 (preset: pkm)

- 작성: ht-planner / 2026-10-19
- 대상 레포: `/home/hm/work/SecondBrain` (Obsidian PKM 볼트)
- 상위 도구 레포: `/home/hm/work/projects/herdr-team` (프리셋 템플릿 정의 원본)

## 0. 한 줄 정의
SecondBrain 볼트에서 **노트·볼트 페이지·지식 구조 생성/정리 작업**을 기획→(조사)→구현→검증 순차 파이프라인으로 처리하는 5인 프리셋.

## 0.1 근거 (사실)
- SecondBrain은 Obsidian 볼트: `00-Inbox` ~ `08-TIL`, `01-System/Obsidian-문서규격.md`(문서 규격), `01-System/Templates`(템플릿) 존재.
- 기존 프리셋 `research`(4역할, `sb-` prefix)가 이미 시딩됨: `agents/research/`, `.opencode/agents/sb-*.md`, `.herdr-team/preset`에 `research` 기록.
- herdr-team CLI는 `templates/<preset>/preset.conf`(`PRESET_DESC`, `ROLES`, `LAYOUT`)를 발견해 프리셋을 자동 열거/시딩한다. 시딩 결과물: `agents/<preset>/AGENTS.md` + `<prefix>-<role>.md`, `.opencode/agents/<prefix>-<role>.md`, 루트 `AGENTS.md`, `.herdr-team/preset` 활성화.
- 역할 파일 원본: `templates/agents/ROLE-<role>.md`(pane용) / `templates/opencode-agents/ROLE-<role>.md`(agent 설정용).

## 0.2 파일 위치 ( SecondBrain 레포 기준 — 작성 대상 )
SecondBrain 레포에 **신규 생성**할 파일:
| 파일 | 용도 |
|---|---|
| `agents/pkm/AGENTS.md` | pkm 프리셋 팀 정의서 (§1 형식 준용, `{{PREFIX}}` 치환) |
| `agents/pkm/pk-orchestrator.md` ~ `pk-reviewer.md` (5개) | 역할별 지침 정본 |
| `.opencode/agents/pk-orchestrator.md` ~ `pk-reviewer.md` (5개) | agent 설정 (frontmatter `description`/`mode`/`permission`) |
| `.herdr-team/preset` | 내용을 `pkm`으로 교체 (프리셋 활성화) |
| `AGENTS.md` (루트) | `agents/pkm/AGENTS.md` 복사본으로 교체 |

Prefix는 **`pk`**를 사용한다. 기존 `sb-*`(research) 에이전트와 충돌을 피하기 위함 (가정 — 열린 질문 Q1).
업스트림(도구 레포)에는 동일 내용을 `templates/pkm/`(preset.conf, AGENTS.md)와 `templates/agents/`·`templates/opencode-agents/`의 `ROLE-*` 템플릿 보완으로 반영한다. 본 명세의 구현 대상은 SecondBrain 레포 시딩 산출물로 한정하되, 업스트림 템플릿 동기화는 열린 질문 Q2.

## 0.3 preset.conf (SecondBrain 시딩 시 CLI가 참조하는 값)
```
# preset: pkm — Personal Knowledge Management (PKM 볼트 생산·정리 체제)
PRESET_DESC="PKM Vault Team (노트·볼트 페이지 생산/정리, orchestrator/planner/researcher/worker/reviewer)"
ROLES="orchestrator planner researcher worker reviewer"
LAYOUT="2col"
```

---

## 1. 소통 흐름 (Communication Flow) — 순차 파이프라인 (PM - Orchestrator - Team)

병렬 팬아웃 없음. 기본 흐름은 순차이며, 리뷰 실패 시 `pk-worker`로 즉시 회귀한다.
**Orchestrator(`pk-orchestrator`)는 파이프라인 중계·드라이브 전담. 각 단계 완료 즉시 다음 단계를 연결한다(무방치 원칙).**

```
[ User ]
   │ 요청 / 최종 피드백
   ▼
[ PM (agy) ] ── 상위 목표 수립 / 최종 취합 보고
   ▼
[ Orchestrator (pk-orchestrator) ] ── 파이프라인 실시간 중계 & 드라이브 (쓰기 금지)
   │
   ├─ 1) 명세 지시 ─────► [ pk-planner ] 노트 규격·위치·링크 구조 명세 + Task Breakdown
   │        │                │      (외부 근거가 필요하면 researcher sub-question 발행)
   │        ▼ 근거 수령      │
   ├─ 2) 조사 지시 ─────► [ pk-researcher ] 출처 기반 수집·요약 (읽기 전용, 볼트 쓰기 금지)
   │        │
   │        ▼ 산출물 전달  완료 즉시 다음 연결
   ├─ 3) 구현 지시 ─────► [ pk-worker ] 노트/볼트 페이지 실제 작성 + 링크/규격 검산
   │        │                │
   │        ▼ 변경사항 전달 │
   └─ 4) 검증/리뷰 지시 ► [ pk-reviewer ] 규격·링크·중복·출처 검증
                              │
                              ├ [APPROVE + 검증 로그] ──► Orchestrator → PM 보고
                              └ [REQUEST CHANGES + 보완 항목] ──► pk-worker로 즉시 반송 (Orchestrator 중재)
```

- researcher는 상시가 아닌 **on-demand 기동**: 플래너 명세에 "조사 필요" 표기가 있을 때만 Orchestrator가 단계 2를 실행하고, 없으면 1→3 바로 연결.
- 팀 간 직접 협업 금지: 모든 반송/승인은 Orchestrator(필요 시 PM) 경유.
- 가드레일(§1.1)은 dev/AGENTS.md의 것을 준용: 쉘 이스케이프 수칙, 단일 명령 불변식, 중복 대기 금지(`--wait` 후 재-wait 금지), `--until` 단일 상태값, `sleep` 폴링·파이프 필터 금지.

## 2. 역할별 스코프드 권한 (Scoped Permissions)

| 역할 | 쓰기 | 읽기/실행 | 금지 |
|---|---|---|---|
| `pk-planner` | **문서 전용**: `docs/specs/*.md` | 볼트 전체 읽기, grep/jq 등 읽기 명령 | 노트/볼트 페이지 직접 작성, 프로덕션 코드·테스트 수정 |
| `pk-researcher` | **없음 (읽기 전용)** | 웹·볼트 전체 읽기, 인용·발췌 수집 | 볼트 쓰기, 노트 생성, 코드·테스트 수정 |
| `pk-worker` | **구현/테스트 전용**: 볼트 노트(`00-Inbox`~`08-TIL`, `06-Wiki`, `01-System`), 스크립트·테스트 코드. **유일한 실질 쓰기 역할** | 전체 읽기, 노트 작성 스크립트 실행 | — |
| `pk-reviewer` | **검증 실행 전용 임시 쓰기** (`10-temp`, 테스트 산출물·로그) | 전체 읽기, 링크/중복 검사 스크립트 실행, git diff | 프로덕션 코드·노트 직접 수정(발견 즉시 REQUEST CHANGES 반송) |
| `pk-orchestrator` | **쓰기 없음** | `herdr agent list/read`, `herdr pane list/read`, `git status/diff/log`, 로그 취합, 사용자 보고 | 파일 편집, 노트 작성, 테스트 실행, `git commit/push`, 직접 코딩 |

`.opencode/agents/pk-<role>.md` frontmatter의 `permission` 블록으로 강제한다(기존 `sb-planner.md`의 `edit: deny`, 읽기 bash allow 패턴 양식 준용). 예:
```yaml
---
description: "pk-worker — 볼트 노트/페이지 구현 유일 쓰기 역할. 명세 기반 작성 + 링크·규격 검산."
mode: primary
permission:
  edit: allow
  bash:
    "*": ask
    "python3 scripts/*": allow
    "git status*": allow
    "git diff*": allow
---
```

## 3. PKM 도메인 특화 산출물 정의

대표 작업: "노트/볼트 페이지 생성". 명세-구현-검증 산출물 3단으로 고정:

| 단계 | 역할 | 산출물 (파일) | 형식 |
|---|---|---|---|
| 명세 | planner | `docs/specs/<YYYY-MM-DD>-<작업명>.md` | 목적·대상 폴더(예: `06-Wiki/`), 노트 제목/파일명 규칙, frontmatter 필트(YAML), 링크/태그 구조, 출처 요구, Task Breakdown |
| (조사) | researcher | 명세 파일에 `## 근거` 섹션 추가 or 별도 수집 노트 | 모든 주장에 출처 URL/버전/발췌 (research 프리셋 기준 준용) |
| 구현 | worker | 실제 노트/볼트 페이지 (`00-Inbox`, `06-Wiki`, `08-TIL` 등) + 필요 시 스크립트 | `01-System/Obsidian-문서규격.md` 준수, `01-System/Templates` 템플릿 사용, 위키링크 `[[...]]` 유효성 |
| 검증 | reviewer | 검증 로그(임시) + 판정 | 규격 준수, 링크 유효성, 중복/파편화, 출처 정확성 |

그 외 도메인 작업 유형: 노트 정리·리팩터링(인박스 소화), 인덱스/대시보드 갱신(`update_log_index.py` 등 기존 스크립트 활용), 템플릿·규격 문서 개정.

## 4. 역할별 DoD 및 최종 승인 게이트

| 역할 | DoD |
|---|---|
| planner | 명세 파일 경로 회신 + 1줄 요약 / Task Breakdown 포함 / 볼트 폴더·규격 참조 명시 |
| researcher | 모든 주장에 출처 URL·버전·발췌 / 재현 가능한 검색어 기록 / 볼트 쓰기 0건 |
| worker | 명세 DoD 충족 노트 작성 / 링크·frontmatter 검산 통과 / 생성 파일 경로 목록 회신 |
| reviewer | 실제 검증 실행 로그 첨부 / [APPROVE] 또는 [REQUEST CHANGES(+재현 방법)] 판정 / 노트·코드 미수정 |
| orchestrator | 각 단계 완료 즉시 연결 / 최종 보고(명세·구현 목록·판정 로그 요약) |

**최종 승인 게이트 (reviewer)**:
1. 규격 준수: `01-System/Obsidian-문서규격.md` 및 명세의 frontmatter/템플릿 요구 충족.
2. 링크 유효성: 새 노트의 `[[위키링크]]` 전부 실존 파일·노트로 해석됨.
3. 중복·파편화: 기존 볼트에 동일 주제 노트가 없거나, 있으면 링크로 통합됨.
4. 출처 정확성(조사 포함 작업): researcher 근거와 본문 주장 불일치 없음.
5. 범위 준수: 명세 범위 외 파일 생성/수정 0건.
→ 5항목 전부 충족 시 [APPROVE], 하나라도 실패 시 [REQUEST CHANGES]로 worker 반송 (Orchestrator 중재). 반송 후 재검증은 동일 게이트 기준 1회 재판정, 2회 반복 실패 시 PM에 에스컬레이션.

## 5. Task Breakdown (ht-worker 구현 대상 — SecondBrain 레포)

- T1: `agents/pkm/AGENTS.md` 작성 — §1 파이프라인 다이어그램·§1.1 가드레일·§2 권한표·§3 산출물·§4 DoD를 `{{PREFIX}}` 치환 양식으로. 완료 기준: dev/research AGENTS.md와 동일 구조(장 구성 동일), 5역할 표기.
- T2: `agents/pkm/pk-{orchestrator,planner,researcher,worker,reviewer}.md` 5개 작성 — dev의 `ht-<role>.md` 핵심 미션/규칙/보고 형식 3단 구조 준용 + PKM 도메인 규칙 추가.
- T3: `.opencode/agents/pk-{...}.md` 5개 작성 — §2 권한표를 frontmatter `permission`으로 변환, `sb-planner.md` 양식 준용.
- T4: `.herdr-team/preset`을 `pkm`으로 교체, 루트 `AGENTS.md`를 `agents/pkm/AGENTS.md` 내용으로 갱신(현재 research 시딩과 충돌 없음 확인).
- T5 (검증): `herdr-team --list-presets`/시딩 dry-run 대상 확인, `.opencode/agents/` 파싱 오류 없음 확인.

TDD 대상: 볼트 프리셋은 주로 마크다운/설정 파일이므로 전통 단위 테스트 대상은 적음. T5의 구문·경로 검산(파일 존재, frontmatter YAML 유효성 체크 스크립트 1개)을 최소 자가검증으로 요구.

## 6. 엣지 케이스

1. **research 프리셋과의 공존**: `sb-*` 에이전트가 남아 있어도 `pk-*`와 충돌 없음. 단 `.herdr-team/preset`은 1개만 활성 가능 → 활성화 전 기존 research 세션 종료 확인.
2. **worker의 삭제 권한**: 노트 정리 작업에서 기존 노트 이동/삭제가 필요 → 삭제는 10-temp 보관 후 이동 방식으로 제한(실수 방지).
3. **리서치 불필요 태스크**: researcher 생략 경로(1→3 직결)를 orchestrator 판단 규칙에 명시해 빈 단계 대기 방지.
4. **오탈자 링크**: `[[...]]` 링크는 Obsidian이 자동 생성하지만 대상 노트 미존재 시 미해석 → reviewer 게이트 2항으로 커버.

## 7. 열린 질문 (PM 확인 필요)

1. Prefix `pk` 확정 여부 (现有 `sb` 재사용 안).
2. 업스트림(`templates/pkm/`) 템플릿 동기화를 이번 작업에 포함할지 — SecondBrain 시딩만 먼저 할지.
3. `LAYOUT` 2col에서 5역할 pane 배치(orchestrator 단독 / 4역할) 확인 필요 시 도구 쪽 확인.

---

### 회신 형식 (규약)
- 산출물: `docs/specs/pkm-preset-spec.md`
- 1줄 요약: SecondBrain 볼트용 5인 PKM 프리셋 — 순차 파이프라인·역할별 스코프드 권한·PKM 도메인 산출물(명세-조사-구현-검증)·DoD·Approval 게이트 정의.
