# PROGRESS.md — state of Wickmere

_Updated 2026-09-22 (session 3)._

## State

**1204 unit tests green, 0 failed, 0 content problems and 0 script errors. The smoke run
builds all 24 shipping interiors clean and sweeps all six regions and 34 places. The scripted
journey passes all 16 of DESIGN's done-list promises in the built world — including the
sixteenth, which had never once run, because it was called and never written and the file
would not parse. 912 content definitions: 236 items, 89 rumours, 76 NPC defs (68 of them
named people), 64 dialogues, 48 POIs, 40 quests, 40 books, 34 places, 26 enemies, 25
interiors, 21 recipes, 15 sayings, 8 factions, 6 callings, 5 bosses. The world is 16
Terrain3D regions over 8 km square, built deterministically in about three and a half
minutes, with 1024 cells of scatter, 24 interiors with doors in the ground, all 55 points of
interest dressed and standing, 16 Hearthstones in the open country, and the worst captured
frame — a village street — costing 1240 draw calls and 1.18 M primitives against budgets of
2000 and 1.5 M.**

Four commands verify it, and a fifth presses the way in:

```
./run.sh test       # the unit suite; content problems and logged errors both fail the run
./run.sh smoke      # build every interior for real; fail on any error
./run.sh journey    # one scripted run through every promise in the done list
./run.sh flow       # boot, the Naming, and the world appearing, in captures
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
* **Narrative** — 64 NPCs with weekly schedules and dialogue graphs of their own, living in
  every settlement of the six regions (DESIGN §6's sixty are met: Grandfather Hollow,
  Brindlecrag, Nauve's Landing and Greyfold had nobody at all, and every city, town and
  village now has at least three residents and a shop), the seven main quests, four faction
  lines of four quests each, eleven side quests across all six regions, 25 books carrying the
  four contradictory accounts, 89 rumours of which the local ones are seeded into a region's
  settlements when you walk in. Every faction and side quest is taken off a choice in its
  giver's own dialogue and every decision one asks for is on a button in front of somebody.
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

Items 3, 4 and 5 of the previous list are done and are written up in their own sections at
the end of this file: every place and POI now has something standing on it, the settlement
fabric is inside the draw-call budget with windows and chimneys on it, and the country has
sixty-eight named people in it instead of forty-three. What is left, in the order it is
worth doing:

1. **Play it.** Still the first item, and still nobody has. The journey proves sixteen
   promises hold; it cannot tell you whether swinging a sword feels like anything.
2. **Hedgerows, ground cover and light.** The downs read as bare ground with trees on it and
   the country casts no shadow at all, which is the single largest reason a frame reads flat.
   In hand.
3. **A graded road can stand a hundred metres above the ground.** `carve_roads` limits a
   road's profile to 11% and writes it into the heightmap; where the ground falls faster than
   the road descends — the spur out of Kharrow Hold toward Gullhithe — the road becomes an
   arête that nothing in the region's shape function put there. Invisible to every audit we
   have and obvious from the ground.
4. **The quest plumbing three.** `quest_at` with an integer stage is off by one across the
   pack (the context returns a 0-based index; the content is written 1-based), nothing in the
   game emits `escort_arrived`, and the authored quest items that `collect` objectives name
   are placed in the world by nothing.
5. **Close the drop test.** Colour was 0.64 and landform 0.21 against bars of 0.80 and 0.55,
   measured before any of this session's work; both want re-measuring once the ground cover
   and light land, and the landform proposal in `## Sightlines, answered` is the honest next
   step for the axis that is barely above chance.
6. **Encounters and people at the points of interest.** Every POI's `encounter` sentence and
   its named NPC — the lamplighter, the toll-keeper, the knight in the eye, the hermit — are
   still absent, so the props are set out as if somebody had just stepped away.

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
because Pellam keeps the Wardens' Roll and that is a different order entirely. ~~There is no
Name-table *mesh* yet; it stands in as a trestle and is written down as owed.~~ **Paid:**
`gen_props.name_table` builds it in Cinderlea's palette — one heavy baulk of near-black
timber on four iron-strapped posts, a plate of bell bronze let into the top with the
Order's note cut into it, and a small bronze bowl for the Ember Motes that pay for the
writing — and the chapter cell's muster room is regenerated around it.

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

*Since written:* the two ordering complaints are fixed and most of both was the tool, not the
data — see "Four small holes" below. The flat-armour one stands, unretuned, as a design
question. The healthy readings hold, except that a house now reads 46 to 157 Hearthvale
fights rather than 57 to 195: no house price changed, but the tool's estimate of what a
Hearthvale fight pays rose from 25 to 31 marks once it started counting the loot every kill
guarantees.

## What the forge stream found by opening the renders

The measurable part of the prop pass was right before anybody looked at it: `prop_heights.py`
reported nothing unbuilt and no dead stand-in. The **visual** part was not, and three of the
faults were the exact class `ASSESSMENT.md` warns about — obvious in the first image, invisible
in a careful reading.

* **The scale constant, still live, in a place `relief` cannot reach.** `wood_planks` lays a
  grain wave in the *albedo* every `scale`/22.5 m. On a 0.33 m hammer haft that is eleven rings
  at 31 mm pitch around an 18 mm stick; the spear and pitchfork shafts carried fifty-odd; the
  shield read as corduroy and the spoon's bowl as a scallop shell. `lake_stone` had the same
  fault in its normal: a 40 mm bedding bump, absolute, on a 40 mm whetstone, so the hone came
  out as courses of stacked slate. Both take a multiplier now, and the forge README has a
  section listing all four known instances of this fault with the rule for new parameters.
* **Three props with parts floating in mid-air**, from one mistake: `rotation_euler` +
  `apply_transforms` on a part rotates it about *its own* origin and leaves it where it was.
  The spear's socket rivet hung 0.14 m off the shaft; the shield's six boss rivets sat in a
  flat ring in the plane the boss occupied *before* the shield stood up, four of them clear of
  the board. `stand_up()` bakes placement into vertices first.
* **`B.rope_loop` accepted a `location` and silently dropped it**, and that had shipped in four
  committed props: the Sedgemire rope coil was four flat turns on the ground with its end
  hanging over nothing, the sack's neck tie was inside the sack, the dock post's lashings were
  buried in the mud and the small bell's hanger was at its mouth.
* **The 0-byte albedo I found was two defects.** `save_png` wrote in place, so a kill mid-bake
  truncates the file; and `is_current` trusted the meta's hash and checked textures with
  `.exists()`, so nothing could ever notice. It writes to a neighbour and renames now, and
  checks size.
* **Briarwold's own timber.** A second set of meshes in the same wood is a different *seed*,
  not a different material — the first Briarwold trestle came out eight units of 255 from the
  Hearthvale one, because `wood_planks` mixes a fifth of the palette's `earth` role and all six
  regions' earth roles are the same red-brown. A `TIMBER` table keyed on the region gives
  Briarwold the black ash its flora list names. Measured after: 82/56/41 against 103/82/57.

**Accepted, with the way back written down:** the asset weight ceiling went from 150 MB to 165.
The committed library was already at 145.8 MB, so the next thing built was going to break it
whatever it was, and the twenty-three new props cost 0.31 MB each against a library averaging
0.55. Two levers remain and are written into the test rather than left as a magic number: the
drawn leaf and grass atlases write their normals at full size where everything baked writes at
half (~3 MB across 85 assets), and the ten landmarks carry 1536 px albedos and are 27 MB
between them — a fifth of the library for ten objects (~10 MB back at 1024).

**A warning for the next person reviewing a material:** the exposure in `asset_review.tscn`
makes every diffuse surface read about two stops lighter than its albedo. It cost the forge
stream two rebuild cycles on the anvil's stump before they rendered a trestle table next to it
and found that Hearthvale's pale honey timber is the house style and not a bug. Render a known
reference beside anything you are judging in that scene.

## The way in had never been pressed

The main menu, the Naming and the world were three screens nobody had walked between. The
journey drives systems directly and the UI review renders screens with believable data; no
test and no tool had ever started at `boot.tscn` and clicked New Game. Four things were wrong
at once, and a player met all four in the first minute:

* **The Naming spoke a vocabulary the body does not read.** It kept swatch indices, a
  `height_m` and a face named after a culture, and handed that to
  `HumanoidModel.apply_appearance`, which reads `CharacterAppearance`: `skin` arrived as the
  string "1", `height` was never set, and with no `parts` there was no hair and no clothes. The
  preview was the naked rig whatever you chose. `CharacterAppearance` is the one vocabulary now
  — it carries the forge's colour tables, the head presets and the culture palettes, and dresses
  a character for its people — and the Naming edits that record in place.
* **Nothing read the Naming's flags.** `player_name`, `player_calling` and `player_appearance`
  were written by the screen and read by no one, so the body at the Hushline Stair was the bare
  rig with the default head, with no name, none of the Calling's three skill bonuses and none of
  its items. `Player._take_the_naming` reads them when the body stands.
* **Continue, Load and `--load=<slot>` did not load.** All three wrote
  `_pending_load_slot` and nothing ever read it: every one of them stood a new Foundling up
  with the save untouched on disk. `PlayerSpawn.load_pending_slot` reads it before the body.
* **The screen was a dead black rectangle** from "Be named" until the world stood — ten to
  fifty seconds of it, with no frame drawn at all while the terrain comes up. The fade layer
  carries a loading caption now: a sheet of paper, a line in the world's voice, the bell mark
  swaying, and what the world has raised so far.

`./run.sh flow` is the test that presses it: three runs from `boot.tscn` (New Game through the
Naming, then `--load`, then Continue), clicking by the words on the buttons, typing a name,
working a chooser with the arrow keys, dragging both sliders, walking Tab round the form, and
then asking the *body* in the world whether it is the character that was made. Every step is a
PNG in `captures/flow/`. It found two of its own: the Naming gave nothing keyboard focus, and
the Calling cards' wrapping focus chain trapped Tab for ever.

## Known issues

* **Sixteen `Parameter "material" is null` messages a headless run**, one per NPC actor freed
  in `test_npc_actor`'s teardown, raised inside Godot's *dummy* material storage
  (`material_get_instance_shader_parameters`). Nothing in this project sets an instance
  shader parameter anywhere, and the bodies it frees all carry a `material_override`, so this
  is the headless renderer's own teardown path rather than ours. Recorded so the next person
  does not spend an hour on it; it does not appear under a real renderer and it fails nothing.

* **A record from before that vocabulary existed** — `{"skin": 3, "hair": 2}`, which is what
  the Naming used to write and what the journey still writes — is converted at the edge now
  (an index means the tone it indexed). Any save still carrying the older shape makes a proper
  body, but the journey's own shorthand should be brought up to the record's spelling.
* **`./run.sh flow`'s Continue run depends on what else has saved.** Continue promises the
  newest slot, so a journey run or another session writing into the same `user://saves` takes
  that place; the probe reports which slot it got and falls back to checking that slot's own
  summary. Tools that write saves should clear them (the UI review does now).
* ~~**The journey's death step has failed once in five runs**~~ **Diagnosed and fixed: the Echo
  noticed its own player.** It was never a frame-scheduling accident. The Echo is an `Area3D`
  spawned at the spot the player fell, and for the three seconds of `RESPAWN_DELAY` the body is
  still lying on that spot — so the area woke up around its own player, `body_entered` fired and
  `recover_echo()` returned every mark before the player had stood up. Death has therefore never
  cost anything in play: the Echo you are meant to walk back to went quiet within a frame of your
  falling. The journey sees the same fault as `dropped=false`, as `marks_gone=false` or as a
  clean pass depending only on whether a physics tick lands between two of the step's checks,
  which is why more frames appeared to help and why five runs could not settle it. An Echo is
  something you come back to, so `Hearth` now arms it on respawn (one restored from a save is
  armed at once) and `recover_echo()` refuses outright while a death is unresolved. Two tests in
  `test_hearth.gd` pin it, and they need a body the physics server can see, because an `Area3D`
  never notices the bare `Node3D` the old fakes used. The same seam gave up a second fault:
  `_respawn()` was not idempotent and the death delay's timer cannot be cancelled, so anything
  that brought the player back sooner — a load, a scripted respawn, the journey's own — was
  undone three seconds later when the timer yanked the body to the Hearthstone mid-stride.
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
* ~~Cave floors show a faint dune ripple where the shell noise is applied before the
  floor is flattened.~~ **Fixed, and the diagnosis was wrong.** The floors were flat all
  along -- measured off the shell, the lowest surface in every square metre of the
  Undercroft's bell hall and Hollin Barrow's reeve hall is flat to one millimetre over
  five hundred cells, and masking the noise around them changes nothing you can see. What
  the shells did not have was **normals**: `trimesh` writes a NORMAL attribute only if the
  mesh already has vertex normals cached, nothing ever asked for them, and glTF says a
  reader must then compute flat ones -- so Godot was shading three hundred thousand
  separate facets per cave. On a wall that passes for broken rock; on a flat floor it is
  drifted sand. `include_normals=True` on the export, all nine rebuilt, structure
  unchanged to the centimetre.
* Compatibility renderer lacks SSAO/volumetric fog; the look must not depend on them.

## Exteriors: the fabric under budget

The worst frame in the game was a village street: Merrowby from the road, **2438 draw
calls** against DESIGN §11's 2000 (ASSESSMENT.md recorded 2678 on the previous machine).
Primitives were inside budget at 1.15 M; this was object count, and nobody had broken it
down. `tools_gd/draw_attribution.gd` does now — a census of what the camera sees by owning
script, and the measured cost of hiding each owner, which is the number that includes the
sun's four shadow cascades. `-- --attribute` on any capture writes `attribution.json`;
`draws measure` in the console prints the same. Measured on gl_compatibility at 1600x900
(no Vulkan in this container; object counts do not depend on the renderer), Merrowby's
2441 draws were:

| owner | draws | what it was |
|---|---|---|
| `Building` (11 entered houses in view) | 1093 | 358 MeshInstance3Ds: 31 room masses, 31 plinths, 62 roof slabs, 62 gables, 30 ridges, 11 chimneys, 44 door parts, 33 window parts — each drawn for the eye and again per cascade |
| villagers (`HumanoidModel`) | 583 | 20 in view, about nine skinned meshes each (body, head, two eyes, torso, legs, feet, belt, hair…), all shadow-casting |
| scatter MultiMeshes (`WorldStreamer`) | 325 | 373 MultiMeshInstance3Ds across 25 cells, trees and rocks in the near ring casting |
| `Settlement` (fabric, props, boards, stations) | 244 | two merged meshes per settlement, but ~100 props as instantiated scenes with no visibility range, so seven other settlements' fences and barrels were in the frame from kilometres off |
| `Terrain3D` | 151 | the clipmap |
| doors, water, landmarks, sky, UI | ~45 | |
| **of which shadow passes** | **1535** | sun shadows off: 2441 → 906 |

**What changed.** `FabricMesh` gathers boxes and triangles under a surface key and commits one
`MeshInstance3D` per key with a vertex colour per piece; `painted_surface.gdshader` multiplies
by `COLOR`, which is white wherever a mesh carries none, so interiors are untouched. A
`Building` is four meshes (walls, roof, stone, joinery) plus a body a room; a `Settlement`'s
filler houses are the same four meshes for the whole settlement, each house in its own bucket
of limewash; props are one `MultiMesh` per forge asset (lifted by the mesh's own box where it
reaches below the ground). Joinery and props carry a visibility range and the joinery casts no
shadow; walls and roofs still go to the horizon, because a village is read by its roofs from
the next hill. `JobBoard`, `JobStation` and `PropertySign` stay their own bodies on the
interaction layer. The filler houses, which the capture showed as windowless plaster boxes,
got a plinth that varies, gables, overhanging eaves, a chimney at the hearth end, a framed
plank door under a lintel on a stone step, and framed, shuttered windows in bays along the
street with fewer at the back and one in the far gable — all inside the merged meshes, at no
draw cost. Villagers' eyes no longer cast shadows (they fall inside the head's).

**Measured, the six `*_street` shots of `tools/capture/plans/streets.json`, before → after:**

| shot | draw calls | primitives | what is left (after) |
|---|---|---|---|
| hearthvale_street (Merrowby) | **2438 → 1328 → 1240** | 1.15 M → 1.18 M | villagers 590, scatter 332, terrain 160, buildings 120, fabric 110 |
| brightwater_street (Tollmere) | 479 → 283 | 0.34 M → 0.34 M | terrain 105, scatter 68, fabric 61, villager 26, buildings 16 |
| sedgemire_street | 660 → 498 | 0.73 M → 0.73 M | terrain 184, scatter 182, fabric 60, villagers 53, buildings 12 |
| briarwold_street | 764 → 547 | 0.80 M → 0.79 M | scatter 316, terrain 154, fabric 54, buildings 16 |
| skerrow_street | 609 → 433 | 0.37 M → 0.45 M | scatter 136, terrain 126, villagers 95, fabric 59, buildings 18 |
| cinderlea_street | 515 → 405 | 0.63 M → 0.62 M | terrain 170, scatter 123, villagers 56, buildings 11, fabric 10 |

Merrowby's three numbers are the original, the figure after the fabric was merged, and the
figure after villagers' eyes stopped casting a shadow into the head they sit in. The first
measurement of the same shot on the integrated branch, with nine other streams' work in it,
read 1330: the gap is their scatter, their points of interest and their light, not the
fabric, whose own contribution `--attribute` will name at any time.

