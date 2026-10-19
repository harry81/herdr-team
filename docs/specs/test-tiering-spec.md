# Spec: 테스트 티어링 — Test Bloat / Regression Trap 제거 (T1/T2/T3 3계층)

- 작성: ht-planner / 2026-10-19
- 범위: 본 레포 정본(AGENTS.md, agents/dev/*.md, templates/)+시딩 파이프라인, 소비 프로젝트(scriptstudio 등)에 공통 적용되는 테스트 실행 규약
- 회신 규약: 경로 + 1줄 요약

## (a) 현행 규칙의 함정 분석 (사실)

- `AGENTS.md §5`: "worker는 … **전체 회귀는 완료 직전 1회만 실행**해 [full-regression] 결과를 고지한다. reviewer는 … git diff 리뷰 + **전체 회귀 1회** + DoD 대조".
  - 함정 1: "완료 직전 1회"가 태스크 단위로 해석되어 **모든 태스크가 full regression을 강제**. 태스크를 잘게 쪼갤수록 full 실행 횟수는 오히려 늘어난다(변경 크기가 아니라 태스크 개수에 비례).
  - 함정 2: worker full + reviewer full = **태스크당 full 회귀 2회**. 오타 재실행까지 누적하면 3회 — scriptstudio에서 3줄 변경에 2194개×166s급 비용이 중첩된 실증.
- `agents/dev/ht-reviewer.md §3-3`: "변경 범위에 따라 관련 통합·회귀 스위트 실행… 전체 실행이 무거우면 최소 변경 관련 스코프 + 핵심 회귀 1종은 필수" — 절충 여지가 있으나 **변경 범위 판정 기준이 규정되지 않아** reviewer는 판단 부담을 피해 full 실행을 선택하는 최대 방어가 규약상 유효 선택이 됨.
- 근본 원인 두 가지(PM 진단 수용): (1) 규칙 문구가 모든 태스크에 full regression을 강제, (2) blast radius(surface/core) 판정 주체·기준 부재 → worker/reviewer의 안전 강박이 항상 full을 택함.
- 규모 실증: full 일회 166초, 오타 재실행으로 세션 10분 이상 점유. 3줄 변경과 2194 테스트는 비례하지 않음.

## (b) 3계층 정의

| 티어 | 정의 | 트리거 | 실행 주체 | 범위 | 시간 예산 | 재실행 예산 |
|---|---|---|---|---|---|---|
| T1 Fast-Loop | 편집 루프용 최소 테스트 | Red-Green 루프의 매 전환 | worker | 대상 파일 전용 테스트(`pytest tests/test_<target>.py -q` 등) | 5초 이내 | 루프 내 무제한 |
| T2 Scoped Regression | 변경 파일에 대응하는 영향 스위트만 태스크 완료 시 1회 실행 | 태스크 구현 완료 시 1회 | worker | `scripts/testmap.sh`가 출력하는 매핑 스위트(§e) | 10초 이내 목표 | 태스크당 1회. 실패 시 수정 후 재실행 1회 허용 |
| T3 Full Regression | 전체 스위트 | push 직전 또는 CI에서만 1회, 비동기 | reviewer(push 직전) 또는 CI | 전체 | 상한 없음(비동기, 세션 점유 없음) | 노드당 1회. 실패 시 CI 재실행 또는 worker 반송 후 push 단계에서 다시 1회 |

- T3는 worker가 임의로 실행하지 않는다(push/CI 노드 전용).
- reviewer의 개별 테스트 재실행은 금지 유지 — T3 노드 규정과 함께 보강.

## (c) blast radius 분류 기준 (surface / core)

| 분류 | 판정 규칙 (파일 경로 기반, 추론 없음) | T3 승격 |
|---|---|---|
| 표면 (surface) | CLI 플래그 기본값·도움말·출력 문구·주석·문서(`docs/`) 등 **알고리즘·계약 동작에 영향을 주지 않는 표층 변경** | 없음 — T2로 충분 |
| 코어 (core) | 공유 유틸/헬퍼, 알고리즘 로직, 스키마/데이터 구조/API 계약, 임포트 트리상 다른 모듈이 참조하는 파일 — 매핑 표의 **코어 경로 필터**(`bin/herdr-team`, `lib/`, `src/`, `schemas/` 등 공유 위치)에 해당하는 파일 | worker는 T2만 실행; push/CI 노드에서 T3로 승격 |

- 판정은 확정 경로 필터만 사용한다(import 그래프 분석 같은 도구·서비스·AI 추론 배제). 경계 사례는 reviewer 반송에서 수동 검토.
- 미분류 파일: 보수적으로 T3 승격 후보로 표시한다. push 전 reviewer가 실제 영향을 검토한다(경로 필터가 판정하지 못한 파일의 안전망).

**T3 승격 조건(하나라도 충족 → push/CI 노드에서 T3 실행)**:
1. core 경로 필터에 해당하는 파일이 변경된 경우.
2. T2가 재실행까지 포함해 2회 연속 실패.
3. 매핑 표에서 미분류 파일(§e 규칙).

## (d) 티어 선택 책임 소재 (판정 주체 고정)

- **orchestrator**: 태스크 지시에 티어를 명시(`tier=T2` 또는 `tier=T2, core — push/CI에서 T3`)해 worker에게 전달. 판정 기준: **surface 변경=T2로 태스크 종료**, **core 변경=worker는 T2까지만 수행하고 push/CI 노드에서 T3로 승격**(태스크 안에서 full을 돌리지 않는다).
- **worker**: 지시받은 티어만 실행. **임의 T3 실행 금지**. 티어 지시가 없으면 T1만 실행한 뒤 orchestrator에 재지시를 요청하고 정지한다(임의 상향 금지, 판정 주체 부재 재발 방지).
- **reviewer**: worker의 T1/T2 결과 보고를 확인하고(중복 실행 금지 유지), push/CI 노드에서 T3를 실행. 티어 규약 위반을 발견하면 REQUEST CHANGES 사유로 보고.
- **공통**: 태스크 진행 중 blast radius가 예상과 다름이 발견되면(예: surface로 지시받은 작업에서 core 파일 변경이 발견됨) worker는 티어를 임의로 상향하지 않고 orchestrator에 보고해 재지시만 요청한다.

## (e) 매핑 스크립트 인터페이스 (T2 스위트 선택의 유일한 근거)

- **위치**: `scripts/testmap.sh` — **단일 셸 스크립트**, 외부 도구·서비스·AI 배제.
- **역할**: git diff 변경 파일 목록을 매핑 표에 대응시켜 "실행할 테스트 스위트 목록"을 출력한다.

```
사용법:
  scripts/testmap.sh [--base REF] [--mode bare|json]
  git repo 루트에서 실행.

출력:
  bare 모드(기본): 한 줄당 스위트 경로. 예: tests/test_preset.sh
  json 모드: {"suites":[...],"unclassified":[...]} — 구현 시 키를 이 라인과 동일하게 고정.
```

- **매핑 표**(스크립트 내부 case 표): 파일 경로 → 스위트.
  - 본 레포 예시: `bin/herdr-team` 변경 → `tests/test_agent_session.sh`, `tests/test_pane_ready.sh`, `tests/test_preset.sh` / `templates/**` 변경 → `tests/test_preset.sh`, `tests/test_permissions_seed.sh` / `tests/test_foo.sh` 변경 → 그 파일 자체.
  - 소비 프로젝트: 표의 override 확장만 제공(로컬 프로젝트 자체 설정 파일로 코어 필터·매핑 표를 추가).
- **미분류 처리 규칙**: 표에 없는 파일은 unclassified로 수집하고, 이 경우 fallback 스위트(지정된 기본 스위트)를 출력에 추가한다. exit code는 unclassified 유무와 관계없이 0(성공)을 유지하며, unclassified 리스트가 정보를 전달한다 — exit 1은 쉘/환경 오류("git repo 아님")에만 사용.
- 자기 자신의 수용 테스트 기준(`tests/test_testmap.sh`):
  1. 변경 없음 → 스위트 0, exit 0.
  2. `bin/herdr-team` 변경 → 기대 스위트 전부 출력.
  3. 표에 매핑된 파일 변경 → 매핑된 스위트(예: 그 파일 자체) 출력.
  4. 문서만 변경 → 스위트 0, unclassified에 경로 기재.
  5. 매핑 표에 없는 파일 변경 → fallback 스위트 출력 + 해당 파일을 unclassified에 기재.
  6. git repo 이외에서 실행 → 명시적 에러 메시지 + exit 1.
  7. 결정성: 동일 입력 반복 실행 시 출력 항상 동일.
  8. 성능: 스크립트 자체 1초 이내.
  9. json 모드 출력이 유효 JSON으로 파싱됨 확인.

## (f) AGENTS.md §5 개정 초안 문구 (정본 동시 반영)

> 정본 동시 반영: `AGENTS.md` 루트 + `agents/dev/ht-worker.md` + `agents/dev/ht-reviewer.md` + `templates/agents/ROLE-worker.md`/`ROLE-reviewer.md` — 한 가지 문구로 4위치 동일 반영(4위치 간 문구 편차 방지).

### 개정 초안(교체 문구):
> 5. **테스트 티어링 (Fast Loop 원칙)**: 테스트는 3계층으로 실행한다. **T1 Fast-Loop**(변경 파일 대응 테스트, 편집 루프마다, 5초 이내)와 **T2 Scoped Regression**(`scripts/testmap.sh` 매핑 스위트, 태스크 완료 시 1회, 10초 이내 목표)은 worker가 실행한다. **T3 Full Regression**은 push 직전 또는 CI에서만 1회, 비동기 실행 — worker의 임의 T3 실행 금지. 티어 선택은 Orchestrator가 태스크 지시에 명시하고 worker는 지시된 티어만 실행(지시 없으면 T1만 후 재지시 요청). blast radius 판정(core/surface)은 `docs/specs/test-tiering-spec.md`의 파일 경로 기반 규칙으로 한다. reviewer는 T3 노드에서만 full regression 실행, 그 외 규정 밖 단위 테스트 재실행 금지. 결과 고지: `[T2 scoped] <command> → N passed in T s` — 기존 [full-regression] 고지 형식은 폐지하고 이 형식으로 전환한다.

### 반영 위치:
- `agents/dev/ht-worker.md` — §2.1 TDD 절차에 T1/T2 체계를 흡수하고, "전체 회귀는 완료 직전 1회" 문구를 티어 규약으로 교체한다.
- `agents/dev/ht-reviewer.md` — §3-3에 T3 실행 노드(push/CI)를 고정하고, 변경 범위 판정은 본 명세 (c) 규칙에 위임됨을 명시한다.
- `templates/agents/ROLE-worker.md`, `templates/agents/ROLE-reviewer.md` — 위 교체 문구와 동일한 문장을 그대로 반영한다.
- 기타 프리셋(biz/creator/mkt 등)의 ROLE 템플릿에는 동일 문구를 적용하되, 프리셋별 세부 조정은 PM 승인 후 후속 명세로 예약한다.

## (g) 수용 테스트 목록

| # | 테스트 | 위치 | 검증 |
|---|---|---|---|
| G1 | testmap 기능·결정성 | `tests/test_testmap.sh` | 위 (e) 9건 fixture 기반 |
| G2 | full 실행 빈도 제한 | `tests/test_no_force_full.sh` | 보고서·로그의 [full-regression] 횟수를 세어, 태스크당 full 회귀가 규약 상한(push/CI 노드 기준)을 초과하지 않음을 검증 |
| G3 | T3 승격 조건 | (후속 구현 명세에서 정의) | core 파일 변경·T2 2회 실패·미분류 3가지 조건이 각각 T3 승격 트리거로 판정되는지 검증 |
| G4 | 정본 동시 반영 | grep 기반 검사 | 위 4위치 문서에 교체 문구가 동일하게 존재함을 검증 |
| G5 | 전체 회귀 | `tests/` 전체 (worker [full-regression] 1회 고지) |

## 열린 질문 (PM 확정 필요)
1. `testmap.sh` 위치 확정(`scripts/`) 및 소비 프로젝트 override 방식(파일 vs 환경변수).
2. T2 실패 2회 룰의 정확 상한(1회 후 고정 vs. 2회 후 T3 승격 유지).
