#!/usr/bin/env bash
# Downloads the Godot editor (Linux, x86_64) to /usr/local/bin/godot and the named members of its
# export templates into Godot's template folder, at GODOT_VERSION. Used by
# .github/workflows/game-build.yml; any member not named is not unpacked (the .tpz is 1.3 GB).
#
#   GODOT_VERSION=4.7.2 tools/release/get_godot.sh [template member ...]
#   e.g. tools/release/get_godot.sh windows_release_x86_64.exe macos.zip
set -eu
v="${GODOT_VERSION:?set GODOT_VERSION}"
base1="https://github.com/godotengine/godot-builds/releases/download/${v}-stable"
base2="https://github.com/godotengine/godot/releases/download/${v}-stable"
fetch() { curl -fsSL --retry 3 -o "$2" "$base1/$1" || curl -fsSL --retry 3 -o "$2" "$base2/$1"; }

fetch "Godot_v${v}-stable_linux.x86_64.zip" godot.zip
unzip -q godot.zip && mv "Godot_v${v}-stable_linux.x86_64" /usr/local/bin/godot && rm godot.zip
godot --version

if [ "$#" -gt 0 ]; then
  fetch "Godot_v${v}-stable_export_templates.tpz" templates.tpz
  dest="$HOME/.local/share/godot/export_templates/${v}.stable"
  mkdir -p "$dest"
  members=("templates/version.txt")
  for m in "$@"; do members+=("templates/$m"); done
  unzip -q -j templates.tpz "${members[@]}" -d "$dest"
  rm templates.tpz
  ls -la "$dest"
fi
