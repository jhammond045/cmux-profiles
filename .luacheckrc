-- Hammerspoon injects `hs`; Spoons are reachable via `spoon`.
std = "max"
read_globals = { "hs", "spoon" }
max_line_length = 120
-- CI installs luacheck into ./.luarocks in the workspace; don't lint vendored code.
exclude_files = { ".luarocks" }
