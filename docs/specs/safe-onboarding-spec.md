# Safe Onboarding Spec — 온보딩 안전성 개선 (gitignore 멱등 / 루트 AGENTS.md 보호 / 충돌 가드)

- 상태: draft (planner 산출물, `ht-worker` 구현 대기)
- 대상 코드: `bin/herdr-team` (`setup_templates`, `sync_root_agents`, 인자 파싱), `tests/`
- 범위 밖: pane 분할/시작 로직, permissions 시딩, 템플릿 내용 자체

---

## 1. 요구사항 요약 & 목표

`herdr-team`은 대상 저장소에 `.herdr-team/`, `.opencode/`, `agents/<preset>/`, 루트 `AGENTS.md`를 생성하지만 (1) 사용자 저장소의 `.gitignore`를 보강하지 않아 `git status`가 더럽혀지고, (2) 루트 `AGENTS.md`를 `cp`로 덮어쓰면서(active 상태 분실·`--force` 시) 사용자 편집분을 유실할 수 있으며, (3) `agents.md`/`AGENTS.md` 대소문자 공존, `agents`가 디렉터리가 아닌 경우 등 비정상 상태에서 원시 에러로 사망한다.

| # | 요구사항 | 목표 |
|---|---|---|
| R1 | gitignore 멱등 보강 | `.herdr-team/`, `.opencode/` 항목을 "없을 때만 1회" 추가. 기존 내용·끝 개행 보존, 재실행 무변경, 파일 누락 시 생성, dry-run 계획 출력 일치 |
| R2 | 루트 AGENTS.md 자산 보호 | 덮어쓰기 전 타임스탬프 백업 + 기존 사용자 본문 보존 병합(관리 섹션 방식). 재실행 시 중복 섹션 없음 |
| R3 | 충돌 가드 | 대소문자 `agents.md`+`AGENTS.md` 공존 시 덮어쓰기 금지·명시 경고, `agents`가 일반 파일이면 안전 중단(명확한 에러 + 정의된 종료코드), **어떤 쓰기도 발생 전** fail-fast |

### 현황 팩트 (코드 근거)

- gitignore 처리 코드가 존재하지 않음. `.herdr-team`(L455-456, 965), `.opencode/agents`(L704-705, 1044)는 생성하지만 무시 등록은 전무.
- `sync_root_agents` (L468-488): (4b)에서 `cp "$canon/AGENTS.md" "$root"` — 백업 없음. write-back(4a)은 `active` 상태가 있고 preset이 다를 때만. **active가 없거나(`""`) 손상된 경우(L471-474 경고 후 active="") canon이 stale이면 루트 사용자 편집분이 무손실 write-back 없이 덮여 씀.** `--force` 역시 무백업 덮어쓰기.
- 백업 선례 존재: `setup_permissions`의 `cp -p "$global" "$global.bak"` (L713-714).
- 블록 치환 선례 존재: `permissions_inject_frontmatter` (L658-672) — awk로 frontmatter 블록 교체. 관리 섹션 구현의 패턴 원본.
- `setup_templates` (L904-1003): `mkdir -p "$canon" "$CWD/.herdr-team"` (L965). `$CWD/agents` 또는 `$CWD/.herdr-team`이 일반 파일이면 `set -euo pipefail`(L19) 하에 mkdir 원시 에러로 사망 (tests/test_preset.sh §32가 rc≠0만 단언, 메시지 품질 미검증).
- 인자 파싱 (L218-239): `--*` 미지원 옵션 → `error: 알 수 없는 옵션` + exit 2. 신규 플래그는 이 루프에 추가.
- 종료코드 관례: 2=검증/인자 에러, 1=런타임 에러, 127=의존성 부재. 가드는 2로 통일.
- 테스트 관례: `tests/test_preset.sh`의 PASS/FAIL 카운터 + `ok/bad/assert_*` 헬퍼 + herdr stub + `iso_run`(--cwd tmp) 패턴. `scripts/testmap.sh` L37의 `bin/herdr-team` 매핑에 스위트 등록 필요.

---

## 2. 아키텍처 / 데이터 흐름

