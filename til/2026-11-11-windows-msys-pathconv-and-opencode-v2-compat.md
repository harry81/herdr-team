# 2026-11-11 Today I Learned: Windows Git-Bash(MSYS2) 경로 변환 방어 및 OpenCode v2 API 호환성

## 1. 배경 및 문제 상황

Windows 환경에서 `windows/start-team.bat` 런처를 실행했을 때 두 가지 치명적인 문제가 발생했다:

1. **OpenCode V1 vs V2 스키마 불일치**:
   - `herdr-team`이 `.opencode/opencode.jsonc`에 V2 스키마(`"permissions": [...]`, `"policies": [...]`)를 작성했을 때, Windows에 설치된 `opencode` v1.x에서 `V2 permissions are not supported by OpenCode V1. Use V1 "permission" rules or run opencode2` 구문 오류를 던지며 종료됨.
   - 또한 `opencode_supports_api` 판별식에서 `grep -q 'opencode api'`로 `opencode --help` 텍스트를 검사했으나, help 출력은 `"api"`로만 나와 v2가 설치되어 있어도 미지원으로 오판하여 `--agent` 플래그로 폴백하다 프로세스가 즉시 종료됨.
2. **Git-Bash(MSYS2) 경로 변환(Path Mangling)에 의한 API 라우팅 실패**:
   - OpenCode v2 환경에서 `opencode api post /api/session -d "$payload"`를 호출할 때, MSYS2 런타임이 선행 슬래시(`/`)로 시작하는 인자를 Windows 로컬 경로(`C:/Program Files/Git/api/session`)로 자동 변환함.
   - OpenCode v2 CLI의 내부 파서는 `[method, path]` 인자 파싱 시 `path.startsWith("/")`를 엄격히 검사하므로, `C:/...`로 변환된 인자를 보고 `Error: Expected an operation name or an HTTP method and path` 예외를 던지며 세션 생성이 실패함.

## 2. 해결 원리 및 핵심 메커니즘

### ① API 판별 기준: 문자열 매칭에서 실행 종료코드(rc) 기반으로 전환
- CLI help 메시지의 포맷이나 로케일에 취약한 문자열 grep 대신, 실제 서브커맨드 존재 여부를 확인하는 프로브 방식 채택:
  ```bash
  opencode api --help >/dev/null 2>&1 && OPENCODE_API_SUPPORTED=1 || OPENCODE_API_SUPPORTED=0
  ```

### ② 대화형 TUI의 `--agent` 플래그 제거 및 세션 사전 생성 단일화
- `opencode` 대화형 TUI 실행 시 `--agent`는 지원되지 않는 비대화형(`opencode run`) 전용 플래그이므로 전달을 완전 제거하고, `opencode api post /api/session`을 통해 사전 발급된 세션 ID(`-- --session <sid>`)만 바인딩함.

### ③ MSYS2 인자 자동 변환 방어: `MSYS2_ARG_CONV_EXCL` 국소 스코핑
- Git-Bash(MSYS2)는 Windows 네이티브 실행 파일 호출 시 POSIX 스타일 경로를 Win32 경로로 자동 변환한다.
- `MSYS_NO_PATHCONV=1`을 전역 선언하면 전체 스크립트에서 Windows 경로 변환이 필요한 다른 명령(`cygpath` 등)에 부작용을 일으킬 수 있다.
- MSYS2 공식 사양에 따라 **해당 API 호출에만 접두사 제외 규칙**을 환경변수로 인라인 주입:
  ```bash
  MSYS2_ARG_CONV_EXCL='/api' run_capture opencode api post /api/session -d "$payload"
  ```
  - `/api`로 시작하는 인자만 경로 변환 대상에서 제외되고 리터럴 `/api/session` 문자열 그대로 OpenCode로 전달된다.
  - Linux/macOS 등 비MSYS 환경에서는 단순한 환경변수 설정이므로 아무런 부작용 없이 투명하게 동작한다.

## 3. 검증 및 결과

- `tests/test_agent_session.sh`: MSYS 경로 변환 방어(`msys_conv`, `msys_scope`, `msys_value`) 단언을 포함한 67개 테스트 전체 통과 (PASS=67, FAIL=0).
- `tests/test_windows_launcher.sh`: 111개 테스트 전체 통과 (PASS=111, FAIL=0).
- Windows 환경에서 Git-Bash를 통한 원클릭 팀 셋업 시 세션 생성 실패 없이 정상적으로 팀 에이전트들이 interactive 프롬프트로 준비 완료됨.
