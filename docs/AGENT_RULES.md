# Rules for every area agent on Wickmere

You are one of eleven area agents running at once on one machine: **4 cores, 15 GB RAM, ~23 GB
free disk.** The previous coordinating session ran the same team on the same kind of machine and
lost work to the OOM killer, to a container restart, and to a usage limit. These rules exist
because of that.

## Where you work
- Your worktree is `/home/user/Claudetopia/.claude/worktrees/<area>`, on the local branch
  `wip/<area>`. **Main has already been merged into it** (main = `dc2a749a`, the other session's
  final head, which is also this session's integration branch `claude/gifted-brahmagupta-29u39r`).
- Work only in your own worktree. Never edit another area's worktree or the main checkout at
  `/home/user/Claudetopia`.
- First thing, seed your import cache from main's (already imported and checked):
  `./run.sh seed-import /home/user/Claudetopia` (run from your worktree root).

## Read before you start
- `HANDOFF.md` (the whole thing is worth it; your area's §6 subsection is essential) and §7–§8.
- The newest `PROGRESS.md` section for your area, and `git log --no-merges -20` on your branch.

## Git
- **Commit locally, often.** A container restart already cost this project unverified work twice.
  Unfinished work is committed with a subject starting `WIP:` and a body saying what is not done.
- **Never push.** Never switch branches. Never `git stash` (shared across worktrees; make a WIP
  commit instead). Never rebase or amend commits that came from someone else.
- Stage **by name**. Never `git add -A` / `git add .`. Never commit symlinks.
- Never commit `game/world/generated` or `game/terrain_data` — only the coordinator commits world
  data, from the main checkout, after a rebuild. Before committing, `git status` must not list them.
- Don't commit Godot `.import` churn that no change of yours needs.
- End every commit message with exactly these two lines (no model names anywhere else — not in
  code, docs, commit subjects or comments):

      Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
      Claude-Session: https://claude.ai/code/session_0112mWM76VHFrF6Lkz5ygd61

- Commit subjects are sentences about what is now true. PROGRESS/DECISIONS entries say what was
  measured, not what was hoped. Append your PROGRESS section at the end of the file only.

## Sharing the machine (this is the part that bit last time)
- Scratch space: `$SCRATCH/<area>/ (the session's scratchpad directory)`.
  Delete superseded builds and captures as you go.
- **Before any Godot run:** `free -g` must show ≥ 3 GB available (≥ 4 GB for the full suite,
  flow, journey or captures). If it doesn't, wait (`sleep 60` in a loop, up to 20 min) — don't
  pile on.
- **Run one Godot process of your own at a time.** Prefer `./run.sh test --filter=<name>` over the
  full suite while iterating; run the full suite, journey and flow only before a hand-back.
- **Blender:** one at a time on the whole machine. Take `$SCRATCH/BLENDER.lock` (write
  `<area> <epoch> <what>`), release it when done; if it exists and is under 45 min old, wait.
- **World builds:** take `$SCRATCH/WORLD_BUILD.lock` the same way (HANDOFF §8). While it exists
  and is under 45 min old, start no new Godot or Blender run. A 4096 build needs ~10 GB free;
  1024 previews (~0.6 GB) are what agents should normally use.
- **The lock is for one build, not a session.** Its holder runs **one** build at a time, releases
  the lock when that build ends, and leaves **at least 20 minutes** before taking it again, so the
  others get a window. Looking at a finished build (renders, shots) happens outside the lock. Two
  back-to-back builds need the coordinator's say-so. (On the first evening one agent held it
  through three renewals with two builds running at once, while three others queued and the
  machine fell to 2 GB available.)
- **`pytest tools/world/tests` builds a 1024 world itself** (about 1.6 GB, into bare `/tmp`), so
  it wants the lock like any build.
- **Use the gate:** `$SCRATCH/gate.sh [GB] [MAX_WAIT_MIN] && <your run>` waits until the lock is
  clear (or yours, with `GATE_OWNER=<area>`) and that much memory is available, then returns; it
  gives up after MAX_WAIT_MIN and says why. Every Godot, Blender and world run goes through it.
- **Check the lock and `free -g` immediately before each run, not once at the top of a task.**
  A run started under the lock or below the memory floor is the one the OOM killer takes, and it
  may take somebody else's with it.
- Never pipe `run.sh test` or `flow` into `head`; redirect to a file and read it.
- Never edit `game/` while a Godot run of yours is going (hot reload fakes SCRIPT ERRORs).
- In background shells use `unlink <path>` one path at a time rather than `rm` of many paths.
- **Stop only processes you started, by PID.** Never `pkill -f` / `killall` by a pattern: every
  agent runs the same scripts (`gate.sh`, `run.sh`, `godot`), so a pattern kills other agents'
  runs too. (It happened once: a `pkill -f scratchpad/gate.sh` ended every agent's waiting gate.)

## Quality bar (the user's words, from HANDOFF §1)
The painted, mythical look of *Oblivion*, *Fable* and *Dark Souls 2*. Every environment, point of
interest and quest distinct and compelling. Optimised, "not at the expense of visuals". **Look at
what you make** — render it and open the image. Every significant finding in this project came
from looking; a test that passes proves only that it passes. Write the test that presses the
button, not the one that calls the function under it.

## Hand-back
When a coherent piece is done and verified (the §7 checks that apply to your change, all green on
your branch), send the coordinator a short report with `SendMessage` to `main`: the head commit,
what is now true, what you measured and how, what you looked at, what fails or is not done, and
anything you think the coordinator has wrong. Then carry on with your next item; don't wait. Your
final report at the end is the same shape.
