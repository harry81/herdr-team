# Spec: agent_pane_busy 근본 원인 분석 및 결정론적 해결책 (5인 분할-시작 배선)

- 작성: ht-planner / 2026-10-19
- 범위: `bin/herdr-team`의 5인 프리셋 분할→agent 시작 배선 모든 프리셋 공통 경로
- 회신 규약: 경로 + 1줄 요약

## 1. 재현 조건과 원인 경로 분석

### 1.1 재현 조건
- `herdr-team ht --preset <5인프리셋>` (예: dev/pkm: orchestrator+4역할, LAYOUT=2col) 실행 시 **간헐적** 발생.
- 특히 기존 프로젝트 재실행(pane 재분할) 또는 세션 화면이 이미 여러 pane으로 과밀한 상태에서 발생 빈도 상승 (TIL 2026-09-24: "`ht` 재실행 시 재분할되며 `agent_pane_busy` 오류 발생 가능" 기록 — 증거).

### 1.2 원인 경로 (증거 기반)
코드 경로: `bin/herdr-team` `run_team()` (L944~1068).
1. 분할 루프(L967~1033): `herdr pane split`을 **백투백 연속 호출** → 새 pane_id 수집만 하고 pane 내부 상태(shell 프로세스 기동/프롬프트 렌더) 검증 없음.
2. rename 루프(L1038~1043) → start 루프(L1049~1063)로 **즉시 직결**.
3. start 루프에서 `herdr agent start <agent> --pane <ID> ...` 호출. herdr `agent start --help` 명세(실행 확인한 사실):
   - "`--pane <ID>`: **Existing pane at an interactive shell prompt**" / "The pane must be at its interactive shell prompt."
   - start는 내부적으로 `--timeout <MS>`(default 30000) 동안 interactive readiness를 기다리지만, **대상 pane이 'available shell'로 판정되지 않으면 그 전에 `agent_pane_busy`로 fail-fast**한다.
4. 결론(근본 원인): `pane split` 직후 새 pane의 shell 프로세스는 기동 중일 수 있고(프롬프트 미렌더), herdr의 agent start는 이때 `agent_pane_busy — agent target pane is not an available shell`를 반환. 분할과 시작이 **인터리빙 없이 두 개의 별도 tight loop**로 배선되어, split~start 사이 간격이 rename 루프 지연에만 의존 → 타이밍 race. 간헐성은 opencode 세션 사전 생성(`opencode_session_for`, L1053)이 역할마다 수백 ms 수준의 **가변 지연**을 끼워넣어 race 윈도우가 매번 다르기 때문.

### 1.3 현재 우회 실태 (사실/추정 구분)
- 사실: 레포 코드(bin/, docs/)에 `sleep 0.5` 존재하지 않음 (grep 확인).
- 추정: sleep 0.5 우회는 외부 운영 프롬프트/에이전트 레벨에서 "다시 시도" 패턴으로 쓰이는 것으로 보임. PM의 추정과 일치하나 레포 내 구현은 미확인 → 열린 질문 Q1.
- 추가 결함 (증거): `run()` 헬퍼(L490)는 `"$@" >/dev/null`로 **exit code만` set -e`로 방어**(`set -euo pipefail`, L19)하지만 실패 시 에러 메시지가 무음 소실되어 어떤 pane에서 실패했는지 파악 불가.

## 2. 후보 해결책 비교

평가 기준: **결정론성**(타이밍이 아닌 상태/이벤트 기반 여부), **폐쇄성**(무한 대기 불가능 여부), **복잡도**, **실패 모드**.

