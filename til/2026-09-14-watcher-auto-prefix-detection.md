# Herdr Watcher PWD 기반 접두사(Prefix) 자동 감지 (Auto-Detect)

## 1. 배경 및 동기
- `herdr-team`(`ht` / `hts`)은 타깃 프로젝트 디렉토리에서 인자 없이 실행할 때, 현재 Git 레포지토리 또는 폴더 이름을 분석하여 2~4글자의 프로젝트 접두사(예: `herdr-team` -> `ht`, `my-project` -> `mp`)를 자동 계산한다.
- `herdr-watcher`(`htw`)는 백그라운드에서 실행되며 에이전트들의 상태를 감시하고 멈춤(`blocked`)이나 셸 권한 승인(`Permission required`)을 자동 해결하는 보조 도구이다.
- 이전에는 `htw` 실행 시 `--prefix <prefix>-`를 사용자가 직접 명시하지 않으면 동작하지 않거나 전체를 감시해야 했다.
- 사용자가 동일한 프로젝트 디렉토리에서 `ht`와 `htw`를 실행할 때, `htw`도 `ht`와 완전히 동일한 규칙으로 prefix를 계산하여 별도 인자 없이 즉시 해당 프로젝트 팀을 타깃 감시할 수 있어야 한다.

---

## 2. 핵심 설계 원칙

1. **단일 진실 원천(Single Truth)과 일관된 알고리즘**:
   - `bin/herdr-team`의 bash 기반 `auto_prefix` 함수와 `bin/herdr-watcher`의 python 기반 `auto_prefix` 함수가 동일한 디렉토리에 대해 항상 동일한 결과를 반환하도록 동일한 정규식 규칙 및 경계 분리 알고리즘을 적용한다.
   - 알고리즘:
     1. `git -C <cwd> rev-parse --show-toplevel`로 git 루트 확인 (실패 시 cwd 폴더명 fallback).
     2. 공백 제거 영숫자 길이가 4글자 이하이면 그대로 반환.
     3. camelCase, 숫자-문자 경계, `-_ .` 구분자를 기준으로 단어를 토큰화.
     4. 각 단어의 첫 글자(initial)를 추출하여 2~4글자 축약어 생성.
     5. 축약어가 2글자 미만이면 전체 소문자 중 앞 2글자 반환.

2. **CLI 인터페이스 우선순위**:
   - `--all`: prefix 필터링 없이 전체 에이전트 감시 (`prefix = None`).
   - `--prefix <value>`: 사용자가 명시한 접두사 최우선 적용.
   - 기본값: 현재 디렉토리(`cwd`) 기준 `auto_prefix()`를 호출하여 `<detected>-` 접두사 자동 적용.

3. **TDD 기반 검증**:
   - `tests/test_install.sh`에 `auto_prefix` 파이썬 로직 단위 테스트 및 CLI 플래그 조합 검증 케이스 추가.
   - 단독 실행 시 현재 레포(`herdr-team` -> `ht-`)를 자동 추출함을 테스트로 보장.

---

## 3. 효과
- 사용자 경험 일관성: 같은 폴더에서 `ht` 실행 후 `htw &`만 입력하면 추가 옵션 없이 바로 해당 팀 전담 감시 시작.
- 다중 프로젝트 세션 격리: 타 프로젝트의 에이전트와 혼선 없이 현재 프로젝트의 에이전트 멈춤 및 권한 승인만 정확히 처리.
