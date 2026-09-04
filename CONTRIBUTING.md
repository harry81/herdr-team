# Contributing to herdr-team

Thanks for helping! This project follows a small-team agent workflow, but human
PRs are very welcome.

## Quick way to contribute

1. Fork and clone: `git clone https://github.com/harry81/herdr-team`
2. Create a branch: `git checkout -b feat/my-change`
3. Follow TDD: add/adjust `tests/test_*.sh` first (Red), implement (Green).
4. Run all suites locally:
   ```bash
   bash tests/test_preset.sh
   bash tests/test_install.sh
   bash tests/test_windows_launcher.sh
   ```
5. Open a PR using the template (summary, impact, pasted test results).

## Rules

- Keep `bin/herdr-team` backward compatible; `bin/herdr-team-setup` must stay a
  pure forwarder (outputs must stay byte-identical — see test §12).
- New presets = new `templates/<preset>/` directory (`preset.conf` + `AGENTS.md`);
  new roles need `templates/agents/ROLE-<role>.md`.
- `.bat` files must stay CRLF with `chcp 65001` on top.
- User-facing changes need `README.md` + `README.ko.md` updates.
- MIT License: by contributing you agree your work is MIT-licensed.
