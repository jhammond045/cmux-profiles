# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-20

First release.

### Added
- `hs.chooser` fuzzy modal launcher for cmux profiles, summoned with Cmd+O
  (only while cmux is frontmost; configurable, or global).
- Reads iTerm2 dynamic-profile JSON (`{"Profiles":[...]}` or a bare array).
  `Name`, `Command`, `Custom Command`, `Working Directory`, and `Tags` are used;
  name, command, and tags are all searchable.
- **Enter** opens a profile in a new workspace (`cmux new-workspace` with
  `--name`/`--cwd`/`--command`/`--focus`).
- **Shift+Enter** opens it as a split in the current workspace
  (`cmux new-split` then `cmux send`).
- Packaged as a Hammerspoon Spoon (`CmuxPick.spoon`, `hs.loadSpoon("CmuxPick")`).
- `install.sh` to link the Spoon, seed a config, and add the loader.
- `luacheck` CI on every push.

[1.0.0]: https://github.com/jhammond045/cmux-profiles/releases/tag/v1.0.0
