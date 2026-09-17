# 2026-09-17 TIL: Multi-Agent 파이프라인 명명 리팩토링 (Task Manager → Orchestrator)

## 1. 배경 및 문제 의식
- Herdr 기반 팀 오케스트레이션에서 `taskmanager` 에이전트는 기획(`planner`), 구현/조사(`worker`/`researcher`), 검증(`reviewer`) 간의 순차 파이프라인을 중계하고 제어하는 역할을 전담함.
- 그러나 `taskmanager`라는 명칭은 Jira나 Asana의 티켓/일감 등록 관리자나, 하위 태스크를 직접 수행하는 작업자로 오해될 여지가 컸음.
- 실제로 이 에이전트는 **직접 코드 수정을 하지 않고(edit: deny, task: deny)**, 전체 멀티 에이전트 간의 릴레이 실행 흐름을 지휘하고 조율하는 역할을 수행하므로 `orchestrator`라는 명칭이 본질과 훨씬 부합함.

## 2. 변경 내용
1. **역할명 및 템플릿 변경**:
   - `templates/opencode-agents/ROLE-taskmanager.md` → `templates/opencode-agents/ROLE-orchestrator.md`
   - 프롬프트 및 시스템 설명문 내 `taskmanager` 표기를 `orchestrator`로 통일.
2. **프리셋 정의 갱신**:
   - `templates/dev/preset.conf`: `ROLES="orchestrator planner worker reviewer"`
   - `templates/app/preset.conf`: `ROLES="orchestrator planner worker reviewer"`
   - `templates/biz/preset.conf`: `ROLES="orchestrator planner researcher reviewer"`
   - 각 프리셋의 `AGENTS.md` 내 가드레일 및 다이어그램 텍스트 동기화.
3. **런타임 및 하위 호환성 보장**:
   - `bin/herdr-team`: 2col 분할, 변수명(`P_ORCHESTRATOR`), 역할 생성 조건문에서 `orchestrator|taskmanager`를 모두 처리하도록 지원하여 레거시 템플릿과의 하위 호환성 유지.
4. **테스트 검증 (TDD)**:
   - `tests/test_preset.sh` 내 역할 정의, dry-run 출력, agent 생성 검증을 `orchestrator` 기준으로 업데이트하고 123개 전체 테스트 PASS 확인.

## 3. 배운 점
- 멀티 에이전트 아키텍처에서 에이전트의 명칭(Naming)은 사용자와 상위 PM뿐만 아니라 LLM 스스로에게도 자신의 역할 경계(Boundary)를 인식시키는 핵심 신호(Signal)로 작동함.
- Manager(관리)에서 Orchestrator(지휘/조율)로의 명확한 용어 변경은 "직접 하지 않고 위임·중계한다"는 가드레일을 직관적으로 강화함.
