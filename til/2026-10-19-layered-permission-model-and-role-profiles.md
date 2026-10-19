# TIL: 2026-10-19 계층형 번들 + 역할 프로파일 기반의 선언적 권한 아키텍처

## 1. 문제 상황 및 동기
- 기존 방식: 개별 명령어 단위로 `"*": ask` 기반의 40~50줄짜리 하드코딩된 allowlist를 에이전트마다 수동 등록.
- 한계:
  1. 명령어 변경/추가 시 모든 프리셋의 ROLE 파일을 일일이 편집해야 하는 높은 유지비.
  2. `worker`가 TDD 실행(`pytest`, `chmod`, `git add`) 시마다 수동 승인(`ask`)에 걸려 파이프라인이 멈추는 극심한 병목.
  3. 반복되는 팝업으로 인해 사용자가 무심코 "Allow always"를 남발하여 최소 권한 경계가 훼손되는 피로 승인 역효과.

## 2. 해결 방안: 계층형 번들 + 역할 프로파일 (Layered Bundle & Role Profile)
명령어 1줄씩 나열하는 방식에서 벗어나 **위험도 계층(Tier) × 도메인 번들(Bundle) × 역할 프로파일(Profile)**의 3단계 선언적 구조로 설계:

### (1) 위험도 4단계 계층 (Tiered Security)
- **L0 (Read-Only)**: 상태 조회 및 읽기 (`ls`, `cat`, `git status/diff/log`, `herdr agent list`) ➔ **무조건 `allow`**
- **L1 (Additive)**: 멱등 실행, 빌드, 테스트, 로컬 마크다운/코드 작성 ➔ **역할 프로파일별 `allow` (TDD 무블로킹 달성)**
- **L2 (Destructive)**: 원격 영향 및 파괴적 명령 (`git push`, 단일 파일 삭제 `rm <file>`) ➔ **수동 승인 유지 (`ask`)**
- **L3 (Privileged)**: 시스템 파괴 및 권한 탈취 (`sudo *`, `rm -rf *`, `curl * | sh`) ➔ **전역 최상위 `hard-deny` (사용자 승인 불가, 원천 차단)**

### (2) 구조 및 파일 배치 (`templates/permissions/`)
- `baseline.json`: L0 전역 allow + L2 ask fallback + L3 policies hard-deny.
- `bundle/*.json`: 업무 단위 번들 (`core-read`, `git`, `test-build`, `docs-write`, `vault-write`, `herdr-read`, `opencode-api`).
- `profile/<preset>/<role>.json`: 6개 프리셋의 25개 역할별 조합 (dev, pkm, biz, mkt, creator, research).

### (3) OpenCode V2 런타임 소비 표면 정합성
- **역할별 스코프 규칙**: 에이전트 마크다운 frontmatter의 `permissions:` 배열로 주입 (`opencode debug agents`로 실측 검증).
- **L3 정책 차단**: `.opencode/opencode.jsonc`의 최상위 `policies` 블록으로 주입 (frontmatter에 넣을 경우 V2 스키마 위반으로 무시되는 결함을 리뷰어 실측 검증을 통해 발견 및 시정).
- **기존 사용자 설정 보호**: 기존 `opencode.jsonc`가 있으면 `.bak`로 백업하고, 사용자 정의 키를 보존하며 멱등(idempotent)하게 병합.

## 3. 검증 결과
- **신규 테스트 스위트**: 
  - `tests/test_permissions_merge.sh` (69 asserts): 프로파일 25종 로드, 번들 확장, last-match-wins 우선순위, L3 전역 차단, `git push=ask` 검증 통과.
  - `tests/test_permissions_seed.sh` (56 asserts): 실제 `opencode debug agents` 연동, config 백업 및 사용자 규칙 보존 검증 통과.
- **효과**: `worker`의 일상 TDD 루프에서 수동 승인 팝업이 0건으로 제거되면서도, 위험한 파괴 명령(`rm -rf`, `sudo`)과 원격 변경(`git push`)은 완벽히 방어됨.
