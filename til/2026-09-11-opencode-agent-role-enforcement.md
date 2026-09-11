# TIL: opencode `--agent`로 역할을 강제하기 (2026-09-11)

역할 문서(role doc)만 복사하던 기존 모델의 한계와, opencode primary agent + `--agent`로 역할·권한을 강제하는 방식으로 herdr-team을 확장하며 정리한 내용.

## 1. 문제: herdr는 역할(role)을 부여하지 않는다

- `herdr agent start <name> --kind opencode`는 **표시 이름만** 붙인다. 역할 시스템 프롬프트나 위임 규율을 주입하지 않는다.
- herdr 통합 플러그인(`herdr-agent-state.js`)은 `idle/working/blocked` **상태 보고만** 한다.
- 즉 pane agent는 기본 opencode `build` agent로 뜨고, 역할은 "PM이 첫 prompt로 `agents/<role>.md`를 읽어라"라고 **권고**하는 데 그친다 → pane agent가 위임 없이 직접 처리하는 원인.
- `herdr agent explain`의 `manifest: none`은 herdr가 역할 매니페스트를 갖지 않음을 확인해 준다(그 manifest는 agent 감지용이지 역할용이 아님).

## 2. 해결: agent 정의 = 강제, role 문서 = 상세 정본

- opencode는 `--agent <name>`으로 primary agent를 선택할 수 있다.
- agent md frontmatter의 `mode: primary` + `permission`이 **실제 강제 장치**:
  - `taskmanager`: `edit: deny`, `task: deny`, `bash`는 `herdr *` 허용 → 직접 구현/우회 불가.
  - `worker`: `task: deny` → 재위임(무한 분화) 방지.
  - `planner`/`reviewer`/`researcher`: `edit: deny` → 읽기 전용.
- 프롬프트만으로는 LLM이 무시할 수 있으므로 **권한이 핵심**. role 문서는 상세 프로토콜 정본으로 두고 agent md가 그 문서를 가리키게 해 중복/drift를 줄인다.

## 3. herdr-team에 적용한 변경

- **신규** `templates/opencode-agents/ROLE-*.md` (5역할, `{{PREFIX}}` 치환, `mode: primary` + permission).
- **`bin/herdr-team`**:
  - `setup_opencode_agents()` 신설 → 대상 프로젝트 `.opencode/agents/<prefix>-<role>.md` 설치(파일별 멱등, `--force`/`--dry-run` 지원).
  - opencode일 때 `herdr agent start ... --pane <id> -- --agent <prefix>-<role>` (codex/gemini 등은 `--agent` 미지원 → 게이팅).
- **AGENTS.md/README**: "역할 주입" → "역할 강제"로 갱신, `.opencode/agents/` 위치와 `--agent` 사용법 명시.

## 4. 얻은 교훈

- **전역 vs 프로젝트 로컬**: 임의 프로젝트를 셋업하는 배포 도구는 전역(`~/.config/opencode/agents/`)이 아니라 대상 프로젝트 `.opencode/agents/`에 설치해야 오염/prefix 충돌이 없다. opencode는 pane cwd 기준으로 프로젝트 agent를 로드한다.
- **멱등 가드의 함정**: `setup_templates`는 팀 문서가 이미 있으면 조기 반환한다. 새 산출물(`.opencode/agents`)은 별도 함수로 분리해야 **기존 셋업 프로젝트도 업그레이드**된다.
- **CLI별 `--agent` 지원 차이**: `opencode`/`claude`/`agy`는 `--agent` 지원, `codex`는 profile + `--sandbox`, `gemini`는 역할 플래그가 없다. herdr는 `--` 뒤 인자를 전달만 하므로 강제 장치는 CLI별 권한/샌드박스 옵션에 달려 있다.
- **테스트 전략**: herdr가 필요한 경로는 stub `herdr` + 임시 CWD로 실제 파일 생성까지 검증하면 파이프라인 전체를 회귀 테스트할 수 있다(총 186 PASS).
