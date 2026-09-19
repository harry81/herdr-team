# herdr-team (한국어 가이드)

> **AI 코딩 에이전트를 위한 멀티에이전트 오케스트레이션** — herdr 터미널 멀티플렉서 위에서 planner / worker / reviewer 4-pane 팀을 한 줄 명령으로 띄웁니다.

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-blue)](README.md)
[![Stars](https://img.shields.io/github/stars/harry81/herdr-team?style=social)](https://github.com/harry81/herdr-team/stargazers)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> 기존 `herdr-team-setup` 이름은 100% 호환 레거시 별칭으로 계속 동작합니다.
> English version: [README.md](README.md). 본 문서는 한국어 사용자를 위한 가이드입니다.

## 문제 & 해결책

> **문제** — AI 에이전트 팀을 돌리려면 매번 탭을 만들고, 여러 개의 pane으로 분할하고,
> 에이전트를 하나씩 시작하고, 역할 문서를 손으로 연결해야 합니다.
>
> **해결** — `hts` 한 줄(또는 Windows 더블클릭)이면 터미널이 4분할 AI 팀으로 변합니다.
> task manager가 파이프라인을 중계하므로 planner → worker → reviewer가 기획·구현(TDD)·
> 로그 첨부 검증을 수행하며, 어떤 에이전트도 놀지 않습니다.

## 어떻게 보이나요

```
+----------------+----------------+----------------+----------------+
| ① PM           | ② Planner      | ③ Worker       | ④ Reviewer     |
| 총괄 지휘      | 기획·분할      | 구현 (TDD)     | 검증           |
+----------------+----------------+----------------+----------------+
      \                  |                    |                   /
       └──── 작업 ───────┴────── 코드+테스트 ─────┴── 승인(APPROVE) ┘
```

파이프라인 흐름:

```
User → ① PM → task manager → ② Planner → ③ Worker → ④ Reviewer ─[APPROVE + 실행 로그]→ 보고
                                       ↑______________[REQUEST CHANGES]______________|
```

## 왜 herdr-team인가요?

- **dev — 소프트웨어 개발 TDD:** 코드를 출시하는 개발팀을 위한 — 모든 기능이 planner 설계
  (필요 시 UX/와이어프레임 포함) → worker TDD 구현 → reviewer 실행 로그 첨부 검증(+배포/E2E)으로
  이어지는 품질 게이트.
- **research — 심층 조사·지식 탐색:** 근거 기반으로 조사해야 하는 사용자를 위한 — 질문을 평가축·가설로
  나누고, 출처가 붙은 비교표와 검증된 종합 리포트를 만듭니다.
- **biz — 소상공인 사업 운영:** 코딩 없는 운영자를 위한 — 정부지원사업·정책·사례를 출처와 함께 비교하고
  (행정·CS 매뉴얼·운영 자동화), 직원을 뽑지 않고 결정만 하면 됩니다.
- **mkt — 로컬·SNS 마케팅:** 자영업/1인 마케터를 위한 — 키워드·상권·경쟁 분석과 캠페인 캘린더,
  광고 규정을 지킨 카피·포스팅을 만듭니다.
- **creator — 콘텐츠 창작·출판:** 창작자를 위한 — 목차 → 초안 → 교정 파이프라인(전자책/블로그/뉴스레터)으로,
  worker가 집필하고 reviewer가 팩트체크합니다.

## 30초 빠른 시작

**Windows — 터미널 0회.** GitHub Releases에서 배포 zip(`herdr-team-YYYYMMDD.zip`)을 받아
압축을 풀고 **`start-team.bat`**(및 권한 자동승인용 **`start-watcher.bat`**)을 더블클릭하세요. 메뉴에서 프리셋 선택.
끝입니다. 터미널은 한 번도 안 엽니다.

**Linux / macOS — 한 줄이면 어디서든 `hts`:**

```bash
curl -fsSL https://raw.githubusercontent.com/harry81/herdr-team/main/install.sh | HERDR_TEAM_REPO_URL=https://github.com/harry81/herdr-team.git bash
hts --help
```

(git 선호 시: `git clone https://github.com/harry81/herdr-team ~/work/projects/herdr-team && cd ~/work/projects/herdr-team && ./install.sh` — 결과 동일.)

이어서 Herdr 세션 안의 빈 shell pane에서:

```bash
cd <target-project>
hts                    # prefix 자동 결정, TUI 프리셋 메뉴, 분할+시작
htw &                  # (권장) 백그라운드 Watcher 실행: 셸 권한 팝업 자동 승인 및 멈춤 방지
hts myproj --preset research
hts sd --dry-run       # 실행 없이 계획만 출력
```

## 프리셋 요약

| 프리셋 | 누구를 위한 것인가 | 팀 구성 | 초점 |
|--------|--------------------|---------|------|
| `dev` (기본) | 코드를 출시하는 개발팀 | orchestrator, planner, worker, reviewer | 소프트웨어 개발, TDD 품질 게이트 (+ UX/와이어프레임, 배포/E2E) |
| `research` | 근거 기반 조사가 필요한 사용자 | orchestrator, planner, researcher, reviewer | 심층 조사·지식 탐색, 출처 비교표 + 검증 리포트 |
| `biz` | 코딩 없는 소규모 운영자 | orchestrator, planner, researcher, reviewer | 소상공인 사업 운영: 지원사업·CS 매뉴얼·운영 자동화 (worker 없음) |
| `mkt` | 자영업/1인 마케터 | orchestrator, planner, researcher, reviewer | 로컬·SNS 마케팅, 키워드·경쟁 분석, 규정 준수 카피 |
| `creator` | 창작자·출판 | orchestrator, planner, worker, reviewer | 콘텐츠 창작·출판, 목차 → 초안 → 교정 |

> `app`은 `dev`에 흡수되었습니다. `--preset app`은 계속 동작하지만 deprecated alias(경고)입니다.

<details>
<summary><b>고급 — 전체 참고 자료 (저장소 구조, 동작 순서, TUI, 프리셋, Windows, CLI 옵션, 요구사항, 팀 모델, 테스트)</b></summary>

## 고급 / 참고 자료

아래는 전부 참고용 부록입니다. 위 30초 시작에는 필요 없습니다.

### 저장소 구조

```
herdr-team/
├── bin/
│   ├── herdr-team        # 본 스크립트 (실행 파일, 정본)
│   ├── herdr-watcher     # 팀 워처 스크립트 (셸 권한 팝업 자동 승인, htw)
│   └── herdr-team-setup  # 레거시 래퍼 (100% 호환, herdr-team으로 전달)
├── windows/
│   ├── start-team.bat          # Windows 팀 원클릭 런처 (더블클릭 실행)
│   ├── start-watcher.bat       # Windows 워처 원클릭 런처 (더블클릭 실행)
│   └── create-shortcut.bat     # 바탕화면 바로가기 생성기 ("Start AI Team")
├── start-team.bat              # 루트 래퍼 → windows\start-team.bat
├── start-watcher.bat           # 루트 래퍼 → windows\start-watcher.bat
├── scripts/
│   └── build-zip.sh            # 배포 아카이브 생성 (기본: herdr-team-<날짜>.zip)
├── templates/
│   ├── AGENTS.md               # {{PREFIX}} 템플릿화된 팀 오케스트레이션 정본
│   ├── agents/
│   │   ├── ROLE-orchestrator.md # {{PREFIX}}-orchestrator 역할 템플릿 (파이프라인 중계)
│   │   ├── ROLE-planner.md     # {{PREFIX}}-planner 역할 템플릿
│   │   ├── ROLE-worker.md      # {{PREFIX}}-worker 역할 템플릿
│   │   ├── ROLE-reviewer.md    # {{PREFIX}}-reviewer 역할 템플릿
│   │   └── ROLE-researcher.md  # {{PREFIX}}-researcher 역할 템플릿 (research/biz/mkt 프리셋)
│   ├── opencode-agents/        # opencode primary agent 정의 (--agent <prefix>-<role>, 권한 강제)
│   │   ├── ROLE-orchestrator.md
│   │   ├── ROLE-planner.md
│   │   ├── ROLE-worker.md
│   │   ├── ROLE-reviewer.md
│   │   └── ROLE-researcher.md
│   ├── dev/                    # 프리셋: 개발 4인 팀
│   ├── research/               # 프리셋: 심층 조사·지식 탐색
│   ├── biz/                    # 프리셋: 소상공인 사업 운영
│   ├── mkt/                    # 프리셋: 로컬·SNS 마케팅
│   └── creator/                # 프리셋: 콘텐츠 창작·출판
├── tests/
│   ├── test_preset.sh          # 프리셋 + TUI 테스트 (정본 + 레거시 래퍼)
│   ├── test_install.sh         # 설치 + 배포 zip 테스트
│   └── test_windows_launcher.sh# Windows 런처 테스트
├── install.sh                  # ~/bin + ~/templates 심볼릭 링크 설치
├── LICENSE                     # MIT 라이선스
├── README.md                   # 영문 기본 문서 (Primary)
└── README.ko.md                # 본 문서 (한국어 가이드)
```

### 동작 순서

1. **prefix 결정** — `$1` 우선, 없으면 git root 디렉토리명(없으면 폴더명)에서 자동 추출.
   `try2`→`try2`, `my-project`→`mp`, `scandimension`→`sc` 형태의 2~4글자 축약 또는 폴더명 그대로.
2. **프리셋 결정** — `--preset dev|research|biz|mkt|creator`, 환경변수 `HERDR_TEAM_PRESET`, 또는 TUI 메뉴 (기본값: `dev`). `app`은 `dev`의 deprecated alias입니다.
3. **템플릿 준비 & 격리** — 프리셋별 정본은 `agents/<preset>/`(`AGENTS.md`·`<prefix>-<role>.md`)에,
   활성 프리셋은 `.herdr-team/preset`에 기록됩니다. 루트 `AGENTS.md`는 활성 뷰로, 전환 시 루트 수정분을
   나가는 프리셋 정본에 write-back한 뒤 들어오는 정본을 루트로 복사합니다.
   opencode 역할 agent는 `.opencode/agents/<prefix>-*.md`로 재생성(비활성 role은 prune, 같은 프리셋 재실행은 편집 보존).
4. **Pane 분할 및 레이아웃** — 기본 레이아웃은 `2col`:
   - 좌측 열: [PM (상단 50%)] / [Task Manager (하단 50%)]
   - 우측 열: [Role 2 (상단)] / [Role 3 (중단)] / [Role 4 (하단)]
   (기존 단일 우측 스택을 원할 경우 `--layout right-stack` 사용).
5. **균등화** — 각 down 분할 시 `--ratio 1/(N-k+1)` (및 PM/TM 0.5)을 전달하므로 별도 resize 없이 정확히 균등해집니다.
6. **레이블 + 시작** — ① PM / ② Task Manager / ③④⑤ 역할 로 변경 후
   `herdr agent start <prefix>-<role> --kind opencode -- --agent <prefix>-<role>`
   (opencode 역할 강제; 이미 있으면 생략).

`install.sh`는 아래 심볼릭 링크를 만들고,
`~/.bashrc`·`~/.zshrc`에 `~/bin` PATH 등록을 수행합니다 (marker 주석, 멱등):

```bash
~/bin/herdr-team       -> <repo>/bin/herdr-team
~/bin/ht               -> <repo>/bin/herdr-team
~/bin/hts              -> <repo>/bin/herdr-team
~/bin/herdr-team-setup -> <repo>/bin/herdr-team   # 레거시 별칭
~/bin/herdr-watcher    -> <repo>/bin/herdr-watcher
~/bin/htw              -> <repo>/bin/herdr-watcher # watcher 별칭
~/templates/agent-team -> <repo>/templates
```

> `~/bin`이 `PATH`에 있어야 터미널 어디서든 `herdr-team`으로 실행할 수 있습니다.

### 프리셋 격리 & 무손실 전환

역할 문서는 **대상 프로젝트** 안에서 프리셋별로 격리되어, 프리셋 전환이 다른 프리셋의 문서를 덮어쓰지 않습니다:

```
<대상 프로젝트>/
├── AGENTS.md                     # 활성 뷰 (활성 프리셋 정본의 동기화 사본)
├── .herdr-team/preset            # 활성 canonical preset 1줄 (예: mkt)
├── agents/
│   ├── dev/                      # 프리셋별 정본 (AGENTS.md + <prefix>-<role>.md)
│   ├── mkt/                      # 프리셋별 정본
│   └── <prefix>-<role>.md        # 레거시 평면 문서 (복사 import, 원본 불변)
└── .opencode/agents/             # 생성물: 활성 ROLES만
```

- **전환(dev → mkt)**: 루트 `AGENTS.md` 수정분을 `agents/dev/AGENTS.md`로 write-back(무손실)한 뒤,
  `agents/mkt/AGENTS.md`를 루트로 복사합니다. 되돌리면 dev가 복원됩니다.
- **마이그레이션**: 기존 평면 `agents/<prefix>-<role>.md`는 `agents/<preset>/`로 복사 import(원본 불변).
  공존 시 `agents/<preset>/` 우선. herdr-team 저장소 자신도 안전합니다.
- **`--force`**: 요청한 프리셋 폴더만 템플릿에서 재시딩 + 루트 강제 활성. 다른 프리셋은 불가침.
- **`--dry-run`**: 격리 계획만 출력하고 아무것도 쓰지 않습니다(문서·상태 미변경).

### TUI 인터랙티브 메뉴

`--preset` 지정이 없으면(환경변수·`--no-interactive`도 없을 때) 프리셋 메뉴가 표시됩니다. 영어 기본 + 한국어 병기:

```
Select AI team preset (1-5 or name, default: dev):
  1) dev - Software Development (소프트웨어 개발·MVP, 4인 팀, orchestrator/planner/worker/reviewer)
  2) research - Deep Research & Knowledge Discovery (...)
  3) biz - Small Business Operations (소상공인 사업 운영, ...)
  4) mkt - Local & SNS Marketing (로컬·SNS 마케팅, ...)
  5) creator - Content Creation & Publishing (콘텐츠 창작·출판, ...)
Select [1-5/dev/research/biz/mkt/creator] (default: dev, 10s):
```

참고:

- 블로킹 없음: EOF·타임아웃·파이프 입력이면 `dev`로 진행 (자동화 안전).
- `--no-interactive`는 묻지 않고 `dev`로 진행.
- `--list-presets`는 프리셋 목록 출력 후 종료.

### 프리셋 (dev, research, biz, mkt, creator)

| 프리셋 | 역할 | 용도 |
|--------|------|------|
| `dev` (기본) | orchestrator, planner, worker, reviewer | 개발 4인 팀, TDD (+ UX/와이어프레임, 배포/E2E) |
| `research` | orchestrator, planner, researcher, reviewer | 심층 조사·지식 탐색, 출처 비교표 + 검증 리포트 |
| `biz` | orchestrator, planner, researcher, reviewer | 소상공인 사업 운영: 지원사업·CS·운영 자동화 (worker 없음) |
| `mkt` | orchestrator, planner, researcher, reviewer | 로컬·SNS 마케팅, 키워드·경쟁 분석, 규정 준수 카피 (worker on-demand) |
| `creator` | orchestrator, planner, worker, reviewer | 콘텐츠 창작·출판, 목차 → 초안 → 교정 (researcher on-demand) |

각 프리셋은 `templates/<preset>/` (`preset.conf` + `AGENTS.md`)에 정의됩니다.
역할은 일반화되어 있어 프리셋의 `ROLES`에서 에이전트명(`<prefix>-<role>`)을 도출하므로,
새 프리셋 추가는 디렉토리 추가만으로 가능합니다 (새 역할이면 `ROLE-<role>.md`도 함께).
프리셋은 `--template-dir`와 번들 `templates/`에서 동적으로 발견되므로, 사용자 `<name>/preset.conf`를
추가하면 `--list-presets`와 TUI에 자동 노출됩니다. `app`은 `dev`의 deprecated alias로 예약되어 있습니다.

### Windows 원클릭 상세

Windows 일반 사용자용 — 더블클릭만으로 실행, 터미널 지식 불필요:

1. 저장소 루트(또는 배포 zip)의 **`start-team.bat`** 더블클릭.
2. 백그라운드 워처 실행을 원할 시 **`start-watcher.bat`** 더블클릭 (권장: 셸 실행 승인 팝업 자동 처리).
3. 메뉴에서 프리셋 선택 (영어 기본 + 한국어 병기, 10초 무입력 시 dev).
4. `windows\create-shortcut.bat` 실행 시 바탕화면 바로가기("Start AI Team") 생성.

런처는 WSL(없으면 Git-Bash) 경유로 저장소 스크립트를 실행하며,
`wsl wslpath`로 경로 변환, 모든 인자(`--preset`, `--dry-run` 등)를 그대로 전달합니다.
부작용 없는 시뮬레이션: `HERDR_TEAM_DRYRUN=1`.
마지막 pause 생략(자동화): `HERDR_TEAM_NOPAUSE=1`.
Git/WSL이 없으면 `winget install --id Git.Git`·`wsl --install` 안내가 뜹니다
(`HERDR_TEAM_SKIP_CHECK=1`로 점검 생략 가능).

### CLI 옵션표

| 옵션 | 설명 |
|------|------|
| `prefix` | 에이전트 prefix (예: `sd`, `myproj`), 생략 시 자동 결정 |
| `--kind KIND` | agent kind (기본값: `opencode` / TUI 메뉴; 지원: `opencode`, `claude`, `codex`, `agy` 등, 또는 `HERDR_TEAM_KIND`) |
| `--layout LAYOUT` | 팀 pane 레이아웃: `2col` (기본값, PM 하단에 TM) \| `right-stack` (또는 `HERDR_TEAM_LAYOUT`) |
| `--cwd PATH` | 작업 디렉토리 (기본값: `$PWD`) |
| `--template-dir D` | 템플릿 디렉토리 (기본값: `~/templates/agent-team`, 또는 `HERDR_TEAM_TEMPLATE_DIR`) |
| `--preset NAME` | 팀 프리셋: `dev` \| `research` \| `biz` \| `mkt` \| `creator` (`app` = `dev`의 deprecated alias, 또는 `HERDR_TEAM_PRESET`, 기본값: `dev` / TUI) |
| `--list-presets` | 프리셋 목록 출력 후 종료 |
| `--no-interactive` | 묻지 않고 기본값으로 진행 (`preset=dev`, `kind=opencode`) |
| `--no-template` | 템플릿 복사/생성 생략 |
| `--no-resize` | `--ratio` 균등화 없이 분할 (별도 resize 단계 없음) |
| `--no-start` | 에이전트 시작 생략 (분할+레이블만 수행) |
| `--force` | 요청한 프리셋 폴더(`agents/<preset>/`)만 템플릿에서 재시딩 + 루트 강제 활성 (타 프리셋 불가침) |
| `--dry-run` | 실제 실행 없이 수행할 명령만 출력 |
| `-h, --help` | 도움말 |

### 요구사항

- `herdr` CLI (Herdr 세션 안에서 실행)
- `jq` (pane ID 파싱용 — `herdr pane current/split`의 JSON 응답 해석)
- Windows 런처: WSL (권장) 또는 Git-Bash

### 팀 모델 (task manager + 3역할)

```
User → PM(agy) → task manager → planner → worker → reviewer ─[APPROVE + 실행 로그]→ 보고
                                             ↑________[REQUEST CHANGES]________|
```

- task manager가 순차 파이프라인을 중계(코드 수정 금지). PM은 사용자 소통·상위 목표 수립만.
- 수정 권한은 worker만. reviewer는 정적 리뷰 + 빌드/단위/통합·E2E·회귀 직접 실행 후 판정만.
- on-demand: researcher(조사), ops(배포·인프라) — PM이 필요 시 기동.
- 상세 규율은 템플릿 `AGENTS.md` + 역할 문서를 참조.

### 테스트

```bash
bash tests/test_preset.sh            # 프리셋 + TUI (정본 + 레거시 래퍼)
bash tests/test_install.sh           # 설치 + 배포 zip
bash tests/test_windows_launcher.sh  # 런처 구조 + 전달 명령 시뮬레이션
```

</details>

## 라이선스

MIT License — [LICENSE](LICENSE) 참조.
Copyright (c) 2026 Herdr Team Contributors.
누구나 자유롭게 사용·수정·배포할 수 있습니다.