| # | 후보 | 결정론성 | 복잡도 | 실패 모드 | 판정 |
|---|---|---|---|---|---|
| A | sleep 0.5 고정 대기(현 우회) | ❌ 시간 기반 추측 — 0.5s 내 shell 기동 재보장 없음. 시스템 부하 시 무효 | 최저 | 느린 환경에서 실패 재발 / 증상만 억제, 근본 미해결 | 기각 |
| B | sleep 재시도(sleep+retry N회) | △ 재시도는 있으나 트리거가 여전히 시간 | 낮음 | 실패한 pane 식별 불가, 무음 소실(`run()` 결함 중첩); N·간격 파라미터 비결정 | 기각 (A의 확장일 뿐, 타이밍 의존 유지) |
| C | **pane 프로세스/스냅샷 기반 raw 감지**: `herdr pane process-info --pane P`에서 foreground가 shell인지 확인 후 start | ○ 상태 기반 | 중 | process-info 스키마의 "shell 여부" 판별 필드 불명(미검증) → 판별 로직 취약 | 보류 (실행 검증 후 보조용) |
| D | **ready 이벤트 대기**: `herdr pane wait-output --pane P --regex/--match <프롬프트/마커> --timeout <MS>` | ◎ 이벤트 기반(Bounded poll 내장: "selected snapshot을 즉시 검색 후 polling", `--timeout`으로 폐쇄) | 중 | 프롬프트 형식 차주제(다른 쉘/호스트) 패턴 미스매치 | 채택 |
| E | 분할-시작 인터리빙: split 직후 해당 pane의 agent를 곧바로 start하는 루프 병합 | △ 레이스 윈도우 축소(C 확률 감소)이나 완전 제거 아님 | 중(배선 재구성) | 빠른 분할 연속에서 여전히 비결정적 | 채택(선택) — 결정론적 보완책 D 전제 하에 도입 |
| F | herdr 자체 `agent start --timeout` 상향만 | △ 하지만 busy fail-fast 경로는 timeout이 아니라 즉시 반환되므로 무의미 (§1.2-3) | 최저 | 부적절 pane 판정을 못 잡음 | 기각 |

### 2.1 채택 조합: D(핵심) + B의 페쇄형 변형(재시도) + E(구조 개선, 옵션)
- **D가 핵심인 이유**: `herdr pane wait-output`은 이미 도구 내장(builtin) 대기 프리미티브이며, 즉시 검색+폴링+`--timeout` 폐쇄 조건을 갖춰 sleep 폴링이 없이도 결정론적이다.
- **재시도 변형**: 이벤트 대기 자체가 실패(pane에서 마커 미출력发散 등)한 경우에만 최대 N회 재시도 — 트리거가 상태이지 시간이 아님.

## 3. 추천 해결책 (선정 + 근거)

**선정: pane ready 이벤트 기반 대기(D) + bounded 재시도 폐쇄 변형.**

구현 개념: 새 헬퍼 `wait_pane_ready <PANE_ID>` — pane이 interactive shell 프롬프트 상태임을 이벤트로 확증하는 유일한 판정부.
제일 확실한 ready 서명: "shell이 명령을 실제로 실행했다"는 사실. `pane run`을 프롬프트 이벤트 감지보다 강한 1차 프로브로 쓰고, wait-output으로 마커 회수:

```
wait_pane_ready() {
  local pane="$1" n=0
  # 폐쇄성: READY_TIMEOUT_S(기본 20) 초과 시 실패로 반환
  until herdr pane run "$pane" printf __HT_READY_MARKER__ >/dev/null 2>&1 \
        && herdr pane wait-output "$pane" --match "__HT_READY_MARKER__" --timeout 1500 >/dev/null 2>&1; do
    (( SECONDS < READY_TIMEOUT_S )) || { echo "error: pane $pane ready 대기 초과" >&2; return 1; }
    n=$((n+1)); log "pane $pane ready 대기 중 (attempt $n)"
  done
}
```
(최종 코드는 worker가 `pane run`의 완료 시맨틱과 프로브 마커 방식을 검증 후 확정 — 아래 §4 검증 포인트.)

