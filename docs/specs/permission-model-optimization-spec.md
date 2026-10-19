# Spec: 권한 모델 아키텍처 최적화 — 최소 권한 × 자동화 균형 설계

- 작성: ht-planner / 2026-10-19
- 범위: herdr-team 프리셋이 시딩하는 OpenCode agent 권한 설정 전반 (`bin/herdr-team`, `templates/opencode-agents/ROLE-*.md`, 각 프로젝트 `.opencode/agents/<prefix>-<role>.md`)
- 회신 규약: 경로 + 1줄 요약

## 0. 현행 조사 (사실)

### 0.1 현행 권한 설정 방식
- agent 권한은 **V1형 frontmatter 맵**으로 정의된다(`.opencode/agents/sb-planner.md` 실태):
  ```yaml
  permission:
    edit: deny
    task: deny
    bash:
      "*": ask          # 화이트리스트 밖은 전부 수동 대기
      "pwd": allow
      "git status*": allow
      ... (40~50개 수동 등록)
  ```
- `templates/opencode-agents/ROLE-orchestrator.md`에도 동일한 ~50개 allow 목록이 hardcoded되어 프리셋별로 ROLE 파일 복제·치환 시딩 시 **역할×프리셋 단위로 동일 allowlist가 중복 관리**된다.
- 대조적으로 `ROLE-worker.md`는 `task: deny`만 정의(§0.2) → worker의 모든 shell 명령은 기본 ask로 블로킹.
- **V2 문서 사실(opencode.ai/v2/docs/permissions)**:
  - V2는 `permissions: [{action, resource, effect}]` **순차 배열, 뒤가 이긴다(last-match wins)**. broad rule 후 narrow exception 배치 지원.
  - effect는 allow/deny/ask, 불일치 시 기본 ask. deny는 절대 우선.
  - `policies`(hard-deny)는 allow/ask를 deny로 전환하는 상위 강제선.
  - 대화형 "Allow always" 승인은 프로젝트 스코프 durable allow로 저장(선택된 패턴이 allow 규칙으로 누적).
  - ⚠️ 문서 원문 경고: shell은 호스트 권한으로 실행되며 커맨드 텍스트 기반 위험 판별은 best-effort → **narrow allowlist 권유**.
  - V1 필드 `permission/bash/task`는 deprecated로 문서에 명시 경고.

### 0.2 도킹 대상 구조
- 시딩 파이프라인: `herdr-team --preset X` → `templates/opencode-agents/ROLE-<role>.md` → `.opencode/agents/<PREFIX>-<role>.md` 생성. preset.conf는 `PRESET_DESC/ROLES/LAYOUT`만 보유.
- 테스트 체계: `tests/test_*.sh`(bash, fake herdr shim 방식) — 생성물의 텍스트·구조를 검증하는 패턴이 존재: 권한 설정 테스트도 동일 방식 가능.

## (a) 현행 방식 문제점 분석

| 축 | 문제 (사실 기반) |
|---|---|
| 블로킹 빈도 | worker 등 shell 규칙 미정의 역할은 모든 shell이 `ask` → 파이프라인은 `--wait` 순차 연결 구조라 대화형 승인 대기가 곧 병목. AGENTS.md 가드레일의 "Allow once 블로킹 해제" 절차 존재 자체가 상시 발생의 증거. |
| 유지비 | 역할마다 40~50개 allow를 수동 관리. 신규 명령(예: `opencode api`) 추가 시 ROLE 파일 수×프리셋 수 중복 편집. |
| 사용자 피로 | once/always 승인 매 세션·pane 재노출; 일상 명령까지 반복 승인 강요. |
| 실수 위험 | 승인 피로 누적 → "Allow always" 난발로 `shell: *` 수준 allow 확장 → 최소 권한 무력화. 반대로 보수적 승인 회피는 파이프라인 교착. |
| 결정성 | 유저 승인 내역이 프로젝트별·시점별로 상이 → 동일 프리셋이라도 권한 상태 비결정(재현/감사 불가). |

핵심 판단: **개별 명령 화이트리스트는 최소 권한은 산출하지만 결정성·유지비·생산성에서 실패. 최소 권한의 단위를 명령어→(위험 계층 × 도메인 번들 × 역할 프로파일)로 올려도 보안은 유지된다.**

## (b) 후보 모델 비교표

