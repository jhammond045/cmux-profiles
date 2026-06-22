--- === CmuxProfiles ===
---
--- An iTerm2-Profiles-style session launcher for the cmux terminal.
---
--- Reads iTerm2 dynamic-profile JSON and launches profiles through the cmux
--- CLI. Press the hotkey (default Cmd+O, only while cmux is frontmost) to open a
--- fuzzy modal of your profiles:
---   * Enter        -> open the profile in a new workspace
---   * Shift+Enter  -> open it as a split ("tab") in the current workspace
---   * Cmd+E        -> open the profile editor (also the "Edit profiles…" row)
---
--- Download: https://github.com/jhammond045/cmux-profiles

local obj = {}
obj.__index = obj

obj.name     = "CmuxProfiles"
obj.version  = "2.0.0"
obj.author   = "jhammond"
obj.homepage = "https://github.com/jhammond045/cmux-profiles"
obj.license  = "MIT - https://opensource.org/licenses/MIT"

-- directory of this file (to find editor.html)
local SOURCE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)")) or "./"

-- shell single-quote:  ' -> '\''
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- expand a leading ~ (we single-quote paths, so the shell won't do it for us)
local function expanduser(p)
  if type(p) == "string" and p:sub(1, 1) == "~" then
    return os.getenv("HOME") .. p:sub(2)
  end
  return p
end

local function readFile(p)
  local f = io.open(p, "r"); if not f then return nil end
  local s = f:read("a"); f:close(); return s
end

--- CmuxProfiles:start([opts]) -> self
--- Start the launcher. opts (all optional):
---   profiles    profiles JSON path     (default ~/.config/cmux-profiles/profiles.json)
---   app         cmux's macOS app name  (default "cmux")
---   splitDir    down|up|left|right     (default "down")
---   hotkeyMods  modifier table         (default {"cmd"})
---   hotkeyKey   key                    (default "o")
---   global      summon from any app    (default false = only when cmux frontmost)
---   cmuxBin     explicit CLI path      (default: auto-resolve)
function obj:start(opts)
  opts = opts or {}
  local PROFILES = opts.profiles or (os.getenv("HOME") .. "/.config/cmux-profiles/profiles.json")
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
      hs.alert.show("cmux-profiles: cmux CLI not found (install it from cmux Settings)")
      return nil
    end
    local out, ok, _, rc = hs.execute(shq(bin) .. " " .. args, true)
    if not ok then
      hs.alert.show("cmux " .. args .. "  ->  exit " .. tostring(rc) .. "\n" .. (out or ""))
      return nil
    end
    return out or ""
  end

  -- Read the profiles file. Returns (array, wasWrapped) where wasWrapped is true
  -- for {"Profiles":[...]} and false for a bare top-level array.
  local function readProfilesFile()
    local data = hs.json.read(PROFILES)
    if type(data) ~= "table" then return {}, true end
    if data.Profiles then return data.Profiles, true end
    return data, false
  end

  -- Parse profiles for the picker. iTerm2 dynamic-profile JSON or a bare array.
  local function loadChoices()
    local list = readProfilesFile()
    local choices = {
      {
        text    = "\u{270E}  Edit profiles\u{2026}",
        subText = "Add, edit, or remove profiles  (\u{2318}E)",
        action  = "edit",
      },
    }
    for _, p in ipairs(list) do
      local sub = p.Command or ""
      if p.Tags and #p.Tags > 0 then              -- show + make tags searchable
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
      hs.timer.doAfter(0.35, function()           -- non-blocking; split -> shell ready
        cmux("send --surface " .. sid .. " " .. line)
      end)
    end
  end

  ---------------------------------------------------------------------------
  -- Profile editor (hs.webview form)
  ---------------------------------------------------------------------------
  local editorWrapped = true                      -- shape to write back on save

  -- Write the profiles array back, preserving the file's original shape and
  -- keeping a .bak of the previous contents. Writes through a symlink in place.
  local function writeProfiles(arr)
    local prev = readFile(PROFILES)
    if prev then
      local b = io.open(PROFILES .. ".bak", "w")
      if b then b:write(prev); b:close() end
    end
    local out = editorWrapped and { Profiles = arr } or arr
    local f, err = io.open(PROFILES, "w")
    if not f then
      hs.alert.show("cmux-profiles: can't write profiles \u{2014} " .. tostring(err)); return false
    end
    f:write(hs.json.encode(out, true)); f:write("\n"); f:close()
    return true
  end

  -- JS -> Lua bridge: window.webkit.messageHandlers.cmuxprofiles.postMessage({...})
  local ucc = hs.webview.usercontent.new("cmuxprofiles")
  ucc:setCallback(function(msg)
    local body = type(msg) == "table" and msg.body or nil
    if type(body) ~= "table" then return end
    if body.action == "save" then
      local arr = body.profiles or {}
      if writeProfiles(arr) then
        hs.alert.show("cmux-profiles: saved " .. tostring(#arr) .. " profiles")
      end
    elseif body.action == "close" then
      if self._editor then self._editor:delete(); self._editor = nil end
    end
  end)

  local function openEditor()
    local arr, wrapped = readProfilesFile()
    editorWrapped = wrapped
    local html = readFile(SOURCE_DIR .. "editor.html")
    if not html then hs.alert.show("cmux-profiles: editor.html not found"); return end
    local b64 = hs.base64.encode(hs.json.encode(arr))
    html = html:gsub("__PROFILES_B64__", function() return b64 end)

    local fr = hs.screen.mainScreen():frame()
    local w, h = 920, 640
    local rect = { x = fr.x + (fr.w - w) / 2, y = fr.y + (fr.h - h) / 2, w = w, h = h }

    if self._editor then self._editor:delete() end
    local masks = hs.webview.windowMasks
    local wv = hs.webview.new(rect, { developerExtrasEnabled = false }, ucc)
      :windowStyle(masks.titled | masks.closable | masks.resizable)
      :windowTitle("cmux-profiles \u{2014} Profiles")
      :allowTextEntry(true)
      :html(html)
    wv:windowCallback(function(action) if action == "closing" then self._editor = nil end end)
    wv:show():bringToFront(true)
    hs.timer.doAfter(0.05, function()
      local win = wv:hswindow(); if win then win:focus() end
    end)
    self._editor = wv
  end

  ---------------------------------------------------------------------------
  -- Picker
  ---------------------------------------------------------------------------
  local altTap            -- forward decl (captured by onPick, show, tap)
  local splitting = false -- guards against a double-launch if hide() fires onPick

  local function onPick(c)                         -- Enter / click / Esc(nil)
    if altTap then altTap:stop() end
    if splitting then return end
    if c and c.action == "edit" then openEditor(); return end
    launchWorkspace(c)
  end

  local picker = hs.chooser.new(onPick)
  picker:searchSubText(true)                       -- typing matches Command + Tags
  picker:placeholderText("Search Profiles      \u{21A9} workspace   \u{21E7}\u{21A9} split   \u{2318}E edit")

  -- Alternate keys while the modal is open. hs.chooser can't report modifiers
  -- in its callback, so intercept here. (Cmd+Return is swallowed by macOS ->
  -- beep, which is why split is on Shift+Return.)
  local RETURN = hs.keycodes.map["return"]
  local KEY_E  = hs.keycodes.map["e"]
  altTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if not picker:isVisible() then return false end
    local f, kc = e:getFlags(), e:getKeyCode()

    if kc == KEY_E and f.cmd and not (f.shift or f.alt or f.ctrl) then
      picker:hide(); altTap:stop(); openEditor()
      return true
    end

    if kc == RETURN and f.shift and not (f.cmd or f.alt or f.ctrl) then
      local ok, c = pcall(function() return picker:selectedRowContents() end)
      local doSplit = ok and type(c) == "table" and c.text ~= nil and c.action == nil
      if doSplit then splitting = true end
      picker:hide(); altTap:stop()
      if doSplit then
        launchSplit(c)
      elseif not (ok and type(c) == "table" and c.action) then
        hs.alert.show("cmux-profiles: couldn't read selection \u{2014} update Hammerspoon")
      end
      splitting = false
      return true
    end

    return false
  end)

  local function show()
    picker:choices(loadChoices())                  -- re-read each summon (live updates)
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

  self._picker, self._tap = picker, altTap         -- keep refs alive (avoid GC)
  return self
end

return obj