```
main 인자 파싱 (L218)
  └─ 신규: --no-gitignore, --no-backup  (unknown --* → exit 2 불변)
실행 직전 (setup_templates 호출 전, 쓰기 0 시점):
  └─ guard_preconditions()   ← R3. 실패 시 exit 2, 부분 쓰기 없음
setup_templates (L904)
  ├─ ensure_gitignore()      ← R1. git repo 내부에서만 동작, 백그라운드 무음
  ├─ (기존) canon 시딩 (1)(2)
  └─ sync_root_agents (3)    ← R2 적용
        ├─ write-back(4a): 루트 → agents/<active>/AGENTS.md
        │    └─ 변경: 루트 전체가 아닌 "관리 섹션 내용만" 추출해 스냅샷
        └─ activate(4b): agents/<preset>/AGENTS.md → 루트
             └─ 변경: 타임스탬프 백업(cp -p, 선례 L713) 후
                      "기존 본문 보존 + 관리 섹션 치환" 병합 쓰기
```

### R2 병합 전략 비교 (채택: A)

| 방안 | 동작 | 장점 | 단점 | 판정 |
|---|---|---|---|---|
| **A. 관리 섹션 (채택)** | 루트에 `<!-- herdr-team:managed BEGIN -->…END` 마커 블록. 본문은 위에 그대로 유지, 활성화 시 블록만 awk 치환 | 사용자 본문 100% 보존, 단일 파일(에이전트가 읽는 경로 불변), 코드베이스에 동일 패턴 선례(`permissions_inject_frontmatter`) | 마커 파싱 필요 | ✅ 최소 변경·무손실 |
| B. 별도 유지 파일 | 루트는 1행 포인터만 추가, 내용은 `.herdr-team/AGENTS.managed.md` | 루트 충돌 최소화 | 루트를 결국 수정(1행), opencode/herdr agent가 포인터를 따라 읽지 않음(문서 파싱 불가 → 기능 깨짐), 파일 2개 관리 | ❌ |

**A의 정의:**
- 마커: 시작 `<!-- herdr-team:managed BEGIN (preset=<PRESET>) -->`, 종료 `<!-- herdr-team:managed END -->`.
- activate(4b) 시: (i) 루트 존재 → `cp -p root → .herdr-team/backup/AGENTS.md.<UTC 타임스탬프>.bak` 후, 기존 본문(마커 블록 **제외한** 전체) 유지 + 마커 블록을 신규 canon 내용으로 치환해 원자적 쓰기(tmp→mv). (ii) 루트 부재 → canon 내용만 마커로 감싸 생성.
- write-back(4a) 시: 루트에서 마커 블록 내부 내용만 추출해 `agents/<active>/AGENTS.md`에 기록 (canon은 "프리셋 순수 내용" 유지 → 왕복 무손실, 사용자 본문이 canon 오염되지 않음).
- 재실행(같은 preset, 비FORCE): 루트 불변 (기존 §30 테스트 유지). 마커가 이미 있어도 블록이 1개임이 보장됨(치환 방식).
- 마커가 정확히 1쌍 존재하는지 검사: 0쌍→삽입, 1쌍→치환, 2쌍 이상(수동 복붙 등)→가드 위반(R3 성격)으로 경고 후 종료 2.
- `--force`: 기존 의미(재시딩) 유지 + **백업은 항상 선행** (`--no-backup`으로만 면제).

### R1 정의

- 동작 위치: `$CWD/.gitignore` (git repo 하위든 루트든 CWD 기준 — `.herdr-team`도 CWD에 생성되므로 디렉터리 단위 gitignore로 유효).
- 트리거: `git -C "$CWD" rev-parse --show-toplevel` 성공 시에만 (비 git 디렉터리 → 생략 + log 1줄).
- 추가 항목: 마커 주석 `# herdr-team` + `.herdr-team/` + `.opencode/`.
- 멱등 판정: 기존 행을 "행 끝 공백 trim + 후행 슬래시 제거"로 정규화해 `.herdr-team` / `.opencode` 토큰 매칭. 이미 매칭되면 그 항목은 미추가 (대소문자 비교는 그대로 — `.OpenCode`는 다른 항목으로 간주).
- 쓰기: tmp 파일에 기존 바이트 그대로 복사 → 끝 개행 없으면 개행 1개 보강 → 부족분만 append → `mv` 원자 치환. 기존 내용은 1바이트도 편집하지 않음.
- dry-run: `+ gitignore: append .herdr-team/ .opencode/ → <path>` 형태 계획 출력, 실제 쓰기 0 (기존 §34 불변식 유지).

