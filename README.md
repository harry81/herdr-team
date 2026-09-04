# herdr-team

**One command turns your terminal into a 4-pane AI crew that plans, builds, and gate-checks every change — pick a preset, double-click or type `hts`, done.**

```
+----------------+----------------+----------------+----------------+
| ① PM           | ② Planner      | ③ Worker       | ④ Reviewer     |
| orchestrates   | plans & splits | builds (TDD)   | verifies       |
+----------------+----------------+----------------+----------------+
      \                  |                    |                   /
       └──── tasks ──────┴────── code + tests ─────┴── APPROVE ──┘
```

> Formerly `herdr-team-setup` — that name still works as a fully compatible legacy alias.
> 한국어 가이드는 [README.ko.md](README.ko.md) 참조.

## Why herdr-team?

- **app — Solo App & Idea Discovery (1인 앱/아이템).**
  Weekend side project? The planner turns your one-line idea into buildable tasks,
  the worker ships code with tests, and the reviewer runs deploy/E2E checks —
  you just answer the preset menu and watch three panes work.
- **biz — Small Business Operations (스몰 비즈니스).**
  No code required. The researcher compares vendors, prices, and options with
  sources attached, the planner structures the decision, and the reviewer
  validates it. Research-first teamwork without hiring anyone.
- **dev — Software Development, TDD (개발 3인 팀).**
  Every feature goes planner → worker (Red→Green→Refactor) → reviewer
  (build/unit/E2E executed, log attached). `[APPROVE]` only counts with
  execution logs — quality gate built into the workflow.

## Quick Start

**Windows — zero terminal.** Download `herdr-team.zip` from GitHub Releases,
unzip, and double-click **`start-team.bat`**. Pick a preset from the menu.
That's it — no terminal opened, ever.

**Linux / macOS — one line, then `hts` works everywhere:**

```bash
curl -fsSL <this-repo>/install.sh | HERDR_TEAM_REPO_URL=<this-repo>.git bash
hts --help
```

(Prefer git? `git clone <this-repo> ~/work/projects/herdr-team && cd ~/work/projects/herdr-team && ./install.sh` — same result.)

Then, inside an empty shell pane of a Herdr session:

```bash
cd <target-project>
hts                    # auto-detect prefix, TUI preset menu, split + start
hts myproj --preset app
hts sd --dry-run       # print plan only, no changes
```

## Advanced

Everything below is reference material. You never need it for the 30-second start above.

### Repository layout

```
herdr-team/
├── bin/
│   ├── herdr-team        # Main script (executable, canonical)
│   └── herdr-team-setup  # Legacy wrapper (100% compatible, forwards to herdr-team)
├── windows/
│   ├── start-team.bat          # Windows one-click launcher (double-click this)
│   └── create-shortcut.bat     # Desktop shortcut creator ("Start AI Team")
├── start-team.bat              # Root wrapper → windows\start-team.bat
├── scripts/
│   └── build-zip.sh            # Release archive builder (default: herdr-team-<date>.zip)
├── templates/
│   ├── AGENTS.md               # {{PREFIX}} team orchestration master template
│   ├── agents/
│   │   ├── ROLE-planner.md     # {{PREFIX}}-planner role template
│   │   ├── ROLE-worker.md      # {{PREFIX}}-worker role template
│   │   ├── ROLE-reviewer.md    # {{PREFIX}}-reviewer role template
│   │   └── ROLE-researcher.md  # {{PREFIX}}-researcher role template (biz preset)
│   ├── dev/                    # Preset: Software Development
│   ├── app/                    # Preset: Solo App & Idea Discovery
│   └── biz/                    # Preset: Small Business Operations
├── tests/
│   ├── test_preset.sh          # Preset + TUI tests (canonical + legacy wrapper)
│   ├── test_install.sh         # Installer + release zip tests
│   └── test_windows_launcher.sh# Windows launcher tests
├── install.sh                  # Symlink installer (~/bin + ~/templates)
├── LICENSE                     # MIT License
├── README.md                   # This file (English, primary)
└── README.ko.md                # 한국어 상세 가이드
```

### How it works

1. **Prefix** — `$1` wins; otherwise derived from the git root (or folder) name.
   `try2`→`try2`, `my-project`→`mp`, `scandimension`→`sc` (2–4 letter abbreviation or full name).
2. **Preset** — `--preset dev|app|biz`, `HERDR_TEAM_PRESET`, or the interactive TUI menu (default: `dev`).
3. **Templates** — copies `AGENTS.md` + `agents/<prefix>-*.md` from `~/templates/agent-team`
   (with `{{PREFIX}}` substitution). Skipped if team docs already exist (idempotent).
4. **Pane split** — current pane (PM) → split right (role 1) → split down twice (roles 2–3).
5. **Equalize** — `herdr pane resize` evens the 3 right panes (~1:1:1, best-effort).
6. **Label + start** — renames to ① PM / ② / ③ / ④ and runs
   `herdr agent start <prefix>-<role> --kind opencode` (skips existing agents).

