# PROGRESS.md — state of Wickmere

_Updated 2026-09-19 (session 1)._

## State

**1077 unit tests green, 0 content problems. The smoke run builds all 24 shipping interiors
clean and sweeps all six regions and 34 places. The scripted journey passes all 15 of
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
* **Every villager was naked.** `apply_appearance` is what dresses the humanoid rig, and
  outside the character-creation screen nothing had ever called it — so every NPC the world
  stood up was the bare body. They now take a roll seeded from their own def, with whatever
  numbers that def states laid over it; the prose in an appearance block (`"build":
  "short_thick"`, a note about bone dust in the creases of both hands) is for the writer and
  is not applied as a part name. They also stood in a ten-metre scrum on the green, because
  the spawn radius was two to ten metres for a village of twenty-three; it is six to forty now.
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

## The forge, as handed over

The asset forge is finished and stood down. `python3 tools/forge/build_assets.py --list` is
the authoritative inventory (250 entries, 145.6 MB across five categories) and
`tools/forge/README.md` has the build, review and texture-weight rules. Four weaknesses are
recorded rather than hidden, each with its reason:

* **Tree LOD1 is 1288 triangles, not the 800 I asked for.** Deliberate: at 800 the woody part
  gets about 420 and the trunk shatters into flat shards that catch the sun. It was rendered
  and judged worse than what it replaced. The honest route to the last 500 is an authored LOD1
  trunk, and it is not urgent at 0.75 M primitives.
* **Cliff faces read as a stack of ledges** rather than as a face with a fallen block or two in
  front of it. Much better than the shattered glass they were; not yet Skerrow's best.
* **Ten material builders take no feature scale** (`painted_wood`, `carved_wood`, `canvas`,
  `wax`, `glass`, `ember`, `soot`, `snow`, `water_still`, `driftwood`). Left that way on
  purpose: they are near-featureless or only ever used at prop scale, and a parameter nobody
  passes is noise. The moment a hero piece wants one — a fifty-metre sail, a frozen lake — is
  the moment to add it, and it is one line each now.
* **Skerrow is judged slate, not lilac**, so `limestone` is to be left alone. Recorded because
  it is the kind of thing somebody re-litigates from a bad screenshot.

## The smith has no hammer, and his anvil is at his knees

Found by checking the one thing the character stream said it had not verified, and worth
keeping in this shape because the measurements are all here:

* **There is no hammer prop.** `game/assets/models/props/` holds an anvil and a forge hearth
  and no hammer of any kind. The only hammer in the pack is `core:item/reeves_bell_hammer`,
  a quest object with `model: null`. `Work_Hammer` is the most-used work clip in the game and
  it aims a tool socket at a point in space with nothing in the hand.
* **The anvil is 371 mm tall and stands on the floor.** `hearthvale_anvil_a` has
  `bounds.height 0.371` with `min[1] == 0.0`, and both Hallam's forge and Osric's smithy place
  it at `y = 0.0`. A working anvil is about that much iron standing on a *stump* that brings
  the face to knuckle height; the stump is missing. At the hammer strike the clip's socket
  sits 765 mm above the anvil face.
* **The clip is probably right and the world under it is wrong.** A socket at 1.136 m with 63%
  arm extension is a person working at a normal bench height. Do not re-tune the clips against
  the current anvil: fix the anvil (a stump, or place it raised) and build a hammer, then
  re-measure. The other three contacts for reference — Work_Chop z 0.910 / 64%, Work_Dig
  z 0.808 / 85%, Work_Stir z 1.230 / 88%.

## Why the smith has no hammer: eleven tools pointed at one that was never built

The hammer above is not a single oversight. Following it out with `tools/prop_heights.py`
gives the shape of the whole gap, measured rather than guessed:

* **54 of 516 prop placements across the 15 shipping house interiors draw a labelled box**
  rather than a mesh — 10%. Worst are the two smithies and the lodge: Hallam's forge 9 of 38,
  Alder's antler lodge 8 of 45, Osric's smithy 7 of 34, the Toll's Lip inn 7 of 50.
