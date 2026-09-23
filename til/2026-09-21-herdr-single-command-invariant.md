# TIL: Herdr 명령어 한 줄 다중 실행 금지 원칙 (Strict Invariant)

- **작성일**: 2026-09-21
- **태그**: `herdr`, `multi-agent`, `shell`, `deadlock`, `orchestration`

---

## 1. 발생한 문제 현상
Herdr 오케스트레이션 환경에서 Reviewer 에이전트는 이미 작업을 끝마쳤음에도(idle), 이를 호출한 Orchestrator 에이전트가 쉘 명령 반환을 받지 못하고 무한 대기(Hang) 상태에 빠지는 현상이 반복적으로 발생함.

---

## 2. 근본 원인 분석 (Root Cause)
Orchestrator가 에이전트에게 프롬프트를 전송할 때 다음과 같이 파이프라인 필터를 한 줄로 엮어서 실행함:

```bash
herdr agent prompt <TARGET> "$PROMPT" --wait ... 2>&1 | tail -2
```

### 메커니즘
1. **표준입력(stdin) EOF 미수신으로 인한 블로킹**:
   - `tail -n` 명령어는 입력 스트림이 완전히 닫히는 `EOF(End Of File)` 신호를 받아야만 출력을 덤프하고 종료됨.
   - 서브쉘(zsh/bash) 파이프라인 환경에서 소켓/파이프 디스크립터가 상위 쉘에 물려있어, 좌측의 `herdr` 명령이 종료되었음에도 `tail` 프로세스가 EOF를 수신하지 못하고 영원히 대기함.
2. **소켓 및 TUI 버퍼 충돌**:
   - `herdr`는 백그라운드 소켓 통신 및 TUI 버퍼 제어를 실시간으로 수행하는 멀티플렉서 도구임.
   - 세미콜론(`;`), `&&`, `||`, 백그라운드(`&`)로 여러 명령어를 한 줄에 묶으면, 소켓 이벤트 수신 타이밍과 쉘 프로세스 반환 타이밍이 어긋나 데드락이 발생함.

---

## 3. 엄격 불변 규칙 (Strict Invariant)

> **⚠️ Herdr 관련 명령어는 절대 한 줄에 여러 명령어(연쇄 연산자, 파이프)를 실행해서는 안 된다.**

1. **파이프라인 필터 절대 금지**:
   - ❌ `herdr ... | tail -2`
   - ❌ `herdr ... | head -10`
   - ❌ `herdr ... | grep ...`
2. **연쇄/동시 연산자 절대 금지**:
   - ❌ `herdr ... && herdr ...`
   - ❌ `cmd1 ; herdr ...`
   - ❌ `herdr ... &`
3. **단독 명령 원칙 (Single-Command Execution)**:
   - ✅ 프롬프트 위임: `herdr agent prompt <TARGET> "<INSTRUCTION>" --wait`
   - ✅ 상태 대기: `herdr agent wait <TARGET> --until idle`
   - ✅ 화면 확인: `herdr pane read <PANE_ID>`
   - 모든 `herdr` 명령은 **반드시 한 줄에 오직 하나의 단독 명령어**로만 실행해야 한다.
