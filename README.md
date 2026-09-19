# Wickmere

An original open-world action RPG built in Godot 4.7. Warm villages that
remember you, wild country between them, and old deep places where the world has
gone quiet.

* `DESIGN.md` — game bible · `WORLD_BIBLE.md` — world bible
* `ARCHITECTURE.md` — how the code is organised · `PROGRESS.md` — state & next
* `DECISIONS.md` — why · `LICENSES.md` — third-party assets

## Run

```
./run.sh          # builds world data if missing, then runs the game
./run.sh test     # unit tests + smoke run
./run.sh shots    # headless fly-through captures into captures/
```

Requirements: Godot 4.7.2 (`GODOT` env var or `godot` on PATH), Python 3.11+
with numpy/pillow (`pip install -r tools/requirements.txt`). Blender 4.x is only
needed to regenerate meshes.
