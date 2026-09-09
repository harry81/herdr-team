# herdr-team

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-blue)](README.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Stars](https://img.shields.io/github/stars/harry81/herdr-team?style=social)](https://github.com/harry81/herdr-team/stargazers)

> Formerly `herdr-team-setup` — that name still works as a fully compatible legacy alias.
> 한국어 가이드는 [README.ko.md](README.ko.md) 참조.

## Problem & Solution

> **Problem** — every time you want an AI agent team you manually create a tab,
> split it into panes, start each agent, and wire up role docs by hand.
>
> **Solution** — one `hts` line (or a Windows double-click) turns your terminal into a
> 4-pane AI crew. A task manager relays the pipeline so planner → worker → reviewer
> plan, build (TDD), and gate-check every change — without any agent idling.

## How it looks

```
+----------------+----------------+----------------+----------------+
| ① PM           | ② Planner      | ③ Worker       | ④ Reviewer     |
| orchestrates   | plans & splits | builds (TDD)   | verifies       |
+----------------+----------------+----------------+----------------+
      \                  |                    |                   /
       └──── tasks ──────┴────── code + tests ─────┴── APPROVE ──┘
```

Pipeline view:

```
User → ① PM → task manager → ② Planner → ③ Worker → ④ Reviewer ─[APPROVE + run log]→ report
                                       ↑______________[REQUEST CHANGES]______________|
```

## Why herdr-team?

- **dev — Software Development (TDD):** for development teams that want every feature
  planner-designed, TDD-built, and reviewer-gate-checked with attached execution logs.
- **app — Solo App & Idea Discovery:** for solo builders — turn a weekend idea into
  buildable tasks, shipped code, and deploy/E2E checks without juggling context.
- **biz — Small Business Operations:** for non-coders — a research-first team compares
  vendors, prices, and options with sources, so you decide without hiring anyone.

## Quick Start

**Windows — zero terminal.** Download `herdr-team.zip` from GitHub Releases,
unzip, and double-click **`start-team.bat`**. Pick a preset from the menu.
That's it — no terminal opened, ever.

**Linux / macOS — one line, then `hts` works everywhere:**

```bash
curl -fsSL https://raw.githubusercontent.com/harry81/herdr-team/main/install.sh | HERDR_TEAM_REPO_URL=https://github.com/harry81/herdr-team.git bash
hts --help
```

(Prefer git? `git clone https://github.com/harry81/herdr-team ~/work/projects/herdr-team && cd ~/work/projects/herdr-team && ./install.sh` — same result.)

Then, inside an empty shell pane of a Herdr session:

```bash
cd <target-project>
hts                    # auto-detect prefix, TUI preset menu, split + start
hts myproj --preset app
hts sd --dry-run       # print plan only, no changes
```

## Preset Summary

| Preset | Who it's for | Team | Focus |
|--------|--------------|------|-------|
| `dev` (default) | development teams shipping code | taskmanager, planner, worker, reviewer | Software Development, TDD quality gate |
| `app` | solo builders validating an idea | taskmanager, planner, worker, reviewer | Solo App & Idea Discovery, deploy/E2E emphasis |
| `biz` | small business operators, no code | taskmanager, planner, researcher, reviewer | research-first vendor/option research with sources (no worker) |

<details>
<summary><b>Advanced — full reference (repository layout, how it works, TUI, presets, Windows, CLI options, requirements, team model, tests)</b></summary>

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
│   │   ├── ROLE-taskmanager.md # {{PREFIX}}-taskmanager role template (pipeline relay)
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
4. **Pane split** — current pane (PM) → split right (task manager) → split down for each remaining role.
5. **Equalize** — each down split passes `--ratio 1/(N-k+1)`, so the right-column panes are exactly
   equalized (~1:1:1:1, no resize step needed).
6. **Label + start** — renames to ① PM / ② Task Manager / ③④⑤ roles and runs
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
  1) dev - Software Development (개발 4인 팀, 기본값)
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
| `dev` (default) | taskmanager, planner, worker, reviewer | Software Development, TDD |
| `app` | taskmanager, planner, worker, reviewer | Solo App & Idea Discovery, deploy/E2E emphasis |
| `biz` | taskmanager, planner, researcher, reviewer | Small Business Operations, research-first (no worker) |

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
| `--kind KIND` | Agent kind (default: `opencode` / TUI menu; supported: `opencode`, `claude`, `codex`, `agy`, etc., or `HERDR_TEAM_KIND`) |
| `--cwd PATH` | Working directory (default: `$PWD`) |
| `--template-dir D` | Template directory (default: `~/templates/agent-team`, or `HERDR_TEAM_TEMPLATE_DIR`) |
| `--preset NAME` | Team preset: `dev` \| `app` \| `biz` (or `HERDR_TEAM_PRESET`; default: `dev` / TUI) |
| `--list-presets` | Print available presets and exit |
| `--no-interactive` | Never prompt; default `preset=dev`, `kind=opencode` |
| `--no-template` | Skip template copy/generate step |
| `--no-resize` | Split without `--ratio` equalization (no separate resize step) |
| `--no-start` | Skip agent start (split + label only) |
| `--force` | Overwrite existing `AGENTS.md`/agents docs |
| `--dry-run` | Print planned commands without executing |
| `-h, --help` | Print help |

### Requirements

- `herdr` CLI (run inside a Herdr session)
- `jq` (parses `herdr pane current/split` JSON responses)
- Windows launcher: WSL (preferred) or Git-Bash

### Team model (task manager + 3 roles)

```
User → PM(agy) → task manager → planner → worker → reviewer ─[APPROVE + run log]→ report
                                             ↑________[REQUEST CHANGES]________|
```

- Task manager relays the sequential pipeline (no code edits); PM stays for user
  communication & top-level goals.
- Only worker edits code. Reviewer runs static review + build/unit/integration·E2E·regression, then judges only.
- On-demand: researcher (research), ops (deploy/infra) — started by PM when needed.
- See template `AGENTS.md` + role docs for the full protocol.

### Tests

```bash
bash tests/test_preset.sh            # preset + TUI (canonical + legacy wrapper)
bash tests/test_install.sh           # installer + release zip
bash tests/test_windows_launcher.sh  # launcher structure + forwarded-command simulation
```

</details>

## License

MIT License — see [LICENSE](LICENSE).
Copyright (c) 2026 Herdr Team Contributors.
Free for everyone to use, modify, and distribute.
