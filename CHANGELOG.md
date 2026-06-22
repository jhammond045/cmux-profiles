# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-06-21

### Changed
- **Renamed the project to cmux-profiles.** The Spoon is now `CmuxProfiles.spoon`
  and loads with `hs.loadSpoon("CmuxProfiles")`; the default config directory is
  `~/.config/cmux-profiles/`. **Breaking** for existing installs: update the
  loader in `~/.hammerspoon/init.lua` and move your config dir — or just re-run
  `install.sh`.

## [1.1.0] - 2026-06-20

### Added
- Built-in profile editor (`hs.webview` form): add, edit, rename, and delete
  profiles, then save. Opened with **Cmd+E** or the **✎ Edit profiles…** row in
  the picker.
- Editor preserves unknown profile fields (e.g. iTerm2 `Guid`) on save, writes a
  `.bak` of the previous file, and assigns a `Guid` to new profiles.

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
- Packaged as a Hammerspoon Spoon (`CmuxProfiles.spoon`, `hs.loadSpoon("CmuxProfiles")`).
- `install.sh` to link the Spoon, seed a config, and add the loader.
- `luacheck` CI on every push.

[2.0.0]: https://github.com/jhammond045/cmux-profiles/releases/tag/v2.0.0
[1.1.0]: https://github.com/jhammond045/cmux-profiles/releases/tag/v1.1.0
[1.0.0]: https://github.com/jhammond045/cmux-profiles/releases/tag/v1.0.0
