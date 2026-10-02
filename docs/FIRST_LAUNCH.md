# First launch: no deadlock, shaders baked into the build

## The freeze was a deadlock

On a first launch the title could hang for good. It was reproduced here on an unbaked build with
an empty user cache, both exported and from the project, 110 s in. The threads, from gdb, with
strings near the return addresses naming the functions:

- Every worker thread is inside a threaded resource load (ResourceLoader, an ArrayMesh's
  surface being added, MeshStorage).
- One worker holds ShaderRD's lock (`version_set_code` / `version_get_shader` in shader_rd.cpp)
  and waits in `_compile_version_end` for that shader's compile. The compile is a group of tasks
  on the same worker pool, and the wait does not run other tasks.
- The other workers wait for that lock.
- The main thread, drawing (`SceneShaderForwardClustered::_get_shader_variant`), waits for the
  same compile.
- No thread is left to compile.

The world streamer asked the loader for a hundred assets at once, so every worker had one. When
the cache is warm (a second launch) or baked, a shader loads from the cache without a compile
group, nothing waits, and nothing locks up. That is why it was only ever the first launch.

**The fix is in the game's code.** Every `load_threaded_request` goes through `ThreadedLoads`
(`game/core/threaded_loads.gd`):
- it hands at most the pool's thread count minus 2 reads to the loader (1 to 4);
- it queues the rest, which read as in progress;
- it reads a queued one on the calling thread if it is taken early.

A compile always has a free thread. The same unbaked first launch then ran to its country without
locking up. Any new threaded read must use `ThreadedLoads`, never `ResourceLoader` directly.

A shader the warm set does not cover still compiles on first use, so baking alone would not have
been enough.

## Shaders: why the first launch is slow

A player's first launch has an empty shader cache. Without baked shaders, every shader the title
and the world use is compiled from source (GLSL to SPIR-V) the first time it is drawn, and the
engine waits for it. The title stands the whole world up behind its menu (`TitleVista`,
`World.warm_layers`), so on a fresh PC all of that happened behind the title, and a player saw the
title freeze. A second launch skips it, because the compiled shaders are in
`user://shader_cache` by then.

## What the build does now

