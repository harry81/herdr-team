# herdr-team (한국어 가이드)

어떤 프로젝트에서든 Herdr 기반 3인 에이전트 팀(PM + planner / worker / reviewer)을 **원클릭으로 구성**하는 셋업 스크립트 저장소입니다.

> 기존 `herdr-team-setup` 이름은 100% 호환 레거시 별칭으로 계속 동작합니다.
> 영문 기본 문서는 [README.md](README.md) 참조. 본 문서는 한국어 사용자를 위한 상세 가이드입니다.

## 구성

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

## 설치

```bash
git clone <this-repo> ~/work/projects/herdr-team
cd ~/work/projects/herdr-team
./install.sh
```

`install.sh`는 아래 심볼릭 링크를 생성합니다.

```bash
~/bin/herdr-team       -> <repo>/bin/herdr-team
~/bin/ht               -> <repo>/bin/herdr-team
~/bin/hts              -> <repo>/bin/herdr-team
~/bin/herdr-team-setup -> <repo>/bin/herdr-team   # 레거시 별칭
~/templates/agent-team -> <repo>/templates
```

수동 설치 시:

```bash
ln -s "$PWD/bin/herdr-team" ~/bin/herdr-team
ln -s "$PWD/bin/herdr-team" ~/bin/ht
ln -s "$PWD/bin/herdr-team" ~/bin/hts
ln -s "$PWD/bin/herdr-team" ~/bin/herdr-team-setup
ln -s "$PWD/templates" ~/templates/agent-team
```

> `~/bin`이 `PATH`에 있어야 터미널 어디서든 `herdr-team`으로 실행할 수 있습니다.

## 사용법

```bash
# Herdr 세션 안의 빈 shell pane에서 실행
cd <target-project>

herdr-team               # 폴더명 기반 prefix 자동 결정
herdr-team myproj        # prefix 강제 지정
herdr-team sd --dry-run  # 실행 없이 계획만 출력
```

동작 순서:

1. **prefix 결정** — `$1` 우선, 없으면 git root 디렉토리명(없으면 폴더명)에서 자동 추출.
   `try2`→`try2`, `my-project`→`mp`, `scandimension`→`sc` 형태의 2~4글자 축약 또는 폴더명 그대로.
2. **프리셋 결정** — `--preset dev|app|biz`, 환경변수 `HERDR_TEAM_PRESET`, 또는 TUI 메뉴 (기본값: `dev`).
3. **템플릿 준비** — `AGENTS.md`·`agents/<prefix>-*.md`가 없으면 `~/templates/agent-team`에서 복사
   (파일 내 `{{PREFIX}}` 치환). 이미 있으면 생략(멱등).
4. **Pane 분할** — 현재 Pane(PM) 기준 우측 분할(역할 1) → 아래로 2분할(역할 2·3).
5. **균등화** — `herdr pane resize`로 우측 3 Pane 높이 약 1:1:1 조정 (best-effort).
6. **레이블 + 시작** — ① PM / ② / ③ / ④ 로 변경 후
   `herdr agent start <prefix>-<role> --kind opencode` (이미 있으면 생략).

## TUI 인터랙티브 메뉴

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

## 프리셋 (dev, app, biz)

| 프리셋 | 역할 | 용도 |
|--------|------|------|
| `dev` (기본) | planner, worker, reviewer | 개발 3인 팀, TDD 개발용 |
| `app` | planner, worker, reviewer | 1인 앱/아이템 발굴, 배포·E2E 강조 |
| `biz` | planner, researcher, reviewer | 스몰 비즈니스 운영, 조사 중심 (worker 없음) |

각 프리셋은 `templates/<preset>/` (`preset.conf` + `AGENTS.md`)에 정의됩니다.
역할은 일반화되어 있어 프리셋의 `ROLES`에서 에이전트명(`<prefix>-<role>`)을 도출하므로,
새 프리셋 추가는 디렉토리 추가만으로 가능합니다 (새 역할이면 `ROLE-<role>.md`도 함께).

## Windows 원클릭 실행

Windows 일반 사용자용 — 더블클릭만으로 실행, 터미널 지식 불필요:

1. 저장소 루트의 **`start-team.bat`** 더블클릭.
2. 메뉴에서 프리셋 선택 (영어 기본 + 한국어 병기, 10초 무입력 시 dev).
3. `windows\create-shortcut.bat` 실행 시 바탕화면 바로가기("Start AI Team") 생성.

런처는 WSL(없으면 Git-Bash) 경유로 저장소 스크립트를 실행하며,
`wsl wslpath`로 경로 변환, 모든 인자(`--preset`, `--dry-run` 등)를 그대로 전달합니다.
부작용 없는 시뮬레이션: `HERDR_TEAM_DRYRUN=1`.
마지막 pause 생략(자동화): `HERDR_TEAM_NOPAUSE=1`.

## 커맨드 옵션

```
herdr-team [prefix] [options]

  --kind KIND       agent kind (기본값: opencode)
  --cwd PATH        작업 디렉토리 (기본값: $PWD)
  --template-dir D  템플릿 디렉토리 (기본값: ~/templates/agent-team,
                    환경변수 HERDR_TEAM_TEMPLATE_DIR로도 지정 가능)
  --preset NAME     팀 프리셋: dev | app | biz
                    (또는 HERDR_TEAM_PRESET, 기본값: dev / TUI 선택)
  --list-presets    프리셋 목록 출력 후 종료
  --no-interactive  묻지 않고 진행 (preset=dev)
  --no-template     템플릿 복사/생성 생략
  --no-resize       pane resize 생략
  --no-start        에이전트 시작 생략 (분할+레이블만 수행)
  --force           기존 AGENTS.md/agents 문서 덮어쓰기
  --dry-run         실제 실행 없이 수행할 명령만 출력
  -h, --help        도움말
```

## 요구사항

- `herdr` CLI (Herdr 세션 안에서 실행)
- `jq` (pane ID 파싱용 — `herdr pane current/split`의 JSON 응답 해석)
- Windows 런처: WSL (권장) 또는 Git-Bash

## 팀 모델 (3인 체제)

```
User → PM(agy) → planner → worker → reviewer ─[APPROVE + 실행 로그]→ 보고
                               ↑____[REQUEST CHANGES]____|
```

- 수정 권한은 worker만. reviewer는 정적 리뷰 + 빌드/단위/통합·E2E·회귀 직접 실행 후 판정만.
- on-demand: researcher(조사), ops(배포·인프라) — PM이 필요 시 기동.
- 상세 규율은 템플릿 `AGENTS.md` + 역할 문서를 참조.

## 테스트

```bash
bash tests/test_preset.sh            # 프리셋 + TUI (영문 기준 assertion 포함)
bash tests/test_windows_launcher.sh  # 런처 구조 + 전달 명령 시뮬레이션
```

## 라이선스

MIT License — [LICENSE](LICENSE) 참조.
Copyright (c) 2026 Herdr Team Setup Contributors.
누구나 자유롭게 사용·수정·배포할 수 있습니다.
