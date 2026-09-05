# TIL: Task Manager 도입을 통한 4인 체제 파이프라인 오케스트레이션 (2026-09-05)

PM(인간/사용자 소통 및 상위 목표 수립)과 실행 파이프라인 오케스트레이션을 분리하기 위해 `taskmanager` 역할을 신규 도입하고, 4인 체제(Task Manager, Planner, Worker, Reviewer)로 팀 아키텍처를 개편하면서 정리한 패턴.

## 1. PM과 Task Manager의 책임 분리 (Separation of Concerns)

- **문제점**:
  - 기존 3인 체제에서는 PM(`agy`)이 사용자 소통, 기획 방향성 설정뿐 아니라 에이전트 간의 실시간 프롬프트 전달, 상태 모니터링, 반송/승인 중계까지 모두 담당함.
  - 이로 인해 PM 컨텍스트 윈도우가 파이프라인 중간 로그로 과부하되고, 인간과의 고차원 인터랙션에 지연이 발생함.
- **해결책**:
  - **PM (`agy`)**: 사용자 소통, 상위 목표 수립, 최종 요약 보고만 담당.
  - **Task Manager (`<prefix>-taskmanager`, `opencode`)**: 파이프라인 실시간 중계 & 드라이브 전담. 각 에이전트 완료 즉시 다음 에이전트로 연결하여 무방치(Continuous Operation) 보장.
  - Task Manager 역시 코드 수정 금지(쓰기 금지 가드레일). 프롬프트 위임(`herdr agent prompt`), 상태 모니터링(`herdr agent wait/read`), 산출물 중계만 수행.

## 2. 순차 파이프라인 중계 및 반송 루프

```
[ User ]
   │
   ▼
[ PM (agy) ] ── 상위 목표 수립 / 최종 취합 보고
   │
   ▼
[ Task Manager (hts-taskmanager) ] ── 실시간 파이프라인 드라이브
   ├─ 1) 기획 지시 ──► [ Planner ] 명세/Task Breakdown
   │                     │
   │                     ▼ 산출물 수령
   ├─ 2) TDD 지시 ───► [ Worker ] 구현 + 단위 테스트 PASS
   │                     │
   │                     ▼ 변경사항 수령
   └─ 3) 검증 지시 ──► [ Reviewer ]
                           ├─ [APPROVE] ─────────► Task Manager → PM 보고
                           └─ [REQUEST CHANGES] ──► Worker로 즉시 반송 (Task Manager 중재)
```

- **팀 간 직접 프롬프트 금지**: Worker와 Reviewer 간 직접 통신하지 않고 Task Manager가 중재하여 상태 추적성과 일관성을 유지.
- **무방치 원칙**: 작업 완료 시 idle 상태로 방치되지 않고 즉시 다음 단계(Reviewer 또는 다음 Task)로 연결.

## 3. 프리셋 및 스크립트 확장 패턴

- **역할 일반화 확장**:
  - `dev`, `app`, `biz` 프리셋의 `preset.conf` 내 `ROLES`에 `taskmanager`를 첫 번째 슬롯으로 등록.
  - `templates/agents/ROLE-taskmanager.md`를 추가하여 동적 prefix 치환 지원.
  - `bin/herdr-team`에서 `setup_templates`의 템플릿 복사 및 인라인 폴백 생성 로직에 `taskmanager` 대응 추가.
- **레이아웃 확장**:
  - PM pane 기준 우측 분할 후, 첫 슬롯(Task Manager)부터 순차적으로 하단 분할(down)하여 4개 서브 pane 균등 배치.