* **Seventeen kinds have nothing to draw, but they are not seventeen gaps.** Ten of them are
  dead substitution chains in `PropLibrary.STAND_IN`: `hammer`, `chisel`, `punch`, `file`,
  `knife`, `whetstone` and `bung_mallet` all point at `tongs`, `ladle` and `flour_scoop` at
  `spoon`, `rag` and `oil_rag` at `cloth`, `scythe` at `pitchfork` — and **`tongs`, `spoon`,
  `cloth` and `pitchfork` were never built**. Three meshes close fifteen of the seventeen
  kinds and fifty of the fifty-four placements. A stand-in pointing at nothing is worse than
  no stand-in: it reads as coverage in the source and delivers none in the room.
* `test_prop_library.test_every_stand_in_points_at_something_built` **is red on purpose** and
  names all twelve dead chains. It stays red until the forge lands the meshes. It is the test
  that would have caught this the day the map was written, and it did not exist.
* **The per-region material system has almost nothing to choose between.** 53 prop kinds are
  built; exactly three (`barrel`, `basket`, `crate`) exist in more than one region. Hearthvale
  has 35 of them, Brightwater 8, Sedgemire 6, Cinderlea 5, Skerrow 2, and **Briarwold none at
  all** — every prop in a woodfolk house is borrowed.
* **`HouseInterior._instance()` was handing `resolve()` a culture where it wants a region.**
  `resolve("barrel", "vale")` returned `brightwater_barrel_a`; `resolve("barrel",
  "hearthvale")` returns `hearthvale_barrel_a`. Not an error the function can see — it falls
  through to "any region at all" and answers with a perfectly good barrel from the wrong part
  of the country. `PropLibrary` now translates culture to region itself, so neither caller has
  to know, and a test asserts the map is the exact inverse of `Settlement.CULTURE_BY_REGION`.
  This bites on three kinds today and on every kind the forge adds from now on.

One correction to the record, because it was nearly written down: an earlier pass through this
counted **127 of 516 placements with no mesh**, and then a larger one. Both were wrong. They
were computed without reading `STAND_IN` at all, so every kind that resolves through a
substitute was counted as missing. `tools/prop_heights.py` now reads the map out of the
GDScript and follows `resolve()`'s own rule — the kind, then its stand-in, and nothing looser.
The real number is 54.

## The chart filled up by conversation only

`GameState.discover()` had two callers in the whole game: a dialogue effect, and resting at a
Hearthstone. Nothing found a place by *going* to it. You could walk from Merrowby to Tollmere
and arrive with blank paper, because the only way to learn that a place existed was for
somebody to tell you about it.

The half of DESIGN §5.16 that says "you fill it by looking from high places (surveying at
vistas)" was worse off than that. `map_screen.gd` reads a `surveyed:<place>` flag for its much
wider reveal, and the only thing in the project that ever set one was the UI review's fake
save. The larger reveal had never been drawn in play. Alongside it, every one of the 48 POIs
carries a `visible_from` list — 90 authored sightlines, the composition rule from DESIGN §4 —
and no code read the key at all; `tools/dead_data.py` had it at 48 uses and no reader.

`game/systems/exploration/place_discovery.gd` is the thing that was missing. Walking inside a
place's own footprint finds it. Standing at a vista — which is any place a POI names as
somewhere it can be seen from, so the authored data doubles as the vista list rather than
needing a second one that can disagree with it — sets the survey flag and reveals what the
country actually shows you from there.

**Actually shows you.** The sightline is marched over the built heightmap rather than taken on
trust, and this is where it gets interesting:

* **54 of the 90 authored sightlines survive contact with the terrain. 36 do not, and 10 POIs
  cannot be seen from anywhere at all.** `tools/sightlines.py` lists every one with how far
  the ground stands over the line. Some are unarguable — the Three Sisters claims to see the
  Seven Stones 707 m away through 178 m of mountain. Most are small: a 4 m swell of chalk
  downland between Merrowby and Larkbourne Ford, which is exactly what downland does.
* That is a world-building question and not a code one. Move the POI, raise it, or drop the
  line; the tool only finds them. Until somebody answers it, those sightlines reveal nothing
  and the POIs behind them are found by walking to them, which is the right way for the
  feature to degrade.
* The model's parameters are stated rather than fitted: eye at 1.65 m, a per-kind landmark
  height (a beacon tower is 18 m and a charcoal camp is 2.5 m — a flat 6 m for everything made
  the falls invisible and the campfires monumental), 2 m of clearance, and the first 140 m
  from the vantage ignored, because a person reading the country off a quay takes the few
  paces needed to see past the bank at their feet. The Python tool reads all of them out of the
  GDScript so the audit and the game cannot drift apart. Adding the per-kind heights made the
  clear count *worse* (49 to 46) before the foreground rule brought it to 54; that order is
  recorded because it is the evidence that the numbers were not fitted to.
