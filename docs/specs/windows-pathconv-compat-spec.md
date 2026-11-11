# Windows MSYS 슬래시 경로 자동 변환 호환 명세 (fix/windows-runtime-compat)

- 브랜치: `fix/windows-runtime-compat` (체크아웃 완료). 선행 명세 `docs/specs/opencode-startup-compat-spec.md`는
  이미 구현 완료(working tree, `agent.err.start_fail`/`--timeout`/rc 기반 프루브 확인됨) — 본 명세는 그 위에 얹는 긴급 수정.
- 대상: `bin/herdr-team`의 `opencode_session_for` api 호출, `tests/test_agent_session.sh`,
  `tests/test_windows_launcher.sh`.
- 작성자: ht-planner (기획/설계 전용, 코드 수정 없음).
- 결론 요약: `MSYS2_ARG_CONV_EXCL='/api'`를 **호출 단위**로 `run_capture opencode api post /api/session`
  호출에만 적용한다. bat 레벨 변경 불필요(방어는 bash 스크립트 내부이므로 모든 진입 경로 커버).

---

## 1. 진단 근거 (사실 기록)

### 1.1 버그 재현 서술 (Windows Git-Bash, 본 머신은 Linux라 실측 불가 — 추측 표기)

사용자 보고 + MSYS2 공식 문서 기준 재현 경로(추측 없는 부분 = 문서 근거, 환경 세부는 보고 기반):
1. `windows\start-team.bat` → Git-Bash 백엔드 선택(63행, 162행) →
   `"%ProgramFiles%\Git\bin\bash.exe" "!MSYS_REPO!/bin/herdr-team" --cwd "!MSYS_CWD!" ...`
2. `bin/herdr-team` 시작 루프(`bin/herdr-team:1983-1992`)가 `opencode_session_for` 호출.
3. `bin/herdr-team:1486`:
   `out="$(run_capture opencode api post /api/session -d "$payload")"`
4. MSYS2 런타임은 **네이티브 Windows 실행 파일(opencode.exe / opencode.cmd 셈) 스폰 시** 슬래시로 시작하는
   인자를 POSIX 경로로 간주해 자동 변환한다. Git for Windows 설치 기준 Git 루트가 설치 디렉터리이므로
   `/api/session` → `C:/Program Files/Git/api/session`.
   (근거: MSYS2 공식 문서 "Automatic Unix → Windows Path Conversion — Process Arguments";
   Git for Windows Known Issues "command-line options starting with a slash ... conversion will kick in")
5. opencode v2는 `C:/Program Files/Git/api/session`을 HTTP method+path도 OpenAPI operation ID도 아닌
   값으로 보고 `Expected an operation name or an HTTP method and path` 예외 → rc!=0.
6. 선행 명세의 fail-fast 계약에 따라 `agent.err.session_fail` → `agent.err.session_abort` → 시작 중단.
   즉 **Windows Git-Bash에서 opencode 팀 시작이 항상 실패**한다(세션 사전생성 경로가 전부 이 호출에 의존).

### 1.2 진단 1 — `opencode_session_for`와 `run_capture` (라인 번호, 현재 working tree)

- `run()` `bin/herdr-team:1140-1150`: dry-run 시 계획만 출력, 실모드 `"$@" >/dev/null && return 0`.
- `run_capture()` `bin/herdr-team:1152-1157`: dry-run 계획 출력, 실모드 `"$@"` **그대로 exec**.
  쿼팅 수준: 인자는 각각 호출부에서 개별 쿼팅(`-d "$payload"`)되고 런타임 변환은 전혀 없음 —
  셸 차원에서는 인자가 온전히 보존된다. 즉 **변환은 셸이 아니라 MSYS2 런타임이 exec 시점에 수행**하므로
  쿼팅 강화로는 방어 불가능(근거: §2.1 문서 — 변환은 인자 문자열 기준).
