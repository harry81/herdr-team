# TIL: 2열 Pane 레이아웃 오케스트레이션과 SIGPIPE 파이프라인 안정성 (2026-09-14)

## 1. 2열 Pane 레이아웃 분할 순서와 BSP(Binary Space Partitioning) 트리

Herdr(tmux/zellij 백엔드)와 같은 터미널 멀티플렉서 환경에서 복합 그리드 레이아웃을 구성할 때, **분할 순서(Split Order)**는 레이아웃 트리의 계층 구조를 결정하는 핵심 요소이다.

### 기존 단일 우측 스택 (`right-stack`)의 한계
* `BASE(PM)`에서 우측(`right`)으로 분할 후, 계속해서 아래(`down`)로 체이닝 분할.
* 결과: 좌측에 PM 하나만 세로 전체를 차지하고, 우측 컬럼에 Task Manager, Planner, Worker, Reviewer가 4등분되어 세로 공간이 협소해짐.

### 2열 그리드 (`2col`) 분할 순서 설계
좌측 열에 `[PM / Task Manager]`, 우측 열에 `[Planner / Worker / Reviewer]`를 배치하기 위한 분할 알고리즘:

```text
+-------------------+----------------------------+
| ① PM (상단 50%)   | ③ Planner (우측 상단 1/3)   |
|                   +----------------------------+
|                   | ④ Worker (우측 중단 1/3)    |
+-------------------+----------------------------+
| ② Task Manager    | ⑤ Reviewer (우측 하단 1/3)  |
|   (하단 50%)      |                            |
+-------------------+----------------------------+
```

1. **1단계: 우측 컬럼 분기 (Right Split)**
   * `BASE(PM)`에서 우측(`--direction right`)으로 분할하여 우측 상단 기준 pane(`first_right_pane`)을 생성.
2. **2단계: 좌측 컬럼 양분 (Down Split with ratio 0.5)**
   * `BASE(PM)`에서 하단(`--direction down --ratio 0.5`)으로 `Task Manager` pane 생성.
   * PM은 상단 50%, Task Manager는 하단 50%로 정확히 1:1 양분.
3. **3단계: 우측 컬럼 균등화 (Down Splits with ratio 1/(M-k+1))**
   * 우측 상단 pane에서 시작하여 우측 나머지 역할 수 $M$에 대해 순차적 down 분할.
   * $M=3$일 때:
     * $k=1$ (Worker): $\text{ratio} = 1/(3-1+1) = 1/3 \approx 0.333333$
     * $k=2$ (Reviewer): $\text{ratio} = 1/(3-2+1) = 1/2 = 0.5$
   * 우측 컬럼의 3개 pane이 1:1:1로 균등 분할됨.
4. **4단계: 역할과 Pane ID 1:1 매핑 유지**
   * `ROLES` 배열 순서(`taskmanager`, `planner`, `worker`, `reviewer`)에 맞춰 `PANE_IDS` 배열을 재구성하여 후속 레이블링(`herdr pane rename`)과 에이전트 구동(`herdr agent start`) 파이프라인의 하위 호환성을 100% 보장.

---

## 2. Shell 파이프라인과 SIGPIPE 함정 (`set -o pipefail` 환경)

### 문제 현상
* 테스트 스크립트(`set -uo pipefail`)에서 `assert_contains` 검증 시 간헐적 실패:
  ```bash
  assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3"; fi
  }
  ```
* `grep -q`는 매칭되는 문자열을 발견하는 즉시 프로세스를 종료(`exit 0`)함.
* 검사 대상 변수(`$1`)의 내용이 버퍼 크기(약 64KB)보다 클 경우, `printf`가 닫힌 파이프에 쓰기를 시도하면서 `SIGPIPE`(종료 코드 141)를 수신.
* `pipefail` 옵션으로 인해 파이프라인 전체 반환값이 141(비정상)이 되어 `if` 문이 `false`로 빠지는 문제 발생.

### 해결책
1. **SIGPIPE 방어**: 조기 종료하는 `-q` 대신 `grep -F -- "$2" >/dev/null`을 사용하여 파이프가 닫히지 않고 전체 입력을 안전하게 소진하도록 처리.
2. **원천 차단**: `.opencode/*`, `node_modules` 등 불필요한 임시 디렉토리를 `.gitignore` 및 빌드 아카이브(`build-zip.sh`) 제외 목록에 추가하여 버퍼 폭증 방지.

---

## 3. 사용자 제어 가능한 3계층 레이아웃 구성

* **1순위 (CLI)**: `ht --layout 2col` 또는 `ht --layout right-stack`
* **2순위 (환경변수)**: `HERDR_TEAM_LAYOUT="2col"`
* **3순위 (프리셋 파일)**: `templates/<preset>/preset.conf` 내 `LAYOUT="2col"`
* **기본값**: `2col`