1. **The export bakes.** `game/export_presets.cfg` has `shader_baker/enabled=true`. The baker only
   runs when the exporting editor has a rendering device. **An export made `--headless` bakes
   nothing**, and the pack is the same size as without it. So the Windows build
   (`.github/workflows/game-build.yml`, job `windows`) exports with the editor under `xvfb-run`, on Mesa's
   software Vulkan (lavapipe), with `--rendering-driver vulkan --rendering-method forward_plus`.
   Then `tools/debug/pck_shader_cache.py` fails the job if the pack holds no
   `.godot/shader_cache/` entries, or too few of the materials' ones. By hand:

       xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver vulkan \
         --rendering-method forward_plus --export-release "Windows Desktop" ../build/windows/Wickmere.exe
       python3 tools/debug/pck_shader_cache.py build/windows/Wickmere.pck

   The export takes about three minutes longer. The pack gains about 49 MB of SPIR-V (247
   entries; 170 of them are the materials' SceneForwardClustered shaders).

   Two cautions for a local export:
   - The editor rewrites `game/project.godot` while it runs (it drops the settings that equal
     their defaults), so check that file out again afterwards.
   - The editor keeps its customized resources in `game/.godot/exported/`, and a later export
     reuses them *without baking them again*. A second export here baked only 77 entries. Delete
     that folder before a local baked export. CI starts without it.

2. **The warm set.** The baker compiles only the materials and shaders it finds in exported
   resources. Most of Wickmere's materials are made in code: about a hundred
   `StandardMaterial3D.new()` / `ShaderMaterial.new()` sites, the water's shader with its defines,
   Label3D's own material, and Terrain3D's generated shader. The cache is keyed by a shader's
   source, so a baked entry serves any runtime material whose generated shader is the same.
   `game/assets/shader_warm/warm_set.tres` (a `ShaderWarmSet`) holds one material for every
   feature key the game was seen using. Its textures are shared placeholders, because a
   material's shader depends on which slots are set, not on the pictures in them. Nothing in the
   game loads it; only the export reads it.

3. **The census** (`game/tools_gd/material_census.gd`) writes the warm set. Any run started with
   `-- --material-census=<file.tres>` attaches it (through the Debug autoload). It then walks the
   tree every few seconds and looks at every node as it is added. It collects:
   - material override and overlay;
   - surface override and mesh surface materials, including MultiMesh and particle draw passes;
   - particle process materials;
   - CSG;
   - fog volumes;
   - the sky;
   - CanvasItem materials;
   - Label3D/Sprite3D's built-in material;
   - Terrain3D's shader, as code from the rendering server. Only a drawn run can read it.

   A material's key is made from:
   - its class;
   - every stored bool and enum or int;
   - which texture slots are set;
   - for a ShaderMaterial, its shader's file or a hash of its code.

   Colours, floats and vectors are uniforms and are left out. The water's four shader variants are
   always added, because the reflections setting swaps them.

## When to run `./run.sh shader-warm` again

Run it whenever a change could give the game a shader it has not had before:
- a new `.gdshader`, or a change to how code builds one (the water's defines);
- a new material made in code with a new combination of flags, transparency, shading or cull
  mode, billboard, or texture slots;
- a new particle effect;
- a new kind of Label3D or Sprite3D;
- a Terrain3D setting that changes its shader (auto shader, dual scaling, texture filtering, the
  world background);
- a Godot upgrade (the baked code is the engine's).

Then commit the regenerated `warm_set.tres`.

    ./run.sh shader-warm                 # adds to the set: the title, smoke, flow, fights, journey
    ./run.sh shader-warm --fresh         # starts it again
    ./run.sh shader-warm --only=title    # one part

The parts:
- The title is drawn on Forward+ under xvfb with Vulkan. Here, lavapipe draws the coarse ground,
  because Terrain3D crashes that driver.
- The flow's first way in (a new game's opening) is drawn with OpenGL, and gives Terrain3D's
  shader.
- The smoke (every region, place and interior), the fights and the journey are headless.

A shader the census never saw is still compiled on the player's machine the first time it is
drawn, as before. The set only has to cover what the first minutes use for the first launch to be
smooth.

## Weak graphics: the first launch's preset, the filmed title, the menus' pace

The owner's laptops (an HP G11 with a Ryzen 5 PRO's Radeon iGPU) lagged on the title, the menus
and the Naming until the game began. What a weak machine is given now:

- **A preset for the adapter on the first launch** (`core/hardware_tier.gd`). When settings.cfg
  has no `graphics` section, a player's launch reads the adapter's type, then its name as a hint,
  and the machine's RAM:
  - integrated graphics, or an adapter it does not recognise, gets **Medium**;
  - a software rasterizer, old Intel HD/UHD, AMD Vega or the 610M, or an iGPU with under 8 GB of
    RAM gets **Low**;
  - a graphics card of its own keeps **High**.

  A driver that calls an AMD APU "discrete" is not believed when the name says APU, and on the
  Compatibility renderer, which calls every adapter "other", the name decides. Godot 4.7 cannot
  tell a card's video memory, so that is not used. The startup trace says what was decided:
  `graphics: first launch, <adapter> (...): Medium -- integrated graphics`. Every later launch
  reads `graphics: preset X, the player's`. Settings, Graphics, "Detect recommended" asks again.
  Tools, tests and the benchmark never get a first-launch verdict.
- **Medium upscales with FSR 1** from 0.77 of the window, sharpened (`Graphics.FSR_SHARPNESS`).
  FSR is a shader, so it runs on any GPU, but only under Forward+. On Compatibility, Medium draws
  at 0.85, scaled bilinearly. The menus' words are always drawn at the window's own pixels.
- **The filmed title** (`ui/menus/title_reel.gd`, `game/assets/video/title_reel.ogv`). Low and
  Medium ("Drawn live behind the title" off) play a Theora film of the title's own shots behind
  the menu instead of standing the world up. So does a live title whose first shot draws at a
  median of more than 40 ms a frame (`TitleVista.FRAME_BUDGET_MS`), and one that gives up for
  any other reason. Without the file, the drawn chart stays. `tools/title_reel.sh` films and
  encodes it again (see its header).
- **The menus' pace.** While the title or the Naming is up, with no game behind it, the frame rate
  is held to 60 (30 on Low), or to the player's own lower cap. The game's cap comes back when the
  world takes over.
- **The Naming.** Its portrait is drawn no larger than its rectangle on the screen, at the render
  scale and with the upscaler, with 2x MSAA on Low and Medium (4x above). On Low the hair is drawn
  as its shell instead of its strand cards. While the title is up, the title reads the Naming's
  scene, the body and its stage, and the world's ground textures on loader threads
  (`ui/menus/naming_ahead.gd`). It then draws the body once on a tiny stage off the screen, so its
  pipelines are compiled before New Game is pressed. The title's world is freed when the Naming
  opens, since the scene changes.

## The title's safety nets

On a **software rasterizer** (Mesa's lavapipe, or Windows' WARP on a PC with no graphics driver
installed yet), the title keeps its chart and stands no world up
(`TitleVista.software_renderer()`). Its first frames of the world were each tens of seconds of
pipeline compiles (44, 18, 79 and 30 s on lavapipe here), with the menu frozen under them.

On a real graphics card:

`TitleVista` gives up the country for that visit and keeps the drawn chart if either of these
happens before its first shot:
- one frame takes more than `LONG_FRAME_S` (4 s) while the first shot is first drawn
  (`World.warm_layers`). The world standing up has a known long frame of its own, when the
  provider reads its maps (2.4 s of CPU here), so only the cap covers that;
- more than `FIRST_SHOW_CAP_S` (90 s) pass after the world was asked for.

It logs a warning either way, and logs each warming frame's time. The menu keeps answering. The
next launch tries again, with the shaders this one compiled now in the user cache.

## If the title freezes: what to send

Every launch writes a startup trace, one line per step, flushed to disk as it is written, so a game
killed from the Task Manager still has every line:

    %APPDATA%\Godot\app_userdata\Wickmere\logs\startup_<date>_<time>.txt     (Windows)
    ~/.local/share/godot/app_userdata/Wickmere/logs/startup_<date>_<time>.txt  (Linux)

The last ten are kept. **A tester whose game froze sends the newest `startup_*.txt`**, with the
`session_*_summary.txt` of the same time and `launch_state.json` from the folder above `logs`.
Settings, "Open log folder" opens the folder.

What the trace has (`core/startup_trace.gd`, `core/startup.gd`):
- the machine first: GPU name, vendor and type (integrated, discrete), driver, renderer and API,
  CPU and its threads, RAM and free RAM, the worker pool's size and how many threaded reads it
  allows, the window, the arguments;
- boot, the content, the title's first frame, the title asking for its world;
- each step of the world standing up, begun and done with its milliseconds; inside the terrain
  step, the assets asked for and received, each region file's read begun and ended with the worker
  thread that read it, each `add_region`, `update_maps`, the first terrain frame, the material and
  its shader parameters, and the texture arrays;
- every threaded read asked for, done and taken, until the title's first shot is shown, and a
  line whenever the main thread takes one that is still being read (it waits there);
- the first frame of 3D asked for and drawn, and the title giving its country up;
- every click on the title, and each step of tearing the title's world down;
- memory on every line: the engine's own (static), the video memory the renderer reports (main
  thread lines), and what the machine still has free.

