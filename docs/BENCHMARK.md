# The built-in benchmark

The game times itself on a fixed path and writes what it measured to a file, so a run on one
machine can be compared with a run on another, or with the same machine after a change. It is
`game/tools_gd/benchmark.gd`.

## What it does

About three minutes, without anyone touching anything:

1. **The title** for 14 s, with whatever is behind its menu on this machine: the live country, the
   filmed one, or the drawn chart.
2. **The Naming** for 10 s, the figure turning and the portrait closing in on the face and out again.
3. **The world**, stood up as the title stands it (no body, no people), then five stops. At each,
   the country is streamed in first, then the camera flies a fixed line for 12 s while it is timed:
   - `town`: Merrowby's street and market at a walk, by day;
   - `greatwood`: over and into the Briarwold's Greatwood;
   - `open_country`: the Hearthvale from a height, the long view west;
   - `large_site`: round Tinehold, the castle ruin under the Tine Tower;
   - `town_night`: a Cinderlea street by night, its lamps lit.

By default it does not hold the frame rate back: vsync and every frame cap are off while it runs,
so the numbers are what the machine can do. It draws with the player's graphics settings, or with
the preset a first launch would be given if nothing has been saved yet.

## Running it on Windows

From a Command Prompt or PowerShell in the folder with `Wickmere.exe`:

    Wickmere.exe -- --benchmark

It quits by itself when it is done. To time a preset other than the saved one, for this run only
(settings.cfg is not changed):

    Wickmere.exe -- --benchmark --benchmark-preset=medium

`low`, `medium`, `high` and `painted` are the presets. Two more switches:

- `--benchmark-paced` keeps the player's vsync and frame cap, to see what a player sees;
- `--benchmark-quick` runs every segment at 40 % of its length, for a quick look.

From inside the game: on the title screen, press **Ctrl+Shift+B**. The benchmark runs, then comes
back to the title and says where it wrote the report.

## The report

Two files per run, named by the time it started:

    %APPDATA%\Godot\app_userdata\Wickmere\benchmark\benchmark_<date>_<time>.txt
    %APPDATA%\Godot\app_userdata\Wickmere\benchmark\benchmark_<date>_<time>.json

(`~/.local/share/godot/app_userdata/Wickmere/benchmark/` on Linux.) Settings, "Open log folder"
opens the folder beside it.

The text file has:

- the machine: GPU, vendor and kind (integrated or discrete), driver, renderer and API, CPU, RAM;
- the window and the settings it ran with: the preset, render scale and upscaler, MSAA, shadows,
  SSAO, view distance, the title's live country, the distant ground;
- the preset this GPU would be recommended;
- a table, one row a segment: frames, average fps, frame time p50, p95, p99 and max (ms), frames
  over 50 ms and over 100 ms (hitches a player feels), and draw calls and primitives, mean and max;
- the worst hitches of each segment.

The JSON has the same numbers for a script to read. Send both.

## Reading it

- **p50** is the typical frame, **p95** and **p99** the rough ones, and **max** the worst.
  16.7 ms is 60 fps and 33.3 ms is 30.
- Frames **over 50 ms** are the stutters a player notices. Some on the first second of a stop are
  the country's last pieces arriving; many all through a segment is the machine.
- **Draws** and **primitives** say how much is asked of the GPU. The game's budget is 2000 draw
  calls and 1.5 M primitives at 1080p (DESIGN §11). They depend on the settings and the place, not
  the GPU, so two machines on the same preset should show the same counts.
- The title's and the Naming's rows are where a weak GPU used to lag before the game began.

## On the build machine

The build machine has no GPU (Mesa's llvmpipe draws in software), so a run there checks only that
the benchmark goes through and writes its report; its frame times say nothing about a player's
machine. Its draw and primitive counts are real.

    xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
      --audio-driver Dummy --resolution 1280x720 -- --benchmark --benchmark-quick
