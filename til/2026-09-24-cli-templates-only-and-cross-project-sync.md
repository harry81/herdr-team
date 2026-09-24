# TIL: herdr-team --templates-only 옵션을 통한 타 프로젝트 템플릿 동기화 및 생명주기 분리

- **날짜**: 2026-09-24
- **작성자**: PM / Orchestration Team
- **범위**: `bin/herdr-team` (CLI 인자 파싱 및 실행 제어), `tests/test_templates_only.sh`

---

## 1. 배경 및 문제 의식

`herdr-team`(`ht`)은 프로젝트 초기 설정 시 프리셋 기반의 템플릿 파일 생성(`setup_templates`, `setup_opencode_agents`)과 Pane 분할 및 에이전트 시작(`setup_panes`)을 하나의 명령으로 수행한다.

그러나 프로젝트를 진행하면서 중앙 템플릿(예: `templates/opencode-agents/ROLE-*.md`의 권한 블록, 프롬프트 지침, 또는 프리셋 문서)을 수정한 뒤, **이미 팀 구성과 Pane 레이아웃이 갖춰진 다른 프로젝트에 수정된 템플릿 파일만 적용**해야 하는 요구사항이 발생했다.

기존 옵션의 한계:
- `--no-template`: 템플릿 생성을 건너뛰고 Pane 분할만 수행
- `--no-start`: Pane 분할과 레이블 지정까지만 수행하고 에이전트 시작을 건너뜀
- ❌ **Pane 분할을 건너뛰고 템플릿 파일만 치환·설치하는 옵션 부재**: 기존 프로젝트에서 `ht`를 재실행하면 불필요하게 Pane이 다시 분할되거나 `agent_pane_busy` 오류가 발생할 수 있었다.

---

## 2. 해결 방안: `--templates-only` 플래그 신설

`bin/herdr-team`의 라이프사이클을 템플릿 동기화 단계와 Pane 오케스트레이션 단계로 명확히 분리했다.

```
[ CLI 실행 ]
     │
     ├─ 1) prefix 결정 & 인자 파싱
     ├─ 2) setup_templates (AGENTS.md, agents/<preset>/ 치환 복사)
     ├─ 3) setup_opencode_agents (.opencode/agents/ 생성)
     │
     ├─ [ TEMPLATES_ONLY == 1 ] ──► 로그 출력 후 즉시 종료 (exit 0) ✅
     │
     └─ 4) setup_panes (Pane 분할, 레이블, herdr agent start)
```

### 핵심 구현
1. **플래그 파싱**: `--templates-only` 인자를 수신하여 `TEMPLATES_ONLY=1` 설정.
2. **조기 종료 게이트**: `setup_opencode_agents` 완료 직후 `TEMPLATES_ONLY=1`이면 로그 출력 후 `exit 0`으로 정상 종료.
3. **호환성 보장**:
   - `--force`와 결합 시: 기존 파일을 덮어쓰고 최신 템플릿으로 완전 재시딩.
   - `--dry-run`과 결합 시: 파일 쓰기 없이 생성 계획만 출력.
   - `--preset <name>`과 결합 시: 지정한 프리셋 템플릿을 타깃 디렉토리에 동기화.

---

## 3. 검증 (TDD)

`tests/test_templates_only.sh`를 신설하여 22개 시나리오를 엄격히 검증:
- `--help`에 `--templates-only` 설명 노출 확인
- 격리된 테스트 CWD에서 단독 실행 시 `agents/` 및 `.opencode/agents/` 파일 정상 생성 확인
- stub `herdr`를 주입하여 Pane 분할(`pane split`) 명령이 일절 호출되지 않음을 확인
- `--force`, `--dry-run`, 프리셋 전환과의 연계 동작 검증
- 기존 6개 테스트 스위트(총 607개 테스트 케이스) 전수 PASS

---

## 4. 실무 활용 패턴

중앙 템플릿이 업데이트되었을 때 다른 프로젝트에서 안전하게 동기화하는 표준 절차:

```bash
# 1. 대상 프로젝트 루트로 이동
cd /path/to/target-project

# 2. 변경 계획 미리보기 (dry-run)
ht --templates-only --dry-run

# 3. 최신 템플릿 강제 덮어쓰기 적용
ht --templates-only --force
```
