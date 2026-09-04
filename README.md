# herdr-team

One-click setup for a 3-agent Herdr team (PM + planner / worker / reviewer) in any project.

> Formerly `herdr-team-setup` — that name still works as a fully compatible legacy alias.
> 한국어 가이드는 [README.ko.md](README.ko.md) 참조.

## Overview

`herdr-team` scaffolds team orchestration docs (`AGENTS.md`, `agents/<prefix>-*.md`) and splits your current Herdr pane into a labeled PM + 3-agent layout, then starts the agents (idempotent — existing agents are skipped).

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

## Quick Start

```bash
git clone <this-repo> ~/work/projects/herdr-team
cd ~/work/projects/herdr-team
./install.sh
```

`install.sh` creates these symlinks:

```bash
~/bin/herdr-team       -> <repo>/bin/herdr-team
~/bin/ht               -> <repo>/bin/herdr-team
~/bin/hts              -> <repo>/bin/herdr-team
~/bin/herdr-team-setup -> <repo>/bin/herdr-team   # legacy alias
~/templates/agent-team -> <repo>/templates
```

Manual install:

```bash
ln -s "$PWD/bin/herdr-team" ~/bin/herdr-team
ln -s "$PWD/bin/herdr-team" ~/bin/ht
ln -s "$PWD/bin/herdr-team" ~/bin/hts
ln -s "$PWD/bin/herdr-team" ~/bin/herdr-team-setup
ln -s "$PWD/templates" ~/templates/agent-team
```

> `~/bin` must be on your `PATH` to run `herdr-team` from anywhere.

Run it inside an empty shell pane of a Herdr session:

```bash
cd <target-project>

herdr-team               # auto-detect prefix from folder name
herdr-team myproj        # force prefix
herdr-team sd --dry-run  # print plan only, no changes
```

How it works:

1. **Prefix** — `$1` wins; otherwise derived from the git root (or folder) name.
   `try2`→`try2`, `my-project`→`mp`, `scandimension`→`sc` (2–4 letter abbreviation or full name).
2. **Preset** — `--preset dev|app|biz`, `HERDR_TEAM_PRESET`, or the interactive TUI menu (default: `dev`).
3. **Templates** — copies `AGENTS.md` + `agents/<prefix>-*.md` from `~/templates/agent-team`
   (with `{{PREFIX}}` substitution). Skipped if team docs already exist (idempotent).
4. **Pane split** — current pane (PM) → split right (role 1) → split down twice (roles 2–3).
5. **Equalize** — `herdr pane resize` evens the 3 right panes (~1:1:1, best-effort).
6. **Label + start** — renames to ① PM / ② / ③ / ④ and runs
   `herdr agent start <prefix>-<role> --kind opencode` (skips existing agents).

## Interactive TUI

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

## Presets (dev, app, biz)

| Preset | Roles | Focus |
|--------|-------|-------|
| `dev` (default) | planner, worker, reviewer | Software Development, TDD |
| `app` | planner, worker, reviewer | Solo App & Idea Discovery, deploy/E2E emphasis |
| `biz` | planner, researcher, reviewer | Small Business Operations, research-first (no worker) |

Each preset lives in `templates/<preset>/` (`preset.conf` + `AGENTS.md`).
Roles are generalized: the script derives agent names (`<prefix>-<role>`) from the preset's `ROLES`,
so adding a preset is just adding a directory (+ `ROLE-<role>.md` if it uses a new role).

## Windows One-Click

For non-technical users on Windows — double-click, no terminal knowledge required:

1. Double-click **`start-team.bat`** (repo root).
2. Pick a preset from the menu (English primary + Korean, 10s default: dev).
3. A desktop shortcut ("Start AI Team") can be created with `windows\create-shortcut.bat`.

The launcher runs the repo script via WSL (fallback: Git-Bash), converting paths with
`wsl wslpath`, forwarding all args (`--preset`, `--dry-run`, ...).
Simulation without side effects: `HERDR_TEAM_DRYRUN=1`.
Skip the final pause (automation): `HERDR_TEAM_NOPAUSE=1`.

## Command Options

```
herdr-team [prefix] [options]

  --kind KIND       agent kind (default: opencode)
  --cwd PATH        working directory (default: $PWD)
  --template-dir D  template directory (default: ~/templates/agent-team,
                    or HERDR_TEAM_TEMPLATE_DIR)
  --preset NAME     team preset: dev | app | biz
                    (or HERDR_TEAM_PRESET; default: dev / TUI)
  --list-presets    print available presets and exit
  --no-interactive  never prompt; default preset=dev
  --no-template     skip template copy/generate step
  --no-resize       skip pane resize step
  --no-start        skip agent start (split + label only)
  --force           overwrite existing AGENTS.md/agents docs
  --dry-run         print planned commands without executing
  -h, --help        print help
```

## Requirements

- `herdr` CLI (run inside a Herdr session)
- `jq` (parses `herdr pane current/split` JSON responses)
- Windows launcher: WSL (preferred) or Git-Bash

## Team Model (3 roles)

```
User → PM(agy) → planner → worker → reviewer ─[APPROVE + run log]→ report
                               ↑____[REQUEST CHANGES]____|
```

- Only worker edits code. Reviewer runs static review + build/unit/integration·E2E·regression, then judges only.
- On-demand: researcher (research), ops (deploy/infra) — started by PM when needed.
- See template `AGENTS.md` + role docs for the full protocol.

## Tests

```bash
bash tests/test_preset.sh           # preset + TUI (English-primary assertions incl.)
bash tests/test_windows_launcher.sh # launcher structure + forwarded-command simulation
```

## License

MIT License — see [LICENSE](LICENSE).
Copyright (c) 2026 Herdr Team Setup Contributors.
Free for everyone to use, modify, and distribute.