- `opencode_session_for()` `bin/herdr-team:1470-1495`:
  - 1471-1475: agent/var/model 준비 (`mp` 모델 조각).
  - 1476-1479: dry-run 계획 printf — **문자열 출력일 뿐 exec 없음**, 변환 대상 아님.
  - 1481-1485: payload JSON 생성(`jq -nc ...`). jq 인자는 `{...}`·`.` 시작이라 변환 면제(§1.4).
  - **1486: 실제 호출 — 유일한 변환 노출 지점.**
    `run_capture opencode api post /api/session -d "$payload"`
    - `opencode` 실행 파일명(변환 대상 아님), `api`/`post`(슬래시 없음), **`/api/session`(변환 대상)**,
      `-d`(옵션), `"$payload"`(`{` 시작 JSON → 면제).
  - 1490-1494: sid 파싱(`jq_text '.data.id // empty'` — `.` 시작 → 면제).
- `opencode_supports_api()` `bin/herdr-team:1460-1468`: `opencode api --help` 프루브 — 슬래시 인자 없음,
  변환 노출 없음. 단 **호출 단위 방어의 스코핑 검증 대상**(§5 TB-3).

### 1.3 진단 2 — MSYS 자동 경로 변환 조건 (근거: msys2.org/docs/filesystem-paths, Git for Windows Known Issues)

변환 실행 조건: **MSYS/Cygwin 컨텍스트의 bash에서 네이티브 Windows 실행 파일을 호출할 때**, 인자 문자열이
POSIX 경로처럼 보이면 변환한다. 판정 표:

| 인자 예 | 판정 | 근거 |
|---|---|---|
| `/api/session` | **변환됨** → `C:/Program Files/Git/api/session` | 선행 `/` = 절대 POSIX 경로. 본 버그 원인 |
| `--upload-pack=/opt/...` | 변환됨(옵션 내부 경로) | 문서 명시 예시 |
| `--dir=/foo` | 변환됨 | msys2.org 예시 |
| `/foo:/bar` | 변환됨(경로 리스트, `:`→`;`) | msys2.org |
| `C:/Users/x`, `C:\Users\x` | **면제** | 이미 Windows 형태(드라이브 접두) — `CWD_HERDR`(`bin/herdr-team:409-411`, `cygpath -w`)가 이 형태 |
| `{...}`(JSON payload), `.data.id`, `(?m)^...`, `s/^./\U&/`, `__HT_READY_MARKER__` | **면제** | 선행 `/`·경로 리스트 형태 아님 |
| `relative/path` | 면제 | 상대 경로는 변환하지 않음(문서) |
| `//server/share`, `//x` | 변환됨(UNC/`/x` 축소) — 이중 슬래시 트릭은 Git-Bash 한정 | §3.2 기각 근거 |

