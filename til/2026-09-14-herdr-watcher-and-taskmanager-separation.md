# TIL: Watchdog과 Orchestrator의 분업 및 Watcher 내재화 (2026-09-14)

## 1. 분산 에이전트 시스템에서 Watchdog과 Orchestrator의 관심사 분리 (Separation of Concerns)

멀티 에이전트 환경에서 "에이전트 상태를 감시하고 막힘을 해소하는 일"과 "업무를 조율하고 릴레이하는 일"을 동일한 LLM 에이전트에게 맡기면 두 가지 심각한 비효율이 발생한다:
1. **토큰 및 컴퓨팅 낭비**: LLM이 5초마다 상태를 조회(`herdr agent list`)하며 "아직 일하는 중인가?"를 확인하는 폴링 루프를 돌게 됨.
2. **컨텍스트 오염**: 기계적인 터미널 팝업 승인(키 입력)과 실제 소프트웨어 엔지니어링 산출물(기획서, 코드, 테스트 결과) 해석이 뒤섞여 오케스트레이션 집중도가 저하됨.

### 워치독(Watcher / `htw`)과 오케스트레이터(Task Manager)의 분업 모델

| 구분 | **Watcher (`bin/herdr-watcher` / `htw`)** | **Task Manager (`hts-taskmanager`)** |
| :--- | :--- | :--- |
| **패턴** | **기계적 워치독 (Context-free Watchdog)** | **지능형 오케스트레이터 (Context-aware Orchestrator)** |
| **실행 주체** | 경량 백그라운드 Python 데몬 프로세스 | LLM 기반 AI 에이전트 |
| **핵심 업무** | • 5초 주기 상태 전이 모니터링<br>• OpenCode 터미널 실행 권한(`Permission required`) 감지 시 `tab+enter` 키 전송으로 자동 승인 | • 요구사항 분석 및 기획/구현/리뷰 파이프라인 제어<br>• Reviewer 반려 시 Worker로 재작업 반송 중재<br>• PM에게 최종 진행 상황 요약 보고 |
| **동기화 기법** | 능동적 폴링 (Polling Loop) | **블로킹 완료 대기 (`--wait`)** |

* Task Manager는 상태 감시를 전적으로 Watcher에게 일임하고, 작업 지시 시 `--wait` 플래그를 통해 완료 시점만 수동적으로 기다렸다가 산출물 중계에만 전념함으로써 토큰 소모를 0으로 줄이고 파이프라인의 견고함을 극대화한다.

---

## 2. 독립 패키징 및 CLI 인스톨러 설계 패턴

* **외부 종속성 제거 (Self-contained)**:
  * 로컬 환경(`~/.gemini/config/skills/...`)에만 머물러 있던 Watcher 스크립트를 레포지토리의 `bin/herdr-watcher`로 내재화.
* **사용자 친화적 단축 명령어 (`ht` & `htw`)**:
  * `install.sh`가 `~/bin/herdr-watcher`와 `~/bin/htw` 심볼릭 링크를 자동 등록.
  * 개발자는 `ht`로 팀 세션을 띄우고, `htw &` 한 줄로 백그라운드 워치독을 가동할 수 있어 사용자 경험이 획기적으로 개선됨.
* **TDD 리그레션 방지**:
  * `tests/test_install.sh`에 링크 생성, zip 패키지 포함 여부, `--help` 및 1회 실행 정상성 검증 케이스를 추가하여 CI/설치 안정성 확보.
