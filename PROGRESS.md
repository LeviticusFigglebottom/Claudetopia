# PROGRESS.md — state of Wickmere

_Updated 2026-09-19 (session 1)._

## State

**910 unit tests green, 0 content problems. The smoke run builds all 24 shipping interiors
clean and sweeps all six regions and 34 places. The scripted journey passes all 13 of
DESIGN's done-list promises, in the built world: it wakes at the Hushline Stair, walks 378 m
of real ground out of the Cinderlea and into Sedgemire, and goes on from there. 764 content
definitions. The world is 16 Terrain3D regions over 8 km square, built deterministically in
about two and a half minutes, with 404,000 scatter instances of 79 forged assets, 596
creatures in 247 groups, 24 interiors with doors in the ground, and the worst captured frame
costing 95 draw calls and 0.2M primitives against budgets of 2000 and 1.5M.**

Verify the whole thing with four commands:

```
./run.sh test       # the unit suite; content validation fails the build
./run.sh smoke      # build every interior for real; fail on any error
./run.sh journey    # one scripted run through every promise in the done list
./run.sh perf       # draw calls and primitives against the budgets
```

Merged and working on the main branch:

* **Foundations** — autoloads (Log, ContentDB, EventBus, Settings, WorldClock, GameState,
  SaveSystem, Hearth, Interiors, Debug), namespaced IDs with schema and dangling-reference
  validation, versioned saves with a tested migration chain, data-driven input bindings
  with rebinding, a unit-test runner that treats content problems as failures.
* **Atmosphere** — painted sky shader, sun and moon over a 48-minute day, per-region light
  recipes that blend on region change, 16 weather states with precipitation and global
  wind/wetness shader parameters.
* **Hearth** — Hearthstones, death, and the Echo that holds your marks until a second death
  lets it go quiet.
* **Interiors** — a far-pocket loader and doors; the cave forge (nine deep places, each
  with its own formation grammar, beats, shortcut and boss) and the house forge (fifteen
  houses whose plan and contents follow from the resident's trade, wealth, household and
  habits). 3.4 M triangles of authored cave, chunked per chamber so it culls.
* **Integration** — `GameServices` installs law, ownership, stealth, NPC life, market and
  property in dependency order; the player carries and saves their own bag, paper doll,
  skills and recipes. Both existed only because the journey found them missing.
* **Inventory, progression, crafting** — stacks with per-instance state, 13 equipment
  slots, deterministic loot tables, 16 use-based skills with 34 perks, six callings,
  smithing with tempering, alchemy with effect discovery, enchanting with mote charge.
* **Saying** — what a character knows lives on Progression beside their skills. Three
  Sayer-ish callings come up knowing one or two; fifteen spell tomes (a book with the
  working written out and an item that reads it) teach the rest; the three Sayers of the
  Circle teach the first rung of Binding, Hush and Mending, and the Sayers', Order's and
  Quiet Hands' questlines each end in one. The Sayings screen readies one to the cast key,
  the HUD shows it over the quick slots, and a saying nobody taught cannot be cast however
  its id reached the slot.
* **Bosses** — five, with phases that swap attack sets, breakable limbs on the
  Stone-Thrall King, channelled attacks that must be interrupted or silenced, and unique
  drops that carry the fight they came out of.
* **Combat and actors** — the full melee, ranged and magic loop with stamina, committed
  attacks, dodge i-frames, block, parry and riposte, poise and stagger, nine status
  effects; player with first and third person cameras, lock-on, mantling and interaction;
  enemy brains for every archetype, pack flanking, chargers, and phased bosses.
* **Narrative** — 25 NPCs with weekly schedules, 25 dialogue graphs, the seven main
  quests, three faction lines, six side quests, 20 books carrying the four contradictory
  accounts, 22 rumours.
* **Audio** — a full synthesis toolkit (no sample or recording enters the project): six
  region themes in five stems each, built on a five-note bell motif from the Toll and
  developed per region's mode; 43 ambience beds and one-shot pools by time, weather and
  interior; 70 sound ids in 240 variants; `Music`, `Ambience` and `Foley` autoloads over a
  seven-bus layout. 62 MB.
* **UI** — a generated "tended paper" identity: parchment panels, brass and dark-oak
  frames, hand-drawn icons, a painted chart. Title, the Naming, HUD with compass and boss
  bar, conversation and gesture wheel, pause, settings with live rebinding, save and load,
  journal in four tabs, book reader, inventory, skills and perks, sayings, the three
  crafting stations, trade, deeds and the map. Every screen renders from real content.
