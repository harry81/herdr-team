# TIL: PKM 5인 프리셋 — 순차 파이프라인 구조와 쓰기/읽기 권한 분리 설계

- **날짜**: 2026-10-19
- **작성자**: ht-worker / PKM Preset Team
- **범위**: `templates/pkm/` (preset.conf·AGENTS.md·agents/ROLE-*.md), `docs/specs/pkm-preset-spec.md`

---

## 1. 배경

Obsidian PKM 볼트(SecondBrain)의 노트·볼트 페이지 생성/정리 작업을 기존 `research`(4역할) 프리셋과는 다른 형태로 처리할 필요가 있었다. 조사(researcher)가 **상시가 아닌 on-demand**이고, 실제 볼트 쓰기가 **worker 1명으로 집중**되는 5인 구조를 설계했다. 산출물은 대부분 마크다운·설정 파일이므로, 프리셋은 `templates/<preset>/preset.conf`의 `ROLES`/`LAYOUT`/`PRESET_DESC` 발견(convention over configuration)으로 시딩된다.

---

## 2. PKM 5인 파이프라인 구조

```
PM(agy) → orchestrator → planner → (researcher, on-demand) → worker → reviewer
                                                  ▲ 반송 시 회귀
```

- **순차 파이프라인**: 병렬 팬아웃 없음. 각 단계 완료 즉시 다음 단계를 연결한다(무방치 원칙).
- **researcher on-demand**: planner 명세에 "조사 필요" 표기가 있을 때만 단계 2를 실행하고, 없으면 planner → worker로 직결한다. 이 규칙을 orchestrator 판단 규칙에 명시해 **빈 단계 대기(불필요한 대기 블로킹)를 방지**한다 — 조사가 필요 없는 노트 작업(TIL 기록, 인박스 소화)이 주류인 볼트에서 researcher를 상시로 두면 단계 자체가 낭비된다.
- **리뷰 실패 시 회귀(regression loop)**: reviewer의 `[REQUEST CHANGES]`는 Orchestrator 중재로 **즉시 worker에 반송**된다. 팀 간 직접 협업(worker↔reviewer 직접 prompt)을 금지해 반송·승인 경로를 단일화하고, 판정 로그의 추적성을 보장한다. 재판정은 동일 게이트 기준 1회 재판정, 2회 실패 시 PM 에스컬레이션으로 무한 루프를 차단한다.

---

## 3. 쓰기/읽기 권한 분리 (Scoped Permissions)

| 역할 | 쓰기 권한 | 읽기/실행 |
|------|-----------|-----------|
| orchestrator | **없음** | herdr 상태 조회, git 읽기, 로그 취합 |
| planner | **문서 전용** (`docs/specs/*.md`) | 볼트 전체 읽기 |
| researcher | **없음 (읽기 전용)** | 웹·볼트 전체 읽기 |
| worker | **구현 전용** (볼트 노트, 스크립트·테스트) | 전체 읽기, 스크립트 실행 |
| reviewer | **임시 쓰기** (`10-temp`, 검증 로그) | 전체 읽기, 검사 스크립트 실행, git diff |

### 이 설계의 이유

1. **쓰기 주체 단일화**: 프로덕션 변경(여기선 볼트 노트)을 worker 한 곳으로 모으면 "누가 무엇을 바꿨나"를 한 사람의 생성 목록으로 회수할 수 있고, reviewer의 게이트 5항목 중 "범위 준수(명세 외 파일 0건)" 검증이 귀납적으로 단순해진다.
2. **조율자는 쓰지 않는다**: orchestrator가 직접 파일을 고치면 파이프라인이 우회로(circumvention) 생기고 중계 상태와 실제 저장소 상태가 어긋난다. orchestrator의 권한이 herdr 조회·위임으로 제한되어야 "모든 반송/승인의 무방치 즉시 연결"이 신뢰 가능하다.
3. **읽기 전용 조사의 근거 체계**: researcher가 쓸 수 없으면 수집 내용이 planner 명세의 `## 근거` 섹션(또는 별도 수집 노트)으로만 존재해, reviewer가 "researcher 근거 ↔ 본문 주장 일치"를 검증할 참조 지점이 고정된다.
4. **검증자의 임시 쓰기만 허용**: reviewer가 산출물을 직접 고치면 검증 게이트가 자기 승인으로 둔갑한다. 수정은 발견 즉시 `[REQUEST CHANGES]` 반송으로만 이루어지고, reviewer의 쓰기는 로그·산출물 임시(`10-temp`)에 한정한다.
5. **worker의 삭제 제한**: 노트 정리 작업의 실수 위험 때문에 삭제는 10-temp 보관 후 이동 방식으로만 허용 — 실질 쓰기 역할에 집중되는 파괴적 동작의 자기 방어(self-guard) 규칙이다.

---

## 4. 구현 도킹 (기계적 배선)

- prefix는 **프로젝트명 기반**(SecondBrain은 기존 `sb-`)이므로 템플릿은 `{{PREFIX}}` 치환 양식으로만 작성하고, 프리셋 단위로 도메인 특화 ROLE 문서를 `templates/pkm/agents/ROLE-*.md`에 두면 **preset-local 우선 해석**이 공용 템플릿을 건드리지 않고 PKM 규칙을 주입한다.
- 프리셋 추가는 디렉터리 하나(`templates/<name>/preset.conf` + `AGENTS.md`)로 끝난다 — 디스커버리가 하드코딩 대신 파일 시스템에서 열거하므로, `--list-presets`/TUI/시딩/CI 게이트가 모두 동일 근거(파일 존재)로 일관되게 확장된다.

---

## 5. 교훈

- 문서 중심 산출물도 **배선(discovery/parse/gen) 검증 테스트**가 필요하다: 파일 존재, `{{PREFIX}}` 잔존 0건, 시딩 산출물 구조, preset-local 우선 적용 등을 전용 스위트(`tests/test_pkm_preset.sh`)로 고정해 회귀를 막았다.
- 정본 계약 문서(AGENTS.md 3종: 루트·정본·템플릿)는 한 문구라도 3파일 동시 반영이 원칙이다 — 루트만 고치면 write-back/reseed 경로가 결함을 재생한다.
