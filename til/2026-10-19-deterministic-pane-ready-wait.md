# TIL: 2026-10-19 herdr agent_pane_busy 쉘 레이스 제거와 결정론적 wait_pane_ready 설계

## 1. 배경 및 문제 상황
- `herdr-team`에서 5인 이상의 대규모 프리셋(`pkm`, `dev` 등) 기동 시 `agent_pane_busy: agent target pane is not an available shell` 에러가 간헐적으로 발생.
- `pane split` 직후 쉘이 완전한 대화형(interactive) 프롬프트 렌더링 상태에 도달하기 전에 `agent start`가 즉시 호출되어 발생한 프로세스 레이스 컨디션(Race Condition).
- 단순 `sleep 0.5` 임의 대기는 타이밍 기반의 취약한 땜질(Non-deterministic)이며, 시스템 부하 시 재발하므로 기각됨.

## 2. 해결 방안: 이벤트 기반 결정론적 대기 (`wait_pane_ready`)
임의의 시간 대기(`sleep`) 대신 herdr의 내장 상태 및 이벤트 프리미티브를 결합한 2단계 게이트를 구축:

1. **Foreground 프로세스 상태 게이트 (`pane_shell_foreground`)**:
   - `herdr pane process-info --pane <ID>`를 확인하여 현재 Pane의 포그라운드 프로세스 그룹이 쉘 자체인지 검증.
   - 다른 명령어나 프로세스가 실행 중인 busy 상태를 원천 필터링.
2. **프로브 마커 + 출력 이벤트 대기 (`pane wait-output`)**:
   - `herdr pane run "$pane" printf ...`로 고유 마커를 주입하고,
   - `herdr pane wait-output "$pane" --regex "^__HT_READY_MARKER__" --timeout 1500`으로 쉘이 실제로 명령을 수신하여 실행을 마쳤음을 이벤트로 확증.
3. **폐쇄성 (Bounded Closure)**:
   - 최대 타임아웃(`HERDR_TEAM_READY_TIMEOUT_S`, 기본 20s)을 적용하여 무한 대기를 차단하고 실패 시 대상 Pane ID를 명확히 출력.
4. **에러 가시성 확보**:
   - 기존 `run()` 헬퍼의 무음 소실(`>/dev/null`)을 개선하여 실패 시 stderr 메시지를 정상 노출.

## 3. 검증 결과
- **테스트 스위트**: `tests/test_pane_ready.sh` (20 asserts) 전용 테스트 작성 및 통과.
- **전체 회귀 테스트**: 10종 테스트 스위트 777 PASS / 0 FAIL (100% 무결점).
- **실측 성능**: `pane split` 직후 평균 23ms 내에 쉘 ready 상태를 확증하고 즉시 `agent start`로 전환되어 불필요한 고정 지연 0초 달성.