* **Tooling** — `run.sh`, the debug console with scripted `--cmd` runs, the region
  drop-test checker, the naming generator with a banned-name check, review scenes for
  atmosphere, interiors and the combat arena.

## In flight

Two streams are still polishing what they landed, against captures taken in the built world:
the terrain surface (the texture boundaries read as a pixel staircase, the road as a painted
stripe, the horizon as a white band) and the trees (they read as winter scrub at distance
rather than the Vale's orchards and hedgerows). Everything else is merged.

## Next

1. The surface and tree passes above, then re-shoot and judge the six regions again.
2. Hedgerows and field boundaries in Hearthvale: the bible's defining feature, and the thing
   that would most change how the downs read.
3. **Nothing named is standing in the world.** `game/world/pois/` is empty, so `scene_for()`
   in the world build never resolves a scene and all 34 places and 48 POIs are flattened pads
   with nothing on them. The forge has built the six landmark meshes — the Cracked Toll, the
   Lamp, the Sayer's Spire, both Choir Colossi, the Fallen Hand — and seven standing stones,
   and no code places any of them. You can stand on the exact coordinates of a forty-metre
   bronze bell that the main quest turns on and see a bald hillside. This is the largest
   remaining hole in the world and the one the drop test most depends on. Assigned to the
   world stream: resolve a landmark `.glb` as the place's scene, give it collision and a
   deliberate yaw, and place standing stones as hand-authored sets rather than scatter.
4. **The settlements are built but not planned.** Eleven places now carry a fabric of
   generated houses around their hand-built interiors — 54 slate roofs in Tollmere, 34 thatched
   ones in Merrowby, with the culture's walls, a plinth, a framed door and the carts, hay,
   fences and market stalls the forge has made. What they do not have is a *street*: the roads
   stop at the edge of the flattened pad instead of running through it, so the layout falls back
   to a ring around a green every time. `Settlement._along_road` already fronts houses onto a
   road correctly when one crosses the pad (there is a test for it) — the roads simply do not.
   Second: the pads are far wider than the towns on them and are paved edge to edge, so every
   village sits in the middle of a two-hundred-metre cobbled disc.
5. NPC and encounter density tuning. There is now somebody to walk the country and feel it:
   until this pass **nothing outside a test had ever called `NpcRegistry.spawn()`**, so the
   schedules ran, dispositions changed and guards noticed crimes in villages that contained no
   bodies at all. `NpcStreamer` follows whoever the world is streaming around and keeps people
   standing in a 240 m ring (330 m before they are taken down again), capped at 48. What is
   untuned is how many and how busy. Whoever the hour has indoors is not stood up in the
   street — so a village genuinely empties at three in the morning, and rain sends the idlers
   home — and going through a door stands the residents up in the room their hour calls for.
   Nobody is placed inside an interior they do not live in, so an inn at midday has its
   landlord and no drinkers.
6. Hedgerows and field boundaries in Hearthvale (see 2) are the other half of the landform
   score: the downs currently read as bare ground with trees on it.

## Deliberately not done (pass two)

* **The Barrow Reeve's falling pillars.** WORLD_BIBLE §9 says the arena's pillars
  come down during the fight to make cover. The chamber's pillars are part of the
  cave shell mesh, not separate props, so felling them needs the cave forge to emit
  them as their own bodies. The fight ships without it: the second phase changes
  through the toll (silence, four raised wights, a faster second stroke) instead.
* **Light as a spell effect.** Kindling is "fire and light" in DESIGN §5.3 but the
  spell runtime has no effect type that puts a light in the world, so all three
  Kindling spells are fire. A `light` effect is a small addition once someone wants
  a lantern spell.

## Two things that were built and never connected

Both were found the same way: by asking which public functions in the systems are called
only by the tests. A system can be complete, correct, covered and inert, and nothing in a
green test suite says so.

* **Nobody was standing in the villages.** `NpcRegistry.spawn()` had one caller in the
  repository and it was a unit test. Fixed by `NpcStreamer` (see above).
* **Nothing told the law.** `Bounty.commit()` had two callers — picking a lock and picking a
  pocket — and neither of the two crimes a player is most likely to commit. Emptying a
  stranger's chest and killing a villager in their own kitchen both went unreported, so the
  witness model, the guard confrontation, the fine, the jail term and the morality hit were
  all working perfectly on events that never arrived. `CrimeReports` is the join.

Three more turned up the same way, all of them content that had been written and then never
read:

* **Every chest in the world was a mesh.** `WorldContainer` could roll loot, lock itself and be
  emptied, and no interior ever attached one to the chest standing in the room — and no screen
  ever showed you the inside of one. Twenty-three chests, fourteen cupboards, strongboxes and
  sacks across the twenty-four interiors. They open now, they belong to whoever lives there,
  and emptying somebody's is one theft rather than nine.
* **A hundred and forty-seven greeting lines had never been said.** Every dialogue in the pack
  carries a `greetings` array written beside the conversation it belongs to — the lines that
  know this particular miller's water has come back — and `Greetings` only ever read
  `core:table/greetings`. They are rows now, keyed to whoever owns the dialogue, which makes
  them the most specific match whenever their conditions hold.
* **Sixty-five rumours and no way to hear most of them.** A rumour only ever entered a place's
  pool because the player spoke to whoever seeds it, so a village nobody had questioned was
  silent. Walking into a region now stocks its settlements with their own talk at a heat below
  the spreading threshold — local colour, not news — and the journal's rumour page checks a
  rumour's conditions before printing it, which it never did.
* **Every shopkeeper was somebody you could only talk to.** Thirteen people in the pack keep
  shops, `Merchant` registers with the economy, the trade screen is built and themed, and
  nothing opened it.
* **Seventy-eight schedule entries never applied.** They say `"days": "weekdays"`, and
  `Schedules` knew `workdays` and fell through to false for anything else, so a large part of
  the roster's working day was quietly dropped — invisible, because the fallback is a
  plausible schedule rather than an error.

And one smaller: **letting and rent were built and had nowhere to be done from.** Standing
at the board outside a house you own told you that you owned it. It is now a landlord's board —
collect the rent that is waiting, or put the word out that the place is to let.

The audit is `tools/unwired.py`, a sibling in spirit to `tools/dead_data.py`: the first asks
what the *data* promises that the code never reads, the second asks what the *code* can do
that nothing outside a test ever asks for. Run both before calling anything finished. Neither
is a compiler, so read the output rather than trusting it — an accessor nobody calls is dead
weight, but a verb nobody calls is a feature that does not happen.

## Known issues

* **The journey's death step has failed once in five runs**, and I have not pinned down why.
  It rests at a Hearthstone, dies, respawns and recovers the echo, and one run in five one of
  those five conditions came back false. The step now names which one when it fails instead of
  printing the success sentence, and each settling point waits two frames rather than one,
  which has held for every run since — but "it stopped happening" is not a diagnosis and it is
  recorded here as unexplained rather than fixed.
* **The exterior is over the primitive budget, badly.** DESIGN §11 sets 1.5 M primitives and
  2000 draw calls. Interiors are all comfortably inside it (the Cantor's Seat is the worst at
  1.17 M and 61 draws). The country is not: Merrowby from the air is **5.14 M primitives**
  against 1.5 M, and the same village from the street is 4.04 M. Draw calls are fine (1259 and
  1066), so this is not a batching problem — it is roughly 150 triangles on every one of the
  eight to nine thousand scatter instances in view, with no distance LOD. Tollmere, on a bare
  ash pad with little flora, sits inside budget at 1.07 M, which confirms where it comes from.
  The fix is a cheap far variant per scatter asset, not fewer plants; it is with the world and
  forge streams and it is not done.
* **The drop test does not pass**, and half of it cannot yet be measured. `uniqueness_check.py`
  scores colour and landform separately (DESIGN §10.1). Today: colour 0.57, together 0.43,
  against a 0.17 chance line and a 0.80 bar — so the combined bar fails, plainly.
  The landform figure is 0.10, which is *below* chance, and that is a statement about the
  sample rather than about the country: there are three images per region, so leave-one-out
  over six regions turns on one or two frames. The tool now says so and refuses to fail the
  run on it. Getting a real landform reading needs six or more shots per region, which is
  cheap and is not done. The confusion pairs are informative meanwhile: Brightwater reads as
  Cinderlea, and Briarwold as Sedgemire and as Hearthvale.
  I also removed the absolute horizon height and the sky fraction from the landform signature
  after the world stream pointed out that changing the vista camera moved the score by a
  factor of eight. Those two terms were measuring how high the camera stood, which is the
  photographer's choice and not the place's.
* Terrain3D + lavapipe (software Vulkan) crashes in JIT code; use OpenGL for
  headless captures (ARCHITECTURE.md §10).
* Cave floors show a faint dune ripple where the shell noise is applied before the
  floor is flattened. It reads as drifted sand rather than stone in the flattest
  chambers; the fix is to flatten first and noise the walls only.
* Compatibility renderer lacks SSAO/volumetric fog; the look must not depend on them.
