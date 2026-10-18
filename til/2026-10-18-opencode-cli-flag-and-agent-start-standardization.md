# TIL: OpenCode CLI 플래그 변화와 herdr agent start 표준화 (2026-10-18)

## 1. 배경 및 문제 상황
- `herdr-team`에서 팀원 에이전트를 시작할 때 `opencode` 엔진의 경우 `-- --agent <agent>` 플래그를 전달하도록 구성되어 있었다:
  ```bash
  herdr agent start <agent> --kind opencode --pane <pane> -- --agent <agent>
  ```
- 이는 과거 opencode 버전에서 primary agent를 CLI 플래그로 지정하려던 시도였으나, 최신 OpenCode(`v2.0.32` 기준) 실행 시 다음과 같은 오류가 발생하며 에이전트 구동이 실패함:
  ```
  ERROR: Unrecognized flag: --agent in command opencode
  ```
- OpenCode v2.x CLI 구조상 `--agent` 옵션은 루트 대화형 TUI 커맨드(`opencode`)에서는 지원되지 않고, `mini` 또는 `run` 서브커맨드 전용 옵션임.

## 2. 해결 및 설계 결정
1. **`herdr agent start` 호출의 엔진 공통 표준화**:
   - `bin/herdr-team`에서 `opencode` 전용으로 붙이던 `-- --agent <agent>` 전달 로직을 제거.
   - 모든 에이전트 종류에 대해 일관되게 `herdr agent start <name> --kind <kind> --pane <pane>` 형식으로 단일화.
2. **역할 강제와 에이전트 정의 연동**:
   - OpenCode는 작업 디렉토리의 `.opencode/agents/<prefix>-<role>.md` 파일 정의를 프로젝트 레벨에서 인식하므로, CLI의 임의 플래그에 의존하지 않고 herdr pane 라벨 및 프로젝트 에이전트 설정을 통해 역할을 안정적으로 강제함.
3. **문서 및 테스트 동기화**:
   - `tests/test_preset.sh` 17번 항목에서 `-- --agent` 미사용(깨끗한 표준 호출) 검증으로 수정.
   - `AGENTS.md`, `README.md`, `README.ko.md`, 및 프리셋 템플릿 문서(`templates/AGENTS.md`, `templates/*/AGENTS.md`)의 예시 명령어 일괄 갱신.
