# Wickmere on the Mac

## Playing it

**Download.** Open the repository's Releases (on the right of its page on GitHub): `nightly` is
main, `playtest` is a branch built by hand, and a `v*` release is a tagged version. Download
`Wickmere-macos-<commit>.zip`. If the release has `Wickmere-macos-<commit>.zip.part00`, `part01`
and so on instead (a zip over 2 GB), download every part into one folder and join them in
Terminal there: `cat Wickmere-macos-<commit>.zip.part* > Wickmere-macos-<commit>.zip`.

**Install.** Double-click the zip in Finder. It unpacks `Wickmere.app` and a `README.txt`. Drag
`Wickmere.app` to Applications. Use Finder (Archive Utility) or `ditto -x -k` to unpack it: some
other unpackers drop the app's signature, and macOS then says the app "is damaged".

**The first time you open it.** The app is signed ad hoc and not notarized by Apple, so
Gatekeeper stops it the first time with "Apple could not verify 'Wickmere' is free of malware".
Do this once:

- **macOS 15 (Sequoia) or later.** Double-click Wickmere and click **Done**. Open System Settings
  > Privacy & Security and scroll down to Security. Next to "Wickmere was blocked…", click **Open
  Anyway**, then **Open Anyway** in the dialog (with your password or Touch ID if asked). macOS 15
  dropped the Control-click → Open way round.
- **macOS 14 or older.** Control-click (or right-click) Wickmere, choose **Open**, then **Open**.
- **Any macOS, in Terminal:** `xattr -dr com.apple.quarantine /Applications/Wickmere.app`, then
  open it as usual. This clears the download's quarantine flag, so Gatekeeper never asks.

After that it opens like any other app. A new download of a later build asks again.

**Requirements.**

| | |
|---|---|
| Macs | Apple Silicon (M1 and later) natively, and Intel Macs: `Wickmere.app` is one universal app |
| macOS | 10.15 (Catalina) or later to run; **macOS 15 (Sequoia) or later for the full terrain** |
| Graphics | Metal on Apple Silicon; Vulkan through MoltenVK (built into the app) on Intel |
| Memory | 8 GB at least; 16 GB plays better |

