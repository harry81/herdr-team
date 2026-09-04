# herdr-team-setup

Herdr 기반 3인 에이전트 팀(PM + planner / worker / reviewer)을 **어떤 프로젝트에서든 원클릭으로 구성**하는 범용 셋업 스크립트 저장소입니다.

## 구성

```
herdr-team-setup/
├── bin/
│   └── herdr-team-setup        # 본 스크립트 (실행 파일)
├── templates/
│   ├── AGENTS.md               # {{PREFIX}} 템플릿화된 팀 오케스트레이션 정본
│   └── agents/
│       ├── ROLE-planner.md     # {{PREFIX}}-planner 역할 템플릿
│       ├── ROLE-worker.md      # {{PREFIX}}-worker 역할 템플릿
│       └── ROLE-reviewer.md    # {{PREFIX}}-reviewer 역할 템플릿
├── install.sh                  # ~/bin + ~/templates 심볼릭 링크 설치
└── README.md
```

## 설치

```bash
git clone <this-repo> ~/work/projects/herdr-team-setup
cd ~/work/projects/herdr-team-setup
./install.sh
```

`install.sh`는 아래 두 심볼릭 링크를 생성합니다.

```bash
~/bin/herdr-team-setup     -> <repo>/bin/herdr-team-setup
~/templates/agent-team     -> <repo>/templates
```

수동 설치 시:

```bash
ln -s "$PWD/bin/herdr-team-setup" ~/bin/herdr-team-setup
ln -s "$PWD/templates" ~/templates/agent-team
```

> `~/bin`이 `PATH`에 있어야 터미널 어디서든 `herdr-team-setup`으로 실행할 수 있습니다.

## 사용법

```bash
# Herdr 세션 안의 빈 shell pane에서 실행
cd <target-project>

herdr-team-setup               # 폴더명 기반 prefix 자동 결정
herdr-team-setup myproj        # prefix 강제 지정
herdr-team-setup sd --dry-run  # 실행 없이 계획만 출력
```

동작 순서:

1. **prefix 결정** — `$1` 우선, 없으면 git root 디렉토리명(없으면 폴더명)에서 자동 추출.
   `try2`→`try2`, `my-project`→`mp`, `scandimension`→`sc` 형태의 2~4글자 축약 또는 폴더명 그대로.
2. **템플릿 준비** — `AGENTS.md`·`agents/<prefix>-*.md`가 없으면 `~/templates/agent-team`에서 복사
   (파일 내 `{{PREFIX}}` 치환). 템플릿 디렉토리가 없으면 내장 최소 문서 생성. 이미 있으면 생략(멱등).
3. **Pane 분할** — 현재 Pane(PM) 기준 우측 분할(Planner) → 아래로 2분할(Worker, Reviewer).
4. **균등화** — `herdr pane resize`로 우측 3 Pane 높이 약 1:1:1 조정 (best-effort).
5. **레이블 + 시작** — `① PM` / `② Planner` / `③ Worker` / `④ Reviewer`로 변경 후
   `herdr agent start <prefix>-{planner,worker,reviewer} --kind opencode` (이미 있으면 생략).

## 커맨드 옵션

```
herdr-team-setup [prefix] [options]

  --kind KIND       agent kind (기본값: opencode)
  --cwd PATH        작업 디렉토리 (기본값: $PWD)
  --template-dir D  템플릿 디렉토리 (기본값: ~/templates/agent-team,
                    환경변수 HERDR_TEAM_TEMPLATE_DIR로도 지정 가능)
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

## 팀 모델 (3인 체제)

```
User → PM(agy) → planner → worker → reviewer ─[APPROVE + 실행 로그]→ 보고
                              ↑____[REQUEST CHANGES]____|
```

- 수정 권한은 worker만. reviewer는 정적 리뷰 + 빌드/단위/통합·E2E·회귀 직접 실행 후 판정만.
- on-demand: researcher(조사), ops(배포·인프라) — PM이 필요 시 기동.
- 상세 규율은 템플릿 `AGENTS.md` + 역할 문서를 참조.