### R3 정의 (guard_preconditions, 쓰기 전 fail-fast)

| 가드 | 조건 | 동작 | 종료코드 |
|---|---|---|---|
| G1 케이스 충돌 | `$CWD/AGENTS.md`와 `$CWD/agents.md`가 **서로 다른 파일로** 동시 존재 (case-sensitive fs) | 두 경로를 명시한 경고 출력, 루트 activate/write-back 전면 금지, 즉시 중단 | 2 |
| G2 agents 비정상 | `$CWD/agents`가 존재하나 디렉터리가 아님(일반 파일/심링크-파일) | `error: <path> 가 디렉터리가 아닙니다 — agents/<preset>/ 시딩에 실패합니다. 파일을 정리 후 재실행하세요.` | 2 |
| G3 canon 비정상 | `$CWD/agents/<PRESET>`이 존재하나 디렉터리가 아님 | 동일 문안 | 2 |
| G4 state 비정상 | `$CWD/.herdr-team`이 존재하나 디렉터리가 아님 | 동일 문안 | 2 |
| G5 마커 다중 | 루트 AGENTS.md에 관리 섹션 마커가 2쌍 이상 | 경고(수동 편집 개입 안내), 중단 | 2 |

- 심링크-디렉터리는 `-d` 참이므로 통과(정상). 심링크-파일은 G2/G3/G4로 중단.
- G1은 case-insensitive fs(macOS 기본 APFS)에서 발생 불가 → 테스트는 Linux(case-sensitive) 기준, fs 특성은 엣지 표 참조.

---

## 3. CLI 플래그 제안 (인자 파싱 L218 루프 + usage L147)

| 플래그 | 기본 | 의미 |
|---|---|---|
| `--no-gitignore` | off | R1 보강 생략 (CI 등 읽기전용 CWD 대응) |
| `--no-backup` | off | R2 타임스탬프 백업 생략 (전문가용 탈출구; 병합 자체는 유지) |

- dry-run 계획 출력은 플래그 상태를 반영해야 함(플래그 off면 해당 `+` 라인 미출력).
- usage()에 두 플래그 문서화 1줄씩 추가. 그 외 신규 플래그 없음 (마커 방식은 자동).

---

## 4. TDD 테스트 케이스 목록

신규 스위트: **`tests/test_safe_onboarding.sh`** (test_preset.sh의 헬퍼/stub/iso_run 패턴 복제).

### R1 — gitignore 멱등 보강 (TC-GI)
1. git repo tmp CWD, `.gitignore` 부재 → 실행 후 생성, 3행(마커+2항목) 존재, exit 0
2. 기존 `.gitignore`("node_modules/\n") → 실행 후 원본 행 보존 + 신규 3행 append, 끝 개행 정상
3. **멱등**: 동일 실행 2회 → `.herdr-team`/`.opencode`/`# herdr-team` 각 1회만 (`grep -c` 카운트 — test_install.sh §2 마커 패턴 재사용)
4. `.opencode`(슬래시 없음) 이미 존재 → `.opencode` 중복 추가 없음, `.herdr-team/`만 추가
5. 끝 개행 없는 파일("x" 1바이트) → 기존 바이트 보존 + 개행 보강 후 append
6. `--dry-run` → `+ gitignore:` 계획 라인 출력 + **파일 미생성·미변경** (실제 쓰기 0)
7. dry-run 계획과 실제 실행 결과 일치: dry-run에서 `append` 출력된 케이스는 실실행에서도 append, `이미 있음`이면 미출력
8. 비 git 디렉터리 → 보강 생략 log, `.gitignore` 미생성, exit 0
9. `--no-gitignore` → 어떤 상태에서도 무시 등록 없음
10. 읽기전용 `.gitignore`(chmod 444, 쓰기 불가 dir) → 명확 에러, exit ≠ 0, 기존 파일 무손상

