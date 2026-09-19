# Today I Learned: herdr agent wait 문법 오류 교정 및 유령 대기 프로세스 자동 해소 (Ghost Process Auto-Unblock)

- **날짜**: 2026-09-19
- **작성자**: PM / Orchestration Team
- **관련 커밋**: `e12ab62`
- **범위**: `herdr-team` (5종 프리셋 템플릿, `bin/herdr-watcher`, `AGENTS.md`)

---

## 1. 배경 및 문제 현상

팀 파이프라인 오케스트레이션 중 Orchestrator가 하위 에이전트(Planner, Worker, Reviewer)에게 작업을 지시한 후, 하위 에이전트의 작업이 끝났음에도 **최대 10~30분간 터미널이 멈춰 서는(Stuck)** 현상이 반복적으로 발생했다.

```
[Planner 작업 완료 (idle 전이)] ──► [Orchestrator는 여전히 대기 중 (Stuck)]
```

상태 추적 결과, 두 가지 독립적이지만 상호작용하는 원인이 규명되었다:
1. **잘못된 CLI 플래그 문법 (`--until idle,done`)**:
   - 기존 지침 문서에 `--until idle,done` 형태로 콤마 구분이 기술되어 있었으나, `herdr` CLI는 단일 상태값만 허용하므로 `invalid agent status: idle,done` 에러를 반환함.
   - 이를 본 LLM Orchestrator가 임의로 `--until done`으로 명령을 변경함.
   - 그러나 OpenCode 에이전트는 한 턴 작업을 마치면 `done`이 아닌 **`idle`**로 전이되므로, 타임아웃(30분)이 끝날 때까지 무한 대기함.
2. **복합 쉘 스크립트 실행 시의 레이스 컨디션 (Ghost Wait Process)**:
   - Orchestrator가 다음과 같은 한 줄 스크립트를 작성함:
     ```bash
     herdr agent prompt <TARGET> "..." --wait; herdr agent wait <TARGET> --until idle; herdr pane read ...
     ```
   - 앞의 `--wait`로 인해 첫 번째 명령이 끝났을 때 대상 에이전트는 이미 `idle` 상태임.
   - 뒤이어 실행된 `herdr agent wait --until idle`은 소켓 이벤트 구독을 시작하지만, **이미 완료된 상태이므로 '새로운 idle 전이 이벤트'가 발생하지 않아** 타임아웃 동안 블로킹됨.

---

## 2. 해결 아키텍처

### 1) 템플릿 정본 및 가이드 문서 문법 표준화
`herdr-team`의 5종 프리셋(`dev`, `mkt`, `biz`, `creator`, `research`) 및 가이드 문서의 구문을 일괄 수정하였다.

- **As-Is**:
  ```bash
  herdr agent wait <TARGET> --until idle,done --timeout <MS>  # ❌ 문법 에러 및 done 오인 대기
  ```
- **To-Be**:
  ```bash
  herdr agent wait <TARGET> --until idle --timeout <MS>       # ✅ 정상 소켓 이벤트 수신
  # 또는 옵션 생략 (기본 Settled 상태: idle, done, blocked 즉시 반환)
  herdr agent wait <TARGET> --timeout <MS>
  ```

### 2) `herdr-watcher` 유령 대기 프로세스 자동 해소 (`clean_stuck_waits`)
Orchestrator(LLM)가 프롬프트 뒤에 중복 `agent wait`를 붙이는 버릇이 있더라도 시스템이 멈추지 않도록, 백그라운드 감시 데몬인 [`bin/herdr-watcher`](../bin/herdr-watcher)에 자가 치유(Self-Healing) 로직을 탑재했다.

```python
def clean_stuck_waits(current_agents):
    try:
        out = subprocess.check_output(["ps", "-eo", "pid,args"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        for line in out.splitlines():
            if "herdr agent wait" in line and "grep" not in line:
                parts = line.strip().split()
                if not parts:
                    continue
                pid = parts[0]
                for name, info in current_agents.items():
                    if f"wait {name}" in line:
                        # 대상 에이전트가 이미 작업 완료(idle/done) 상태인데 wait가 물려있는 경우
                        if info["status"] in ("idle", "done"):
                            print(f"[{time.strftime('%H:%M:%S')}] [AUTO-UNBLOCK-WAIT] {name} 이미 {info['status']} 상태이나 대기 중인 프로세스(PID: {pid}) 감지 -> 자동 종료(kill)")
                            subprocess.run(["kill", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
```

- 5초마다 실행 프로세스를 스캔하여 "대상 에이전트는 이미 끝났는데 혼자 이벤트를 놓치고 기다리는 유령 wait 프로세스"를 즉시 제거한다.
- Orchestrator의 쉘은 5초 이내에 자동으로 다음 명령(`pane read` 및 후속 단계)으로 직행한다.

---

## 3. 검증 결과

1. **테스트 검증**: `tests/test_preset.sh` 255개 전체 PASS 확인.
2. **자가 치유 검증**: `flutter_meal_lens` 프로젝트에서 실제로 Worker 완료 후 멈춰 있던 Orchestrator의 `wait` 프로세스가 실시간으로 자동 감지 및 kill되어 파이프라인이 정상 재개됨을 확인.
