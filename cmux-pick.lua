-- cmux-pick — an iTerm2-Profiles-style launcher for the cmux terminal.
--
-- Hammerspoon module. In your ~/.hammerspoon/init.lua:
--
--     require("cmux-pick").start()                          -- defaults
--     require("cmux-pick").start({ splitDir = "right" })    -- override an option
--
-- Press the hotkey (default Cmd+O, only while cmux is frontmost) to open a
-- fuzzy modal of your profiles. Enter opens the profile in a new workspace;
-- Cmd+Enter opens it as a split in the current workspace.
--
-- Options (all optional):
--   profiles    path to the profiles JSON   (default ~/.config/cmux-pick/profiles.json)
--   app         cmux's app name in macOS    (default "cmux")
--   splitDir    "down" | "up" | "left" | "right"  (default "down")
--   hotkeyMods  modifier table              (default {"cmd"})
--   hotkeyKey   key                         (default "o")
--   global      true = summon from any app; false = only when cmux frontmost (default false)
--   cmuxBin     explicit path to the cmux CLI (default: auto-resolve)

local M = {}

-- single-quote a string for the shell:  ' -> '\''
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- expand a leading ~ (cmux --cwd / cd won't, because we single-quote it)
local function expanduser(p)
  if type(p) == "string" and p:sub(1, 1) == "~" then
    return os.getenv("HOME") .. p:sub(2)
  end
  return p
end

function M.start(opts)
  opts = opts or {}
  local PROFILES = opts.profiles or (os.getenv("HOME") .. "/.config/cmux-pick/profiles.json")
  local APP      = opts.app or "cmux"
  local SPLIT    = opts.splitDir or "down"
  local MODS     = opts.hotkeyMods or { "cmd" }
  local KEY      = opts.hotkeyKey or "o"
  local GLOBAL   = opts.global or false

  -- Resolve the cmux CLI once: explicit override, then PATH, then app-bundle shim.
  -- NOTE: the binary at Contents/MacOS/cmux is the GUI (no-ops on args, exits 15);
  -- the real CLI is the shim under Contents/Resources/bin/cmux.
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

  -- Run a cmux subcommand. Returns stdout on success, nil on failure (and alerts).
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

  -- Parse the iTerm2 dynamic-profiles JSON ({"Profiles":[...]}); a bare array works too.
  local function loadProfiles()
    local data = hs.json.read(PROFILES)
    if not data then
      hs.alert.show("cmux-pick: cannot read " .. PROFILES)
      return {}
    end
    local list = data.Profiles or data
    local choices = {}
    for _, p in ipairs(list) do
      choices[#choices + 1] = {
        text    = p.Name or "(unnamed)",
        subText = p.Command or "",
        cmd     = (p["Custom Command"] == "Yes") and p.Command or nil,
        dir     = p["Working Directory"],
      }
    end
    return choices
  end

  -- Enter: open the profile in a brand-new workspace (one clean call).
  local function launchWorkspace(c)
    if not c or not c.text then return end       -- ESC / dismissed / empty
    local a = { "new-workspace", "--focus", "true", "--name", shq(c.text) }
    if c.dir and c.dir ~= "" then a[#a + 1] = "--cwd";     a[#a + 1] = shq(expanduser(c.dir)) end
    if c.cmd and c.cmd ~= "" then a[#a + 1] = "--command"; a[#a + 1] = shq(c.cmd) end
    cmux(table.concat(a, " "))
  end

  -- Cmd+Enter: open the profile as a split in the CURRENT workspace.
  -- new-split has no --command, so split then send the command line.
  local function launchSplit(c)
    if not c or not c.text then return end
    local cw  = cmux("current-workspace")
    cw = cw and cw:match("workspace:%d+")
    local out = cmux("new-split " .. SPLIT .. " --focus true"
                     .. (cw and (" --workspace " .. cw) or ""))
    local sid = out and out:match("surface:%d+")
    if not sid then return end                   -- cmux() already alerted

    local parts = {}
    if c.dir and c.dir ~= "" then parts[#parts + 1] = "cd " .. shq(expanduser(c.dir)) end
    if c.cmd and c.cmd ~= "" then parts[#parts + 1] = c.cmd end
    if #parts > 0 then
      hs.timer.usleep(350000)                    -- split -> shell ready
      cmux("send --surface " .. sid .. " " .. shq(table.concat(parts, " && ") .. "\n"))
    end
  end

  local picker = hs.chooser.new(launchWorkspace)
  picker:searchSubText(true)                     -- typing also matches Command/host
  picker:placeholderText("Search Profiles      ↵ new workspace   ⌘↵ split tab")

  -- Cmd+Return = alternate action. hs.chooser can't report modifiers in its
  -- callback, so intercept the keystroke while the chooser is open.
  local RETURN = hs.keycodes.map["return"]
  local altTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if not picker:isVisible() then return false end
    local f = e:getFlags()
    if e:getKeyCode() == RETURN and f.cmd and not (f.alt or f.ctrl or f.shift) then
      local c = picker:selectedRowContents()
      picker:hide()                              -- does not fire the completion cb
      launchSplit(c)
      return true                                -- swallow; don't let Enter fire too
    end
    return false
  end)
  altTap:start()

  local function show()
    picker:choices(loadProfiles())               -- re-read each summon (live updates)
    picker:query("")
    picker:show()
  end

  if GLOBAL then
    M._hk = hs.hotkey.bind(MODS, KEY, show)
  else
    -- Bind the hotkey only while cmux is frontmost (passes through everywhere else).
    local hk = hs.hotkey.new(MODS, KEY, show)
    local wf = hs.window.filter.new(APP)
    wf:subscribe(hs.window.filter.windowFocused,   function() hk:enable()  end)
    wf:subscribe(hs.window.filter.windowUnfocused, function() hk:disable() end)
    M._hk, M._wf = hk, wf                         -- keep refs alive (avoid GC)
  end

  M._picker, M._tap = picker, altTap             -- keep refs alive
  return M
end

return M