### R2 — 루트 AGENTS.md 보호 (TC-BA)
11. 신규 설치(루트 부재) → 루트 생성, 내용이 마커로 감싸진 canon과 동일, 백업 파일 없음
12. 루트에 사용자 본문 존재 + active 없음 + canon stale → 실행 후 **사용자 본문 원문 보존** + 마커 블록은 신규 preset 내용
13. 덮어쓰기 발생 케이스(12) → `.herdr-team/backup/AGENTS.md.<ts>.bak` 1개 생성, 내용 == 실행 전 루트 원본
14. **재실행(같은 preset, 비FORCE)** → 루트 바이트 동일(`cmp`), 마커 블록 1쌍, 백업 신규 생성 없음
15. preset 전환(dev→mkt) → write-back으로 `agents/dev/AGENTS.md`에 마커 내부 내용만 스냅샷(사용자 본문 미포함), 루트 본문 유지 + mkt 블록 치환, dev→mkt→dev 왕복 시 dev canon 복원
16. `--force` → 백업 선행 후 재시딩 (백업 부재 → 실패)
17. `--no-backup` → 백업 없이 병합 진행
18. 마커 2쌍 수동 주입 → exit 2, 경고에 "마커" 문구, 쓰기 0

### R3 — 충돌 가드 (TC-GD)
19. `AGENTS.md` + `agents.md` 공존 → exit 2, stderr에 양쪽 경로 명시, **`agents/`, `.herdr-team/`, `.opencode/` 어떤 쓰기도 없음**(실행 전 가드 증거)
20. 가드 후 재실행 가능성: 원인 제거(agents.md 삭제) 시 정상 진행
21. `$CWD/agents`가 일반 파일 → exit 2, 에러에 절대경로 + "디렉터리가 아닙니다" 문구 (mkdir 원시 에러 없음)
22. `$CWD/agents/<preset>`이 일반 파일 → exit 2, 동일 문구
23. `$CWD/.herdr-team`이 일반 파일 → exit 2 (기존 §32 'blocker' 케이스 격상 — rc≠0 → 명확 메시지 + rc==2)
24. 심링크-디렉터리 `agents` → 정상 통과 (회귀 방지)
25. dry-run에서는 G1~G4 검출 시에도 계획 출력만 하고 exit 2 (쓰기 0 불변)

### 기존 스위트 재사용 지점
- `tests/test_preset.sh` §30(same preset 루트 불변), §34(dry-run 쓰기 0), §32(state 실패 유지), §24-26(왕복 무손실) → **모두 계속 통과해야 함** (회귀 게이트). §32의 rc≠0 단언은 R3 도입 후 rc==2로 강화 가능(선택).
- `tests/test_install.sh` §2 마커 카운트 패턴(`grep -cF`) → TC-GI-3 멱등 검증에 동일 기법 적용.
- herdr stub / tmp CWD / `trap rm -rf` 패턴 → 그대로 복제.

---

## 5. 엣지 케이스 표

| # | 상황 | 기대 동작 | 비고 |
|---|---|---|---|
| E1 | `.gitignore` 심링크 | 대상 파일 기준으로 read/append (`-f`/`-e`가 심링크 따라감) | 깨진 심링크면 생성 시도가 target 생성 → 허용(드묾), 명시 금지 없음 |
| E2 | `.gitignore` CRLF | 기존 CRLF 행 보존, append만 LF | 혼합 개행 허용 명시 |
| E3 | `.gitignore`에 주석 섞인 기존 항목(`.opencode # note`) | 정규화 매칭으로 중복 방지 | trim + 슬래시 제거 |
| E4 | CWD가 git repo 하위 디렉터리 | CWD의 `.gitignore`에 기록 (디렉터리 단위 유효) | repo root가 아님에 유의 |
| E5 | 루트 AGENTS.md 심링크(예: repo가 링크로 관리) | 백업은 링크 대상 내용 기준(cp는 역참조), 치환은 링크 경로에 쓰기 | macOS APFS 케이스-불감: `agents.md`만 있으면 `AGENTS.md` 쓰기가 동일 파일 덮음 → R2 백업+병합이 이를 커버 (G1 미발동, 정상) |
| E6 | 타임스탬프 중복(1초 내 재실행) | 파일명 `<ts>` 충돌 시 `.bak.<ts>.<n>` 접미사 | 백업은 activate(덮어쓰기) 시에만 생성되므로 실질 발생 낮음 |
| E7 | backup 디렉터리 생성 실패(읽기전용) | 에러 + 중단, 루트 미변경 | 백업 실패 = 진행 금지 (`--no-backup`으로만 우회) |
| E8 | 루트 본문에 마커와 유사 문자열이 코드블록 내 존재 | BEGIN/END 정확 쌍 매칭만 인정 (라인 전체 일치) | awk 라인 단위 매칭 |
| E9 | `--templates-only` | R1/R2/R3 전부 적용 (템플릿 단계가 R1~R3 소재) | pane 분할만 생략 |
| E10 | `--no-template` | R1~R3 전부 생략 (기존 §33 불변식 유지) | |
| E11 | CWD에 쓰기 권한 없음 | R1/R2/R3 각각 명확 에러, 원본 무손상 | |

