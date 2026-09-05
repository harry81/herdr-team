# TIL: 에이전트 종류(Kind) 대화형 TUI 선택 및 다중 백엔드 지원 (2026-09-05)

팀 초기화 시 기본값(`opencode`)에 고정되어 있던 에이전트 종류(`--kind`)를 사용자가 환경에 맞게 유연하게 설정할 수 있도록, 대화형 TUI 2단계 선택과 환경변수(`HERDR_TEAM_KIND`), CLI 옵션 체계를 고도화하면서 정리한 패턴.

## 1. 2단계 순차 TUI 인터랙션 설계

- **흐름**: 1단계 프리셋 선택(`dev`/`app`/`biz`) → 2단계 에이전트 종류 선택(`opencode`/`claude`/`codex`/`agy` 등).
- **입출력 분리**: 메뉴 출력은 `stderr`(`>&2`), 결과값 반환은 `stdout`으로 격리하여 쉘 변수 치환(`KIND="$(choose_kind_tui)"`) 및 비TTY 파이프라인에서 깨끗하게 합성 가능.
- **행(Hang) 방지 및 안전망**:
  - `read -t 10` 타임아웃 적용 (10초 무입력 시 기본값 `opencode` 자동 폴백).
  - EOF / 파이프 입력 / non-TTY 환경에서도 멈춤 없이 기본값으로 즉시 진행.
  - `--no-interactive` 지정 시 두 메뉴 모두 건너뛰고 기본값(`dev`, `opencode`)으로 즉시 진행.
- **우선순위 계층**:
  - `명시적 --kind` > `환경변수 HERDR_TEAM_KIND` > `대화형 TUI 메뉴` > `기본값 (opencode)`.

## 2. Herdr 지원 에이전트 종류 검증

- `herdr agent start`가 지원하는 공식 agent kind(`opencode`, `claude`, `codex`, `agy`, `pi`, `gemini`, `cursor`, `devin` 등) 목록을 화이트리스트 검증 함수 `is_known_kind`로 체크.
- 잘못된 kind가 들어올 경우 명확한 에러 메시지와 함께 exit code 2로 즉시 중단.

## 3. Windows 원클릭 런처 (`start-team.bat`) 연계

- Windows 배치 스크립트에서도 동일한 2단계 `choice /t 10 /d 1` 인터랙션을 구성하여 GUI/더블클릭 사용자도 원하는 에이전트 백엔드(`opencode`, `claude`, `codex`, `agy`)를 원클릭으로 선택할 수 있도록 구현.
- `%KIND_ARG%`를 WSL/Git-Bash 실행 명령줄에 안전하게 전달.