The full terrain is drawn by Terrain3D 1.0.2, and its macOS framework is built for macOS 15 or
later (its `LC_BUILD_VERSION`). On an older macOS the game draws the coarse ground from the 8 m
height map, and the title screen says why (`game/world/world_status.gd`, README "Which machines
draw the full terrain").

**The first launch is slower.** A Mac compiles the game's shaders for its GPU on the first launch
(see below), so the title can take a minute or two to show its country. Later launches read them
from the cache.

**Saves, settings and logs** live in
`~/Library/Application Support/Godot/app_userdata/Wickmere/`. The logs are in its `logs` folder:
`wickmere.log` (the game's log), `godot.log` (the engine's) and a session's error files. Settings >
**Open log folder** opens that folder in Finder, and its tooltip shows the path. In Finder, Go > Go
to Folder… takes the path too. Deleting the folder resets the game, saves included.

**Controls on a Mac.**
- **Dodge is Control.** Godot turns Control-click into a right-click on the Mac, as macOS does
  elsewhere, so a light attack clicked while Control is held arrives as the right button. Dodge is
  a tap, so this rarely matters. Rebind it in Settings > Controls if it does.
- **Lock on is the middle mouse button**, which a trackpad has not got. Rebind it (Settings >
  Controls) to a key when playing on a trackpad. A two-finger click is the right button.
- **F5, F9 and F12** need the **fn** key on most Mac keyboards, unless "Use F1, F2, etc. keys as
  standard function keys" is on (System Settings > Keyboard).
- Walk is **Option** (Alt).
- ⌘Q quits, and ⌘H hides the game, as in any Mac app.

**If the picture is black or broken on an Apple Silicon Mac,** select `Wickmere.app` in Finder,
choose File > Get Info, tick **Open using Rosetta** and open it again. That runs the Intel half of
the app, which draws with Vulkan through MoltenVK instead of Metal. Then say so in a report, with
`logs/godot.log`.

## How the Mac build is made

`.github/workflows/game-build.yml`, job `macos`, on an ubuntu runner (a macOS runner costs ten
times the minutes). By hand:

    tools/release/get_godot.sh macos.zip          # or fetch macos.zip from the 4.7.2 .tpz yourself
    python3 tools/release/macos_template.py       # once per template folder; see "Universal" below
    godot --headless --path game --export-release "macOS" ../build/macos/Wickmere.zip
    python3 tools/release/macos_check.py build/macos/Wickmere.zip

The editor rewrites `game/project.godot` while it runs: check it out again afterwards.

**What the zip holds** (checked by `tools/release/macos_check.py`, 2026-09-30):

    Wickmere.app/Contents/Info.plist                         com.wickmere.game, games, high-res
    Wickmere.app/Contents/MacOS/Wickmere                     universal: x86_64 + arm64, signed ad hoc
    Wickmere.app/Contents/Frameworks/libterrain.macos.release.framework/
        libterrain.macos.release                             universal, signed ad hoc
        Resources/Info.plist                                 made by the export
        _CodeSignature/CodeResources
    Wickmere.app/Contents/Resources/Wickmere.pck             the game (1.3 GB)
    Wickmere.app/Contents/Resources/icon.icns, PrivacyInfo.xcprivacy
    Wickmere.app/Contents/_CodeSignature/CodeResources       the bundle's seal
    README.txt                                               tools/release/README-macos.txt

The zip is about 0.97 GB, under GitHub's 2 GiB limit for a release file.

**The preset** ("macOS", `preset.1` in `game/export_presets.cfg`) has the Windows preset's export
filters (`include_filter`, `exclude_filter`, `script_export_mode`). It uses bundle id
`com.wickmere.game`, category Games and high-res. It declares the oldest macOS Godot 4.7's
Forward+ runs on: 10.15 for Intel (Vulkan through MoltenVK needs it) and 11.0 for Apple Silicon.
It asks for no microphone, camera or other entitlements except one: *disable library validation*.
An ad hoc signed app needs it to load the Terrain3D framework, and Godot adds it anyway.

**Signing.** A Linux export can only sign ad hoc (`codesign/codesign=1`, Godot's built-in signer),
with no notarization. Every Mach-O in the bundle is signed, which Apple Silicon requires to run
anything, and the bundle is sealed. What the player must do on first open is above. Real signing
and notarization would need an Apple Developer ID ($99 a year) and either a macOS runner or
`rcodesign` with the certificate and an App Store Connect API key as repository secrets
(`notarization/*` in the preset). With those, the first-open step would go away.

**Universal, without ETC2/ASTC textures.** Godot's macOS export refuses the `universal` and `arm64`
architectures unless the project imports ETC2/ASTC textures. Wickmere imports only S3TC/BPTC.
Turning ETC2/ASTC on would re-import its ~1,600 VRAM-compressed textures, rewrite every `.import`
file, add roughly an hour of ASTC encoding to a cold CI import, and add about 340 MB to the cache
and the Mac pack. Every Apple Silicon GPU reads BC (S3TC/BPTC) textures: Godot's Metal driver asks
Metal's `supportsBCTextureCompression` and uses them. Intel Macs, and Rosetta, read them through
MoltenVK.

So the preset asks for `x86_64`, which needs only S3TC/BPTC, and
`tools/release/macos_template.py` adds `godot_macos_{release,debug}.x86_64` to the official
`macos.zip` template as copies of its universal binaries. The export then writes and signs a
universal executable. Without that script, the export stops with "Requested template binary
'godot_macos_release.x86_64' not found". If this is ever unwanted, there are two ways out:
- turn on `rendering/textures/vram_compression/import_etc2_astc` and set the preset to
  `universal`, which costs the above;
- or ship Intel-only, and Apple Silicon runs it under Rosetta.

**Renderer.** The project's `renderer/rendering_method` is `forward_plus` for every desktop, so a
Mac gets Forward+. On Apple Silicon, Godot 4.7 draws it with **Metal**
(`rendering/rendering_device/driver.macos` defaults to `metal`). The template's x86_64 half is
built without Metal (only its arm64 half has `RenderingDeviceDriverMetal`), so an Intel Mac, or
Rosetta, draws Forward+ with **Vulkan through MoltenVK**, which is linked into the binary. If
neither starts, Godot falls back to the Compatibility renderer (OpenGL; `fallback_to_opengl3`,
Godot's default, left on), as it does on Windows.

**Shaders are not baked for the Mac.** The export's shader baker bakes for the platform's
configured driver. For macOS that is Metal, and only an editor running on macOS can bake Metal
shaders. An export under xvfb with lavapipe, as the Windows one is made, baked 0 entries into the
Mac pack (checked with `tools/debug/pck_shader_cache.py`, 2026-09-30). So the preset has
`shader_baker/enabled=false`, and the Mac export runs headless, which is quicker.

On a Mac's first launch every shader the title and the world use is compiled from source, as
Windows did before the bake (`docs/FIRST_LAUNCH.md`). `ThreadedLoads` keeps a worker thread free
for the compiles, so that launch is slow but cannot deadlock. The title's safety nets (the long
frame and first-show caps) keep the menu answering. The compiled shaders stay in `user://` for the
next launch. Baking for the Mac would need the export to run on a macOS runner.

**The smoke test** (`mac-smoke`, off by default: Run workflow with `mac_smoke` ticked) takes the
built zip to a `macos-15` Apple Silicon runner. It uses macOS 15 because that is Terrain3D's
floor. There it:
- unpacks the zip with `ditto`;
- runs `codesign --verify --deep --strict`, `lipo -info`, and `spctl` (which only logs the
  expected refusal);
- starts a new game headless twice, natively and under Rosetta, using `tools/release/mac_smoke.sh`.

The exported game has no smoke runner (`tests/` is not exported), and a release build ignores
`--script`. So the pass is the world's own log line, `[World] ready: terrain=terrain3d`. It proves
that the Terrain3D framework loaded on a real Mac, that its classes read their regions from the
pack, and that the world stood up. Its logs are uploaded as `mac-smoke-logs`.

**What only a real Mac with a screen can check:**
- that Metal draws the game;
- that BC textures show on Apple Silicon;
- the first-launch shader compile time;
- the Gatekeeper steps above, as a player meets them;
- the controls on a trackpad.

The CI runners have no GPU, and the smoke test is headless.