The steps stop being written when a game's world is ready. The **watchdog**, a thread of its own,
writes `WATCHDOG: main thread stalled N s at step "..."` into the same file when the main thread has
not moved for 5 s, and again every 5 s while it stays stopped, with the memory each time, so a hang
shows where it stopped and whether memory is growing. It never touches the scene tree or the
renderer. When the main thread goes on, it writes `main thread went on after N s`.

**The window's X cannot be made to work while the main thread is stuck.** On Windows the close
request is a message to the window, and the window's messages are read by the main thread, so no
other thread can know the X was pressed. Windows itself offers "Close the program" on a window that
has not read its messages for a few seconds. A watchdog killing the game on a stall alone would kill
games that are only slow, so it does not.

## Safe mode

`user://launch_state.json` says how far each launch got: `starting` (written at boot), `stalled`
(written by the watchdog while the main thread is stopped, and put back when it goes on),
`menu_ok` (the title answered for 20 s with its country shown or given up, or a game's world stood
up) and `clean_exit`. A launch that finds `starting` or `stalled` there starts **safely**:
- the coarse ground (`WorldStatus.force_fallback`, as `--terrain=fallback`);
- no country behind the title (the drawn chart);
- one threaded read at a time;
- one line on the title saying so, and that the Graphics settings turn the full terrain back on.

It also turns the Graphics setting "Full terrain and the title's country" off, so it stays off
until the player turns it on: it never switches back behind their back. `-- --safe-mode` asks for
it, `-- --no-safe-mode` skips the check, `-- --terrain=terrain3d` never starts safely. Headless runs,
tools and tests, runs from the editor's debugger, and any run with a tool's argument never check or
write the sentinel.

A debug build takes `-- --debug-stall-terrain=N` to hold the main thread N seconds in the terrain
step, which tests the watchdog and the next launch's safe mode.

## The click that froze the title

The owner reproduced the freeze on a fresh user folder: the title looked fine, and any click froze
the game for good; on the coarse ground (`--terrain=fallback`) it did not. A click tore the title's
world down, and that teardown **waited on the main thread for work on the worker threads**:
- `World._exit_tree` waited for the region-file reads (`wait_for_group_task_completion`);
- `ThreadedLoads.forget` of the terrain's assets waited for their read (`load_threaded_get`): a
  2 s hold here, on a click 2 s after the menu came up;
- the streamer waited for the cells it was reading;
- at quit, `ThreadedLoads.drain` waited for every read still going.

