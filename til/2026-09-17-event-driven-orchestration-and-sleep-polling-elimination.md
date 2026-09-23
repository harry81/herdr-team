# Today I Learned: 이벤트 기반 오케스트레이션과 Sleep 폴링 안티패턴 제거

- **날짜**: 2026-09-17
- **분류**: Multi-Agent Architecture / Performance Optimization / Orchestration Guardrails

---

## 1. 배경 및 문제 상황

Herdr 기반 멀티 에이전트 팀(`lo-`, `dev`, `biz` 등) 파이프라인 운영 중, 오케스트레이터(Task Manager / Orchestrator)가 다음 단계로 전환할 때 수십 초간 멍하니 대기하는 병목 현상이 관측되었다.

에이전트가 실제로 실행한 명령어를 추적한 결과, 다음과 같은 셸 스크립트 기반 폴링 루프를 자체 생성하여 실행하고 있었다:

```bash
# ❌ 관측된 안티패턴: 고정 슬립 기반 무거운 폴링 루프
for i in $(seq 1 60); do
  st=$(herdr agent list 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print([a['agent_status'] for a in d['result']['agents'] if a.get('name')=='lo-planner'][0])" 2>/dev/null)
  if [ "$st" = "idle" ]; then echo "IDLE after $((i*20))s"; break; fi
  sleep 20
done
```

### 이로 인한 문제점:
1. **고정 딜레이 누적 (Latency Penalty)**: 하위 에이전트가 1초 만에 작업을 끝내도, `sleep 20` 카운트다운이 만료될 때까지 최대 20초 동안 파이프라인이 멈춤. 단계가 누적될수록 수 분의 시간 낭비 발생.
2. **불필요한 시스템 부하**: 매 20초마다 `herdr agent list` 호출 ➔ `python3` 인터프리터 기동 ➔ JSON 파싱 과정을 수십 번 반복 실행.
3. **코드 복잡도 및 취약성**: JSON 출력 형식이나 에이전트 이름 파싱 오류 시 무한 루프나 조기 종료 위험.

---

## 2. 원인 분석 (Root Cause)

1. **지침서의 추상성**: 기존 템플릿 문서에 `herdr agent wait/read`라는 키워드만 나열되어 있고, 구체적인 명령 문법과 플래그가 예시로 주어지지 않음.
2. **LLM의 셸 스크립트 편향**: LLM이 백그라운드 프로세스 모니터링을 지시받았을 때, 일반적인 리눅스 셸 상식(bash `sleep` 루프)을 조합하여 방어적인 폴링 스크립트를 작성함.

---

## 3. 해결 방안: 이벤트 기반 네이티브 대기 (Event-Driven Wait)

Herdr CLI는 이미 소켓 API를 통해 에이전트의 상태 변화를 실시간 이벤트로 감지하는 네이티브 커맨드를 제공한다. 이를 표준 프로토콜로 강제 지정하였다.

### ✅ 패턴 1: 원샷 프롬프트 + 동기 대기 (`--wait`)
프롬프트를 전송하면서 작업이 끝날 때까지 한 줄로 대기:
```bash
herdr agent prompt {{PREFIX}}-planner "기획 명세 작성" --wait --timeout 600000
```
- 프롬프트 전달 후 상태가 `idle`/`done`으로 전환될 때까지 블로킹 대기.
- 별도의 대기 루프나 스크립트 작성이 완전히 불필요함.

### ⚠️(교정됨) 패턴 2: 소켓 이벤트 기반 상태 대기 (`herdr agent wait`)
비동기로 작업을 지시했거나 이미 실행 중인 에이전트를 대기할 때:
```bash
herdr agent wait {{PREFIX}}-planner --until idle,done --timeout 600000  # (2026-09-19 교정: --until 은 단일 상태값만 허용. 콤마 나열은 invalid agent status 에러)
```
- Herdr 데몬 소켓에서 에이전트 상태 변화를 푸시(Push) 방식으로 수신하여 **0ms 즉시 반환**.
- CPU 자원 소모 0, 고정 슬립 딜레이 0.

---

## 4. 비교 분석

| 평가 항목 | 기존 방식 (`sleep 20` 쉘 루프) | 개선 방식 (`herdr agent wait` / `--wait`) |
|---|---|---|
| **아키텍처** | 주기적 폴링 (Polling) | 소켓 이벤트 푸시 (Event-Driven) |
| **반응 지연** | 최소 10초 ~ 최대 20초 지연 | **0ms (이벤트 즉시 감지)** |
| **시스템 오버헤드** | 루프마다 서브프로세스 2개(python) 기동 | 단일 경량 소켓 대기 (자원 소모 없음) |
| **명령어 복잡도** | 8~10줄의 복잡한 셸 스크립트 | **단 1줄의 표준 CLI 커맨드** |
| **안정성** | 파싱 에러, 타임아웃 예외 취약 | 바이너리 레벨 타임아웃 및 상태 보장 |

---

## 5. 템플릿 및 가드레일 반영 내역

1. `templates/opencode-agents/ROLE-orchestrator.md`:
   - ❌ `sleep` 기반 쉘 폴링 루프 작성 절대 금지 조항 명시.
   - ✅ `--wait` 및 `agent wait` 표준 커맨드 규정.
2. `templates/agents/ROLE-taskmanager.md`:
   - 3.6 가드레일에 폴링 금지 및 소켓 이벤트 대기 필수 원칙 수록.
3. `templates/biz/AGENTS.md`, `templates/dev/AGENTS.md`, `templates/app/AGENTS.md`, `AGENTS.md`:
   - 1.1 PM 및 Orchestrator 가드레일 3번에 표준 대기 명령 명시.