| # | 후보 | 보안 강도 | 생산성 | 구현 복잡도 | 실패 모드 | 마이그레이션 비용 |
|---|---|---|---|---|---|---|
| 1 | 현행: 개별 명령 allowlist + `"*": ask` | ○ (narrow allowlist로 문서 권유 부합) | ✗ (누적 승인 병목, 유지비 큼) | 0 (무변경) | 피로 승인으로 규칙 훼손 | — (baseline) |
| 2 | 디렉터리/패턴 스코프 권한 (경로 글롭 allow) | ◎ (edit/read가 자원(경로) 단위로 직접 제한 — 문서 지원 `edit: packages/docs/*.mdx`) | △ (shell 생산성엔 무표: shell 경로 추론은 best-effort) | 낮음 (edit/read에 글롭) | 경로 추론 우회 시도 | 중 (frontmatter V2 변환) |
| 3 | 프로젝트 컨텍스트 프로파일 (프리셋별 권한 세트) | ◎ (프리셋 역할 경계 = 권한 경계) | ◎ (프리셋 단위 일괄 적용) | 중 (시딩기 확장) | 프로파일이 균열되면 역할 격리 붕괴 | 중 (preset.conf·시딩기 변경) |
| 4 | 위험도 계층형 분류 (read-only/additive/destructive/privileged) | ◎ (계층별 기본 고정 + hard-deny 존재) | ◎ (L0/L1 무블로킹, L2만 ask) | 중 | 파괴 패턴 나열식 차단의 근본 한계(문서 경고 → 보완 필요) | 중 |
| 5 | 도메인별 실행 세트 (테스트·빌드·git·배포 묶음) | △~○ (묶음은 coarse: `git *`은 push 포함) | ◎ (번들 일괄 allow, 유지비 축소) | 낮음 (선언적 프래그먼트) | coarse 번들이 L2/L3 명령을 함께 열어줌 → 계층 조합 필수 | 낮음 |
| 6 | 수동 Ask-only 운영 (현행 조작 모델) | ✗ (피로로 항상 always 면적) | ✗ | 0 | 피로 승인 | 기각 |

## (c) 추천 아키텍처: 계층(4) + 번들(5) + 프로파일(3) + 스코프 글롭(2) 조합

**조합 이유**: 어느 한 모델이 모든 위험 축을 커버하지 못한다.
- 4(계층) = "어떤 effect가 어느 한계"의 보안 골격.
- 5(번들) = 정합적 업무 묶음을 allow로 일괄 편성(생산성·유지비 축소).
- 3(프로파일) = 역할 경계(orchestrator 쓰기 금지 등)를 프리셋 단위로 결정(아키텍처 정합성, 기존 Scoped Permissions 계승).
- 2(스코프 글롭) = edit/read의 자원(경로) 축 직결 고정(`docs/specs/*` 볼 전체 등 기존 스코프드 권한 규칙의 유지). shell 글롭은 문서 경고대로 보안 주체로 쓰지 않고 allow-list 편성용으로만 사용.

### 계층 정의 (도킹 표준)
| 계층 | 정의 | 기본 effect | 예 |
|---|---|---|---|
| L0 read-only | 상태 조회·읽기 | allow | `ls`, `cat`, `git status/diff/log`, `herdr agent list/read`, `herdr pane list/read` |
| L1 additive | 멱등 생성·편집·테스트·빌드(역할 프로파일이 열 자원 한정) | allow | `edit (프로젝트 경로 글롭)`, `pytest -q`, `npm test/build`, `python scripts/*` |
| L2 destructive | 파괴적·영구 변경 | 항상 **ask** | `git push`, `rm <프로젝트 파일>`, `herdr pane close`, `git reset --hard` |
| L3 privileged | 권한상승·서브쉘·업로드-실행·확산 삭제 | **policies hard-deny** (PM 사외 승인 임시 상향만 예외) | `sudo *`, `curl * | sh`, `rm -rf *`, 서브셀 백틱·`${...}` 삽입 |

### 횡단 규칙 (최소 안전선)
1. L3는 `policies`로 영구 hard-deny — 역할·프로파일 무관, 예외 없음(임시 상향은 정식 승인 절차로만).
2. L2는 ask이며 승인은 `Allow once`만 상정. `Allow always`는 L0/L1에만 허용.
3. 미분류는 ask(fallback). 다만 L0/L1 번들이 커버 못한 실제 생산 명령이 반복 ask되면 번들을 갱신하는 운영 루프 명시.
4. "Allow always" 누적은 선언적 프로필로 수렴: 일시적 always 저장 → 다음 작업 주기에 프로필 JSON으로 정규화(감사 가능).

### 선언적 구성 (신규 파일, 결정성 확보)
```
templates/permissions/
  baseline.json                 # 전역 공통: L0 allow 번들 + L2 ask + L3 policies hard-deny
  bundle/<name>.json            # 도메인 번들: git-inspect, python-test, node-build, pkm-vault-edit, herdr-read, opencode-api-read...
  profile/<preset>/<role>.json  # 역할 조합: includes=[bundle...], 좁은 allow/deny/ask 오버라이드
```
- preset.conf 확장은 불필요: profile 경로가 프리셋명을 이미 품음(`profile/dev/*.json`) → ROLES에서 역할 이름으로 인덱싱.
- 기존 ROLE-*.md frontmatter `permission:`은 **계약 축(edit/task deny 등 경계)만 유지**하고 shell 규칙은 프로젝트 jsonc로 이관.