Every shot is inside the 2000 budget with margin and the worst is under 1500. Buildings went
from 1093 to 120 draws on the worst frame and the fabric from 244 to 110 (the 110 is
Merrowby's own four meshes, nine prop MultiMeshes, a board, three stations and two signs
with their cascades, plus the other ten settlements' walls and roofs at a few draws each).
`test_settlements.gd` ratchets a village of Merrowby's kind at **31** mesh nodes and pins
the rest: four meshes for a city and a hamlet alike, six or more distinct washes in the merged
walls, near-only shadowless joinery, one MultiMesh per prop asset within the pad, boards and
stations and signs as separate bodies on the interaction layer, the inn as four meshes and a
body a room, and every box in the fabric facing outward.

**What is left belongs elsewhere.** The residue on Merrowby's street is people, plants and
ground. Villagers are the largest: about nine skinned `MeshInstance3D`s each under
`HumanoidModel`, all casting into up to four cascades, so twenty in view are ~590 draws — a
merged body per appearance, or shadows from a single proxy mesh, would take most of that
(NPC appearance is the boot/UX stream's). Scatter is 332 draws for 373 MultiMeshes across 25
cells, most of them a handful of instances each; merging a cell's small kinds or ranging the
far ring's is the world-look stream's. Terrain3D's clipmap is 105–184 draws and not ours.
## Points of interest, dressed

`pois.json` has 82 entries — 34 places and the 48 POIs of the registry — and nine of them
had a scene: the six landmarks and eleven of the Choir's colossi. Everything else was a pad
the world builder had flattened, with a name on it. Every bridge, shrine, tower, hidden
valley, camp, waterfall, ruin, strange tree, wreck, giant bone and stone setting is raised
now, and so is the Hearthstone of every place whose `shrine` tag promised one.

**It is raised at runtime, from the built data, the way a settlement is.** `WorldPois` (a
node in `world.tscn` beside `WorldDoors`) indexes the dressable entries of `pois.json` by
cell; `WorldStreamer._build_cell` asks it for that cell's dressings and parents them to the
cell node. So a camp arrives with the ground it stands on, unloads with it, and in the far
ring (past 384 m) is built as silhouette pieces only, with no lights, no collision and no
Hearthstone. The alternative — raising all 55 at startup under one node, as `WorldDoors`
does for settlements — would keep seventy-odd fires, lanterns and interactables in the tree
wherever the player was standing, and the ring system already knows what is near. Nothing is
positioned by a table in code: every dressing reads its position, pad radius and region out
of `pois.json` and the content pack, so the sightlines stream can move a POI and the dressing
follows it with no rebuild.

Each builder is deterministic from the POI's id (`rng.seed = abs(poi_id.hash())`), and each
answers the POI's own `unique_feature` as a brief: the thing the data names is the thing you
see. `PoiKit` finds the forge's assets, stands them on the real ground with the collision the
forge authored for them, instances repeats in a MultiMesh, paints runtime masonry with
`painted_surface`, and puts a light where a fire or a lantern is. `PoiMasonry` builds what the
forge has no asset for — a drum of courses, a humped arch, a plank deck, a flight of steps, a
mound, a pool, a hanging sheet — out of one `SurfaceTool` per material, one draw call each.

### What each kind is made of

* **Camps** (4) — a fire ring with its stones, light and smoke; three or four tents turned to
  the fire with a bedroll in each mouth; crates, barrels and sacks against the tents; a
  lantern on a post; a cart and a hitching rail on the road side; spears and a shield where
  the campers fight for a living. The brief on top: the Gosling Pit's stolen mill wheel is a
  millstone laid on a barrel with the cups still on it; the Charcoal Camp's kilns are turf
  domes smoking; the Clanless Camp's loosened chain links hang as bells on a line behind a
  drystone windbreak; the Cold Fire has no light at all — an ash disc, the stools round it and
  the cup set down.
* **Shrines** (6) — each keeps a working `Hearthstone` under the POI's own id, with candles, a
  small bell on a frame, offerings and the region's flowers. Ansel's is a hawthorn grown
  through a stone chair with the stone in its lap; the Shingle Shrine is a cairn of a hundred
  and ninety lake pebbles with the stone out of its top; the Drowned Bell is a peat hummock
  ringed with lantern poles beside a pool where the old bell breaks the surface; the Oiled
  Stone is oiled to a chestnut shine with the jugs and the rag beside it; the Finger Shrine is
  a sinkhole rim of leaning slabs round a giant's finger bone stood on end; the Pilgrims' Bell
  is a bell the size of a house on its side that you walk into through its mouth.
* **The Hearthstone of a settlement** (7 places tagged `shrine`) — a standing stone and the
  stone that keeps a name, set off the place's centre beyond whatever landmark stands there,
  with candles, a bench and a bell.
* **Towers** (6) — the Tumbled Watch is a hollow drum lying down its valley, open at both
  ends, its stump still standing, with the Wardens' bell rolled out of the top and somebody
  living in the corridor; the North Cliff Beacon is a broken drum with an Oroth bell upturned
  on its crown for a fire-bowl, lit; Heron Watch is a plank platform on stilts with a roof, a
  ladder and a bell under the eaves; the Hunters' Stand is a railed platform round a giant
  oak's trunk with its rope ladder pulled up; the Watch of the Gate is a square drystone
  toll-house under drifts of old snow with its bell frozen mid-swing; the Headless Watch is a
  colossus's head sunk to the jaw in ash with a cold blue eye and a stair up to it.
* **Bridges** (7) — where water lies within reach the deck spans it bank to bank; where the
  builder set the bridge on dry ground it is still a crossing with the thing under it the
  brief names. The Long Stride strides out over the Mere on piers with a lit Oroth lamp post
  every seven metres; Larkbourne Ford has the Toll's clapper half sunk and paved round under
  its arch; the Glass Bridge has a black glass riverbed; the Eelweir is dock posts and wicker
  with a plank walk on top and the eel traps hung below; the Lantern Causeway is a boardwalk
  of lantern poles roped pole to pole; Mossbridge is a natural granite arch with a great tree
  at each end; the Chain Bridge is a plank deck slung between four stone pylons on four
  chains of links. Every deck has collision, so the road that crosses there can be walked.
* **Waterfalls** (4) — a face of the region's cliff slabs on an arc, with a sheet off its lip
  into a pool, spray at the foot and a bank of ground behind so the lip is a hillside's edge.
  `falling_water.gdshader` streaks down the sheet's own V and froths where it lands. Foxfire's
  ravine carries bracket fungus with a green light in it; the Three Sisters is three falls one
  above another, each with a ledge and a stair, and the Hearthstone the sisters carried up on
  the middle one; the Glass Falls has no water — a still black face with slab ledges for the
  climb the Order forbids and uses.
* **Ruins** (4) — a hall of courses to the knee so the plan is readable, one gable still up, a
  doorway that stands because a lintel is the last thing to go, the hearth and its chimney
  breast, and the roof slates flat inside the walls. The Pilgrim Stair and the Stair of Isse
  are an Oroth colonnade rising out of the water, seven pairs of columns broken to seven
  heights, the drums that fell lying where they rolled. The Thirteenth is a colossus face down
  in the ash with its head buried to the brow in a trench of spoil and the Sayer camp arguing
  round it. The Breach is four Oroth wardstones across a gap in the Briar, two snapped, the
  thorn living either side and ash-grey where something walked through.
* **Giant bones** (2) — articulated, not heaped. The Rib Cathedral is nine pairs of ribs along
  a line leaned in over the aisle so they close above your head, a vertebra at the top of each
  arch, the neck running on past the last rib and the skull at the end of it; the clans' oath
  hearth is on the aisle floor with a stone to swear on. The Hart Bones is an antlered skull
  the size of a hall with two racks built out of finger bones, and a Hart-Knight's vigil.
* **Strange trees** (3) — the Singing Yew at three times a hedge yew's scale with the bell it
  ate in a split of its trunk and the bark grown round it; the Sallow King, a willow in a ring
  of seven more with the rooted limb that made each one running back to the king, standing
  water inside the ring; Willow Isle, a dome of earth out of the lake under a pollarded willow
  at the size of a barn, with the hermit's boat in its roots and his fire on the crown.
* **Wrecks** (2) — an open broken hull: a keel, seven or nine pairs of ribs with the weather
  side snapped to stumps, three strakes left on the lee side, the stem up out of the bow, the
  mast fallen across her, the cargo down the beach and a lantern still on the stem. The Reed
  Wreck is half again as big and three miles inland among the reeds.
* **Hidden valleys** (5) — a screen with something behind it. Foxglove Dell is a turf hut with
  a smoking chimney inside a hedge, with two hundred and sixty foxgloves; the Hidden Tarn is
  black water with no fringe of anything, because nothing lives in it, behind a bank of scree;
  Wisp Hollow is a channel with a drowned house's chimney above the water, five cold green
  lights over it and the strongbox in the chimney; Fern Gully is two walls of cliff slab with
  mist that does not lift and three silk bridges across it; the Hushline Stair is forty Oroth
  steps down into mist between two piers, with Wren Tallow's Hearthstone at the top step.
* **Standing stones** (3) — `worldgen/stones.py` sets stones across the country from places and
  roads, so the three POIs that *are* a setting were not among them. Bell Meadow leans three
  bronze-streaked stones round pieces of the Toll's crown; the Seven Stones are seven for
  seven clans, each lichened a different colour with the seventh bare, because that clan is
  dead; the Tideflat Stones stand in a line along a strand that is not the shore any more.
  Every stone gets its own packing stones, which is how a stone is actually set.
* **Strange** (2) — built from their own sentence: twelve bell buoys on the water, each a
  barrel float, a post, a cage and a bell a little smaller than the last, with the boat you row
  out in; and the One Poppy, with the ring of stones somebody set round it and the cup of
  water somebody brings it.

### The Hearthstones, which is a gameplay hole closed

No Hearthstone stood anywhere in the overworld: they existed only in caves, and in the
journey's own scratch scene. So outside the deep places the player had no rest, no respawn
point and no way to light a stone — and the main quest's second stage says *rest at Pilgrim's
Ash*, which had nothing to rest at, as did the Isseva and Fallen Hand stages. There are
sixteen now: six at the shrine POIs, three more at POIs whose data asks for one (the Three
Sisters, the Hushline Stair, the Drowned Bell), and seven at the places tagged `shrine`
(Merrowby, Tollmere, Isseva, Grandfather Hollow, Kharrow Hold, the Fallen Hand, Pilgrim's
Ash). Each carries the id of the place or POI it stands at, which is exactly what a quest's
`rest_at` objective names, and `test_pois.gd` walks every `rest_at` target in the pack and
fails if no stone stands there.

### What the captures changed

Every image in `tools/capture/plans/pois.json` was looked at, and four things were only
visible by looking:

* **A wall was a heap of bricks.** `drum` and `wall` laid every stone as its own box, so a
  tower was six hundred boxes with the painted surface's stone-block pattern drawn over them —
  coursing twice, at two sizes, which reads as neither, and the Tumbled Watch photographed as
  a stack of pillows. Both build a shell now, one ring of quads inside and out stepped in at
  each course, and the stones are the shader's, the way `Settlement` does a house.
* **A cliff was a wall.** The waterfall face was slabs at even spacing all turned one way on a
  straight line: brickwork in a field. It is an arc now whose ends come forward, every slab
  turned to the tangent and then well off it, scaled 0.78–1.22 and staggered in depth.
* **And then the fix for that was worse.** An earth bank was put behind the face so the lip
  would read as a hillside's edge, and Whitecut Falls came back as a smooth brown cone with
  no rock and no water visible at all — a mound as tall as the fall, six metres behind it,
  simply swallows it. The bank is gone. A dressing that raises its own hill fights the
  terrain it stands on, and the ground behind a waterfall is the world builder's business.
* **Old snow was a marshmallow.** `mound` drew perfect domes. It swells and dips in broad
  lobes now, jitters its rim, and the drifts lie long and low against the walls.
* **Two trees were thorn-balls.** A tree's leaf cards scale with the tree, and much past twice
  its built size they stop reading as foliage and start reading as shards. The Singing Yew
  came down from 3.1 to 2.2 and Willow Isle's pollard from 2.6 to 2.1; both are still half
  again anything around them, which is all "strange" needs.
* **A colossus's head was an egg.** What a head faces is decided by the ground and where you
  walk up from is not, so a brow, a nose and one eye on the front face photographed from
  behind as a smooth ovoid with brick coursing on it. It has a brow band right round, cheeks,
  a jaw, a chin and a socket on both sides now, and carved stone at a 3.4 m unit rather than
  the Oroth 1.1 m, which was bricking a face.
* **Dusk at 19:00 is night.** The first camp and shrine shots were black ground under a violet
  sky. The plan's dusk hour is 17:10 — the last hour where a fire reads against the sky and
  the ground still does — any POI whose own feature text is about a light gets it whatever its
  kind, and every camera bearing is scored by how flat its ground is rather than taking the
  approach side blind, because a camera forty metres up a slope photographs a map.

### Two GDScript traps this work walked into, both worth knowing

* **Two `class_name` scripts that name each other may not resolve, and the error lands on a
  third file.** Every builder takes a `PoiDressing` and `PoiDressing` called
  `PoiBuilders.build()`. GDScript resolved that pair when the POI tests ran alone and failed
  once an import had rebuilt the global class cache, reporting `Could not resolve class
  "PoiBuilders", because of a parser error` against `test_pois.gd` — which merely mentions the
  name. `poi_builders.gd` has no `class_name` at all now: `PoiDressing` loads it by path and
  the list of built kinds lives on `PoiDressing.KINDS_BUILT`.
* **A loop variable that shadows one in the same function stops the whole script compiling.**
  `_bridge_arch` holds the near end of its span in `a` and a later loop declared `a` again.
  Nothing that draws a point of interest loads when that happens, the test runner reports
  "did not compile" rather than a failure, and neither branch held both declarations at once
  so neither branch saw it — only the integration branch did.

### What is still wanting

* **The pads are flat and the dressing does not know it.** The world builder flattens a pad
  for every POI, so a waterfall's cliff, a gorge's bridge and a sinkhole's rim are all built on
  level ground and have to raise or sink their own landform. The Hidden Tarn and the sinkhole
  would read far better as ground the builder had actually cut. That is the world builder's
  side of the line, not this node's.
* **Two bridges do not cross water.** Larkbourne Ford is 335 m from the Larkbourne and the
  Glass Bridge 2 km from any river, so they are crossings over a dry bed with the brief's own
  thing under the arch. Honest, but a bridge wants a river; the positions belong to the
  sightlines stream.
* **The encounters each POI's data describes are not spawned here.** Every POI carries an
  `encounter` sentence ("two bandits shake down late travellers after dark") and the dressing
  reads it only for what it implies about the props. `worldgen/encounters.py` places the
  country's spawns by density and does not know POIs exist.
* **Nothing in a dressing is interactable except the Hearthstones.** The chests, the job-less
  camps, the Sayers' books and the strongbox in Wisp Hollow's chimney are scenery; they are
  forge props, not `WorldContainer`s or `WorldItem`s.
* **No NPC stands at any of them.** The lamplighter of the Lantern Causeway, the toll-keeper of
  the Chain Bridge, the knight in the Headless Watch's eye and the hermit of Willow Isle are
  all named in the data and all absent; their props are set out as though they had just
  stepped away. That is the content stream's.
* **The One Poppy does not read from thirty metres.** The dressing is honest to the fiction —
  one red poppy in a square kilometre of grey grass, with a ring of stones somebody set round
  it and a cup of water beside it — and photographed from the plan's distance the poppy is a
  speck and the ring is pebbles. It wants a mark a person would see: the ring at three times
  the size, or a low cairn. That was not changed blind, because the last unverified
  improvement in this work (the bank behind the waterfall) was worse than the fault.
* **The Headless Watch reads as a head now, and a little like a helmet.** The brow band that
  fixed the egg is a continuous ridge, which from the approach reads as a visor, and the
  carved stone at a 3.4 m unit is very smooth beside the region's other Oroth work. Breaking
  the band over the sockets and coarsening the surface would finish it.
* **The Thirteenth reads as fallen masonry, not as a body.** The torso, arms and legs are
  boxes at a colossus's scale and from most angles they merge into one long mass. The
  excavation, the spoil and the Sayer camp at its head carry the scene; the figure does not.
  It wants separated limbs and a shoulder taper.
* **The far ring builds silhouettes but they are not impostors.** A far-ring dressing draws its
  LOD1 meshes out to 950 m, which is cheap enough at 55 POIs but is not what a proper
  impostor would cost.

## Four small holes in the systems

All four were found the way the ones above were found: by asking what the code and the data
promise that nothing in the game actually does. `tools/unwired.py --verbs` went from 43
test-only verbs to 41, and `tools/dead_data.py` from 6 unread content keys to 6 (the two this
work could have closed were not the ones it names; see the end).

**Furnishings were promised and unbuyable.** DESIGN §5.14 ends "Furnishings bought".
`PropertyRegistry.add_furnishing()` and `furnishings()` were written, saved and covered by a
test, and nothing else in the repository called either — so the promise was a field in a save
file. Six furnishings ship now (`items/furnishings.json`: a hearth rug, bed hangings, a settle
chair, a shelf of jars, a book press and a banded oak chest), each naming a prop *kind* the
forge has already built rather than an asset path, so a rug is woven from whatever cloth its
region makes. They are sold from the landlord's side of the deed screen — the board outside a
house you own, which now asks rather than guesses: rent waiting, letting, and the furnishings
on offer, each its own button. `HouseInterior.dress_furnishings()` puts them in the rooms when
that house is built, at a spot *derived* from the room (a lattice of candidates scored by
distance from whatever the dressing pass already put there, deterministic per house) because a
house you buy has no recipe line for a rug. Nothing but the item ids goes in the save.

The six deeds on sale still name interiors the forge has not built — `property.gd` has always
said so — so the mechanism is real and the houses to walk into are not there yet.
`test_furnishings.gd` stands it up against a real house's real rooms and the real positions of
its resident's things; when those houses are forged, nothing has to change.

**The job boards never listed a job.** `Social.take_quest()` was reached only by tests, and so
was the whole radiant layer behind it: `Jobs.board_offers()` asked the quest-log participant
for a `generate()` method that `QuestLog` does not have — it *holds* the RadiantGenerator, and
`Social.board_jobs()` is what drives it — so every board in the country fell through to the
economy's own parcel deliveries, every time. Six templates, bounties and hunts with
region-appropriate quarry, written text and per-board daily cooldowns, and no notice post in
Wickmere had ever shown one. Both halves go through the façade now.

Wiring it exposed two more: the board announced `quest_started` itself on top of the one
`QuestLog.start()` already emits, and announced it even when the quest refused to start; and
`RadiantGenerator` handed notices back out of a board's cache, and restored them from a save,
without registering them with the quest log — so every job still hanging on a board in a
loaded game answered "cannot start unknown quest" when taken. A new game cleared the log and
left the board cache, which is the same divergence.

**Two danger promises the data broke.** Fixed, and most of both was `tools/balance.py` reading
the wrong numbers: a spell attack's damage lives in the spell, not the attack, so a caster
scored zero three casts in five; a bleed or a poison goes on taking health after the blow, past
armour; and `guaranteed` loot was skipped, so a sallowjaw read as worth three marks when the
hide it always leaves is worth thirty-four. Four enemy numbers then changed, each odd on its
own terms. DECISIONS.md has the reasoning and what was left alone.
`tools/tests/test_balance.py` fails the build if either ordering inverts again.

**`systems/exploration` had no README.** Now it has one, and ARCHITECTURE §5 has its row plus
a note on `GameServices`, which installs the ten non-autoload world services and appeared
nowhere in ARCHITECTURE at all — the reason a system can ship a working `ensure()` and never
run. Its save section is deliberately none: everything `PlaceDiscovery` learns is GameState's
and rides in its section, and what the node holds is a poll timer and a cache rebuilt from the
content pack on first use.

**Two things found in passing and not fixed.** `test_deed_screen.gd` called
`registry.owns(DEED)`, which does not exist — the call errored, the test method aborted, and
the runner counted it green, so the press-the-button test for buying a house had been asserting
nothing since it was written. It says `is_owned` now and the assertions do run (and pass: the
behaviour was right all along). And `sells_deeds` on Ellard's def is still dead data: the
honest use of it is a steward-mediated sale, which would undo the direct board route that was
just built, so it is left for whoever authors that dialogue. `beds` on the deed items is
likewise still unread.

## The country, looked at

A pass over the land, the cover on it, the roads and the light, judged by opening the
pictures rather than by reading the numbers off a build. What follows is what moved, with
what it cost, and what is still wanting.

**There were no shadows anywhere, and the reason was the sun.** Three separate frames were
reported as flat — a Merrowby street at nine in the morning, a four-pylon chain bridge in a
steep Skerrow valley at two in the afternoon, the opening view of Cinderlea. In all three the
shadows were being drawn and were the size of a doormat, because four of the six regions ran
a sun between 60° and 94° above the horizon at their own review hour. `sun_elevation_scale`
is the per-region knob for exactly this and only three regions set it, so the rest inherited
a `-cos(hour)` curve that reaches vertical at noon. At each region's review hour:

| | before | after | shadow as a fraction of height |
|---|---|---|---|
| Hearthvale 09:00 | 59.6° | 29.7° | 0.59 → 1.75 |
| Brightwater 12:00 | 94.0° | 51.7° | past vertical → 0.79 |
| Briarwold 10:30 | 74.8° | 44.9° | 0.27 → 1.00 |
| Skerrow 14:00 | 79.9° | 31.6° | 0.18 → 1.62 |

Sedgemire (21.3°) and Cinderlea (3.2°) were already low, which is why neither was among the
frames that read as flat. A cottage now throws ten metres of shadow across the green instead
of three. Two hours went into a wrong hypothesis first — that Terrain3D does not receive
directional shadows on the Compatibility renderer — and `game/tools_gd/shadow_probe.tscn` is
the instrument that disproved it; it is committed, because "this frame has no shadows" has
three unrelated causes and a screenshot cannot tell them apart.

**The ground had no cover.** Hearthvale carried 45 flora instances a hectare, one plant per
26 m², and four regions named no ground carpet in their flora list at all. Measured over 140
sampled cells, flora per hectare now: Hearthvale 761, Briarwold 565, Cinderlea 464,
Sedgemire 461, Brightwater 406, Skerrow 295. Villages were the worst of it and for a separate
reason: scatter was excluded from the whole of a settlement's pad, and the street camera
stands 46 m inside Merrowby's 63.7 m pad, so that frame contained no growing thing by
construction. `worldgen/pads.py` now gives a normalised radius rather than a flag, and low
cover returns to the green inside 0.22 of it and the verge beyond 0.90 — either side of the
20-to-50 m band the settlement builder rings its houses through.

**The fields have hedges.** This was PROGRESS's "next" item for some time and is DESIGN §4.1's
first line. `worldgen/hedges.py` lays 122 477 hedge pieces along the parcel boundaries
`fields.py` has been drawing all along: a run of segments turned to lie *along* the boundary
(from the tangent of the distance field — laid at random angles they read as loose bushes),
hawthorn every 27 m, an oak standard every 70, gateways from a low-frequency field, and always
a gap where a road crosses. Skerrow's boundaries take drystone wall instead, so the moor is
enclosed too. 774 apple trees stand in rows in Tamwick's parcels. None of it was affordable
with what existed — the nearest asset to a hedge was a 5 610-triangle hawthorn — so
`tools/forge/gen_ground_kit.py` builds 2.2 m of hedge in 66 triangles, with a gate post and a
milestone beside it. `worldgen/roadside.py` adds 6 024 milestones, junction signposts and
post-and-rail frontages.

**Every per-instance tint had been thrown away.** The builder has always written a distinct
colour per plant — 88 different greens among 91 grass clumps in one Merrowby cell — and
`foliage_wind.gdshader` never read `COLOR`. Turning it on immediately exposed two faults that
had been latent in the data for as long: the jitter drew three independent per-channel
normals, so it moved hue rather than lightness and the moor came back scattered with yellow,
violet and blue clumps; and the palette was being applied twice, because the forge already
builds each asset in its region's colours, which turned gold barley and red poppies into
orange slabs. Both fixed; rules now carry a `tint_strength`.

**Light.** Each region's recipe now comes from its own identity sheet rather than from a
narrow band around the middle. Fog density spans 0.00014 (Skerrow, thin cold air) to 0.00125
(Sedgemire, where the fog is the region) against a previous 0.00016–0.00085.

### What the drop test says

The full 42-shot sheet, seven images a region, so **the landform axis binds** (DESIGN §10.1):

| | before (ASSESSMENT) | after | bar |
|---|---|---|---|
| colour | 0.64 | **0.74** | — |
| landform | 0.21 | **0.12** | 0.55 |
| together | 0.55 | **0.71** | 0.80 |

Colour and the two together moved a long way and the test still fails, on both bars. (Measured before the last change of the pass: Cinderlea's sun was raised from 3.2 degrees to 9.2 at its own hour afterwards, because at 3.2 the energy curve had already halved it and the region's ground shots came back nearly black. That is a change to one region's light which these numbers do not include.)

One further caveat, and it matters most to the landform figure: the sheet was shot before the fix for `poi_builders.gd` landed, and that script was failing to parse, so **none of the fifty-five dressed points of interest were standing in the world when these frames were taken**. The towers, bridges, shrines, stone settings and giant bones are exactly the distinctive geometry the landform axis reads, and every one of them was absent. The next sheet should be shot with them in. The
landform figure went *down*, and below the 0.17 chance line, which is the honest cost of this
pass and worth stating plainly: the landform signature reads the skyline, the ruggedness and
where the detail sits down the frame, and giving all six regions a dense near field of
similar tufts made the bottom of every frame equally busy. The cover was added uniformly
because the ground was uniformly bare; what it needs next is cover that differs in *structure*
between regions — a flat reed horizon against a crag line — and not simply in tint. The
confusion pairs say the same thing: Briarwold reads as Sedgemire and Skerrow as Sedgemire.

### What it costs

Measured across the same 42 shots: **one frame** is over budget, the Merrowby street at 1511
draws and 1.59 M primitives against 2000 and 1.5 M; nothing else exceeds either, the worst
other frame is 1.23 M, and the median is 0.68 M. Before this pass that street was 1330 draws
and 1.18 M. The new draw attribution is what found where it goes — 645 apple trees and 1234
hawthorns in one frame at ~5 700 triangles each, against 4399 grass clumps in three draws —
which is why the orchards went back to Tamwick alone and the hedge trees thinned from every
13 m to every 27. The world build went from 217 s to 260 s and from 346 306 scatter instances
to 3 473 920.

### Still wanting

* **The ground cover does not yet read as a carpet at eye height.** It reads as tufts on turf.
  A true carpet needs an order of magnitude more instances than the primitive budget allows at
  cell granularity, so the honest next lever is the terrain albedo itself, not more instances.
* **Hedges read as dotted rather than solid at 400 m**, where the far ring keeps 40% of them.
* **Skerrow's drystone walls are placed but have not been judged in a capture** at close range.
* **The gate posts mark gaps but no gate hangs in them**, and the five signposts point nowhere
  in particular: the asset has arms, but nothing writes the names of the places the road goes
  to onto them, though every road is named for the two settlements it joins.
* **Bridge abutments were not done.** The road crossings are left clear, as asked.
* **A village street still has a bare green in front of it.** Cover returns to the green and
  the verge but not to the 20-to-50 m band the houses ring through, because a grass tuft
  standing inside somebody's cottage is a worse fault than a mown green. Putting cover there
  needs the building footprints, which are raised at runtime and are not known to the builder.
* **The Briarwold vista shot is inside a tree.** `make_default_plan.py` puts that camera 12 m
  above the highest ground within 600 m, which in a forest of 30 m oaks is inside the canopy;
  the vista shots skip the `clear_spot` check the ground shots use. One of the seven Briarwold
  images in the sheet above is therefore a photograph of leaves, and the drop test scored it.
## Sightlines, answered

DESIGN §4 ends "placed with sightlines: each POI names at least one other POI it should be
visible from", and `tools/sightlines.py` had been saying for a while that the land did not
agree: **90 authored sightlines, 54 clear, 36 the ground refused, and 10 POIs that no vantage
could see at all.** Until they were answered, surveying from those vistas found nothing and
the POIs behind them could only be found by walking into them, which is the right way for the
feature to degrade and no way to leave it.

They are answered. The tool now reads **90 authored sightlines: 87 the land honours, 0 it
refuses, 3 into hidden valleys.** Every POI outside those three can be seen from somewhere.

### First, the heights were guesses

`LANDMARK_M` — how far a thing of each kind stands above its own ground — was written before a
single POI had geometry. Now that all 55 are dressed, `poi_builders.gd` is the authority, and
four of the twelve numbers were wrong by a factor. A watch drum is 7.6 m and carries its
fire-bowl to about 10, not 18; the Tumbled Watch is 5, because it is lying down. A waterfall's
face is 11 to 13 m, not 24. A standing gable is 4.6 m and the tallest Oroth column 7.2, not 8
across the board. A bell buoy is a barrel with a post and a cage on it and the One Poppy is a
poppy, so `strange` is 2.5 and not 6. Three went the other way: the Hart Bones' antlers reach
15 m, a menhir set at 1.15–1.55 scale stands 5, and the Chain Bridge's pylons are 7.8 m over
their deck.

Correcting them made the reading **worse** before it made it better — 53 clear and 37 refused,
with the Glass Falls joining the POIs nothing could see. That order is recorded because it is
the evidence that these are measurements and not a fit, which is the same reason the per-kind
heights' own arrival is recorded above.

### Then, every line

Nineteen POIs moved and seven vantages were replaced. No POI was deleted and no line dropped —
the authored count is still 90 — and the terrain generator was not touched, because the land is
built last and the places land on it (DECISIONS, 2026-09-20).

| line | what was wrong | what was done |
|---|---|---|
| Three Sisters → Seven Stones | 178 m of mountain at 707 m; the stones lay in a bowl at 464 m that nothing in the world could see into | the stones moved 161 m onto the ridge at 577 m, where a setting of stones belongs; the line replaced by the Clanless Camp, who have no stone of their own and can see all seven |
| Watch of the Gate → Seven Stones | 96 m over | the same move answers it |
| Hidden Tarn → Watch of the Gate | 90 m of mountain | the Watch moved 70 m along the pass shoulder; its second vantage is the Seven Stones at 470 m, and the two see each other |
| Chain Bridge → Three Sisters | 135 m of ridge | replaced by the Clanless Camp, 1044 m |
| Kharrow Hold → Chain Bridge | 21 m — the hold's own level platform hides a bridge 112 m off and 47 m below it | the bridge moved 102 m onto the lower shelf, 192 m out, where the hold looks down on it |
| Three Sisters → Chain Bridge | 141 m of ridge, and nothing in Skerrow can see into that hollow | the line went to the Breach, which carried only one vantage and can hold Weaverdeep's; the Chain Bridge keeps the one its own brief names |
| Thornmarch → Breach | 30 m over | the Breach moved 172 m north along the Briar |
| Foxfire Falls ↔ Charcoal Camp | 55 m and 49 m, both ways | Foxfire Falls moved 161 m up its ravine to 164 m; both ways clear, and Weaverdeep's line with them |
| Weaverdeep → Foxfire Falls | 39 m over | the same move |
| Thornmarch / Standing Moot / Hunters' Stand → Hart Bones | 42, 22 and 14 m over; the skull lay in a hollow only Brightwater, 3.4 km off, could see | the Hart Bones moved 228 m onto the rise at 196 m |
| Hart Bones → Hunters' Stand | 13 m over | the same move |
| Sunken Choir → Thirteenth | 23 m over | the Thirteenth moved 291 m onto the shelf at 116 m, still 420 m from the ring it walked away from |
| Headless Watch → Thirteenth | 20 m over | the same move, and the Watch's own below |
| Sunken Choir → Headless Watch | 12 m over | the Headless Watch moved 102 m |
| Glass Bridge → Glass Falls, Sunken Choir → Glass Falls | 14 m and 7 m over | the Glass Falls moved 100 m along the scarp |
| Greyfold → Cold Fire, One Poppy → Cold Fire | 14 m and 3 m over | the camp moved 72 m toward Greyfold, whose people sat down in it |
| Cracked Toll → Bell Meadow Stones, Merrowby → Bell Meadow Stones | 9 m and 8 m of chalk; the stones lay in a hollow at 27 m | moved 89 m onto the rise at 34 m, nearer the crater whose crown they carry |
| Fallen Hand → Rib Cathedral | 9 m over | the ribs moved 40 m |
| Fernhold → Mossbridge, Oiled Stone → Mossbridge | 8 m and 3 m over | Mossbridge moved 120 m, still 101 m off the road it carries |
| Pilgrim's Ash → Pilgrims' Bell | 7 m over | the bell moved 80 m along the pilgrim road |
| Tollmere → Bell Buoys | 6 m of the city's own shore, and there is no water Tollmere can see to move them onto | replaced by the Sayers' Spire at 655 m: the Sayers tuned the buoys, so it is their spire that watches them |
| Gullhithe → Bell Buoys | 5 m over | replaced by the Long Stride at 1342 m: you cross the causeway and the field of bells is off the rail |
| Tollmere → North Cliff Beacon | 6 m over | the beacon moved 28 m along the cliff |
| Merrowby → Larkbourne Ford | 3 m of chalk — and the ford stood 335 m from the Larkbourne | moved 337 m onto the river it is named for, which answers the dressing stream's complaint as well |
| Wardens' Rest → Tumbled Watch | 3 m over at 1005 m | the tower moved 82 m further down its dry valley |
| Tollmere → Willow Isle | 3 m over | the islet moved 20 m |
| Singing Yew → Ansel's Hedge Shrine | 3 m over | the shrine moved 20 m |
| Singing Yew → Foxglove Dell | 3 m over | left refused: it is a hidden valley |
| Frostmother's Cradle → Hidden Tarn | 146 m over | left refused: it is a hidden valley |
| Cantor's Seat → Hushline Stair | 42 m over | left refused: it is a hidden valley |

Every POI stayed in its region and in character: the ford is on its river, the bridges on
crossings, the stones on skylines, the camps in hollows.

### Two things the first pass got wrong

**A pad flattens the ground under the POI it moves to**, so the height a POI is aimed at is not
the height it lands at. Mossbridge and the Watch of the Gate were placed on ground that read
clear before the build and came up 2 m and 5 m short after it, because their new pads took 2
and 5 metres off the knoll each was standing on. They were re-aimed at ground that clears
whatever the pad does to it — every candidate re-tested at ±3 m of pad level — and the second
build held. Anything else that picks positions off `heights.r32` should expect the same.

**The released Chain Bridge line was first pointed at the bridge from Weaverdeep**, 3.7 km away
through a mountain, which is the same mistake in miniature: a line is not answered by being
given to somebody else's name, only by being given to ground that can hold it. It went to the
Breach instead, which is 240 m from the Thornmarch and had only one vantage.

### What the tool says now, and what keeps it saying it

`tools/sightlines.py` counts the three hidden-valley lines apart rather than as faults. It
already made that distinction for the POIs and not for the lines, which is why a valley doing
its job read as a placement error.

`tools/world/tests/test_sightlines.py` marches the same audit over the built world and fails if
any line is refused, if any POI outside the hidden valleys loses its last vantage, if the
authored count falls under 90, or if anything but a hidden valley claims that exemption. It
reads the full 4096 build rather than building its own at 1024 the way `test_build.py` does,
because a coarse build smooths exactly the hills that were in the way.

**Some of it is thin.** Nine of the 87 clear lines clear the ground by less than half a metre
— Pilgrim's Ash to the Pilgrims' Bell by 0.15 m, the Choir to the Thirteenth by 0.17. Widening
them means moving POIs that are currently right, and moving a POI moves its pad, which is what
went wrong the first time. They are left as they are and the test is what notices if they go.
Two of them (the Thornmarch's lines to the Hart Bones and the Breach) fall the other way on the
quarter-resolution `runtime/heights_1024.r32` that a headless run samples when Terrain3D is not
loaded; both targets have another vantage, so nothing goes dark either way.

### What moving a POI touches

Nothing needed a code change: the dressing reads its position, pad radius and region out of
`pois.json` at runtime, so a moved POI arrives dressed where it now stands.
`tools/capture/plans/pois.json` bakes camera positions and was regenerated. Two quest
objectives name POIs that moved — the Tumbled Watch (`reach`, radius 140) and the Breach — and
both still sit where their own text says they are. One side effect is worth knowing: `camp` is
in `ROAD_KINDS`, so moving the Cold Fire moved a road with it.

### Two things found in passing

**A graded road can become a levee.** `carve_roads` limits a road's elevation profile to 11%
and writes it into the heightmap. Where the natural ground falls away faster than the road
descends — the spur out of Kharrow Hold toward Gullhithe is the one that showed up — the road
becomes an embankment standing as much as 100 m above the ground on both sides of it, which
samples as a knife-edge arête that nothing in the region's shape function put there. It is
invisible to a sightline audit, because the road holds the line of sight open, and would be
very visible from the ground. That is the roads stream's.

**`poi_builders.gd` did not parse.** A paving loop under the Toll's clapper declared `var a`
for an angle in a function whose span end is already called `a`. `poi_dressing.gd` could not
then resolve `PoiBuilders`, so `world_pois.gd`, `world_streamer.gd`, `world.gd` and the debug
console failed to compile behind it and `test_pois.gd` would not load: the suite read 1143
tests with 2 failures instead of 1152 with 1. Renamed and noted here because the file belongs
to the dressing stream.

### A landform apiece, proposed and not built

The drop test's landform axis (DESIGN §10.1) reads 0.21 against a 0.55 bar. This is a proposal
and nothing here is implemented. `tools/uniqueness_check.py` was not run for it — it wants six
frames a region and the capture stream is using the display — so the regions named are the ones
whose *shape functions* have the least silhouette to give, not measured confusion pairs. Each
is a term the region's own shape could grow, in the manner of the Hearthvale escarpment
(DECISIONS, 2026-09-20): one primary landform the region has and nobody else does, generated
from the region's own geometry with no reference to where anything stands.

* **Brightwater — the Mere's raised beaches.** `shape_lake_basin` is a 13 m plane with a tanh
  wobble on it: in silhouette a straight line, which is why a lake cannot be told from a marsh
  with the colour taken out. The Mere has fallen since the Toll came down, and a lake that
  falls leaves strandlines. Terrace the basin against the lake's own signed distance field,
  which the shape already holds: three or four level benches 2.5–4 m apart out to about 900 m
  from the water, each cut through by the streams off the downs. The skyline becomes a flight
  of steps down to the water and the causeway has something to climb.
* **Sedgemire — levees.** `shape_delta` carves two braided channels; what a real delta has and
  this one does not is the silt bank either side of each channel, a metre or two above the
  marsh, which is the only dry line in the country and exactly what a boardwalk town gets built
  along. A ring term on the same channel field — up where the channel distance is 0.20–0.30,
  down inside it — gives a flat horizon *striped* by long low banks. Nothing else in Wickmere
  makes that shape, and it explains Isseva.
* **Briarwold — the granite stair.** `shape_forest_rise` climbs to the Briar on a clean ramp
  (`0.05 * clip(X - 900)`) with tor blobs sprinkled over it. Old granite does not ramp; it goes
  up in benches. Terrace the rise at about 18 m with a soft knee and put the existing tors on
  the tread edges rather than at random, so the region reads as stacked flats with rock on
  every lip — and the ravines the falls need already step where the benches do.
* **Cinderlea — the street plan under the ash.** `shape_ash_plateau` terraces near the Choir
  and pits elsewhere, which at a distance is noise. The region is ash lying over a Builders'
  city: give the whole plateau a very low rectilinear ripple, ±1.2 m on one bearing at a 60–90 m
  period, damped where the terraces already bite. At the metre scale the ground is
  unnaturally straight and repeating, which no natural landform does and no other region here
  would show.

Skerrow and Hearthvale are left alone: the karst has ridges, terraces, gorges, sinkholes and a
moor, and the downs have the escarpment. Two costs are real and should be counted before any
of it is built: terracing Brightwater moves the shore that the Long Stride, the Shingle Shrine
and Tollmere's own pad stand on, and levees in Sedgemire will push the marsh roads onto them,
which is correct but is a change to where the roads go. If the axis is still under the bar with
four new landforms in, the next thing to suspect is the sample — six frames a region, as §10.1
says.

## What the forge owed, and the four diagnoses that did not survive measurement

Six things were owed by the forge, and four of the six turned out to be a different fault
than the one written down. That is the pattern worth carrying forward more than any of the
individual fixes: every one of these was recorded by somebody who had reasoned about it
carefully, and the measurement disagreed each time.

**The forge could not build anything at all on the machine it runs on.** Every generator died
on its first object. The forge is written against Blender 4.0 and 4.2.3 is what is installed:
`Mesh.use_auto_smooth` is gone (4.1 replaced it with the `shade_smooth_by_angle` operator),
the glTF exporter renamed `export_colors`, and Blender's bundled Python has no Pillow, so
every bake ended in `'NoneType' object has no attribute 'fromarray'` with no mention of what
was missing. Three version guards in `lib/scene.py`, `lib/export.py` and `lib/__init__.py`,
and `lib/bake.py` now names Pillow and the interpreter that needs it instead of dying on a
None. Worth knowing before anyone rebuilds an old asset: a thing rebuilt under 4.2 is *not*
byte-identical to its 4.0 twin — the mug came back 0.108 m instead of 0.110 and its LOD2
differs by two triangles — so the rule that untouched assets stay byte-identical means
untouched, not rebuilt-and-compared.

**Eleven stand-ins lied about their size.** `test_prop_library` has been red on this for a
while: `PropLibrary.STAND_IN` pointed a lantern at a `bucket`, a pair of boots at a `crate`,
a brewing copper at a `barrel`, and the written size in `HouseInterior._placeholder_size` was
out by more than a quarter in each case. The answer is not a better substitution table; the
forge builds them. Ten new kinds in `gen_props.py` — `bowl`, `plate_stack`, `paper_stack`,
`phial`, `jar`, `mortar`, `candle_stub`, `boots`, `lantern_hand`, `copper` — at the forge's
own texture weights, grounded, and every one rendered in `asset_review.tscn` beside a known
trestle. Five of them failed that review and were rebuilt: the boots read as bleached planks
with soles, the mortar as a dark vase, the candle stub as a fresh candle, the paper stack as
more planks, and the copper's setting had daylight showing between its blocks. `prop_heights.py`
now reads *52 prop kinds have a written size; 0 meshes differ by 25% or more*.

**Cave floors, the dune ripple.** Covered above under Known issues: the floors were flat all
along and the shells had no normals. Two attempts at the recorded fix — masking the noise
around the floor, then flattening the shader's `broad_fade` — changed nothing measurable and
were reverted rather than kept as decoration.

**The tunic's sleeves.** ASSESSMENT lists "tunic sleeves are wider than the forearm under
them", and a finished character does show a leg-of-mutton shoulder. Distance from every sleeve
vertex to the body surface beneath it, median: tunic 19/14/13 mm at shoulder, upper arm and
forearm, against its own design of 11. The garment that stands off is the **gambeson** at
31–38 mm, which is a padded jack and is meant to; half the presets in the lineup wear one. The
robe's 40 mm forearm is its sleeve bells. Nothing was widened or narrowed — the numbers went
into `lib/cloth.torso_region`'s docstring and ASSESSMENT's weak list is corrected, so the next
screenshot does not re-open it. Two earlier measurements of mine were wrong before the third
was right, which is in the commit message.

**Three body variants shipped as a skeleton with nothing on it.**
`game/assets/models/characters/bodies/{child,heavy,slight}` each held a rig and no geometry, so
`CharacterAppearance.body_variant()` had nothing to select and the build slider was a uniform
widening of one rig. `slight` and `heavy` are built and skinned to `WM_Humanoid_v1` and
`HumanoidModel` wears them (worst joint displacement 3.3 mm and 1.9 mm — they ride the shared
rig honestly). **`child` is left undone on purpose**: at child proportions the worst joint is
476 mm out and the summed error over 29 bones is 9.2 m. A child is not a scaled adult, and
doing it properly means its own skeleton and its own bake of the 70 clips, which is a piece of
work and not a wiring change. A child NPC is still a small adult until that is done.

**The Name-table** now exists as a mesh as well as a name — see above.

### Left for others, found in passing

* **`game/world/pois/poi_builders.gd:923` does not compile.** A variable named `a` is
  re-declared inside a `for i in 22:` loop. `test_pois.gd` therefore fails to load, and
  `./run.sh smoke` exits 1 because of it *while printing* `SMOKE: PASS` with zero logged
  errors over all 24 interiors. Anyone reading that exit code is reading the parse error, not
  the interiors.
* **Character body GLBs embed their textures** (bufferView, no uri) instead of referencing the
  external PNGs as CONTRACTS §4 requires, which leaves the loose PNGs beside them unreferenced
  — including stale doubled ones such as `heavy_heavy_albedo.png`.
* **Two dependencies were undeclared**: `scikit-image` and `fast_simplification` (trimesh 5
  moved `simplify_quadric_decimation` out). Both are in `tools/requirements.txt` now.

## The painted look: six lights, a sky, water that mirrors it, and the lamps after dark

The frames were competent and flat: even light, one layer of fog, a gradient for a sky with
grey blobs in it, water that was a grey plane, nights that were dark rather than lit, and six
regions told apart by the colour of their ground more than by their light. This pass is the
light. It stopped, on the user's order, before the after-sheet and the drop test were shot:
what is measured and what is not is said plainly below, and the Next list at the end is the
rest of the brief in order. Everything was measured on the world in the main checkout, built
2026-09-22 12:56:09Z and still that build when this was written.

### The cameras first, because a photograph of leaves is not a measurement

The Briarwold vista stood twelve metres up inside a giant oak: `make_default_plan.py` put every
vista above the highest ground near its viewpoint and never asked what was growing there. The
plan's scatter index now carries every tree as a cylinder of crown, its reach and height read
from the forge's own meta and scaled per instance, so a lens is in a crown only where it is
inside one and a line of sight is blocked only where it passes through one. A vista takes the
highest of a dozen candidate spots whose lens is clear and whose line to its target the land and
the crowns allow; a landmark shot swings its bearing fifteen degrees at a time until it can see
its landmark. **The recorded diagnosis was half of it**: the Briarwold's *landmark* camera was
also looking at the Grandfather through the crowns on the rise in front of it (it turned 45°;
Hearthvale's turned 15°). `horizon.json` is generated now (`--horizon`) from the same vantages --
the hand-written one had its Hearthvale camera in the grass and its Briarwold camera in the
crowns -- and `--look` writes seventeen frames the drop-test sheet never shows: dusk and dawn at
each region's own sunset (the sky follows the sun's height, so "19:24" over the Mere is already
night), night, the lamps, the Mere at eye level, and four waterfalls, re-aimed at runtime at
each fall's own sheet (`frame` in the plan; the capture runner reads the sheet's facing off its
mesh). `tools/tests/test_capture_plan.py` pins the crown model and the committed plans.

Regenerating the plan also moved every ground shot, which is not this change: the committed plan
had been drawn from an older build and the region mask under it had moved. The baseline was shot
on the regenerated plan, from a snapshot of the untouched game (`git archive 7d1652e4 game`), so
before and after are the same cameras.

**The drop test's `--json` had never worked**: it read two variables before assigning them. On
the regenerated plan, before any change to the light, 42 images, seven a region:

| | colour | landform | together |
|---|---|---|---|
| recorded in "The country, looked at" (older plan, no POIs standing, a frame of leaves) | 0.74 | 0.12 | 0.71 |
| baseline, regenerated plan, landmark cameras on their old bearings | 0.81 | 0.26 | 0.64 |
| **baseline, regenerated plan, clear landmark cameras** | **0.81** | **0.31** | **0.64** |
| after this pass | not shot | not shot | not shot |

### What the renderer we can capture actually draws

`game/tools_gd/render_probe.gd` turns each Environment feature on against a test stage and compares
the frame. On Compatibility, every feature the look leans on is drawn: exponential, height and
depth fog, aerial perspective, sky affect and sun scatter, glow, saturation, 1D and 3D colour
correction, ACES, AgX and exposure, the ambient sky contribution, and both the screen and depth
textures. Eight unshadowed omni lights cost no draw calls (30 → 30), one shadowed omni costs 4,
and a second shadowed directional light costs 22. Nothing below needed a Forward+ feature;
volumetric fog (which the Briarwold's `god_rays` drive), SDFGI and SSAO are behind the renderer
check and their own settings, and the first two are off by default.

### Six lights

Each region's `identity.light` is now a named palette of some thirty optional keys, extended
rather than rewritten: every old key survives. The table and the intent behind each light are in
`game/systems/atmosphere/README.md`; WORLD_BIBLE §6 points there. Harvest Gold (Hearthvale), Lake
Glass (Brightwater), Drowned Lantern (Sedgemire), Green Cathedral (Briarwold), Bone and Slate
(Skerrow), Ember Ash (Cinderlea). What each carries: the sun's colour high and near the horizon,
and its strength; shadows with a colour of their own (the fill's tint and how much sky is in it);
two fogs, a far aerial-perspective layer and a low haze whose top is held under the eye (Godot's
height fog ignores distance, so a haze top fixed in the world veiled the grass at your feet as
thickly as the valley a kilometre off); a grade -- saturation, contrast, exposure, and a 3D LUT
built from where the blacks lean, how warm the lights are and the midtone tint; vignette and
grain; the region's clouds; and moonlight, with the exposure opening after dark.

The day now follows the sun's height, not the clock (`SUN_KEYS`, keyed by elevation), so each
region's sky and light agree wherever its latitude puts its sun: Cinderlea's nine-degree sun at
half past four used to stand under a mid-afternoon sky.

### The sky and the water, and two faults that had been there all along

The sky shader is rewritten: a disc a degree and a half across with a halo, cumulus lit from the
side the light is on (the density a step toward the sun against the density here) falling into
painted steps with a silver lining, cirrus streaked along the wind, a stratus bank where a region
asks for one, a horizon that burns under a low sun and goes rose over a blue band opposite it,
and stars in two sizes, a band of milk and a moon at night. **The old sun disc was 11 to 14
degrees in radius**: its size was a 1 − cos of 0.03 that nothing ever set. Its declared
half-resolution pass was never read. The new disc was at first *mixed* over a sky that already
carried its own halo, and came out darker than its surroundings -- a dark lozenge over Cinderlea.
`game/tools_gd/sun_probe.tscn` measured the disc's centre at 0.58 against 0.83 five degrees above
it, with the grade and the glow each on and off, which put the fault in the sky shader rather
than the post; the disc adds now and reads 0.996.

The water shader wrote a world-space normal, up in green, into `NORMAL_MAP`, which Godot reads
as tangent space and rebuilds z from. **Every water surface in the game has been lit as if tilted
steeply away from the sun**: `render_probe.gd` draws a flat plane under an overhead sun at 0.659
mean brightness with no normal map, 0.662 with a true flat one, and 0.234 with the old encoding.
It writes a view-space `NORMAL` now, mirrors the sky's own zenith and horizon (published by the
atmosphere as linear globals) through a Fresnel term capped at 0.65, lays a path of glints under
the sun and the moon, breaks its shore foam into patches, and thins to nothing at the waterline.
The falls do use `falling_water.gdshader`: all four were framed from their own sheets and looked
at in the baseline (the Glass Falls as black glass, as written); they have not been re-shot under
the new light.

### After dark

POI dressing already hung real lights -- 27 `k.light` calls across its builders: camp fires,
shrine lamps, the beacon, bridge and causeway lamps, the wisps and the foxfire -- always on, and
faded out between 55 and 95 m. Settlements had none: the lakefolk's lanterns and the pilgrims'
braziers were props with no light in them, and every window was a black box. Now a window pane is
its own kind of box in the fabric whose vertex colour carries its coordinates across the glass
and, in alpha, how brightly the room behind is lit; the joinery shader paints glazing bars and a
hearth glow warmest low in the glass (a first cut at 3.2× the lamp colour came out as a white
lightbox under ACES; it is 1.25 now). Seven houses in ten have somebody home, with a lamp over the
door of each, and the dimmer rooms go out from about eleven until five.
`game/world/night_lights.gd` keeps every lamp, lantern, brazier, fire and lit window as one glow
MultiMesh for the whole country (one draw, at night only) and hands a pool of eight unshadowed
OmniLights (`video/night_lights`, ten at most, because Compatibility draws twelve lights on an
object) to the real-light sources nearest the camera. The moon takes the shadow cascades over when
the sun has set, on two cascades over 160 m. The night street (Merrowby at 22:00) went from 367
draws and 0.41 M primitives (the baseline night had no moon shadows and no lamps) to 889 and 1.13
M with four cascades, and to 617 and 0.75 M with two -- well under the same street by day.

### What it costs, measured

The worst frame, the Merrowby street at 09:00: **1521 draws and 1.613 M primitives before, 1502
and 1.592 M after** (`captures/tune_4/perf.json` against `captures/before/perf.json`). That is
inside run-to-run noise: the seven other shots of the same round moved by −3 to +14 draws and
−0.012 to +0.023 M against the same baseline, with nothing of this pass able to account for it,
because by day this pass adds a vignette rect (and a grain rect in Cinderlea) and nothing else
to draw -- the glows, the lamp pool and the moon's cascades are all off. I did not run one build
twice to measure the noise directly; the spread is the evidence. The street was over the 1.5 M
primitive budget before this pass and still is; that is the scatter and tree LOD work, not
this. The unit suite is 1244 tests, 0 failed, 0 content problems, 0 script errors;
`./run.sh flow` passes all three starts with 0 errors; the tools tests are 19, all passing.

### Looked at, and what still reads badly

Four tuning rounds, 34 frames across the six regions at day, dusk and night, each opened and
looked at. What still reads badly: Sedgemire's landmark from 55 m is most of a whiteout (the far
fog and the haze together); the Briarwold's olive cloud steps read murky rather than painted;
the Mere from its landmark is still a pale sheet more than a mirror (the glint path shows only
toward the sun); dusk everywhere is warm enough that Hearthvale's and Cinderlea's are closer to
each other than they should be.

### Next, in order:

1. **Done and verified, in this worktree's `captures/`** (gitignored; the plans that make them are
   committed): the baseline sheet `before/` (54 frames, drop test 0.81 / 0.31 / 0.64 in
   `before/drop_test.json`), `before_horizon2/`, `before_look/` and `before_fix/` (the seven
   look frames whose hours or framing changed); the four tuning rounds `tune_1/` to `tune_4/`,
   of which `tune_4` is the current state; `render_probe/`, `sun_probe/`, `flow/`. Verified:
   suite green, flow 3/3, worst day frame unchanged within noise (1502 / 1.592 M against
   1521 / 1.613 M), night street 617 draws.
2. **Nothing is half-done in code.** Everything is on by default and has been looked at in
   captures except the Forward+ extras, which are off: `video/volumetric_fog` (which carries the
   Briarwold's `god_rays`) and `video/sdfgi` default to false and never enable on Compatibility;
   `video/ssao` keeps its old default and is Forward+ only. Switches for the rest:
   `video/color_grade` (the LUT), `video/night_lights` (0 to 10 real lamps; glows still draw),
   `video/glow`, and any key of a region's `identity.light` in
   `game/content/packs/core/regions/regions.json` (the palettes are written by hand there).
3. **Shoot the after-sheets and measure.** With `free -g` at 4 GB or more, one Godot at a time:
   `xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 --audio-driver Dummy --resolution 1600x900 -- --capture=tools/capture/plans/default.json --out=$PWD/captures/after`
   (about an hour), then the same with `horizon.json` into `captures/after_horizon2` and
   `look.json` into `captures/after_look`. Open every frame. Then
   `python3 tools/uniqueness_check.py captures/after/regions --json captures/after/drop_test.json`
   and report colour, landform and together against 0.81 / 0.31 / 0.64. Acceptance: all three
   numbers reported, and if they do not move, say what the frames show and why; the landform
   axis is the terrain's and light is not expected to carry it to 0.55. One caveat on the
   comparison: the baseline's capture runner did not settle a region's six-second look blend
   before an exposure, so a baseline shot taken just after crossing a region border (the six
   street shots each do) may carry some of the previous region's light; the runner at this
   head settles it.
4. **`./run.sh perf`** (the interiors, which this pass does not touch indoors beyond the
   atmosphere's existing interior mode) and the street from the after-sheet's `perf.json`.
   Acceptance: every frame ≤ 2000 draws; the street's primitives no higher than 1.61 M.
5. **Tune what reads badly**, then re-shoot the frame and look at it: Sedgemire's
   `haze_density` (0.03) and `fog_sky_affect` (0.5) for `sedgemire_landmark`; the Briarwold's
   `painterly` (0.6 default) and cloud colours for `briarwold_vista`; Brightwater's water
   `reflect` (0.8, `game/world/water_surface.gd` REGION_WATER) for `brightwater_landmark`; a
   cooler `dusk_tint` for Cinderlea against Hearthvale's. The Briarwold's light shafts exist only
   on Forward+ (volumetric fog); a Compatibility version would be the cave forge's
   `light_shaft.gdshader` cones stood in clearings, which nobody has built.
6. **Re-shoot the falls under the new light** (`look.json`'s four `*_falls` frames) and look at
   them; nothing in the falls was changed.
7. **Measure the two costs nobody has timed**: the glow MultiMesh is rebuilt on the main thread
   whenever a settlement, building or POI registers or leaves (about a thousand sources, on cell
   loads), and the grade LUT (4913 texels of GDScript) is rebuilt at most every 0.4 s while a
   region's look blends. Both are suspects for a hitch at a region border.

Known risks: the POI dressing's own OmniLights are always on and do not count against the pool,
so beside the Long Stride the pool and the POI lamps together can pass Compatibility's twelve
lights on one object, and the extras are dropped without a word. The haze's top follows the
camera, by design, so it moves as you climb. None of the Forward+ extras has been seen, because
Forward+ does not run here. The before sheets live only in this worktree. They were shot from the
untouched game: `before/` from the worktree before its first game change, the rest from a
`git archive 7d1652e4 game` snapshot (`before_fix/` with this head's capture runner copied in, for
its `frame` re-aiming, which the old atmosphere ignores). Re-shooting them that way reproduces them.
## The shape of the land

A pass over the ground itself: the road that stood on a knife-edge, a landform apiece for the
six regions, and cover that differs between them in structure rather than tint. It was stopped
part-way by a stopping-point order, so it ends in two halves. **The roads, the rivers under
them and the staged-build check are finished, measured and on by default. The landforms and
the regional cover are built and partly measured, and are switched off** (`--recipe landforms`,
`--recipe cover`), because nobody has yet looked at them from the ground or put them through
the drop test. The numbers below are from three full 4096 builds in this worktree: the world
as this pass found it, the default build as it now stands, and a build with both recipes.

### The arete was two faults, and the diagnosis had half of one

PROGRESS recorded it as `carve_roads` writing an 11% profile into the heightmap "where the ground
falls away faster than the road descends". That is the second fault. The first is the router:
`build_graph` charged for climbing and gave nothing back for descending (`descent_bonus=0`),
and the roads are routed in one direction, so a road planned from Kharrow Hold down to the Mere
paid nothing to go straight over the edge of the mountain. `_grade` then limited the grade by
lifting the profile (a forward clamp, sixty passes, no reference to the ground), and the road
stood where the grade put it. The carve blended the land up to it across its shoulder.

**What changed.** A road is now routed twice: on the 16 m lattice to choose which side of a hill
to go, then again on a 4 m lattice inside 64 m of that line, with the knight's moves added so it
can zigzag. Grade costs the same both ways, quadratically past 10% and hard past 22%; every change
of heading costs something, so a switchback's legs are long; a cliff, and a cell standing proud
of or sunk into its own twenty metres (a knife-edge spur, a V-gully), cost enough that the road
crosses them rather than riding them; a road already laid is cheaper to follow than new ground,
so roads out of one town share a trunk and fork, and where one runs on another it takes that
road's level. The profile (`grade_profile`, every 4 m) is held within `cut_fill_m(width)` of the
ground under it -- 2.4 m for a track, 3.6 m for a town road, which is what a one-in-two batter
across the carve's shoulder allows -- and is never lifted to make a grade. Where the ground is
steeper than 11% plus that room, the road is steep: that is the honest failure, and the router is
what keeps it rare. No road builds up within 14 m of an authored sightline.

Measured with the ground read 2 m past each road's carve on both sides (above the higher side is
an embankment standing proud; below the lower, a cutting), raw, nothing discounted:

| worst road | before | default build | with both recipes |
|---|---|---|---|
| above both sides | **150.1 m** (Gullhithe - Kharrow Hold) | 4.8 m (Gullhithe - Kharrow Hold) | 7.5 m (Kharrow Hold - Grandfather Hollow) |
| below both sides | **67.0 m** (Gullhithe - Kharrow Hold) | 8.2 m (Kharrow Hold - Grandfather Hollow) | 14.4 m (Charcoal Camp - Gullhithe) |
| steepest grade of the carved road, 99th percentile of any road | 7.29 (the arete's flanks) | 0.45 (Gullhithe - Kharrow Hold) | 0.50 (Brindlecrag - the Clanless Camp) |
| steepest grade of the carved road, anywhere | 9.1 | 0.81 (Kharrow Hold - Grandfather Hollow) | 0.92 (Gullhithe - Kharrow Hold) |

What is left in those raw figures is the land's own relief -- a road along a spur is on the spur
-- and `tools/world/tests/test_roads.py` discounts it from the builder's own record of the land
each road was laid on (`road_profiles.json`, new, read by nothing in the game). It holds every
road of the built world three ways: graded within `cut_fill_m` of that land; the carved
heightmap under the centre line equal to the grade (away from pads and fords); and, from
outside, the land beside the road no lower (or higher) than the road by more than the land
under it already was, plus the carve's tolerance and 3 m for the land's curvature. The default
build and the recipe build both pass. The world this pass started from fails the last on twelve
roads, worst the Gullhithe road at 150.1 m against 6.6 m allowed.

**A test that passed the world it was written to fail.** As first committed, that last check
took the carved road for its own land wherever a build had written no record, which excused
every arete: run against the old world it passed. Found while writing this up, fixed (no record
now means nothing is discounted), and checked against the old world again.

### Rivers ran under the pads and roads laid on them

Found in passing, measured on the old world: pads and roads are laid after the rivers are cut,
and both flatten or grade whatever is under them. The Larkbourne Ford -- moved last session onto
the river it is named for -- filled 54 m of the Larkbourne with its own pad; the Three Sisters'
pad left 46 m of the Skerrow Water dry at the foot of the falls; each road crossing dammed its
river for 8 to 30 m. Six dry runs longer than 6 m in all. `hydro.keep_channels` cuts every
channel back through what was laid on it, holding a crossing to a ford 0.45 m under the
surface: 0 dry runs on the default build, 0 with the recipes, and a test holds it.

### Two recorded diagnoses that did not survive measurement

**"The pads module flattens under the original positions of POIs that were later moved."** Not
in a full build. Measured on the old world, the nineteen POIs moved last session have flat
pads at their new positions (0.00 m of relief within 15 m) and nothing flat at their old ones
(0.7 to 55 m of relief, the same as control points beside them); the scatter has 28 to 143
instances within 18 m of each old position and 0 to 5 at each new one. The one path that does
do it is the staged build: `--only textures` and `--only cells` reuse `heights.r32` from disk
and re-flatten pads in memory where things now stand, so a moved POI keeps its old pad in the
terrain and stands on unflattened ground, while the scatter clears a pad that is not there. The
manifest now records a checksum of every pad (`pad_fingerprint`) and a staged build refuses a
heightmap whose pads were laid for other positions. Tested.

**"`camp` is missing from ROAD_KINDS."** It is not, and never was: `ROAD_KINDS` has included it
since the first commit that defined it (6a5a84df), and last session's own note says so ("`camp`
is in `ROAD_KINDS`, so moving the Cold Fire moved a road with it"). What was true is that nothing
kept the world builder's kinds and the exterior's in step, so a test now reads
`Settlement.FABRIC` out of `settlement.gd` and requires `ROAD_KINDS`, `FABRIC_COUNT` and
`ROAD_WIDTH` to name exactly its kinds, with the same counts.

### Sightlines, and two that had been answered by accident

The old world read 90 authored lines, 87 clear, 0 refused, 3 into hidden valleys. The first
scratch build with the roads held to their carve refused two and left a third clear by 0.03 m,
and the reason is worth more than the fix: all three had been answered last session on a world
where a road cut as deep as its grade wanted. Beside the Clanless Camp the old road from
Brindlecrag had cut a trench that, worked back through the pad's blend, took the ground 30 m
from the camp down to about 264 m, 88 m under the pad (the old world reads that road 65 m below
the land on both sides 44 m from the camp), and the line from Brindlecrag looked through it.
Between Greyfold and the Cold Fire the old road had taken 1.7 m off the hump the line crosses.
The Long Stride's line to the Bell Buoys went the other way: the first router swam to Tollmere
instead of taking the causeway, and its fill rose 3 m into the line.

* **The Long Stride -> the Bell Buoys** -- answered by the road: a coarse cell counts as water
  only when all of it is, so the causeway is dry ground, and a route that crosses open water is
  re-planned over the whole lattice.
* **Greyfold -> the Cold Fire** -- the Cold Fire moves another 20 m toward Greyfold, to
  (-2260, 2760), where the line clears on the land itself and not on a road cutting.
* **Brindlecrag -> the Clanless Camp** -- left in place. The positions that clear it by a metre
  are 35 to 40 m down the cliff, where the pad would cut away the overhang the camp is named for
  ("Find the camp under the overhang"), and a 21 m move buys half a metre.

| | old world | default build | with both recipes |
|---|---|---|---|
| clear / refused / into hidden valleys | 87 / 0 / 3 | 87 / 0 / 3 | 87 / 0 / 3 |
| Brindlecrag -> the Clanless Camp, clearance | clear, through the old road's trench | 0.03 m | 0.03 m |
| Greyfold -> the Cold Fire, clearance | clear, over the old road's cutting | 1.07 m | 1.07 m |

### Built, measured, and switched off: a landform apiece

`worldgen/landforms.py`, the `landforms` recipe: applied to the composed land after the drainage
and the Mere, so the rivers, pads and roads that follow are laid on it. Each term comes from the
region's own geometry, with no reference to where anything stands (DECISIONS, 2026-09-20), and
is weighted by the region's blend so borders mix:

| region | the landform | relief | scale |
|---|---|---|---|
| Brightwater | raised beaches: the basin terraced every 3.2 m of height from 110 to 950 m back from the Mere; and on the open south and east shores a strandplain of dune ridges parallel to the water, each with a steep face to it and a long back | benches 3.2 m, ridges to 5.5 m | ridges 78 m apart, 35 to 600 m from the water |
| Sedgemire | silt levees either side of both channel fields `shape_delta` cuts; 34 cut-off meanders, crescent pools cut below the marsh table with a low rim | levees 2.2 m, pools to 3 m | crescents 55 to 130 m across |
| Briarwold | the granite stair: the rise terraced every 18 m with a soft riser, tors on the lips of the treads | 18 m steps, tors to about 8 m | treads 50 to 300 m deep |
| Skerrow | limestone scars across the 200 to 540 m band; about 900 shakeholes on the moor | 20 m steps, holes 3 to 7 m | holes 9 to 22 m across |
| Cinderlea | the Builders' street grid, 96 by 72 m blocks on a bearing of 23 degrees: streets 12 m wide sunk 2.8 m, blocks mounded up to 3.5 m | 6.3 m from street floor to block top | 72 to 96 m |
| Hearthvale | strip lynchets stepping the scarp face in flights; 26 lines of barrows behind the crest | lynchets 3 m, barrows 3 to 5.5 m | barrows 28 to 48 m across, in lines of 3 to 6 |

The ground under every place is left as it was out to 1.3 pad radii, nothing is raised within
14 m of an authored sightline, and the stepped landforms fade out on ground steeper than about
one in two: on Kharrow Hold's flanks the first scars came out as twenty-metre slots aliased
into a stair of texels, and every road off the hold dived into one.

**What it measured**, the recipe build against the default build (so the roads are the same
kind on both). The land band-passed to the walking scale (a difference of
Gaussians at 12 and 75 m, so roughly 50 to 300 m wavelengths), in metres, over each region's dry
land away from the world's edges:

| region | relief, median / 75th / 95th percentile, default | with the landforms | dry land moved over 1 m (over 3 m) |
|---|---|---|---|
| Hearthvale | 2.49 / 4.68 / 14.80 | 2.50 / 4.69 / 14.87 | 4.6% (0.8%) |
| Brightwater | 0.95 / 2.86 / 15.67 | 1.17 / 2.95 / 15.82 | 40.0% (2.7%) |
| Sedgemire | 0.59 / 2.16 / 25.94 | 0.57 / 1.90 / 24.95 | 12.5% (0.2%) |
| Briarwold | 5.70 / 9.90 / 18.57 | 6.14 / 10.65 / 19.20 | 56.1% (41.1%) |
| Skerrow | 9.23 / 18.29 / 37.90 | 9.24 / 18.35 / 38.10 | 8.4% (3.8%) |
| Cinderlea | 4.23 / 7.34 / 13.17 | 4.27 / 7.40 / 13.25 | 26.4% (1.9%) |

The finding I did not expect, and one reason this is off by default: **measured as relief at
50 to 300 m, the landforms barely move any region.** They move a lot of ground -- more than a
metre on 56% of the Briarwold's dry land and 40% of Brightwater's -- but the land already had
metres of relief at that scale, and a 3 m bench or a 2.8 m street adds to it in quadrature.
Whether they read from a walking camera is a question for the camera, and the camera has not
been asked.

### Built, measured, and switched off: cover by structure

The `cover` recipe. Until now what differed between regions was which species and what tint; the
rules that place them -- a density, a clustering field, a pull toward water or a boundary -- were
the same everywhere, and the field boundaries, walls and roadside rails were one pattern laid
over three regions. With the recipe:

* **Sedgemire** -- reed beds at the water's edge rather than a sprinkle across the peat; willows
  and alders in *lines* along every channel and pool, a willow every 16 m a few paces back from
  the water with gaps where the bank will not hold one (`hedges.waterside`), and the scattered
  willow and alder thinned to make room.
* **Brightwater** -- marram on the crests of the dune ridges and not in the slacks: a rule gated
  by `tpi`, the height of a point above its own 30 m, new in the scatter.
* **The Briarwold** -- boulder fields on the risers of the stair; its lanes sunk as holloways
  (1.9 m under the land, inside the same band as any road).
* **Skerrow** -- intakes, not fields: parcels 300 m across with walls that run dead straight, the
  walls stopping at the fell wall at 430 m, and the roads walled in drystone in 70 m runs.
* **Cinderlea** -- the ash in the Builders' sunken streets, and the stubs of their walls, fused
  blocks, along the streets' lips (`hedges.ruin_lines`). No fence along any road.

Measured on the recipe build against the old world:

| | old world | with both recipes |
|---|---|---|
| Sedgemire reeds within 14 m of water | 28% of 102 071 | 73% of 35 929 |
| Sedgemire willow and alder within 8 m of water | 23% of 8 730 | 56% of 6 317 |
| Brightwater grass on a crest (tpi over 0.35 m) | 25% of 414 099 | 44% of 551 696 |
| Briarwold boulders on slopes over 0.16 | 201 in the region | 4 111 (83% on the risers) |
| Skerrow drystone wall pieces | 21 553 | 10 707 |
| Cinderlea ash in hollows (tpi under -0.7 m) | 37% of 1 359 | 81% of 596 |
| Cinderlea wall stubs | 35 | 2 703 |
| scatter instances, whole world | 3 477 721 | 3 370 573 |

By region the instance totals move from -17% (Sedgemire) to +26% (Brightwater, the marram); the
Vale, where the worst captured frame is, moves by 0.3%. None of it has been rendered. The brief
also asked for wind-bent trees in Brightwater, and the instance format (`[x, y, z, yaw, scale,
tint]`) has no tilt, so that is not a scatter rule away; it is a format change.

### What it costs

| | before | default build | with both recipes |
|---|---|---|---|
| `build_world.py`, whole build (the machine shared with five other agents throughout) | 237.8 s | 544.3 s (the machine twice as loaded; see below) | 262.3 s |
| of which the roads stage | 7.1 s | 75.4 s | 28.1 s |
| scatter instances | 3 477 721 | 3 484 974 | 3 370 573 |
| hedge pieces / roadside pieces | 122 398 / 6 261 | 122 359 / 8 871 | 106 471 / 6 371 |
| total length of road | 35.6 km | 41.9 km | 44.7 km |
| points in `roads.json` | 3 113 | 3 558 | 3 796 |
| `./run.sh perf`, worst of the 24 interiors | 183 draws, 0.99 M | not re-run | not re-run |
| worst captured frame, default plan | 1521 draws, 1.61 M (hearthvale_street) | not captured | not captured |
| drop test colour / landform / together (42 shots) | 0.76 / 0.26 / 0.64 | not captured | not captured |

Whole-build times on this machine are not comparable between runs: the default build ran while
it was about twice as loaded, and the stages whose code did not change took about twice as long
(469 s against the old build's 231 s; its textures stage alone 129 s against 49 s in the recipe
build an hour earlier). The recipe build ran at about the old build's load -- everything but its
roads took 234 s against 231 -- and the roads stage is the only one whose work grew: two
routings and a profile every 4 m, 28 s against 7 s. The roads are 18% longer --
they go round the Kharrow Hold spur instead of over it, and zigzag where they climb -- which is
where the extra roadside pieces come from. `roads.json` is written at about 12 m (every third laid
point, each on the carved centre line), because the POI dresser walks every segment of every road
for each point of interest. `./run.sh perf` measures the interiors, which read nothing the
world build writes, so it was not re-run. The captures and the drop test were not taken after:
the pass was stopped before them, and they are the first thing the recipes need (below).

### Still wanting

* **Brindlecrag -> the Clanless Camp clears by 0.03 m.** It is the thinnest authored line in
  the world. Nothing this pass lays can raise the ground under it, but anything that lowers the
  camp's pad or raises the cliff edge will close it.
* **Steep pitches.** Where the ground is steeper than the grade plus the band, the road goes with
  the ground. Read along each road's centre line every 4 m on the default build, the steepest
  grade anywhere is 0.81, on the Kharrow Hold - Grandfather Hollow road below the hold near
  (1045, -2278), and the worst 99th percentile of any road is 0.45 (Gullhithe - Kharrow Hold).
  The router keeps these short; it does not remove them.
* **`road_profiles.json` is not in CONTRACTS.** It is a build artifact for the tests, and says so
  in `output.py`.
* **Pilgrim's Ash has lost its cross street** on the default build (38 roads, was 39). The two
  roads north out of it (to Isseva and Nauve's Landing, on one trunk as before) and the road to
  the Cold Fire now leave it 130 degrees apart instead of 120, which is past `add_streets`'
  threshold for a road "across the grain"; the recipe build keeps it. The town still has its
  through street and all four roads.
* **The Kharrow Hold - Grandfather Hollow road is 5.4 km, was 4.1.** It goes round the spur
  the old one stood on. Nothing in the game prices a road's length yet, but anyone timing a
  walk will notice.
* **`tools/capture/plans/pois.json`** still has the Cold Fire at its old position
  (`tools/capture/make_pois_plan.py` regenerates it).
* **From above, the scars hardly show.** On a scratch build before the steep-ground fade, the
  scars round Kharrow Hold came out as contour rings aliased into stairs of texels. With the
  fade, a hillshade 2.8 km across Skerrow is hard to tell from the default build's: the thin
  looping lines in both are the drainage carve's, already in the old world. What does show is
  Brightwater's raised beaches, as close-set contours above the Mere's north shore -- a terrace
  of a round hill is a contour, which is not what a limestone scar looks like either. If the
  recipe goes on, the scars want to be long, level and few.
* Found in passing and fixed: `tools/uniqueness_check.py --json` raised a NameError after
  printing its scores (two names used three lines before they were assigned), so nobody had the
  drop test's JSON. And **`./run.sh test` exited 1 on a passing suite**: under `pipefail` it read
  the verdict with `echo "$out" | grep -q`, which stops reading at the match and can leave echo
  a SIGPIPE, so the pipeline failed with "RESULT: PASS" in it (3 runs in 50, replayed on that
  run's own output). The flow and smoke verdicts were read the same way, where the race could
  also pass a failing run. All four read to the end now.

### Rebuilding the world after the merge

```
./run.sh world
```

That is the default build: the roads, rivers and pads above, no landforms, no regional cover.
To build the rest for evaluation, in a worktree:

```
./run.sh world --recipe landforms --recipe cover
```

### Next, in order:

1. **Done and verified: what the default build now produces, against the world this pass
   found** (full 4096 builds, both in this worktree). Roads laid on the land: the worst road
   above both sides of it 150.1 m -> 4.8 m, below both sides 67.0 m -> 8.2 m, raw; every road
   graded within 2.4 to 3.6 m of its land and carved to that grade; the steepest grade along
   any road 9.1 -> 0.81. Rivers under every crossing as fords: dry runs over 6 m, 6 -> 0.
   Sightlines 87 / 0 / 3, unchanged, with Clanless at 0.03 m and the Cold Fire 20 m nearer
   Greyfold at (-2260, 2760). Staged builds refuse a heightmap whose pads have moved;
   `ROAD_KINDS` is held to the exterior's `FABRIC`. Roads 35.6 km -> 41.9 km, 39 -> 38
   (Pilgrim's Ash's cross street); `roads.json` 3 113 -> 3 558 points, plus
   `road_profiles.json`; the manifest gains `pad_fingerprint` and `recipes`. Scatter
   3 477 721 -> 3 484 974 instances. The roads stage costs about 21 s more at the old build's
   load. `game/world/terrain_assets.tres` unchanged. No landforms and no regional cover: those
   are recipes (3). Verified on that world by `python3 -m pytest tools/world/tests tools/tests`
   (49 passed), `./run.sh test` (1226 tests, 0 failed, 0 content problems, 0 script errors)
   and `./run.sh journey` (16 of 16 steps, 0 skipped, 0 logged errors).
2. **After the merge, rebuild the main checkout's world**: `./run.sh world`. Until that runs,
   `tools/world/tests/test_roads.py` fails there, by design -- it reads the old world's
   Gullhithe road 150.1 m above both sides. Accept on: pytest green, `python3 tools/sightlines.py`
   saying 87 clear / 0 refused / 3 veiled, `./run.sh test` green, `./run.sh journey` 16/16, and
   `git status` showing no change to `game/world/terrain_assets.tres` (none here).
3. **Half-done, off by default: the `landforms` and `cover` recipes.** They live in
   `tools/world/build_world.py` (`RECIPES`, `--recipe`, recorded as the manifest's `recipes`);
   `worldgen/landforms.py`, called from `heights.compose_heights(landforms=True)`; the `recipes`
   / `cover` block of `tools/world/scatter_rules.json`, applied by `cells.load_rules`;
   `fields.PATTERNS` (against the default `ONE_PATTERN`); `hedges.place(fell_wall=True)`,
   `hedges.waterside`, `hedges.ruin_lines`; `roadside.place(by_region=True)`; and
   `roads.ROAD_SINK_M` (the holloways, passed only with `cover`). `test_recipes.py` holds the
   defaults off and builds both recipes small. Measured with both on: sightlines 87 / 0 / 3,
   Clanless 0.03 m; the road and river tests pass; the relief and structure tables above. Not
   measured: any frame, the drop test, frame cost.
4. **Evaluate them** in a worktree, against the default build shot the same way, since the
   cameras stand on the ground as built. For each of `./run.sh world` and
   `./run.sh world --recipe landforms --recipe cover` (about 4.5 minutes each, peaking near
   8 GB: `free -g` first): `python3 tools/sightlines.py` (accept at least 87 clear, 0 refused)
   and pytest; `python3 tools/capture/make_default_plan.py --out <dir>` to place the cameras on
   that ground; `./run.sh shots <dir>/default.json` and the horizon plan (about 80 s a shot);
   `python3 tools/uniqueness_check.py <captures>/regions --json <captures>/drop_test.json`.
   **Look at every frame**, the landforms first: the relief figures say they may barely show
   from an approach camera. Accept the recipes if the landform axis rises and colour and
   together do not fall (the old world read 0.76 / 0.26 / 0.64 on this pass's sheet), and the
   worst frame stays within 2000 draws and no worse in primitives than the default build's
   (the old world's worst was 1.61 M, already over the 1.5 M budget).
5. **If they pass, make them the default**: drop the gating in `build_world.py` (or apply both
   recipes when none is named), fold the `cover` block into the rules proper, change
   `test_recipes.py`'s expectation that a default build has none, rebuild, and repeat 2.
6. **If the landforms do not read from the ground**: they are 2 to 6 m against natural relief
   whose 95th percentile at the same scale is already 13 to 38 m by region (median 0.6 to 9 m).
   The larger terms are the place to push -- Cinderlea's streets and blocks, Brightwater's
   ridges -- and Skerrow's scars want to be long level bands that show, rather than terraces
   that follow the contours (see Still wanting); any raise stays out of the 14 m sightline
   corridors, with the Clanless line re-measured.
7. **Risks and regressions, with numbers**: Brindlecrag -> the Clanless Camp clears by
   0.03 m (the thinnest line in the world; Foxfire Falls -> the Charcoal Camp is next at
   0.08 m); the steepest grade along a road is 0.81 and the worst 99th percentile 0.45
   (Gullhithe - Kharrow Hold); the roads stage costs about 21 s more at the old build's load
   (68 s more on the loaded run); the roads are 18% longer and Pilgrim's Ash has no cross
   street; no frame of the default build has been captured, so its frame cost is inferred
   (every region's scatter is within 0.6% of before, most of the difference roadside rail) and
   not measured; `road_profiles.json` is not in CONTRACTS; `tools/capture/plans/pois.json` has
   the Cold Fire's old position (`python3 tools/capture/make_pois_plan.py`); Brightwater's
   wind-bent trees need a tilt in the scatter's instance format, which is a CONTRACTS change.
## Combat measured, fights fought headless, four hooks owned, and the game heard

Five parts, one branch. Every number below was produced by the running game, not read off the
data: `./run.sh test --filter=test_combat_design | grep MEASURE` rebuilds the combat table,
`./run.sh fights` the fights table, and `python3 tools/audio/audit.py` the audio one.

### A. Combat against DESIGN §5.3

`tests/unit/test_combat_design.gd` (19 tests) drives the real Player through the real input
actions on a real floor against a real Enemy and prints what the game did. Before is the tree
this branch started from; after is this branch. Timings have one-frame resolution (16.7 ms).

| what | design | measured before | measured after |
|---|---|---|---|
| stamina pool at the character's own Endurance | 100 + 8·E (140 at E 5; 180 at E 10) | 180, whatever E was | 180 at E 10 |
| mana pool at the character's own Will | 60 + 6·W | 120, whatever W was | 120 at W 10 |
| stamina / mana after a level's point | +8 / +6 | +0 / +0 | 188 / 126 |
| light / heavy / dodge / sprint cost (iron sword) | 18 / 32 / 22 / 8 per s | 18 / 32 / 22 / 8 | 18 / 32 / 22 / 8 |
| stamina regen delay, rate | 0.8 s, 30/s | 0.800 s, 30/s | 0.800 s, 30/s |
| input buffer | 0.25 s | 0.250 s | 0.250 s |
| one-handed light chain | 3 | 3 | 3 |
| heavy held to full, charge factor | 1.5× | 1.000× | 1.500× |
| cancel a light into a dodge | only after the active frames | at 0.483 s, inside the hit window (0.323–0.493 s) | at 0.483 s, after it (0.297–0.467 s) |
| roll, light load: length, i-frames | 0.6 s, 0.08–0.38 s | 0.600 s, 0.083–0.383 s | 0.600 s, 0.083–0.383 s |
| load of a plate kit and a sword | worn / (40 + 3·E): 49.1% at E 5, 38.6% at E 10 | 24.3% | 38.6% |
| a bag past its capacity | overloaded roll | 24.3%, never overloaded | 129%, overloaded roll |
| stamina regen at light / heavy / overloaded load | slower as load rises (§5.7) | 30 / 30 / 30 per s | 30 / 22.5 / 15 per s |
| guard of a 20 hit, clan shield (stability 0.8) | 4 through, 2.4 stamina | 20 through, 12 stamina | 4, 2.4 |
| parry window | 0.18 s | 0.167 s (10 frames) | 0.167 s (10 frames; 0.18 s is 10.8) |
| riposte_open, riposte multiplier | 2 s, 3× | 2.000 s, 3.000× | 2.000 s, 3.000× |
| poise regen delay, rate | 1.5 s, 4/s | 1.517 s, 4/s | 1.500 s, 4/s |
| stagger at zero poise, poise reset | yes | yes | yes |
| poise a player's heavy loses to an 8-poise hit in its wind-up | 0 (hyper-armour) | 8 | 0 |
| first light, iron sword, on a bandit (armour 2) | the §5.3 formula: 12.35 | 12.70 (a one-handed skill the character did not have) | 12.35 |
| armour_flat, helm + tunic + gloves + boots | 15 | 3 (the body piece only) | 15 |
| a light from behind; a sneaking dagger on an unaware foe | ×3; ×6 | ×1; ×1 | ×3; ×6 |
| lock-on cycling, foes ahead, ahead-left, behind, and at 34 m | inside the 30 m cone only | cycled to the one behind | ahead-left, ahead |
| burning / chilled / webbed / bleeding / poisoned / silenced | 12 / 0.6× / 0.45× / 6 / 15 / refused | all as designed | all as designed |
| renown lost to 10 s of quieted | 2 | 0 | 2 |

What changed to get there is in DECISIONS (2026-09-22: attributes start at 10 and one set of
pool formulas, schema 4; load and regen by load; hyper-armour 12 and hit windows from the clip;
backstab and sneak rules; the swing band and knockback in metres). The humanoid wind-ups were
the largest single fault: 65 of 69 humanoid attacks threw their blow off the authored time (56
early, 6 late, 3 never live) because the rig played the clip on its own schedule; the
AnimationDriver now keeps the time and stretches the rig to it, and the worst of 100 attacks is
0.017 s off.

### B. Hit windows, telegraphs, and a scripted player against every archetype

`tests/unit/test_attack_windows.gd` walks the data (every weapon's swings have `hit_start` and
`hit_end`; every enemy and boss attack, every phase, winds up for at least 0.3 s) and then
stands every one of them up in its real body and measures telegraph to live hitbox.

`./run.sh fights` (`tests/arena/fights.gd`) puts a scripted level-1 player of a starting Calling
on a flat floor against one foe of every §5.4 archetype, headless, at a fixed 60 fps and a
seeded RNG (two runs diff equal). It checks, over 20 fights: every blow that landed was
telegraphed for its authored time (238 seen), lock-on takes and cycles inside the cone, a parry
inside the window opens a riposte and one outside does not, a roll's i-frames take a blow clean
(170), a foe at zero poise staggers (19), and every fight is heard (20). All pass.

| calling | archetype | foe | outcome | seconds | blows taken | damage taken | hits/swings | foe hp left |
|---|---|---|---|---|---|---|---|---|
| hearthkeeper | skirmisher | roadside bandit | won | 20.9 | 4 | 58 | 4/5 | 0% |
| hearthkeeper | pack | down wolf | won | 38.9 | 4 | 40 | 8/9 | 0% |
| hearthkeeper | brute | hedge wight | won | 13.2 | 0 | 0 | 13/13 | 0% |
| hearthkeeper | charger | bristleback | won | 10.2 | 1 | 22 | 9/9 | 0% |
| hearthkeeper | ambusher | sallowjaw | won | 14.9 | 0 | 0 | 12/12 | 0% |
| hearthkeeper | caster | smuggler sayer | won | 28.2 | 4 | 50 | 4/4 | 0% |
| hearthkeeper | sentinel | warden | won | 41.3 | 0 | 0 | 28/29 | 0% |
| hearthkeeper | swarm | gutter drake | lost (died) | 35.5 | 11 | 100 | 5/8 | 30% |
| hearthkeeper | elite | bravo | won | 42.2 | 0 | 0 | 20/20 | 0% |
| hearthkeeper | boss | barrow reeve | lost (died) | 66.9 | 4 | 100 | 38/36 | 61% |
| cragborn | skirmisher | roadside bandit | won | 12.1 | 2 | 30 | 3/5 | 0% |
| cragborn | pack | down wolf | won | 13.2 | 7 | 42 | 6/6 | 0% |
| cragborn | brute | hedge wight | won | 18.1 | 0 | 0 | 11/11 | 0% |
| cragborn | charger | bristleback | won | 11.5 | 1 | 19 | 7/7 | 0% |
| cragborn | ambusher | sallowjaw | won | 22.6 | 1 | 32 | 11/12 | 0% |
| cragborn | caster | smuggler sayer | lost (died) | 55.1 | 10 | 100 | 2/8 | 31% |
| cragborn | sentinel | warden | won | 84.9 | 0 | 0 | 42/42 | 0% |
| cragborn | swarm | gutter drake | won | 7.0 | 7 | 45 | 4/4 | 0% |
| cragborn | elite | bravo | lost (died) | 40.0 | 6 | 100 | 10/17 | 42% |
| cragborn | boss | barrow reeve | lost (died) | 104.3 | 5 | 100 | 44/43 | 68% |

Before the seven fixes below, the Hearthkeeper's first run read: pack and charger not won in 120
s (the wolves bit nobody; the player was thrown off the edge of the arena), swarm lost with none
of its swings landing, boss not won. A later run had the caster not won by either Calling: it
walked away past its leash. After, 15 of 20 are won; the five lost are the swarm and the boss
for the Hearthkeeper's dagger, and the caster, the elite and the boss for the Cragborn's axe.

"Lost" is this player's result, not a verdict on the fight: the script never blocks (no starting
kit has a shield) and never heals, because the flask DESIGN §5.5 refills at a Hearthstone does
not exist and a loaf mends 8. The Barrow Reeve (520 hp, slash resist 0.3, armour 6) takes 7–11
per landed blow from a starting weapon; at the scripted player's pace that is a minute and a
half to three minutes of fighting without taking five of his blows. No fight is trivial by the
harness's measure (over in under 8 s with nothing taken).

The first runs found seven faults in the game, all fixed and pinned in
`tests/unit/test_fights_found.gd`: a swing volume at chest height that no sword could land on a
gutter drake with (0 hits); knockback summed into the velocity every frame (the bristleback
threw the player at 140 m/s off the arena); an enemy that left the fight mid-blow lunging for
ever; patience counted from the start of a fight rather than the last sight; a pack waiting on a
ring wider than its bite (no blow landed on the player in 120 s against three wolves); circling
at a speed no one could aim at; and a leash that broke for one frame (a caster walked 50 m from
a 32 m leash). The first run also found `StatusEffects.advance` reading an effect a tick earlier
in the same loop had ended.

### C. Four hooks, owned

`LootDrops.context_provider` (GameServices.loot_context: level, luck, quest stages),
`Player.quick_slot_handler` (Equipment.use_quick_index), `Player.ammo_provider`
(Inventory.ammo_for) and the Name-table's refusal reason (Crafting.enchant_check, shown on the
station screen) each have an owner and a running-game test (`test_hooks_wired.gd`).
`tools/unwired.py` now also lists Callable hooks nothing assigns: 3 before, 0 after. The fourth
was not a hook but a function only its test called (`Enchanting.enchant_blocker`); the
Name-table's screen asks it now, through `Crafting.enchant_check`, and shows the reason.

### D. The audio

Before: nothing in the game called Foley -- no footstep, blow, door, chest, coin or button had
ever been heard. The score's combat layer came in only after a hit and went back to exploring
eight seconds later mid-fight; there was no night; the second boss track arrived through a quest
stage, as a cut; the ambience read the weather once per announcement and missed the blend;
indoors, world sounds went round the Sounds slider. After:

* an enemy entering combat holds the combat layer at 0.6 or above until the last one dies or
  gives up, then it decays to exploring in 4.8 s; a region crossfades over 4 s between two banks
  of stems; 21:00-05:00 is a night mix (melody -11 dB, deep stem -14 dB); an interior brings the
  deep mix, a room tone, a 900 Hz low-pass on the ambience and a door; a boss's second phase
  crossfades to the second track on its own player;
* the ambience re-reads the Atmosphere's weather every second, so rain comes and goes with the
  blend, not only with the announcement;
* footsteps fall a stride apart by distance covered (0.35·speed + 0.6 m, so the cadence follows
  whatever speeds the gait has) on the collider's surface, else water, else the region's ground;
  blows sound the struck body's material; whooshes go with the blade; bows, arrows, sayings,
  locks, buttons, chests, coins, meals, armour, menus, refusals, the Hearthstone and the Echo
  are heard;
* the Interior bus goes out through SFX, so the Sounds slider reaches indoors.

`tests/unit/test_audio_wired.gd` (17 tests) drives each from its real trigger and samples every
music player's level every 1/60 s: no player moves more than 3 dB in a step, and outgoing and
incoming tracks are both audible at once. It also checks that every sound the code can ask for
is a row whose files load (11 rows have nothing that asks, listed below), that every one of the
393 audio files is used, that every bus a sound is sent to exists, and that the six sliders on
the Settings screen move their buses (0.25 on a slider puts its bus at -12.0 dB).

**The files.** `tools/audio/audit.py` measures every one of the 393 audio files the game ships
(peak, true peak, clipping, DC, loudness per file and per category, one-shot edges and lead-ins,
dead air in beds, loop-seam clicks and breaks) and flags what fails a release. Measured before:
nothing clipped (highest true peak -1.48 dBTP), no DC, no loop clicked at its wrap (worst 3.8 dB
against a 6 dB bar) and no loop broke its level at the wrap past anything it does elsewhere;
every music stem sits within 0.1 LU of its stem's target and every bed within 0.6 LU of -30.
What did fail:

| check | files flagged before | after |
|---|---|---|
| a one-shot that decodes starting mid-waveform (first sample above -40 dBFS) | 50 | 0 |
| a one-shot that starts late (more than 25 ms before it is heard) | 9 | 0 |
| a variant more than 4 LU from the other variants of its effect | 4 | 0 |
| an effect more than 10 LU from its family, at its table level | 7 (2 effects) | 0 |
| a bed that drops to digital silence for more than 0.25 s | 3 | 0 |
| clipping, true peak above -1 dBTP, DC, a click or a level break at a loop's wrap | 0 | 0 |
| any of these | 69 | 0 |

Fixed in the generators, then regenerated -- all 70 effects (240 files, because the edge fix
applies to every effect) and four ambience keys (frogs, rope_creak, chain_clink, thunder_far);
nothing else was re-rendered. The numbers under the flags: the effects' first decoded sample
went from a median of -51.6 dBFS (worst -25.5) to digital zero, because Vorbis rings ahead of a
transient on sample 0 and every effect is now set in 4 ms of silence; the longest digital
silence in the frogs, boardwalk-rope and chain-bridge beds went from 2.4, 9.1 and 8.6 s to none,
with the beds still at -30 LUFS (-30.2, -29.5, -29.8) and the frogs' wrap still under the click
bar (4.5 dB against 6); the far thunder's lead-in went from up to 1.43 s to under 25 ms and the
coins' from 108 ms; the four wide effects went from 4.1-4.9 LU of variant spread to 2.9-3.4; the
lockpick click's median went from -34.6 to -30.2 LUFS and the cart wheels' from -30.0 to -24.0
at their table levels; the highest true peak anywhere went from -1.48 to -1.26 dBTP. A music
stem is not held to never going silent -- a melody rests while the others play -- only a bed is.

### E. Test hygiene

Sixteen tests opened a screen through the real event and left it open for the runner to find
paused. `TestCase.close_screen(menu_id)` closes what a test opened and fails the test if it was
not open; the count of tests leaving the world paused is 0 (it was 16).

### Also fixed in passing

* `./run.sh test` could report a green run as failed: `echo "$out" | grep -q` under pipefail
  lets grep's early exit kill the echo; four of five replays of a green log failed. The parent
  branch found and fixed the same race while this work was going on; this branch carries the
  parent's lines verbatim (so the two merge without a conflict) plus its `fights` command, and
  the parent's check reads the final green log as a pass twenty times in twenty.

### Found and not fixed

* 25 perk stat keys are read by nothing (the combat perks do nothing): damage_one_handed,
  damage_two_handed, damage_archery, poise_damage_one_handed, stamina_cost_heavy,
  stamina_cost_dodge, poise_max, dodge_iframes, block_stability, parry_window,
  pickpocket_chance, sneak_attack_mult, prices_buy, prices_sell, renown_gain, ingredient_yield,
  bow_draw_speed, arrow_recovery, weight_class_penalty, mote_yield, spell_cost_kindling,
  spell_cost_hush, spell_power_mending, spell_duration_binding, spell_duration_calling.
* The heavy and overloaded equipment tiers cannot be reached by gear alone (the heaviest kit
  in the pack is about 0.61 of capacity); only an overfull bag gets there.
* Flask charges (DESIGN §5.5) do not exist anywhere in the code.
* Eleven sfx rows have nothing that plays them: bell_hand, bell_tavern, bell_toll, bell_tower,
  thunder_far, thunder_near (the ambience has its own thunder), wind_gust, wood_creak,
  cart_wheels, footstep_sand, footstep_snow (no region's ground is sand or snow).
* POI structures (piers, walls, bridges) declare no footstep surface, so they sound like their
  region's ground.
* `tools/unwired.py` lists `use_quick` and `set_boss_intensity` because their only callers are
  in their own files.

### Next, in order

1. **The 25 inert perk keys.** Each names a number the combat, stealth or economy code already
   computes; read the character's modifiers for that key at that point and add a test per key
   that takes the perk and measures the number move. `test_combat_design.gd` has the harness
   for the combat ones.
2. **Flask charges** (DESIGN §5.5): a quick-slot consumable refilled at a Hearthstone. Then
   `./run.sh fights --only=boss` and record whether a level-1 player of either Calling can win
   the Barrow Reeve; if not, the boss's numbers are DESIGN's to change.
3. **The heavy load tier** cannot be reached by gear; either heavier kit or lower tier bounds
   (`DamageModel.load_tier`), with the MEASURE rows in `test_combat_design.gd` updated.
4. **POI footstep surfaces**: `poi_kit.gd`'s colliders take `surface` meta from the material they
   were built with (timber and planks wood, stone and oroth stone); `test_audio_wired.gd` has the
   walking test to copy.
5. **The eleven unplayed sfx rows**: wire them (tower and tavern bells to the hour in Tollmere,
   thunder to the Atmosphere's strikes, cart wheels to road travellers, snow to Skerrow above the
   snow line) or drop them from `gen_sfx.py`. The test prints the list on every run.
6. **unwired.py** could count a same-file caller when that caller is itself reached from outside
   (it lists `use_quick` and `set_boss_intensity`, both reached through their own file).

## The quests, walked to the end of every objective; and who stands at the points of interest

Next item 4 recorded three diagnoses of the quest plumbing and item 6 the absent people and
encounters at the points of interest. All three diagnoses survived measurement; the first was
larger than written, and the walk of every quest that followed found more of the same kind.

**`quest_at` counted from one and was read from nought — forty-eight times.** Content numbers a
stage from one (`["core:quest/the_naming", 1]` is the waking); `quest_at`, `quest_min_stage` and
`quest_stage` read the number as an index, so every one of the pack's forty-eight numbered
references, in nine quests, landed a stage late. `QuestLog.stage_index()` is now the one
translation (a stage id, or its number from one) and `test_quest_stage_references.gd` pins each of
the forty-eight to the stage id its writer meant, and fails on a new number until somebody says
what it means. The same pass found `advance()` walking on into the next stage over the top of a
branch that had just sent the quest somewhere else; it stops now.

**Nothing said `escort_arrived`, and nothing closed five deliveries or five decisions.**
`Escorts` (systems/npc_life) walks the person with you: they fall in when the stage is under way
and they have been spoken to, follow at your elbow, stop and wait with a journal line when left
more than forty metres behind and fall in again when you come back, fail the quest when they
die, and close the objective when they reach the place; they are saved on the road. Aud Fennick's
vigil and the job boards' escorts both walk (`test_escorts.gd`, seven cases with bodies moved
by hand). Five deliveries had no line anywhere to hand the thing over on (the letter to the
Circle, Aud's bell to Cadwen, the Fennick bell, the press screw, the three loaves): finishing a
conversation with the person while carrying it hands it over now, except where an author wrote
the scene. The main thread's five decisions had no button anywhere: the open options are put at
the host's hub, and the last one, the note, which has nobody left in the room to ask, at a cold
light in the Cantor's Seat (`ChoicePoint`). Tools could not be used, so the speaking stone and the
sluice pin could never be; a tool is used now without being used up.

**Eighteen objectives in fourteen quests asked for things nothing gave, sold or put anywhere.**
`QuestItems` (world/pois/quest_items.gd) puts them down as the world streams in: at the
objective's `where`, the item's own, or the place the same stage sends you to; on a marker the
dressing puts down when the objective names a `spot` (the Tumbled Watch's fallen stair, the
Clanless Camp's chimes, the Gullhithe keel, the Wisp Hollow chimney), in a deep place's chamber or
a house's room when it is inside; `owner` makes taking it theft; what is taken is the
`quest_items` save section. A deep place's `item` features were props with an item written on
them; they are pickups, except a boss's own drop. Hesta gives the Fennick bell on her blue-cuff
line and the general store stocks the hearth loaf, rather than either lying in the road.

**Every objective, walked.** `QuestWalk` (systems/quests/quest_walk.gd) asks of every objective
of every authored quest what in the built game sends the event it waits for — the person and
where they live, the enemy and where it stands (the built cells, a deep place's encounters, a
point of interest's), the item and how it is got, the decision and who puts it — and
`test_quest_walk.gd` fails on a new one that cannot be closed. **255 objectives in 35 quests:
none without a way now, and every quest has a line or an effect that starts it.** Its radiant half
asks the same of every target a job board could name, region by region, and found three ways a
board could post work that is not work: an escort of a placeholder from the writers' first roster
(one of them a dog, `example_dog_gosling`) or of an anonymous watch post, a fetch for cottongrass,
which nothing in the game has, and — once those were out — an escort of Bessa Tamwick to Tamwick,
where she lives, which ended the moment she agreed to it. The generator leaves all three out.

The walk says whether the thing an objective waits for exists and can happen. It does not say the
stage before is reachable, that a `requires` chain can be met, how hard the fight is, or that a
kill happens where the story puts it (see the Undercroft below). The last column names only what
an objective could not be closed without: a source this work added that nothing older supplies —
a kill with enemies in the open is not counted for also standing at a point of interest, nor an
item that is also sold for also lying somewhere.

| quest | objectives | closable | numbered stage references (each read a stage late) | could not be closed without |
|---|---|---|---|---|
| `a_hand_on_the_rope` | 10 | all | - | placed, decision at the hub |
| `a_thing_nobody_reported` | 7 | all | - | placed |
| `a_verse_about_you` | 8 | all | 6 | stocked, hand-over, placed |
| `against_the_bell` | 7 | all | - | - |
| `at_the_gate` | 6 | all | - | - |
| `bramble` | 6 | all | 4 | - |
| `cask_and_press` | 8 | all | 6 | placed, hand-over |
| `every_price` | 6 | all | - | placed x2 |
| `forty_one_places` | 6 | all | - | - |
| `four_hundred_and_twelve` | 7 | all | - | placed |
| `grist` | 8 | all | 5 | tool use |
| `in_council` | 10 | all | - | - |
| `last_name` | 9 | all | 6 | - |
| `louder` | 8 | all | - | tool use, placed |
| `louder_than_books` | 7 | all | 2 | hand-over, decision at the hub |
| `seventeen_bells` | 7 | all | 4 | given (Hesta), hand-over |
| `the_briars_purpose` | 10 | all | - | POI encounter only, decision at the hub |
| `the_cold_fire` | 5 | all | - | - |
| `the_deep_lines` | 6 | all | - | - |
| `the_fawning_months` | 6 | all | - | - |
| `the_held_note` | 7 | all | - | decision at the Seat |
| `the_lamp_is_dimmer` | 8 | all | - | placed |
| `the_lane_that_isnt` | 7 | all | - | - |
| `the_lantern_still_lit` | 6 | all | - | placed |
| `the_last_column` | 2 | all | - | hand-over |
| `the_long_measurement` | 9 | all | - | - |
| `the_names_in_the_chapter_book` | 5 | all | - | - |
| `the_naming` | 7 | all | 7 | - |
| `the_reading` | 6 | all | - | - |
| `the_toll_hums` | 10 | all | 8 | placed x2 |
| `the_unsaid_ledger` | 6 | all | - | placed x2 |
| `the_unsaid_woman` | 9 | all | - | - |
| `vigil` | 9 | all | - | escort, hand-over |
| `wardens_roll_of_names` | 8 | all | - | placed |
| `what_the_water_kept` | 9 | all | - | decision at the hub, placed |

*placed*: lies where `QuestItems` or a deep place's feature (now a pickup) puts it, and nothing
else gives it. *stocked*, *given (Hesta)*: a shop's stock or a line now supplies it. *hand-over*:
finishing a conversation with the person while carrying it. *decision at the hub* / *at the Seat*:
`ChoicePoint`. *tool use*: used without being used up. *escort*: `Escorts`. *POI encounter only*:
the Hart of Thorns, which nothing but the Standing Moot's encounter stands up.

**The points of interest stand up what their sentences say.** Every POI has carried an
`encounter` sentence and nothing stood up what any of them described; the world builder keeps the
country's encounters off every pad, so the places a player is drawn to were the one ground sure
to be empty. Thirty-three `encounter` defs (content/packs/core/encounters/pois.json) say the
sentences in terms `PoiEncounters` can raise with the dressing: groups at a marker the builders
put down or on the pad's rim, by the hour (the ford's bandits after dark, the dell's bristlebacks
at dawn, the shrine's wisps at midnight), kept away by a condition (the Larkbourne Boys while the
Roll of Names sends you to hear Ryn out) or by a person being present (the Lantern Causeway's
drowned climb the poles only when the lamplighter is not on them), or seated until something is
touched (Greyfold's six at the Cold Fire rise when you take up the cup). A group killed stays dead
until a Hearthstone rest; a boss put down stays down. **The Hart of Thorns was stood up nowhere**
— its arena is the Standing Moot, a place rather than a deep place — **so the main thread's
fourth account could not be finished**; the Moot is dressed as a stone circle now (a place's
`dressing` kind) with the Hart in its middle. `test_poi_encounters.gd` pins what stands at every
one of the forty-eight, people included, both ways round.

The people the sentences and stories name are ordinary npc defs with dialogue, and so they are in
the `npcs` save section like anybody (`test_poi_people.gd` saves every one of them, loads over a
standing body and into an empty registry, and finds one Ivo each time and the killed lamplighter
still dead): **Lissane Sa** the lamplighter, **Khath ko-Rudd** the toll-keeper, **Calen Ash** the
knight in the Headless Watch's eye (who asks what bread costs in Tollmere and writes the answer
inside the eye with a burnt stick), **Ivo Goslin** the hermit, with a side quest (*The Last
Column*) and his exercise book to read on his crate, **Marigold Orchard** the pilgrim at Ansel's
chair on three days in seven, and **Sorrel and Barnaby Rooke**, the burners who never sleep at the
same time, with a stock table and the camp's job board. Three more that the places' stories name
were still missing after this work's first pass, and one had been written down and never made: **Tansy
Cresswell**, Foxglove Dell's hedge-witch, was a row in the names index ("made Nell Harebell's
cousin by this stream") and Nell's line about her, and nobody at the dell. She sells yew berries
to anybody who asks plainly, which Nell will not, is asleep in her hut while the boars root at
dawn, and says what the story leaves open: whoever takes her yew keeps the seed and leaves the
harmless flesh in heaps (Nell has a line back). **Ruska ko-Dreugh** takes three marks at Windgate
for a pass the snow has shut for nine winters and writes you in the book as crossed. **Gisel
Morneth and Wennick Anthar** are the Sayers' camp at the Thirteenth, arguing whether its head is
the Cantor's likeness or a face somebody cut into it afterwards, which is what Calen says they do
instead of saying so; neither is shown right, and both are in their tents with the flaps tied
before the choristers come. Two rumours carry the new ones about (the heaps under the yew, and
crossing Windgate, which a capture's log has being said at Kharrow Hold). Ryn Larkbourne's
schedule named a spot `gosling_pit` in Merrowby that
nothing there was called; he keeps the camp at the head of the stolen mill wheel now. Each works
on a marker their place's dressing puts down, and a marker says whose place it is in, so two
camps' fires are never taken for each other. The Reed Wreck's chart of the Salt Isles lies on its
crate.

A body stands exactly where its marker is, and that found a mistake of this work's own: the
Sayers' camp at the Thirteenth had been measured from the head toward the hips, so its table, lamp
and ladder stood inside the colossus's shoulders and a tent in its flung arm (the B2 capture shows
the tent's canvas through the carving's flank and no table anywhere). The camp is on the head's
right, the one quarter the figure leaves open, and `test_poi_people.gd` now puts a person-sized
capsule on every working marker and fails if it touches anything solid (a capsule at the
colossus's hips must, and does), fails if two people work one marker at one hour, which the
second Sayer first did, and stands every one of the twelve up at every hour they work and fails
if any is more than half a metre off their marker — a marker the registry cannot find puts a
person on a ring round the place's middle without a word, and on an island that ring is water.

**The One Poppy and the Thirteenth, looked at.** From the POI plan's thirty metres the poppy was
grey grass and nothing. It has what people who come out to it would leave: the grass worn away
inside a ring of carried stones and down a path, a cairn by the path with a peeled white stake
standing out of the flat heath, and the flower built from shapes, a bloom two hands across that
holds a little light, the one colour there. At thirty metres the ring, the stake and the red are
all legible; the bloom itself is a handful of pixels, which is what a poppy at thirty metres is. A
trodden path laid as thin boards photographed as a white rail across the heath and was taken
out. Kneeling by it now puts its sentence's deed: water it (the Hearth) or pick it (the Hollow,
four petals, and it is not rebuilt). The Thirteenth was boxes and a dome in the coursed Oroth
surface — a wall and an igloo. It is carved: the back, the blades and the hips as rounded masses,
long limbs, the soles turned up, one arm flung ahead with the fingers spread, the robe's folds
down its back, the hooded head down in the Sayers' diggings under a hoist. On round forms the
Oroth courses drew seams and the body looked inflated, so it is the Builders' dark stone with
hairline weathering instead. From above or along its length it is a figure lying face down; from
the ground by its head it is a mass of carved stone with the dig at its crown — better, and still
simplified: the limbs are smooth round forms, not sculpture. Captured again on the merged result,
under the painted sky and its palette: the poppy still reads from thirty metres (the ring, the
stake, and a red mark a few pixels wide), the Thirteenth's camp stands on the head's right with
both Sayers on their feet at the table and the trench, and the gate-warden stands on clear ground
in front of the toll-house's drifts. Foxglove Dell's hedge hides the valley from the pois plan's
own shot, which is what a hedge is for; from above it, Tansy is among the foxgloves in the
morning and at her door in the firelight at dusk.

**Found in passing, and fixed (twice, some of it).** The journey's death step read
`marks_gone=false recovered=true` with the count exactly what it was, once in this work's runs
and once in another branch's run the same night (240 marks, no Naming step in it), so it was
never the Toll Hums, as this work first guessed. The physics server says who came into an Area3D
as the iteration after the step that found them begins; when exactly one physics step fell
between the journey's fall and its coming back, that step found the body lying in the still-quiet
Echo, `_respawn` armed it, and the word arrived after, with the player already at the stone: the
marks came straight back. The player-feel work found the same hole the same night and fixed it
the same way; the merge keeps its Echo (`_is_here` measures a body against the Echo's own radius
and height, where this work's measured a round 2.5 m) and both tests: its own stages the
journey's single step, and this work's stages one, two and three steps with the count measured,
restaging any frame that overshoots, and failed at one step before the fix. `Readable` never set
its collision layer, so the interaction ray, which masks only the interactable layer, went through
every shelf book in every house: the shelves were readable only by a test calling `interact()`.
`run.sh` read the test and smoke verdicts with `echo "$out" | grep -q` under `pipefail`, which
returns 141 when grep leaves at its match while echo is still writing: five reruns in forty over
one passing log exited 1, and the smoke check could have passed a log that said SCRIPT ERROR. The
parent branch fixed that the same night too, with a grep that reads to the end, and its version
is the one merged.

**Measured**, on this branch with the parent merged in twice (the painted look, the roads, combat
and audio, then player feel and no void): the unit suite 1398 tests, 0 failed, 0 content
problems, 0 script errors and 0 dead lambda captures (four logged errors, the same four tests of
bad input as before this work). The journey 16 of 16 in each of three runs; its meet-somebody
step now closes the Naming at Wren's word in Merrowby and checks the Toll Hums begins, which is
the furthest a noon in Merrowby carries the thread (the Naming's earlier stages are a day's walk
away, and the unit suite walks them). Smoke PASS over 6 regions, 34 places and 24 interiors, with
nothing logged. Against the parent branch as it stands, `unwired.py --verbs` counts two fewer
verbs reached only by tests (37 to its 39: `open_options` and `start_def` are reached now) and
none new, and `dead_data.py` the same five unread keys (559 distinct keys to its 542; every one
this work added is read).

**Found and not fixed.**

* **Kills count wherever they happen.** The Undercroft's strongroom stage asks for bravos and the
  room behind the bell for gutter drakes; the Undercroft's own encounters are down-wolves and
  bandits, so both close by killing bravos at the Long Stride and drakes at the Gullhithe Wreck.
  The fix is the Undercroft's meta or a kill objective that names where.
* **Hollin Barrow's bell cist names `core:item/wardens_roll_fragment` as a feature; no such item
  exists**, so it stays a prop.
* **Aud Fennick walks "into the grey"** at the end of the vigil and the registry puts her back on
  her schedule at Pilgrim's Ash; Seventeen Bells needs her there, so the story and the roster
  disagree rather than either being broken.
* **The loot tables' `quest_at` / `quest_min` conditions read a `quests` context nobody fills**;
  no loot def uses them yet, and whoever does will meet this and the stage-numbering rule at once.
* **A quest's `giver` starts nothing** (`QuestConditions.offers_of` is called only by its tests).
  Every authored quest has a line or an effect that starts it, so none is stuck; a new quest that
  relies on its giver alone will be.
* **Sentences not honoured, or honoured loosely:** the Singing Yew's wights turning away, the
  Sallow King's moral choice, the Headless Watch's fallen knight "if the watch has turned" (nothing
  turns it), the Mossbridge Wardens' "stolen forest goods" (their own greed rule stands in),
  Tideflat's crabs (there is no crab), Gosling Pit's brute leader, who is Ryn, a person you parley
  with, the Long Stride's bravo, who is hostile by day rather than waiting for somebody to refuse
  the toll (there is no toll to refuse), and the Clanless Camp's "brute and two skirmishers", who
  are three raiders. Groups said to be up high ("at the top", "on the cliffs above", "in the cave
  behind the falls") stand on the pad's rim, and the sentences' ground — Gosling Pit's rear path
  from the Hound's eye, Fern Gully's bridges to cut, Whitecut's wet stone — is terrain, not people.
* **The Hart of Thorns stands in the Moot as a bare humanoid rig**, and the Moot's stones read
  dark on dark under the Briarwold canopy; both are in the capture and neither is this work's art.
* **The placeholder roster is still in the world**: `example_merrowby.json`'s eight, three of them
  sharing a name with a real person (Wren Tallow, Maud Brambling, Osric Pennywort), which are three
  of `namegen.py --check`'s four problems; the fourth is two items both called "Reed Lantern".
* **The pois plan's own shot of the Watch of the Gate photographs a hillside**: 44 m back from the
  toll-house on its approach is behind a shoulder of the pass. A shot at half the distance shows
  the house and its warden; `make_pois_plan.py` does not look for a clear line.

**Left for next, in order.** (1) Give the Undercroft its drakes and bravos, and let a kill objective
name where it counts. (2) Make `wardens_roll_fragment` or take it out of the cist. (3) The
unhonoured sentences above, the Moot's stones and the Hart's model. (4) Delete or rename the
placeholder roster.

## Every perk kept, a flask to drink, every load band reachable, and the ground heard

Six parts, one branch, in the order they were asked for. The tables are the game's own output:
`./run.sh test --filter=test_perks_do_what_they_say | grep PERK`, `./run.sh fights
--calling=<calling>` once per Calling, and `./run.sh test --filter=test_footsteps_in_the_world |
grep FOOTSTEPS`.

### 1. The perks

Twenty-eight perk stats had no reader: the 25 listed last time, and `armour`, `noise` and
`stamina_cost_light`, whose names appeared in the code only as other things. Each is now read
where the thing it names happens. `test_perks_do_what_they_say.gd` takes every perk the way a
character takes one (the skill raised to where the perk opens, its prerequisites first, a perk
point spent) on the player scene, measures what the text names, takes the perk, and measures
again. Every row below matched the figure the text gives:

| perk | measured | before | after |
|---|---|---|---|
| wardens grip | sword light hit | 15.4 | 16.94 |
| quick steel | stamina for a sword light | 18 | 15.3 |
| ringing blow | sword poise damage | 12 | 15 |
| wide sweep | greatsword charged heavy | 68.64 | 75.504 |
| hafted poise | poise | 40 | 55 |
| bell swing | stamina for a greatsword heavy | 44 | 35.2 |
| fernhold draw | seconds to full draw | 0.9 | 0.783 |
| fletchers thrift | chance a loosed arrow survives | 0.4 | 0.65 |
| steady breath | arrow damage at full draw | 36.75 | 42.262 |
| braced stance | guard stability | 0.8 | 0.9 |
| braced stance | damage through the guard from 100 | 19 | 9 |
| ready answer | parry window s | 0.18 | 0.24 |
| broken in | armour worn | 12 | 13.2 |
| second skin | noise at a jog in plate | 0.872 | 0.693 |
| second skin | roll load | 0.886 | 0.543 |
| quiet step | noise at a jog | 0.513 | 0.359 |
| quiet step | a jump heard | 0.4 | 0.28 |
| light fingers | pickpocket chance | 0.508 | 0.658 |
| unsaid | sneak attack multiplier (sword) | 3 | 4 |
| fair dealing | buy price | 160 | 144 |
| fair dealing | sell price | 46 | 51 |
| loud name | renown from a deed worth 50 | 50 | 60 |
| hedge wise | restore health brewed | 24 | 28.8 |
| forager | lichen from one plant | 1 | 2 |
| bitter tongue | damage health brewed | 7 | 9.1 |
| red door | tier-2 sword hit | 17.22 | 18.655 |
| red door | tier-2 jerkin armour | 7.2 | 7.8 |
| thrifty forge | ingots for a greatsword | 4 | 3 |
| ember keeper | charge from four motes | 100 | 125 |
| deep writing | ember burst magnitude | 24 | 28.8 |
| wind in the chest | stamina | 180 | 195 |
| strong back | carry capacity | 100 | 120 |
| roll away | roll stamina | 22 | 18.7 |
| roll away | roll safe window s | 0.3 | 0.35 |
| warm word | mana for a kindle bolt | 11.4 | 9.69 |
| mote catcher | motes from a foe a Kindling word killed | 1 | 2 |
| quieted | mana for a frost bolt | 13.3 | 11.305 |
| held fast | ward seconds | 12 | 15.6 |
| held fast | binding word hold seconds | 1 | 1.3 |
| tender | health from Mend | 38.5 | 46.2 |
| loud company | seconds the hound stays | 45 | 58.5 |

Its last test reads every script in the game and fails when any of the 36 perk stat keys has no
reader (0 today).

Found on the way: nothing wrote the player's `stealth_visibility`, which every foe's eyes
multiply by, so a crouched figure in the dark was seen as plainly as one sprinting at noon; the
Stealth service now writes it every physics frame (0.62 in the open, 0.08 crouched in shadow).
The round shield could not be taken up: the slot rules knew only shields carried as weapons.
Red Door's wider temper step was shown at the forge and never swung or worn. A note written on
armour and a Resist draught changed nothing: `Equipment.modifiers()` was worked out and handed
to nobody, and nothing read `resist_<kind>`. `grant_perk` changed the modifier table without the
body hearing of it. Four stats needed a system first (DECISIONS): arrows that survive (40%, a
pickup where they strike, or loot in the body), Ember Motes caught from a Kindling kill (1),
picking an ingredient off the ground, and armour weight in the roll's load and in the noise.

### 2. Healing in a fight, and the fights again

DESIGN §5.5 has a flask that a Hearthstone refills, and there was none. `core:item/hearth_flask`
holds three swallows of 40% of greatest health. A swallow is a committed one-second drink (the
warmth lands at 0.55 s, and a stagger before then spills it). The flask is filled by a rest and
by coming back from death, kept by the save, and shown on the belt as swallows left against a
full flask. Potions, food, Mending (the Ashwalker's saying) and a rest already healed; the flask
is the one thing every Calling has from the first fight.

The scripted player now blocks when it has not the stamina to roll. Below 45% of its health it
backs off to drink, and when the flask is dry it says a mending saying below 55% if it knows
one. It says what else its Calling knows: a ward before the fight and again when it breaks, and
a bolt at a foe out of reach. An archer shoots, backs off inside 4 m and closes with its knife.
The Naming's own fight (three ash-wights) joined the roster. After the merge of the movement
rework the harness needed one more thing a player does. Locked on, the body now strafes at
2.6 m/s, and the smuggler-sayer backs off at about 3. The Cragborn and the Wayfarer followed it
3.0 m behind for two minutes and landed 0 of 52 and 0 of 48 swings. Out of reach, the scripted
player now sprints, which breaks the strafe, until it is in reach.

One run per Calling. Each cell is the time to win; "sw" counts swallows and "bl" blocks:

| fight | Hearthkeeper | Wayfarer | Reedborn | Cragborn | Ashwalker | Lantern-Clerk |
|---|---|---|---|---|---|---|
| naming: ash wight | 15 s | 18 s | 10 s | 24 s (2 sw, 1 bl) | 8 s | 19 s |
| skirmisher: roadside bandit | 23 s (1 sw) | 3 s | 5 s | 5 s | 2 s | 21 s |
| pack: down wolf | 32 s | 30 s | 10 s | 35 s (2 sw) | 8 s | 32 s (1 bl) |
| brute: hedge wight | 14 s | 14 s | 35 s | 20 s | 6 s | 15 s |
| charger: bristleback | 11 s | 13 s | 20 s | 12 s | 7 s | 13 s |
| ambusher: sallowjaw | 15 s | 15 s | 38 s | 22 s | 8 s | 16 s |
| caster: smuggler sayer | 26 s | 58 s (1 sw) | 39 s | 55 s | 28 s | 31 s |
| sentinel: warden | 42 s | 73 s | **120 s**, 47% left | 86 s | 42 s | 42 s |
| swarm: gutter drake | 34 s (3 sw) | 7 s | 9 s | 5 s | 7 s | 22 s (1 sw, 2 bl) |
| elite: bravo | 13 s | 41 s | 69 s | 64 s (3 sw) | 8 s | 14 s |
| boss: barrow reeve | **died** at 90 s, 61% left (1 sw) | **died** at 76 s, 61% left | **120 s**, 47% left | **died** at 115 s, 69% left | **died** at 38 s, 73% left (1 bl) | **120 s**, 71% left (2 sw) |

The danger-one foes, from Hearthvale and Brightwater, are the skirmisher, the pack, the brute, the
charger, the caster, the swarm and the elite. The ambusher is Sedgemire's (danger two) and the
sentinel Briarwold's (danger three). The ash-wights are the Naming's own fight.

What a competent player loses at level 1, and why:

* **The Barrow Reeve, for every Calling** (four die, two run out of the 120 s with 47–73% of him
  left). He has 520 health and armour 6 against 3–11 a blow. Four to six of his blows (22–36
  each, a knockdown among them) kill a 100-health character, flask and all. He is the third
  quest of the Wardens' line, behind 45 reputation and the quest before it, so he is met well
  past level 1 and was not tuned.
* **The warden, for the Reedborn** (120 s, 47% left). The Reedborn starts with fists and
  Hush-Frost (12 frost). The warden, a danger-three treant, has 265 health and armour 10, so
  the Reedborn lands 1.4 a hit and runs out of mana. Every other Calling kills it in 42–86 s.
* **Two Callings could not beat the danger-one foes** before they were given blades
  (DECISIONS). Measured again on the reworked movement, without its dagger the Lantern-Clerk
  died to the swarm with 85% of the drakes left. It ran out of time on the pack (95% left, 528
  damage survived by drinking), the hedge-wight (33%) and the bravo (41%). Without its knife the
  Wayfarer died to the swarm with 60% of the drakes left. With the blades both win every
  danger-one fight: the Wayfarer in 3–58 s and the Lantern-Clerk in 13–32 s.

The Ashwalker's sayings make six of its eleven fights trivial (2–8 s without a blow taken); the
other five Callings win the danger-one fights in 3–69 s. Nothing was tuned for that, because
DESIGN asks only that every Calling live through the first fights.

### 3. The heavy load band

Load is now measured against `20 + 1.5·Endurance` (35 at the start), no longer
`40 + 3·Endurance` (DECISIONS). With nothing in the bag, at base Endurance:

| worn and wielded | load | band |
|---|---|---|
| leathers and a sword | 25% | light |
| a brigandine and a sword | 51% | medium |
| clan plate and an iron greatsword | 89% | heavy |
| clan plate and the Bearer's clapper | 109% | overloaded |

Before, the heaviest of these reached 54%. Every Calling still starts light (0–14%). Second
Skin moves plate and a greatsword from heavy to medium (0.89 to 0.54).
`test_every_load_band_can_be_reached_by_what_is_worn` equips the four kits and checks each band.

### 4. The eleven sounds nothing played

Five were wired to their events:

* `bell_toll` rings for the Bell-bearer's toll and bell swing, for the Barrow Reeve's toll, and
  as the Reeve opens his second phase.
* `bell_hand` rings as a bell-headed weapon goes live: the Tolling knight's mace and his tolling
  blow, the Reeve's bell sweep, and the Last Cantor's blades.
* `bell_tavern` rings when you come through an inn's door (Toll's Lip), and not a bakehouse's.
* `footstep_snow` and `footstep_sand` play on the snow and the tide-flats the builder paints.

An attack or a boss phase may now name a sound. Footsteps on the terrain now read the paint:
`TerrainProvider.texture_at` names the painted id from the manifest's slot list, because the
Terrain3D texture list is emptied once its arrays are built. The builder's 21 textures fall into
8 surfaces.

Six were dropped, with their files and generators: `bell_tower` (no bell strikes the hours),
`thunder_near`, `thunder_far` and `wind_gust` (the ambience's storm and wind layers are those),
`wood_creak` (the creak pools are) and `cart_wheels` (no cart moves). A generator run also stopped
writing a dropped id back into `core:table/sfx` from the old manifest. The wiring test now fails
on any row nothing can play (0 of 64). The audio toolkit's 124 tests pass, two of them new: the
manifest and the table hold exactly what the catalogue makes.

### 5. Footsteps where the feet are

Every collider the POI kit builds now names what it is made of. A stone bridge's deck, parapets
and abutments are stone. A timber span, and every plank deck, post and ladder, is wood. Walls,
drums, doorways, steps, carved figures and cairns are stone, and a mound is dirt. A forged
asset's collision takes its surface from its name: pier, boardwalk, cart, stool and signpost are
wood; cliff, drystone, cairn and the giants' bones are stone; scree is gravel. One body can carry
both, so Foley reads the shape a ray hit before the body.

`test_footsteps_in_the_world.gd` loads the built world and finds each place from what was built:
the terrain's own paint, a bridge POI raised as the streamer raises it, and a deep place walked
into through Interiors. A body's footfalls walk it for three seconds at 4.2 m/s:

| where | at | heard |
|---|---|---|
| a market street in Merrowby (cobbles) | (900, 2350) | 6 × stone |
| the bog at Isseva (mud, peat) | (-2882, -500) | 6 × mud |
| the Skerrow heights (snow) | (1242, -3617) | 6 × snow |
| the western tide-flats (sand) | (-3485, -544) | 6 × sand |
| the deck of Larkbourne Ford (a stone bridge) | (733, 2303) | 6 × stone |
| the deck of Eelweir (timber) | (-1400, -100) | 6 × wood |
| the floor of Weaverdeep | the pocket | 6 × stone |

Its second test fails when a texture the builder paints has no footstep (0 of 21). In
`test_pois.gd`, every point of interest in the world is raised, and all 966 collision shapes
its builders put up name their surface. With the forged props there are 1269 stone, 241 wood,
46 gravel and 14 dirt; 131 props (trees, hedges, tents, braziers) leave it to the ground.

Found on the way and fixed:

* **A house or deep place entered from the overworld built nothing.** Its wrapper looked for
  the current interior, which is set only once the player is through the door. Interiors now
  hands it the meta.
* **What a quest left inside (the steward's key, the Ledger of Prices) was never raised when
  walked into.** The builders asked themselves which interior they were, and only the wrapper
  was told. The wrappers now hand the name down.
* **Every deep place dropped the player 3.0–4.5 m onto its mouth.** There was no Entrance marker,
  so the arrival fell back to a metre above the pocket. One now stands on the rock under the
  forge's entrance, read from the collision mesh (the voxel rock lies 0.25–0.55 m below the
  nominal floor). All nine arrive 0.05 m above rock.
* **A foe raised a script error on every sweep once its last candidate had been freed.**
  Perception now tests validity before `is`.

### 6. The arena, seen again

Run again after the audio commits and both merges, under xvfb with the OpenGL renderer
(`godot --path game --rendering-driver opengl3 -- --arena --verify --out=<dir>`): 16 checks, 16
passed, and 12 screenshots. They show the arena, the player, the HUD's bars, the compass and the
readied saying. Attack, parry and riposte, the roll's i-frames (0.08–0.38 s of 0.60), block,
stagger, a saying and silence, the bow, the mantle, the prompt, the wolves' flanking, the
charger's knockdown, the boss's phases and the respawn all pass as before. The wolves and the
bristleback are still placeholder boxes. The belt is empty, because the arena's Foundling never
passes through the Naming, which is where a new character is given the flask.

### Checks

`./run.sh test`: 1463 tests, 0 failed, 0 content problems, 0 script errors (the 4 logged errors
are the ones their tests provoke). `./run.sh journey`: 16 of 16 steps. The audio toolkit's
tests: 124 passed. `./run.sh fights --calling=<calling>` for each of the six: every check
passes. All were run after both merges; the POI tests were run again after the last change (19
tests, 0 failed).

### Found and not fixed

* **Going into a house stands the player in the corner of its first room**, a metre up, not
  inside the door. The house builder makes no Entrance marker and nothing reads the meta's
  `entrance`. Queued as its own task.
* **A whole `./run.sh fights` (six Callings in one process) crashes in the engine.** It crashed
  in two of three attempts, at a different fight each time. The crash is in a worker thread; the
  log shows `propagate_notification()` called on /root from a thread (the crash handler's own
  notification) and then signal 11, sometimes after Jolt's "exceeded the maximum number of
  jobs". Runs of one Calling (`--calling=`) completed 12 times in 12 across the two full sets,
  and the knife-less Wayfarer comparison crashed in two of three. The machine's load average was
  about 40 throughout.
* **Locked on, a melee player cannot close on a caster without sprinting.** The strafe speed
  (2.6 m/s) is below the smuggler-sayer's back-off (about 3). That speed is the movement work's
  number, so it is left alone and reported here.
* The Reedborn's first saying (12 frost) does next to nothing against armour 10.

### Next, in order

1. Stand the player inside a house's door (the queued task).
2. The Barrow Reeve at the level a player reaches him: fight him at the level the Wardens' line
   takes to get there, and tune him only if that loses.
3. The engine crash in long fights runs: a symbol build's backtrace, or split `./run.sh fights`
   into a process per Calling.
## Cloned, pressed Play, and stood on nothing

A player cloned the repository, played it on their own machine, and reported that "when
progressing in the game the player is transported to a blank empty plane with nothing visible
in every direction". Every check here passed, because this machine has the built world and
nothing else ever looked at a machine that did not.

**Reproduced first, both ways.** With `game/world/generated` empty, New Game went through the
Naming into a world with no manifest: the body stood at (-1900, 1, 3900), at y = 0 on nothing,
fog in every direction, HUD up — and `./run.sh flow` printed `FLOW: PASS (new: 67 checks, 0
failed)`. With the data but no Terrain3D regions (the state of a Mac, where the plugin never
loads), trees, props and the Hushline's bench hung in the same fog over no ground; `FLOW: PASS`
again. Nothing in the flow asked whether there was ground, and nothing in the game did either:
`world.gd` logged a warning and carried on.

Three things were true at once, and a clone met all three:

* **The world was not in the repository.** `game/world/generated` and `game/terrain_data` were
  ignored whole. `./run.sh` built them when the manifest was missing — Python, 8 GB, minutes —
  but the Godot editor's Play button does not run `run.sh`, and a failed build left nothing.
* **Terrain3D had binaries for two desktops of the three it names.** The vendored addon carried
  Linux and Windows on x86_64; `terrain.gdextension` points macOS at two frameworks that were
  not there.
* **Every way in let a player through.** The title menu, boot's `--new-game` and `--load`, the
  Naming and the capture runner all went into `world.tscn` without asking.

### What changed

**The title asks first (`WorldStatus`).** One module reads what is on disk and what the engine
loaded and says `missing`, `fallback` or `ready`. With no world data the title sheet says so
plainly — what is missing, `./run.sh world`, and what it needs — and New Game, Continue and Load
stay shut; asked again at the door, because the load screen calls `load_slot` itself. Boot,
the Naming and the capture runner ask the same question, and a world entered anyway (the
editor's Play Scene) stands down with the same notice and a way back to the title rather than
emitting `world_ready`. `test_world_status.gd` holds each branch: data missing, plugin missing,
regions missing, forced, both present — against the verdict, the title screen and the world.

**Terrain3D for macOS.** The official 1.0.2 archive came through the proxy by its release URL
(the GitHub API and release pages are refused; the Asset Library's entry 3892 names the file).
All four vendored binaries, `terrain.gdextension` and `plugin.cfg` are byte-identical to it,
which is how it is known to be the same release; its two macOS frameworks are added unmodified,
with the URL and every hash in `LICENSES.md`. Two things the release does not do: it has **no
Linux arm64 or riscv64 binaries** at all, though the `.gdextension` names them, and its macOS
frameworks are built for **macOS 15.0 and later** (their `LC_BUILD_VERSION`), universal, with
only the arm64 slice signed.

**The coarse ground (`FallbackTerrain`).** When Terrain3D cannot draw — no library, no regions,
regions that load as nothing, or `-- --fallback-terrain` — the ground is drawn from the builder's
8 m runtime height map: 256 chunks of 512 m sharing one flat grid with a skirt, lifted in the
vertex shader, with four index LODs that Godot's mesh LOD picks; the region's own terrain
textures in two arrays, tinted by the palette the way the builder's colour map is (the shader's
mean tint per region is within a few percent of `color.rgba8`'s), with slope, height bands,
snow, the lake bed and roads stamped at 2 m; and a HeightMapShape3D per chunk on the world and
terrain layers. The mesh, the collision and `TerrainProvider.get_height` split every quad the
same way — `test_fallback_terrain.gd` checks Jolt's split with a twisted quad and the world's
collision against the provider at forty points — and each cell's scatter, placed on the 2 m
ground, is set down on the 8 m one as it streams in. It builds in 1.8 s here when the machine
is quiet (1.6 s of it reading back and scaling the terrain textures) and 7.8 s at a load of 25.
Looked at against Terrain3D from the same cameras: the Hearthvale downs, the Merrowby street and
the Brightwater island read as the same country; the spawn's ash spit and the hill behind it
match; what is lost is fine relief — Cinderlea's terraces are rounded off, cliffs are softer,
and the field patchwork and hedge lines are not there.

**The runtime heights were read 3 m out.** `runtime/heights_1024.r32` is a 4 x 4 block mean,
so its texel sits at `origin + 8 i + 3 m`; `TerrainProvider` read it at `origin + 8 i`. Against
the 2 m ground that was more than a metre out on 37% of the land and more than three on 11%;
read where it is, 11% and 1.15%. The regions, water and levels are point samples and were read
correctly. The offset is in CONTRACTS §6 now.

**The flow fails on a void, and `run.sh` now says so.** After the body stands, the probe checks
that the ground is drawn (by Terrain3D or the fallback), that a ray finds ground under the feet,
and that at least ten drawn things stand within 200 m. With no world on disk it fails at the
title instead, with the title's words in its report. And `./run.sh flow` itself had never
failed: it ran `flow_run new && flow_run load && flow_run continue` and printed `[flow] PASS` on
the next line, and an `&&` list that fails part-way does not trip `set -e`, so a failed probe
exited 0 under a PASS, with only a `[flow] FAIL` line further up to say otherwise. The verdict is
taken from the list now. Any earlier "flow passes" that was read from the last line or the exit
code was not a reading of the probe. The other way round, this branch's final suite printed
`RESULT: PASS` and exited 1: `echo "$out" | grep -q` under `pipefail` (44 failures in 200
replays of that log); the parent branch's fix, a grep that reads to the end, is taken verbatim.

**The fade waits for the country.** It lifted on `player_spawned`, and in all three flow runs
**none** of the full-detail cells round the body was standing at that moment (the Hushline Stair
is on the world's south edge, so its ring is six cells, not nine): the first frame a player saw
was bare ground with the trees and the steps arriving over it. The fade now holds until the ring
is in, for up to 20 s, with "Laying the country around you: n of 6" in the caption and the body's
hands held; the probe fails a run whose fade had to give up. It held 8.0 s (New Game), 4.4 s
(`--load`) and 12.8 s (Continue) here, at a load average of 20; on a machine to itself it will be
a fraction of that. The world's own synchronous load (no frame at all for 17 to 19 s after the
press, the probe's note) is unchanged: that is the terrain and the doors, not the cells.

**Shipping the world so a clone plays without Python.** Every read of `res://world/generated`
and `res://terrain_data` in `game/` was traced. The game reads the manifest, `pois.json`,
`roads.json`, `rivers.json`, the four `runtime/` maps, the 1024 cells and the sixteen Terrain3D
regions, and nothing else:

| Set | Files | Raw | zlib-6 (git's) |
|---|---|---|---|
| manifest, pois, roads, rivers | 4 | 0.1 MB | 0.03 MB |
| `runtime/` | 4 | 10.0 MB | 3.8 MB |
| `cells/` | 1024 | 153.5 MB | 58.1 MB |
| `terrain_data/` | 16 | 145.1 MB | 144.7 MB |
| **total** | 1048 | **308.7 MB** | **206.6 MB** |

A repository holding exactly that set packs to **206.7 MiB**. The full-resolution maps only
the terrain import reads — `heights.r32`, `color.rgba8`, `control.u32`, `flow.rg8`, the three
`texture_*.u8`, `water_mask.u8`, `region_mask.u8` — are 304 MB and stay out. The Terrain3D regions
are already compressed: every region file is `RSCC`, the format `ResourceSaver`'s
`FLAG_COMPRESS` writes — zstd, but in 4 KB blocks — so a region's 13.3 MB comes to about
9.1 MB where whole-file zlib would give 7.6 and xz 5.8. There is no flag in
`import_terrain.gd` to change that: it hands the saving to Terrain3D's `save_directory`, which
chooses the format itself. Terrain3D's 16-bit height option would save about 2 MB a region at a
worst error of 0.125 m here (0.25 m above 512 m); not taken. Cells could be stored gzipped
(58 MB instead of 154 checked out; git stores them compressed either way): reading one costs the
worker thread 2.3 ms more for a median cell and 8.3 ms for the largest, against a JSON parse of
10.5 and 21.5 ms, measured at a load average of 20, and `_parse_cell` runs on the worker pool,
so none of it is frame time. Not done: it is the builder's file to write, and the builder is
another stream's this round. `.gitignore` now names
exactly the runtime set (checked against placeholders of every file the builder writes, and an
unknown new one, which stays out); `run.sh` imports a never-imported project before running it,
and `ensure_world` checks the manifest and the regions, imports the regions alone when the
full-resolution maps are there, and otherwise builds; README's "Run it" is rewritten for a
repository that carries its world. **The world data itself is not committed on this branch**:
another stream is rebuilding it this round.

**Proved on a clean clone.** A clone of this branch in a scratch directory, never opened and never
imported. With no world on disk, `./run.sh flow` imported the project (5060 files, a 519 MB import
cache) and failed at the title, whose sheet said what was missing, the command and what it needs,
with New Game, Continue and Load shut — and the sheet, seen there for the first time, overflowed
1280 x 720, so it was tightened. With only the runtime set copied in (`git status` in the clone
then listed exactly those 1048 files, and nothing else the builder writes), the same command passed
all three runs — 72, 28 and 31 checks, none failed, no errors logged — without building anything,
the fade holding 8.2, 12.0 and 11.1 s for the near cells. Then, as near as this Linux machine
can come to a Mac without the plugin, `terrain.gdextension` was taken out of the clone: the
`Terrain3D` class did not exist, the title showed its one small line about the coarse ground, the
world drew `FallbackTerrain` (built in 5.5 s at a load average of 32), and the flow passed all
three runs again — the body standing on the heightfield chunk `Ground_4_15` at 0.00 m, thirty
drawn things within 200 m, the notice on arrival.

### Found and not fixed

* **`tools_gd/check_scripts.gd` does not run on 4.7.2**: an internal VM error at its line 20,
  after which it never quits (the `SceneTree` waits for ever). Use the test runner.
* **The water sheet samples its maps 4 m out.** `painted_water.gdshader` maps a world point to
  `(xz - origin) / size`, which puts runtime texel k at `origin + 8 k + 4`: the mask and levels
  are point samples at `origin + 8 k`, the heights at `+ 3`. Four metres of shoreline.
* **Whether the water sheet is drawn at the sea inlets.** Its discard test is
  `texture(mask_tex, uv).r < 0.5` on a mask whose water texels are the byte 1, which normalises
  to 1/255; yet the Mere's surface looks like water from its shore. I have not settled which it
  is — Cinderlea's water is near-black and so is its ground — and the test that would is one
  capture with `use_mask` off beside one with it on.
* **`run.sh flow` keeps only its last run in a redirected log.** `flow_run` tees each probe's
  output to `/dev/stderr`, and when stderr is a file, `tee` reopens it truncated, so
  `./run.sh flow > log 2>&1` ends with only the Continue run in `log`. The per-run JSON reports
  in the output directory are complete; read those.
* **The headless teardown message came seventeen times, not sixteen** (`Parameter "material" is
  null`, Known issues above), in the first full run with the two new test files, which stand up
  three more worlds with people in them. Probably one more NPC body freed; not traced.
* **After this merges, a worktree with the world symlinked in shows the two symlinks as
  untracked** (`game/world/generated`, `game/terrain_data`), because `.gitignore` can no longer
  ignore those paths whole and still track files inside them. Add files by name.

### Then: Forward+, a player on Windows, and the coarse ground said out loud

The player's own logs (Windows, a Radeon RX 9070 XT, Forward+, Godot 4.7.1) said
`[World] ready: terrain=fallback` on every run, with no errors. Their world build had written the
maps and the Terrain3D import after it never ran: `run.sh` called `godot`, which is not on a
Windows `PATH`. The coarse ground carried them — and was much of the grey, barren look they
reported, announced by one small line on the title and one toast that they never saw.

**Forward+ on this machine crashed as the world was built, and it is not ours.** With Mesa's
software Vulkan driver installed, the flow got through the title and the Naming and died at
`add_child(terrain_node)`: the deprecation warning, "/root: The caller thread can't call the
function `propagate_notification()`", signal 11 in an unknown module. Terrain3D 1.0.2 alone in an
empty project (a camera, a light, the node) crashes it too. Under gdb all four `llvmpipe`
rasterizer threads stop at one address in the driver's compiled shader, on an indexed load
(`vmovd 0x0(%r13,%rax,4)`) out of range. The thread error is Godot's crash handler sending
NOTIFICATION_CRASH to the tree from that thread: under gdb, which takes the fault first, it never
prints. Nothing of ours touches the tree from a thread: the game's one worker-thread task (the
streamer's `_parse_cell`) reads a file and parses JSON, no node processes on a sub-thread group,
and nothing of ours listens to Terrain3D's signals. The deprecated
`instance_reset_physics_interpolation` is compiled only into Terrain3D's 4.4-targeted builds and
lands on Godot's compatibility binding: one warning, harmless, and not the crash.

When it crashes is the clipmap and the view, not the ring count alone. Alone, at 2 m spacing with
the regions, 60 frames each: Terrain3D's default 7 rings of 48, and 7, 8 and 9 rings of 32 (the
game's), all drew; 9 of 48 crashed. At 1 m spacing, 7 of 48 crashed on the first frame, with the
regions and without. In the game, 9 rings crash as the world is built; the painted-look stream
found 7 ran, and here 7 drew the real terrain (Cinderlea, the Builders' towers) through forty
seconds of the New Game flow and then crashed the same way. So fewer rings buy short captures,
not safety.

**No newer Terrain3D to move to.** `git ls-remote` of the upstream repository: the newest tag is
`v1.0.2-stable`; its `1.0` branch has one commit since, to the installation docs; `main` is
`1.1.0-dev` (`compatibility_minimum = 4.5`) and no longer makes the deprecated call, but has no
release and no official binaries. Nothing to verify against, so nothing was changed.

**What changed.**

* `WorldStatus` does not start Terrain3D on a RenderingDevice (Forward+, Mobile) whose adapter is
  llvmpipe: the coarse ground, with the reason and the renderer that does draw it (the
  Compatibility renderer's llvmpipe draws Terrain3D, as every flow here always has).
  `-- --terrain=terrain3d` tries Terrain3D anyway; `-- --terrain=fallback` asks for the coarse
  ground anywhere (`--fallback-terrain` still works), read from the user arguments and the
  engine's own, so the editor's Main Run Args carry it too. `-- --terrain-lods=N` (or
  `WICKMERE_TERRAIN_LODS=N`), 1 to 10, sets Terrain3D's clipmap rings for tools, nine when nobody
  asks; asking also tries Terrain3D on llvmpipe, for short Forward+ captures of the real terrain. On Forward+ over lavapipe the New Game
  flow now passes (75 checks, none failed, no errors logged), and so does it with
  `--terrain=fallback` (74).
* The coarse ground, unless asked for, is said where it cannot be missed (`GroundNotice`): across
  the title sheet as plainly as a missing world, with the way to the full terrain and the way in
  still open; on a card across the top of the view once the region's name has gone; and on a
  "Coarse ground" plate in the top left corner, with the reason, for as long as the HUD is up.
  Asked for, it is the plate alone and one small line on the title. When the maps were built here
  and never imported, the way named is `./run.sh terrain`, not a rebuild. The flow checks the
  plate and the card on the coarse ground, and that nothing says so on Terrain3D.
* `run.sh` finds Godot: `GODOT` if set, then the usual names on the `PATH`, then the usual places
  (Downloads, the Desktop, `C:/Godot`, Program Files, Steam and winget on Windows, the console
  build first; `/Applications/Godot.app`; an unpacked Linux download), a 4.7 before any other,
  with a warning when it is not a 4.7. `./run.sh godot` says which. A command that needs Godot and
  has none stops before doing anything, with a banner naming `GODOT` and an example per system;
  `./run.sh world` looks before it builds. A failed terrain import gets a banner too, and
  `./run.sh terrain` runs the import alone. Python is found the same way (`PYTHON`, `python3`,
  `python`). Checked on this machine against fake homes; not run on Windows.
* This branch's final suite had printed `RESULT: PASS` and exited 1: `echo | grep -q` under
  `pipefail`. The parent's fix is taken verbatim.
* The arrival card waits 4.8 s of game time for the region's title card, and game time is slow
  when frames are: the engine clamps a slow frame's delta to what its capped physics steps cover
  (0.12 to 0.15 s for a 0.5 s frame, measured), so on Forward+ over lavapipe under load the probe's
  twelve seconds ran out before the card came. It waits up to ninety.
* **The pushed branch, cloned and played.** Once the world was committed (197a50c1, the 1048
  files of the runtime set), `claude/blissful-volta-dg80e6` at 549dd05 was cloned fresh from
  GitHub (`--depth 1`, 1.4 GB checked out), never opened, never imported, no Python run. In it
  `./run.sh flow` imported the project and passed all three starts on Terrain3D: New Game 73
  checks, `--load` 28, Continue 31, none failed, no errors logged; the ground drawn by Terrain3D,
  46 drawn things within 200 m, the fade held 8.3, 6.1 and 3.5 s for the near cells. In all
  three the ray down from the body met the Hushline Stair's masonry 1.36 m below the feet and
  no terrain collision: the same in every Terrain3D run here since the first, and consistent with
  what the user's second playtest found and main has since mended (Terrain3D's collision stayed
  round the fly camera, not the player).
* **Main's `World.follow` and dry landing merged in, and nothing here leans on the fly camera.**
  The coarse ground's collision is a heightfield per chunk over the whole world and its LOD is
  Godot's mesh LOD on whatever camera draws; the fade's count asks the streamer, which `follow()`
  points at the body before `player_spawned`. The flow now checks both things that let the old
  bug through: that Terrain3D's camera is the body's own, and that the fade counted cells round
  the body at all (a streamer following something else counts nothing, and nothing is all in at
  once).
* **The fade counts cells, not seconds** (the coordinator's finding on the main branch: the
  `--load` start lifted with 8 of 9 near cells after 535 s of wall time, the machine running the
  game at a few per cent of real speed). The 20 s cap described above is gone. `UI.wait_for_country`
  holds while cells keep arriving and gives up only when none has come for 120 frames and 10
  seconds together, or after 600 s; the caption goes on counting. `test_country_wait.gd` throttles
  a fake streamer by hand rather than hoping for a slow machine: a cell every eight frames at two
  seconds a frame is waited out to nine of nine (the old wait would have lifted on one), a streamer
  that stops at five is given up on after both halves of the stall and no longer, a cell every 45
  frames on a 1 ms clock is not given up on for its quiet frames alone, and the cap ends a wait
  that is still moving.
* **The wait went to main without the probe that reads it.** fc24424c took `UI.COUNTRY_WAIT_S`
  away and `flow_probe.gd` still named it, so the probe does not compile on a main that has
  fc24424c alone and `./run.sh flow` has no verdict there; 3e10d533 on this branch is its other
  half.
* **A player who built the world pulls the tracked one without trouble.** Modelled in a scratch
  repository with both `.gitignore`s: the locally built manifest and runtime maps were ignored, so
  `git pull` replaces them with the tracked ones silently (git's default for ignored files) and
  leaves the full-resolution maps alone; `git status` is clean after. Those maps are then the old
  build's: `./run.sh` leaves them be (the regions are there), but a `./run.sh terrain` would import
  them over the tracked regions.
* **`run.sh` stopped reaching for `xvfb-run` on Windows and a Mac**, which never have it and
  always have a screen.

**Found on merging main at f1cd8852, and not this stream's.** The merged suite: 1562 tests, 3
failed, 3 script errors, where this branch alone had been 1421, none failed and none. (Main
mended the three tests and the errors itself in d9c4b6ce and ef0b0ce2; merged again at 146494ec,
the suite is 1570 tests, none failed, no content problems, no script errors, no dead captures.)
`test_inventory_loot`'s two quest tests count the Naming's stages as wake, ash_wights, hearthstone,
the_cart (quests round two, b1326eb6), and the opening (20ef631b) put `the_choir` second.
`test_the_start.test_the_stair_head_is_a_camp_with_the_warden_s_place_in_front` finds one light
at the Stair Head where it wants more than two. `test_property` calls `Ownership.instance`, which
it never makes and which no test before it now leaves standing. And the New Game flow sat in the
opening for 601 s with 2 of its 10 shots shown, at a load average of 25: each shot holds until the
cells round its points are in, and they came slowly. It did the same again on the final merge
(602 s, the same two shots, `the_name` and `the_mere`, then a hold on the third), so it may not be
load alone. It never handed over, so the HUD, the first
frame of control, the Warden, the objective line and this stream's Terrain3D-camera check all
failed after it: the camera was still `/root/World/Opening/CinematicCamera`. The hair chooser's
list did not open within its 60 frames either. The slot that run saved kept the `new_game` flag up
(it stays up until the opening hands back), so the `--load` start after it played the opening
again. With `-- --no-opening` the same three starts read past it: every check of this stream
passed in all three -- nine of nine near cells in before the fade lifted (13.7, 25.1 and 20.3 s,
two frames each), Terrain3D following `/root/World/Player/CameraRig/Yaw/Pitch/Arm/Camera3D`, its
ground 0.00 m under the feet, 158 things drawn within 200 m -- and `--load` passed whole (32
checks). New Game failed only the two choosers and the opening it was told not to play; Continue
only "the body's hair is short (it is long)": it takes the newest slot, and every worktree on this
machine saves into the one `user://`. On Forward+ over lavapipe, `--load` with the opening off
drew the coarse ground and passed every check of this stream -- the plate in the corner, the card
41.9 s after the fade (game time runs slow there), the body on `Ground_4_15`, 160 things drawn
within 200 m, the fade holding 87.2 s for nine of nine -- and failed only the same hair.

### Next, in order

1. ~~**Commit the built world.**~~ Done on the main branch (197a50c1), and a fresh clone of it
   plays without Python (above).
2. **Play it on a Mac.** Nothing here can run macOS. On macOS 15 or later the title must say
   nothing about the ground and `./run.sh flow` must pass on Terrain3D; on macOS 14 or earlier the
   title's notice must name macOS 15, the corner plate must say "Coarse ground", and the flow must
   pass on the coarse ground. If the frameworks are refused (quarantine, signing), the Console log
   says so and the game still plays, coarse, and says so.
2a. **Run `./run.sh` on Windows from Git Bash**, with Godot unzipped into Downloads and not on the
   `PATH`: `./run.sh godot` must name the console build, and with no Godot anywhere every command
   must stop with the banner before building anything.
3. **Linux on arm64** is the same test as an old Mac, and Terrain3D has no binary for it: the
   fix there is upstream, or building Terrain3D 1.0.2 for arm64 ourselves.
4. **Settle the water sheet** (see above): one capture of the Mere and one of the Hushline's
   inlet with `use_mask` on and off. Then move its samples onto the texels they belong to.
5. **The coarse ground's weak places**: Cinderlea's terraces, cliffs and the field patchwork do
   not survive 8 m. A 2 m runtime copy of the heights would be 64 MB; a small runtime field map
   from the builder would bring the hedges back. Both are the builder's files, not this stream's.
6. **`check_scripts.gd`** wants mending for 4.7.2 or deleting.
## Walking, the view, the roll and the compass: what the player felt, measured

The first report was "the walk animation seems very slow and jagged, like a crouch walk (no
sprint?)", and that the compass moved erratically as the player did. After playing the build:
"the movement is indeed very slow, and the mouse/movement (WASD) relationship seems off, hence
the compass and orientation issues". After the first round: "movements/animations still a
little clunky (no roll?)". Every part of that was true, and each had a cause that could be
measured. Most were not the cause first guessed.

**The view turned with the body.** The camera rig was a plain child of the player's body, so
the view looked along body yaw plus rig yaw, while movement, respawn, the save and every test
read the rig's yaw as the whole of it. One second of D, mouse untouched, turned the body −90°
and the view +89.9°. The compass swung 89.9° in steps of up to 21° a frame, and W then sent the
body off at an angle to what the player could see. That one fault is the "mouse/movement
relationship" and the "compass and orientation issues". The rig is `top_level` now. It follows
the body's drawn position every frame, never its rotation, and its yaw is a world yaw that only
look input changes. The mouse signs were already right; a test pins them now. W/A/S/D are
relative to the view, and over twenty cases (camera yaw 0, 90, 180, 270 and odd angles, each
key) the worst direction error is 0.00°. The body turns toward where it is going at a rate that
falls with speed: 900°/s standing, 720 at a walk, 540 at a jog, 300 at a sprint. It gives up
speed while a large turn is still to make, so a reversal from a jog plants and faces round in
0.42 s instead of moonwalking. Locked on, blocking or in first person, it faces the target or
the view and strafes.

**"Very slow" was two things, and only one of them was the speed.** A brand-new character
reached exactly 4.20 m/s, the design's number, in 0.067 s, and nothing but a status touches
ground speed. The gaits are now walk 1.8 m/s (Alt, or a light stick), jog 5.0 (the default)
and sprint 7.8 (Shift held). The sprint costs 8 stamina a second, and run to empty it stops
until a quarter of the pool is back instead of stuttering on every regen tick. Measured on a
new character: 1.80, 5.00 and 7.80. Rest to a jog takes 0.317 s; a jog stops in 0.25 s over
0.58 m, a sprint in 0.48 s over 2.05 m. The other half of "slow" was a jog posed as a crouch.
The blend space fed velocity/6.5 with Sneak_Walk half way up its forward axis, so at 4.2 m/s
the body was three-quarters into the sneak: hips 15.2 cm below standing, knees at 58°, the
planted foot sliding at 79% of the ground speed. The sprint played the Walk clip and slid at
76%. Legs that shuffle under a gliding body read as slow at any speed.

**The legs keep pace with the ground.** `HumanoidModel.set_locomotion` takes metres per second.
Every moving clip lies on one shared stride timeline with its silent inputs kept running, and
one time scale plays it at ground speed over stride. The planted foot as a share of ground
speed is now: walk 2%, brisk walk 2%, walk to jog 6%, jog 3%, jog to sprint 3%, sprint 3%, sneak
1%, a villager at 2.2 m/s 2%, a strafe 0%, a backpedal 0%. The thresholds are 5% at a gait and
8% in a blend. Every gait reads the same phase to within 0.001 of a stride through a walk, a
jog, a sprint, a strafe and a backpedal. Villagers were never told how fast they walked; the
village glided about in its idle pose. They are told now.

**The clips were crouched as well.** Walk, Run and Sneak_Walk are re-made in the forge at the
game's speeds, and there is a new Sprint. Played in the engine at walk, jog and sprint speed,
the hips rode 5.4 cm below standing with 11.4 cm of bob at a walk, and 8.7 cm with 23.9 cm at a
jog. The sprint was the jog's clip sped up and did the same. Now they ride 4.2 cm with 5.0 cm,
4.1 cm with 5.3 cm, and 4.4 cm with 6.2 cm. The first model's walk was lowest at mid-stance
and its run highest there, which is backwards. The new stride model in
`tools/forge/lib/anim.py` plants the foot ahead of the hip by a share of the sweep, plans the
hips from where the ankle really is once the foot has rolled, meets the reach limit through a
smooth minimum, and phases the bob the right way round. The side-steps dropped the hips 21.3 cm
at every step, a bounce whenever the player was locked on, and are shortened to move them
5.7 cm.

**The roll existed; nothing said where it was.** Proved from real key events through the
default bindings, Ctrl rolled a jogging body 3.31 m in the tick the key went down, untouchable
for 0.30 s, playing Dodge_F. But Ctrl is a key the genre does not use for a roll. A tap of
Sprint now rolls, as it does in the games most players will have come from, and a hold sprints.
The sprint waits out the 0.22 s tap window, so a tap is not a lurch and then a roll. Ctrl and a
pad's B still roll, and Space stays jump. The tap has a setting and is off while Sprint is a
toggle. The roll itself was wrong too: its keys put the toes 19 cm into the ground on the way
down, the head 24 cm into it at the turn and the back 26 cm clear of it coming over, and it
stood up on bent legs with its feet 30 cm in the air. Every frame now lowers or raises the
whole body until its lowest point touches the floor, within 1 cm, and it ends standing. It also
widened the view: the sprint's widening read real speed, and a roll peaks at 11 m/s, so every
roll breathed the view out from 75° to 77.8°. It stays at 75.0° now.

**The first minutes teach the controls.** A strip low in the HUD reads "WASD move · Shift
sprint · tap Shift roll · Space jump · E use · LMB strike · RMB block" from the live bindings,
or the pad's buttons while a pad is in use. Each item fades once it has been done, and the
strip goes when nothing is left or after fifteen minutes. What was learned rides in the game,
so a new game is taught again. The pause page reaches "How to move and fight", every control as
bound now, one button from rebinding.

**Locked on, the pace goes by the way you go.** The combat round's headless fights found that
a locked-on player could not close on a caster backing away at about 3 m/s: every locked-on
direction was capped at 2.6 m/s, and the gap grew 1.39 m in three seconds of W. Locked on, the
body now goes 5.0 m/s at the foe, 3.0 across and 1.8 backing off (the ellipse between), and the
gap closes 5.26 m in the same three seconds with the lock held. In the arena, at the old pace
the Cragborn's caster fight was not won in 120 s (0 of 53 swings landed); at the new one it is
won in 35.1 s, and the Hearthkeeper's in 20.7 s rather than 59.0. Sprint while locked on runs
and keeps the lock. A raised guard walks at 1.56 m/s. It used to glide there with frozen legs,
because Block_Idle was played as a whole-body state. It is a layer over the upper body now, and
the legs walk under it, 2% slide. A body turning on the spot, guarding or locked on, steps
round rather than pivoting on planted feet.

**Starts, stops and the camera's follow.** The stride's rate was read off a speed smoothed over
0.08 s. Under a jog's stop that runs up to 1.6 m/s ahead of the body, so the legs went on
stepping 0.12 of a stride after the body stood, then held a split for a tenth of a second and
snapped together. The rate now follows the ground speed as it is, no step is taken after the
body stands, and the idle eases in over 0.2 s from the moment the body's own speed says so. The
camera trailed a jog by 0.34 m and drew 0.4 m away at every start and back at every stop. It
trails by 0.23 m now and closes up in about 0.15 s.

**Smooth at any refresh rate.** Physics interpolation was off, so a body moved at 60 Hz stepped
on any faster display, and the camera and the compass stepped with it. It is on, with the
jitter fix off. What that needs was measured in the engine first. A child moved every frame
under an interpolated parent trails (drawn at 3.61 when put at 4), so the per-frame things opt
out: the camera rig, the sockets on the hands, the atmosphere, a dropped item's bob, the Echo's
hover, the Naming's mannequin, the UI. An existing node moved without a reset smears (moved
from x = 4 to 500 it was drawn at 254 for a frame), so everything that jumps resets:
`Player.teleport` (which respawn, loads, doors, jail, exile and the console go through), an
enemy sent home, a villager put indoors, a loaded actor. A wall 1.6 m behind the camera pulls
it in to 1.39 m at once, and it eases back to 3.59 m over a third of a second. A sprint draws
it back 0.5 m and widens the view from 75° to 81.8°, eased both ways. Checked against
`World.follow`, which gives Terrain3D the player's own camera: a teleport made outside a physics
tick (a respawn timer, a load, the console) left the interpolated transform at the old place for
a frame, so the rig snapped there and the frame was drawn, and the terrain built, from 800 m
away. On the frame of a snap the rig now reads where the body was put: 4.23 m from it the next
frame.

**The compass reads the view**, eased over about 30 ms, processed after the camera, with
bearings from where the body is drawn. On a path past Merrowby that turned the body 450° with
the mouse still, the strip moved 0.00°. With the view turning, it stays within 1.33° of the view
and never moves further in a frame than the view did plus the lag it carried.

**Holes found on the way.** The Echo handed a death's marks back. An Area3D finds an overlap
in one physics step and reports it at the start of the next, and the journey dies and comes
back one frame apart. So the body's single tick on the Echo was reported after Hearth had
armed it and moved the body 30 m to the stone. The Echo now checks the body is standing in it
when the arrival is reported; a test reproduces the stale report. After the merge with the
combat work, three tests measured the machine instead of the game, and they are fixed. The
blend test played every tick twice once the model advanced its own tree. The compass test's
bound grew with frame times. A footstep test walked "a second and a half" on a loaded wall
clock that fitted a third of a second of play.

**Tools left behind.** `game/tools_gd/motion_studio.tscn` films the real player on a plain
floor from real key events, in Forward+ in a minute or two, where loading the country crashes
Mesa's software Vulkan. `tools/capture/plans/motion.json`, `gaits_studio.json` and
`controls.json` are its plans. The capture runner's gait runs can hold and tap real keys
(`tools/capture/plans/roll.json`). `tools/forge/bake_clips.py` bakes every clip onto the bare
armature in 26 s where the rig bake takes 24 minutes. `tools/forge/transplant_clips.py` moves
clips onto the committed rig by bone name and proves nothing else changed. Under Blender 4.2
the rig bake repaints the body the 4.0-built rig was made with, so the transplant is how
clips change without the body.

**Looked at.** Eight frames 0.1 s apart of each gait, from the side, in the world at the
Cracked Toll, through the capture runner's `gait` section (`tools/capture/plans/gait.json`,
`--fixed-fps 60`), before and after. Before: the jog was a hunched, bent-kneed shuffle with
both feet near the ground in every frame; the "walk" was the same, since there was no walk key;
the sprint was the Walk clip at 6.5 m/s, an upright stroll with the arms hanging. After: the
walk is upright, with a heel strike and a straight leg under the body. The jog leans a little,
drives a knee and leaves the ground between steps. The sprint leans hard, drives the knee to the
hip and spends much of each stride in the air. In Forward+, in the motion studio: the roll goes
over the shoulders and back and ends standing; the stop's stance closes steadily over 0.2 s,
where it had frozen mid-stride and snapped; a guard held while walking now steps under the
raised hands, where the legs had stood still; a turn on the spot steps round.

**Checks at the end.** On the final head: `./run.sh test` 1436 tests, 0 failed, 0 content
problems, 0 script errors, 0 dead lambda captures; `./run.sh journey` 16 of 16, 0 logged errors;
`./run.sh flow` PASS on all three starts (new 73 checks, load 28, continue 31, 0 errors logged).
The forge's own tests: 28, all passing. `./run.sh fights --only=caster`: both Callings win.

### Found, and not fixed

* **A stop still slides its feet together.** The split closes steadily over 0.2 s now rather
  than freezing and snapping, but the feet travel 59 cm in all doing it. A stop clip (the back
  foot stepping up) or foot locking would take it out.
* **Turning on the spot is a side-step, not a turn clip.** It reads as stepping round in the
  frames; 90° and 180° turn-in-place clips would be the proper thing if it reads as a shuffle
  in play.
* **The diagonals slide.** Locked on, the planted foot moves at 28% of the ground speed on the
  forward diagonal (3.64 m/s) and 23% backing off diagonally; it was 19% at the old 2.6 m/s.
  Blending a forward stride with a side-step in rotation space does not put the foot at the
  average of the two footfalls. It needs diagonal clips or foot IK.
* **Footsteps count ground, not footfalls.** The foley added in the combat round counts
  ground covered and is right on average. The clips carry `footstep_l`/`footstep_r` at the
  shared phase (left 0, right 0.5), which would put the sound exactly on the foot.
* **The pad layout wants its own pass.** The right-stick click is both lock-on and camera
  toggle, and D-pad up is both cast and quick slot 1. The Sayings menu has no pad button since
  sprint took the left-stick click. Cycle target, lantern, skills and quick save/load have
  none either.
* **Walk_Back and the strafes are still made by the first stride model.** They measure
  upright enough (Walk_Back 3.7 cm below standing, 6.8 cm of bob), so only the side-step
  length changed.
* **Villagers walk at 2.2 m/s**, the walk clip at 1.2 times its speed: purposeful, not wrong.
* **Terrain3D 1.0.2 calls the deprecated `instance_reset_physics_interpolation`**, which prints
  a warning at load and is harmless.

### What a pair of hands should check

The feel cannot be measured headless. Check the turn rates, the 0.3 s start, the stops, the
0.22 s tap (too short for a deliberate tap? too long for a sprint start?), mouse sensitivity,
whether 3.6 m behind the shoulder is the right distance, and whether the sprint's widening
reads as speed. On a display faster than 60 Hz, the body and the camera should glide, not
step; the software rasteriser here cannot show that. On Windows, check that Alt (walk) does not
take the keyboard into the window's menu, and that Ctrl + W in the editor's embedded game
window rolls rather than closing anything.

## Doors walked both ways, the crash found in the audio mixer, and every interior walked into

Three parts, in the order they were asked for, the second made first when the same crash killed a
unit run. Measured with `./run.sh test --filter=test_every_door_both_ways` (its DOOR and CONTENTS
lines), `tools/debug/audio_race_check.sh`, and `./run.sh fights`.

### 1. Every door lands the body just inside it, and just outside it on the way back

All 24 doors the world puts up (15 houses, 9 deep places) are walked both ways by the world's own
player, as a player would: stand two paces out, press the door, measure, press the way out,
measure again.

* **In.** A house now stands the body a step inside its front door. It is on the floor of the room
  the door opens into, facing into the room, on the nearest spot that is clear of the real prop
  meshes. The forge had stood Maud's bread oven, one of Hesta's stools and Osric's bellows right
  inside their doors. A deep place stands the body 1.2 m inside its way out, on the rock. Measured
  across the 24, the body lands 1.03-1.74 m from the interior's own door and 0.04-0.05 m over the
  floor, standing in nothing, facing into the room: 1.00 where the door is straight ahead, and
  0.59-0.98 where the nearest clear spot is to one side.
* **Out.** The body lands 1.50 m in front of the door it came in by, on the ground (0.00 m), facing
  away from the door (1.00).
* **Before.** A house put the player in the corner of its first room, a metre up. A deep place put
  them in the middle of its mouth chamber, 3-5 m from the way out. Leaving faced the player back at
  the door they had just come out of.
* **A game saved inside.** It now leaves by the door it came in by. The load had taken the body's
  own position, in the pocket 50 km off, as the way out.

### 2. The crash: the engine's audio mixer reading freed memory

**Found.** All five crash logs have the same backtrace: four fights runs and the unit run on
main. The stripped binary's frames were named by the strings each function refers to (Godot's
error macros carry the file and function names):

* StringName's copy constructor ("!configured", string_name.cpp);
* AudioServer::_mix_step, at the copy of a playing sound's bus details;
* AudioServer::_driver_process;
* the audio driver's thread.

The "/root: The caller thread can't call `propagate_notification()`" line is the crash handler
itself, running on that thread.

**Why it happens.** Godot 4.7.2 swaps in new bus details whenever a playing sound's volume or
panning changes. For every AudioStreamPlayer3D that is playing, that is every physics frame: it
compares a mix count it never records. AudioServer.update() frees the old details two updates
later, whatever the mixing thread is doing. A mixer descheduled between loading a sound's details
and copying them therefore copies freed memory.

**Not the suspects.** Jolt, bodies freed in flight, navigation, interpolation and Terrain3D are
not involved. The crashing thread was the mixer every time. The Jolt warning that came before some
crashes is starvation, and no project setting sets that limit.

**Reproduced deterministically.** `tools/debug/stall_mixer.py` holds only the mixing thread, under
gdb, at the instruction between the load and the copy (0x3b19830 in the official build).
`tools_gd/audio_race.gd` keeps sounds playing. Results:

* frames unpaced (`--fixed-fps`): crashed at the first 30 ms stall;
* frames paced at 60 a second: crashed at the first 20 ms stall, and after 57 stalls of 10 ms;
* the real fights harness: crashed after 32 stalls of 20 ms.

**Can the game hit it?** Yes. The unit suite and a Forward+ world load are paced runs, and they
met it. It needs the mixer descheduled at one instruction for about a frame. That is rare on an
idle machine and ordinary on a busy one. More sounds playing means more chances.

**Fixed, or worked around where the fault is the engine's.** `AudioGuard` (systems/audio, stood up
by Foley) stands between frames in every run. At the end of each frame's processing it takes the
audio driver's lock and lets it go at once. The mixer holds that lock for a whole mix, so this
waits out a mix under way and holds nothing. Anything a later update() frees was swapped out
before the barrier. With the guard:

* the stalled reproduction ran its 40 s through 1,434 stalls;
* the fights under 20 ms stalls completed through 2,655 stalls;
* two full six-Calling fights runs in one process passed (66 fights each, 0 checks failed), where
  two of three had crashed before;
* the unit suite ran 1,584 tests with 0 failed and no crash.

Ours, also fixed: the music stems and ambience beds wrote their volume every frame. Every write
swaps in new bus details, and they sit at their level most of the time; they now write only when
the volume moves.

**Regression.** `tools/debug/audio_race_check.sh` fails unless the stalled reproduction crashes
without the guard and runs with it. It needs gdb and the official 4.7.2 build, and a crash cannot
run inside the suite. `test_audio_guard.gd` checks four things:

* a barrier every frame;
* that the barrier waits for whoever holds the lock (257 ms behind a 250 ms hold);
* that it holds nothing (the mixer goes on mixing);
* that an unmoved volume is not written.

The fault should go upstream with the reproduction. AudioServer's bus-details graveyard frees by
frame count and not by the mixer's progress, and AudioStreamPlayer3D never records
`last_mix_count`.

### 3. Every interior walked into from the world

The same walk now checks what each interior holds, against its meta and the quests.

* **Holds what it should.** All 24 are built (44-169 meshes, a floor that says what it is, 3-44
  lights). Every house prop the meta places stands (13-50 per house). Every foe a deep place's
  markers ask for stands (8-14 per place). Every quest thing the placer puts inside is there: the
  steward's key, the Ledger of Prices, the note at the Cantor's Seat, the cold flour, and the
  things in Tallissa's and Dunna's houses. Built empty from the overworld and quest things not
  placed were the faults fixed in the last round; they hold here.
* **Stood over the rock.** A new case of the arrival drop's class. Every deep place stood its
  Hearthstone, dressing, pickups and quest things at a chamber's nominal floor, 0.34-0.55 m over
  the voxel rock. Sunken Barge stood its Hearthstone in the middle of the hold, over the pool,
  with no rock within 6 m under it (the hold's and the nest's middles are both over nothing).
  Features, spawn markers and the placer's things now go on the rock under them, or on the
  nearest floor point that has rock under it. All nine deep places now measure 0.00 m.
* **Other ways in.** A loaded game re-enters through the same builder as a door, and leaves by the
  saved door (part 1). The console's `interior <id>` also uses the same builder. No deep place has
  a door to a second interior.

### 4. Combat timing against DESIGN §5.3

Measured in the player scene on the merged head, after the movement rework, the tap-to-roll and
physics interpolation, by `test_combat_design.gd` at 60 physics frames a second. Every timing
lands within one frame (16.7 ms) of DESIGN:

| what | DESIGN | measured |
|---|---|---|
| stamina regen | 30/s after 0.8 s | 30.00/s after 0.800 s |
| sprint | 8/s | 8.00/s |
| input buffer | 0.25 s | 0.250 s (a press 0.25 s early fired, one earlier did not) |
| light chain | 3 | 3 (indices 0, 1, 2, then 0) |
| heavy charge, tapped / held | 1.0× / 1.5× | 1.017× / 1.500× |
| cancel into a dodge | after the active frames (hit_end 0.467 s) | 0.483 s, the next frame |
| roll at a light load | 0.60 s, i-frames 0.08-0.38 s | 0.600 s, 0.083-0.383 s |
| roll at a medium load | 0.66 s, 0.08-0.34 s | 0.667 s, 0.083-0.350 s |
| roll at a heavy load | 0.80 s, 0.10-0.30 s | 0.800 s, 0.100-0.300 s |
| roll overloaded | 1.00 s, 0.12-0.26 s | 1.000 s, 0.133-0.267 s |
| parry window | 0.18 s | 0.167 s (10 frames; 11 frames early is too early) |
| riposte open, and its damage | 2 s, 3× | 2.000 s, 3.000× |
| poise regen | 4/s after 1.5 s | 4.00/s after 1.500 s |
| enemy wind-ups | as authored | 0 frames apart over 100 attacks |

The one gap is the tapped heavy. It is released after a frame of charge and lands at 1.017×.
Nothing was changed for it. Main's roll by a tap of Shift starts on the release, up to 0.22 s
after the press, as its own DECISIONS entry says; Ctrl and B start on the press.

### Checks

Run on the merged head (main at a3e9fe6b), one Godot at a time:

* `./run.sh test`: 1,584 tests, 0 failed, 0 content problems, 0 script errors, and no crash. The
  4 logged errors are the ones their tests provoke.
* `./run.sh journey`: 16 of 16 steps.
* `./run.sh fights`, all six Callings in one process: 66 fights, 0 checks failed, twice, with no
  crash.
* `tools/debug/audio_race_check.sh`: passes. Without the guard it crashes at the first stall;
  with it, it runs 40 s through 1,650 stalls.
* The audio toolkit's tests: 128 passed.
* `./run.sh flow`: **fails, in the opening cinematic.** Two of its ten shots are shown, then it
  holds on the third for 606 s, and a held key does not skip it. Ten of the 88 checks fail, all
  downstream of that: no HUD, the cinematic camera still current, nothing drawn near the body.
  It fails the same way with the audio guard off (`--no-audio-guard`, 606 s, the same ten), and
  nothing in this branch touches the cinematic or the streaming.

### Found and not fixed

* **The opening cinematic hangs on its third shot** in `./run.sh flow` (above), and holding a key
  does not skip it; it is the opening's own work and was left to it.
* The engine faults above, to report upstream with the reproduction.
* A house's front door always opens into its first ground-floor room from the north wall, and the
  meta's `entrance` names an internal door; the landing reads the front door and ignores
  `entrance`.

## The opening, and the start it hands over to

The user's report was "no proper intro cinematic", and there was none: "Be named" cut from the
Naming to a body on the Hushline Stair with a quest toast. The second playtest added: "Starter
area seemed barren and without obvious direction/compelling elements of the map". The player had
been stood on the Stair's pad, a single 8 m mound in the Hush's water at the foot of an 80 m
cliff. The first objective, "Go to The Hushline Stair", was done the moment it appeared. The
Warden it asked for next was in Merrowby. There is an opening now, and a start (DESIGN §5.1a;
DECISIONS 2026-09-22 and 2026-09-23).

### What a new game does

After the Naming on a **New Game**, the Warden says the name back over black. Then she tells the
Foundling what they have come up into, over the real country, which streams in as the camera
flies. The last shot comes up the cliff from over the Hush, follows the Hushline Stair to the
Wardens' camp at its head, and settles behind the Foundling's shoulder facing the Choir. Control
comes back there. The Naming starts at that hand-over, not under the pictures. The Warden speaks
first, and the HUD writes "The Naming: Speak to the Warden at her fire" under the compass, with
its smudge on the strip. A Continue or a Load never plays the opening.

**Where it hooks in.** One call, in `GameServices.begin_new_game()`, the one place a new game
already began: `await CinematicPlayer.play_opening(opening)` before the opening quest is started.
Nothing in the boot, title or Naming code changed. The fade that waits for the country is waited
for (the opening borrows nothing until it lets go), and its black lifts onto the opening's own.

**The shots** (`core:cinematic/opening`, 94.5 s of pictures):

| # | shot | where | hour, weather | the Warden |
|---|---|---|---|---|
| 1 | the_name | black | — | "{name}." / "There. Said out loud, and heard. That is how it holds." |
| 2 | the_mere | Tollmere from 700→520 m south over the Mere; the title card inks in | 7.3→7.5, clear | "Nobody in Wickmere agrees what the world is." |
| 3 | the_spire | the Sayers' Spire from low over the Mere, east of it, against the sky | 7.6, clear | a bell, struck once / by the hour |
| 4 | the_nave | the Drowned Nave across the marsh | 8.0, mist | "The marsh says it is a tide going out." |
| 5 | the_hand | above the Fallen Hand's palm, orbiting to face its fingers | 10.0, clear_cold | "The clans say something vast is breathing in." |
| 6 | merrowby | Merrowby under the Cracked Toll | 7.6, clear | a candle wants tending |
| 7 | the_roll | the downs and Wardens' Rest | 8.6, overcast | what it is doing / the Roll |
| 8 | the_toll | the Cracked Toll on its mound | 18.2, thin_sun | began to hum / Gosford |
| 9 | the_choir | inside the Sunken Choir's ring | 16.8, ashfall | Cinderlea / the Hush |
| 10 | the_stair | from 330 m out over the Hush, up the cliff and the stair to the camp, onto the shoulder | 7.2, thin_sun | nineteen years / nobody up it / you did / keep up |

**How it is built.** It is data plus a small player. `CinematicDef` validates a definition as
content (`Schemas` calls it), and `CinematicPath` resolves each camera key. Every key is a
bearing, a distance and a height *relative to a place and to the ground under it*, so the cameras
move with the land when it is rebuilt. `CinematicPlayer` plays it in the running world:
letterbox, eased Hermite moves, cross-dissolves from a frozen last frame, a title card in the UI
theme, subtitles that follow the subtitles and UI-scale settings, and a cue on the music director.
It borrows the camera, the streamer's target, the terrain's clipmap camera, the clock, the sky,
two buses, the HUD, the toasts and the body's input and physics. It gives each back through one
`_restore()`, watched or skipped. The tree is never paused. The streamer follows the cinematic
camera and loads the next shot's start and what it looks at. If a shot's cells are not in by its
cut, the last frame holds; after half a second the picture goes to black with "The Warden waits
for you to catch her up.", and the music waits too, for four seconds at most, and then the shot
is shown with what has come. The pictures keep the wall clock, as the music does: a long frame
after quick ones is a hitch and counts a second at most, a long frame after long ones counts in
full, and no frame moves a shot past half its length. Six minutes after the first shot the whole
opening hands over as a held key would. No slot is written while it plays, and a loaded game
never plays it. Every shot logs its frames and its wall time, and a hold of two seconds logs
which cells it is missing and where each has got to in the streamer.

**Skipping, the setting, the replay.** Any key or button shows *Hold to skip* with a brass fill.
Holding it for a second, timed from the key going down, fades to black and arrives at the
hand-over's exact state: the world handed to the body (`World.follow`), the HUD, the Warden
stood up at her fire, the objective written. *Play the opening on a new game* (Settings,
gameplay) turns it off. The pause menu's *How it began* plays it again, then puts the player, the
clock, the sky and the rest back.

**The music.** `core:music/opening` is composed by `tools/audio/compose.py` from the shot list
itself, so its sections change where the pictures cut. A bell and a drone in E phrygian over the
black; the Toll leitmotif under the title; each place in its own mode; the Hush thinning to a hum
a half-step wrong. On "Then, this morning, you did" it turns to E lydian with the Toll, and it is
silent by the end of the hand-over. It is a one-shot at -18 LUFS: 108 s, peak -3.2 dB. Its
loudness curve was checked against the cuts; nobody has listened to it.

### The start (`core:poi/stair_head`)

* **Where.** A Wardens' camp on the rim of the Cinderlea cliff, 190 m north of the Stair's pad,
  on a knoll that falls to the Hush behind and opens north over the heath. The POI's position is
  the spot you stand on. It is dry, walkable ground by the spawn's own test, so main's
  `PlayerSpawn.dry_ground_near` leaves it where it is: the search is a safety net under the
  choice, not the choice. The camp's builder (`_camp_stair_head`) lays everything out ahead of you,
  towards where its `path` goes:
  * the Warden's fire, with her place beside it turned to you (`NpcSpot`);
  * two tents, and a cart with its load;
  * two grey-green Warden colours with a bell each, either side of the way out;
  * a signpost, and lamps.

  Behind you are the Oroth piers at the head of the stair and her Hearthstone, and **the stair
  itself**: straight down the 77 m face to the Hush and on into the water, where the mist takes
  it. Every step follows the ground and is filled down into the face, with a parapet either side
  and a sloped collider per flight.
* **Who.** Wren Tallow, held at her fire by a new `holds` entry in her npc def
  (`Schedules.held_entry`: the dialogue's condition vocabulary, checked before the timetable).
  The hold runs from the moment a new game is named (the `new_game` flag, which now stays up
  through the opening) until the walk to the Choir is done. The registry looks again whenever a
  quest moves. She speaks first, with her own greeting for the waking ("There you are. Eyes
  working? Good. Don't look behind you yet. Come to the fire."), and her dialogue now gives you
  the road.
* **What to do.** The Naming is now `wake` (speak to the Warden, marker at the camp) →
  `the_choir` (walk the waystones to the Sunken Choir) → `ash_wights` (three, among the Choir's
  feet, where the waystones end; they were set on the Stair's pad in the sea, which nobody can
  reach) → `hearthstone` → `the_cart`. Standing at the start completes nothing. Wren's dialogue
  names the Naming's stages by id, so a stage can be added without renumbering her. The HUD
  writes each new objective under the compass for seven seconds.
* **The way.** Waystones every 22 m, a lamp on every third, lay the POI's `path` 413 m to the
  Choir: about a minute and a half on foot, past the Cantor's Seat. `test_the_start` holds every
  straight leg against the built ground (walkable at 4 m samples, dry). It holds each leg against
  every enemy the build stood on the heath (none within 50 m), and against every solid scene the
  build stood near it (the way goes round each, by its model's footprint and a body's width).
  The enemy check failed once already: the world was rebuilt under the first route, and a
  bell-bearer came to stand 32 m from it. So the way was re-routed, and the test names the leg
  when it happens again. The solid check is new this round (below).
* **Before the land knows it.** A POI the content has and the built world does not is dressed
  where its def says, on the ground as it stands (`WorldPois.unbuilt_entries`), until the next
  build flattens it a pad.
* **The Stair's own landing** (`core:poi/hushline_stair`). Once the sea was drawn, the built
  world's pad showed for what it is: 0.2 m above a sea 19 to 25 m deep. The Oroth stair went down
  into clear water, and the POI's four ash-wights stood at the waterline. Its builder now seats a
  landing there on a rough stone shelf, with Oroth paving 1.6 m clear of the water. The
  Hearthstone, the brazier, the piers and the wights (a raised `the_landing` marker the encounter
  now names) stand on it. The stair goes out from it away from the cliff, and the mist lies on the
  water from where the stair goes under to past its last step. The mist was on the sea bed before,
  twenty metres down, and so was the cliff stair's. Nobody can walk out to it yet: it is a hundred
  metres of sea from the cliff's foot. The builder only raises the shelf where a pad sits within
  1.6 m of the water beside it. A pad the land lifts clear keeps its ground, and the stair starts
  where that ground first drops a metre.
* **When the atlas world lands.** The land agent's atlas puts the camp on the rim at about
  (10, 3670) and the Stair on a 4 m shelf at the cliff's foot, with a switchback stair road down
  the bank between them. Everything here keys off the built world's pads through
  `World.place_position`, so the spawn, the camp and the cinematic's keys go with them. The
  waystones follow the built road the Stair Head's `path.built_road` names
  (`core:road/stair_head_sunken_choir`) when the build has it, and its `via` otherwise; a way
  that does not start at the camp gets no stones. The camp's own stair down the face stands
  aside when the build has `core:road/stair_head_hushline_stair`. `PlayerSpawn` does not read
  the manifest's new `start`: it would be a second word for where the opening's place is.

### Tests

* `test_cinematic_def`: the validator, the shipped definition, and the cue.
* `test_cinematic_path`: the arithmetic.
* `test_cinematic_paths_clear`: every shot is sampled 160 times against the full-resolution
  ground, the water and the scatter bounds. No camera comes within 3 m of the ground or inside
  a tree, and none looks off the world's edge within 700 m. The hand-over's last metres may come
  down to the gameplay camera's own height.
* `test_cinematic_player`:
  * a New Game plays the opening and a Continue does not;
  * control comes back at the Stair Head with the Warden's first words;
  * the Warden stands 3 to 12 m in front;
  * skipping at the black, during a hold for the country, at Merrowby and on the Stair ends in
    exactly the state watching it through does (position, facing, streamer, region reporting,
    nothing paused, buses, clock, weather, HUD, input, body physics, terrain camera);
  * a fade left down by a menu is lifted under the opening's black;
  * a replay puts everything back;
  * with the streamer throttled to nothing, every shot is still shown once its own wait runs
    out, and with the waits made endless the overall cap hands over; both end exactly where
    watching it through does;
  * with every frame stalled to a third of a second, a shot's clock keeps the wall clock;
  * no slot is written while it plays, and a slot that still carries the `new_game` flag is
    loaded without the opening, with the story going on;
  * a new game skipped while its country is late is handed over whole: the streaming and
    Terrain3D's camera on the body, the gameplay camera drawing, the HUD up, the Naming begun,
    the body on dry ground, the Warden near and in view, the objective's smudge on the strip
    and its line written;
  * a tap inside a long frame never skips, and a key held across one does;
  * a prompt let go before its fade began stays gone.
* `test_the_start`, thirteen tests: where the start is, that it is dry and level, what stands
  there, that the spawn is clear, the way (walkable, clear of the heath's enemies, round what
  stands solid), the Warden's hold, the story's first two asks, the first words and the
  objective line. Two more hold the first fight's ground at the Choir dry and walkable from the
  last waystone, and the Hushline's landing clear of the water, with every wight's feet on it
  and the mist lying on the water. `test_world_spawn` now expects the body at the Stair Head
  itself.
* `test_kill_places`: a colossus built the way the streamer builds one (a hollow trimesh), with
  all three of the Naming's ash-wights stood outside it.
* The flow probe's New Game run watches the opening: a frame per shot as it plays, a hold to skip
  in the last shot, the mouse given back. Then, on the first frame of control, it checks five
  things: the body is on the screen, standing on dry ground by the spawn's own test; the Warden
  is within 14 m and in view; the objective's smudge is on the strip; and the objective line is
  written. The Load and Continue runs check that nothing plays.

### Found, and fixed

* **The third-shot stall was slow motion.** Three New Game flows sat ten minutes in the opening
  with two of its ten shots shown. That was the no-void stream's two runs and the coordinator's
  on main, all at a load of 20 to 25 on this machine's four cores. The last frame of each shows
  the Spire *playing*, its first line up: nothing was being waited for. Godot slows the whole
  game rather than step physics more than eight times a frame, so a frame of five or six seconds
  counts as an eighth of one. The opening was timed on that. A log line per shot, taken at the
  same load:
  * `the_name`: six seconds of pictures took 37 s on the wall in six frames, and the engine
    counted 0.8 s of them.
  * Timed on the engine, the name and the Mere alone come to about 135 frames. That is the ten
    minutes, and the Spire was where they ran out.
  * Each hold also sat four frames to settle, 25 to 30 s a shot there.

  Now the pictures keep the wall clock:
  * A long frame after quick ones is a hitch and counts a second at most.
  * A long frame after long ones counts in full.
  * No frame moves a shot past half its length, so every shot is drawn once past its middle.

  The waits are bounded:
  * A hold is four seconds at most, and its settling frames are skipped for the black and once
    that wait is spent.
  * Six minutes after the first shot the opening hands over as a skip would.

  At the same load, a shot now takes two or three frames: 10 to 40 s on the wall, depending on
  how much of the country is in view.
* **The Warden was not at her fire on the first frame of control.** It happened twice over.
  First, a point of interest's people wait for its dressing (`NpcStreamer._place_ready`). The
  camp's dressing went with its cell when the camera flew off, and the NPC streamer only looks
  round every three quarters of a second of game time, which on that machine is half a minute. So
  she was never stood up while the opening played.

  Second, a trace of the registry showed that `QuestLog.start` announces a quest a moment before
  its first stage. With `new_game` just down and the stage still at -1, her hold on the Naming's
  first stage let go for that moment. The registry sent her home and took her body away, then put
  her back at her fire without standing her up again.

  The fixes:
  * The opening stands the camp's people up as the last shot is shown and at the hand-over.
  * The new-game hook asks the NPC streamer to look round once the story has started.
  * The hand-over gives the world to the body through `World.follow`: the streaming, Terrain3D's
    camera, and the fly camera let go.
  * The hand-over test checks the first frame, as the probe does.
* **The 0.029 frame the probe failed on was bare black.** When the country's hold ended, the
  curtain was raised over the menus' fade, and it covered the caption card at once. On a slow
  machine the player then looked at an empty black screen until the Warden's first words. The
  curtain now waits under the fade and its caption until both have gone, so the card fades out
  over black. The check was right and the frame was wrong. The run after the fix read 0.129, then
  0.103, 0.076, 0.053, 0.033 as the card faded.
* **A tap could skip.** The hold was summed from frame deltas, so one five-second frame made any
  key press a skip. It is timed from the key going down now, on the wall clock. A prompt asked
  for and let go before its fade began no longer goes on fading in over the skip's black.
* **A slot written mid-opening played the opening again when loaded.** The probe saved while the
  opening held the game, with `new_game` still up, and the `--load` run played it again. Such a
  slot also kept the shot's borrowed hour and sky. Now:
  * No slot is written while a cinematic holds the game (`SaveSystem.hold_saves`, released after
    `finished` has been heard, when the flag is down).
  * A world loaded from a slot never plays the opening, whatever its flags say
    (`PlayerSpawn.loaded_slot`).
  * The quicksave key and the save menu say when a save was refused, and why. The menu used to say
    "Written down" either way.
* **The probe missed the black shot.** It watched the opening only after its samples of the world
  standing up and the fade's lift. On a slow machine those outlast the black shot. It now
  photographs the opening from a watcher started at the press. It reads each frame just before
  the frame is drawn, so the picture it keeps is the moment it read. It presses the skip key at
  the start of a frame, as a hand's key arrives.
* **One test's save slot was every checkout's.** All the worktrees on this machine share one
  `user://saves`. Another suite running `test_cinematic_player` deleted the slot between this
  one's save and its Continue. The slot is named for the process now. `test_player_body` and
  `test_save` still use fixed names, and so does the flow's `flow` slot.
* **The Naming's three ash-wights stood on the Stair's pad**, a mound in the sea that nobody can
  reach. They are asked for among the Choir's feet, where the waystones end, and the objective
  says so. A test holds every point QuestFoes can stand them on as dry ground at least a metre
  above water, and holds the walk from the last waystone to each of them.
* **The waystones walked through a colossus.** Framing a photograph of the first fight found the
  way's last three legs going through the robe of the colossus nearest the Choir. The Choir's
  colossi are twenty-seven metres across at the foot, and two of the stones stood inside the
  stone. The legs had been held against the ground and the heath's enemies, not against what
  stands on the ground. The way now goes round the colossus on its west side, over ground the
  tests accept, and ends 22 m from the Choir, in the ring where the ash-wights stand; it is
  413 m, not 426 m. A new test holds every leg clear of every solid scene the build stood near
  it, by the model's footprint and a body's width.
* **Two of the Naming's three ash-wights were stood inside the Choir's colossus.** The capture
  that staged the first fight logged where QuestFoes stood them. Two were 9 and 11 m from the
  colossus's middle, inside its robe, where nobody could reach them and the Naming could not be
  finished. A landmark's collision is its mesh's surface (`WorldStreamer._add_collision` builds a
  trimesh), so a body inside it touches nothing, and QuestFoes' shape query called the spot
  clear. QuestFoes now also calls a spot blocked when anything solid stands straight over it: a
  roof, or the inside of a hull. That holds for the Choir's other two fights as well, Vigil's six
  ash-wights and At the Gate's two choristers, which had the same ring round the same colossus.
  `test_kill_places` builds a colossus as the streamer builds one and holds all three wights
  outside it.

### The frames, and the runs

Everything was run one Godot at a time on the merged head, with main at 6838f23b.

* `./run.sh flow` on a369e637, the opening's last change, under load: **passes**. New Game ran 99
  checks, Load 32 and Continue 35; none failed and no errors were logged. It started at a load of
  19.3 on four cores with 5.0 GB available (5,097 MB). The New Game run went on at 21 to 24 with
  2.5 to 5 GB available, beside other streams' builds and runs.
  * The opening played after the Naming with no HUD over it, and the probe photographed all ten
    shots as they played. It ran 302 s from its first frame to the skip; its slowest frame took
    20 s.
  * The last frame before the world is the caption over black (luma 0.129), not a dead screen.
    The samples after it read 0.104, 0.075, 0.051, 0.033 and 0.025, as the card faded out over the
    opening's black and its first shot.
  * A key pressed in the last shot showed *Hold to skip*; held, it was taken as a skip, and the
    mouse came back.
  * On the first frame of control:
    * the body stood on dry ground, 77.9 m above the nearest water;
    * the Warden stood 7.1 m in front of it;
    * the objective's smudge was on the strip, and its line was written: "The Naming: Speak to the
      Warden at her fire";
    * her first words were "There you are. Eyes working? Good. Don't look behind you yet. Come to
      the fire."
  * The Load and Continue runs played nothing.
* `./run.sh flow` again, on the final tree (a92cec29): **passes**, with the same counts: New Game
  99, Load 32, Continue 35, none failed, no errors logged. It started at a load of 4.8 with 13.8 GB
  available. Other streams' runs came back during it, and took the load to 24 and the available
  memory down to 3.6 GB.
  * All ten shots were photographed as they played, 271 s from the opening's first frame to the
    skip.
  * The first frame of control has the same five things:
    * dry ground 77.9 m above the water;
    * the Warden 7.1 m in front;
    * the smudge on the strip;
    * the objective line;
    * her first words.
  * The caption and the samples after it read 0.129, then 0.100, 0.075, 0.051, 0.033 and 0.025.
  * Every one of its 41 frames was looked at, and they match the run under load.
* `./run.sh test` on the final tree: 1,594 tests, 0 failed, 0 content problems, 0 script errors,
  no dead lambda captures. The 4 logged errors are the ones their tests provoke. The run before it
  failed once, on its own new test. The first QuestFoes fix looked overhead only down to 1.9 m,
  and the test caught a wight 13.3 m out, just inside the robe's flared foot. The look goes down
  to 0.3 m now.
* `./run.sh journey` on the final tree: 16 of 16 steps.

Every frame of the run under load was looked at. That is the title, the Naming, the caption, the
five samples, the ten shots, the prompt, the first moment of control, the world standing, the
portrait, and the Load and Continue runs' frames. The ten shots:
* the black with the Warden's line;
* Tollmere on its island across the Mere, the causeway coming in;
* the Spire standing clear of the island's hill against a morning sky;
* the Drowned Nave leaning out of the marsh;
* the Fallen Hand's fingers from above its palm;
* Merrowby under the Toll's green mound;
* the downs and Wardens' Rest under cloud;
* the Toll at dusk;
* the colossi of the Choir in the ash;
* the camp at the top of the stair.

The hold-to-skip frame has the prompt and its bar at the bottom right. The first frame of
control has the Warden by the fire ahead of the body, the tents, the cart and the colours, the
Choir's colossi on the skyline, and the objective under the compass.

The captures of the landing and the first fight were taken with `capture_runner` from a person's
height. The landing's frames show:
* its paving clear of the water, the POI's four ash-wights standing on it, and the grey mist lying
  on the water where the stair goes under;
* the landing from its stair head;
* the landing from the camp, a hundred metres of sea off the cliff's foot.

The runner can now stage a fight as it is met. A plan's `quests` puts a quest at a stage. A shot's
`body` stands the player's body, and `face_foes` turns it to the nearest foe. The first fight's
frames were taken with the Naming at `ash_wights`, which had QuestFoes stand its three wights
round the Choir. They show:
* the way going round the colossus at the Choir's foot;
* the body where the stage begins, 40 m out, turned to the nearest wight 26 m off (the body hides
  it, because the camera is straight behind);
* the body at the last stone, with an ash-wight at its shoulder on the ash beside the colossus's
  plinth.

The wights stood at 15.6, 17.7 and 19.8 m from the colossus's middle, all outside its 13.5 m robe.
In the run before the QuestFoes fix, two of them stood inside it.

### Found, and not fixed

* The Hushline Stair's landing cannot be walked to: a hundred metres of sea lie between the foot
  of the cliff stair and the landing. Its four wights stand there for show until the land lifts a
  landing at the cliff's foot. The atlas world does that (below).
* The Stair Head has no pad of its own until the next world build. There are no animals in the
  camp, because nothing in the asset library is one.
* The Spire's shot hides most of Tollmere behind the island's hill; the Spire itself stands clear
  against the sky, which is what the line is about. The Mere's town is small in its frame.
* On a machine drawing a frame every few seconds a subtitle inks in over several frames, because
  its fade runs in game time, and a line can fall between two frames. The pictures and the music
  keep time; the words may not.
* The NPC streamer looks round every three quarters of a second of game time, and so does much
  else that is timed on the engine's delta. On a slow machine that is half a minute. The opening
  works round it for its own greeter; nothing else does.
* `QuestLog.start` emits `quest_started` with the stage at -1, before the first stage is entered.
  Any npc hold keyed to a quest's first stage lets go for that moment, and the registry despawns
  the npc. When the hold takes again at the first stage, the registry puts the npc back in the
  state without standing them up; they reappear at the NPC streamer's next look round. The
  new-game hook covers the Warden. Any other story that holds somebody on its first stage has the
  same gap. The fix belongs in the registry (resync a loaded cell's unspawned npcs on simulate)
  or in QuestLog (announce after the first stage), not here.
* The flow's `flow` slot, `test_player_body`'s and `test_save`'s are still fixed names in the one
  `user://saves` every checkout on the machine shares. Two runs at once can load each other's.
* Stars come out over the Toll at dusk while the sky is still light.
* A vertical dotted line stands in the sky in several shots, far off: something in the built
  world, not the camera.
* The title menu's music and the Naming's never play here.
* A place where QuestFoes finds no clear spot in its ring still gets its fight "at the middle".
  At a landmark, the middle is inside it. The Choir's ring has room now, so the Naming never gets
  there, but nothing else stops it.
* The way's check against solid scenes reads each model's bounds, not its collision. For a model
  whose collision is much narrower than its bounds, the way is held further off than it need be.
* Forward+ on this machine's software Vulkan crashed at world load in every earlier attempt to
  photograph the start. It has not been tried again since the audio guard landed; the mixer crash
  that guard stops is one a Forward+ world load met. So every frame here is the Compatibility
  renderer's, and the start, the landing's mist and the opening have not been seen as a player on
  Forward+ sees them.

### What a human should check

* The music, by ear: that the cuts land on its sections, that the E-lydian turn lands on "Then,
  this morning, you did", and that it is gone by the end of the hand-over.
* The motion in real time on a real GPU: the eased moves, the dissolves and the letterbox, which
  have only been judged from frames, and whether any shot hitches when cells arrive mid-move.
* The opening on Forward+: the Nave's mist, the Toll's dusk, the Choir's ash, and the grey mist
  lying on the Hush where the Stair goes under.
* Holding a key or a pad button to skip, and that a tap does not.
* The walk from the camp along the waystones to the Choir, on foot (a minute and a half, past the
  Cantor's Seat), round the west side of the colossus at its end, and whether its three
  ash-wights are a fair first fight. They come at you round the colossus's foot.

### Next, for the atlas world

* Steps and parapets on the land's stair road down the bank (`core:road/stair_head_hushline_stair`),
  on its `road_profiles.json` `elevation_m`, when that world lands; the camp's own stair already
  stands aside for it. The land agent will send the stair's steepest grade and end heights.
* Photograph the start, the stair and the landing on the atlas terrain, and look at the
  cinematic's last shot, which flies up whichever stair is there.

## Feet on the ground: stops, turns, the four ways, and the pad

The user called the movement clunky. The last round ended with its own list of what was still
wrong, and that list was the brief for this one, in order: the stop that slid the feet together,
the diagonal strafes, a real turn on the spot, the backpedal and side-steps on the stride model,
and the pad's shared buttons. Measuring them properly turned up two faults under all of them.
Every figure here is taken at the heel and the ball of each foot, the two points a foot bears on
and turns about (`tests/unit/foot_contact.gd`). A foot that rolls about either point keeps that
point still, so a point moves while it is down only when the foot slides.

**Every clip held its first frame twice.** The forge baked keys from frame 1, and the glTF
exporter wrote them from 1/30 s. Godot's importer sampled every clip from 0 and held the first
pose. So every loop stood still for one frame each cycle, with the left foot just down, and that
foot was carried along the ground at the body's speed. The keys start at frame 0 now. A loop is
a whole number of frames (the walk was 28.8), and a one-shot is sampled on to its end frame.

**Every foot scuffed as it lifted and landed.** An eased swing starts and stops still in the
body's frame, but the body's frame moves at the body's speed. Now a swing leaves the ground and
meets it at the ground's own pace, eased in and out in the world. That carries the foot back as
it rises and out past its landing before it comes down. `swing_lag` and `swing_reach` had faked
this heel recovery and reach by hand. In the forge's own sampling a stride slid 5.3, 6.0 and
4.1 cm at a walk, a jog and a sprint; now 0.4. The sprint keeps only 15% of the ease, because the
full ease carried its foot too far out in front and pulled the hips 6.5 cm down.

**The stop.** A stop froze the stride wherever it had got to, one foot ahead and one behind, and
cross-faded into the idle, where the feet stand side by side. Both feet slid along the ground
into the idle: 58.6 cm between them at the end of a stop from a jog. On the heel and ball that
was 114, 110 and 43 cm from a walk, a jog and a sprint. Now `FootPlanter`
(`actors/shared/foot_planter.gd`) holds each foot where it stands in the world once the body is
under 5 cm/s. It does this with a two-bone solve of the leg against the pose the clips set, and
lowers the hips as far as the wider stance needs. Then it steps the feet into the idle's stance
one at a time, 0.24 s a step and 6 cm up, lifting and setting down straight. A settled body's
feet stay put and step again only when it turns or drifts away from them, so a villager turning
to face someone shuffles round on its feet. The planter lets go when the body moves off, leaves
the ground, plays a one-shot or is carried off (a teleport, a snap turn).

That took out the settle and showed the slide before it. As the body slowed, the legs blended
down through the slower gaits, and a run's feet and a walk's are down for different shares of a
stride. While the body slowed, the heel and ball slid 0.8 cm in a stop from a walk, 39.9 from a
jog and 34.6 from a sprint (the mean of eight stops begun at eight points of the stride). Braking
harder than 6 m/s², the legs now keep the gait they were in, played at the ground's pace however
slow, until the feet are planted.

The film then found what none of that measured. A stop from a sprint slowed its stride with the
body and froze it in the stride's flight. The body stood 0.2 s in the air with both feet up. Then
the back foot, held 0.9 m from its place in the stance, tripped the planter's 0.7 m "carried off"
test and snapped there, 60 cm along the ground in one frame. The stop test measured feet sliding on the ground, and
neither foot was on it. It now also measures how long a standing body has both feet off the
ground (0.22 s from a jog and 0.36 from a sprint, over the eight stops) and the most a foot moves
in a tick (57 and 75 cm). Braking in the air now plays the flight at its own pace, so the body
lands on a foot and brakes on it, and a body that stands in the air finishes the flight first. A
foot counts as down when its heel or its ball is, not its ankle, so a foot up on its ball stands.
A foot caught in the air steps down at once, and a body counts as carried off only when it moves
25 cm in a frame.

Now, from a walk, a jog and a sprint, the heel and ball slide 0.1, 0.6 and 2.0 cm while the body
moves (the mean of eight stops), and 0.0 settling. The sprint's was 1.3 before the flight change:
the flight's pace is read off the last frame, and can run a frame into the landing. Once the body
stands, both feet are off the ground for 0.00 s over the eight stops, and 0.06 s at the most over
thirty from each gait, while a flight lands. No foot moves faster than a step, 7.0 cm in a 120th
of a second. A stop takes two steps and is settled within 0.50 s of standing, with the feet
ending within 0.1 cm of the idle's stance. The hips come down 5.2, 8.6 and 6.3 cm for the split
stance the braking ends in, and rise again as the feet step in.

**The four ways.** Locked on, a diagonal blended the side-step with the forward or backward
stride by the share of the pace that went sideways. Two strides blended that way put the planted
foot on a line between their two footfalls. It moved at 28% of the ground speed on the diagonal
ahead (3.64 m/s) and 23% backing off diagonally (2.18 m/s); on the heel and ball, 79 and 49 cm a
stride. Now the legs play one of four ways, whichever is nearest where the body goes: ahead and
back each take the 67.5° either side of them, and the side-steps take the rest. The hips are
turned the rest of the way over 0.08 s, and the chest is turned back 80% of that to face the foe
(`HumanoidModel._turn_the_hips`). A way is left only 10° past its edge, and the legs hand over
across 0.15 s. Now 2% and 5%, 3.7 and 7.7 cm a stride. The diagonal ahead at 3.64 m/s had also
fallen between the brisk walk and the jog, blended half and half, and that still slid 11.3 cm.
A slow run, Trot (3.6 m/s), now stands between them and takes it.

**Turning on the spot.** The last round's turn on the spot was a side-step. It told the legs to
walk sideways at the pace the feet go round the middle, and it read as a shuffle. There are four
turn clips now. Turn_L90 and Turn_R90 are a quarter turn in two steps. Turn_L180 and Turn_R180
are an about-face: a long pivot step, then the other foot round after it. The feet pivot on
their balls, the head leads by 12° (18° in the about-face) and the shoulders follow. The clips
are made in the turning body's frame and set in the idle's stance. They play at the rate the
body turns (a cycle for every `turn` degrees in the sidecar), the way the gaits play at the
ground's pace.

A standing body (under 0.3 m/s) that turns faster than 60°/s plays the quarter turn, and a turn
begun faster than 200°/s plays the about-face. A turn picks up as far round as the body has come
and blends in over 0.03 s with the planted feet held. It ends when the body has turned slower
than 30°/s for 0.08 s, and the feet are then planted and stepped into the stance as after a
stop. Slower than 60°/s, the planted feet step round by themselves. On the heel and ball, a
quarter turn over 0.7 s slides 1.1 cm in all and an about-face over 0.35 s 3.9 cm. With the
player's view swung 147° in half a second while blocking, the body plays Turn_L180 and the legs
are told 0.00 m/s sideways. The model reads the body's own turning, so a villager or a foe
turning on the spot steps the same way.

The first cut left the body on tiptoe after every turn, its heels 3.0 cm off the ground until it
next moved. The turns pivot on the balls with the heels 8° up, and the planter held the feet as
the turn left them; 8° of tilt is under the 0.15 rad of turn that makes a foot step. A held foot
that is in its place now settles to the clips' tilt about the lower of its heel and ball while
neither foot steps, and a foot steps for its heading alone. The heels are down after every turn
now (0.0 cm), for 0.2 cm more slide than before.

**The backpedal and the side-steps.** Both were still the first stride model's. They are made
again on the new model at the paces a locked-on body goes. Walk_Back is 1.8 m/s and lands toe
first. The side-steps are 3.0 m/s, a shuffle with a little flight and the swing foot crossing in
front; they had been made at 1.9 m/s and played at 1.58 times. On the clips this round began
with, the heel and ball slid 23.4 cm a stride side-stepping and 7.2 backpedalling; now 4.5 and
1.8. The forward gaits went from 8.6, 15.9 and 2.7 cm a stride at a walk, a jog and a sprint to
3.2, 2.5 and 3.1, and sneaking is 3.0.

As the last round measured it, the planted foot's speed as a share of the ground's is: walk 2%,
brisk walk 2%, walk to jog 4% (was 6%), jog 3%, jog to sprint 3%, sprint 3%, sneak 1%, a villager
2%, the side-steps 0%, the backpedal 3% (4% locked on), and the diagonals 2% and 5%. The hips ride
4.3 cm below standing with 5.2 cm of bob at a walk, 5.2 with 4.4 at a jog and 5.1 with 5.7 at a
sprint. The jog sits 1.1 cm lower than last round, with its swing eased in the world.

**The pad.** Three buttons did two things at once. The right stick's click locked on and
switched to first person. D-pad up cast and used the first quick slot. And the map sat on Guide,
which Windows keeps for itself (it opens the Game Bar). Now the layout is the one the Souls games
use. B is Sprint: a tap rolls and a hold runs, judged the same as Shift. The left stick's click
sneaks, LB casts, and the right stick's click locks on and does nothing else. Back is the chart,
and Start is the pause page, which now also opens what you can say. A tap of B rolls on the tick
it is let go: 3.31 m, untouchable for 0.30 s. A still uses in play and confirms in a menu, the
one button with two actions, which are never listened for at once. A player whose saved bindings
are still the old defaults is moved onto the new ones, and a binding they changed is kept
(`Settings.RETIRED_DEFAULTS`). The hint strip and the controls page say "tap B".
`test_pad_layout` pins all of it.

**Filmed.** In Forward+, in the motion studio, from real key and mouse events at a fixed 60 fps
(`tools/capture/plans/turns_and_ways.json` and `stop_planted.json`), on the final code. With the
guard up and the view swung 90° over 0.7 s, the body lifts the left foot round and sets it down
flat, then the right; both are down 0.7 s after the view began to move, the body faces the new
way at 0.9 s, and the heels settle at 1.1 s. Swung 180° in 0.35 s, it pivots on the right ball
while the left foot swings round, then on the left ball while the right comes after it. Both feet
are down 0.4 s after the view began, the body faces about at 0.6 s, and the heels settle at 0.8 s.
Frames of the feet just after each turn, from before and after the heel fix, show the heels
raised and then flat. Locked on, the diagonal ahead reads as a run the way the body goes, the
diagonal back as a walk backwards, and the side-step as a wide shuffle with the swing foot
crossing in front. In the studio's log of the ankles, a planted foot stays within a centimetre
while it is down on the diagonal ahead and in the side-step, and drifts 2 cm backing off
diagonally.

A stop from a walk draws the front foot back under the body and brings the back foot up beside
it, settled 0.5 s after the body stood. From a jog, the body brakes over the planted front foot
for 0.25 s with the back foot up behind, and that foot comes down beside it 0.2 s after the body
stands. From a sprint, the stride lands its flight on the right foot, the body brakes over it for
0.15 s with the left up behind, and the left comes down beside it 0.2 s after the body stands;
the right then shuffles 15 cm to square the stance. No foot jumps; the first film of the sprint's stop had the left foot snap 60 cm along the ground
in one frame.

**Checks at the end.** On 5138a6b4 (this round's work merged with the main branch at 6838f23b,
the flight fix in): `./run.sh test` 1595 tests, 0 failed, 0 content problems, 0 script errors, 0
dead lambda captures, and 4 logged errors, all ones the tests expect. The first full run logged
one more, in `test_cinematic_player` (below); run alone it passed, and the next full run passed.
`./run.sh journey` 16 of 16, 0 logged errors (7e88fa44). The forge's rig tests: 29 pass.
`./run.sh flow` has not passed on this branch. The first run (7e88fa44, a load average of 23 on
four cores) reached the world, the body standing 22.3 s after the press. But each of the
opening's shots took minutes, and the probe's 600 s cap ran out with 2 of 10 photographed, so
the ten checks of the hand-over after it failed. After the main branch's opening work was merged
(6985d356: the pictures keep the wall clock), a second run reached the opening's fifth shot at a
load of 36 to 45 and was killed with SIGKILL before a verdict. The heel fix (4751c103) and that
merge have had the locomotion, planter and player tests, not a full suite.

### Found, and not fixed

* **The lantern and the first-person view have no pad button.** Back could take the lantern as
  a hold if a pad player needs it without a menu.
* **With "A tap of Sprint rolls" off, or Sprint a toggle, a pad has no roll** until Dodge is
  given a button in the controls settings.
* **Footstep sounds do not keep the legs' time.** `Footfalls` sounds a step every 0.68, 0.47 and
  0.31 s at a walk, a jog and a sprint. The clips put a foot down every 0.48, 0.35 and 0.30 s.
  The clips carry `footstep_l` and `footstep_r` events, which would put the sound on the foot.
* **The keys are 30 a second.** Between keys the engine turns every joint along the shortest
  way, which carries a planted foot 2 to 5 cm a stride in the game against 0.4 in the forge's own
  sampling. Baking at 60 frames a second would halve it and double the clips.
* **Braking plays the last stride in slow motion.** The stride keeps its length and slows its
  cadence with the body, where a runner braking shortens the stride at the same cadence. On film
  the trailing foot is still up behind when the body stands, and comes down 0.2 s later. A stop
  clip for each foot is the next thing.
* **The fastest turns outrun the turn clips.** A turn plays at up to 2.5 times the clip's own
  pace: 321°/s for the quarter turn, 750°/s for the about-face. The player's standing turn tops
  out at 900°/s, so the feet turn with the body for the start of the fastest flick.
* **The diagonal back slides the most of the four ways**, 7.7 cm a stride on the heel and ball.
* **A stop brings the hips down 5 to 9 cm** while the feet are split, and back up as they step
  in. A split stance does that, but it shows.
* **Every worktree's tests write the same user directory.** Godot keeps `user://` by the
  project's name, so every checkout's runs share one `saves/` and one `settings.cfg`. The first
  full run on this branch logged an error nobody expected in `test_cinematic_player` ("could not
  load slot 'test_cinematic_opening': File not found") while two other worktrees ran their
  suites. Run alone, the test passed with no error, and so did the next full run. A test's slot
  can be deleted under it by another checkout's `after_each`. A user directory for each checkout
  (`application/config/use_custom_user_dir`) or slot names for each run would end it.

### What a pair of hands should check

The feel cannot be measured headless. Check whether a stop's two steps (up to 0.50 s after the
body stands) read as settling or as fidgeting, and whether braking from a sprint reads as slow
motion. Check whether 60°/s is the right place for a turn on the spot to start, and how the
about-face looks when the view is flicked round while blocking. Locked on, check whether the
hips turning toward a diagonal and the chest turning back reads as a body going that way. On a
real pad, check that a tap of B rolls and a hold runs, that L3 sneaks, that LB casts, and that
Back opens the chart on Windows. Start the game once with an old `settings.cfg` to see the pad's
bindings move onto the new layout.

## Graphics settings, and every tree drawn at the distance it stands

Two things were asked together because each needs the other. A Graphics section: four
presets and every knob that decides what the picture costs, each written to settings.cfg and
put into the engine the moment it moves. And the trees: Merrowby's street, the worst frame in
the game, was over the 1.5 M primitive budget, and thinning the trees was ruled out. The
level-of-detail setting is the one knob the trees answer to, and the presets are how the
trees' savings are measured.

### The Graphics tab

`core/graphics.gd` owns the `graphics` section: what every knob means, the four presets, the
line that says why a control is greyed out, and `apply()`, the one place a setting reaches the
engine. Twenty-nine controls: render scale and upscaler, MSAA, FXAA, TAA, texture filtering,
vsync, a frame-rate cap, sun shadows with their map size, cascade count, reach and softness,
ground-cover density, scatter view distance, the level-of-detail bias, distance haze, volumetric
fog, SSAO and its quality, SSIL, SDFGI, glow, water quality, the water's reflections and the
lamps lit at night, and the look's own colour grade, vignette and film grain (these last three
no preset touches, as it touches neither vsync nor the frame cap). **High is the game as it was
tuned**, number for number: every value in it is what `project.godot`, the atmosphere or the
streamer already used, so the default preset changes nothing about how the world looks except
what the tree levels save. Painted is everything on that the renderer can do; Low is what a
struggling machine should be offered first.

Everything applies live. The viewport takes scale, upscaler, MSAA, screen-space AA, TAA,
anisotropy and the mesh-LOD threshold; the rendering server the shadow atlas, soft-shadow
filter and SSAO/SSIL quality; the streamer its view range, density and bias; the water sheet
re-cuts itself. Every DirectionalLight3D and WorldEnvironment is adopted as it enters the tree
and remembers what its author gave it, so shadows turned off and on come back as the author
set them, a shadow distance is a share of the author's, the moon is never given shadows the
sun had, and a review stage that never had fog is not given fog by a setting that allows it.

On Compatibility the rows the renderer cannot do are greyed with the reason beside them
(FXAA, TAA, volumetric fog, SSIL, SDFGI, both FSRs). SSAO is greyed there too although 4.7's
Compatibility renderer has one: it is a pass over the finished picture that darkens sunlit
ground as much as shade, and the atmosphere lights the world without it on that renderer. A
preset read on the other renderer is still that preset. A file from before the section
existed has its `video` keys (vsync, render scale, MSAA, SSAO, glow, shadows) carried across
once. The unit tests, the capture tool and the perf probe never write the player's file.

`test_graphics_settings` (14) sets every knob through `Settings` and reads the engine back —
the viewport's scale and MSAA, the rendering server's atlas and filter, the real atmosphere's
sun and its shadow reach, the streamer's view range and LOD bias, the water's subdivisions —
data-driven over the control list, so a knob added without a way into the engine fails it.
`test_settings_graphics_screen` (6) opens the tab, presses every control on it through the
harness, presses each preset, checks the greyed rows and their reasons on Compatibility, and
closes the screen with Escape and with Done. `./run.sh perf` and `./run.sh shots` take
`--preset=low|medium|high|painted`, and both record the preset and every value in perf.json.

### Trees at the distance they stand

A MultiMesh chooses one level of detail for all its instances, from its bounding box, and a
cell's box holds the camera whenever the camera is in it or beside it. So every tree in the
ring around the eye was drawn whole: on Merrowby's street 1,937 trees in the near ring, 43 of
them within 80 m, and 650 thousand of the frame's 1.56 million primitives were trees and
their shadows (the attribution now counts primitives per owner as well as draws).

`world/scatter_lod.gd` draws each tree at the level its own distance asks for: the full mesh to
max(50 m, 4 × its height), the forge's LOD1 to max(70 m, 10 × its height), and the forge's
picture beyond, each line multiplied by the LOD bias (no picture ever nearer than 50 m and no
full mesh given up nearer than 20 m, whatever the bias). The full mesh's line was 30 m until the
far-trees plan's eye-level shot was set beside the same frame drawn without the ladder: the
hedgerow oak at 45 m, in its LOD1, was a sparser crown of bigger cards with a blade of bark
sticking out of it, where the whole oak was a tree. Shot again at 50 m, it is the whole oak, and
the frame costs 645 draws and 0.83 M against 572 and 0.99 M without the ladder. Each cell's
trees of one kind are one group, a MultiMesh per level, re-sorted when the eye has moved two
metres, within a 4 ms budget a frame. The canopy and the picture dissolve into each other across
a band a fifth of the distance wide (`lod_fade.gdshaderinc`, measured from the main camera so
the shadow passes agree), so a tree changing level neither pops nor is drawn twice; the bark
switches outright in the middle of the band, under the canopy, with a metre and a half of
hysteresis. The far ring is all pictures and never re-sorted. Opaque scatter heavy enough to be
worth it (a LOD0 of 1,500 triangles or more: Skerrow's drystone walls, the boulders and the
scree, 35 kinds) takes the same ladder by its bounding radius, without the dissolve.

**The picture** is new forge work, one `<tree>_impostor` manifest entry per tree, built by
`gen_impostors.py` after the trees: eight Cycles views into a 384 px palette atlas, and a 192 px
atlas of normals with the baked sky visibility in alpha; LOD2 becomes one upright quad that
`tree_impostor.gdshader` turns to face the camera (the sun, in the shadow pass, so a far
tree's shadow is its silhouette), choosing and dissolving between the two nearest views. It
is lit through its normals and shades its own middle by the sky it sees; it does not take
shadows, because the sun-facing caster crossing the camera-facing picture drew a dark wedge
through every far tree. All 35 trees in 802 s; the library went from 162.0 to 161.8 MB.

**The mid rung was the ladder's weakest step.** Blender's collapse decimator, taken to LOD1's
900 triangles, had bridged branches with sheets of bark: 25 m² on the black ash, 102 m² on the
third, standing metres clear of any branch — cardboard in plain view wherever a tree was at
LOD1. `lib/lod_repair.py` drops every LOD1 bark triangle standing more than half a metre off
the full tree's bark: 174 triangles in 19 of the 35 trees, none from the giant oaks' big
honest trunk faces. `gen_impostors` does it on every build; `repair_lod1.py` did it to the
trees already current.

**The picture is measured against the mesh, not tuned by eye.** `lod_review.tscn --calibrate`
stands each tree at its own switch distance, in its own region's light, three LOD1s beside
three pictures, and moves the picture's brightness and alpha cut until its *ink* — the summed
change it makes to the view — and its silhouette match the mesh's. A dissolve keeps the view
the same only if both levels change it by the same total, and that is what ink measures. Two
earlier measures were tried and refused on the pictures they produced: matching mean colours
painted the pictures pale, because a far mesh is leaves and twigs thinner than a pixel blended
with the sky between them; and giving the gain a hue as well turned a black ash's crown cream
and a willow pollard's bark lilac. The gain is one brightness for all three channels and the
picture keeps the colours Cycles gave it. 33 trees measured on Compatibility: luminance ink
within 3% for 28, 6.4% at worst (the tall willow, whose mesh at 176 m is mostly sky); the two
charred stumps, under a metre tall, were too small at 70 m to measure and keep the shader's
own. The same 33 were measured on Forward+ too (Mesa's software Vulkan: the review stage has
no terrain, so it runs where the world cannot): within 3% for 26 and 5% for 28, the worst the
first juniper at 12.7%, and the second and third black ash at the gain ceiling of 2, because
on Forward+ their LOD1 is sparse black clumps and a dense picture has to be twice as bright per
pixel to darken the view as little. Results, with what each was measured against, are in
`world/impostor_calibration.json` per renderer; a renderer a tree was not measured on takes
its Compatibility entry. What a brightness cannot fix is hue: the junipers' pictures are browner
than their LOD1, because Cycles drew the whole shrub, branches and all, and LOD1 is mostly
cards.

**What the far trees look like.** `tools/capture/plans/far_trees.json` is six frames full of
trees between forty metres and the horizon, shot at High with the ladder and again with
`--no-lod`. Two things came out of setting them side by side. The hedgerow oak at 45 m was the
case above, and the full mesh's line moved to 50 m. And the old far ring had been drawing
every tree past the near ring as **a cloud of leaf cards with no trunk**: `_mesh_of` skips a
rung under twelve triangles, the old eight-triangle crossed cards were under it, and the next
rung down by name was `<tree>_cards_LOD1` — the canopy alone. Briarwold's far hills in
`briarwold_approach` were floating leaves; they are trees now. (With the ladder and the full
mesh's line still at 30 m, the six frames cost 0.46–0.78 M primitives against 0.68–1.17 M
without it; the draw calls went both ways, from 111 fewer to 104 more, because a cell's trees
can now stand at three levels at once.)

### What it costs, measured

The six `*_street` shots of `tools/capture/plans/streets.json`, each column one run of
`./run.sh shots` with `--preset=`, draw calls / primitives. The last column is the same build
with `--no-lod` — the trees drawn the old way — which is this pass's *before*: it reads 1470
and 1.55 M at Merrowby, the figure this branch started from (the painted-look branch measured
1521 and 1.61 M on main, with its lights in).

| shot | Low | Medium | **High** (default) | Painted | before: High, no tree levels |
|---|---|---|---|---|---|
| hearthvale_street (Merrowby) | 793 / 0.49 M | 1273 / 0.80 M | **1384 / 0.94 M** | 1606 / 1.25 M | 1470 / 1.55 M |
| brightwater_street | 305 / 0.30 M | 419 / 0.43 M | **449 / 0.46 M** | 495 / 0.52 M | 464 / 0.59 M |
| sedgemire_street | 417 / 0.29 M | 681 / 0.51 M | **708 / 0.57 M** | 826 / 0.72 M | 709 / 0.89 M |
| briarwold_street | 407 / 0.34 M | 625 / 0.56 M | **692 / 0.63 M** | 854 / 0.89 M | 600 / 0.85 M |
| skerrow_street | 370 / 0.32 M | 558 / 0.50 M | **593 / 0.55 M** | 704 / 0.68 M | 630 / 0.77 M |
| cinderlea_street | 312 / 0.23 M | 467 / 0.34 M | **517 / 0.41 M** | 596 / 0.54 M | 487 / 0.65 M |

* **High**, the default, puts the worst frame at 1384 draws and 0.94 M primitives against 2000
  and 1.5 M: 39% fewer primitives than before, and every street is under both budgets. It
  draws **more** trees, not fewer: the streamer counted 65,837 scatter instances in range at
  Merrowby against 63,513 the old way, the same world and preset, and the difference is the far
  ring's trees, which the old far ring thinned and the pictures let stand. The near ring's trees
  alone, by the attribution: 289 draws and 650 K primitives before, 200 and 53 K now. Two
  frames gained draw calls, Briarwold's street (600 to 692) and Cinderlea's (487 to 517): a
  wood's cells hold each kind of tree at up to three levels at once.
* **Low** is 43% fewer draws and 48% fewer primitives than High at Merrowby (793 / 0.49 M), and
  looks it: a softer picture (three-quarter scale, bilinear on Compatibility), half the grass,
  shorter shadows, no glow.
* **Painted** does not exceed the budget either: 1606 draws and 1.25 M at worst, 20% under
  2000 draws and 17% under 1.5 M, with half as much shadow reach again, an 8192 shadow map,
  4× MSAA and every tree kept whole half as far again.
* The High column was measured with `--attribute`, which takes frames between shots; a plain
  re-run agreed within 9 draw calls and 0.01 M on the four shots it finished before the
  machine's memory ran out. Compatibility throughout, because Terrain3D does not survive the
  software Vulkan driver; on Forward+ Painted also turns on SDFGI, SSIL, volumetric fog and TAA,
  whose cost in draws, primitives and time nobody has measured in the world.

Interiors, the perf probe's 24 on Forward+ (lavapipe), `./run.sh perf --preset=`: the worst is
Hollin Barrow at 96 draw calls on every preset, and 0.96 M (Low), 0.98 M (Medium), 0.99 M
(High) and 1.06 M (Painted) primitives; none over budget. An interior has no scatter, so
the presets move only its shadows there.

### Still wrong, and what was not verified

* **Forward+ has not been looked at on Terrain3D.** The player's machine draws Forward+, and
  Terrain3D crashes on the software Vulkan driver this container has, so every Terrain3D frame
  here is Compatibility's; Forward+ has been seen only at High on the coarse ground (below).
  SDFGI, SSIL, volumetric fog, TAA and both FSRs are set, read back from the engine in the tests
  and greyed on Compatibility, but nobody has seen Painted on Forward+: the SDFGI and
  volumetric-fog numbers in `Graphics.apply_environment` are conservative guesses (density
  0.004, 180 m; first cascade 0.4 m) until someone does.
* **The Forward+ measurements are a software rasteriser's**, the same shaders on llvmpipe; a
  Radeon's shadow filtering and SSAO may read a far canopy differently. Re-measure on the
  player's hardware before tuning any tree by eye.
* **Four trees' LOD1s are still poor after the repair**: the third black ash's trunk tapers to a
  point at its foot, the tall Sedgemire willow's LOD1 is spiky, and the yews' carry tan blades
  that stick out of the crown, because what the decimator left of them is not much of a tree.
  They are drawn from 72, 70 and 50 m to 181, 176 and 70 m; the yews' band is so short that
  both its ends are dissolves. The fix is in the forge: a LOD1 built from fewer Sapling
  segments rather than collapsed from LOD0.
* **Not looked at: the giant oaks' full meshes carry one bark triangle of 22 and 31 m²**, the
  same in LOD0 and LOD1, so the repair leaves it (it lies on the full tree). It may be a root
  skirt; nobody has checked.
* **Far pictures do not take shadows.** A tree past its picture line standing in a hill's
  shadow stays sunlit (the receiving picture drew a wedge through itself; see the shader).
* **The instance's scale is not in the level choice**: a hedgerow oak scattered at 1.25× leaves
  its full mesh where an oak of 1× does. The shaders' dissolve bands would need the scale too.
* **Not looked at: the opaque ladders.** The walls, boulders and scree switch levels by their
  radius (LOD1 from 25 m or ten radii, LOD2 from 60 m or twenty-five), and the Skerrow street
  cost less with them (630 draws and 0.77 M before, 593 and 0.55 M now), but no capture has
  been studied at a wall's switch distance for a pop; `lod_review` stands only trees.
* **`check_scripts` still hangs on `tools_gd`** (every script loads on its own); not this pass's.

### Merged with main

Main had moved 134 commits on under this branch, and eight files had changed on both sides (and
seven more later, the audio guard, the doors and the interiors, which met this branch only in
this file). The
painted look's settings were the one real decision: main's atmosphere, water and lamps read
`video/*`, and they now read `graphics/*`. The lamps lit at night and the water's reflections
are costs, so they are in the presets (Low: two lamps and no reflections, the frame copy saved;
Medium: four; High and Painted: eight, with reflections); the colour grade, vignette and film
grain are taste, and are Graphics-tab toggles no preset touches. A settings file from main has
its `video` keys carried across once. Main's brightness line stands. The water keeps main's
mirror and this branch's quality knob, which still reaches the finest ripple and the foam's
wobble in main's rewritten shader. Two of main's new callers opened the settings screen by tab
number, which the Graphics tab had moved; they ask by name now.

The merge also exposed a fault of this branch's own: the GLB post-import read every sidecar's
`bounds` as the forge's dictionary, and a character's `bounds` is a list, so when main's
character models changed, every body in the game failed to import — 537 script errors and 14
failed tests on the first run, none on the second. An import that fails in Godot 4.7 still
records itself as done, so a stale scene survives it silently; the characters had to be
reimported by hand once the script was fixed.

### Measured again after the merge

Main now draws the lakes and the sea, lights a pool of lamps and grades the picture through a
table, and its villagers are the characters pass's heavier bodies. The streets plan again on the
merged tree, Compatibility as before, draw calls / primitives (the two right-hand columns are
the table above, on the world as it was built then):

| shot | **High** | Painted | High, no tree levels | High before the merge | Painted before |
|---|---|---|---|---|---|
| hearthvale_street (Merrowby) | **1526 / 1.05 M** | 1805 / 1.39 M | 1619 / 1.71 M | 1384 / 0.94 M | 1606 / 1.25 M |
| brightwater_street | **468 / 0.48 M** | 501 / 0.54 M | 491 / 0.61 M | 449 / 0.46 M | 495 / 0.52 M |
| sedgemire_street | **805 / 0.59 M** | 972 / 0.75 M | 791 / 0.89 M | 708 / 0.57 M | 826 / 0.72 M |
| briarwold_street | **734 / 0.64 M** | 919 / 0.90 M | 640 / 0.85 M | 692 / 0.63 M | 854 / 0.89 M |
| skerrow_street | **750 / 0.60 M** | 847 / 0.75 M | 799 / 0.85 M | 593 / 0.55 M | 704 / 0.68 M |
| cinderlea_street | **557 / 0.49 M** | 630 / 0.62 M | 519 / 0.71 M | 517 / 0.41 M | 596 / 0.54 M |

* **High is under both budgets on every street**: 1526 draws and 1.05 M at worst, against 1619
  and 1.71 M with the trees drawn the old way on the same tree, which is over the primitive
  budget. The High run twice (the merge, and the head after it) agreed within two draw calls.
* **Painted is under both as well**, and the nearest to them: 1805 draws (10% under 2000) and
  1.39 M (7% under 1.5 M) at Merrowby. Main's additions cost it 199 draws and 0.14 M there.
* **Where Merrowby's High frame grew**, by the attribution (each owner hidden in turn):
  the villagers, 566 to 656 draws and 215 K to 329 K primitives; the rest is spread thin, 10 to
  34 draws each (the water, 27, now that it is drawn; Terrain3D, 27; the landmarks, 26; the
  trees' near ring, 26 and 13 K). The shadow passes went from 914 to 1048 draws.

With main's opening merged in, on the head: `./run.sh test` 1626 tests, 0 failed, 0 script
errors, 0 dead lambda captures (a later run under load failed 2 of main's wall-clock tests,
test_audio_wired and test_cinematic_player, which passed run alone, 18 of 18 and 10 of 10);
`./run.sh flow` passes all three starts (New Game 99 of 99, load 32 of 32, Continue 35 of 35, no
errors logged, no script errors); `./run.sh journey` 16 of 16. Before that fix the flow's New
Game start failed, and only on the opening stalling at its third shot of ten (10 of 89 checks,
all downstream of it), and its load start failed with it, because the `flow` slot had been saved
while the stalled opening still held the `new_game` flag and a load with that flag up plays the
opening again.

### Forward+, seen on the coarse ground

Main's guard for Terrain3D on Mesa's software Vulkan draws the coarse ground there instead of
crashing, so the world can now be looked at on Forward+ in this container, on that ground:
Merrowby's and Briarwold's street shots (`tools/capture/plans/streets_two.json`), through
`godot --path game --rendering-driver vulkan --rendering-method forward_plus --
--capture=tools/capture/plans/streets_two.json --out=<dir> --preset=<p>`.

* **The first look found a fault of this branch's, now fixed.** The coarse ground sets each
  arriving cell's scatter down by reading its MultiMeshes back; a tree group's are refilled from
  its own rows as the eye moves, and on Forward+ they read back as NaN, which reached the height
  map as an index (72 script errors at High, 454 at Painted) and was written back as trees at
  nonsense heights across the view: a black wall over half of Merrowby's frame, a green one over
  Briarwold's sky. The group's rows are set down instead (`ScatterLod.Group.set_down`), with a
  test. This reached any player whose machine draws the coarse ground: a Mac before 15, arm64
  Linux, `--terrain=fallback`.
* **High after the fix**: no script errors, 1339 draws and 0.99 M at Merrowby, 579 and 0.59 M at
  Briarwold, and both frames read as they do on Compatibility, the wood whole. Fourteen engine
  errors, `Buffer argument is not a valid buffer` from the rendering device, come before the
  first shot, and they come with the tree groups: the same first shot drawn with `--no-lod` has
  none (1432 draws and 1.65 M; that run was killed for memory before its second shot). Which of
  the groups' MultiMesh calls the device refuses is not traced; the frames are not marked by it.
  A pale column stands in Merrowby's sky on Forward+ that is not in the Compatibility frame;
  not traced.
* **Painted after the fix has not been seen**: its run was killed for memory, with 7 GB free,
  before the first shot, and the run before the fix finished but its frames are the broken ones.
  So SDFGI, SSIL, volumetric fog and TAA are still unseen in a sane frame.
* **Terrain3D asked for seven rings** (`--terrain-lods=7`) at Painted crashed the driver before
  the first shot (exit 139), as main recorded for the New Game flow.

### Next, in order

1. **Look at Painted and High on Forward+ in the world on Terrain3D**, the renderer the game
   ships on, on a machine whose Vulkan driver Terrain3D survives (only the coarse ground has been
   seen here, above):
   `godot --path game --rendering-driver vulkan --rendering-method forward_plus --
   --capture=tools/capture/plans/streets.json --out=<dir> --preset=painted` (`./run.sh shots`
   forces opengl3). Accept when SDFGI, SSIL and volumetric fog read as light in the air and not
   as a grey wash or a flicker, and Painted stays under 2000 draws and 1.5 M; tune
   `Graphics.apply_environment`'s numbers only, never the atmosphere's recipes. Without such a
   machine, Painted can at least be seen on the coarse ground here, with `streets_two.json` in
   place of `streets.json`; on the software driver it wants more than 7 GB free.
2. **Measure the pictures on the player's GPU**: `godot --path game --rendering-driver vulkan
   --rendering-method forward_plus res://tools_gd/lod_review.tscn -- --out=<dir> --calibrate`
   rewrites every tree's `forward_plus` entry in `world/impostor_calibration.json` (about two
   minutes a tree here). Accept at luminance ink within 5% for every tree, with each
   `<tree>_calibrated.png` looked at.
3. **Measure Low and Medium on the merged tree** (`./run.sh shots tools/capture/plans/streets.json
   --preset=low`, and `medium`): High and Painted were measured again after the merge, above.
4. **Rebuild the poor LOD1s** (the third black ash, the tall Sedgemire willow, the yews) from
   fewer Sapling segments instead of collapsing LOD0 (`lib/export.make_lods` for trees), then
   `./run.sh assets --only briarwold_black_ash_c --only sedgemire_willow_a --only hearthvale_yew
   --force`, which rebuilds their pictures and repairs them on the way, and `lod_review.tscn --
   --calibrate --assets=briarwold_black_ash_c,sedgemire_willow_a,hearthvale_yew_a,hearthvale_yew_b`
   on both renderers. Accept when
   `lod_review --distances=80,150` shows a trunk that reaches the ground and no spikes.
5. **Take the instance's scale into the level lines** (`Group.update` measures distance only):
   a 1.25× oak should keep its full mesh 25% further. The dissolve bands in the shaders would
   need the scale as well; the instance colour's alpha is free to carry it.
