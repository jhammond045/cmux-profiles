# cmux-pick

An [iTerm2 Profiles](https://iterm2.com/documentation-dynamic-profiles.html)-style
launcher for the [cmux](https://cmux.com) terminal, built on
[Hammerspoon](https://www.hammerspoon.org).

Press a hotkey, get a fuzzy-search modal of your saved sessions, hit Enter, and
the profile opens in a new cmux workspace running its command (usually `ssh …`).
It reads the **same JSON format iTerm2 uses for dynamic profiles**, so you can
point it at a profiles file you already maintain.

```
┌───────────────────────────────────────────────┐
│ Search Profiles      ↵ new workspace  ⌘↵ split │
├───────────────────────────────────────────────┤
│ prod web (ssh)            ssh deploy@prod-1…    │
│ staging db                ssh root@10.0.0.5     │
│ local project             ~/code/myapp          │
└───────────────────────────────────────────────┘
```

- **Enter** → open the profile in a new workspace.
- **Cmd+Enter** → open it as a split ("tab") in the current workspace.

## Requirements

- macOS
- [cmux](https://cmux.com) (the native terminal app)
- [Hammerspoon](https://www.hammerspoon.org) — `brew install --cask hammerspoon`
  (grant it Accessibility permission on first launch)

## Install

```bash
git clone https://github.com/<you>/cmux-pick.git
cd cmux-pick
./install.sh
```

`install.sh` symlinks `cmux-pick.lua` into `~/.hammerspoon/`, seeds a config at
`~/.config/cmux-pick/profiles.json`, and appends `require("cmux-pick").start()`
to your `~/.hammerspoon/init.lua`. Then:

1. **Enable socket access in cmux** — Settings → allow external processes
   (`CMUX_SOCKET_MODE = automation`). Without this, launches fail with `exit 15`,
   because Hammerspoon isn't a process cmux spawned itself.
2. Reload Hammerspoon (menu bar → *Reload Config*).
3. Focus cmux, press **Cmd+O**.

### Manual install

If you'd rather not run the script: symlink or copy `cmux-pick.lua` somewhere on
Hammerspoon's Lua path (`~/.hammerspoon/` works), then add to `init.lua`:

```lua
require("cmux-pick").start()
```

## Profiles

Profiles live in a JSON file (default `~/.config/cmux-pick/profiles.json`) in
iTerm2 dynamic-profile shape. Only a few fields are used:

```json
{
  "Profiles": [
    { "Name": "prod web (ssh)", "Command": "ssh deploy@prod-1.example.com", "Custom Command": "Yes" },
    { "Name": "local project",  "Working Directory": "~/code/myapp" }
  ]
}
```

| Field | Meaning |
|-------|---------|
| `Name` | Shown in the picker; becomes the workspace name. |
| `Command` | Command to run (with `"Custom Command": "Yes"`). Usually `ssh …`. |
| `Custom Command` | `"Yes"` to run `Command`; otherwise a plain shell. |
| `Working Directory` | `cwd` for the session. `~` is expanded. |

A bare top-level array (`[ {…}, {…} ]`) also works.

**Already keep an iTerm2 dynamic-profiles file?** Point cmux-pick straight at it
instead of maintaining a second copy:

```bash
ln -sf ~/Library/Application\ Support/iTerm2/DynamicProfiles/yours.json \
       ~/.config/cmux-pick/profiles.json
```

The file is re-read every time you open the picker, so edits show up immediately.

## Configuration

Pass an options table to `start()`:

```lua
require("cmux-pick").start({
  profiles   = "~/dotfiles/cmux-profiles.json",  -- profiles JSON path
  app        = "cmux",                           -- cmux's macOS app name
  splitDir   = "down",                           -- down | up | left | right
  hotkeyMods = { "cmd" },                        -- hotkey modifiers
  hotkeyKey  = "o",                              -- hotkey key
  global     = false,                            -- true = summon from any app
  -- cmuxBin = "/path/to/cmux",                  -- override CLI auto-detection
})
```

All options are optional; the defaults match the install steps above.

If **Cmd+O** does nothing, your cmux app may register under a different name —
check it in the Hammerspoon console with
`hs.application.frontmostApplication():name()` (with cmux focused) and set
`app = "…"` accordingly. Or set `global = true` to bind the hotkey everywhere.

## How it works

cmux ships a CLI that talks to the running app over a Unix socket. cmux-pick
shells out to it:

- **Enter** → `cmux new-workspace --name … --cwd … --command … --focus true`
  (one call; cmux runs the command in the new workspace, no race).
- **Cmd+Enter** → `cmux new-split <dir> --workspace <current> --focus true`,
  then `cmux send --surface <new> "<command>\n"` (split has no `--command`).

The picker is a native `hs.chooser`. Because `hs.chooser` can't report which
modifier was held on selection, Cmd+Enter is caught by an `hs.eventtap` that's
active only while the modal is open.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Launch alert `exit 15` | Socket closed to external processes. Enable automation mode in cmux Settings. |
| "cmux CLI not found" | cmux not installed, or in a non-standard location — set `cmuxBin`. |
| Cmd+O does nothing | Wrong `app` name (see above), or Hammerspoon lacks Accessibility permission. |
| Cmd+Enter does nothing | Needs a recent Hammerspoon (`selectedRowContents`). `brew upgrade --cask hammerspoon`. |
| Picker empty | Bad/missing profiles file — check the path and JSON. |

## License

MIT — see [LICENSE](LICENSE).