### 산출 예시 (worker 프로필로 병합된 `.opencode/opencode.jsonc`)
```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permissions": [
    { "action": "shell", "resource": "*", "effect": "ask" },
    // baseline.json (L0 allow + narrow)…
    { "action": "shell", "resource": "git status*", "effect": "allow" },
    { "action": "shell", "resource": "git diff*", "effect": "allow" },
    // bundle/python-test.json …
    { "action": "shell", "resource": "pytest*", "effect": "allow" },
    // profile/dev/worker.json (역할 오버라이드)…
    { "action": "edit", "resource": "*.md", "effect": "allow" },
    { "action": "shell", "resource": "git push*", "effect": "ask" },
    { "action": "shell", "resource": "rm -rf *", "effect": "deny" }
  ],
  "policies": [
    { "action": "tool.use", "resource": "shell:sudo *", "effect": "deny" },
    { "action": "tool.use", "resource": "shell:curl * | *", "effect": "deny" }
  ]
}
```

## (d) 권한 판정 알고리즘 + 예외/에스컬레이션

판정 순서 (V2 규격 준용, 아키텍처 명시):
1. `policies` hard-deny 매칭 → 즉시 거부 (에스컬레이션 불가 보장).
2. agent rules → global rules 순으로 **last-match-wins** 판정 (문서 표준 그대로).
3. 매칭 없음 → ask (기본 안전선).
4. ask인 경우: L2 판정이면 대화형 승인 (`Allow once`) 요청. Orchestrator는 승인 대기 블로킹 해제 절차에 따르되 **파괴적 위험 명령(`rm -rf`, 캐시 전역 삭제 등)은 반드시 사용자에게 확인** — AGENTS.md 가드레일 최소 안전선 준용.
5. "Allow always" 승인은 일시 허용으로만 운영 → 정기 정규화 루프(4항)에서 프로필로 영속화.

에스컬레이션: L3 필요 → PM의 명시적 승인 + 임시 프로필 상향(기간·범위 기록) → 세션/pane 재생성 시 자동 해제. L2 반복 발생 → 번들 갱신 제안(Planner 명세로 회기).

## (e) 구현 대상 파일·설정 포맷·수용 테스트 기준

| 대상 | 변경 |
|---|---|
| `templates/permissions/` (신규) | baseline.json + bundle/* + profile/<preset>/<role>/* 선언 |
| `templates/opencode-agents/ROLE-*.md` | frontmatter의 긴 bash allowlist 축소 → 계약 경계(edit/task deny) + worker의 L0/L1 프로필 include로 대체 자동화 |
| `bin/herdr-team` | 시딩 시 `profile/<preset>/<role>.json`의 include 병합 결과를 해당 프로젝트 `.opencode/opencode.jsonc`에 생성(순수 함수형 병합, jq) |
| 프로젝트 저장소 (SecondBrain 등) | 시딩 결과물로만 — 수동 편집 금지(auto-gen 표시 유지) |

**설정 포맷 원칙**: V2 `opencode.jsonc`가 single source of truth. agent frontmatter permission은 역할 계약 경계 전용으로 축소. V1형 형식과 공존 허용이지만 신규 번들은 V2형으로만 관리하고 점진 이관.

**수용 테스트 기준** (`tests/test_permissions_*.sh`, 기존 fake herdr shim+생성물 검사 방식 준용):
1. **병합 결정성**: baseline+bundle+profile 3층 병합이 기대 effect로 결정하게 판정되는지(last-match-wins 시나리오, 동일 리소스 allow/ask/deny 충돌 케이스 최소 3건). `bash tests/test_permissions_merge.sh`.
2. **보안 게이트**: L3 명령(`sudo`, `rm -rf`, `curl|sh`)에 hard-deny policy 존재 검증 + 어떤 프로필도 그 allow와 ask로 극복할 수 없음(e2e deny 전달) 확인.
3. **생산성 제계**: worker 기준 대표 작업 명령 10종이 ask 아닌 allow로 판정되는 것을 프로필로 정의·검증(잔여 ask 목록은 명시 리스트로 보고).
4. **시딩 통합**: `bash tests/test_permissions_seed.sh` — 실제 시딩 dry-run 실행 후 `.opencode/opencode.jsonc` 생성·JSONC 유효성·`$schema` 존재 검증.
5. **전체 회귀**: `tests/` 정체 통과 (worker [full-regression] 1회 고지).

## 열린 질문 (PM)
1. L2 `git push`를 pkm/dev 프리셋 worker에 ask로 남길 것인지 deny로 고정할 것인지(운영 습관에 따라).
2. V1(frontmatter 긴 allowlist)의 전량 이관 시점 — 공존 후 2단계 이관 또는 즉시 교체.