`install.sh` creates these symlinks (plus `~/bin` PATH registration in
`~/.bashrc`/`~/.zshrc`, marker comment, idempotent):

```bash
~/bin/herdr-team       -> <repo>/bin/herdr-team
~/bin/ht               -> <repo>/bin/herdr-team
~/bin/hts              -> <repo>/bin/herdr-team
~/bin/herdr-team-setup -> <repo>/bin/herdr-team   # legacy alias
~/templates/agent-team -> <repo>/templates
```

> `~/bin` must be on your `PATH` to run `herdr-team` from anywhere.

### Interactive TUI

With no `--preset` (and no `HERDR_TEAM_PRESET` / `--no-interactive`), a preset menu is shown:

```
Select AI team preset (1-3 or name, default: dev):
  1) dev - Software Development (개발 3인 팀, 기본값)
  2) app - Solo App & Idea Discovery (1인 앱/아이템)
  3) biz - Small Business Operations (스몰 비즈니스)
Select [1-3/dev/app/biz] (default: dev, 10s):
```

Notes:

- Non-blocking: EOF / timeout / piped input falls back to `dev` (automation-safe).
- `--no-interactive` never prompts and defaults to `dev`.
- `--list-presets` prints available presets and exits.

### Presets (dev, app, biz)

| Preset | Roles | Focus |
|--------|-------|-------|
| `dev` (default) | planner, worker, reviewer | Software Development, TDD |
| `app` | planner, worker, reviewer | Solo App & Idea Discovery, deploy/E2E emphasis |
| `biz` | planner, researcher, reviewer | Small Business Operations, research-first (no worker) |

Each preset lives in `templates/<preset>/` (`preset.conf` + `AGENTS.md`).
Roles are generalized: the script derives agent names (`<prefix>-<role>`) from the preset's `ROLES`,
so adding a preset is just adding a directory (+ `ROLE-<role>.md` if it uses a new role).

### Windows one-click details

For non-technical users on Windows — double-click, no terminal knowledge required:

1. Double-click **`start-team.bat`** (repo root, or from the release zip).
2. Pick a preset from the menu (English primary + Korean, 10s default: dev).
3. A desktop shortcut ("Start AI Team") can be created with `windows\create-shortcut.bat`.

The launcher runs the repo script via WSL (fallback: Git-Bash), converting paths with
`wsl wslpath`, forwarding all args (`--preset`, `--dry-run`, ...).
Simulation without side effects: `HERDR_TEAM_DRYRUN=1`.
Skip the final pause (automation): `HERDR_TEAM_NOPAUSE=1`.
Missing Git/WSL? The launcher guides you to `winget install --id Git.Git` and
`wsl --install` (`HERDR_TEAM_SKIP_CHECK=1` bypasses the check).

### CLI options reference

| Option | Description |
|--------|-------------|
| `prefix` | Agent prefix (e.g. `sd`, `myproj`); auto-detected when omitted |
| `--kind KIND` | Agent kind (default: `opencode`) |
| `--cwd PATH` | Working directory (default: `$PWD`) |
| `--template-dir D` | Template directory (default: `~/templates/agent-team`, or `HERDR_TEAM_TEMPLATE_DIR`) |
| `--preset NAME` | Team preset: `dev` \| `app` \| `biz` (or `HERDR_TEAM_PRESET`; default: `dev` / TUI) |
| `--list-presets` | Print available presets and exit |
| `--no-interactive` | Never prompt; default `preset=dev` |
| `--no-template` | Skip template copy/generate step |
| `--no-resize` | Skip pane resize step |
| `--no-start` | Skip agent start (split + label only) |
| `--force` | Overwrite existing `AGENTS.md`/agents docs |
| `--dry-run` | Print planned commands without executing |
| `-h, --help` | Print help |

### Requirements

- `herdr` CLI (run inside a Herdr session)
- `jq` (parses `herdr pane current/split` JSON responses)
- Windows launcher: WSL (preferred) or Git-Bash

### Team model (3 roles)

```
User → PM(agy) → planner → worker → reviewer ─[APPROVE + run log]→ report
                               ↑____[REQUEST CHANGES]____|
```

- Only worker edits code. Reviewer runs static review + build/unit/integration·E2E·regression, then judges only.
- On-demand: researcher (research), ops (deploy/infra) — started by PM when needed.
- See template `AGENTS.md` + role docs for the full protocol.

### Tests

```bash
bash tests/test_preset.sh            # preset + TUI (canonical + legacy wrapper)
bash tests/test_install.sh           # installer + release zip
bash tests/test_windows_launcher.sh  # launcher structure + forwarded-command simulation
```

### License

MIT License — see [LICENSE](LICENSE).
Copyright (c) 2026 Herdr Team Contributors.
Free for everyone to use, modify, and distribute.