변수 차이 (근거: msys2.org filesystem-paths, Git for Windows Known Issues, msys2-runtime#357):

| 항목 | `MSYS2_ARG_CONV_EXCL` | `MSYS_NO_PATHCONV` |
|---|---|---|
| 지원 런타임 | MSYS2 정본 + Git for Windows(포크가 상속) | **Git for Windows 전용**(정본 MSYS2는 무시) |
| 의미 | 인자 변환 **제외 목록**. `*`=전체, 또는 `;` 구분 **인자 접두사 리스트**(인자 문자열 전체에 접두 매칭) | 존재 검사 — 값이 `1`/`0`/빈값이든 **정의되기만 하면 모든 변환 비활성** |
| 스코프 | **인자 변환만** (env 변환은 별도 `MSYS2_ENV_CONV_EXCL`) | 인자+env 등 **전부** |
| 부작용 | 접두 지정 시 목표 인자만 면제 — 같은 호출의 다른 변환은 유지 | 같은 호출에서 *필요한* 변환까지 죽임(msys2-runtime#357 AWS 사례: 전역 설정 시 자격증명 경로 변환이 사라져 실패) |
| 전역 export 부작용 | 다른 명령의 의도된 변환(예: `git -C "$CWD"`의 POSIX→Windows, `mktemp /tmp/...`)이 깨질 수 있음 — 동일 | gcloud 브레이크 실측 사례 존재(pascallandau.com 블로그: 전역 export 후 `C:\c\Users\...` 오류) |

**확정: `MSYS2_ARG_CONV_EXCL='/api'` 단독 사용.** 근거: (1) Git Bash·순수 MSYS2 양쪽에서 유효한 유일 변수,
(2) 접두 매칭이라 `/api/session`만 정밀 면제 — 같은 호출의 다른 인자 변환 보존, (3) `MSYS_NO_PATHCONV`는
Git-Bash 전용 + 존재 검사 계약(값 무시) + 광역 차단이라 부작용 표면이 넓다.
두 변수 **병용은 하지 않는다**: 병용 시 Git Bash에서는 NO_PATHCONV가 사실상 승자가 되어 정밀성이 사라지고,
테스트 계약이 런타임별로 갈라진다(§5 stub 검증은 단일 값 단언으로 단순화).

### 1.4 진단 3 — MSYS 관련 방어 전무 확인 + bat 호출 지점 전수 열거

`grep -rn "MSYS\|NO_PATHCONV\|ARG_CONV" bin windows *.bat install.sh tests` 결과: **방어 코드 0건**
(`MSYS_REPO=` 등은 bat 자체의 경로 문자열 치환일 뿐 변환 방어와 무관). 방어는 전무하다.

bat 파일 목록(9개)과 bash 호출 지점:

| 파일 | bash 호출 지점(행) | 내용 | 환경 전파 |
|---|---|---|---|
| windows/start-team.bat | 32 | `wsl bash -lc "echo wsl-ok"` 감지 프루브 | cmd `setlocal EnableDelayedExpansion` 내; HERDR_TEAM_* 사용자 env 상속 |
| 〃 | 60 | `wsl bash "!WSL_REPO!/bin/herdr-team" --precheck` | WSL=Linux, **MSYS 변환 없음**(방어 무관) |
| 〃 | 63 | `"%ProgramFiles%\Git\bin\bash.exe" "!MSYS_REPO!/bin/herdr-team" --precheck` | Git Bash. **MSYS 변환 활성, 방어 없음** |
| 〃 | 144 | `wsl bash ... --cwd "!WSL_CWD!" ...` (실실행) | Linux |
| 〃 | **162** | `bash.exe "!MSYS_REPO!/bin/herdr-team" --cwd "!MSYS_CWD!" %PRESET_ARG% %KIND_ARG% %*` (실실행) | **본 버그의 주 경로**. cmd env(setlocal)가 그대로 자식 bash에 상속 |
| windows/install.bat | 44 | `wsl bash -lc "echo wsl-ok"` 프루브 | 〃 |
| 〃 | 71 | `wsl bash "!WSL_REPO!/bin/herdr-team" --precheck` | Linux |
| 〃 | 79 | `"%ProgramFiles%\Git\bin\bash.exe" "!MSYS_REPO!/bin/herdr-team" --precheck` | Git Bash, 방어 없음 |
| windows/start-watcher.bat | 25 | `wsl bash -lc "echo wsl-ok"` 프루브 | 〃 |
| 〃 | 42 | `wsl bash ... --precheck` | Linux |
| 〃 | 45 | `bash.exe ... --precheck` | Git Bash, 방어 없음 |
| 〃 | 96 | `bash.exe -c "python3 '!MSYS_REPO!/bin/herdr-watcher' ... \|\| python ..."` | `-c` 문자열 인자 하나(선행 문자 `p`)라 인자 변환 미적용; 문자열 내부 경로는 `C:/` 형태라 면제 |
| install.bat / start-team.bat / start-watcher.bat (루트 3개) | 없음 | `call windows\*.bat` 순수 셈 | — |
| hts.bat / htw.bat (루트) | 없음 | `call windows\*.bat` 순수 셈 | — |
| windows/create-shortcut.bat | 없음 | powershell만 사용 | — |

환경 전파 결론: bat의 `set`/사용자 env는 `setlocal` 블록 내에서 자식 bash.exe 프로세스 환경으로 상속된다.
**그러나 방어를 bash 스크립트 내부 호출 시점에 적용하면 bat/PowerShell/cmd/더블클릭 어느 진입 경로든 무관하게
커버된다** — 방어 변수를 bat에 심을 필요가 없다(§2.2).

### 1.5 진단 4 — 슬래시 인자 노출 전수 조사 (bin/herdr-team exec 지점)

exec 발생 지점 전수(`run`/`run_capture`/직접 호출) 조사 결과, 선행 슬래시 인자는 **1곳뿐**:

| 위치 | 호출 | 노출 | 판정 |
|---|---|---|---|
| `bin/herdr-team:1486` | `run_capture opencode api post /api/session -d "$payload"` | `/api/session` | **수정 대상 (유일)** |
| `bin/herdr-team:1477-1478` | dry-run 계획 printf | `/api/session` 텍스트 | exec 없음 — 면제 |
| `bin/herdr-team:1465` | `opencode api --help` 프루브 | 없음 | 면제 |
| `bin/herdr-team:1218,1224-1225` | `herdr pane run/wait-output --match/--regex "$HT_READY_MARKER..."` | 마커는 `__HT_READY_MARKER__` 기반, `(?m)^...` 시작 | 선행 `/` 아님 — 면제 |
| `bin/herdr-team:1965,1970,1988,1994` | `run herdr pane rename` / `agent start --timeout --pane ... -- --session "$sid"` | `ses_*`·pane id·숫자 | 면제 |
| `bin/herdr-team:575-576,1012` | `git -C "$CWD" rev-parse` | `$CWD` POSIX 경로 → **의도된 변환**(`C:\...`) | 변환이 *필요한* 사례 — 전역 방어 금지의 근거 |
| `bin/herdr-team:1481,1490` | jq/jq_text 인자 | `{`·`.` 시작 | 면제 |
| `bin/herdr-team:516` | `mktemp "${TMPDIR:-/tmp}/ht-cnt.XXXXXX"` | `/tmp/...` | **변환 대상이나 현행 동작 유지** — Git Bash에서 /tmp 마운트가 Git 루트로 매핑되어 임시파일 기능상 문제 미보고. `shortcut: /tmp 프루브는 기존 동작 유지, Windows에서 임시파일 문제 보고 시 cygpath 기반으로 재검토` |
| 그 외(install.sh, watcher bat -c 내부) | POSIX/Linux 도구 대상 또는 `C:/` 형태 | — | 범위 외/면제 |

결론: 방어는 1486 단일 호출에만 필요하고, 그 이외의 변환은 의도된 동작이므로 **호출 단위 적용이 정답**이다.

### 1.6 진단 5 — Linux 재현 불가 → stub 기반 검증 전략

본 머신(Linux)에서 MSYS 변환은 재현 불가. 검증은 stub으로 대체한다:
- 가짜 `opencode`(이미 `tests/test_agent_session.sh:54-73` 존재)를 확장해 **받은 argv와 자신에게 설정된
  MSYS 방어 변수를 호출마다 로그에 기록**하게 한다.
- 테스트는 (i) 방어 변수가 실제 `opencode api post /api/session` 호출 환경에 전달되었는지, (ii) 값이
  정확히 `/api`인지, (iii) 다른 opencode 호출(프루브 등)에는 노출되지 않는지(호출 단위 스코핑),
  (iv) argv에 `/api/session`이 **리터럴로 그대로** 도달하는지(Linux 비회귀 불변식)를 단언한다.
- 한계(명시): Linux stub은 "변환이 실제로 막혔는지"는 증명할 수 없다. 증명 가능한 것은 "방어 변수가
  정확한 값으로 해당 호출에 전달됨"까지이며, 실변환 차단은 MSYS 공식 문서의 변수 계약에 근거한 신뢰다.
  Windows 실기 검증은 사용자 보고/수동 확인 대상으로 남긴다(열린 질문 §7-2).

---

## 2. 수정 계약

### 2.1 불변식

- **I-P1 (유일 노출 지점 방어)**: `bin/herdr-team:1486`의 `run_capture opencode api post /api/session`
  호출에만 `MSYS2_ARG_CONV_EXCL='/api'`가 설정된다. 다른 opencode 호출(`api --help` 프루브 등)에는
  변수가 노출되지 않는다(호출 단위 스코핑 — stub 테스트로 단언).
- **I-P2 (비MSYS 무부작용)**: Linux/macOS에서 `MSYS2_ARG_CONV_EXCL=/api`는 opencode가 무시하는 알 수 없는
  env일 뿐이며, argv는 변환 없이 그대로 전달된다. stub 테스트가 `/api/session` 리터럴 도달을 단언한다.
- **I-P3 (기존 테스트 불변식 유지)**: `tests/test_agent_session.sh` 기존 27 케이스(a~l, 현재 0 FAIL)과
  `tests/test_preset.sh` §17/§39(`-- --agent` 미사용, `--pane ... -- --session` 정합)은 유지.
- **I-P4 (진입 경로 독립)**: 방어는 `bin/herdr-team` 내부이므로 windows/*.bat, PowerShell 직접
  `bash.exe bin/herdr-team ...`, cmd 직접 호출 어디서든 동일 적용된다. **bat 파일 변경 없음.**
- **I-P5 (사용자 값 비보존 계약)**: 해당 호출에서 `MSYS2_ARG_CONV_EXCL`은 `/api`로 **덮어쓴다**.
  사용자가 전역으로 설정한 값이 있어도 이 한 호출에서만 무시된다(트레이드오프 명시 — 병합 로직
  `;` 결합은 불필요한 복잡도, YAGNI).

구현 형태(인터페이스 예시, `bin/herdr-team:1486` 교체):
```bash
  # Git-Bash/MSYS2는 선행 '/' 인자를 Windows 경로로 자동 변환한다(/api/session → C:/Program Files/Git/api/session).
  # 이 호출에만 접두 제외(MSYS2_ARG_CONV_EXCL, msys2.org filesystem-paths)를 적용한다 — 비MSYS는 무시하는 env일 뿐(I-P2).
  if ! out="$(MSYS2_ARG_CONV_EXCL='/api' run_capture opencode api post /api/session -d "$payload")"; then
```
- 함수 호출에 대한 `VAR=x fn` 접두: bash는 함수 스코프에 임시 export 변수를 부여하며 함수 내부 exec에
  상속된다(본 머신 bash 실측: `MSYS2_ARG_CONV_EXCL=/api f` → 함수 내 `env`에서 관찰됨, 미설정 시 관찰 안 됨).

### 2.2 적용 위치 판정 (요구사항 대응)

| 후보 | 판정 | 근거 |
|---|---|---|
| **함수 내부 호출 단위** | **채택** | 유일 노출 지점이 1486 하나(§1.4). 다른 호출·다른 명령의 의도된 변환 보존. 스코핑이 stub 테스트로 검증 가능(I-P1). bat/PowerShell/cmd 진입과 무관하게 커버(I-P4) |
| 스크립트 전역 export | 기각 | `git -C "$CWD"` 등 의도된 변환까지 위험(§1.4). 방어 표면이 필요 이상으로 넓고, 사용자가 임의로 설정한 값과 충돌 가능 |
| bat 호출 지점 전달 | 기각 | 루트 셈·PowerShell·직접 bash 호출 등 bat을 거치지 않는 경로를 커버하지 못함(요구사항 위반). windows/*.bat 4개 × 호출 지점 6곳 중복 관리 비용 |

### 2.3 슬래시 우회 대안 검토 (요구사항: 존재하면 판정)

| 대안 | 판정 | 근거 |
|---|---|---|
| OpenAPI operation ID 사용 (`opencode api <operationId> -d ...`) | 보류 (미채택) | help상 가능성은 있으나(`opencode api --help`: "OpenAPI operation ID") operation ID 목록 확인에 **기동 중인 서버 필요** — Linux에서 확인 불가. 확인되면 변환 문제를 근원 회피하지만 버전별 ID 취약성. 열린 질문 §7-1 |
| 상대 경로 `api/session` (선행 슬래시 제거) | 기각 | 변환은 안 되지만 opencode가 상대 경로를 수용하는지 검증 불가(문서상 "HTTP method and path" 표기만 존재). 잘못 수용 시 조용히 다른 의미로 해석될 위험 — env 변수 방어가 결정론적 |
| 이중 슬래시 `//api/session` | 기각 | Git for Windows는 `//x`→`/x` 축소로 회피 가능하나, **순수 MSYS2는 `//x`를 UNC형으로 처리**해 `\\api\session`으로 변환(다른 깨짐). 또한 `MSYS_NO_PATHCONV` 병용 시 축소가 일어나지 않아 상호 배타적. Git-Bash 전용 트릭 |
| 별도 플래그로 path 전달 | 기각 | api 서브커맨드에 path용 플래그 없음(`--data/-d` 본문뿐, 실측 help) |

### 2.4 실패 메시지 진단성 (신규 키 비용 명시)

- 채택(저비용): **기존 키 텍스트 확장** — `agent.err.session_fail`(`bin/herdr-team:150`)을
  `'error: session creation failed (%s) - check opencode install/background service (Git-Bash/MSYS: /api argument auto-conversion is blocked via MSYS2_ARG_CONV_EXCL=/api)'` 로 변경.
  키 추가가 아니므로 `tests/test_tui_i18n.sh` 키집합 검사 영향 **0**.
- 신규 키 경로(비고): 별도 키(예: `agent.err.session_msys`)를 두면 조건별 상이 메시지가 가능하나
  `MSG_KEYS(89)` + `_msg_en(93+)` + i18n 키집합 3곳 동시 변경 필요(선행 명세 §TB-5와 동일 절차).
  본 태스크에서는 채택하지 않는다 — 필요성이 단일 문구로 충분하기 때문.

---

## 3. 테스트 보강 설계

### 3.1 stub 기반 검증 (tests/test_agent_session.sh)

- stub `opencode`(`tests/test_agent_session.sh:54-73`) 확장: 각 호출마다 로그에
  `ENV MSYS2_ARG_CONV_EXCL=<값> MSYS_NO_PATHCONV=<값>` 라인을 argv 라인 **앞에** 기록.
  `OPENCODE_ENV_LOG` 미설정 시 `/dev/null`로 기존 동작 무변경:
  ```bash
  printf 'ENV MSYS2_ARG_CONV_EXCL=%s MSYS_NO_PATHCONV=%s\n' "${MSYS2_ARG_CONV_EXCL-}" "${MSYS_NO_PATHCONV-}" >> "${OPENCODE_ENV_LOG:-/dev/null}"
  printf '%s\n' "$*" >> "${OPENCODE_CALL_LOG:?}"
  ```
  (변수 확장 시 `${VAR-}` 형태 사용 — stub은 `set -u` 영향 밖이지만 계약상 안전 형태로 통일.)
- `run_case`(`tests/test_agent_session.sh:75-81`)에 `OPENCODE_ENV_LOG="$dir/env.log"` 전달 추가.

### 3.2 신규 케이스

- **case m) MSYS 방어 변수 전달** (RED 먼저): `run_case ok` 후
  (i) `env.log`에서 `api post /api/session` argv 라인 직전 ENV 라인이 `MSYS2_ARG_CONV_EXCL=/api`인지,
  (ii) 값이 정확히 `/api`(접두 완전일치 — `/api/...` 같은 과잉값 불허),
  (iii) `MSYS_NO_PATHCONV`는 **설정되지 않음**(미채택 변수의 실수 주입 방지).
  단언 방식: `grep -B1 -F 'api post /api/session' env.log | grep -F 'MSYS2_ARG_CONV_EXCL=/api'` 계열.
- **case n) 스코핑 + Linux 비회귀 가드**:
  (i) `api --help` 프루브 호출의 ENV 라인에는 방어 변수가 **없음**(호출 단위, I-P1 —
  구현을 전역 export로 때우면 이 단언이 FAIL로 잡는다),
  (ii) `opencode.log`에 `/api/session`이 리터럴로 존재(argv 무손상, I-P2),
  (iii) 방어 변수는 `run_case` 외부 환경에 export되지 않음(스크립트 프로세스 밖 누출 없음).
- **case o) 값 불변식**: 동일 run에서 세션 생성 호출 수(=역할 수 4)만큼의 ENV 라인이 모두 `/api`로 동일
  (캐시·반복 호출 간 일관성).

### 3.3 bat 정적 단언 (tests/test_windows_launcher.sh)

기존 방식(파일을 `cat` → `assert_contains` 토큰 단언, §4-§10)을 따라 신규 케이스 추가:
- (i) `bin/herdr-team`에 방어 토큰 `MSYS2_ARG_CONV_EXCL` 존재(**단일 소스 고정**) — bat이 자체 방어를
  중복 구현하는 드리프트를 차단하는 반대 방향 단언으로 "windows/*.bat에 MSYS2_ARG_CONV_EXCL/MSYS_NO_PATHCONV
  토큰 없음"을 함께 단언(방어는 bash 스크립트 소유, I-P4).
- (ii) 기존 Git-bash 위임 단언(`windows\start-team.bat` 등)과 충돌 없음 확인.
- **범위 밖 명시**: 기존 `printf %s | grep` 조합의 SIGPIPE 거짓 음성 flake(본 머신 재실행 시 FAIL 수가
  1↔5로 변동하는 실측 확인됨)는 손대지 않는다. 신규 단언은 파일 텍스트 기반 `assert_contains`만 추가하고
  새 파이프라인 패턴을 만들지 않는다.
- 기존 4~5건의 FAIL(연구 프리셋 라벨·winget 토큰 등 bat 내용 드리프트)은 **선존결함** — 본 태스크 완료
  기준에서 제외하되, 신규 단언으로 인한 **신규 FAIL 0**을 기준으로 한다.

### 3.4 테스트 티어 (Fast Loop 원칙)

- **T1 Fast-Loop**(편집 루프마다, 5초 이내): 변경 파일 대응 단일 케이스만 —
  `bash tests/test_agent_session.sh`의 신규 case m/n(해당 블록만 추출 실행은 불가하므로 스위트 전체,
  현재 ~2s 실측으로 5초 이내 충족).
- **T2 Scoped Regression**(태스크 완료 시 1회): `bash scripts/testmap.sh` 매핑 스위트 — 본 태스크 최소
  집합: `tests/test_agent_session.sh tests/test_preset.sh tests/test_pane_ready.sh
  tests/test_permissions_seed.sh tests/test_windows_launcher.sh`. 고지:
  `[T2 scoped] <command> → N passed in T s`.
- **T3 Full Regression**(push 직전, reviewer 노드 전용 — worker 임의 실행 금지): testmap 전체 +
  `tests/test_preset.sh`.

---

## 4. Task Breakdown (TDD 순서, ht-worker용)

### TB-1 — stub env 기록 인프라 + RED (tests/test_agent_session.sh:54-81 부근)
- **RED**: §3.1대로 stub/run_case 확장 후 §3.2 case m 작성 → 방어 미구현이라 FAIL 확인.
- **구현**: 테스트 인프라만 변경(bin 무변경).
- **T2**: `bash tests/test_agent_session.sh` (case m만 FAIL, 나머지 a~l 유지 확인).

### TB-2 — 호출 단위 방어 적용 (bin/herdr-team:1486)
- **구현**: §2.1 예시로 교체(주석 포함). 함수 접두 env의 함수 내부 상속은 실측 완료(§2.1).
- **GREEN**: case m PASS.
- **T2**: `bash tests/test_agent_session.sh && bash tests/test_preset.sh && bash tests/test_pane_ready.sh`
  (기존 27 케이스 회귀 0 포함).

### TB-3 — 스코핑·비회귀 가드 케이스 (tests/test_agent_session.sh, case n/o)
- **RED**: case n(i)은 구현이 "전역 export"였다면 FAIL이 될 가드 — TB-2 직후 작성해 즉시 GREEN 확인.
  case n(ii)/(iii), case o 작성.
- **구현**: 테스트만 (bin은 TB-2에서 완료). n이 FAIL이면 TB-2 구현이 계약 위반(전역 export 등) → 재작업.
- **T2**: `bash tests/test_agent_session.sh && bash scripts/testmap.sh`(매핑 확인 포함).

### TB-4 — session_fail 메시지 진단 힌트 (bin/herdr-team:150)
- **RED**: case b(`tests/test_agent_session.sh:90-98`)에 신규 단언 — stderr에
  `MSYS2_ARG_CONV_EXCL=/api` 힌트 토큰 포함 → 현재 텍스트엔 없어 FAIL.
- **구현**: `agent.err.session_fail` 텍스트 확장(§2.4). 키 추가 아님 → MSG_KEYS/`_msg_en` 키집합 불변.
- **T2**: `bash tests/test_agent_session.sh && bash tests/test_tui_i18n.sh`.

### TB-5 — bat 정적 단언 회귀 잠금 (tests/test_windows_launcher.sh, 신규 §11 부근)
- **RED**: 별도 RED 없음(TB-2 완료 후 잠금용) — 신규 단언 작성 즉시 GREEN 확인.
  (i) bin 방어 토큰 존재, (ii) windows/*.bat 4개에 `MSYS2_ARG_CONV_EXCL`/`MSYS_NO_PATHCONV` 토큰 없음.
- **구현**: 테스트만.
- **T2**: `bash tests/test_windows_launcher.sh` (신규 FAIL 0 — 선존 flake/드리프트 FAIL은 기준 제외, §3.3).

### TB-6 — 최종 회귀 (T3, push 직전 / reviewer 노드 전용)
- `bash scripts/testmap.sh` 전체 + `bash tests/test_preset.sh`(기존 PASS 461 유지) +
  `bash tests/test_agent_session.sh`(기대 PASS 27+신규 3케이스) + `bash tests/test_tui_i18n.sh` +
  `bash tests/test_windows_launcher.sh`(신규 FAIL 0).

---

## 5. 엣지 케이스

1. **WSL 백엔드**: 변환 런타임이 아예 없음 — 접두 env는 Linux bash에서 무해한 미사용 변수(I-P2로 무변경).
2. **opencode가 .cmd 셈인 경우**: 변환은 체인의 네이티브 프로세스(cmd.exe)에서 발생하지만 방어 변수는
   환경으로 상속되므로 동일 적용. Git Bash가 네이티브 exe로 직접 exec하는 경우에도 동일.
3. **사용자가 전역 `MSYS2_ARG_CONV_EXCL`을 이미 설정한 경우**: 이 한 호출에서 `/api`로 덮어써진다(I-P5
   명시 트레이드오프). 다른 호출에는 영향 없음.
4. **dry-run**: exec 없음 — 계획 출력은 무방어 그대로(문자열일 뿐), 테스트 case e 유지.
5. **payload 내부 슬래시**(`location:{directory:$d}`의 `$CWD_HERDR`): 인자 선두가 `{`라 변환 면제(§1.4).
6. **향후 `/api/*` 호출 추가 시**: 접두 `/api`가 함께 커버 — 개별 수정 불필요(접두 매칭 계약).

## 6. 명시적 비범위

- `tests/test_windows_launcher.sh` 선존 flake(printf|grep SIGPIPE) 및 bat 내용 드리프트 FAIL — 수정 금지.
- `bin/herdr-team:516` `/tmp` mktemp 노출 — 현행 유지(§1.4 shortcut 주석).
- opencode operation ID 경로 실증(§2.3) — 열린 질문으로 이관.

## 7. 열린 질문 (PM/후속 확인 대상)

1. opencode 세션 생성 OpenAPI operation ID 실증(기동 서버 필요) — 실증되면 env 방어를 대체 가능한
   근원 회피 후보. 현재는 env 방어가 정본.
2. Windows 실기 검증 — 본 명세의 검증은 stub 기반이므로, 실기에서 `/api/session` 리터럴 도달 확인은
   사용자 보고 또는 reviewer의 E2E 노드 과제로 남긴다.
3. `MSYS2_ARG_CONV_EXCL` 미지원 구버전 Git for Windows(2016년 이전 포크) 지원 여부 — winget 설치본은
   지원. 병용(`MSYS_NO_PATHCONV=1`)은 §2.1에서 기각했으므로 구버전은 미지원으로 문서화.