배선 변경:
1. start 루프의 `herdr agent start ... --pane "${PANE_IDS[$i]}"` **직전**에 `wait_pane_ready "${PANE_IDS[$i]}"` 삽입 (L1052~1060 상·하단 분기 공통). 기존 `agent list | grep` 체크는 유지(중복 start 방지).
2. `run()` 개선: 실패 시 stderr 유출 — `"$@" > /dev/null` → `"$@" > /dev/null 2>&1 || { echo "error: 명령 실패: $*" >&2; return or exit; }` 형태로 성공/실패를 명시화 (무음 소실 제거, 폐쇄성 보강).
3. (옵션 E) 인터리빙 리팩터링은 D 적용 후 실패 재발 시에만 진행하는 2차 후보로 연기 — YAGNI.

인터페이스 예시일 뿐, 구현은 레포 기존 셸 컨벤션(down_split_ratio/log 등)을 따른다.

## 4. 구현 명세 대상 함수·파일 위치와 수용 테스트

### 4.1 대상
| 파일/함수 | 위치 | 변경 |
|---|---|---|
| `bin/herdr-team` | 신규 헬퍼 `wait_pane_ready()` — `down_split_ratio()`(L527) 부근 | D 구현: ready 프로브+bounded wait |
| `bin/herdr-team` | `run_team()` start 루프 L1049~1063 | start 직전 ready 대기 삽입 |
| `bin/herdr-team` | `run()` L490 | 실패 처리 명시화 (무음 소실 제거) |
| `bin/herdr-team` | dry-run 출력부 L930~935 | 위 배선을 dry-run에 동반 반영 |

### 4.2 검증 포인트 (worker가 구현 전 확인)
1. `herdr pane run <PANE_ID> <CMD>`: Returns immediately vs waits for completion? Does it require shell readiness?
2. `herdr pane process-info --pane <ID>`: Output schema 및 foreground process는 shell인지 식별 가능한 필드의 유무 (보조 프로브로 승격 가능) 확인.
3. `wait-output`의 snapshot source 기본 동작(visible vs recent)이 마커 감지에 충분한지.

### 4.3 수용 테스트 기준 (재현 테스트 포함)
- **R1 재현 테스트**: sleep없는 현 배선에서 반복 실행(≥5회)으로 `agent_pane_busy` 재현 → 로그 고정(재현 근거 문서화). 사전 조건: herdr 세션 활성 + 5인 프리셋(pkm).
- **R2 견고성 테스트**: 개선 후 동일 조건 반복 20회 — `agent_pane_busy` 0건 & 5인 전원 `herdr agent get <agent>`로 ready 확인. (근본 지표: 프로세스 경쟁이 사실상 제거되어야 함)
- **R3 폐쇄성 테스트**: 인위적으로 shell 기동을 지연시킨 pane(예: `pane run`으로120s 연산 실행 후 재분할)에서 — 무한 대기 없이 정해진 timeout 내 명시적 에러로 종료.
- **R4 dry-run 일관성**: `--dry-run` 출력에 ready 대기 배선이 포함되고, 그대로 실행 가능한 수준의 정확성 유지.
- **R5 프로젝트 테스트스위트 통과**: 기존 `tests/` 전체 회귀 PASS (worker [full-regression] 1회).

## 5. 엣지 케이스
1. pane 내 사용자 텍스트 편집 중(vim 등 foreground 다른 프로세스): pane run/wait-output 모두 실패 → 에러로 명확 종료 (조용한 실패 아님). 재실행 시 답변 안내 필요.
2. `SECONDS` 변수 사용하지 않는 zsh 환경 표준 POSIX 대체 필요할 수 있음 (스크립트 헤더 셸 확인).
3. 기존 세션 재실행: agent가 이미 존재(grep 소실 방지는 유지) → ready 대기는 새 pane에만 적용, 기존 agent는 skip.

## 6. 열린 질문 (PM/도구 확인)
1. sleep 0.5 우회가 실제로 어느 레이어(외부 운영 메뉴얼? 별도 watchdog?)에 있는지 확인 필요 — 레포 내엔 없음 (Q1).
2. `pane run`이 분할 직후 미성숙 shell에서도 큐잉되는지 (§4.2-1) — 최종 프로브 방식에 따라 구현 세부가 달라질 수 있음.
