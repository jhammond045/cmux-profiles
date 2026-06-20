#!/usr/bin/env bash
# cmux-pick installer: link the Spoon into ~/.hammerspoon/Spoons, seed a config,
# and add the loader to your init.lua. Idempotent — safe to re-run.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS="$HOME/.hammerspoon"
SPOONS="$HS/Spoons"
CFG="$HOME/.config/cmux-pick"

mkdir -p "$SPOONS" "$CFG"

ln -sfn "$SRC/CmuxPick.spoon" "$SPOONS/CmuxPick.spoon"
echo "linked  $SPOONS/CmuxPick.spoon -> $SRC/CmuxPick.spoon"

if [[ ! -e "$CFG/profiles.json" ]]; then
  cp "$SRC/examples/profiles.example.json" "$CFG/profiles.json"
  echo "seeded  $CFG/profiles.json  (edit this — or symlink it to your own profiles)"
else
  echo "kept    $CFG/profiles.json  (already exists)"
fi

LOADER='hs.loadSpoon("CmuxPick"):start()'
if [[ -f "$HS/init.lua" ]] && grep -qF 'loadSpoon("CmuxPick")' "$HS/init.lua"; then
  echo "loader  already present in $HS/init.lua"
else
  printf '\n%s\n' "$LOADER" >> "$HS/init.lua"
  echo "added   loader to $HS/init.lua"
fi

cat <<'EOF'

Next:
  1. In cmux: Settings -> enable socket access for external processes
     (CMUX_SOCKET_MODE = automation). Required, or launches fail with exit 15.
  2. Reload Hammerspoon (menu bar -> Reload Config, or run hs.reload()).
  3. Focus cmux and press Cmd+O.  Enter = new workspace,  Shift+Enter = split.

Done.
EOF