A read of textures on a worker thread can itself wait for the main thread: the rendering device
hands its uploads over at the end of a frame. A main thread waiting for that read never ends its
frame, and nothing moves again. Nothing of this could happen on the coarse ground, which reads no
terrain textures on a thread.

Now nothing the title's world does is waited for when it goes:
- `World.tear_down` stops its streamer and paced stand-up, and lets go of Terrain3D in the provider;
- the region files are read by an object of their own (`World.RegionReads`), and the cells by one
  each (`WorldStreamer.CellRead`), so a world freed while they are read leaves them to finish:
  `ThreadedLoads.after_task` keeps them alive and collects them on a later frame;
- `ThreadedLoads.forget` never waits: a read still going is left to finish and collected;
- the title lets go of every read its world asked for ahead (hundreds of props; a game's world asks
  again);
- a quit waits at most 1.5 s for reads still going, then leaves them.

(Terrain3D 1.0.2 crashes if it is given a null camera on the way out, so it is not.)

The region files are read on at most half the pool's threads past two, never every thread
(`World.region_read_tasks`), and those threads are taken off ThreadedLoads' limit while they are
read, so the two together always leave a compile two threads.

`tools/debug/click_probe.sh` presses a title button at several moments while the country stands
up, one fresh launch each, on the Compatibility renderer, which draws Terrain3D here:

    GODOT=... tools/debug/click_probe.sh --terrain=terrain3d --times="0.5 1 2 4 8" --repeat=2
    GODOT=... tools/debug/click_probe.sh --button=Settings --times="2 8"
    GODOT=... tools/debug/click_probe.sh --times="shown+3"     # after the first shot, caps lifted

It fails a click that held the main thread more than 1 s before the next screen came, any later
frame over 1 s, and any error reported after the click. (The Naming's own first frame is about
1.8 s on llvmpipe with or without a country behind the title; it is reported, not judged.)

## What cannot be done ahead, and what is left

- **Pipelines.** The driver compiles each shader's SPIR-V into GPU code on first draw. That
  result is specific to the GPU and driver (`user://vulkan/`), so it cannot be shipped. Godot's
  ubershaders and background compiles keep most of it off the main thread.
- **D3D12.** If a PC cannot start Vulkan, Godot falls back to Direct3D 12
  (`rendering/rendering_device/fallback_to_d3d12`, on by default). The Linux editor cannot bake
  D3D12 shaders, because its binary has no DXIL container. A PC on D3D12 therefore compiles
  everything on first launch, and relies on `ThreadedLoads` not to lock up. Exporting from a
  Windows runner would bake both. `application/export_d3d12` (the Agility SDK) stays off; nothing
  here needs it.
- **The Mac.** Its Forward+ is Metal on Apple Silicon (MoltenVK on Intel), and the baker bakes
  only for the platform's driver, Metal, which only an editor on a Mac can bake: a Linux export
  put 0 entries in the Mac pack. So the Mac preset does not bake, and a Mac compiles its shaders
  on first launch behind the title, kept from locking up by `ThreadedLoads` (`docs/MAC.md`).
- **Quitting on lavapipe.** Here the game sometimes hung, or once crashed, in the engine's
  cleanup after quitting, with the worker pool idle. This happened before and after these
  changes. It was not seen with OpenGL, and nothing here can say whether a real GPU shows it.

## Measured (2026-09-30, a Linux export on lavapipe, empty user:// and Mesa cache)

All runs have the title's caps off and the software rule lifted (`--cpu-no-vista-caps`), so the
title runs to the end on a software device.

| build | first menu frame | shaders compiled at runtime | country shown | longest frame |
|---|---|---|---|---|
| unbaked, before ThreadedLoads | 6-10 s | - | never: **deadlock** (110 s in from the project; the export also locked up) | - |
| unbaked, first launch | 7.06 s | 110 (43 materials') | 210 s | 72 s |
| unbaked, second launch | 6.25 s | 0 new | 208 s | 67 s |
| baked + warm set, first launch | 5.18 s | 1 | 198 s | 75 s |
| baked + warm set, second launch | 5.38 s | 0 new | 198 s | 68 s |
| baked, as shipped (chart kept on a software device) | 6.17 s | 0 | - | 135 ms (menu, 800 frames) |

The minutes to the country, and the longest frames, are lavapipe compiling pipelines with LLVM:
44 to 79 s per warming frame, cold or warm. Baking does not touch that cost. What baking removes
is the SPIR-V compile of every shader: 110 on an unbaked first launch, and 1 with the warm set.
A real GPU compiles pipelines in milliseconds each, so there the SPIR-V compiles and the deadlock
were what froze the title.
