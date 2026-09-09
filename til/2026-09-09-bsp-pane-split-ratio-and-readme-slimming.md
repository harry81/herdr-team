# TIL: Pane 분할의 BSP 트리 구조와 ratio 1/(N-k+1) 균등 분할, README 랜딩 슬림화 (2026-09-09)

Herdr 터미널 레이아웃을 자동 구성하는 `bin/herdr-team`의 분할 로직에서 "사후 resize 땜질"을 걷어내고 **생성 시점 `--ratio` 균등 분할**로 교체한 작업과, 방문자 랜딩 UX를 위해 README를 "Problem & Solution 우선 + 레퍼런스 접기" 구조로 슬림화하며 정리한 내용.

## 1. BSP(Binary Space Partitioning) 트리 구조에서의 Pane 분할 중첩

터미널 멀티플렉서(tmux 계열·Herdr 포함)의 레이아웃은 **BSP 트리**로 모델링된다. 화면은 리프(pane)까지 이진 분할을 반복한 트리이며, 각 내부 노드는 방향+비율(`split`) 정보를 보유한다. "아래로 순차 분할(down 체이닝)"은 항상 방금 만든 pane을 다음 분할 대상으로 삼으므로, 한 컬럼의 분할 내역이 그대로 중첩된 단일 트리로 표현된다.

### 1.1 "resize는 노드의 ratio 델타, split --ratio는 노드의 ratio 절대값"

- `herdr pane split --direction down --ratio F` 는 **분할 대상 pane이 보유하는 비율**을 뜻하고, 나머지 `1-F`가 새 pane에 할당된다.
- `herdr pane resize --amount A` 는 포함(containing) split의 ratio에 **델타 보정**을 가한다. 절대 크기가 아니라 "노드가 이미 가진 ratio"에 대한 상대 변화다.
- 따라서 "결과 크기를 정확히 지정"하려면 split 시점에 `--ratio`를 박아야 하고, resize로는 목표 비율에 수렴시킬 수 없다.

### 1.2 균등화 ratio 수열 `1/(N-k+1)`의 유도

컬럼 높이를 1로 정규화하고, `A_k` = k번째 down 분할 직전 **대상 pane**(직전 split이 만든 pane)의 크기라고 하자.

- k=1에서는 첫 right 분할이 컬럼 전체를 차지하므로 `A_1 = 1`.
- k번째 down 분할에서 대상 pane이 `r_k`를 보유하고 `1-r_k`를 새 pane에 넘기면, 새 pane 크기는 `A_k·(1-r_k)`가 된다.

컬럼을 `N`등분하려면 각 단계에서 **대상 pane의 보유분과 새 pane이 모두 `1/N`** 이어야 한다. 대상 pane은 시점상 이미 `A_k = (N-k+1)/N` 크기를 갖고 있으므로:

```
r_k = (1/N) / A_k = (1/N) / ((N-k+1)/N) = 1/(N-k+1)
```

**N=4 수열 검산:**

```
k=1: A_1 = 1      → r_1 = 1/4 = 0.25      → ① 0.25 보유, 새 pane 0.75
k=2: A_2 = 3/4    → r_2 = 1/3 ≈ 0.333333  → ② 0.25 보유(0.75·1/3), 새 pane 0.50
k=3: A_3 = 1/2    → r_3 = 1/2 = 0.5       → ③ 0.25 보유(0.50·1/2), 새 pane 0.25
결과: 0.25 / 0.25 / 0.25 / 0.25 = 1:1:1:1   (68행 컬럼 실측 → 17/17/17/17)
```

- **흔한 오답**: 보유 비율을 `k/(k+1)`로 잡으면(k=1,2,3 → 0.5/0.666667/0.75) 새 pane이 항상 대상 pane의 `1/(k+1)`만 받아 아래로 갈수록 얇아져(0.5/0.333/0.125/0.042) 균등화되지 않는다. 이 수열은 "대상 pane이 컬럼의 `1/k`를 차지한다"는 전제(기본 0.5 체이닝에서만 성립)에서 나온 오해다. 보유 비율은 **컬럼 전체 대비 목표 크기(`1/N`)에서 역산**해야 하므로 `1/(N-k+1)`가 정답이다.
- 구현 시에는 `python3` 의존을 피하려 POSIX `awk 'BEGIN{printf "%.6f", 1.0/(n-k+1)}'`로 계산하고 후행 0을 제거(0.250000→0.25)해 명령 인자와 dry-run 출력을 일치시킨다(bash 3.x 호환).