* A hidden valley is called hidden. Three of them are invisible from everywhere and the tool
  says so separately rather than counting it against the placement.

## No village in the country had any work in it

`JobBoard` and `JobStation` are complete, tested, self-placing nodes. **No file in the project
outside their own two scripts and the tests ever named either class.** There was no notice post
in any settlement and no bellows, mash tun, chopping block or eel trap anywhere in eight
kilometres of country, so `Jobs` generated work that could not be handed to anybody and
DESIGN §5.15's jobs were a unit test.

`Settlement` places both now. The work follows who lives there — the interiors carry each
resident's trade — so Merrowby's two smithies put a bellows in a yard and its brewhouse a mash
tun, and a place whose people have no authored trade gets its region's own work instead. A
hamlet gets no charter-board. `ui/jobs/job_board_screen.gd` draws the notices; `interact()`
goes through the event bus now, the way an opened chest does, because the node signal it
emitted had no listener outside a test.

**Still owed:** the forge has no chopping block and no peat bank, so `chop` and `dig` stations
wear a crate of billets and a bucket at the cut. The substitution is a named constant in
`settlement.gd` rather than a quiet choice.

## The rest of what `dead_data.py` found, and why most of it is not a bug

Seven content keys had no reader. One was `visible_from` and is now the discovery system
above. The other six are descriptive rather than promised, and are recorded here so nobody
re-investigates them:

* `home_region` (6 callings) — where your Calling is from. DESIGN §5.1 says a Calling sets
  skill bonuses, a signature item and starting reputations; it does not say it moves where you
  wake, and the opening is one fixed place by design. Flavour, correctly inert.
* `unlocks` (1 item) — the Merrowby house key naming what it opens. Doors and containers
  declare their own `key_item`, and `PropertyRegistry.key_item_of()` derives the key from the
  deed, so the item's own field is a duplicate of a fact held elsewhere.
* `sells_deeds` (1 NPC) — Ellard the steward. Deeds are sold by the property sign, which the
  journey buys a house through; the flag on the man is unused.
* `unique_features` (6 regions), `beds` (6 items), `opposite` (12 table rows) — description
  and authoring notes.

The distinction worth keeping: `visible_from` was **mandated by DESIGN §4 and read by nothing**,
which is a dead feature. These six are data that describes the world without promising
behaviour, which is not the same thing and should not be treated as one.

## The shop traded against whatever bag was first in the scene tree

`Merchant` is the whole of DESIGN §5.14, tested to the corners, and nothing a player can do
ever reached it. It prices by region, stock on hand, disposition, your Speech, the shopkeeper's
own temper and how Hollow you have become; it buys only what it deals in; when the till is
short it buys what it can afford one unit at a time; and it turns a deeply Hollow customer
away in a Vale village. `buy_price_of` had ten passing tests and no caller.

The trade screen was handed an npc id and went looking for **"any Inventory that is not the
player's"** — a bridge someone left in with a comment saying the economy stream would replace
it, and nobody did. So a shop opened against whatever bag happened to be first in the scene
tree, and priced everything at base value times a flat multiplier.

`EconomyService.merchant_for()` finds the live shopkeeper behind an npc id now, and the screen
hands buying and selling to them. The bag-to-bag path stays for chests, corpses and review
scenes, which is what it was always for.

Two smaller things found on the way:

* **A loaded interior joins the `interior_root` group now.** The NPC streamer looked it up
  there and fell back to matching the node's *name*. The fallback worked, so the name was
  load-bearing: renaming it would have quietly emptied every house in the country of the
  people who live in it, and nothing would have gone red.
* **`HouseInterior._instance()` instantiated whatever `load()` returned.** A path that exists
  is not a path that loads — a prop whose albedo was half-written came back null and three
  script errors failed a smoke run that this function exists to survive. It draws the labelled
  stand-in now and names the file that would not load, once. That named the file in one line:
  a zero-byte texture on a new prop.

## Smithing, alchemy and enchanting were behind a door with no handle

