#!/usr/bin/env bash
# build_when_free.sh OUT LOG [builder args]: a world build that waits its turn on a shared machine.
#
#   tools/world/build_when_free.sh /tmp/w4096 /tmp/w4096.log                  # the atlas world, 4096
#   MEM_GB=4 tools/world/build_when_free.sh /tmp/w1024 /tmp/w1024.log --size 1024
#
# It waits until MEM_GB (default 10) are available by `free -g`, then runs build_measured.py into
# OUT (emptied first), appending everything to LOG; the last line is the wall time and the peak
# resident memory. A full 4096 build of the atlas peaks at about 6.2 GB and took 16 minutes on
# the machine it was written on; 10 GB leaves room for whatever starts meanwhile, and a build the
# OOM killer takes anyway (exit 137) is tried again, up to three times.
#
# With WORLD_BUILD_LOCK set to a path, it also takes turns with other builders: it waits while
# someone else's lock there is under LOCK_STALE_S old (default 2700 s), then holds the lock
# ("<owner> <epoch> <what>", owner WORLD_BUILD_OWNER or host-pid) from queueing to exit. An EXIT
# trap removes it however the script ends; INT, TERM and HUP are turned into exits so it runs.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
if [ $# -lt 2 ]; then
  echo "usage: $0 OUT LOG [build_world.py args]" >&2
  exit 2
fi
out="$1"; log="$2"; shift 2
case "$(cd "$(dirname "$out")" 2>/dev/null && pwd)/$(basename "$out")" in
  /|"$repo"|"$repo"/game*) echo "refusing to build into $out: build outside the checkout, then install_world.sh" >&2; exit 2 ;;
esac
if [ -d "$out" ] && [ -n "$(ls -A "$out")" ] && [ ! -f "$out/world_manifest.json" ]; then
  echo "refusing to empty $out: it is not a world build" >&2
  exit 2
fi
need="${MEM_GB:-10}"
lock="${WORLD_BUILD_LOCK:-}"
me="${WORLD_BUILD_OWNER:-$(hostname)-$$}"
stale_s="${LOCK_STALE_S:-2700}"

available_gb() { free -g | awk '/Mem/{print $7}'; }
lock_owner() { awk '{print $1}' "$lock" 2>/dev/null; }
lock_age() { echo $(( $(date +%s) - $(awk '{print $2}' "$lock" 2>/dev/null || echo 0) )); }

if [ -n "$lock" ]; then
  while [ -f "$lock" ] && [ "$(lock_owner)" != "$me" ] && [ "$(lock_age)" -lt "$stale_s" ]; do
    echo "[lock] $(date +%H:%M:%S) held by $(lock_owner) for $(lock_age) s: $(cut -d' ' -f3- "$lock" 2>/dev/null); waiting 60 s" >> "$log"
    sleep 60
  done
  release() {
    if [ -f "$lock" ] && [ "$(lock_owner)" = "$me" ]; then
      rm -f "$lock"
      echo "[lock] $(date +%H:%M:%S) released" >> "$log"
    fi
  }
  trap release EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  echo "$me $(date +%s) queued: build into $out" > "$lock"
  echo "[lock] $(date +%H:%M:%S) taken" >> "$log"
fi

rc=1
for attempt in 1 2 3; do
  while [ "$(available_gb)" -lt "$need" ]; do
    echo "[build] $(date +%H:%M:%S) $(available_gb) GB available, $need wanted; waiting 60 s" >> "$log"
    sleep 60
  done
  if [ -n "$lock" ]; then echo "$me $(date +%s) building into $out" > "$lock"; fi
  echo "[build] $(date +%H:%M:%S) attempt $attempt, $(available_gb) GB available, building into $out" >> "$log"
  rm -rf "$out"
  mkdir -p "$out"
  python3 "$here/build_measured.py" --out "$out" "$@" >> "$log" 2>&1
  rc=$?
  echo "[build] $(date +%H:%M:%S) rc=$rc" >> "$log"
  if [ "$rc" -ne 137 ]; then break; fi
done
exit $rc