### 1.3 관찰: 사후 resize 땜질은 구조적으로 불가능

- 기존 구현은 기본 0.5 체이닝(우측 컬럼이 27/21/12/8 식으로 기하급수 감소) 후 `resize --amount 0.10` 두 번으로 "균등화"를 시도했으나, resize는 ratio **델타**라 1:1:1:1이라는 목표값이 없어 수렴할 수 없다.
- 게다가 resize 보정을 **이미 균등해진 레이아웃에 적용하면 오히려 균등을 깨뜨린다.** → "남기되 조용히(`>/dev/null 2>&1`)"보다 **제거**가 유일하게 일관된 선택.

## 2. 생성 시점 ratio 분할 vs 사후 resize, 그리고 CLI JSON 출력 억제

### 2.1 split 시점 해결 vs resize 사후 보정

| | 생성 시점 `split --ratio` | 사후 `resize` |
|---|---|---|
| 값 의미 | 노드 ratio **절대값** | 포함 split ratio의 **델타** |
| 균등 목표 | `1/(N-k+1)` 수열로 정확 도달 | 목표값 부재 → 수렴 불가 |
| 상태 | 한 번에 정확(1:1:1:1) | 점진 보정, 버전별 의미 상이 |

- **설계 원칙**: 비율이 필요한 분할은 명령 **생성 시점**에 `--ratio`로 박고, resize 같은 사후 보정 단계는 두지 않는다. `--no-resize` 플래그는 하위호환 + "ratio 균등화 생략" 의미로 재정의해 죽은 플래그를 만들지 않는다.

### 2.2 불필요한 CLI JSON stdout 억제

- `herdr pane split/resize`는 `cli:pane:*` 원시 JSON을 stdout으로 출력한다. 필요한 곳은 `herdr_pane_id()`(jq)로 소비하고, **반환값이 필요 없는 호출은 `>/dev/null 2>&1`** 로 차단해 콘솔에 JSON이 누출되지 않게 한다.
- `cmd || true`는 **exit code만** 무시하지 stdout을 억제하지 못한다는 점에 유의 — 출력 억제는 리다이렉트의 역할이다.
- dry-run이 실제 실행 명령과 일치해야 하므로 dry-run 출력에서도 resize 라인 대신 실제로 실행될 `--ratio` split 라인을 그대로 출력한다.

## 3. README 슬림화 및 랜딩 UX 최적화

방문자가 "5초에 필요성 이해, 30초에 실행"하도록 구조를 재배치.

- **Problem & Solution 우선 배치**: "AI 에이전트 팀을 매번 손으로 탭 생성→분할→에이전트 시작→역할 셋업" 문제 → "`hts` 한 줄(또는 더블클릭)로 4분할 AI 팀" 해결을 인용 블록 1~2줄로 문서 첫머리에 배치해 5초 가치제안.
- **How it looks 직후 배치**: 4분할 아스키 박스 + 파이프라인 다이어그램(`User → ① PM → task manager → ② Planner → ③ Worker → ④ Reviewer ─[APPROVE + run log]→ report`, `↑...[REQUEST CHANGES]...|` 회귀 화살표)으로 텍스트 설명 없이 동작 구조 전달.
- **Why 압축**: 3프리셋의 장황 문단을 "누구를 위한 것인가" 1줄로 줄이고 상세는 Preset Summary 표로 이관.
- **레퍼런스 `<details>` 접기**: 저장소 구조·동작 순서·TUI·CLI 옵션표 등 부록을 `<details><summary>...</summary>` 안에 보존. `## Advanced` 헤딩 문자열은 접힌 본문에 유지 — CI 가드레일(grep substring 존재 검사)은 문자열 존재만 보므로 통과한다.
- **CI 가드레일 토큰 보존**: `# herdr-team`(L1), `## Quick Start`, `## Advanced`, `start-team.bat`, `curl`, `hts`, `shields.io`, `license`, `PRs Welcome`, raw install URL 등은 1회 존재만으로 충족 → 재배치·접기가 안전. 배지 URL·raw URL은 절대 변경 금지.
- **문서 대칭 유지**: README.md(정본)와 README.ko.md가 섹션 순서·개수를 동일하게 유지(한국어판은 한국어 골격) — 리뷰어의 구조 spot-check 지점.