`station_screen.tscn` draws all three working screens (DESIGN §5.8). `UI.MENUS` has had
`"crafting"` registered from the start. **Nothing in the game ever called
`UI.open("crafting")`.** There was no forge, no still and no bench anywhere in the country
that a player could walk up to, so three complete systems and twenty-one recipes were
unreachable, each with its own passing tests.

`CraftingStation` rides the prop it belongs to — the anvil in Hallam's forge and Osric's
smithy, the alembic in Nell's stillroom — so what you walk up to is the thing you were
looking at rather than an invisible trigger beside it. The anvil and not the hearth: the
anvil is where a smith stands and the hearth is what is hot.

Enchanting was worse off than unreachable. The Name-table is named in DESIGN §5.8, in the
enchanting skill's own definition and in two item descriptions, and **no interior in the
world contained one**. The Tolling Order writes notes into iron, so the Bell Chapter-House at
Pilgrim's Ash has one now — added to Cadwen's own recipe rather than to the warden trade,
because Pellam keeps the Wardens' Roll and that is a different order entirely. There is no
Name-table *mesh* yet; it stands in as a trestle and is written down as owed.

A note on the tests, because it is the same failure one level up: two of the tests I wrote for
this passed while asserting nothing — one iterated an empty list of stations, one built the
interior a way that never produced any. Both say so out loud now. A test that cannot provoke
the thing it tests is not a test.

## The notice post was on a layer the interaction ray does not read

Found by asking what a `.tscn` carries that a `.new()` does not. The player's interaction ray
masks one physics layer. Five of the eight interactable classes set that layer **only in their
own scene file**, and three of those five are instantiated from a scene nowhere in the game —
so the job board, the job station and the for-sale board placed the same day kept Godot's
default layer 1. They stood in the village, drew their props, joined the "interactable" group,
answered `interact()`, and the ray went straight through all three.

Each class sets its own layer now, and `test_interactables.gd` builds all seven with `.new()`
and asserts the four things that only matter at the moment a player points at something: the
layer, a shape to hit, the group, and a method to call. It also asserts that the mask in the
interactor and the layer in each class are the same number, because they live in eight files.

## The first calibration numbers this project has ever had

`ASSESSMENT.md` says every threshold in the game is a considered guess because there has never
been a playthrough to calibrate against. That is still true of *pacing*. It did not have to be
true of the numbers: damage, health, armour, loot, prices and XP are all data, and the formulas
that combine them are three static functions. `tools/balance.py` reads them and prints the
curves. It duplicates the formulas from the GDScript on purpose — a second opinion is the
point — and says plainly what it cannot know.

Three things are out of shape, and the tool states them itself rather than leaving them to be
noticed:

* **Brightwater is safer than Hearthvale.** 13.1 hits to kill you against 6.9, and the world
  puts Brightwater second. Sedgemire, at danger 2, is also gentler than the starting region at
  9.2. The danger rating on a region is a promise to the player and the first three regions do
  not keep it.
* **Sedgemire pays less than Brightwater and less than Hearthvale** — 19 marks a fight against
  74 and 25 — while being more dangerous than both. Brightwater is a city full of Bravos with
  purses, which explains its number without excusing Sedgemire's.
* **Flat armour takes the light/heavy choice away in late fights.** Against the Stone-Thrall
  King's 30 armour the best weapon in Wickmere (40 damage) lands 27 as a light and 107 as a
  fully charged heavy. At mid gear — an ashen sword, skill 50 — a light attack does not get
  through the armour *at all* and is clamped to the 1-point minimum: 1600 hits against 67. A
  player who has not found the best weapon in the game cannot light-attack the last two
  bosses. That is what flat subtraction does at these magnitudes, and whether it is the
  intended shape of a late fight is a design question, not a bug report.

What the tool measured and found healthy: the worst single hit rises evenly from 30% of your
health in Hearthvale to 58% in Cinderlea; bosses with late gear and charged heavies are 7 to
34 hits, which is a Souls-shaped fight; and a house is 57 to 195 Hearthvale fights, which is a
lot and is meant to be.

**What it still cannot tell you** is how long a fight takes, whether there are enough bandits
on the Merrowby road to earn a house without it becoming a job, or whether any of it is any
fun. Those need hands on a controller and nothing in this file substitutes for them.

I have deliberately not retuned anything on the strength of these numbers. Changing balance
without playing is how a considered guess becomes a worse considered guess.

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
