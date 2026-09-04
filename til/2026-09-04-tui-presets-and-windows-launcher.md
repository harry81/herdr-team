# TIL: CLI TUI + Windows 런처 + 프리셋 아키텍처 (2026-09-04)

`herdr-team-setup`에 인터랙티브 TUI 프리셋 선택, Windows 원클릭 런처,
MIT 라이선스/영어 기본화를 적용하며 정리한 패턴.

## 1. CLI TUI 인터랙션 설계 원칙

- **stderr 렌더링 + stdout 값 반환**: 메뉴는 `>&2`로 그려서 파이프/캡처를
  오염시키지 않고, 선택 결과(`dev`/`app`/`biz`)만 stdout으로 반환해
  `PRESET="$(choose_preset_tui)"` 형태의 명령 치환으로 받는다.
  입출력 채널 분리가 TUI를 합성 가능하게 만드는 핵심이다.
- **행(hang) 방지 3중 안전망**: (a) `read -t 10` 타임아웃, (b) EOF/파이프 입력이면
  즉시 기본값(`dev`) 폴백, (c) `--no-interactive` 플래그로 메뉴 진입 자체를 생략.
  CI·파이프·리다이렉션 어떤 경우에도 블로킹하지 않는다.
- **명시적 env 오버라이드 우선순위**: `--preset` > `HERDR_TEAM_PRESET` > TUI 메뉴 >
  기본값. 자동화는 env/플래그로, 사람은 메뉴로 — 같은 코드 경로를 공유한다.
- **테스트 가능성**: TUI 분기는 `printf '2\n' | script` 파이프로 시뮬레이션하고
  `choice` 대신 stdin 한 줄 읽기로 매핑(1/dev, 2/app, 3/biz)하므로
  Linux CI에서도 메뉴 로직을 그대로 검증할 수 있다.

## 2. Windows 배치(.bat) 크로스 플랫폼 브릿지 패턴

- **백엔드 자동 탐색**: `where wsl` 성공 시 WSL 우선, 실패 시
  `"%ProgramFiles%\Git\bin\bash.exe"` 존재 여부로 Git-Bash 폴백.
  둘 다 없으면 한글/영문 병기 에러 + `pause` 후 `exit /b 1`.
- **경로 공백 대응**: 모든 경로는 `"%VAR%"` 인용 + `set "VAR=..."` 안전 대입.
  Windows→WSL 변환은 수동 드라이브 매핑 대신 `wsl wslpath -u "%REPO%"`에 위임
  (대소문자·특수문자 edge case 제거). Git-Bash에는 `C:/...` 슬래시 변환만 전달.
- **CRLF + `chcp 65001`**: `.bat`은 CRLF 저장(혼합 개행 금지, 커밋 전 정규화),
  선두에 `chcp 65001 >nul`로 UTF-8 코드페이지를 고정해야 한글 병기가 깨지지 않는다.
- **시뮬레이션 훅**: `HERDR_TEAM_DRYRUN=1`이면 최종 실행 명령을 `echo`만 하고,
  `HERDR_TEAM_NOPAUSE=1`이면 마지막 `pause`를 생략 — Linux 테스트에서 전달 명령의
  유효성을 실실행(`--dry-run`)으로 검증하는 통로가 된다.
- **파일명은 100% ASCII**: 한글 파일명은 도구·인코딩별로 취급이 달라
  공개 OSS에서는 영문 파일명 + 내용 병기로 통일한다.

## 3. 에이전트 오케스트레이션 프리셋 아키텍처

- **도메인별 역할 분리**: `dev`(planner/worker/reviewer, TDD 개발),
  `app`(동일 3역할, 배포·E2E 강조), `biz`(planner/researcher/reviewer, 조사 중심,
  worker 없음). 같은 3-slot 레이아웃을 공유하면서 역할 구성만 바꾼다.
- **일반화**: 스크립트는 역할을 하드코딩하지 않고 `templates/<preset>/preset.conf`의
  `ROLES`에서 `<prefix>-<role>` 에이전트명을 도출한다. 분할 체이닝(첫 역할 right,
  이후 down)·리네임·시작·템플릿 복사가 모두 `ROLES` 루프 기반이라 새 프리셋 추가는
  디렉토리(`preset.conf` + `AGENTS.md`) 추가만으로 끝나고, 새 역할이면
  `ROLE-<role>.md` 하나만 보태면 된다.
- **기존 호환 별칭 유지**: `PLANNER/WORKER/REVIEWER` 변수는 그대로 두어
  기존 호출·문서와의 호환을 깨지 않으면서 내부는 일반화 경로로 동작하게 한다.
