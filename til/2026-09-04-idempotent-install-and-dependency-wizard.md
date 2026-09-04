# TIL: 멱등 설치·의존성 위저드·릴리스 패키징 (2026-09-04)

`herdr-team-setup` 쉬운 설치/실행 고도화(`hts` 단축어, PATH 자동 등록,
Windows 의존성 위저드, 배포 zip) 작업에서 정리한 패턴.

## 1. 마커 주석 기반 PATH 등록 멱등성

- 셸 설정 파일(`.bashrc`/`.zshrc`)에 PATH를 추가할 때는 기능 코드보다
  **마커 주석을 먼저 검사**한다: `# herdr-team-setup: ...` 한 줄이 곧
  설치 상태의 source of truth다.
- `grep -qF "$MARKER" "$rc"`가 참이면 스킵, 거짓이면 heredoc 한 블록을 append.
  export 라인 자체에는 마커 문자열을 넣지 않아 `grep -c` 카운트가 항상 1로
  수렴하게 만든다 — 테스트가 "정확히 1회"를 단언할 수 있는 구조다.
- rc 파일이 없으면 빈 파일부터 생성(`touch`)한 뒤 진행: `.zshrc`가 없는
  bash 전용 환경에서도 실패하지 않는다.
- 교훈: 멱등성은 "실행 전 상태 확인 → 조건부 변경" 순서로 설계하고,
  검증은 **설치 스크립트를 2회 이상 실행**한 뒤 불변량을 단언하는 형태가 가장 확실하다.

## 2. `curl | bash` 파이프 실행의 저장소 배치 문제

- 파이프 실행 시 `$0`은 `bash`가 되고 `BASH_SOURCE[0]`은 비어 있어
  `dirname $0` 기반 경로 감지가 깨진다. 따라서 감지 우선순위를
  **명시 env(`HERDR_TEAM_REPO`) > 스크립트 위치 > 자동 클론** 순으로 둔다.
- env 경로도 blind trust하지 않고 `bin/herdr-team-setup` 존재 여부로 검증한다.
- 자동 클론(`HERDR_TEAM_REPO_URL` + `git clone --depth 1`)은 마지막 폴백으로만
  두고, 셋 다 실패하면 복구 가이드(3가지 선택지)를 stderr로 출력 후 exit 1.
- 테스트는 `cat install.sh | HERDR_TEAM_REPO=$REPO bash`로 파이프 환경을
  재현한다 — stdin 주입만으로 실제 원라이너와 동일한 코드 경로를 탄다.

## 3. 비개발자 친화적 Windows 의존성 위저드

- Git/WSL이 둘 다 없으면 **강제 자동설치를 하지 않는다**: winget/UAC 상승은
  비개발자 PC에서 프리징·권한 팝업의 원인이 되므로, 관리자 PowerShell용
  복사-붙여넣기 명령(`winget install --id Git.Git`, `wsl --install`)과
  재시작 후 재실행 안내를 영어·한국어 병기로 제시하고 멈춘다.
- 자동화·고급 사용자용 탈출구는 환경변수 바이패스
  (`HERDR_TEAM_SKIP_CHECK=1`) 하나로 통일한다. 플래그가 있으면 경고를 남기고
  `BACKEND=wsl`로 진행 — "검사 생략"이지 "설치 생략"이 아님을 메시지에 명시한다.
- 배치 `if/else` 중첩은 ` HERDR_TEAM_SKIP_CHECK` 분기를 최외곽에 두어
  기존 WSL→Git-Bash 탐지 로직을 그대로 안쪽에 보존한다(최소 변경).

## 4. `zip` 부재 환경을 고려한 Python3 폴백

- 배포 스크립트는 `command -v zip`이 있으면 `zip -qr ... -x '.git/*' 'tests/*'`,
  없으면 `python3 - zipfile` heredoc으로 동일 결과물을 만든다.
  최소 Ubuntu/Windows-Python 환경에서도 빌드가 깨지지 않는다.
- 폴백 구현 시 `os.walk`의 `dirs[:] = [...]` 제자리 필터로 `.git`/`tests`
  서브트리를 진입 전에 가지치기한다 — 파일 단위 제외보다 빠르고,
  `rel.startswith(skip)` prefix 검사가 핵심이다.
- `--out`은 절대/상대 경로를 모두 받아 `mkdir -p $(dirname)` 후 생성하고,
  기존 산출물은 `rm -f`로 정리해 반복 빌드를 멱등하게 만든다.
- 일반 사용자용 패키지에는 `.git`(용량·이력)과 `tests/`(개발용)를 제외하고
  `bin/`, `windows/`, `templates/`, 문서, `LICENSE`, 루트 런처만 담는다.
