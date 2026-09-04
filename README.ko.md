# herdr-team (한국어 가이드)

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-blue)](README.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Stars](https://img.shields.io/github/stars/harry81/herdr-team?style=social)](https://github.com/harry81/herdr-team/stargazers)

**명령어 하나로 터미널이 4분할 AI 팀으로 변합니다. 기획·구현·검증까지 알아서 분업 — 프리셋을 고르고 더블클릭하거나 `hts` 한 줄이면 끝.**

```
+----------------+----------------+----------------+----------------+
| ① PM           | ② Planner      | ③ Worker       | ④ Reviewer     |
| 총괄 지휘      | 기획·분할      | 구현 (TDD)     | 검증           |
+----------------+----------------+----------------+----------------+
      \                  |                    |                   /
       └──── 작업 ───────┴────── 코드+테스트 ─────┴── 승인(APPROVE) ┘
```

> 기존 `herdr-team-setup` 이름은 100% 호환 레거시 별칭으로 계속 동작합니다.
> English version: [README.md](README.md). 본 문서는 한국어 사용자를 위한 가이드입니다.

## 왜 herdr-team인가요?

- **app — 1인 앱 개발 & 아이템 발굴.**
  주말 사이드 프로젝트? 한 줄 아이디어를 planner가 만들 수 있는 작업으로 나누고,
  worker가 테스트 딸린 코드로 배송하고, reviewer가 배포·E2E 점검까지 —
  당신은 프리셋 메뉴에서 고르고 세 개 창이 일하는 것만 보면 됩니다.
- **biz — 스몰 비즈니스 운용.**
  코딩 없이 씁니다. researcher가 출처 딸린 견적·업체·옵션 비교를 뽑고,
  planner가 의사결정 구조를 잡고, reviewer가 검증합니다.
  직원을 뽑지 않고도 조사 중심 팀워크를 돌릴 수 있습니다.
- **dev — 소프트웨어 개발 TDD (개발 3인 팀).**
  모든 기능이 planner → worker(Red→Green→Refactor) → reviewer
  (빌드/단위/E2E 직접 실행, 로그 첨부) 순서로 갑니다.
  실행 로그 없는 `[APPROVE]`는 무효 — 품질 게이트가 워크플로에 내장되어 있습니다.

## 30초 빠른 시작

**Windows — 터미널 0회.** GitHub Releases에서 `herdr-team.zip`을 받아
압축을 풀고 **`start-team.bat`**을 더블클릭하세요. 메뉴에서 프리셋 선택.
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
hts myproj --preset app
hts sd --dry-run       # 실행 없이 계획만 출력
```

## 고급 / 참고 자료

아래는 전부 참고용 부록입니다. 위 30초 시작에는 필요 없습니다.

### 저장소 구조

```
herdr-team/
├── bin/
│   ├── herdr-team        # 본 스크립트 (실행 파일, 정본)
│   └── herdr-team-setup  # 레거시 래퍼 (100% 호환, herdr-team으로 전달)
├── windows/
│   ├── start-team.bat          # Windows 원클릭 런처 (더블클릭 실행)
│   └── create-shortcut.bat     # 바탕화면 바로가기 생성기 ("Start AI Team")
├── start-team.bat              # 루트 래퍼 → windows\start-team.bat
├── scripts/
│   └── build-zip.sh            # 배포 아카이브 생성 (기본: herdr-team-<날짜>.zip)
├── templates/
│   ├── AGENTS.md               # {{PREFIX}} 템플릿화된 팀 오케스트레이션 정본
│   ├── agents/
│   │   ├── ROLE-planner.md     # {{PREFIX}}-planner 역할 템플릿
│   │   ├── ROLE-worker.md      # {{PREFIX}}-worker 역할 템플릿
│   │   ├── ROLE-reviewer.md    # {{PREFIX}}-reviewer 역할 템플릿
│   │   └── ROLE-researcher.md  # {{PREFIX}}-researcher 역할 템플릿 (biz 프리셋)
│   ├── dev/                    # 프리셋: 개발 3인 팀
│   ├── app/                    # 프리셋: 1인 앱/아이템 발굴
│   └── biz/                    # 프리셋: 스몰 비즈니스 운영
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
2. **프리셋 결정** — `--preset dev|app|biz`, 환경변수 `HERDR_TEAM_PRESET`, 또는 TUI 메뉴 (기본값: `dev`).
3. **템플릿 준비** — `AGENTS.md`·`agents/<prefix>-*.md`가 없으면 `~/templates/agent-team`에서 복사
   (파일 내 `{{PREFIX}}` 치환). 이미 있으면 생략(멱등).
4. **Pane 분할** — 현재 Pane(PM) 기준 우측 분할(역할 1) → 아래로 2분할(역할 2·3).
5. **균등화** — `herdr pane resize`로 우측 3 Pane 높이 약 1:1:1 조정 (best-effort).
6. **레이블 + 시작** — ① PM / ② / ③ / ④ 로 변경 후
   `herdr agent start <prefix>-<role> --kind opencode` (이미 있으면 생략).

`install.sh`는 아래 심볼릭 링크를 만들고,
`~/.bashrc`·`~/.zshrc`에 `~/bin` PATH 등록을 수행합니다 (marker 주석, 멱등):

```bash
~/bin/herdr-team       -> <repo>/bin/herdr-team
~/bin/ht               -> <repo>/bin/herdr-team
~/bin/hts              -> <repo>/bin/herdr-team
~/bin/herdr-team-setup -> <repo>/bin/herdr-team   # 레거시 별칭
~/templates/agent-team -> <repo>/templates
```

> `~/bin`이 `PATH`에 있어야 터미널 어디서든 `herdr-team`으로 실행할 수 있습니다.

### TUI 인터랙티브 메뉴

`--preset` 지정이 없으면(환경변수·`--no-interactive`도 없을 때) 프리셋 메뉴가 표시됩니다. 영어 기본 + 한국어 병기:

```
Select AI team preset (1-3 or name, default: dev):
  1) dev - Software Development (개발 3인 팀, 기본값)
  2) app - Solo App & Idea Discovery (1인 앱/아이템)
  3) biz - Small Business Operations (스몰 비즈니스)
Select [1-3/dev/app/biz] (default: dev, 10s):
```

참고:

- 블로킹 없음: EOF·타임아웃·파이프 입력이면 `dev`로 진행 (자동화 안전).
- `--no-interactive`는 묻지 않고 `dev`로 진행.
- `--list-presets`는 프리셋 목록 출력 후 종료.

### 프리셋 (dev, app, biz)

| 프리셋 | 역할 | 용도 |
|--------|------|------|
| `dev` (기본) | planner, worker, reviewer | 개발 3인 팀, TDD 개발용 |
| `app` | planner, worker, reviewer | 1인 앱/아이템 발굴, 배포·E2E 강조 |
| `biz` | planner, researcher, reviewer | 스몰 비즈니스 운영, 조사 중심 (worker 없음) |

각 프리셋은 `templates/<preset>/` (`preset.conf` + `AGENTS.md`)에 정의됩니다.
역할은 일반화되어 있어 프리셋의 `ROLES`에서 에이전트명(`<prefix>-<role>`)을 도출하므로,
새 프리셋 추가는 디렉토리 추가만으로 가능합니다 (새 역할이면 `ROLE-<role>.md`도 함께).

### Windows 원클릭 상세

Windows 일반 사용자용 — 더블클릭만으로 실행, 터미널 지식 불필요:

1. 저장소 루트(또는 배포 zip)의 **`start-team.bat`** 더블클릭.
2. 메뉴에서 프리셋 선택 (영어 기본 + 한국어 병기, 10초 무입력 시 dev).
3. `windows\create-shortcut.bat` 실행 시 바탕화면 바로가기("Start AI Team") 생성.

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
| `--kind KIND` | agent kind (기본값: `opencode`) |
| `--cwd PATH` | 작업 디렉토리 (기본값: `$PWD`) |
| `--template-dir D` | 템플릿 디렉토리 (기본값: `~/templates/agent-team`, 또는 `HERDR_TEAM_TEMPLATE_DIR`) |
| `--preset NAME` | 팀 프리셋: `dev` \| `app` \| `biz` (또는 `HERDR_TEAM_PRESET`, 기본값: `dev` / TUI) |
| `--list-presets` | 프리셋 목록 출력 후 종료 |
| `--no-interactive` | 묻지 않고 진행 (`preset=dev`) |
| `--no-template` | 템플릿 복사/생성 생략 |
| `--no-resize` | pane resize 생략 |
| `--no-start` | 에이전트 시작 생략 (분할+레이블만 수행) |
| `--force` | 기존 `AGENTS.md`/agents 문서 덮어쓰기 |
| `--dry-run` | 실제 실행 없이 수행할 명령만 출력 |
| `-h, --help` | 도움말 |

### 요구사항

- `herdr` CLI (Herdr 세션 안에서 실행)
- `jq` (pane ID 파싱용 — `herdr pane current/split`의 JSON 응답 해석)
- Windows 런처: WSL (권장) 또는 Git-Bash

### 팀 모델 (3인 체제)

```
User → PM(agy) → planner → worker → reviewer ─[APPROVE + 실행 로그]→ 보고
                               ↑____[REQUEST CHANGES]____|
```

- 수정 권한은 worker만. reviewer는 정적 리뷰 + 빌드/단위/통합·E2E·회귀 직접 실행 후 판정만.
- on-demand: researcher(조사), ops(배포·인프라) — PM이 필요 시 기동.
- 상세 규율은 템플릿 `AGENTS.md` + 역할 문서를 참조.

### 테스트

```bash
bash tests/test_preset.sh            # 프리셋 + TUI (정본 + 레거시 래퍼)
bash tests/test_install.sh           # 설치 + 배포 zip
bash tests/test_windows_launcher.sh  # 런처 구조 + 전달 명령 시뮬레이션
```

### 라이선스

MIT License — [LICENSE](LICENSE) 참조.
Copyright (c) 2026 Herdr Team Contributors.
누구나 자유롭게 사용·수정·배포할 수 있습니다.
