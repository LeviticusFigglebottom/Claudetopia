# Sourced by every script here that launches Godot for a test, a measurement or a tool run:
#
#   source "$ROOT/tools/godot_env.sh"
#
# It gives this checkout a user:// of its own. Godot keeps user:// at
# $XDG_DATA_HOME/godot/app_userdata/<project name> on Linux, and every worktree of this repository
# is the same project, "Wickmere", so they all shared ~/.local/share/godot/app_userdata/Wickmere:
# one agent's run that wrote settings.cfg changed every other agent's (on 2026-09-25 a write of
# play_opening=false failed every branch's flow at "a new game plays the opening"), and saves, logs
# and user packs leaked between them the same way. The checkout's is <repo>/.godot_user (ignored),
# and it starts empty: Settings then runs on its shipped DEFAULTS, and nothing is copied from the
# shared folder. WICKMERE_USER_HOME names another.
#
# Only runs for tests and tools: `./run.sh` alone (playing the game) keeps the player's own
# settings and saves. On Windows and macOS Godot does not read XDG_DATA_HOME; this is for Linux.

_wickmere_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_DATA_HOME="${WICKMERE_USER_HOME:-$_wickmere_root/.godot_user}"
mkdir -p "$XDG_DATA_HOME"
WICKMERE_USER_DIR="$XDG_DATA_HOME/godot/app_userdata/Wickmere"

# A run that must start from the shipped settings (the flow, the suite) takes the checkout's own
# settings.cfg away first, so a setting an earlier run of this checkout changed cannot change it.
wickmere_default_settings() {
  if [ -f "$WICKMERE_USER_DIR/settings.cfg" ]; then
    unlink "$WICKMERE_USER_DIR/settings.cfg"
  fi
}
