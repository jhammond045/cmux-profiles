--- === CmuxPick ===
---
--- An iTerm2-Profiles-style session launcher for the cmux terminal.
---
--- Reads iTerm2 dynamic-profile JSON and launches profiles through the cmux
--- CLI. Press the hotkey (default Cmd+O, only while cmux is frontmost) to open a
--- fuzzy modal of your profiles:
---   * Enter        -> open the profile in a new workspace
---   * Shift+Enter  -> open it as a split ("tab") in the current workspace
---
--- Download: https://github.com/jhammond045/cmux-profiles

local obj = {}
obj.__index = obj

obj.name     = "CmuxPick"
obj.version  = "1.0.0"
obj.author   = "jhammond"
obj.homepage = "https://github.com/jhammond045/cmux-profiles"
obj.license  = "MIT - https://opensource.org/licenses/MIT"

-- shell single-quote:  ' -> '\''
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- expand a leading ~ (we single-quote paths, so the shell won't do it for us)
local function expanduser(p)
  if type(p) == "string" and p:sub(1, 1) == "~" then
    return os.getenv("HOME") .. p:sub(2)
  end
  return p
end

--- CmuxPick:start([opts]) -> self
--- Start the launcher. opts (all optional):
---   profiles    profiles JSON path     (default ~/.config/cmux-pick/profiles.json)
---   app         cmux's macOS app name  (default "cmux")
---   splitDir    down|up|left|right     (default "down")
---   hotkeyMods  modifier table         (default {"cmd"})
---   hotkeyKey   key                    (default "o")
---   global      summon from any app    (default false = only when cmux frontmost)
---   cmuxBin     explicit CLI path      (default: auto-resolve)
function obj:start(opts)
  opts = opts or {}
  local PROFILES = opts.profiles or (os.getenv("HOME") .. "/.config/cmux-pick/profiles.json")
  local APP      = opts.app or "cmux"
  local SPLIT    = opts.splitDir or "down"
  local MODS     = opts.hotkeyMods or { "cmd" }
  local KEY      = opts.hotkeyKey or "o"
  local GLOBAL   = opts.global or false

  -- Resolve the cmux CLI once: explicit override, then PATH, then app-bundle shim.
  -- NOTE: Contents/MacOS/cmux is the GUI (no-ops on args, exits 15); the real
  -- CLI is the shim under Contents/Resources/bin/cmux.
  local CMUX
  local function cmuxBin()
    if CMUX ~= nil then return CMUX end
    if opts.cmuxBin then CMUX = opts.cmuxBin; return CMUX end
    local out, ok = hs.execute("command -v cmux", true)
    if ok and out and out:match("%S") then
      CMUX = out:gsub("%s+$", "")
    else
      local shim = "/Applications/cmux.app/Contents/Resources/bin/cmux"
      CMUX = hs.fs.attributes(shim) and shim or false
    end
    return CMUX
  end

  -- Run a cmux subcommand. Returns stdout on success, nil on failure (+ alert).
  local function cmux(args)
    local bin = cmuxBin()
    if not bin then
      hs.alert.show("cmux-pick: cmux CLI not found (install it from cmux Settings)")
      return nil
    end
    local out, ok, _, rc = hs.execute(shq(bin) .. " " .. args, true)
    if not ok then
      hs.alert.show("cmux " .. args .. "  ->  exit " .. tostring(rc) .. "\n" .. (out or ""))
      return nil
    end
    return out or ""
  end

  -- Parse iTerm2 dynamic-profile JSON ({"Profiles":[...]}); a bare array works too.
  local function loadProfiles()
    local data = hs.json.read(PROFILES)
    if not data then
      hs.alert.show("cmux-pick: cannot read " .. PROFILES)
      return {}
    end
    local list = data.Profiles or data
    local choices = {}
    for _, p in ipairs(list) do
      local sub = p.Command or ""
      if p.Tags and #p.Tags > 0 then             -- show + make tags searchable
        local t = "[" .. table.concat(p.Tags, ", ") .. "]"
        sub = (sub ~= "" and (sub .. "  ") or "") .. t
      end
      choices[#choices + 1] = {
        text    = p.Name or "(unnamed)",
        subText = sub,
        cmd     = (p["Custom Command"] == "Yes") and p.Command or nil,
        dir     = p["Working Directory"],
      }
    end
    return choices
  end

  -- Enter: open the profile in a brand-new workspace (one clean call).
  local function launchWorkspace(c)
    if not c or not c.text then return end
    local a = { "new-workspace", "--focus", "true", "--name", shq(c.text) }
    if c.dir and c.dir ~= "" then a[#a + 1] = "--cwd";     a[#a + 1] = shq(expanduser(c.dir)) end
    if c.cmd and c.cmd ~= "" then a[#a + 1] = "--command"; a[#a + 1] = shq(c.cmd) end
    cmux(table.concat(a, " "))
  end

  -- Shift+Enter: open the profile as a split in the CURRENT workspace.
  -- new-split has no --command, so split then send the command line (async,
  -- so Hammerspoon's UI doesn't freeze while the new shell comes up).
  local function launchSplit(c)
    if not c or not c.text then return end
    local cw  = cmux("current-workspace")
    cw = cw and cw:match("workspace:%d+")
    local out = cmux("new-split " .. SPLIT .. " --focus true"
                     .. (cw and (" --workspace " .. cw) or ""))
    local sid = out and out:match("surface:%d+")
    if not sid then return end

    local parts = {}
    if c.dir and c.dir ~= "" then parts[#parts + 1] = "cd " .. shq(expanduser(c.dir)) end
    if c.cmd and c.cmd ~= "" then parts[#parts + 1] = c.cmd end
    if #parts > 0 then
      local line = shq(table.concat(parts, " && ") .. "\n")
      hs.timer.doAfter(0.35, function()          -- non-blocking; split -> shell ready
        cmux("send --surface " .. sid .. " " .. line)
      end)
    end
  end

  local altTap            -- forward decl (captured by onPick + show)
  local splitting = false -- guards against a double-launch if hide() fires onPick

  local function onPick(c)                        -- Enter / click / Esc(nil)
    if altTap then altTap:stop() end
    if splitting then return end                  -- a split is in progress; don't also open a workspace
    launchWorkspace(c)
  end

  local picker = hs.chooser.new(onPick)
  picker:searchSubText(true)                      -- typing also matches Command + Tags
  picker:placeholderText("Search Profiles      \u{21A9} new workspace   \u{21E7}\u{21A9} split tab")

  -- Shift+Return = split. (Cmd+Return is swallowed by the system -> beep.)
  -- hs.chooser can't report modifiers in its callback, so intercept the key.
  local RETURN = hs.keycodes.map["return"]
  altTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if not picker:isVisible() then return false end
    if e:getKeyCode() ~= RETURN then return false end
    local f = e:getFlags()
    if not f.shift or f.cmd or f.alt or f.ctrl then return false end

    local ok, c = pcall(function() return picker:selectedRowContents() end)
    local doSplit = ok and type(c) == "table" and c.text ~= nil
    if doSplit then splitting = true end          -- set before hide(), in case hide() calls onPick
    picker:hide()
    if altTap then altTap:stop() end
    if doSplit then
      launchSplit(c)
    else
      hs.alert.show("cmux-pick: couldn't read selection — update Hammerspoon")
    end
    splitting = false
    return true                                   -- swallow: no beep, no workspace
  end)

  local function show()
    picker:choices(loadProfiles())                -- re-read each summon (live updates)
    picker:query("")
    altTap:start()
    picker:show()
  end

  if GLOBAL then
    self._hk = hs.hotkey.bind(MODS, KEY, show)
  else
    -- Bind the hotkey only while cmux is frontmost (passes through elsewhere).
    local hk = hs.hotkey.new(MODS, KEY, show)
    local wf = hs.window.filter.new(APP)
    wf:subscribe(hs.window.filter.windowFocused,   function() hk:enable()  end)
    wf:subscribe(hs.window.filter.windowUnfocused, function() hk:disable() end)
    self._hk, self._wf = hk, wf
  end

  self._picker, self._tap = picker, altTap        -- keep refs alive (avoid GC)
  return self
end

return obj
