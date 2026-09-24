# herdr-team

> **Multi-agent orchestration for AI coding agents** — a one-command 4-pane planner / worker / reviewer crew on the [herdr](https://github.com/herdrdev/herdr) terminal multiplexer.

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-blue)](README.md)
[![Stars](https://img.shields.io/github/stars/harry81/herdr-team?style=social)](https://github.com/harry81/herdr-team/stargazers)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> 한국어 가이드는 [README.ko.md](README.ko.md) 참조. (Formerly `herdr-team-setup` alias is fully supported)

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
  planner-designed (UX/Wireframe when needed), TDD-built, and reviewer-gate-checked with
  attached execution logs and deploy/E2E checks.
- **research — Deep Research:** for evidence-driven investigation — a research-first team
  turns a question into evaluation axes, sourced comparison tables, and a verified report.
- **biz — Small Business Operations:** for non-coders — a research-first team compares
  applications, policies, and options with sources (administrative/support programs, CS
  manuals, operations automation), so you decide without hiring anyone.
- **mkt — Local & SNS Marketing:** for shop owners and solo marketers — keyword/location
  analysis, campaign calendars, and compliant copy/posts with expression review.
- **creator — Content Creation & Publishing:** for authors — an outline → draft → proofread
  pipeline (ebooks, blogs, newsletters), with the worker writing and the reviewer fact-checking.

## Quick Start

**Windows — zero terminal.** Download the release zip (`herdr-team-YYYYMMDD.zip`) from GitHub Releases,
unzip, and double-click **`start-team.bat`** (and optionally **`start-watcher.bat`** for auto-unblocking).
Pick a preset from the menu. That's it — no terminal opened, ever.

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
htw &                  # (recommended) run background watcher to auto-unblock permission prompts
hts myproj --preset research
hts sd --dry-run       # print plan only, no changes
```

## Preset Summary

| Preset | Who it's for | Team | Focus |
|--------|--------------|------|-------|
| `dev` (default) | development teams shipping code | orchestrator, planner, worker, reviewer | Software Development, TDD quality gate (+ UX/Wireframe, deploy/E2E) |
| `research` | evidence-driven investigation | orchestrator, planner, researcher, reviewer | Deep Research, sourced comparison & verified report |
| `biz` | small business operators, no code | orchestrator, planner, researcher, reviewer | Small Business Operations: support programs, CS manuals, ops automation (no worker) |
| `mkt` | shop owners / solo marketers | orchestrator, planner, researcher, reviewer | Local & SNS Marketing, keyword/competitor analysis, compliant copy |
| `creator` | authors & content creators | orchestrator, planner, worker, reviewer | Content Creation & Publishing, outline → draft → proofread |

> `app` was merged into `dev`; `--preset app` still works as a deprecated alias for `dev`.

<details>
<summary><b>Advanced — full reference (repository layout, how it works, TUI, presets, Windows, CLI options, requirements, team model, tests)</b></summary>

## Advanced

Everything below is reference material. You never need it for the 30-second start above.

### Repository layout

```
herdr-team/
├── bin/
│   ├── herdr-team        # Main script (executable, canonical)
│   ├── herdr-watcher     # Team watcher script (auto-unblocks permission prompts, htw)
│   └── herdr-team-setup  # Legacy wrapper (100% compatible, forwards to herdr-team)
├── windows/
│   ├── start-team.bat          # Windows one-click team launcher (double-click this)
│   ├── start-watcher.bat       # Windows one-click watcher launcher (double-click this)
│   └── create-shortcut.bat     # Desktop shortcut creator ("Start AI Team")
├── start-team.bat              # Root wrapper → windows\start-team.bat
├── start-watcher.bat           # Root wrapper → windows\start-watcher.bat
├── scripts/
│   └── build-zip.sh            # Release archive builder (default: herdr-team-<date>.zip)
├── templates/
│   ├── AGENTS.md               # {{PREFIX}} team orchestration master template
│   ├── agents/
│   │   ├── ROLE-orchestrator.md # {{PREFIX}}-orchestrator role template (pipeline relay)
│   │   ├── ROLE-planner.md     # {{PREFIX}}-planner role template
│   │   ├── ROLE-worker.md      # {{PREFIX}}-worker role template
│   │   ├── ROLE-reviewer.md    # {{PREFIX}}-reviewer role template
│   │   └── ROLE-researcher.md  # {{PREFIX}}-researcher role template (research/biz/mkt presets)
│   ├── opencode-agents/        # opencode primary agent defs (--agent <prefix>-<role>, permission-enforced)
│   │   ├── ROLE-orchestrator.md
│   │   ├── ROLE-planner.md
│   │   ├── ROLE-worker.md
│   │   ├── ROLE-reviewer.md
│   │   └── ROLE-researcher.md
│   ├── dev/                    # Preset: Software Development
│   ├── research/               # Preset: Deep Research & Knowledge Discovery
│   ├── biz/                    # Preset: Small Business Operations
│   ├── mkt/                    # Preset: Local & SNS Marketing
│   └── creator/                # Preset: Content Creation & Publishing
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
2. **Preset** — `--preset dev|research|biz|mkt|creator`, `HERDR_TEAM_PRESET`, or the interactive TUI menu (default: `dev`). `app` is a deprecated alias for `dev`.
3. **Templates & isolation** — each preset's canonical docs live under `agents/<preset>/`
   (`AGENTS.md` + `<prefix>-<role>.md`), with the active preset tracked in `.herdr-team/preset`.
   The root `AGENTS.md` is the active view: on switch the root edits are written back to the
   outgoing preset's canonical folder, then the incoming canonical is copied to the root.
   Also installs/refreshes opencode role agents to `.opencode/agents/<prefix>-*.md`
   (stale roles are pruned; same-preset reruns preserve your edits).
4. **Pane split & Layout** — default layout is `2col`:
   - Left column: [PM (top 50%)] / [Task Manager (bottom 50%)]
   - Right column: [Role 2 (top)] / [Role 3 (middle)] / [Role 4 (bottom)]
   (Use `--layout right-stack` if you prefer the single right-column stack layout).
5. **Equalize** — down splits pass `--ratio 1/(N-k+1)` (and `0.5` for PM/TM), so panes are exactly
   equalized without manual resize.
6. **Label + start** — renames to ① PM / ② Task Manager / ③④⑤ roles and runs
   `herdr agent start <prefix>-<role> --kind opencode -- --agent <prefix>-<role>`
   (opencode role enforcement; skips existing agents).

`install.sh` creates these symlinks (plus `~/bin` PATH registration in
`~/.bashrc`/`~/.zshrc`, marker comment, idempotent):

```bash
~/bin/herdr-team       -> <repo>/bin/herdr-team
~/bin/ht               -> <repo>/bin/herdr-team
~/bin/hts              -> <repo>/bin/herdr-team
~/bin/herdr-team-setup -> <repo>/bin/herdr-team   # legacy alias
~/bin/herdr-watcher    -> <repo>/bin/herdr-watcher
~/bin/htw              -> <repo>/bin/herdr-watcher # watcher alias
~/templates/agent-team -> <repo>/templates
```

> `~/bin` must be on your `PATH` to run `herdr-team` from anywhere.

### Preset isolation & lossless switching

Feature docs are isolated per preset inside the **target project**, so switching presets never
overwrites another preset's docs:

```
<target-project>/
├── AGENTS.md                     # active view (synced copy of the active preset canonical)
├── .herdr-team/preset            # active canonical preset (one line, e.g. mkt)
├── agents/
│   ├── dev/                      # canonical per preset (AGENTS.md + <prefix>-<role>.md)
│   ├── mkt/                      # canonical per preset
│   └── <prefix>-<role>.md        # legacy flat docs (imported by copy, never modified)
└── .opencode/agents/             # generated artifacts for the active ROLES only
```

- **Switch (dev → mkt)**: root `AGENTS.md` edits are written back to `agents/dev/AGENTS.md`
  (lossless), then `agents/mkt/AGENTS.md` is copied to the root. Switching back restores `dev`.
- **Migration**: existing flat `agents/<prefix>-<role>.md` are copied into `agents/<preset>/`
  (originals untouched). If both exist, `agents/<preset>/` wins. herdr-team's own repo is safe.
- **`--force`** now means: reseed **only the requested preset folder** from templates and
  force-activate the root. Other presets under `agents/` are never touched.
- **Dry-run** (`--dry-run`) prints the isolation plan and writes nothing (no docs, no state).

### Interactive TUI

With no `--preset` (and no `HERDR_TEAM_PRESET` / `--no-interactive`), a preset menu is shown:

```
Select AI team preset (1-5 or name, default: dev):
  1) dev - Software Development (소프트웨어 개발·MVP, 4인 팀, orchestrator/planner/worker/reviewer)
  2) research - Deep Research & Knowledge Discovery (...)
  3) biz - Small Business Operations (소상공인 사업 운영, ...)
  4) mkt - Local & SNS Marketing (로컬·SNS 마케팅, ...)
  5) creator - Content Creation & Publishing (콘텐츠 창작·출판, ...)
Select [1-5/dev/research/biz/mkt/creator] (default: dev, 10s):
```

Notes:

- Non-blocking: EOF / timeout / piped input falls back to `dev` (automation-safe).
- `--no-interactive` never prompts and defaults to `dev`.
- `--list-presets` prints available presets and exits.

### Presets (dev, research, biz, mkt, creator)

| Preset | Roles | Focus |
|--------|-------|-------|
| `dev` (default) | orchestrator, planner, worker, reviewer | Software Development, TDD (+ UX/Wireframe, deploy/E2E) |
| `research` | orchestrator, planner, researcher, reviewer | Deep Research, sourced comparison & verified report |
| `biz` | orchestrator, planner, researcher, reviewer | Small Business Operations: support programs, CS, ops automation (no worker) |
| `mkt` | orchestrator, planner, researcher, reviewer | Local & SNS Marketing, keyword/competitor analysis, compliant copy (worker on-demand) |
| `creator` | orchestrator, planner, worker, reviewer | Content Creation & Publishing, outline → draft → proofread (researcher on-demand) |

Each preset lives in `templates/<preset>/` (`preset.conf` + `AGENTS.md`).
Roles are generalized: the script derives agent names (`<prefix>-<role>`) from the preset's `ROLES`,
so adding a preset is just adding a directory (+ `ROLE-<role>.md` if it uses a new role).
Presets are discovered dynamically from `--template-dir` and the bundled `templates/`, so a custom
`<name>/preset.conf` shows up in `--list-presets` and the TUI automatically.
`app` is reserved as a deprecated alias of `dev` (a user-supplied `app/` directory is ignored).

### Windows one-click details

For non-technical users on Windows — double-click, no terminal knowledge required:

1. Double-click **`start-team.bat`** (repo root, or from the release zip).
2. Double-click **`start-watcher.bat`** (recommended: auto-allows command approval prompts in background).
3. Pick a preset from the menu (English primary + Korean, 10s default: dev).
4. A desktop shortcut ("Start AI Team") can be created with `windows\create-shortcut.bat`.

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
| `--layout LAYOUT` | Team pane layout: `2col` (default, TM below PM) \| `right-stack` (or `HERDR_TEAM_LAYOUT`) |
| `--cwd PATH` | Working directory (default: `$PWD`) |
| `--template-dir D` | Template directory (default: `~/templates/agent-team`, or `HERDR_TEAM_TEMPLATE_DIR`) |
| `--preset NAME` | Team preset: `dev` \| `research` \| `biz` \| `mkt` \| `creator` (`app` = deprecated alias of `dev`; or `HERDR_TEAM_PRESET`; default: `dev` / TUI) |
| `--list-presets` | Print available presets and exit |
| `--no-interactive` | Never prompt; default `preset=dev`, `kind=opencode` |
| `--no-template` | Skip template copy/generate step |
| `--no-resize` | Split without `--ratio` equalization (no separate resize step) |
| `--no-start` | Skip agent start (split + label only) |
| `--force` | Reseed **only the requested preset folder** (`agents/<preset>/`) from templates and force-activate root `AGENTS.md`; other presets untouched |
| `--dry-run` | Print planned commands without executing |
| `-v, --version` | Print version and exit |
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
