#!/usr/bin/env bash
# Films the title's shots (core:cinematic/title) from the live vista and encodes the title's filmed
# country, game/assets/video/title_reel.ogv (TitleReel: what Low and Medium show behind the menu).
#
#   tools/title_reel.sh [--fps=12] [--play-fps=24] [--size=1280x720] [--quality=5] [--shots=N] [--keep]
#                       [--renderer=gl_compatibility|forward_plus] [--frames=<dir>]
#
# Drawn under xvfb. Here (no GPU) only the Compatibility renderer draws Terrain3D, so that is the
# default; on a machine with a GPU, `--renderer=forward_plus` films it as Forward+ draws it. Each
# shot is filmed whole at --fps with the engine's fixed frame time, then dipped in and out to the
# menu's dark as the live vista dips (TitleVista.DIP_IN_S, DIP_OUT_S), and the shots are joined.
# The software renderer here draws a frame of the title's country in about 6 s, so it is filmed at
# --fps (12) and played at --play-fps (24), the frames between made by ffmpeg's motion-compensated
# interpolation, which the title's slow, steady camera moves suit. A machine with a GPU can film
# --fps=24 directly.
# GODOT names Godot, as for run.sh. --frames=<dir> skips the filming and encodes frames already
# there. --keep keeps the frames.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
fps=12; play_fps=24; size=1280x720; quality=5; shots=""; keep=0; renderer=gl_compatibility; frames=""
for a in "$@"; do
  case "$a" in
    --fps=*) fps="${a#--fps=}" ;;
    --play-fps=*) play_fps="${a#--play-fps=}" ;;
    --size=*) size="${a#--size=}" ;;
    --quality=*) quality="${a#--quality=}" ;;
    --shots=*) shots="${a#--shots=}" ;;
    --keep) keep=1 ;;
    --renderer=*) renderer="${a#--renderer=}" ;;
    --frames=*) frames="${a#--frames=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
out="$ROOT/game/assets/video/title_reel.ogv"
mkdir -p "$(dirname "$out")"
if [ -z "$frames" ]; then
  frames="$(mktemp -d "${TMPDIR:-/tmp}/title_reel.XXXXXX")"
  driver=opengl3; [ "$renderer" = forward_plus ] && driver=vulkan
  extra=(); [ -n "$shots" ] && extra+=("--shots=$shots")
  xvfb-run -a -s "-screen 0 ${size}x24" "$GODOT" --path "$ROOT/game" --rendering-driver "$driver" \
    --rendering-method "$renderer" --audio-driver Dummy --resolution "$size" --fixed-fps "$fps" \
    res://tools_gd/title_film.tscn -- "--out=$frames" --preset=high "--video=$fps" "${extra[@]}" \
    | grep "TITLE_FILM" || true
fi
report="$frames/title_film.json"
[ -f "$report" ] || { echo "no $report: the film did not run to the end" >&2; exit 1; }
# one segment per shot, each dipped in and out of the dark, then joined
python3 - "$report" "$frames" "$fps" "$quality" "$out" "$play_fps" <<'EOF'
import json, subprocess, sys, os
report, frames, fps, quality, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
play_fps = max(int(sys.argv[6]), fps)
reel = json.load(open(report))["reel"]
dark = reel["dark"]
parts = []
for i, shot in enumerate(reel["shots"]):
    n = shot["frames"]
    dur = n / fps
    seg = os.path.join(frames, "seg_%02d.mkv" % i)
    vf = ("minterpolate=fps=%d:mi_mode=mci:mc_mode=aobmc:me_mode=bidir," % play_fps if play_fps > fps else "")
    vf += ("fade=t=in:st=0:d=%.2f:color=%s,fade=t=out:st=%.2f:d=%.2f:color=%s"
          % (reel["dip_in_s"], dark, dur - reel["dip_out_s"], reel["dip_out_s"], dark))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(fps), "-start_number", str(shot["first"]),
                    "-i", os.path.join(frames, "v_%05d.jpg"), "-vf", vf, "-frames:v", str(n * play_fps // fps),
                    "-c:v", "ffv1", seg], check=True)
    parts.append(seg)
lst = os.path.join(frames, "parts.txt")
with open(lst, "w") as f:
    for p in parts:
        f.write("file '%s'\n" % p)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst,
                "-c:v", "libtheora", "-q:v", quality, "-g", str(play_fps * 4), "-an", out], check=True)
print("title_reel: %s, %d shots, %.1f s, %.1f MB" % (out, len(parts),
      sum(s["frames"] for s in reel["shots"]) / fps, os.path.getsize(out) / 1e6))
EOF
if [ "$keep" = 0 ]; then
  find "$frames" -maxdepth 1 -type f -delete
  rmdir "$frames"
fi