---

## 6. 변경 파일 목록

| 파일 | 변경 |
|---|---|
| `bin/herdr-team` | `guard_preconditions()`, `ensure_gitignore()`, `write_managed_root()`/마커 추출 유틸, `sync_root_agents` 백업+병합 개조, 인자 파싱 2플래그, usage() 2줄 |
| `tests/test_safe_onboarding.sh` | **신규** — TC-GI/BA/GD 25케이스 |
| `scripts/testmap.sh` | L37 `bin/herdr-team` 매핑에 `tests/test_safe_onboarding.sh` 추가 |

(선택) `tests/test_preset.sh` §32 rc 강화, README 플래그 문서 — 필수 아님.

---

## 7. Task Breakdown (ht-worker, TDD)

| Task | 내용 | 완료 기준 | TDD 대상 |
|---|---|---|---|
| **TB-1** | `ensure_gitignore()` + `--no-gitignore` 플래그 + dry-run 계획 | TC-GI 1~10 PASS. 기존 §34(쓰기 0) 유지 | Red: TC-GI-1,3,6 먼저 |
| **TB-2** | R2 백업 + 관리 섹션 병합 (`write_managed_root`, write-back 추출) + `--no-backup` | TC-BA 11~17 PASS + test_preset §24-26/§30/§34 회귀 PASS | Red: TC-BA-12,13,14 먼저 |
| **TB-3** | `guard_preconditions()` (G1~G5) — `setup_templates` 호출 전 배치, dry-run 계획 반영 | TC-GD 18~25 PASS, 부분 쓰기 0 검증 포함 | Red: TC-GD-19,21 먼저 |
| **TB-4** | testmap 등록 + usage 문서화 + 전체 회귀 | testmap.sh가 변경 시 신규 스위트 노출, `tests/test_preset.sh`/`test_install.sh` 전부 PASS, `[T2 scoped] bash scripts/testmap.sh → N passed` 고지 | — |

- 실행 티어: 편집 루프 T1(대상 스위트), 태스크 완료 시 T2(`scripts/testmap.sh` 매핑 — `bin/herdr-team`은 코어 경로이므로 push/CI에서 T3 승격 안내 확인).
- 인터페이스 예시 (구현 아님): `ensure_gitignore`는 `DRY_RUN=1` 시 plan 출력 후 return 0; `write_managed_root root canon preset`는 (backup→merge) 순서 보장.

---

## 8. 열린 질문 (구현 전 결정 권장)

1. 백업 보존 정책: 무제한 vs 최근 N개 유지 — 현재는 무제한(YAGNI), 디스크 부담 제보 시 상한 추가.
2. `.opencode/` 전체 무시 vs `agents/` 하위만 무시: 현재 제안은 디렉터리 전체. 사용자가 `.opencode/opencode.jsonc`를 커밋하고 싶은 경우 충돌 가능 → 항목을 `.herdr-team/` + `.opencode/agents/`로 좁힐지 결정 필요 (기본안: 전체, 기존 항목 있으면 존중).
3. write-back이 "마커 내부만" 스냅샷으로 바뀌면서, 구버전(마커 없는) 루트에서 업그레이드하는 사용자의 첫 전환 시 본문 전체가 스냅샷되는 문제 → 첫 실행(마커 0쌍)일 때는 스냅샷 대신 본문 전체를 백업파일로만 남기고 스냅샷 생략하는 안. 기본안: 마커 0쌍이면 기존 동작(전체 write-back) 유지, 병합 후부터 마커 기준.
