Wickmere for the Mac, built from commit @COMMIT@.

ONE APP FOR EVERY MAC
Wickmere.app runs natively on Apple Silicon (M1 and later) and on Intel Macs. It needs
macOS 10.15 or later; the full terrain needs macOS 15 (Sequoia) or later, and an older
macOS draws a coarser ground and says so on the title screen. A Mac from about 2018 or
later with 8 GB of memory is the least to expect; Apple Silicon plays best.

INSTALL
Drag Wickmere.app to your Applications folder (or anywhere you like).

THE FIRST TIME YOU OPEN IT
Wickmere is not notarized by Apple, so macOS will not open it the first time and says
it "could not verify Wickmere is free of malware". It is safe to go on; do this once:

  macOS 15 (Sequoia) or later:
    1. Double-click Wickmere and click Done.
    2. Open System Settings > Privacy & Security and scroll down to Security.
    3. Next to "Wickmere was blocked...", click Open Anyway, then Open Anyway again
       (and your password or Touch ID if asked).

  macOS 14 or older:
    Control-click (or right-click) Wickmere, choose Open, then click Open.

  Or, on any macOS, in Terminal:
    xattr -dr com.apple.quarantine /Applications/Wickmere.app
  then open it as usual.

After that it opens like any other app.

THE FIRST LAUNCH IS SLOWER
The first time, your Mac compiles the game's shaders for its graphics chip; the title
may take a minute or two to show its country. Later launches reuse them.

SAVES, SETTINGS AND LOGS
  ~/Library/Application Support/Godot/app_userdata/Wickmere/
The logs are in its logs folder (Settings > Open log folder opens it). In Finder, choose
Go > Go to Folder... and paste the path above. When reporting a problem, send
logs/wickmere.log.

IF SOMETHING GOES WRONG
- "Wickmere is damaged and can't be opened": the zip was unpacked by a program that
  lost the app's signature. Unpack it again by double-clicking the zip in Finder, or
  run the xattr command above.
- A black or broken picture on an Apple Silicon Mac: select Wickmere.app in Finder,
  choose File > Get Info, tick "Open using Rosetta", and open it again (this uses the
  Intel copy of the game and its Vulkan renderer), then tell us.
