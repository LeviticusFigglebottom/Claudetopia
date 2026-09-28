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

## Settlements along their streets, the keys nothing read, the sentences honoured, the Hart's body

The brief: make the settlements read as places people live (a Hearthvale street capture was white
boxes with thatch round an empty green), wire or remove the five content keys nothing read and
land the audit that asks what nothing places, then honour the encounter sentences that were
honoured loosely or not at all, and give the Hart of Thorns a body.

**A settlement is laid out along its roads now.** `StreetPlan` (world/exteriors/street_plan.gd)
takes the roads that cross a place's pad, splits them at the middle into arms and merges two that
leave on one line (16 degrees), and puts the frontage beyond the outer of a merged pair where they
part, so a fork is not a front room. A village that a road only reaches has its street carried on
through, and a town on one road gets a cross street. The houses with an inside go on first: each on
the frontage nearest where its door plan wanted it, door on the street, by its footprint read at
runtime from its interior (`Building.footprint_of`). The rest of the fabric fills both sides from
the middle out, each plot an oriented box clear of the roads, the middle and every other plot, its
garden behind it, with a lane left every few plots in a town. Merrowby has four streets and 33
houses along them (10 with an inside), Tollmere 49, Isseva 35, Kharrow Hold 19.

**The houses are built by region and trade** (`HouseKit`): framed plaster, cob in ochre and pink,
flint, render over stone with jettied upper floors, tarred boards on stilts, laid logs, drystone;
porches and door hoods, chimneys, a door painted for its trade in the Vale, and a shop's emblem hung
on an iron bracket over the street; the houses with an inside hang their own names. Windows on
every side, and the houses with an inside had them too, drawn a hand's breadth inside the wall:
the house forge writes a window's `normal` as the wall's axis and not its side, so every window in
a front or left-hand wall was inside the masonry and those houses showed the street blank walls.
The side is read from the window's room now; a window the forge cut across the front door is
dropped, and every outside wall it gave none gets one with its shutters closed.

**What a street has round it.** Gardens fenced the region's way (hurdles, rails, paling, drystone
with a coping of stones on edge), with beds of cabbages, leeks, beans on cane wigwams and earthed-up
potatoes, a shed, a woodpile of round logs with their sawn ends out, washing on a line, an apple
tree; the first cut drew the crops as cubes, which read as a crate of limes, and the woodpile as a
brick stair. A town paves its carriageway, footways and square in setts; a village beats a path to
each door. The middle is a market (stalls facing the square with their goods, a well or a cross,
lamps) or a green (its well, its tree, benches). The ground between the streets, which was a lawn
a town's width across, fills from the edge of the place in with paddocks behind gates, orchards,
allotments, rickyards, woodyards and peat folds. Hens, geese, sheep and pigs (four new forge props)
keep to their own ground and wander it, and only while somebody is near. Two chimneys in three
smoke (one MultiMesh of puffs a place, moved by the shader, leaning with the wind). The people
whose days send them to a stall, the well, the green or the forge stand there, and a smith has an
anvil to stand at.

**On the roads.** A signpost is a fingerpost whose arms point down the roads that leave it, each
with the name of the place it reaches (`RoadNetwork.destinations`, at runtime); the forge's signpost
with arms at random angles and nothing on them is not drawn. A gate post has a five-barred gate,
hung along the hedge's own line across the gap, most shut and some open into the field. Skerrow's
drystone walls were judged and were not walls: the world build's asset lookup took
`drystone_wall_end` for a variant of `drystone_wall`, so a third of every run was a 0.9 m end piece
in a 2.4 m slot, each piece scaled at random in all three axes, and a boundary on the diagonal came
out two texels thick with a wall along each. `cells.py` prefers a region's own exact variants now
(checked to change nothing but Skerrow's walls), and `Wayside` closes the runs, holds a steady
height and drops the doubled diagonal. Six props' atlases had unfilled texels that bled black at
their seams (the well, the three wall pieces, the peat stacks); the forge fills them now
(`atlas_fill.py`).

**The budget.** DESIGN section 11 is 2000 draw calls and 1.5 M primitives, measured on the streets
plan's Merrowby shot, and `DrawAttribution` counts primitives by owner now as well as draws
(`--attribute`). On that shot the frame is 1713 draw calls and 1.82 M primitives, and the
settlements are 216 of the draws and 0.27 M of the primitives. The draws are under the budget and
the primitives are not, and the settlements are the smallest share of them: the scatter is 0.88 M,
the villagers 0.32 M and Terrain3D 0.29 M, 1.49 M before a house is drawn. What the settlements
cost was cut four ways:
* The sun draws the cheapest rung of everything that casts, a MultiMesh of the forge's LOD2 that
  casts and is never seen. Before, each kind was drawn again whole for every cascade.
* The gardens are a mesh a quarter, drawn to 110 m. The small things (the crockery, a bucket, a
  hen) are drawn to 70 m and throw no shadow.
* The orchards of the next village are impostors past 130 m.
* The drystone walls had no range, so every place's were drawn however far off it stood. That
  was 0.32 M of the frame. Now the wall is drawn to a kilometre and its coping, a mesh of its own,
  to 360 m.

Over the round the settlements' share went 0.51 M (the first streets), 0.42 M (the sun's cheap
rung), 0.58 M (the backlands filled and the coping packed tight), and 0.27 M.

**The keys nothing read.** `opposite` (a trait's own opposite, read before the built-in table),
`beds` (a deed on offer says "Four rooms, two beds." and its story), `sells_deeds` (a steward
offers the deeds of their place at their hub, and choosing one opens the purchase) and
`unique_features` (the card a region arrives on says what it is known for, the first time only)
are read now; `unlocks` on the Merrowby house key is gone, since nothing gives the key and nothing
it names reads it. `tools/unplaced.py` is the third audit beside `dead_data.py` and `unwired.py`:
for every enemy, person, item, book, place, interior and dialogue, the ways the built game has of
putting one in front of a player, and the definitions none reaches. **Enemies 0 of 34, people 0 of
87, places, interiors and dialogues 0; items 40 of 239 and books 17 of 41 that nothing places:**
seven pieces of armour (the brigandine's, the clan plate's and the padded set's gauntlets and
greaves or boots, and the leather gloves), six weapons of the ash, ashen and bell-bronze lines, the
Clan shield and the round shield, six potions, seven Sayings' tomes (and their seven books), ten
accounts, pamphlets and letters (and their books), cottongrass and the Merrowby house key. It
counts what an encounter says lies at a place (the chart in the Reed Wreck, the hermit's exercise
book on Willow Isle). It fails on nothing; some of that is meant, and none of it was this brief to
place.

**The sentences, honoured.** Each is a test in `test_poi_encounters.gd` against the built world. The
Clanless Camp is "a brute and two skirmishers": the Clanless Hewer, who goes in first in the
heaviest plate, and two Outriders in plate cut down to run, who flank (two new foes). Gosling Pit's
pack has its brute, the Larkbourne Bruiser, at the fire with the four and standing aside with them
while the Roll sends you to hear Ryn out; Ryn stays the one you talk to. He came in hitting hard
enough to break both of `test_balance.py`'s orderings (the downs more dangerous than Brightwater
after them, and paying more than the marsh), so his maul is 16 and 26: five and a half hits to put a
new player down, where the road's bandit takes eight and a hedge-wight three. The Headless Watch
turns: a fallen Tolling knight stands on the sixth step of its stair while the Chapter Book's walk
out to it is the errand (an encounter's new `if`, the other side of `unless`), and otherwise there
is only the vigil. The Sallow King's sallowjaws lie in the pool under his roots and come up at
whoever walks into the ring; each one the player kills there costs the Reed Council eight points of
regard, with a line saying why (`killing_costs`), and walking back out of the ring costs nothing.
The Mossbridge Wardens sit (`sits`: a foe minding its post sees you and starts nothing; a blow, the
greed rule or its group's wake ends it) and let the empty-handed cross, and wake for whoever comes
within nine metres carrying what was taken out of the Briarwold (`wakes_for`: a Warden's own
heartwood, a Hart-Knight's antler, crown or spear, weaver silk, the old trees' moss and fungus). The
Long Stride has its toll: the guilds' bravo keeps the table at the landward end by day, five marks
paid there covers the day, and whoever walks on past the table unpaid has it out with him (`toll`);
the cutpurses work the queue on the approach. The Tideflat has its crabs and nothing to fight: a
shore crab in two colours (a new forge prop), going about sideways on the old strand as `Livestock`.
The Singing Yew is ground the dead will not cross (`Wards`, from the POI def's `ward`): a foe tagged
undead whose quarry stands under the yew turns for home, comes again when the quarry steps off, and
does not step inside of its own accord. The barrow's nearest dead work the hedges 190 m off on a 26
m leash, too far to lure, so two come up the hedge line past the gravestones after dark and stop
there, for the sentence's show. And the groups said to be up high stand up high: the Foxfire weavers
and the Glass Falls bell-bearer on a shelf of stone on the lip, the Three Sisters' scree-hags on the
top ledge, and Whitecut's down-wolves in a dark mouth at the foot of the face, behind the water.
What stays terrain and not people: Gosling Pit's rear path from the Hound's eye, Fern Gully's
bridges to cut, Whitecut's wet stone.

**The Hart of Thorns wears antlered plate, and no humanoid foe is the bare rig.** Every humanoid foe
stood in the world as the forge's mannequin: no humanoid enemy was ever given an appearance, so the
bandits at the ford, the raiders "in heavy plate" and the Hart of Thorns -- "antlered plate, a spear
the length of a boat" -- were the same bare body in a tint. A foe is dressed from its def now
(`EnemyDress`): an `appearance` like any person's, a `held` forge prop in the right hand along the
socket's blade axis, and `antlers` grown from the head as their own mesh on the head's socket; a def
that says nothing wears the outfit of its first tag that has one, from the garments the character
forge already builds (a hood and a tunic on the road, brigandine on the outlaws, a gambeson and a
hooded cloak on a poacher, plate on a knight and on the clanless, rags on the dead, a robe on a
caster). The forge's cuirass has no sleeves, and the first capture of the Hart showed it over bare
arms, a vest on a labourer; plate is worn over a padded gambeson now, and the test asks that nothing
wears it over bare arms. The Hart wears the cuirass and pauldrons over his gambeson, gauntlets,
boots and a helm, carries the forge's spear at two and a half times its length, and his antlers
stand over the helm a metre across with four tines a side (`test_enemy_dress.gd` measures them on
the rig at rest).

**Two things found on the way.** A foe's eyes asked where the player stood in the frames between
the world and an interior, when the body is out of the tree: an engine error a frame, fourteen in
one run of the suite. Perception passes over a body out of the tree now. And since the physics
interpolation was turned on, every capture logged the engine's warning that a MultiMesh it keeps
was moved outside the physics ticks: the beasts, stepped from `_process`. Their MultiMeshes are out
of the interpolation.

**Checks**, on the merged head (main at 6985d356), one Godot at a time:

* `./run.sh test`: 1,664 tests, 0 failed, 0 content problems, 0 script errors. The 4 logged errors
  are the ones their tests provoke: an unknown item twice, an unknown interior, a missing save
  slot.
* `./run.sh journey`: 16 of 16 steps, 0 logged errors.
* `./run.sh smoke`: PASS. 6 regions, 34 places, 24 interiors, 0 logged errors.
* `./run.sh flow`: **fails 1 of 99 checks, in the opening**: "pressing a key during the opening
  shows the skip prompt". While it ran, other agents' builds held the machine at a load of 11 to
  15. The opening's shots were drawn at 2 to 4 frames each, over 15 to 32 s of wall clock. The
  probe also logged "Lambda capture at index 0 was freed" from its own `_wait_until`. Nothing in
  this branch touches the opening or the probe. The Naming, the handover, the first moment of
  control, the HUD and the objective all pass. The run stopped at that check, so the `--load`
  and `--continue` starts were not run.
* `python3 -m unittest discover tools/tests`: 27 tests, with 3 failing. All three are on the
  forge's empty pauldrons, as on main. `test_balance.py` passes again now that the Bruiser is
  fixed.
* The audits against main:
  * `unwired.py`: 39 functions reached only by the tests, the same 39 names as main.
  * `dead_data.py`: 0 of 620 keys (main: 5 of 599).
  * `unplaced.py`: 0 of 34 enemies and 0 of 87 people; 40 of 239 items and 17 of 41 books;
    places, interiors and dialogues 0.
* The streets plan's Merrowby shot, on Compatibility with `--attribute`: 1713 draw calls and
  1.82 M primitives, of which the settlements are 216 draws and 0.27 M.
* Every frame was looked at:
  * 19 look shots on Compatibility (the five regions' streets, Merrowby's street, market,
    gardens and fingerpost, the aerial, the Vale gate, Skerrow's walls, and the encounter
    places);
  * 8 on Forward+;
  * the streets plan's six and seven framed in the streets, on Forward+, on the final head.

**Found and not fixed.**

* **The streets plan's cameras stand where the ring's gardens were.** The six street shots were
  set for the old layout, 45 m from each middle; with the towns laid along their streets, the
  Merrowby shot looks across back gardens and the Gullhithe one across the grass between two
  streets. They still measure the worst frame (the settlement all round the camera); they are not
  the best picture of a street, and `tools/capture/plans/streets.json` is the shared plan, so it
  is left alone.
* **The primitive budget is over, and not because of the settlements.** On the Merrowby shot:
  * the frame is 1.82 M against DESIGN section 11's 1.5 M;
  * the scatter is 0.88 M, the villagers 0.32 M (0.21 M before the characters' second round) and
    Terrain3D 0.29 M, which is 1.49 M before a house is drawn;
  * the settlements are 0.27 M.
* **A house with an inside has shut windows the inside does not.** The house forge cuts as many
  windows as the household can pay for; the outside now has one on every wall, shuttered where
  the interior has none, and walking in you find a plain wall behind the shutters.
* **The cutpurses at the Long Stride still fight rather than pick pockets in the queue**: their
  blow cuts a purse and they run, which is the bestiary's cutpurse; a queue that jostles is not
  built.
* **Gosling Pit's rear path from the Hound's eye, Fern Gully's bridges to cut and Whitecut's wet
  stone are terrain, and are not built.**
* **The sallowjaws are the quadruped rig in a green tint.** In the capture of the Sallow King's
  ring they stand in the shallow pool as two box-bodied dogs. The bestiary's sallowjaw is a log
  that lies in eight inches of water for a day and a half; that body is the characters' to make.
* **The point-of-interest kinds the drawn map wants next** are not built: cave, farmstead, mill,
  waystone, market field, quarry, shieling and vista (the cartographer's `docs/ATLAS.md`, section
  10). They are next on this list after the settlements.
* **The forge's pauldrons hold no mesh.** `clothing/pauldrons/pauldrons.glb` is a skinned node
  with nothing to skin (`tools/tests/test_glb_textures.py` fails on it, on the parent branch as
  well), so nobody's pauldrons are drawn: the Hart's and the knights' shoulders are their
  gambesons'. They are left in the outfits for the day the forge builds them.
* **The player's Clan Plate is worn over bare arms.** Its description is "iron plates faced with
  giant-bone over a wool arming coat", and its `wear` puts the sleeveless cuirass in the torso slot
  with no coat (`items/armour.json`), as the foes had it before this round. The player's wardrobe
  was not this brief.

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

## The kinds the drawn map asked for, and the 239 warnings in the debugger

Two things asked for after the settlements: the point-of-interest kinds the cartographer's atlas
wants next (docs/ATLAS.md, section 10), and the warnings a user found filling Godot's debugger.

**Eight new kinds of place.** Each is a kind of its own now (`PoiDressing.KINDS`), built in
`world/pois/poi_builders_land.gd`:

- **cave:** two of the region's own cliff slabs leaning together over the mouth, with boulders
  wedged where they meet, heaped over the passage and stepping down its flanks. Its throat goes ten metres
  into the hill in five rings, each darker than the last, and each ring's floor sits on the
  ground there. The Briarwold's is a root-cave; the sea's has the tide in its mouth.
- **farmstead:** a house and a barn of the settlements' own fabric round a walled yard, with its
  gate to the road, a well, hay, a cart and hens. Where the sentence says there is work, the
  notice post stands by the gate.
- **mill:** two floors and a wheel in a stone leat. Where the sentence says sails, it is a stone
  tower turned into the wind with four sails. Wheel and sails turn while somebody is near
  (`Turning`).
- **waystone:** a milestone with the pilgrims' tally cut into both faces, and a bowl of coins.
- **market field:** a walled field and its bell-post. On market day (`MarketDays`) the stalls
  stand in two rows with the carts behind them, packed away, bodies and all, the rest of the week.
- **quarry:** a face of three cut benches, chalk in the Vale. A bench stands no prouder than the
  hill a pace behind it, with the turf over its lip; where the hill does not rise, there is none.
  It has squared blocks, a spoil heap, and a timber crane with a block on its rope.
- **shieling:** a drystone hut under a turf roof, and the round fold with the flock in it.
- **vista:** a bench on the edge, turned to where the ground falls furthest, and the cairn
  walkers add to.

Each kind also has a map marker, a reveal distance and a landmark height.

The world has none of them yet. So a capture plan can now stand any kind up on real ground for a
shot (a shot's `dress`, and `day` for a day of the week). `tools/capture/make_poi_kinds_plan.py`
finds a spot for each on the built world and a camera whose line of sight no tree's crown crosses.

The first capture was honest about three of them:
- The caves were built of painted masonry blocks, and every one read as a tomb's doorway. They
  are the forge's rock now. The second look found a slab laid over the cheeks as a brow, which
  was the doorway again, so the cheeks lean together instead.
- The quarry was a white wall of courses standing on a mound, with trees behind it. Its face is
  cut rock now, no taller than the hill, over a floor the blocks and the crane stand on.
- The mill was behind a tree the world had planted in front of the camera.

The third look (five frames) is better and not yet right:
- The two slabs of a cave read as an A-frame, a tent of rock, more than a cleft in a hill. The
  cliff slab's faces are flat, and it stands on the slope rather than out of it.
- The sea-cave, on Cinderlea's black ash, is two striped slabs on a dark shore.
- The quarry reads as a quarry from the road: low benches, the squared blocks, the crane. Its
  spoil heap is a white mound too big for what the benches gave.
- The vista's bench is lost in the grass at ten metres. The cairn shows; the bench does not.
- The farmstead, the mill, the windmill, the market field, the waystone and the shieling read as
  what they are, from the first look.

**The 239 warnings.** Godot shows a warning in the editor's debugger for every one its analyzer
finds in a script the running game loads. A user counted 239. They cannot be counted from inside
the game, since the analyzer reads each warning's level once, at startup. So
`tools/debug/warning_census.py` does it from outside:
1. It asks Godot which warnings the project leaves at "warn".
2. It writes a marked `game/override.cfg` that makes each of them an error.
3. It has Godot compile every script afresh under a stand-in path.
4. It reads the warnings out of the log, and removes the override whatever happens. `run.sh`
   removes a marked override left behind by a census that was killed.

The count before any fix:
- The event bus: 70 of the 239. Its signals are emitted by other scripts, which is what a bus is
  for, and the analyzer warned of each one its own class never used. The declarations now sit
  between `@warning_ignore_start("unused_signal")` and its restore. That warning is off there and
  nowhere else, and `test_event_bus.gd` holds it.
- 171 more in 70 of the game's scripts, which accounts for the rest of the 239.

Cleared this round: 38 in this branch's own files, by renames and explicit integer divisions.
None changes behaviour:
- a parameter named `basis`, `position`, `scale`, `sign` or `seed` hiding what it names;
- a `camp` or `box` hiding a function;
- unused locals;
- one ternary of a float and a string.

The baseline (`tools/debug/warning_baseline.json`) is now 136 in the game's
scripts. That is main's count after merging it: this branch cleared its own to 132, and main
brought four the ratchet was not there to stop (humanoid_model.gd one more, quest_foes.gd one,
the Stair Head's crows.gd two). `./run.sh test` runs the census after the suite and fails when the count grows past the
baseline, naming the files that grew; `WARNINGS=0` leaves it out. The rest sit in files other
streams are editing (characters, player, enemies, quests, audio, the cinematic, the land), and
each clears its own and brings the baseline down with `--update`.

**Checks.** After merging main (9d948b88):
- `./run.sh test`: 1707 tests, 2 failed, 0 content problems, 2 script errors.
  - Both failures are in test_trade_screen, and one script error is in test_talk_to_the_warden,
    where the Warden was freed under the test.
  - All of these pass when their files run alone (6 tests, 0 failed).
  - The other agents' suites on main's work show the same two failures.
- The census: 136, at the baseline.
- Journey: 16 of 16.
- Smoke: PASS.
- Flow: 106 checks, 4 failed, all at the Warden. Walking up to her on the move key stops at
  3.6 m, so the ray, the prompt and the conversation fail after it. The graphics and painted-look
  agents' flows on main's work stop at the same 3.6 m (or 4.2 m), so it is not this branch's.
  The skip prompt this branch saw fail last round passes now.

**Found and not fixed.**

- **The census counts the analyzer's warnings, not every line the debugger shows.** A script that
  fails to compile under the census (41 "Failed to compile depended scripts") is analyzed no
  further, so a few warnings behind those may be missing. The census can only undercount.
- **The kinds are photographed where the plan stands them up, not where the map will.** Until the
  atlas's world build puts POIs of these kinds on the map, every shot is staged. Its scatter is
  the world's: the trees and walls the build planted stay, because a staged POI has no pad to
  clear.
- **A market field's stalls stand in rows on whatever slope the field is on.** Kharrow Foot's
  field is on a fell side, and the rows follow the ground.

## The painted look, continued: the grey flashes, the grey cast, and lakes that were never drawn

The first playtests of the painted look were on Forward+, the renderer players have, which no
capture here had seen: "a weird persistent grey look, too many filters on the screen, and
everything flicking black and grey every few seconds", then, on the real terrain, "objects
constantly clip black and grey". This section is those, in that order; then the water, which
turned out never to have been drawn at all; then the after-sheet and drop test the first section
left undone. Everything was measured on the world the first section measured on (built
2026-09-22 12:56:09Z) from this branch's own code, so before and after stand on the same ground;
the atlas world that replaces it has not been shot, and the full re-shoot waits for it.

### What this machine can and cannot show of Forward+

Mesa's software Vulkan (lavapipe) runs the game on Forward+ here, at about four seconds a frame,
and with limits that bound every Forward+ claim below. Terrain3D's clipmap at the game's nine LODs
segfaults lavapipe on its first frame; at seven it draws, so every Forward+ frame here is from a
scratch copy of the game whose `world.gd` took the LOD count from an environment variable (the
committed game is unchanged). Lavapipe still segfaults every few teleports, after a "caller thread
can't call propagate_notification() on /root" error, so sets were shot a few shots at a time and
re-run from the one that crashed; the Briarwold, Skerrow and Cinderlea vistas crashed it on every
one of eleven tries and have no Forward+ frame. A camera that moves crashes it within a second.
**Not verified on this machine, therefore:** Forward+ with a moving camera; Forward+ at the game's
nine LODs; those three vistas on Forward+; anything about Forward+ performance; and the
"objects clip black and grey" the player saw, which nothing here reproduces (below). The last two
changes of this section, the cirrus and the stars, are compiled on both renderers and checked in a
numpy model of the shader, and have not been shot: the old world was not to be shot again.

### The flashes were the grade's table, swapped under the renderer

The capture runner's `sequences` hold a camera still, or walk it, while the game runs, and measure
every drawn frame: its mean brightness, the frames under half the run's median (DARK), the frames
brighter or darker than both neighbours (FLASH), and, on a 160 x 90 grid, the samples that jump
and come straight back (a thing flickering on its own). On the merged head at the Hushline Stair,
forty frames a quarter second apart fell from 0.50 mean brightness to 0.02 and back, ten frames at
a time: every 0.4 s refresh of a region's six-second look blend handed the Environment a new
ImageTexture3D for its colour correction, and Forward+ drew with the new texture before it was
uploaded. The table is made once now and rewritten in place (`ImageTexture3D.update`). The same
camera on this code drew 250 frames at 0.378 to 0.493, none dark, no flash, with one texture made
and one assignment in the whole run (`lut_stats` counts both; a test pins them through a blend).
The other per-frame writes were audited: the rain, snow and ash rebuilt their quad and restarted
their particles every frame and are set up once per kind now, and glow is switched only when its
setting changes. The region under the player was also re-decided at every streaming-cell edge
with no margin, and over open water by a nearest-shore search that lands either side of a strait;
a region is entered only 24 m inside it now, kept over water, and taken at once by a camera or a
load that puts you down somewhere.

"Objects clip black and grey" as the camera moves: three Compatibility cameras creeping 2.5 m over
five seconds, every frame checked -- the Merrowby street by day, the Cinderlea street, Merrowby at
half past nine at night -- 95 frames each, no dark frame, no flash, nothing flickering (the worst
frame had 14 of 14400 samples jump, parallax at the edges of things). A still Forward+ camera shows
none. If the player still sees it after the grade fix, it is Forward+ in motion, which is the one
thing lavapipe cannot run: SSAO, the shadow cascades and the visibility-range fades are the
candidates, and a screen recording from the player's machine is the next evidence to get.

### The grey cast and the filters

On Forward+ the look was grey for five reasons, all fixed. The blacks took 0.45 of each region's
`shadow_lift`, a matte over every shadow (0.2 now). `glow_bloom` fed the whole frame into the glow,
a soft light over everything by day (0 until night). The grade's table grades the sky too, and
Hearthvale's warm midtone took a sixth of the blue out of a mid-blue sky and turned it olive-grey,
the whole top half of every Forward+ frame (midtones and gains are within a few percent of white
now; warmth is the sun's and the fill's). The horizon took 0.3 of the fog's colour and the blue
reached down only as far as a `horizon_sharpness` of 3.2 lets it, so a level view, which sees sky
to twenty degrees or so, saw a band of fog-grey (0.15 and 4.5 now). And Cinderlea, where a new game
opens, was the greyest frame in the game -- saturation 0.55, blacks lifted furthest, far fog
0.0008, a cream sky banded like a zoom, grey weather seven times in ten -- and has a clear pale sky
over a warm horizon now, a violet fill that keeps the char from black, gold light, 0.92 saturation,
a quarter of the haze, and dry wind or thin sun as its likeliest weather. The vignette is 0.08 to
0.12 in every region and `video/vignette` turns it off; film grain is off unless
`video/film_grain` is on.

Forward+, the merged head 10dea7e5 against this code, the same cameras
(`captures/fplus_before8`, `captures/fplus_after8` in this worktree):

| shot | before | after |
|---|---|---|
| the new game's first view, Hushline Stair | cream-grey sky raked with streaks, film grain, the land lost in beige haze | a blue sky with cloud masses; the Hush's mist a pale bank to one side; the near ground dark |
| Greyfold, where the user stood | the same streaked cream sky over grey ground | blue sky, lit cumulus, bone-white ash trees against it; the ground in shade near-black |
| the Hearthvale vista | olive-beige sky, the distance sepia | blue sky and cumulus over the green and gold of the vale |
| the Mere from its landmark | a pale sheet where the lake is | a blue lake with the far shore in it |
| the Sedgemire vista | a whiteout: one pale teal-grey field | a broken overcast over the dark marsh |

### The lakes and the sea had never been drawn

The builder writes the water mask as 0 and 1; WaterSurface loaded it as an 8-bit texture, which a
shader samples as byte/255, so a wet texel read 0.004 against the shader's 0.5 test and every
fragment of the water sheet was discarded, from the first runtime world on. What the Mere, the Grey
Sea and the marsh pools showed was the lake bed's terrain texture: the water shader reached a frame
only on the rivers, and every tuning of it in the first section was a tuning of nothing that could
be seen. The mask is stretched to 0 and 255 as it loads, a test loads the mask the manifest names
the way the game does and fails if any wet texel would read as dry, and docs/CONTRACTS.md 6 states
the byte convention. From the Willow Isle the Mere is now mirror-calm deep blue, holding the isle,
its tree, the clouds and the far shore upside down.

With the water drawn, five more faults showed and are fixed. The engine's own specular laid the
sky's radiance over the mirror, so every lake was as bright as the sky above it (SPECULAR 0; the
mirror and the glints are the whole reflection). Depth was read at the sheet's vertices, ninety
metres apart (per fragment now). The Mere's look camera stood at 1.2 m, under the surface at 8 (the
plan generator lifts a camera under water to an eye's height over it). From below, the mirror
smeared the lake bed across the ceiling (the underside is plain water now). And the marsh, which is
shallower than the foam band everywhere, was one field of foam drawn in squares, one octave of
noise on the world's own grid cut hard (two octaves on a turned grid now, and each region says how
much foam its water raises: the sea 0.8, the marsh 0.08). The mirror also follows the reflected ray
over the mask to the shore it meets, so the far shore stands where it should in the water rather
than a camera-height too high. The Hushline Stair's pad, which the sea's arrival showed to sit
0.2 m above deep water, is the opening's, and its section above says what it did.

### The sky, the stars

The cumulus are sized so a frame holds several masses, lit on top by a high sun and on the side by
a low one, and fade out only in the last degree over the horizon, where they used to fade over the
lowest seventeen and a level camera saw none. The cirrus came in straight streaks from edge to edge
of the frame and read as beams of light, or contrails; they are wisps now, bent across the wind
like mares' tails and only where a patchier field allows. The stars came out at half strength with
the sun six degrees down, over a dusk the night exposure had already lifted to rose, and hung in
the opening's still-light evening at the Toll (the opening agent traced it): they wait for the
dark now -- none until six degrees down, most by twelve, all by eighteen -- and each is faded by the
brightness of the sky behind it. The dotted line up the sky in the same frames was the NaN fixed in
a49969bf; the opening agent found no trace of it since.

### The after-sheet and the drop test

The after-sheet is the baseline's own 42 cameras from this branch's head (before the marsh's foam
change; the flythrough, which the drop test does not read, was left off), and every frame was
opened, as were the 17 frames of the look plan (dusk, dawn, night, lamps, the Mere, the falls).

| drop test, 42 images, seven a region | colour | landform | together |
|---|---|---|---|
| baseline (the regenerated plan, clear landmark cameras) | 0.81 | 0.31 | 0.64 |
| **after** | **0.88** | **0.33** | **0.79** |

Misread images went from fifteen to nine. Cinderlea and Skerrow, mistaken for Skerrow, Brightwater
and Sedgemire six times between them, are never mistaken now. What is left is Brightwater read as
Skerrow three times (blue sky over blue-grey stone, twice with the lake in frame) and the Sedgemire
and the Briarwold read as each other three times (green wetland under cloud). The colour axis
clears its bar; landform is the terrain's axis, and `tools/uniqueness_check.py` fails the test on
it, as it should.

The worst frame is still the Merrowby street at nine: 1503 draws and 1.60 M primitives against 1521
and 1.613 M. Across the other forty shots draws moved by -18 to +22, +2.8 on average; the two
landmark cameras the plan turned in the first section are left out (the view changed there, not
the light). The street
was over the 1.5 M primitive budget before this work and is by the same margin now: that is tree and
scatter LOD. The look sheet's worst was 722 draws and 1.22 M (Hearthvale at dusk); Merrowby at ten
at night drew 617 and 0.75 M, with the lamps lit.

From the look sheet: Hearthvale at dusk is gold cloud over a lavender distance; Merrowby at night
has lamplit doors and warm panes with glazing bars under stars; the Mere at noon is a mirror;
the Briarwold at dusk is a painted sunburst through the canopy; Cinderlea at dusk is the ash-gold
the brief praised. The Whitecut and the Foxfire falls read as falls and the Glass Falls as dark
glass, as written; the Three Sisters is a white stepped block, which is its mesh, not its light.
Cinderlea's street at night is nearly black, with one window lit.

### What the per-frame work costs

Count, mean and worst, on Compatibility, before (tuning pass 5) and after (the look sheet): the
grade table, 35 builds at 3.8 / 18.5 ms before, 42 at 2.1 / 7.1 ms after (written as bytes instead
of a call per texel, and updated in place); the glow MultiMesh for 718 lamps, 23 rebuilds at 5.0 /
73.4 ms before, 35 at 1.0 / 14.3 ms after (one buffer from per-owner chunks); the lamp pool's
assignment, 0.75 / 12.1 ms before, 0.73 / 10.7 ms after. On a machine with a GPU all of these are
smaller; here they are llvmpipe's, on a machine running eight other agents.

### Next, in order:

1. **Re-shoot on the atlas world** when it is in main: `default.json` for the drop test and perf,
   `look.json`, and a Forward+ set of stills at seven LODs (the new game's first view, Greyfold, a
   vista a region). Look at the cirrus wisps and the Toll at 18.2 h for stars: neither has been
   seen since its change. Regenerate the plans first; the cameras were drawn for the old world.
2. **If the player still sees objects flash on Forward+**, it is Forward+ in motion; ask for a
   screen recording, and try SSAO off, then shadows at medium, then visibility-range fades off.
3. **Brightwater against Skerrow** in the drop test: the colour axis confuses them in lake-and-sky
   frames. Skerrow's light could go colder and whiter (its snow, its bone), Brightwater's warmer
   in the greens round the Mere.
4. **The Sedgemire against the Briarwold**: two green wetlands under cloud. The marsh's teal fill
   and its mist could lean further from the wood's green.
5. **Cinderlea's ground** is near-black in shade on Forward+ and its street at night nearly black:
   the char textures are dark and the fill lifts them only so far. The fill, the textures or
   the street's lamps, not the grade, which was the grey.
6. **The Briarwold's light shafts exist only on Forward+** (volumetric fog, off by default). A
   Compatibility version would be the cave forge's `light_shaft.gdshader` cones stood in clearings.

Known limits: every Forward+ image here is lavapipe at seven terrain LODs, stills only. The
Forward+ extras (SSAO on, volumetric fog and SDFGI off) were not judged. The before sheets and
the Forward+ pairs live only in this worktree's `captures/`.

## Wickmere drawn by hand, and filled to walk

The playtest put the Foundling at the edge of a map that was mostly empty hills, with a tower
here and there, and said the seed had taken the mystique away. The world's geography is now drawn
by hand in `tools/world/atlas/atlas.json`: twenty-two provinces in the six regions, with 21
ranges, 24 peaks, 29 valleys, 14 rivers, 7 lakes, 21 woods, the coast and its cliffs, 83 roads
and the start. The builder makes the land from it, and noise decides only how a slope is
broken. `docs/ATLAS.md` gives the reasons for each part and every new location's story, and
WORLD_BIBLE §6.7 points to it. The decision is recorded in DECISIONS (2026-09-23, superseding
"The land is built last").

### How full it is

These figures are measured on the preview's 8 m cells (`tools/world/atlas/preview.py`). Walkable
means dry land that is not too steep and not past the Skerrow Wall's or the Thornmarch's crest.

| | |
|---|---|
| land | 61.4 km², of which 47.2 km² is walkable |
| locations | 297: 57 places and 240 points of interest, 6.3 to a walkable km² |
| nearest location | mean 180 m, 95% within 312 m, worst 501 m. 0.1% of walkable ground is over 400 m from one, in three pockets under 0.01 km² each |
| roads | 83, 80 km: highway 3 km, road 25, lane 13, track 36, causeway 1.6, stair 0.6. No stretch is more than 289 m from a location |
| near the start | 15 locations within 1 km of the camp, 29 within 1.5 km, 45 within 2 km |

83 existing places and points of interest were moved to where the map puts them. None was
deleted or renamed. There are 217 new locations:

* 26 places. Each has one resident with a schedule, a dialogue and a habit of their own
  (`game/content/packs/core/npcs/the_map.json`, `dialogues/the_map.json`).
* 191 points of interest: 53 ruins, 39 camps, 29 standing stones, 23 towers, 18 bridges,
  13 shrines, 6 waterfalls, 6 giant bones and 4 wrecks. Each has a one-line hook, and the world
  has 22 Hearthstones in all.

`tools/world/tests/test_atlas_map.py` holds these things:

* every location stands in its own region's provinces, on land unless it is a bridge, wreck or
  the like, and no two within 20 m;
* every place or point of interest that anything in the pack names exists;
* every river falls to its mouth;
* the density: worst gap at most 550 m, at most 1% of the ground over 400 m, no road stretch
  over 300 m from a location, at least 250 locations;
* every settlement is on a road;
* the landing;
* the start faces the Choir.

### The shapes, redrawn where they read as machine-made

* Province borders, woods and the coast are broken every 140 to 210 m and pushed up to 45 to
  70 m off the line. Neighbouring provinces share each border point for point.
* The Wall's summits are drawn by the builder. The "fans" were the preview's shading of them.
* The small waters are drawn to their settings, at 14 to 19 points each.
* The Mere is drawn in features of three hundred metres and more:
  * the Narrows' funnel;
  * Smokehouse Bay, open-mouthed under Merrowhithe;
  * Holm Point;
  * Lime Bay, as wide as it is deep;
  * the Stride Ness, about 470 m long, carrying the Long Stride and the new Ness Market;
  * Willow Bay, closed by Willow Point;
  * the Reed Arm narrowing to the Eelweir;
  * the Lamp's promontory.
* Tollmere's island has a harbour bight where the causeway lands, the Spire Rock (32 m) at its
  high end and a low tail where the Undercroft has its water-gate.
* The built shore had scallops, and the cause is the builder's shore band. On a build, a lake's
  water stands about 36 m inside its polygon (24 to 56 m), so every cove under about a hundred
  metres closed into a round bump. The drawing now has none that small (ATLAS §11).

### The landing

The Foundling comes up out of the Hush onto the Landing, a rock shelf 4 m above the sea under
the cliff. The Oroth stair goes on down into the water from its seaward edge. The fields were
agreed with the land builder:

* a coast shelf at 4 m with a 90 m bank;
* a lobe of the coast polygon with a 4 m cliff on its seaward edge;
* a pad for the Hushline Stair;
* the road `core:road/stair_head_hushline_stair` of kind "stair".

The Stair is one traverse across the bank. Three switchbacks were tried first, and their corners
sat mid-bank and ran 1.6. Drawn, the shelf's seaward edge is a smooth arc. The land builder breaks
it with spurs, bites and fallen blocks, and cuts a notch where the Oroth stair leaves the shelf
(`coast.shelves[].notches`, at (44, 3902)). The Wardens' camp stands on the Stair Knoll, a 110 m dome, so the first
view carries over the heath to Pilgrim's Ash's smoke and Ashwell's roofs. The Ash Heath's relief
is kept at 18 m for the same reason.

These figures are from a 1024 heights build of 9277caaa with the builder at 74143ba9 (92 s, peak
0.9 GB). The camp stands at 108.4 m and the Stair at 4.0 m. The Stair's road is 646 m long, and
its steepest stretch is 0.57.

### The map

`tools/world/atlas/render_map.py` draws the paper map, `docs/atlas/wickmere_atlas.png`. It draws
provinces by biome, woods, rivers, roads by kind (the stair with its steps), and every settlement
and point of interest by kind. Hearthstones are ringed and the start is marked with its first
view, and a panel gives the figures. The options are:

* `--world DIR` draws a build's heights and water, with each lake's shore where the build put it;
* `--coverage` shades what is far from anything, and over a build tints the dry band of each lake.

### Tests

* `check_atlas.py` finds 0 errors. The 20 warnings are places inside a border's blend, and the
  Bell-Buoys in the Mere.
* The Python atlas tests pass (31).
* `./run.sh test` has 0 content problems. test_crime, test_jobs, test_world_data and
  test_poi_encounters were brought to the moved content, and the property, crime, content and
  point-of-interest filters pass.
* Twelve tests read the tracked world, which still has the old positions. They fail until the
  world is rebuilt from the atlas. Each was run alone against the content as committed:
  * test_world_data: the region mask agrees with the place data; settlements are out of the water;
  * test_world_spawn: a character is put on the ground at the opening;
  * test_the_start: the Stair Head is a camp with the Warden's place in front;
  * test_npc_streamer ×3;
  * test_npcs_in_the_world;
  * test_settlement_people ×2;
  * test_cinematic_player ×2.

  The rest of test_world_data passes over the old world, including the Mere's water and every
  point of interest standing on the ground.
* test_inventory_loot's two quest-stage tests fail on the branch this work started from, whether
  run alone or in the full suite. The opening gave the Naming a stage called "the_choir"
  (20ef631b), and the loot test (b1326eb6) still counts four stages. It has nothing to do with the
  map.

### Next, in order

1. **Rebuild the tracked world from the merged atlas**: 9277caaa, with the land builder's notch
   (that is the land builder's work). Then run the world-coupled tests above and test_sightlines
   against it.
2. **Walk the start at ground level**: the Landing, the Stair's traverse, and the first view from
   the knoll. The Lark Pool sits 3 m under the line of sight from the camp and comes into view on
   the way to Pilgrim's Ash. The Glass Falls are behind the plateau's lip.
3. **The cost of the new places at bootstrap**: the 26 new places, mostly hamlets and lodges, all
   bring their fabric and their people. Measure what the streamer carries around the Vale.
4. **Mend test_inventory_loot** for the Naming's five stages.
5. `namegen --check` reports four problems that were there before this pass (the Reed Lantern,
   and duplicates among the example Merrowby people).

## The quests follow the map

The drawn map has 297 locations, and the quests reached few of them. The pack's 35 authored
quests reached 25 of its 57 places and 15 of its 240 points of interest. Nine of its 39
settlements had a resident with work to give. None of the 26 new ones did: each had a resident
with a day and lines of their own and nothing to ask of anybody. Forty side quests are now written
with the map, and three rules hold:

* every settlement has work, given by somebody who lives there;
* every place that is not a settlement is somewhere a quest sends you;
* every point of interest pays off in something the game puts there.

`docs/ATLAS.md` §15 lists the quests province by province, with every settlement and the work in
it. §16 ties every point of interest's hook to the ids that pay it off. WORLD_BIBLE §6.7 points at
both. DECISIONS (2026-09-23, "The map's hooks are kept with the systems the game already has")
says why the work is quests and not jobs, and why a note is an encounter that stands nobody up.

### What was written

* **40 side quests** (`game/content/packs/core/quests/the_map.json`) in the provinces' voices:
  * 11 in Hearthvale, 7 in Skerrow Heights, 6 each in Brightwater, Sedgemire and the Briarwold,
    and 4 in Cinderlea;
  * each has 4 to 6 stages and sends you from its giver's settlement to 2 to 4 other locations,
    and 12 cross from one region into the next;
  * each comes to a decision with three options (120 in all), and every option moves something
    the game reads: standing with a faction, Hearth or Hollow, renown, coin, a deed, or where
    somebody lives. Nella Candlewright can be walked home to her candle stall in Merrowby, or
    she can go on south out of the world.
* **Who gives them.** Each of the 26 residents the map added gives one, and Tor Rookwright gives
  two. The other thirteen come from thirteen residents who already had dialogue in other writers'
  files. Their offer, return and decision lines went in by text insertion only: new nodes, hub
  choices and greetings, and nothing else in those files changed.
* **What is remembered.** The person who asked greets you with what came of each decision once
  the quest is done: 119 greetings in all. 99 were written for flags that nothing read, and 20
  earlier ones now wait for the quest to finish.
* **What lies about.** 84 books, each with an item copy to carry: 12 for the quests, and 72 notes
  at points of interest. The notes are put down by encounter defs with `lies` and no `spawns`
  (`encounters/the_map.json`). 103 items: 31 for the quests and the notes' 72.
* **`core:table/poi_hooks`** gives one row per point of interest: the quests that send you there,
  what lies there, the encounters that stand somebody up there, and its Hearthstone.

### Where it reaches

| | before | now |
|---|---|---|
| authored quests | 35 | 75 |
| settlements with a resident's work | 9 of 39 | 39 of 39 |
| places a quest sends you to | 25 of 57 | 57 of 57 |
| points of interest a quest sends you to | 15 of 240 | 108 of 240 |
| points of interest with anything to go there for | 106 of 240 | 240 of 240 |

Of the 240 points of interest, 108 are sent to by a quest, 74 have something lying there to take
or read, 83 stand up an encounter and 22 keep a Hearthstone. (It was 109 until main moved the
Naming's first fight from the Hushline Stair to the Choir; the Stair keeps its wights and its
Hearthstone.)

### What needed plumbing

Quest plumbing belongs to the settlements stream, so items 1 to 7 were not built, and that stream
has been told of them. The quests use what the game already has. Item 8 was built here, because
the settlements stream asked for it to be:

1. **No effect adds bounty.** Bounty comes only from a crime, such as taking an item a quest marks
   with an `owner`. So no decision here puts a price on your head. A `bounty` effect, or a crime
   effect, would let one.
2. **A `talk` objective closes when you finish speaking with its person, about anything.** A
   delivery can wait for its own line (`QuestRoutes.dialogue_closes`), but a talk cannot. The
   return lines are written, and the objective does not wait for them.
3. **`read_book` resolves only for a book on an interior's shelf or one whose item copy can be
   got.** A book read where it lies, as an encounter's `lies` book, cannot be the target. Every
   book here has an item copy.
4. **Jobs come from boards and stations, never from a resident.** "A job from somebody who lives
   there" is not a thing the Jobs system can say, so the local work is quests.
5. **There is no kind of secret.** Nothing hides a thing until it is found. A hook that promises
   something hidden pays off in a note or an encounter instead.
6. **`test_quest_reach` wants a `start_quest` effect for every authored quest and does not count a
   giver's `offer`.** So every giver's dialogue has a line that starts their quest, as well as the
   `offer` the dialogue runner shows.
7. **Nothing in the game reads `core:table/poi_hooks`.** It is an index, and test_map_quests keeps
   it true.
8. **QuestItems put a find with no marker a few paces off a place's middle, without asking
   whether there was room.** A dressing's collision is a hollow shell. So 24 of the 96 finds the
   map's quests and notes leave at points of interest lay inside a boulder, a wall or a tent, or
   under an arch or thirteen metres of waterfall rock. `QuestItems._spot_in_the_open` now keeps a
   marker's spot exactly. Without one it takes the key's spot when that is open. Otherwise it
   takes the first open spot round and outward from it, and otherwise the key's spot as before.
   Open means a crouching body touches nothing on the world layer and a ball let down from 80 m
   reaches it. The physics space has to hold the place's colliders when the find is asked for.
   WorldPois raises the dressing first, and a query in the same frame sees it (98 of 98 spots
   agree with the ones asked a frame later). A find asked for with no dressing in the tree takes
   the key's spot, as every find did before.
9. **QuestFoes' ring stood a foe inside a hollow landmark until the opening's overhead refusal.**
   Of the map's 27 fights in the open, one needed it: the Watcher, whose scree-hag was stood under
   the skull whenever the Watcher's own scree-hag had been killed before the stage opened. The
   refusal is in main and merged here, and test_map_quest_ground asks QuestFoes itself.

These were handled with what exists:

* An escorted person goes back to their schedule unless a `holds` entry keeps them. Nella's
  hold is in `npcs/the_map.json`, with a `gone_when` for the road south.
* A remembered greeting is as specific as the person's other conditioned greetings. So it is one
  of the lines they may greet you with, not always the first.

### Tests

* `game/tests/unit/test_map_quest_ground.gd` has 3 tests, all passing. It raises what the world
  raises at each place the quests fight at or leave something at: a dressing, a landmark with its
  collision, or a settlement's fabric, on flat ground. It holds to open ground every foe QuestFoes
  stands for the 27 fights, the 45 of the places' own foes those fights count first, and the 98
  finds.
* `game/tests/unit/test_map_quests.gd` has 9 tests, all passing:
  * every settlement has a resident whose work can begin;
  * every place that is not a settlement is somewhere a quest sends you;
  * every point of interest pays off;
  * every hook row is true, and every hook the map wrote leads somewhere;
  * every note can be picked up and read;
  * every objective of every authored quest resolves (more than 300 rows);
  * the map's quests link places and come to a decision;
  * every decision is remembered once the quest is done.
* These pass with 0 content problems and 0 failed tests: test_quest (82, with test_quest_items),
  test_content (43), test_dialogue (48), test_books (6), test_kill_places (12), test_poi (38, with
  test_poi_encounters), test_jobs (12), test_escorts (7), test_social (9), test_recipe_teachers
  (35), test_shopkeepers (7), test_faction_lines (38) and test_inventory_loot (25). Merging main
  mended the loot test's two quest-stage tests.
* The test_settlement filter runs 43 tests, and 3 of them fail. They are world-coupled tests from
  the previous section: test_settlement_people ×2 and test_world_data's settlements out of the
  water. The tracked world still has Merrowby and Tamwick where they were before the map moved
  them, 1.2 to 1.6 km away.
* test_npc: 50 tests, 4 of them failing. These are the world-coupled ones from the last section:
  test_npc_streamer ×3 and test_npcs_in_the_world.
* The journey passes 15 of its 16 steps. The one that fails is "meet somebody who lives here":
  nobody was standing in Merrowby at noon. It is the same world coupling as test_npc_streamer's
  village test, which failed before any of this work. The journey stands at the tracked world's
  Merrowby pad, which is 1.2 km from where the map put the town and its people. It should go green
  with the rebuild, and nothing the quests changed moves anybody at noon.
* The Python atlas tests pass (31). dead_data no longer lists `hook`, which the new test reads.

### Next, in order

1. **Rebuild the tracked world from the atlas** (the land builder's work), then run the
   world-coupled tests and the journey.
2. **The plumbing above, in the settlements stream:** a bounty effect, a talk that closes in its
   own line, and a secret.
3. **Walk three of the quests in the game:** Nella's walk home, the Notch on the Post's branch to
   Pilgrim's Ash, and Cut From Below's fight in the Sunken Barge.

## The plumbing the map's quests were missing

Writing the forty quests that follow the map turned up five gaps in the quest plumbing that bear
on whether the quests play right. The settlements stream owns that plumbing, and it agreed to
these changes and to where they sit (it is changing the dialogue runner's deed offers in the same
file). Each change is opt-in, so the rest of the pack plays as it did. DECISIONS 2026-09-23 ("A
talk waits for its line...") gives the reasons. `game/tests/unit/test_quest_plumbing.gd` holds
all of it in 18 tests.

### What changed

1. **A talk waits for its own line.** A `talk` objective may name a `topic`, which is a node of the
   person's dialogue. The runner says `EventBus.dialogue_node_entered` for every node it enters,
   and QuestLog closes a talk with a topic only on that node. A talk with no topic still closes
   when any conversation with the person ends. QuestWalk checks that the topic is a line the
   person has.
   * All 15 talks in the map's quests now close on their return lines. Three of those lines are
     new: Ushra at Ruddow, Aggie at Hazelwick, and Nella at the Last Camp.
   * Nella's escort now waits until you have said you are ready. Escorts wait for the stage's
     talk with the traveller.
2. **A book read where it lies.** A `read_book` objective may say `in_place`. QuestItems then lays
   the book itself, fixed and with a book to see, at the objective's `where` instead of the copy
   that reads it. Reading it there says `book_opened`, as a book read where it lies always did.
   QuestWalk now counts any book QuestItems lays, which includes the settlements stream's `lies`
   books, such as the one on Willow Isle.
   * Five of the map's books are read where they lie: the Ash Watch night-log, the Pinfold's
     pound-book, Hound Watch's keeper-roll, the Counting Tower's ledger and the slate of names at
     Kharrow's cairns.
3. **A decision can be a crime.** The `bounty` effect (`{"bounty": "theft"}` or `{crime, value, at,
   seen_by, reaction}`) goes through the crime service's own `report_crime`. The person spoken to
   sees it, or the witness the effect names. So the severity, the law of the place's region, the
   report delay, and the lawless regions' ill-feeling that wears off are all the crime system's.
   If nobody sees it, nobody reports it.
   * The crime service now answers `bounty_for`. The dialogue context has always asked it by that
     name and it never had the method. So every `bounty_min` condition and greeting read nought,
     and the Tollmere smith who will not serve a wanted man served everybody.
   * None of the map's 120 options is a crime. The first decision that is one can use the effect.
4. **A giver's offer is a way in.** test_quest_reach now counts a quest that its giver offers at
   their hub, as play always has.
   * The offer nodes written for the map's quests stay. Each carries its giver's pitch, an accept
     and a decline, and each keeps the generic "Is there something I could do?" off the hub. The
     runner offers that line only for quests nothing else starts.
5. **Work from somebody who lives there.** Jobs came only from notice posts and workbenches.
   Settlement.FABRIC puts posts only in towns, cities, villages and forts, so thirty of the
   thirty-nine settlements had no work but a shift at a workbench.
   * The `offer_work` effect has a resident open their place's work, on the same screen a post
     opens. `JobBoard.for_place` returns the post that stands in the place, or else the place's
     carried board: one per place, with no body in the world and nothing to walk up to.
   * All 26 residents the map added offer it: "Is there any work going?"

### Tests

* test_quest_plumbing: 18 tests pass.
* These pass with 0 content problems and 0 failed tests:
  * test_quest (100, with test_quest_reach, test_quest_walk and test_quest_items);
  * test_dialogue (48), test_map (12), test_content (43), test_books (6), test_poi (38);
  * test_jobs (12), test_crime (27), test_escorts (7), test_social (9);
  * test_faction_lines (38), test_shopkeepers (7), test_economy (10).
* test_economy logs one error: a test that adds an item that does not exist, on purpose.
* The merge of main before this work brought the opening's overhead refusal into QuestFoes. So
  test_map_quest_ground now asks QuestFoes itself.
* The merge also moved the Naming's first fight to the Choir, so the hook table was rewritten:
  108 points of interest are now sent to by a quest.

### Next

The quest walker: every one of the 75 authored quests, played end to end in the rebuilt world
through the game's own services, with each decision taken in turn. It waits for the atlas world
in main.


## The land built from the drawing: the atlas builder, what it costs, and what was wrong with it

"Wickmere drawn by hand, and filled to walk", above, is the map: what the cartographer drew and
why. This section is the builder that makes the land from it, which this stream owns. It covers:

* the contract;
* the order the land is made in;
* the faults the full builds of the drawn map showed, and what was done about each;
* what a full build costs;
* what was looked at;
* the tests;
* what is still wrong.

It began as the second half of "The shape of the land" (the recipe evaluation, at the end of
this section). The playtest's verdict on the seeded world turned it into this.

### The atlas is a contract with a check

`tools/world/atlas/SCHEMA.md` is the contract, `atlas.schema.json` its shape, and
`check_atlas.py` what a shape cannot say. The check covers these:

* every region named exists;
* no polygon crosses itself;
* every river ends in water or at another river;
* every place stands in a province of its own region;
* no settlement is in the water;
* every road runs between things that exist;
* an authored pad stands a metre over its water;
* a shelf's notch is on its edge;
* the start is on dry land.

A build checks the atlas first and refuses one with errors. The schema is the coordinator's draft,
finished here (d7973569). The landing added `coast.shelves`, road kind `stair` and `pads`
(f4ab6dfe), and `coast.shelves[].notches` came later (30072bad). The builder and its tests were
written against a first atlas, drawn back out of the committed world (fec9bdf6), before the
cartographer's map existed. Their map replaced it (merged at 987d2ca2, ee4bebc7, 9277caaa and
a72b0458).

### How the land is made, in order

The order is `build_world.build`'s; SCHEMA.md gives it as an author sees it.

1. Each province's ground from its level, relief and character. Borders blend over `blend_m` and
   wander by forty or fifty metres of noise.
2. The ranges at their crest heights, then the peaks, then the valleys.
3. The coast, with its cliffs and shelves, then the lakes, then the drainage by biome.
4. The coast and the lakes again, so the drawn water wins, and the causeways.
5. The upsample to full resolution and the detail band.
6. A pad for every place and point of interest.
7. A saddle under every authored sightline the land stands into by no more than 25 m.
8. The atlas's rivers in valleys of their own, and in gorges where they are held level through
   high ground.
9. Its roads through their `via` points, and the streets. A road to a solid landmark stops at
   its foot.
10. The pads again, and the rivers cut back through whatever was laid on them.
11. Each province's landforms, held off the roads.
12. The shelves' seaward edges broken.
13. Water, textures, colour, points of interest, and the scatter with the atlas's woods planted
    by kind.

The manifest carries the atlas's name and checksum, the start (position, facing, place) and the
lakes. The seed only breaks up the detail: two builds of one atlas are one world.

**Sightlines** (670bf655). The seeded world's land used to refuse the authored lines and the
content was moved to suit it (36 were refused, "Sightlines, answered"). Now the builder cuts a
saddle. Where the ground stands into a line by up to `NOTCH_MAX_M` (25 m), it is cut down under
the line in a notch whose sides rise at 0.6, as a pad is flattened under a place. A line with
more than that in the way is left, and the build says how many. Hidden valleys stay hidden.
On the final build (dbeb9d5f) the builder cut 104 saddles, the deepest 24.5 m, and left none.
By the game's own model (`tools/sightlines.py`, which test_sightlines uses), all 197 lines it can
see are clear and the two hidden valleys stay veiled. The build before refused 28. The
cartographer gave 24 of them new vantages, moved Ghorrow and the Smeltings, and dropped two lines
that no vantage in range could keep.

### What the full builds showed, and what was done

* **The first full build of the drawn atlas was killed at 10.1 GB**, in the texture pass
  (2dad3272). The NoiseBank kept every field it had made. Breaking the 22 provinces' borders
  alone asks for 42 at full resolution (2.7 GB), where the six regions asked for ten. The texture
  pass kept some forty full-resolution patch fields (2.5 GB). The bank now keeps 512 MB, least
  recently used first out, and lets everything go at the end of each stage; the texture pass
  keeps ten. A 512 build made with the caches as committed and again with nothing kept at all is
  byte for byte the same, apart from the manifest's build time. Every stage line of a build now
  ends with its peak memory so far. The next full build peaked at 6.2 GB.
* **The Skerrow dales were combed** (25bfd2a6). From the High Moor down to the Mere's north shore,
  every slope was combed with fine parallel dashes, at 1024, at 2048 and at 4096. The cartographer
  saw it first. **I put it down to the drainage, and that was wrong.** I routed the water over
  five metres of broad noise so it would gather into gills (cb500375). The routing is sound on a
  synthetic dale side (test_erosion.py: 66 gills cross the contour halfway down without it, 12
  with it). But built without any drainage at all, the dales are combed just the same, and they
  are the same without the landforms. Taken apart stage by stage, the provinces' ground is clean
  and the combing comes in with the ranges, and the dales' edges are ranges. `line_field`
  measured each texel to the nearest *sample* of a line, found through a distance transform of
  the samples rasterised. That is the nearest texel holding one, and a few hundred metres out it
  is tens of samples off the foot of the perpendicular. The distance, and the arc position a
  range reads its crest height at, came in steps of a couple of centimetres, and the hill-shading
  showed every step. It now projects onto the segments themselves, and is exact to a millimetre.
  Ranges, valleys, cliffs, causeways, saddles and levees all use it.
* **The Skerrow Wall's sea cliff rang** (25bfd2a6). Where the Wall stands 470 m out of the sea in
  the north-west, the cubic upsample from 2048 undershot the seabed by 70 m: 210 pits down to
  -96 m, 915 texels under -30 m. The upsample is now held inside the range of each coarse
  texel's neighbours.
* **The landing's edge was still the clean arc it was drawn as** (30072bad, ef3c2487). The
  coordinator's note was that a perfect arc of rock two hundred metres across will look made at
  ground level. `break_shelf_edges` now runs last, at full resolution:
  * the drawn edge wanders up to 7 m in and out, as spurs and bites 30 to 90 m apart;
  * blocks fallen from the face lie in the water at its foot, 3.5 to every hundred metres;
  * a notch is cut where the Oroth stair leaves the shelf, at (44, 3902) on the line from the
    camp through the pad. It is a slot 8 m wide, 4 m into the shelf, its floor falling into the
    sea;
  * nothing comes within 3 m of a pad.

  It took four full builds to get right. On the first only the notch was cut: the breaking was
  faded out toward the coast polygon, and the Hushline's coast has a lobe over the whole shelf.
  On the second, faded toward the ground standing over the shelf instead, it broke the back edge
  too, where the stair comes down the bank at the shelf's own height. That cut a 6.5 m hole of
  sea through the stair's last step onto the landing (6217880f). Now only an edge with the sea
  beyond it is broken, and no road is touched. On the third the bites stopped at the drawn line,
  and the coast's band of land just outside it stood as a rib of the old arc with pools behind
  it (d4cd96ca). A bite now takes everything seaward of the wandered edge. The edge is measured
  to the drawn line exactly, and the outline is cleaned of texel specks. At 2048: no rib texels
  and no pools, against 28 and 11 on the third build. An authored pad's skirt no longer fills
  the drop below it; blended over the face, the Hushline Stair's pad had filled the sea at its
  foot to a lip at sea level. The opening's builder needs no change: its Oroth stair starts where
  the ground first falls a metre along the camp -> pad line, which is the notch's inner end. On
  the final build the ground first falls a metre at (43.8, 3897.7), the pad is dry at 4.00 m over
  its 26 m, and the Stair is 646 m long from 107.66 m down to 4.00 m, no steeper than 0.58, with
  its ground within a metre of it and no water under it. The Hushline's own pad, which the
  cartographer moved onto the landing beside the Stair's, is dry at 4.00 m over its 20 m.
* **Rivers hung in the sky** (3aced4f4). A ground capture of the Lower Dales had a river ribbon
  across the sky. `rivers.json` gave each river only its water at its two ends, and the game drew
  the ribbon on a straight ramp between them. A seeded valley river falls about evenly, so the
  ramp was near enough. The drawn Skerrow Water falls from the Hidden Tarn at 520 m down Kharrow
  Gorge and runs nearly level to the Mere, and its ramp stood 158 m over the dales. Four more
  stood 126 to 157 m up, and the Wold Water 84. A river now carries `surface_m`, its water at
  every point, and `WaterSurface` draws on that (CONTRACTS 6). Two rivers still stood off their
  ground on the build after, the Blackgill by 26 m and Weaver's Gill by 29 m, each over a hollow
  it could not climb out of. **The commit says the Blackgill's 23 m is a sightline saddle cut
  across its course. That is wrong.** Built with no saddle allowed within 30 m of a river, it is
  23 m just the same. It is the hollow under the Blackgill Falls, which the river had to climb
  out of to meet the Skarl Water. The cartographer ended both rivers in pools under their falls.
  On the final build no river stands more than 11.1 m over its ground. The worst are a point or
  two at the heads of four becks on the steep fell under the Wall, and I have not traced those.
  It is not the landforms: a build without them floats the same.
* **Rivers ran in slots** (304d5df9, bfb36896). The build after showed, from above, that the
  rivers leaving the dales ran in rectangular trenches. `carve_river_valleys` held the land beside
  a river under its valley side out to half the valley's width, then faded back to the untouched
  land over the last fifth of it: eleven metres, for a beck nine metres wide. Where a river is
  held level through a ridge, the fade was a wall.
  * The Brindle Beck ran through the dales' southern ridge in a trench 95 m wide. At
    (-1080, -1900) its walls fell from 118.6 to 63.7 m in one 9.4 m step.
  * The Rudd Beck and the Rib Beck ran in trenches like it.
  * In the Skarl fells ground frame, a straight dark wall ran beside the river.

  Past the valley, land still over the valley side is now a gorge the river has cut. Its wall
  climbs on at 1.2 until it meets the land. Cut as a plane, that was a smooth ramp a hundred
  metres across, so the wall's line also wanders in and out by 10 m over a few hundred metres,
  as spurs and gullies, and its face has 1.2 m of grain. On 1024 builds, the land within 80 m of
  the Rudd Beck steeper than 1.5 went from 3.5 ha (steepest 6.9) to 1.9 ha (3.9). The Skarl
  Water went from 3.2 ha (7.5) to 0.9 ha (2.8), and the other becks by about half. What is
  still steep is where the atlas draws it: the falls, and the head of Kharrow Gorge.

  The gorge carve first measured every texel to the nearest point of its river, and the land
  behind a river's source is nearest to the source. So a beck rising under the Wall cut a bowl
  into the fell behind its head (4d9e9b64). The Rudd Beck's bowl took the Fallen Hand's knoll,
  80 m up the fell, from 471 to 459 m. That was after the saddle under its line to the Rudd Pike
  Beacon had been cut to the knoll's first height, which left the one line the game refused on
  that build. A valley now comes in down its river from the source, and the land behind the
  source is left alone.
* **The Stair Path ran into the Choir's head colossus** (31aef010). The atlas-readiness run of the
  game found it. A road ended at its place's own position, and the Sunken Choir's head colossus
  stands on the Choir's, 27 m across at the foot. A road to or from a place with a solid landmark
  on it now stops at the landmark's foot: the widest its model's bounds reach across the ground,
  and 3 m for a body. On the final build the Stair Path ends 16.5 m from the Choir and is 542 m
  long, climbing from 107.7 to 129.5 m and no steeper than 0.16. The roads to the Lamp, the
  Fallen Hand and the Drowned Nave stop at theirs.
* **The two new pools flattened the country round them** (dbeb9d5f). A lake's shore is shaped
  over a few hundred metres: the shingle, the bank back to the land by 320 m, and the ground
  within 700 m held over the water. That suits the Mere. The cartographer drew the Blackgill Pot
  and the Weaver's Linn at the feet of falls, 22 and 29 m across their radius.
  * The linn flattened a basin three hundred metres across into the wold, 187 m deep at most, and
    its fall went with it.
  * The pot raised a valley 380 m away by 109 m.

  A lake may now give `shore_m` (default 320), and every one of those distances scales with it.
  Both pools are drawn with 40, and the other seven lakes are built exactly as they were.
* **Three of the build tests failed on the drawn atlas, and the builder was at fault in one.**
  * test_cells_cover_the_world: a Sedgemire grass tuft at x = -2304.004 was filed by its
    unrounded position in cell 6, and written as -2304.0, which is cell 7's ground. On a 1024
    build, 159 of 4.1 M rows were in a neighbour's cell file. Everything that files a row now
    files it by the position as written (`Grid.written_cell`, 3c2e8dda). On the final build, 0
    of 3.97 M rows are.
  * test_texture_rules looked for lake bed within 150 m of each lake's middle. The drawn tarns
    are about a hundred metres across and their water begins thirty metres inside the line, so
    the window was mostly shore. The window is now half as wide as the middle is deep in the
    lake.
  * test_determinism gives each of its two 512 builds ten minutes, and the drawn atlas's scatter
    alone took 429 and 839 s of the two run by hand, since its candidates are drawn in metres.
    Those two builds were the same in every file, cells and all. The test only ever compared
    the heights, and now builds heights only (bd112f73).
* **A group of ash wights stood 46 to 49 m from the way out of the start** (76c25c8b), where
  the opening keeps 50 m clear. The atlas-readiness run of the game found them. No group now
  stands within 50 m of a road out of the start, counting the 12 m its members stray.
* **The lake shaping flattened what the atlas drew at its shores** (3ef9c4c6). The Gull Cliffs,
  a range drawn at 40 m along the Mere's north shore, came out at 24. The Spire Rock, a 32 m dome
  at Tollmere's high end, came out at the island's own 15. A range now keeps its height to 25 m
  from the drawn shore and drops into the water over the last 25. A peak drawn in the water
  stands out of it.
* **Beside a lake the landforms dug dry pits under its level** (ee34ee5f): 7.7 m by the
  Blackwater Tarn, 2.9 m by the Hesk Pool. They were the High Moor's shakeholes and the Ashgrid's
  sunken streets. Within 300 m of a lake a landform now stops half a metre over its water.
* **A lake's water begins some thirty metres inside its polygon**, not at it. The cartographer
  found this, drew to it and placed the shore towns against it. I tried moving the water out to
  the line: the median came down from 16-32 m to 0-4 m. I put it back, because the map is
  finished, and every lake would have grown by thirty metres all round under it. SCHEMA.md now
  says what the builder does.

Found while the builder was first written, and fixed then:

* a one-texel trench of sea round every map edge the land ran off;
* a lake bed rising over its level;
* a river's banks raised in the lake its mouth ran into;
* a range's pass lowering the next range across it;
* a stair corner cut down the fall line at 1.5;
* the detail band roughening a shelf by 1.4 m;
* a shelf left with sea behind it.

### What a full build costs

`./run.sh world` at dbeb9d5f builds at 4096, 2 m a texel. Run through `build_measured.py`,
which reads the process's peak resident memory:

| stage | seconds | peak so far |
|---|---|---|
| regions | 105.2 | 1.8 GB |
| heights | 86.8 | 2.2 GB |
| sightlines | 0.3 | 2.2 GB |
| rivers | 11.9 | 2.9 GB |
| roads | 41.3 | 2.9 GB |
| water | 74.6 | 2.9 GB |
| fields | 6.1 | 2.9 GB |
| textures | 70.2 | 5.5 GB |
| colour | 14.1 | 5.5 GB |
| scatter | 612.9 | 6.2 GB |
| hedges | 10.4 | 6.2 GB |
| write | 18.8 | 6.2 GB |

The pads, landforms and encounters take under a second each. The whole build is 1054.6 s of wall
time with a peak of 6.20 GB. The four full builds before it took 972 to 1049 s at 6.19 to 6.22
GB. It makes 3.97 M scatter instances, heights from -24.2 to 784.1 m, and water over 17.0 percent
of the map. The build writes 494 MB, and Terrain3D's import of it is 146 MB and a minute.

The seeded world built in 280 s with 3.48 M instances, so the scatter is now what a build costs:
613 s, 58 percent of it. It costs about as much at any size, because its candidates are drawn in
metres and not texels: two whole 512 builds spent 429 and 839 s in it, on a quiet machine and a
busy one. That is most of what the Python tests' own builds cost. I have not measured why. The
likeliest cause is that each province draws its candidates over its whole bounding box, once for
every flora rule, rock rule and kind of wood it has. Twenty-two drawn provinces with wandering
borders have far larger boxes, all told, than six regions had.

### Looked at

* **From above**, the final build's hillshade: the whole map at 8 m a pixel, the Skerrow dales at
  2 m, the four gorges, the two pools, the landing and the Choir's avenue at 1 m, and the
  Thornmarch's scarp.
  * The northern range stands as a row of snow-capped massifs with cols between them, as drawn.
    From above, the cols are straight bands across the range's width, evenly spaced: each is a
    low point on the crest line, and the massif profile carries it straight across.
  * The dales' slopes are rough, and nowhere combed.
  * The landing's seaward edge wanders, with the notch at the stair and blocks in the water
    under it.
  * The saddles show from above as straight grooves, a few hundred metres long, across the dale
    sides.
  * The gorges' walls are slopes now, not steps, and their line wanders. But a valley cut
    through high ground has a smooth floor a hundred metres wide in rough fell, and from above
    that still reads as made (under what is still wrong, below).
  * The Weaver's Linn and the Blackgill Pot are open water at the feet of their falls.
  * The Thornmarch's scarp now bends in and out down the east side.
* **At ground level**, from the final build: the start, the landing to the sea and to the cliff,
  the lower dales to the Wall, the Skarl fells, and up the Brindle Beck's and the Rudd Beck's
  gorges.
  * The lower dales' river ribbon is gone from the sky, and the Three Sisters' fall shows at the
    dale head.
  * Beside the Skarl Water the straight dark wall of the old carve is gone.
  * Up the Brindle Beck the gorge reads as a steep valley side, not a trench.
  * The Rudd Beck frame stands too low on its bank to show the gorge.
  * An eighth frame, of the Blackgill Pot, did not come back. The capture waited half an hour on
    it and was then killed for memory with the machine full, so the pot was looked at only from
    above.
* **The capture plans** were made again on the final build (445fb563, 45bbb137).
  * The Briarwold's approach camera stood inside an oak's crown, because no spot on its bearing
    out of Fernhold was clear at 28 m. It now goes over the tallest crown round it.
  * The Briarwold's vista, raised over its own crown, still looked through two taller oaks. It
    now climbs until its first 70 m are clear.

### Tests

With the final build installed:

* **The whole Godot suite** (`res://tests/run_tests.tscn`): 1624 tests, 6 failed. Each is the
  game reading the rebuilt world, not the builder:
  * test_world_data.test_rivers_and_roads_are_sane. Its river widths (4 to 14 m) were written for
    the seeded world, and the drawn rivers run 2 to 24 m. It also wants more than eight points
    on every river, and Weaver's Gill now has six. The atlas-readiness branch widens the ranges
    (709f9908) and holds a river to its drawn line instead (2719f516).
  * test_the_start.test_the_stair_head_is_a_camp_with_the_warden_s_place_in_front. It raises the
    Stair Head only from the points of interest the world has no pad for, and the rebuilt world
    has one.
  * test_the_start.test_the_hushline_landing_stands_clear_of_the_water_with_its_wights_on_it. The
    atlas-readiness branch reads the landing where the land holds it (dc9acdc9).
  * test_pois.test_every_poi_in_the_world_raises_a_dressing. The Blackgill Falls raise a
    hearthstone the data does not give them.
  * test_poi_people.test_nobody_is_stood_inside_anything. The hermit of Willow Isle stands inside
    the isle's masonry.
  * test_kill_places.test_nobody_is_stood_inside_the_choir_s_colossus. The Naming's three
    ash-wights are not all stood at the Choir once its colossus is solid.

  On the same build, the atlas-readiness branch (2a3be507) passes all six: 709f9908 for the
  rivers, the Stair Head, the Blackgill Falls and Willow Isle, 2719f516 for the rivers' points,
  and dc9acdc9 for the landing. Its run also passes test_kill_places, 13 of 13. They clear when
  the two branches merge.
* **The Python tests** (`python3 -m pytest -q tools/world/tests tools/tests`), module by module:
  * The tests that build no world: 95 passed, 3 failed. The three are test_glb_textures on the
    characters' part files (pauldrons.glb's meta says 6441 triangles and the file holds none),
    which this branch does not touch.
  * test_roads: 19 passed, 2 failed on the final build.
    * test_no_river_is_dammed: the heads of the Cressbourne, the Blackgill and Weaver's Gill were
      dry. That is fixed after the build (993e24d2): a beck two metres wide at its head is one
      texel wide, on the diagonal its texels meet only at their corners, and the water mask's
      speck filter counted them side by side.
    * test_the_carved_land_is_the_graded_road: at five roads the land under the road is 2.7 to
      4.6 m off its graded level, mostly under it, where 2.3 to 3.6 is allowed: Pilgrim's Ash -
      Ashwell, Elderhold - the Skarl Bridge, Kharrow Gate - the Ruddale Bridge, Ruddow - the
      Fallen Hand, and Merrowhithe - the Rib Cathedral. On the Rib Cathedral's road the land is
      under even the ground the road was graded against. None of the points is near a pad, a
      river's banks or a sightline's corridor. Not traced (below).
  * test_atlas_world: 16 passed and 1 failed. test_every_river_falls_to_the_water_it_runs_into
    held the Blackgill's mouth to its pot's level, and at the test's 16 m texels the Blackgill's
    head comes out under the pot. The test now holds such a river to ending under its lake
    (ae918839). Rerun, its heights tests pass (8).
  * test_build: its own 1024 build ran past the test's 900 s on the busy machine, and every
    test errored. The whole-build timeout is now 2400 s (dabe9dbc). Rerun, the build took 21
    minutes, and 15 of 16 passed, test_cells_cover_the_world and test_texture_rules among them.
    test_rivers_run_downhill_into_the_water wanted eight points in every river, and Weaver's
    Gill has six. It now holds a river to its line: two points or more, and no gap over 30 m, as
    the atlas-readiness branch does in the game (2719f516). Every river of the head's builds
    meets that. It has not been run again.
  * test_recipes: 6 passed. The cover build at 256 ran past the old 900 s, and has not been run
    again at 2400.
* This pass added test_land_lines.py, test_shelf_edge.py, test_river_valleys.py and
  test_lake_shores.py, the landing's tests in test_atlas_world.py, the routing test in
  test_erosion.py, LandmarkFootTest in test_roads.py and CellFiling in test_build.py.
* Three merges on this branch (8535061e, 8bbfaae1 and 6f2af960) carry no session trailers.
  Adding them would mean rewriting history others have merged from, so they stay as they are.

### Rebuilding the world

`./run.sh world`, with no recipe: the atlas is `tools/world/atlas/atlas.json` and the seed is the
pack's (8471). It builds into `game/world/generated` and imports the terrain. Nothing else is
asked for; `cover` stays off. On a machine other things share, build outside the checkout and
install the result (05937961):

```
tools/world/build_when_free.sh /tmp/w /tmp/w.log   # waits for 10 GB; 17 to 18 minutes, 6.2 GB
tools/world/install_world.sh /tmp/w                # into game/world/generated, then the import
```

The capture plans `default.json`, `horizon.json`, `pois.json` and `look.json` were made again on
the final build (45bbb137). If main's places differ when the world is rebuilt there, make them
again (`make_default_plan.py`, `--horizon`, `--look`, `make_pois_plan.py`): every camera stands on
the ground as built.

### What the atlas still owes

The cartographer answered what the build before this one (w_final4, 3aced4f4) left for the atlas
(merged at 63458fea):

* 28 authored sightlines the land refused by more than a saddle's depth. There are new vantages
  for 24, Ghorrow and the Smeltings moved, and two lines with no vantage in range were dropped.
* The Heron Watch stood 8 m from the North Channel, half its disc river. It is now 35 m off.
* The Blackgill fell into a hollow under its falls and stood 23 to 26 m over the ground, climbing
  out to meet the Skarl Water. It now ends in a pool under the falls (`blackgill_pot`).
* Weaver's Gill stood 29 m over the floor of Fern Gully under its fall. It now ends in the
  Weaver's Linn at the fall's foot, and the gully below is dry.
* The Thornmarch was one straight line at x = 3965 for 7.5 km. Its crest wanders now.
* The Hushline stood in the sea, where the escort to it could not finish on foot. It is on the
  landing now, with a pad of its own beside the Stair's.
* The way from the Stair Head to the Choir was 980 m. It now goes over the knoll's neck and up
  the avenue of colossi, and on the final build it is 542 m.
* Some people's days walked them across water. They no longer do.

Nothing the builder found is still the atlas's. Of what the cartographer's answers left:

* **Grandfather Hollow's roads and street run into the Grandfather.** The town and its tree share
  one position, (2750, 450), because the town is inside the tree. The tree is solid, and its model
  reaches 38.8 m across the ground. All four of the town's roads, and its street, run to the
  trunk. No test covers it: test_the_start only looks within 800 m of the start. The builder can
  stop them at the tree's foot as it now does at the Choir. But the street is laid only where
  roads end at a settlement's centre, and the exterior builder lays its plots along it, so where
  the town's houses and its way into the trunk stand is the game's to say first.

### Next, in order

1. **Merge this branch and rebuild the world in main** with `./run.sh world`. The branch head
   builds the final build's world with the heads of the narrow becks wet (993e24d2). Then run
   the Godot suite with the atlas-readiness branch's tests, and the Python tests.
2. **The land under five roads is off their grade** (test_roads, above). Trace it on a
   4096 build: the heights after the road carve and after each stage that follows it, at the
   points the test names.
3. **Grandfather Hollow** (above): the game's layout first, then the builder's stop at the tree.
4. **A valley carved through high ground has a smooth floor.** The valley and gorge carve replaces
   the land with a smooth surface, so the floor has none of the detail band's roughness. Give it
   the same grain as the gorge wall's.
5. **The heads of four becks** float a point or two over their ground, by 9 to 11 m: the Rib Beck,
   the Brindle Beck, the Oskel, and Weaver's Gill at its source. Trace it; the landforms are
   ruled out.
6. **The build's time.** Measure where the scatter's 613 s go before changing anything. Drawing
   each province's candidates only over its own texels is the first thing to try.
7. **The recipe `cover`** is still off, and with it the wind-bent willows and limes. Its drop test
   was taken on the seeded world, so it wants taking again on this one, and looking at from the
   ground, before it goes on.

### Before the atlas: the landforms and the cover, looked at

This pass began as the second half of "The shape of the land": the landforms and the regional
cover had been built and measured and left off, because nobody had looked at them from the
ground or put them through the drop test. That was finished before the direction changed, and
**the recipes stayed off.** Two full 4096 builds were shot in full (the 42-shot sheet and the
three-shot horizon, each on a plan made from its own world), and every frame was looked at side
by side:

| | default (the committed world) | landforms + cover |
|---|---|---|
| drop test: colour / landform / together | 0.90 / 0.31 / 0.90 | 0.95 / 0.19 / 0.90 |
| landform, image by image | 13 of 42 right | 8 of 42 right |
| worst frame | `hearthvale_street`, 1508 draws, 1.45 M primitives | `hearthvale_street`, 1482 draws, 1.45 M |
| road tests | pass | two fail (below) |

The bar was that the landform axis rises and nothing else falls. Landform fell, from 13 images
read right to 8, and image by image the fall is not significant either: nine read right only on
the default world and four only on the recipes world, an exact McNemar p of 0.27. Colour's rise
from 38 to 40 is not significant (p 0.50). Together is 38 on both. Seven images a region cannot
resolve a change this size. They are seven *kinds* of frame, and a street in Sedgemire looks more
like a street in the Briarwold than like Sedgemire's own vista, so the landform signature mostly
measures that. From the ground, some of the landforms now read. The levees in Sedgemire and
Brightwater's dune ridges read best. The Briarwold's granite stair was worse than nothing up
close, a dark mass filling a third of two ground shots.

**Where the landforms went.** They are no longer a recipe. Each province in the atlas lists its
own (`landform` in SCHEMA.md), and the cartographer chose them: scars and shakeholes in the
dales, buried streets on the Ashgrid only, levees and oxbows in the delta, the granite stair and
tors in the wolds, raised beaches and dune ridges round the Mere, barrows and lynchets on the
downs. They are built wherever the atlas names them. The drop test above is the only measure of
them there is, and it was taken on the old world. `cover` is still a recipe, still off.

**The landforms go on after the roads.** On the recipes world two road tests failed, and the
cause was the order of the build. The router saw the landforms. It took the road from Gullhithe
up to Kharrow Hold straight over a limestone scar: 20 m of rise between two road points 7 m
apart, with the carved land 4.85 m off the grade against 3.6 allowed. It also laid a road along
the lip of a granite step, 9.4 m above the ground either side. The heights now come back from
`compose_heights` with the landform apart. The pads, rivers and roads are laid on the land
without it, and the landform goes on last, held off every road out past its carve
(`landforms.road_clear`). The atlas builder keeps that order.

**Three small faults and two cameras**, all committed before the atlas (b671e069, e8cc8586,
4dfbea85):

* The Clanless Camp's line from Brindlecrag cleared by 0.03 m on every build. A camp that is a
  POI had a 30 m pad (the size a hamlet gets without its houses), and flattened to its knoll's
  median it filled out over the slope into the line. Its pad is 22 m now (`roads.CAMP_PAD_M`).
  A camp that is a *place* keeps 30.
* Foxfire Falls -> the Charcoal Camp cleared by 0.08 m. The camp moves 6 m west, where its pad
  sits 3.8 m higher.
* Pilgrim's Ash lost its cross street, because its side road now arrives 64 and 50 degrees off
  the through street's legs. The threshold is 49 degrees (`CROSS_STREET_DOT`).
* The Cold Fire's camera in `plans/pois.json` looked at ash where the camp used to be.
* The Briarwold's first ground shot photographed bark: a giant oak 12 m off, a quarter-turn from
  its look. A ground shot now also asks that no tree stand in the front hundred degrees of its
  view nearer than 1.2 times its crown's reach (`Scatter.view_clear`), and
  `test_capture_plan.py` holds the committed ground shots to it.

**Wind-bent trees: a contract change.** CONTRACTS section 6 gains two optional fields on a
scatter row: `[x, y, z, yaw_deg, scale, tint_hex, lean_deg, lean_toward_deg]`. Old six-field
rows read as they did. The streamer applies it (`WorldStreamer.instance_transform`, with a unit
test). The rules that lean are Brightwater's pollard willows and limes, which are in `cover`,
so the default world has no bent tree yet.
## Atlas readiness: what remembers a coordinate instead of a place (2026-09-23)

The user asked for a hand-drawn world. The cartographer's atlas moves 83 places and POIs and
adds 216; the land agent builds the world from it. When that world replaces the tracked one,
anything in the game that wrote down where a place *was* is wrong. This round found every such
thing, made the ones that should follow a place follow it, and ran the game on the atlas world.

### The inventory

`docs/COORDINATES.md` sorts every world coordinate the game, its content and its tools hold into
three kinds:

* **Derived from a place**, and already following it: the opening cinematic (every key is a
  place, a bearing, a distance and a height), the start, NPC homes and schedules (a place and a
  named spot), quest markers, kills and escorts, encounters, door plan rows (a ring round the
  place), sightlines, and the journey, flow and perf probes.
* **Literals that should follow a place**: fifteen door plans that copied their place's
  position, the Stair Head's way (18 map points), five hand-written capture plans (48 points),
  five kinds of saved position, the map screen's default centre, the UI review's fake player,
  the chart's region names, and coordinates in eleven test files.
* **Legitimately absolute**: the places' and POIs' own positions (the map itself), the atlas and
  the built world, the map frame and cells, interior pockets, the regions' no-world fallback
  centres, in-flight crime records, and test fixtures off the map or on synthetic ground.

### The conversions

| What | Now | On main's world |
|---|---|---|
| Door plans | name their place only; `WorldDoors` reads the place | the same 15 centres |
| The Stair Head's way | a `shape` between the camp and the Choir (`PlaceRef.along`); along the built road where the world has one | the 18 points to 2 mm (main has no road there) |
| Capture plans by hand (streets, start, opening_scout, gait, roll) | `{place, bearing, distance, height}` specs, resolved the way the cinematic resolves its own | within 7 mm of the old points |
| Saves: the player, the Hearth's landing and Echo, an interior's way out, an escort on the road | a `near` pin: nearest place, where it stood, height above ground | a load with no move is exact |
| Map screen default centre | the `start_hub` place | Merrowby, as before |
| Chart region names (`gen_map.py`) | deep inside the region's mask, nearest its own places, whole and off the compass rose | not regenerated |
| Tests | `TestCase.at_place`. The Mere is found as the deepest water at the lake level, the northern wall behind Windgate, each region's height as its mean over its own mask, "far away" as the emptiest grid point | pass |

`PlaceRef` (game/systems/shared) holds the specs and the pins. `test_place_ref.gd` (15 tests)
moves places the way a redrawn map does and checks that each of the above follows. It also fails
when a definition holds coordinates where a place belongs. Four tools come with it:
`tools/place_paths.py` and `tools/capture/relative_plan.py` turn coordinates into places,
`tools/coordinate_scan.py` lists what is still coordinates, and `tools/world/place_checks.py`
reports what a new build's ground does to the places. `tools/world/use_build.sh` runs the game
on a build without committing it.

### On the atlas world

The land agent's builds were installed in this worktree only and never committed. Its branch
was merged here (to 3aced4f4); it had followed the move by editing coordinates, and the merge
keeps the places instead. The first build, w_final, found five things in the game:

* **The Stair Head's waystones walked a line of 37 to 61 degrees.** The drawn way went straight
  down the knoll; the builder routes its road round it. The waystones now stand along the road
  where the world has one (`WorldPois.road_between`), and the drawn shape is the fallback.
* **32 of the Stair Head's colliders named no surface.** The atlas is the first world to give the
  camp a pad, so nothing had asked what its flights of steps sound like. They are stone.
* **Blackgill Falls stood a Hearthstone its data does not ask for.** The terraced falls raised
  one on their first ledge whatever the data said.
* **Willow Isle's hermit stood inside a hill.** The atlas draws the isle as land. The builder
  heaped a second isle on top, and the stool's marker ended up inside it. A drawn isle is not
  heaped over, and every prop and the marker stand on the surface they are on.
* **The Hand's camera came 1.0 m inside its 3 m clearance** at (883, 400, -3129), where the
  Skerrow Wall rises between the shot's two keys. Both keys go up 3 m.

On the last builds (w_final3 and w_final4, atlas crc d0206101):

* `./run.sh test`: 1,599 tests, **1 failed**. The waystones' walk from the Stair Head to the
  Choir is 980 m, and DESIGN 5.1a's "a couple of minutes" is 300-650 m. The camp stands on a
  110 m knoll, the heath between is at 62-80 m, and the Choir's plateau is at 130 m: the atlas's
  to answer. All 24 doors land both ways, and every interior holds what it should.
* `./run.sh journey`: 16 of 16. `./run.sh fights`: 66 fights, 0 checks failed.
* `./run.sh flow`: the same 10 of 88 checks fail as on main's world, all after the opening holds
  on its third shot (2 of 10 shots, 601 s to the skip). The body stands at the atlas's start,
  (10, 108, 3670), with all 9 near cells in. The Godot process peaked at 2.6 GB. One run on
  w_final2 was killed by the machine's memory limit while five other Godots were up.
* The hand-written start plan, photographed on the atlas world, frames the camp, the Warden and
  the Choir on the skyline from the new Stair Head. Nothing in the plan was edited.

For the map rather than the game, sent to the land agent and the coordinator:

* Heron Watch (-2460, -640) stands in the North Channel: water 3.3 m over ground 2.5 m.
* Schedules across water: Jory Wick's Gullhithe to Tollmere leg crosses 1,085 m of the Mere
  (728 m on main's world too). Wat Thatcher's Pilgrim's Ash to Merrowby leg crosses Lark Pool,
  76 m at (204, 2536) to (207, 2459), and 44 m more.
* The authored sightlines: 171 of 201 honoured, 28 refused, 15 POIs no vantage sees
  (`tools/world/tests/test_sightlines.py` fails).
* The generated capture plans (default, pois, look, horizon) were made for an earlier atlas build
  and fail `tools/tests/test_capture_plan.py` until they are made again. The land agent has fixed
  the one camera that failed even after regenerating (briarwold_vista, a5dfed74).

### On the final atlas build (w_final5), with main merged

Main (ef226622) and the land agent's last commits (45bbb137) are merged here. Main brought the
opening's wall clock and the Stair's landing. The land agent brought the Stair Path up the
Choir's avenue, roads that stop at a landmark's foot, and the capture plans made on the final
build. w_final5 (from dbeb9d5f, atlas crc e11343a1) was installed in this worktree only and
taken out again after the runs. Two more game-side fixes came of it:

* **The Stair's wights on the land.** Main's landing test looked for a raised shelf's collider
  under each wight. The atlas draws the landing as ground under the cliff, so where the landing
  is not raised the test now reads the terrain there.
* **A river is a line, not a count of points.** test_world_data wanted more than eight points in
  every river, that is, a river longer than about 160 m. The atlas's Weaver's Gill falls into its
  linn after 93 m. A river now needs two points and no gap longer than 30 m in its line.

Results on w_final5, one Godot at a time:

* `./run.sh test`: 1,639 tests, 1 failed in the run: the river count above, fixed and rerun green
  (test_world_data 14 of 14). The world-coupled files: 167 of 167 once that is in. All 24 doors
  land both ways, and all 24 interiors hold what they should.
* `./run.sh journey`: 16 of 16.
* `./run.sh flow`: **PASS**, all three starts (a new game through the Naming and the opening,
  --load, Continue; Continue alone is 35 of 35). The opening no longer holds on its third shot.
* `tools/world/place_checks.py`: nothing. The Stair Path is 542 m (DESIGN's 300-650 m), and
  nothing that fights stands within 50 m of it. No place stands in water, no door on water or a
  cliff, no schedule or escort crosses water, and no quest place is out of reach of dry ground.
* `tools/world/tests/test_sightlines.py`, `tools/tests/test_capture_plan.py`,
  `tools/tests/test_relative_plan.py`, `tools/ui/tests/test_gen_map.py`: 25 of 25.

Everything the atlas owed from the earlier builds has been answered by the cartographer and the
land agent: Heron Watch in the channel, the two schedules over water, the refused sightlines,
the 980 m way, the ash-wights by the road and the road through the Choir's colossi. The game
needs nothing more for main's world to be rebuilt from the atlas. After the rebuild, run
`tools/world/place_checks.py` and the generators docs/COORDINATES.md lists.
## The first minute heard, the Warden answers, tents that stand, and the slow machine's other clocks

Six things the opening's work left weak, then what the user's playtest of main 6985d356 found at
the start: talking to the Warden did nothing, the tents were nonsense, and the camp was sparse.
Then the flow's skip check under load. Each is measured with the tests it names, then the full
suite, the journey and the flow on the final tree, merged with main.

### 1. The title and the Naming play their music

The user's first minute was silent.

**Cause.** The music director has always brought up the title's theme on a menu called
`main_menu`, and the Naming's own piece on `character_creation`. Its test says so by emitting
those menus by hand. But the title and the Naming are scenes of their own, changed to with
`change_scene_to_file`, not menus `UI.open` puts on its stack. Nothing ever emitted either name.

**Fix.** Each screen now says it is up when it stands and gone when it goes
(`EventBus.menu_opened` / `menu_closed` with the id the director listens for). The director now
reports which piece its overlay is playing (`Music.overlay_playing()`).

**Checks.**
* `test_music_director` stands each screen up the way the game does, hears its piece start
  (`core:music/main_theme`, then `core:music/naming`), and hears it stop when the screen goes.
* The flow probe checks both screens as a player reaches them.

### 2. A ring with no room stands its fight further out

When QuestFoes found no clear spot in its ring (9 to 22 m round a fight's place), it stood the
foes at the place's middle. The middle of a landmark is inside it. Now:
* the rings further out are tried, 4 m apart and 16 bearings each;
* they go out to 60 m, or to the objective's own radius less a pace, so the kill still counts
  where they stand (KillPlaces, 140 m by default);
* foes that find no spot of their own stand a pace from a spot that was found, or on it;
* only when nothing within reach is clear does the fight go to the middle, and the log says so.

`test_kill_places` holds two places, with every spot outside the solid, clear by QuestFoes' own
test, and within the radius:
* the Choir, with its colossus grown to cover the whole ring;
* the Headless Watch, on a crag as wide as the ring.

### 3. A quest is at its first stage when it says it has started

`QuestLog.start` announced a quest while its stage was still -1, and whatever the announcement
woke read that. An npc held on the quest's first stage was let go for that moment, and the
registry took the Warden's body away on every new game. The record now stands at its first stage
(`stage` 0 and the first stage's id) when `quest_started` goes out. `_enter_stage` enters it
properly just after, as before, with its journal and effects.

**The new-game hook's extra look round is gone.** It had asked the NPC streamer to stand the
Warden up again after the story started, and nothing needs it now. `test_cinematic_player`'s
hand-over test still finds her at the start on the first frame of control without it.

`test_quests` holds the stage the quest is at when the announcement is heard.

### 4. The people, a stage's foes and a reach look round on the wall clock too

Three polls counted game time:
* the NPC streamer's look round (0.75 s);
* QuestFoes' check for fights to stand up (1 s);
* the quest log's check of where the player has reached (0.5 s).

On a machine drawing a frame every few seconds the engine counts each frame as an eighth of a
second, so these came round every 6 to 30 s. That is the same slow motion the opening had. All
three now go through `PollTimer` (systems/shared), which fires on whichever clock gets there
first: the wall on a slow machine, the engine's count in a fixed-rate run that simulates faster
than the wall.

`test_npc_streamer` gives the streamer one long frame the engine counts as a millisecond, and
checks that a look came round.

The escorts' look (0.25 s) is left on game time. It only notices an arrival or somebody left
behind, and a slow machine notices a moment late.

### 5. Words that have to be read fade on the wall clock

A Tween runs on the engine's delta. These fades now run on `WallTweens` (ui/lib), a Tween paused
and moved on by the time that really passed:
* the opening's lines, title card and skip prompt;
* the HUD's subtitle, which carries the Warden's first words.

On a slow machine they had inked in over several frames, so the frame the player looked at had
the line half-in. On a quick machine the two clocks agree. A new HUD subtitle now kills the last
one's fade rather than racing it for the label.

`test_words_keep_time` gives the words one long frame and reads the ink.

ARCHITECTURE §9 now says it plainly: anything a player waits on or reads is timed on the wall.

### 6. The stars at dusk, and the dotted line

Both are in the sky, which is the painted look's. I have told that stream and changed nothing.

**The stars.** The opening's Toll shot is Hearthvale at 18.2 h, with the sun at -6.5°. Three
things meet there:
* `Atmosphere.SUN_KEYS` gives the stars half strength; they already start at -2°.
* `night_of` is 0.95, so the exposure is pushed nearly to the night exposure (×1.3), which lifts
  the twilight to a bright rose.
* The sky shader adds the stars whatever the brightness of the sky behind them.

The same happens on every Hearthvale evening. I suggested fading the stars by the sky's own
brightness in the shader, or starting them later in the keys. The painted look did both (195d01e5,
on its branch):
* no stars until the sun is 6° down, 0.7 at -12°, full at -18°, so the Toll at -6.5° gets 0.13;
* each star faded by the brightness of the sky behind it.

The Toll's frame waits for the atlas world's re-shoot.

**The dotted line.** It was the sky shader's NaN at the sun's bearing, `pow()` of a hair under
zero. The painted look's clamp fixed it on 09-23 at 01:59. The frames that showed it (06:06) were
taken before that fix reached this branch, and neither flow run since has it. I checked the
Toll's sky at the old line's bearing.

### 7. Talking to the Warden does something

The playtest's first report on the new start was "talking to Wren doesn't do anything", and it
didn't.

**Cause.** The interact key reached her. The ray found her body, the prompt showed her name, and
`Interactor.try_interact` called `Npc.interact`. That emitted `EventBus.dialogue_started` and
stopped, as though somebody would hear it and start the talk. Nobody did: only `Social.talk`
starts the `DialogueRunner`, and the dialogue UI only draws once the runner has begun. Every test
and the journey had called `Social.talk` directly, and the flow only looked at where she stood.

A second fault was behind the first. Sixty of the seventy-two dialogues send their `bye` node back
to `hub`, against their own notes ("'bye' ends"). Once a conversation had started, it could not be
left.

**Fix.**
* `Npc.interact` starts the conversation through `Social.talk`, and not while one is running. A
  property's steward is asked the same way.
* The runner ends the conversation after `bye`, whatever `bye` names as next.
* `just_ended()` covers the frame (and quarter second) after a conversation ends.
  `Interactor.try_interact` stands aside while one runs or has just ended, so the press that closes
  a conversation does not open it again.

**Checks.**
* `test_talk_to_the_warden` stands the world up the way a new game does. At 4, 2.5 and 1.5 m it
  faces her and reads the ray and the prompt. It presses the key bound to interact, as a key press,
  and sees the talk on the screen. It answers down to the goodbye by the number keys. At 2.5 m it
  reads the Naming's first objective done.
* `test_dialogue_runner` says goodbye to a hub-shaped conversation and to the Warden's own.
* The flow probe now does the same after the hand-over. It walks up to her on the move key,
  presses interact, photographs the talk (`talking_to_wren_tallow`), answers it and reads the
  objective done.

`cede10cd` went in as a "WIP:" checkpoint before these ran. The empty commit `028d0bcf` carries
its title and the results.

### 8. The tents are tents

The playtest's second report: "nonsensical models (inverted tent edges)" at the Stair Head.

**Cause.** The forge's tent (`gen_props.tent`) made each side's sheet at the middle of its slope,
moved it there a second time, and tilted it a right angle off. The two sheets stood out over the
ridge pole like wings, pale in the sun, and never reached the ground. The tent was also built along
X with the mouth at one end, where a prop's front is -Y (+Z in the game, CONTRACTS §1). All three
camp builders turn a tent's front to the fire with a bedroll "in each mouth". So every tent stood
side-on to its fire with the bedroll along a flank.

Every camp takes its tents from the same two models (`PoiKit.prop("tent")` answers any region's),
so every camp had both faults.

**Fix.** Each sheet is made flat, tilted at the origin with its outer edge down, and moved once. A
quarter turn at the end puts the mouth in front. `cinderlea_tent_a` and `_b` are rebuilt, keeping
their `.import` files (and so their uids).

`test_camp_tents` reads every built tent as the game loads it:
* nothing stands outside the A by more than the canvas's thickness and sag: 3% now, 68% before;
* the widest of it is at the ground, and the highest of it is over the ridge: 0.10 m out now,
  1.5 m before;
* the closed end is behind and the mouth is open in front: 4.6 m² of canvas across the tent
  behind and 0.3 m² in front (its poles and lines), where it was 0.4 m² each way.

The same two models are every camp's tents, so the camps at the other points of interest are
fixed by the same rebuild. They were not photographed.

### 9. The flow's skip check under load

The settlements' flow failed one check, "pressing a key during the opening shows the skip prompt",
at a machine load of 11 to 15. It passed 98 of 99.

**Cause.** The probe photographed the last shot at its middle and pressed after. The shots run on
the wall clock, and on a loaded machine one frame can outlast the rest of the shot. The frame after
the key was already the hand-over, which takes the prompt down.

**Fix.** The probe now:
* photographs the last shot a quarter in (`LAST_SHOT_AT`) and presses straight after;
* looks for the prompt on every frame drawn while the key is down, not only the first;
* reads "taken as a skip" from the opening's own `finished(skipped)`. Before, an opening that ran
  out on its own also counted.

The prompt already fades on the wall clock (`WallTweens`). `test_words_keep_time` now also holds
that it is fully in on the frame after its key, and gone on the frame after it is let go.

### 10. Life at the Stair Head

The playtest found the start "a little sparse". Nothing in it moved but the Warden and a wisp of
smoke. `_camp_life` (poi_builders) now draws, after the rest of the camp, so that everything drawn
before keeps its place and its random draws:
* a pot hung on three lashed poles over the fire, steaming;
* the fire's smoke carried up high enough to be seen from the Stair and across the heath;
* the Wardens' spears stood by the east tent with a shield at their foot;
* a pack at each tent's mouth, peat to feed the fire, a pail, and rope off the cart;
* crows.

**The crows.** Wickmere has no animal models, and the camp animals on the brief's list need a
quadruped from the forge. A crow is a shape against the sky, so `Crows` (world/pois) draws a
body, a head, a tail and two pivoted wings once and shares them. The birds:
* sit on the colours' poles and the lamps, with two wheeling over the heath ahead;
* flap and glide, banked into the turn;
* are put up by anybody who walks within seven metres of a sitting one;
* come back down to a perch nobody is standing near.

`test_crows` holds that they sit and wheel, that somebody coming near puts one up, that none sits
down beside somebody, and that all are sat again once left alone. `test_the_start`'s new
`test_the_camp_is_lived_in` raises the Stair Head and finds the pot, the spears, the shield, the
peat, the pail, the rope and the crows sat about it. In the first view, the pot steams on its
tripod over the fire, the peat is stacked by the west tent, the shield and spears stand at the east
tent's mouth, and two crows are over the heath ahead.

`test_probes_compile` loads the flow probe and the capture runner with the game's singletons up,
so a mistake in either is found in a second rather than an hour into a flow. Nothing else compiled
them.

### Runs

One Godot at a time, each with the memory for it and after the world build's lock (the journey and
the flow went ahead of a queued build, at the coordinator's word).

**Targeted runs**, each on the tree that finished it. Every one had 0 failed and 0 script errors.
* Phase A: `test_music_director` 30, `test_npc_streamer` 12, `test_quests` 38, `test_kill_places`
  14, `test_naming_screen` 16, `test_world_status` 21, `test_signal_hygiene` 8,
  `test_cinematic_player` 10.
* The talk: `test_talk_to_the_warden` 1 (30 s: the world stood up, three distances, a talk answered
  to its goodbye), `test_dialogue_runner` 26, `test_npc_actor` 16, `test_property` 13.
* The tents, the camp, the words and the probes: `test_camp_tents` 2, `test_crows` 2,
  `test_the_start` 14, `test_pois` 19, `test_words_keep_time` 3, `test_probes_compile` 1.

**On the final tree**, `dfc83c6b`, with main's `9263fc11` (player feel, round four) merged in:
* full suite: PASS. 1624 tests, 0 failed, 0 content problems, 0 script errors, 0 dead lambda
  captures. The 4 logged errors, and the 14 engine errors from enemy perception in the Weaverdeep
  footsteps test, are the same as on the Phase A tree;
* journey: PASS, 16 of 16 steps, 0 logged errors;
* flow: PASS. New game 109 of 109 checks, load 32, continue 35, 0 errors logged. On a loaded
  machine, the first frame drawn after the skip key took 2.1 s and carried the prompt. After the
  hand-over the probe walked to the Warden on W, from 7.4 m to 1.4 m, and pressed E. The talk was on
  the screen (`talking_to_wren_tallow`: "Muddy boots, straight back, no idea where you are. You'll
  do."). It was answered to its goodbye, and the Naming went from `wake` to `the_choir`.

**Pictures** (`tools/capture`, opengl3). The Stair Head before and after the tents' rebuild: from
the first view, from the way, each tent from its side, and from above. Before, the tents were
white wings over their ridge poles. After, they are ridge tents with their mouths to the fire.
The first view with the camp's life in is described under 10.

`dfc83c6b` went into main as `36d83f56`.

### Still weak, or not done

* Other UI fades still run on game time. That covers the objective line under the compass, the
  region card and the menus' caption; on a slow machine they ink in slowly, but none of them is
  read against a clock.
* The escorts' look keeps game time (above). It is a one-line change to PollTimer when it
  matters.
* The stars at dusk are fixed on the painted look's branch, not yet in main when this was written.
  The Toll's shot has not been seen with the fix.
* The camp's other animals need a forge generator for a quadruped and a way to move it. The
  crows are drawn at runtime and are the only animals in the game.
* `tools_gd/check_scripts.gd` stops on an internal script error at its line 20 on 4.7.2 and then
  never quits, so a run of it hangs until killed. `test_probes_compile` covers the two probes the
  long runs use: the flow's and the captures'.
* `cede10cd` keeps its "WIP:" subject. It was pushed to `wip/opening` before its tests ran, so it
  is not reworded. The empty commit after it carries the title and the results.
* In the talk's picture, the HUD's "[E] Talk to Wren Tallow" prompt stays up under the
  conversation, and a toast says it again. The Interactor should offer nothing while a
  conversation runs. That is the next commit.
* The camera stays behind the player through a conversation, so the player's back hides the
  Warden. Next after the prompt: a conversation camera that frames the speaker over the
  player's shoulder, eases back to the follow camera on goodbye, keeps to the camera settings
  and stays out of first person.
* For the atlas world (Phase B), from the cartographer's last pass:
  * the Stair Path to the Choir ends inside the primary colossus, so the waystones and the start's
    "goes round what stands solid" check should stop at the Naming stage's reach radius, at the
    head of the avenue;
  * the way now leaves the camp westward, so the camp's way-out poles and lamp should aim at the
    path's first leg, not at the Choir;
  * the path passes 10 m from the Cantor's Seat door, which is unlocked. That needs deciding:
    a detour for the curious, or a marker that keeps the first walk on the way.

## Characters, second pass: the Naming, a face and hands, a skull and hair, cloth that hangs, a harness, and a child

The brief was seven things wrong with the people. Then the user played the Naming and called it
rough, which put the character creator first, and after the first merge named four more things
in it: the Cragborn's plaid, the hands, the idle, the face. Everything below was rendered and
looked at -- Blender clay and numpy rasters for shape, the engine for what a player sees
(`flow_probe.gd --naming-tour`, and `character_review.tscn`, which now takes `--looks=<file>`
for a row of appearances from four sides, `--frame=head` and `--frame=hands` to close in,
`--pose=Walk@0.51` to hold a clip at a time, `--grip=R,L` and `--haft` to close the hands round
a stand-in haft, and `--mode=children`) -- and the renders decided it. Several things I was sure
of before the first render were wrong; they are listed at the end.

### The Naming, rough edge by rough edge

Captured at 1280x720, 1920x1080 and 2560x1440 through the tour (twelve looks through the
screen's own controls, four of them at the ends of both sliders, each closed in on the face,
then every preset and three casts of the lots), and on Forward+ as well as Compatibility: the
user plays in the editor on Forward+, which none of the earlier captures used; Mesa's software
Vulkan runs it here, slowly.

On the final parts, after the last merge: the full tour at 1280x720, 235 checks, 0 failed; the
quick tour at 1920x1080, at 2560x1440 and on Forward+ at 1280x720, 41 checks each, 0 failed; no
script errors, and a figure in every frame. Before that, the full tour ran from a clean class
cache, as a fresh clone runs it: 235 checks, 0 failed, a figure in all 34 frames. Three long
suggested names no longer widen the middle column: they share its width and end in an ellipsis.

* **The preview was drawn in layout pixels.** A 232x380 box, so at 2560x1440 it was a quarter
  of the pixels stretched up, jagged, with a dark fringe from its transparent background and
  the feet cut off. It is a 400-wide framed portrait rendered at the screen's own pixels with
  4x MSAA; at 2560 the figure is as sharp as the text beside it.
* **No light, no ground, no background.** A painted dusk behind the figure, flagstones with a
  pool of light that fall away into it, a key that casts the shadow, a cool rim on the other
  side to separate the silhouette, a fill. The first version clipped white cloth.
* **The skin read orange, and white cloth cream.** Measured off the capture: a white gambeson
  at 37 % saturation, a mid-brown hand at 68 % against its 50 % swatch. The portrait was lit
  by the dusk behind it -- amber ambient -- under a warm key, and the tones darker than the
  bake were orange in the table itself (amber 57 % saturated at hue 28). The ambient is mostly
  a neutral cool with a little of the dusk now, the key barely warm, the darker tones redder
  and less saturated browns, and the skin shader's lift and scatter band gentler: sampled
  again, the gambeson is at 23 %, the hand at 60 % and the face at 49 %. On Forward+ and on
  Compatibility alike the figure is lit with form, the skin reads as skin and cloth as cloth,
  and the whole figure is framed with its feet and headroom.
* **It could not be turned or looked at closely.** It turns under the mouse, the wheel closes
  in, Face / Whole figure frame it, and choosing a face, a tone or a hair style closes in on
  its own. The face framing lost the crown of a broad head at 1.84 m (0.23 m either side of
  the mouth, looked at from below); it is 0.28 m round the eyes' height, from level.
* **The build slider did nothing across its middle third.** The body variant only changes at
  0.30 and 0.68 and the rig was not widened with a variant on. Girth is one continuous line
  now, and the rig makes up the difference to the body worn.
* **At the heavy end the body stood through the clothes**, because every garment was built on
  the default body. A garment can carry the heavy and slight bodies as morph targets once the
  forge has fitted it (`fits` in its meta, `--fits`), and until every garment on the body is
  fitted the default body is worn and the rig widens. Measured against the variant bodies a
  fitted tunic still left 7 % of its vertices inside the heavy body (59 % unfitted) and a coat
  17 %, and four garments' morph targets flung a vertex a hundred kilometres -- a sampled field
  reads 1e6 where no primitive reached, and the fit stepped on it; in the Naming at the solid
  end of the slider the Cragborn's plaid drew as a white bar across the frame. The fit no
  longer steps on such a reading, but the fits are off and the garments ship without them:
  under clothes the default body is worn and widened, which shows no skin.
* **Three of the four beards drew nothing** -- stubble, short and long were an armature with
  no mesh -- and the chooser offered them anyway. It offers only beards that draw. Rebuilt,
  all four draw, and the chooser offers them again (the tour checks it on both renderers).
* **The eyes were never drawn in the engine.** Every eyeball was wound inside out, Blender
  renders both faces so no forge review ever showed it, and the iris shader culls back faces.
* **Every colour change built a new material for every mesh** and dropped the last; on the
  Compatibility renderer that left the eyes pointing at freed materials (`Parameter
  "material" is null`, four times a look) and they stopped drawing. Materials are made once.
* **Swapping one head for another in a frame renamed the new eyes** `@MeshInstance3D@n` and
  dressed them in skin. Eyes are known by meta now.
* **The probe itself clicked in layout units**, so at any size but 1280x720 it missed New
  Game; it converts to window pixels.
* **At 1280x720 the right-hand column ran off the parchment.** Fixed widths, headings that
  wrap.
* **Presets and Cast lots** (six kinds of person; the lots only pick parts that draw),
  swatches that show which one is chosen, arrows on every chooser.
* **The gambeson's neckline in the face view was a torn-paper edge**: `torso_region` faded
  the neckline over 5 cm, and a 26 mm padded garment thinned out over a hand's breadth. The
  cut is crisp now.

### Four more, and what they pulled in

After the first merge the user looked at the Naming again and named four things: the Cragborn's
plaid a thick white blanket, the hands paddles, the idle an A-pose, the face without features.

* **The idle.** It held the upper arms 10 degrees out with the wrists 29 cm from the centre
  line, 11 cm off the hips. The Idle is re-made -- only the Idle: the other 70 clips bake
  identical to the committed ones, within 1e-5 on every channel, and the rig's meshes and images
  stayed the committed ones byte for byte -- with the weight on the left leg, the pelvis over
  that foot and dropped on the free side, the chest tipped back against it, the free foot eased
  forward and turned out, the shoulders let down, the elbows soft, and the wrists 23 cm out, 5
  cm outside the hip: what a hand needs to clear a skirt, a gambeson or a fauld. The first bake
  swung the hands 3 cm out and back with every breath, because the breathing layer rolls the
  shoulders; a counter-roll at the upper arm keeps them hanging. Merged with the planted feet
  (above), the Idle's free foot stood 3.5 cm forward and turned out, a stance of its own, and
  every stop and turn settled into the planter's stance and was then pulled into the Idle's: it
  stands in the planter's now. And its breath and sway moved the hips, which the relaxed pose's
  bent legs followed at every joint; the engine thins those curves on import, and the feet the
  bake holds still wandered 2 mm and were snapped back and forth by the planter for a second
  after every stop. The breath and the sway move the chest, the spine and the head over legs
  that stand still.
* **The hands.** A hand was 1.12 of true size, 4.8 cm thick, and its four fingers one grooved
  mass: at the Naming's distance, a mitten. It is true size now, with a palm 3 cm thick, four
  three-jointed fingers that touch at the root and part towards the tips, curled as a hanging
  hand curls them, and a thumb. At the body's 8 mm mesh the gaps between fingers are not there
  to be found, so the hands are meshed on their own at 2.6 mm (1 800 triangles the pair) from
  the body's own arm past a cut just short of the wrist. The first split ended the forearm
  short inside a hand with a wrist of its own, and in the engine a ragged ring ran round every
  forearm; cut from the one field, the two meshes are one surface. The gloves were an offset of
  the body's 5 mm field -- a padded mitten, the paddle again -- and are made round the hands
  sampled at 2 mm, 3 mm over each finger. `_arm_frame` had built the left hand palm up.
* **The face.** Every mark on it had been kept faint "so it never wins at 30 pixels", and at
  the Naming's 400 pixels there was nothing to read by. The brow, the lash line, the lid crease,
  the inner corner of the eye, the nostrils and the wings of the nose are painted to read. The
  mouth had never read at all, and not because it was faint: the lips were painted 3 cm in
  front of every face -- at the eye line's depth plus 2 cm, where no mouth is -- so the seam was
  masked out and the lips came through at a fifth of their colour. They sit on the mouth's own
  station now, a third of the way from the lip colour to the skin's shadow; at full colour
  they read as painted on.
* **The plaid.** A solid loft 15 cm thick down the back and a tube 7 cm thick across the chest,
  in undyed wool the palette left pale and plain. It is one sheet of cloth a centimetre thick
  now: a sash over the left shoulder, pinned with a ring brooch, lying on the body across the
  chest and round the right side, and the rest hanging from the shoulder blades to behind the
  knee in folds. It is woven: a tartan in the clans' own madder, walnut and undyed wool, crossed
  as a 2/2 twill and baked into the texture, and the part's meta says `"tint": "none"`, so
  HumanoidModel lights it as cloth without dyeing it the palette's primary
  (`test_a_woven_part_is_not_tinted`). The Cragborn preset wore a gambeson under it where the
  game's clans wear a shirt: half of the "padded costume" was the gambeson.

The idle brought one more into view. With the arms down, the deltoid -- a ball laid over the
shoulder joint for the A-pose -- stayed up at each corner as an epaulette, and every garment,
built as an offset of the body, carried the same two balls. The shoulder line was 4 cm high,
above the chin, because the trapezius rose from the neck to a mound. It falls from the neck
now and the deltoid lies along the top of the arm and goes down with it; the head sits on a
neck. Every garment that covers a shoulder is rebuilt on that body. Before the shape, I tried
the weights: four ways of sharing the shoulder between the collarbone and the upper arm, posed
through a weight hook in a numpy skinning previewer, and none of them changed what could be
seen. The mound was in the shape.

### The skull, the hairline, the hair

The bald cranium was an egg. The head is rebuilt as a shared vault -- parietal, frontal,
the occipital shelf the neck tucks under, mastoids -- and a face lofted from its profile below
the brow: a brow ridge, cheekbones and their arch, a jaw with an angle, masseters, a nose that
projects, lips on the dental arch, and ears with a helix, concha, lobe and tragus. The vault
and the brow are the same on all eight presets, so hair and helms fit every face; the faces
differ below the brow. Every hair style is a scalp shell that thins to a millimetre at a
hairline following the skull (temple corners, sideburns, round the ears, the nape) with locks
combed over it along a flow -- a side parting, a centre parting, combed back, to the crown, to
a bun or into a braid -- and a strand-painted albedo, ORM and normal map. Before, each style
was a cap with a hard rim sitting on an egg. Seen in the engine (`character_review --looks
--frame=head`, eight faces from four sides): the long hair falls behind the shoulders from a
centre parting, the braid hangs from the nape, the bun sits at the back of the crown, and the
hairline reads as hair growing out of a head. The bun's first coil was a dish, a button seen
from behind; it climbs its dome now. The three beards that drew nothing draw; each carries a
morph target per face so it lies on a broad jaw as on a narrow one.

Seen and changed after the first engine renders: the long beard's hanging part fell inside
every shirt (it hung 1 cm off the body; a shirt is 1.1 cm off it) and long hair did the same
over the shoulders -- both hang 3 cm off now, eased out from the chin and the scalp rather than
pushed (pushed, the beard lost its hang); and stubble read as a full short beard, an opaque
shell in the hair colour, and is drawn see-through.

Rebuilt on the body with the lower shoulders (below), the long hair lies on them and the braid
and the long beard hang over a shirt.

### The cape, the cloaks, the hood

The shoulder cape was a lampshade: a rigid shell standing off the shoulders. It lies on a
*drape field* now -- every horizontal section of the body unioned with the ones above it and
pushed out a little per metre of fall, the space cloth takes when it is laid over the shoulders
and let go -- so it follows the slope from the neck, breaks over the point of each shoulder and
falls past the arm. It is one sheet drawn from both sides, not a solid with a floor under it;
eleven folds deepen towards a hem that runs lower behind; a standing collar and a clasp close
it. The first render of it still stood off: it rested on the height of the Neck joint, and the
body's shoulders are 6 cm above that joint. `shoulder_line` reads the height off the body.

The cloak was the same lampshade to the calf, and the ragged cloak cut from it exported nothing,
so the Woodfolk walked about without one. The cloak is the cape carried down: open from a clasp
at the throat and wider as it falls, folds from the shoulder blades that deepen to a hem a hand
lower behind, weighted to the chest, spine and hips with the front panels taking some of each
thigh. Hooded, the same sheet is carried up over a *cowl field* -- the head as a hood falls from
it, from the crown past the ears to the shoulders, with a peak of spare cloth behind the crown
-- and the face cut out of it; the hood on its own is that with a short cape. The ragged cloak
is that with a hem torn into thirteen points, and the torn cloak the same with the hood down,
which is what the player wears out of the Naming. Seen in the engine standing and at the Walk's
contact pose from four sides: the cape rests on the shoulders and falls over the tops of the
arms; the cloaks fall from the shoulders open at the front with their folds; the hoods frame the
face; the Woodfolk have a torn hem again, and nothing tears at the hip when the body walks. The
cloaks' upper edge stood to the mouth; it lies round the base of the neck now. They were draped
over the A-posed body with its arms cut off at the shoulder, and the stub of arm left ended
every cloak's shoulder in a square corner, a coat hanger under the cloth; the arms hanging in
the Idle then came out through the sides at every step. They are draped over the arms as the
Idle hangs them now, put back into the rest pose by the inverse of the Idle's skinning so the
Idle brings them to where they were made, and the cloth that lies on an arm takes most of its
swing. The shoulders round over the arms and the sides go with them.

Mid-stride, the arms still came out. The Walk swings a hand 30 cm ahead of the hip, and the
cloth hanging in front of an arm and behind it was too far from the arm to take any of its
swing: the forearm and the hand came out through the front. Distance ahead of and behind an arm
now counts at 0.4 of itself, the cloth near an arm takes 0.95 of its swing, and the back takes
half of the thigh behind it, handed from one thigh to the other across the middle of the back,
so the leg behind no longer comes through at a run. And a long cloak holds a walker's arms in,
as cloth lying on the arms does: `ArmRoom.hold` takes 0.7 of the clip's arm pose back to the
Idle's hang walking and 0.95 running, and nothing in a blow, a guard, a sneak or a fall. Seen in
the engine standing, at two frames of the Walk and two of the Run, from four sides: no arm comes
out of a cloak's side, front or back, and no leg through its back; the hands show at the front
opening, as an open cloak shows them. Standing, the shoulders round over the hanging arms, where
the cloak had stood out from them like a coat hanger with the hands below its sides.

### The skirts

The dress, the robe, the skirt, the kilt and the wrap skirt took the nearest leg's weights
whole, so a stride tore the cloth open between the legs and showed the thigh. And they were
lofted through fixed ellipses cut for an earlier, narrower body: the final body's hips stood 1-2
cm out through the side of every one, a torn patch of thigh at the hip of each dress in the
family lineup, and the Lakefolk coat's column was so narrow that its trousers showed down both
sides of it like an apron. Each station below the waistband is grown to cover the body's own
section now (the waistband is left as cut: grown, it swallowed the belt), trousers lie 7 mm
closer from the thigh up, under whatever is worn over them -- they showed through the tunic at
the hips in green patches -- and below the hips a skirt's weights go to both thighs, blended
across the centre line, with a little to the hips: the cloth over each thigh goes with it and
the cloth between them stretches. Held at the Walk's contact pose from four sides, none of them
opens at the thigh. The Lakefolk coat's skirt is weighted the same way, with more of the thigh
(0.85 of it at the hip, where the forward thigh came through at the contact), and it clears the
body by 1.6 cm at four stations down the thigh: cleared by 1 cm at the hip and the hem only, it
let the trousers through its sides in blue spots standing, and in a strip down the free leg in
the Idle.

Every "mid-stride" lineup rendered before that one had stood in the Idle: `character_review`
held a clip on the AnimationPlayer with the tree switched off, and HumanoidModel steps its tree
by hand every frame, so the locomotion idle overwrote the held clip. The first cut of the skirt
weights, judged on those renders, handed the front of each skirt to the hips, and the first real
stride showed the forward leg out through the front of the robe, the dress, the wrap skirt and
the kilt to the hip.

### The harness, and the other armour

The breastplate stopped at the collarbone over bare shoulders and ended in a hard edge at
the waist: a corset. Plate is a harness now, three meshes of two materials: an arming coat of
cloth under everything (sleeves to the wrist, a skirt to mid-thigh, quilted), a cuirass that
goes over the tops of the shoulders to a ring at the neck with a keel down the breastplate, a
gorget of three lames closing the neck, spaulders stepping down each shoulder cap, and a fauld
and tassets over the hips; the brigandine is the same coat under riveted leather with a
standing collar. The first render showed the cuirass cut flat at shoulder height -- a box with
a head in it -- and the gorget spreading into a plate across the shoulder blades; both are
fixed. The helm was an ellipsoid 3 % bigger than the vault, which the new skull's ears and any
hair came through; it is an offset of the head it sits on, stood off by the hair, down to the
brow in front and over the ears, lower behind, with a rolled rim, rivets, a comb and a nasal.

The same class of fault in the other armour: the gambeson's sleeves stopped three quarters down
the arm, leaving bare forearm above every padded glove (they reach the wrist); trousers ended
3.5 cm above the top of a shoe (they end inside it). And a larger one: none of the twenty armour
items named a part, so equipping a brigandine changed a number and nothing a player could see.
Seventeen carry a `wear` block now and the player's body wears them over the Naming's look;
the leather cap, the padded cap and the leather jerkin have no part yet.

Rebuilt on the new body, the harness and the brigandine go over the lower shoulders. The
brigandine's rivet rows had thrown one rivet a thousand kilometres out -- a step taken on a
sampled field's 1e6 where no primitive reached, the fault the fits had -- and its grid could not
be allocated, so it had not been built since the harness was made; built, its leather decimated
from 325 000 triangles to 5 200 lay in chords that cut inside the coat, and the coat showed
through it in patches. It has 9 000, and in the engine the leather is whole. The pauldrons, an
empty file until now, are three lames over each shoulder.

And the relaxed Idle's hands, 5 cm outside the bare hip, hung inside a gambeson's skirt and the
harness's tassets. `ArmRoom`, a SkeletonModifier3D, turns the arms out at the shoulder after the
clips have posed them, by a table of what is worn (7 degrees for a gambeson, 8 for plate, 3 more
on the heavy body), so a padded body's hands hang clear in every clip. It is a new `class_name`,
and the first tour run after it had an empty stage: a class is known to the game only once the
import has written it into `.godot/global_script_class_cache.cfg`, HumanoidModel failed to parse
without it, and the probe's check that the Naming has a preview body asked only for a node.
`./run.sh run` imports now whenever a script declares a class the cache does not list (it
imported only when a clone had never been imported), and the probe fails unless the body's
script loaded and it draws.

### A hand that closes

No weapon was ever drawn in anyone's hand, and the hand had no finger bones: its palm stayed
open and splayed round any hilt. Bones for the fingers would have changed the skeleton that
every clip and every part is bound to, so the closed hand is a pair of morph targets, grip_L and
grip_R, on the rig's body, the slight, heavy and child bodies and the gloves, whose two meshes
each close with their own hand. `tools/forge/lib/grip.py` curls each finger and the thumb of the
modelled hand as rigid pieces of a chain about its own knuckle hinge, by the angles a search
finds to lay it round a 3.2 cm haft, blended across each joint; the palm stays.
`HumanoidModel.set_grip(side, amount)` closes a hand over a tenth of a second, and a part put on
a closed hand closes with it. The fist holds its haft 1.8 cm deeper in the palm than the weapon
socket (`grip_offset`), and a held weapon is put there: moved into the fist, the sockets had
every grip-led clip re-bake turned at the wrist by up to 175 degrees. Seen in the engine close
up, bare and gloved, and in the one- and two-handed attacks at their windup, each fist closes
round a haft, the fingers on its far side and the thumb across it. The player-feel work attaches
its weapons with these calls. `transplant_clips` carries a morph target written sparse, which it
had refused.

### Textures beside the GLBs

All 54 character GLBs embedded their maps, and Godot's import, told to extract them, wrote a
second, uncompressed copy of every one beside each part as `<glb>_<image>.png` while the
forge's own VRAM-compressed PNGs were loaded by nothing. The 122 embedded images were the
forge's PNGs byte for byte, so `tools/forge/externalise_textures.py` repaired it without a
rebuild (113 extracted doubles deleted, 46 MB to 27 MB), and the forge externalises at every
export. `tools/tests/test_glb_textures.py` walks every GLB under `game/assets`: no embedded
image, every referenced file present, every character GLB holding a mesh, every meta counting
the triangles its file holds, no character texture referenced by nothing. It found five parts
that were an armature with nothing in it (the three beards, the pauldrons and the ragged cloak
-- the exporter drops a mesh it thinks invalid and says so only on stdout); the forge now
refuses an export that wrote no triangles. Eight culture garments also carried import
sidecars nothing had stamped: textures without mipmaps or compression, and no post-import
script. `apply_import_settings.gd` stamps them now.

### Eyes, skin, and what the material is made of

The eyes were not flat discs: they were never drawn at all (above). Wound outward, with the
iris shader drawing both faces, the face view shows an iris with a pupil and a highlight,
tinted by the chosen colour; counted off the rebuilt head GLBs, 94 % of each eye's faces point
out, against 0 % in the old ones.

Compatibility has no subsurface scattering, so skin wears its own shader
(`assets/shaders/skin.gdshader`): the light wraps past the terminator and what it adds there
is tinted towards blood, with a soft sheen instead of a specular spot. The first version made
porcelain of every tone -- the face bakes carry painted light and the engine lit them again --
so the paint is scaled back to the value skin is (0.84). Cloth, leather and metal each get
their own rim and specular in `HumanoidModel._dress`, keyed off the material the forge wrote
into each mesh's meta (a harness is several meshes of several materials: an arming coat of
cloth under steel), and in the Naming's light the belt reads as leather against the tunic's
wool and a cuirass as steel. A part woven in its own colours says `"tint": "none"` and is lit
as its material without being dyed (the plaid).

### A child

The old note said a child needs its own rig and its own bake of the 70 clips. It does not:
CONTRACTS §2 already says the clips retarget by bone-local rotation, and the only thing in the
way is that the exporter writes every bone's own translation into every clip, which on a
child's skeleton would stretch it back into a grown body on the first frame.
`ChildProportions` (a SkeletonModifier3D, `actors/shared/child_proportions.gd`) runs after the
clips have posed the rig and puts each bone back where the child's skeleton has it, carries
each rotation over as a turn from the rest pose, scales the hips' travel to the child's height
and the head to the child's (the heads are the grown ones, worn at 0.86). Everything it uses
is read off the two forge skeletons, so a rebuilt rig does not break it. The child's clothes
are cut on the child's own skeleton (`<garment>_child`: tunic, shirt, trousers, dress, shoes,
boots, belt); a garment with no child's cut becomes the plain one of its slot, and a child is
only put in its own body once those clothes exist -- bare, the child body would stand in the
street as it did in the first render of it.

Seen in the family lineup, standing and walking beside two grown people: a child in a tunic and
trousers and a child in a dress, their clothes cut for them.

Separately, nothing in the packs was ever given a child's height. Seven NPCs are tagged
`child`, two more are only written as nine and eight and `child_small`, and every one was
rolled as a grown person of their culture: the miller's nine-year-old stood as tall as the
miller. `Npc.appearance_of` gives them a child's height for their years (1.22 m at seven,
1.44 m at eleven). The capsule fallback that was meant to shrink a child had been sitting
after the `return` of `appearance_of`, where nothing could reach it.

### Diagnoses that did not survive the render

* **"The eyes are flat discs."** They were never drawn in the engine at all: wound inside out
  and culled. The discs people saw were the sockets.
* **"A child needs its own rig and its own bake of the clips."** It needs neither; the clips
  already retarget by rotation, and the bone translations the exporter writes into them can be
  put back after the pose (above).
* **"The cape stands off the shoulders because it is a rigid shell."** True of the old one, but
  the first render of the draped one stood off too: it rested on the height of the Neck joint,
  and the body's shoulders are 6 cm above that joint. The fault was the landmark.
* **"The cloak flares out to the hands because the A-posed arms are in its drape."** Taking
  the arms out moved the hem by millimetres; it was the cape's flare (0.10 per metre) carried
  down a metre of fall, 0.46 m each side at the knee. The cloak flares at 0.045 now.
* **"The build slider needs the heavy body."** It needed the rig's girth to follow it; the
  heavy body is shape on top of that, and only under clothes fitted for it.
* **"The mouth has no definition because the paint is faint."** It was painted 3 cm in front
  of the face, where the lips' mask never reached the skin.
* **"The epaulettes are a weighting fault."** Four weight schemes for the shoulder, tried on
  the posed body through a weight hook in a numpy previewer, changed nothing that could be
  seen; the mound was in the shape, a ball laid over the joint for the A-pose and a trapezius
  rising to meet it.
* **"The plaid needs less bulk."** It did, but half of the padded costume was the gambeson the
  Cragborn preset wore under it, which the game's own clans do not.

### Found and not fixed

* **The wrist join is a fine line.** The hands are a separate, finer mesh joined to the body's
  forearm, cut from the same field. The hand now covers the body's rounded end, and the groove
  the first join left is gone; but two meshes of different resolution still meet there, in a
  line a pixel or two wide at the Naming's whole figure.
* **A cloak's shoulders are broad and flat on top, and in profile a hood's spare cloth hangs as
  a flap behind the neck.**
* **At the Walk's passing pose the swinging heel shows under the back of a robe to the ankle.**
  The robe's hem is a hand off the ground and the foot comes up behind it.
* **Men in a shirt show the default body's chest through it**: the shirt follows the pectoral
  masses closely enough to read as a bust from the front. Flatter pectorals were tried in a numpy
  render and were not worth the rebuild of everything cut on the body.
* **Padded torsos hold the arms out by a table** (`HumanoidModel.ARM_ROOM`, per torso part, and
  three degrees more on the heavy body); a cloak, a heavy belt or gloves are not counted, and the
  clips themselves still carry the default body's pose.
* **The heavy and slight bodies are worn only bare or under clothes that fit them**, which is none
  yet: the garments' morph fits are built only with `--fits` and still left 7-17 % of a garment's
  vertices inside the heavy body. Under clothes the default body is worn and the rig widened.
* **A child whose people wear a kilt, a wrap or a robe is dressed as a Vale child** (tunic,
  trousers, shoes): only the plain garments have a child's cut.
* **The face is painted, not modelled.** The brow, the lids, the nostrils and the lips read now at
  the Naming's distance; there are no modelled lids and no expressions.
* **NPC defs give `age` in years**, and the record's `age` is 0 (young) to 1 (old). Nothing draws
  age yet and a test pins the raw value, so it is left.
* **The engine thins the clips.** Godot's import keeps a fraction of each clip's keys (the
  Idle's hips kept 10 of their 121), and a foot the bake holds still wanders a millimetre or two
  in the engine. It is why the relaxed Idle's legs now stand still under its breath and sway.
  Turning the import's animation optimizer off for the rig's clips did not keep the keys, and
  wrote a 5 MB sidecar.
* **The closed hand is one fist.** It closes round a single size of haft, 3.2 cm; a bow's grip,
  a shield's handle and a dagger's hilt all get the same fist.

## Characters, third pass: materials, faces that age, a period palette, and cloaks with the hood down

The brief: cloth, leather, metal and skin that read as materials and not painted plastic;
faces with lids, brows, colour and years (characterful storybook faces were the mark); feet at real
size; bugs in the wrap and the cloak; a silhouette for each people. Then, after the first
sheet: an earthy palette, warmer and older faces, beards with a body, a rounded cloak with a
hood, wear at the elbows and knees, the kilt in tartan, and relaxed arms in the lineup.

The same four people are rendered at 1920 through godot_slot.sh after each round, before
against after, three-quarter and front (scratchpad `final_renders/lineup_before_after_1920.png`).

### Materials (game/assets/shaders/garment.gdshader)

- **Every garment wears one shader.** Four kinds: cloth, leather, metal, and woven (tartan,
  left untinted).
  - A detail normal tiles many times over each part's UVs: weave, leather grain, hammer dents.
    The maps are made by tools/forge/gen_character_detail.py and live in
    game/assets/textures/characters.
  - A mottle map gives dye taken unevenly.
  - Folds are darker than the bake's occlusion alone.
  - Grime rises from the ground by model height: hems and boots are dirty, shoulders clean.
- **Cloth, leather and metal:**
  - Cloth is rough, at least 0.86, with a faint wool sheen at grazing angles.
  - Leather scuffs paler.
  - Iron is a dull grey: metallic 0.6–0.75, roughness about 0.62. At near-mirror settings it
    had turned the sky into blue and black blotches.
- **Both faces are drawn.** The glTF materials the shader replaced were double-sided; culled,
  the plaid apron showed only its edge.
- **Detail maps need mipmaps**, or the weave aliases into a chain-mail moiré at any distance.
- **Elbows and knees** are rubbed pale and smoother in each garment's bake (behind the elbow,
  in front of the knee). The old exposure term never found them inside a sleeve.

### The palette

Every people's cloth is dyed in period colours: madder, woad blue-grey, weld yellow, undyed
wool, oak-gall browns and lichen greens. Saturation is low and values vary. The Reedfolk's royal
blue and teal and the Vale's lime hose are gone. The table lives in three places, which agree:
- tools/forge/lib/cloth.py `CULTURE_PALETTES`;
- characters.json;
- CharacterAppearance `CULTURE_PALETTES`.

The kilt is woven all round in the clan's sett, the same one as the plaid.

### Faces

- **Painted (tools/forge/lib/paint.py):**
  - The near-black lash line read as eyeliner. It is now a soft line in the skin's own shadow,
    and a warm lid shadow runs up to the crease.
  - Brows are heavier.
  - Cheeks and nose carry more colour; there is a nasolabial fold and a shadow under the eyes.
  - Each face is off true from its seed: one brow higher, one fold deeper, one cheek redder.
- **Age is a runtime layer.** Every head is baked young and also bakes `<head>_age.png`
  (`paint.age_lines`: forehead creases, the furrow between the brows, crow's feet, nose to
  mouth, mouth to jaw, the fold under the eye). skin.gdshader multiplies it in by the record's
  age: none at 0.30, all of it at 0.85 (`HumanoidModel.age_lines_amount`). The model's colour
  signature includes it. Test: test_the_old_wear_their_years.
- **Skin** keeps its full colour (the shader took 6 % out) and scatters a little warmer.
- **Beards:**
  - A full beard is a mass under the chin, two lobes tapering as they fall, with a few thick
    clumps melted into it. Before, it was forty thin strands like icicles.
  - Locks on the cheeks and the sides of the jaw lie close.
- **Heads** are 6 % larger on adults (ArmRoom `head_scale`).
- **Eyelids:** the lid lens is lower and narrower, so the upper lid covers the top of the iris.

### Proportions, bugs, silhouette

- **Feet** are 26.6 cm (they were 34), and the boots are built round them (test_foot_size.py).
- **The relaxed Idle:**
  - The elbows bend about 36° and the wrists fall with them, the forearms a little forward of
    the thigh. At 28° the arms still read straight in a lineup.
  - This clip is this branch's, re-baked and transplanted. Every other clip stays the weapons
    branch's, byte for byte.
- **The Reedfolk wrap** covers the chest. Its line starts under the left armpit, a hand below
  the shoulder joint.
- **Cloaks** (`cloak`, `torn_cloak`) are worn with the hood down:
  - A roll of cloth lies round the back of the neck, and the hood lies down the back from it.
  - The cloth is gathered 4 cm off the body behind the neck and over the shoulders, so the top
    falls round from the neck to the point of the shoulder.
  - Gathered in front as well, it stood up to the wearer's mouth.
- **Culture belts:**
  - Clans and Woodfolk: a belt with a sheathed knife.
  - Reedfolk: a sash.
  - Ash-Pilgrims: a cord of beads.
  - Lakefolk clerks: a satchel.

### The rig, shared with the weapons branch

The weapons branch owns the clips; this branch owns the meshes, skins, morphs and the Idle.
`transplant_clips.py --keep=<clips>` puts one branch's clips on the other's rig and keeps the
named clips from the base. Its read-back proves both halves byte for byte, and the clip sidecar
is always the weapons branch's.

### Judged on the sheet, and what is still short

The last round was rendered on 29b24fbf, the batch-3 merge with the weapons branch's Backstab.
What reads now that did not before:
- **Colour** is the biggest change. The people sit in the world instead of on top of it. The
  Reedfolk wear woad over madder, the Vale lichen hose under undyed ochre, the Clans an undyed
  shirt over a tartan kilt, and the Woodfolk bark and lichen. A light shirt, a mid skirt and a
  dark cloak are three different values.
- **The kilt** and the plaid are one sett. The Clans read at a glance.
- **Cloth** is matte and woven, and the hems are dirty.
- **The wrap** covers the chest.
- **Feet** are the size of feet.
- **The arms** hang with soft elbows beside the thighs, not in an A.
- **The cloak's top** falls round from the neck to the shoulder, with no square corner, and
  its collar sits below the chin.

Still short of the mark:
- **Iron** is grey now, not black, but still blotchy: the dents and the sky's reflection make
  a noisy, dirty surface, not forged plate. It wants a calmer value with larger dents.
- **The Woodfolk's bark brown** is so dark on a cloak that it reads black. The folds, the hood
  lying down the back and its roll hardly read, even from behind. The torn front edge still
  shows dark gaps by the right hand.
- **Faces** are warm, lidded and coloured, and read as people at the lineup's distance. Close
  to, they are still smooth and doll-like. The brows may now be too heavy.
- **Age lines** show only on an older record. The lineup is at the default age of 0.3, so none
  appear there.
- **Beards** have a body at a distance. Close to, the clumps still hang as separate tails,
  the ginger one most.
- **Elbow and knee wear** is baked in but hardly shows at the lineup's distance: the knees of
  the hose are a little paler, and the elbows of a light shirt show nothing.

## The quests, played on the atlas world

The atlas world's merge had one gate left besides the final build: every authored quest played
through on it, every way. `./run.sh quests` does that (`tests/quests/quest_walker.gd`).

**How it plays.** It stands up a new game in the built world, the way the Naming screen hands one
over. It begins each quest the way the game does: the opening, a line somebody says, the work a
giver offers at their hub, or the quest before it. Then it drives each objective through the
services a player's input reaches:

* **Going places.** It teleports to the place and waits for the country to stream in round the
  body.
* **People.** It finds a person where their day has them and talks through their own dialogue.
  `tests/quests/dialogue_steer.gd` picks the lines, looking ahead through the graph the author
  wrote to the line the objective waits for. On the way it takes no decision and starts nobody
  else's work.
* **Fights.** Whatever stands at the fight is put down with hits through the damage model.
* **Finds.** Things are picked up where they lie. Books are read where they lie or out of the
  bag. What only a shop or a boss has is bought or taken.
* **What gates an objective.** A flag somebody's line sets is earned by saying that line, and that
  line's own gating flag is earned first.

After each stage the walker checks that the stage's effects took. At each ending it checks that
whoever remembers the quest greets you with it.

**Every way.** Before a decision, the game is saved in memory through the same SaveSystem a slot
uses. Each other option is chosen from that save and walked to the quest's end. The houses built
so far are let go on each restore, as the scene change of a real load lets them go. A decision
first met inside a branch is walked every way there.

**On w_final5 (dbeb9d5f).** All 75 quests end every way they can: 224 walks with branches on,
0 logged errors, 30 minutes. Before that, three runs found these:

* **A book left open.** Reading a book where it lies opens the reader, a full-screen menu that
  pauses the game. The walk went on paused, so nothing streamed in and nobody stood up. Four
  quests failed on fights and finds that were never there. The walk now shuts what it left open,
  as a player would. It also says why, when the country does not stream in.
* **Vigil's escort.** It waits on Aud Fennick agreeing, and she agrees only once Cadwen has asked
  for the walk. That is fine in play but was not earned by the walk; the Order's other three
  quests hung on it.
* **What the Water Kept, second way.** Tallissa's book had already been taken in the first
  branch's copy of her house.
* **Two world notes, from POI dressings.**
  * The Wardens' hand-bell lay under the Tumbled Watch's lying stair. Its `fallen_stair` marker
    is now by the fire at the drum's lower mouth.
  * Ivo Goslin stood inside the mound heaped on Willow Isle. That is the heap atlas-readiness
    709f9908 removed, and it clears with the atlas merge.

The walker's WORLD lines name what the built world does to a place, person or find (water,
height, something solid) with coordinates and the shape touched. Any such line fails the run.

### Tests

* `./run.sh quests` passes all 75 quests on w_final5. The two world notes are fixed on this branch
  (the bell) or by the atlas merge (Willow Isle).
* `tests/unit/test_dialogue_steer.gd` covers the line picking against a fixture graph.

### Next

Run `./run.sh quests` on the merged, rebuilt main world, and on every world build after. Its
exit code is the gate.

## The world builder: spurs, pits by the rivers, rolling floors, and rivers that wander

**Roads that went out and back** (5d45b8c1). The five roads whose land stood off their grade
(untraced above) were traced: nothing moved the land after the carve. Each road came back over
itself.
A `via` drawn on a knoll made the road climb to it and return down the same line, and where the
two legs lie side by side the carve holds only one of their levels. 25 roads did it, and
Pilgrim's Ash to Ashwell went 1.6 km up to the Wellspring's plateau and back.
`roads.cut_spurs` cuts such a spur out and keeps switchbacks.

**Rivers hung over pits by their heads** (5d45b8c1). This was a landform (a scar, a shakehole)
dug under the river's bed after the carve, not the carve itself. `landforms.river_guard` keeps
landforms within 60 m of a river half a metre over its water. The floats left sit at falls
steeper than one in one, and where a river enters the sea or a lake.

**Valley floors roll** (5d45b8c1) by 1.8 m over 30 to 160 m, with 0.9 m of grain, instead of
climbing from the bank as a smooth ramp.

**Rivers wander** (3d93541f). `hydro.meander` puts meanders on flat ground and a sway in steep
country between the atlas's drawn points. Every drawn point is on the line, and near a place or
POI the river keeps to its drawn line. The carve, the surface and the flow map follow the new
line. An optional per-river `"meander"` in the atlas scales it, and 0 holds a river to its
line. The steep Skerrow rivers' big bends are the atlas's to draw: the cartographer redrew them
on their branch. A main rebuild is needed.

Left: floats at falls steeper than one in one (the surface runs straight between points 20 m
apart), the Grandfather Hollow roads (its ring street is approved, not built), and the build's
time.

## The world builder: Grandfather Hollow's ring, the level radius, and the falls

**Grandfather Hollow** (4bc399f6, d6174585). The town is a closed ring street 48 m out round the
tree, 6 m wide, with a 4 m spur in to the door at 304 degrees, 41 m out. Every road runs straight
in from the level ground (72 m) to the ring's outer edge (`roads.RING_TOWNS`).

**`radius_level_m`** (d6174585). pois.json gains how far out a pad is truly level: 0.7 of
`radius_flat_m`, or 72 m at Grandfather Hollow. `radius_flat_m` is unchanged; 4bc399f6 briefly
shrank it, and d6174585 puts it back. Houses belong inside `radius_level_m`; the fabric's reader
is still to change.

**Falls** (4283e68b). Down a stretch falling faster than 0.3 a river keeps a point every 5 m, not
20, so its water follows the face. A texel takes the river's level where the line passes nearest
its centre. Stepped pools were tried and were worse.

**A measure above was wrong.** The river-float figures in the entry above (1,686, 1,100, 632)
came from a scratch tool that sampled the heights half a texel off. Corrected, and leaving out
water in the sea or a lake, a 1024 build went from 590 to 462 samples more than 3 m over their
ground with the falls change. Measured against the bed the carve means to cut, the samples more
than 1.5 m over it went from 336 to 78.
## Dense but sprawling: the opening's walk, the horizon, the rivers, the Hollow

The user said the start felt sparse, and the chart's rivers were ruler-straight.

**The walk, measured.** From the Hushline Stair to Merrowby is 5.7 km, 19 minutes at a jog. It was
surveyed on the rebuilt atlas world with the game's own sightline model:
* Something authored is in sight within 700 m at every 75 m of the road.
* No dry ground within 2 km of the road is 450 m from anything.

The sparseness is on screen, not on the map. The streamer builds five cells across, so nothing past
about 0.6 km is drawn but the ground. The Stair Head "sees" Merrowby, the Toll and the Brow Beacon,
and above Pilgrim's Ash the model sees the Grandfather, and none of them is there. `docs/HORIZON.md`
is the list a horizon layer draws from. It covers the landmark models' measured heights and
silhouettes, every tall point of interest, settlement rooflines, the Thornmarch and the Hushline as
bands, and what is lit at night. The graphics owner has it.

**Three thin stretches, filled.**
* Minute 7, the Choir to the Glass Bridge, had nobody and nothing new. The Sweeper's Lean-To is there
  now. Arn Sweeting is a pilgrim who came back up the Stair, sweeps the grey off the road and gives
  **The Swept Road**: a bell to the new Turning Cairn on the Stair's last bend, to tie, ring or keep.
  His box gives up something new after each of three main-line quests.
* Minutes 11 to 14 were a road that climbed to a via point on a knoll and came back. The via keeps to
  the valley floor now, and the builder cuts such spurs besides.
* Minute 17 has the Hayward's Perch. The Novices' Seats give the plateau's lip its view over the
  Hush.

**Rivers.** The seven that come down out of the heights fall 10 to 26 in a hundred, too steep for
the builder's meanders, so their bends are drawn. Each swing sits on the low side of the old line.
Bridges, fords and falls are held, and every mouth is where it was. The land agent meanders the slow
rivers, and every drawn point is an exact anchor. `"meander": 0` on the Blackgill is still to add,
once the schema is on main.

**Grandfather Hollow.** The town and the tree share one centre, and its fabric was being laid inside
the trunk.
* The builder (4bc399f6) lays a ring street at 48 m, which the four roads end on, and a spur at 304°
  to the trunk's foot, on a pad flat to 72 m.
* WorldDoors reserves every landmark's footprint, and the fabric keeps its houses and props off
  reserved ground.
* The door at the spur opens into **the Hollow**, a new forged house. It is the first rooms in the
  heartwood, where Cille Tamwood, the Keeper of Knots, lives. The Hearth-Roll on its shelf tells the
  tree's story and leads into her quest.

### Tests

* test_content 43, test_books 6, test_dialogue 54, test_map_quests 9, test_quest_items 13,
  test_poi_encounters 10, test_settlements 22, test_every_door_both_ways and test_atlas (16) pass.
* The quest walker walks The Swept Road every way.
* test_poi_people fails twice until the next build: the Sweeper's Lean-To has no pad yet, and Willow
  Isle waits for the readiness merge.

### Next

* The main rebuild batches the four new pads, the redrawn rivers, the meander and the Hollow's ring.
* Then: `./run.sh quests`, test_poi_people, and the Blackgill's meander key.
## The ground at the Stair Head: black under a low sun, and the ash that was painted as charcoal

The user's playtest of main at 6985d356 (Windows, Godot 4.7.1, Forward+, RX 9070 XT) opened on
black ground at the Stair Head: the sky, the colossi, the character, the tent and the grass lit,
and the terrain near-black with a faint grey speckle. It was reported as Forward+'s. It is not:
Compatibility on this machine gives the same frame, and did before anyone looked. The whole
foreground of the start's first view read sRGB 10, 8, 14 with a spread of 0.7 -- no texture at
all, just the grade's shadow lift (`#2c2848` x 0.2) with nothing under it.

Two faults, and the light was the larger.

* **The light.** A new game hands over at 7.2 h, and Cinderlea's latitude (scale 0.5, bias -8)
  puts its sun at six degrees then. A sun that low lights flat ground at a graze, so what the
  ground shows is the fill, which was 0.77 of a violet. Terrain3D's grey debug view (every
  material at albedo 0.2, 25 times the ash) came out exactly as black as the ash did, so no
  texture would have been seen under that light. Dark ground in dim light lands in the toe of
  Godot's ACES curve, which takes the darkest values to zero, and the region's contrast of 1.1,
  applied after the tonemap, took everything under a twentieth of the display to black.
* **The ash.** `ash_soil` was painted as charcoal (`#121110` to `#383532`, a mean of 0.017 in
  linear light) and then multiplied by the slot's 0.45 like every other texture, which is meant
  to bring a texture painted at a comfortable value down to a ground albedo: it drew at 0.008, a
  twelfth of vale grass, and the camp's ground is 48% ash, 37% grey grass and 15% fused stone
  (0.020). Relighting the ash alone changed nothing in the frame at the handover.

Mended:

* `low_sun_fill`, a region light key (default 1): the fill is multiplied by it while the sun is up
  and low -- all of it under four degrees, none by twenty-four, none at night
  (`Atmosphere.fill_lift`). Cinderlea asks for 4. Its noon is unchanged by it.
* Cinderlea's contrast 1.1 -> 1.0, and its fill `#8c84b4` -> `#a09ab2`, a greyer violet, so a
  strong fill reads as ash in shade rather than as purple.
* The ash texture relit in linear light (2.7 x c^0.85, the height channel untouched) to a mean of
  0.085, drawn at 0.038; the generator's colours are the old ones under the same curve. The fused
  stone's value 0.42 -> 0.75, drawn at 0.035, in `import_terrain.gd` and `terrain_assets.tres`.
* `tests/unit/test_ground_albedo.gd`: no slot may draw under 0.02 (texture mean x albedo_color),
  the ash stays within a factor of two of the grey grass, and the importer's table and the
  resource agree. `tools/world/ground_albedo.py` prints the table and, in a built world, what the
  ground is made of at a point.

Measured on Compatibility, the foreground of the start's frames (sRGB, mean over the lower third):

| shot | before | after |
|---|---|---|
| the handover, 7.2 h, thin sun | 10, 8, 14 (spread 0.7) | 34, 24, 25 (spread 7.0) |
| the way north | 11, 10, 15 | 34, 26, 32 |
| noon | 43, 33, 27 | 57, 46, 36 |
| still grey, 10 h | 24, 18, 16 | 37, 30, 24 |

To find it, the capture runner takes a per-shot `"look"` (region light keys laid over the
region's own for one shot) and `"terrain_view"` (Terrain3D's debug views), and writes the light
each frame was taken in into perf.json; the debug console has `look <key> <value>` / `look reset`
and `terrain grey|checkered|off`, so the same experiment can be run on a player's machine.

Test on f4c07214: 1600 tests, 0 failed. Forward+ is unverified: lavapipe crashed on all three
attempts at the new-game plan (the `propagate_notification()` error, then signal 11).

### The dead ash trees and the grass tufts at the Stair Head

With the ground readable, two things on it read wrong. The dead ash trees read as crumpled white
paper: a near-white bark (sRGB 0.57 across the atlas, x0.6 of instance tint), on limbs three or
four sides round that the smoothing angle split at every edge (4 126 of 4 464 positions split,
normals 143 degrees apart at the median), plus -- at the mid distance -- the LOD1 bark sheets
bridging the branches that wip/graphics-settings repairs. And the grey grass tufts lay on the
ash like white litter (atlas sRGB 0.56).

* `gen_flora.grey_grass` is grey-brown, straw, one ochre and one char-dark blade; the three tufts
  are rebuilt (atlas linear 0.29 -> 0.12-0.15). They read as dry grass standing in the ash.
* `lib/materials.dead_bark` is an ash-grey (`#77716a` toward the palette's mid), with softer
  relief, streaks down the grain and rot at the foot (`_bark_common` gains `streaks` and `rot`,
  0 for every other bark); `gen_trees` lets a species name its `smooth_angle`, 180 for the dead
  ash tree. Baked on a test cylinder: sRGB median 0.35 against the old 0.54.
* The Blender 4.2 on this machine has no Sapling add-on (4.2 moved it to extensions), so no
  tree can be regrown here. `tools/forge/weather_dead_wood.py` gives the shipped trees the same
  look: the bark albedo darkened, streaked and rotted (each texel's height read from the mesh),
  the bark normals recomputed smooth, the impostor pictures darkened alike. Trees 0.54 -> 0.34,
  stumps 0.59/0.50 -> 0.28/0.21.
* **When wip/graphics-settings merges**, it brings its own tree GLBs (the LOD1 repair) and
  impostor pictures: take its versions and run
  `python3 tools/forge/weather_dead_wood.py game/assets/models/trees/cinderlea_dead_ash_tree_{a,b,c} --smooth --parts impostors,normals`
  and the same with `--parts impostors` for the two char stumps, then re-measure the three dead
  ash impostor calibrations (`tools_gd/lod_review.tscn -- --calibrate`), which were taken against
  the white bark.

Next: the full re-shoot once the atlas world is in main (the plans' cameras were drawn for the
old world); Cinderlea's street at night; the Briarwold's light shafts on Compatibility.
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

### The skyline, and the colossi that went see-through

**The colossi.** The fourth playtest saw the Choir's colossi turn half-transparent as the player
walked up to them. The GLB import gives every model that is not a tree the same level lines,
28 m and 75 m, and each level dissolves itself in and out across a margin; on a 52 m colossus
both lines fall inside the walk to its foot, and inside a margin two levels are drawn
half-dithered, which on Compatibility is see-through stone. `world/landmark_lod.gd` sizes a
landmark's lines by its height, as the trees' are (the full mesh to four heights, 210 m for a
colossus; LOD1 to ten), and a level switches outright with a 3% hysteresis. The streamer applies
it to every landmark scene as it stands it, so nothing has to be reimported. Tested: at every
distance exactly one level of the colossus is drawn, and none dissolves.

**The horizon layer** (`world/horizon_layer.gd`, from the cartographer's `docs/HORIZON.md`). Past
the streamed ring, 384 to 640 m, nothing was drawn but the ground. The layer is always loaded
and holds a stand-in for every landmark model (18: nine places, the Choir's twelve colossi from
the cells round it, less the pool and the hill figure) and every point of interest of a tall kind
(49 towers, falls, strange trees and giant bones, from their dressings' own far-silhouette
build). A landmark's stand-in is its model's LOD1 and LOD2 on the same sized lines as the cell's,
and a dressing's is the silhouette a far-ring cell raises, so the stand-in is hidden in the frame
its cell is built and shown in the frame it goes: the same picture either side, never two. It
is not held back by the sightline model: from the Stair Head at eye height the model hid 52 of
the 67, and so does the ridge in front of it, which Terrain3D draws; the model says what the map
counts as seen, and the land says what the screen shows. Towns need no stand-in: their fabric is
built for the whole world and drawn to the camera's far plane.

**View distance** (Near / Far / Epic; Low Near, Medium and High Far, Painted Epic) sets the
landmarks' reach (2.5, 4.2, 6 km), the tall places' (1.5, 2.5, 4.2 km), the player camera's far
plane (3, 4.4, 6.5 km: it was 3 km, which is where the towns stopped) and the vertices in each of
Terrain3D's clipmap rings (32, 48, 56), which is how fine the far hills are drawn. Epic was 64 and
put Painted at 1.61 M primitives from Wardens' Rest; 56 keeps it at 1.44 M.

`tools/capture/plans/skyline.json` shoots the Stair Head at five bearings, the Choir's plateau,
Wardens' Rest and the top of the Brow Beacon; `--no-horizon` shoots the world as it was (no
stand-ins, 32 vertices a ring). Worst frame, draw calls / primitives:

| | before | High (Far) | Painted (Epic) |
|---|---|---|---|
| Stair Head, worst of 5 | 756 / 0.52 M | 731 / 0.77 M | 847 / 1.14 M |
| the Choir, worst of 2 | 774 / 0.58 M | 758 / 0.82 M | 961 / 1.24 M |
| Wardens' Rest, worst of 2 | 834 / 0.75 M | 820 / 1.02 M | 1031 / 1.44 M |
| the Brow Beacon, worst of 2 | 637 / 0.72 M | 648 / 0.95 M | 749 / 1.33 M |

The stand-ins cost next to nothing in draw calls (the layer is 67 small meshes); the primitives
are the finer terrain. From the Brow Beacon at Far the Choir's twelve colossi stand on the
western skyline, 2.6 km off, where before there was haze.

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

## The world builder: meanders that vary, falls as data, a faster scatter, pads off the roads

**Meanders** (721c9e73). A river's bends are a sine-generated curve whose swing, wavelength
and skew drift along it: lazy bends, goose-necks, the odd straight reach. Beside a tight bend on
a floodplain lies the odd oxbow of still water, carved and wet but not in rivers.json. A river
keeps a point every 10 m.

**Falls as data** (77469aab). rivers.json gives each river's `falls`: top, foot, height, width,
run, facing and kind (`fall` or `cascade`). Where there is room, a fall of 6 m or more has a
plunge pool carved at its foot (CONTRACTS 6). The rebuild3 world has 56 falls and 8 pools.

**Build time** (e40f8f32). The scatter reads each field only where a candidate still stands a
chance. On the same inputs its 1024 output is byte-identical, and it runs in 69 s instead of
426 s. test_build runs in under three minutes. At 4096 the scatter was 625 s of rebuild3's
1067 s; it should fall by the same share. A 4096 build is yet to measure it.

**Roads off their grade** (630e7884). A pad laid again after the roads blended its skirt over
the land they were graded against. It now leaves their corridors alone outside its level core.
The 1024 count of roads off their grade (40) is mostly the 8 m texel on sidelong ground. On the
4096 rebuild3 world, built before this fix, three roads fail test_roads, all in a pad's skirt:
Chain Bridge to Windgate by Kharrow Hold, and the Fernhold and Hazelwick roads by Grandfather
Hollow.

**Fixed along the way:** Grandfather Hollow's door spur had four points, which the game's
test_world_data reads as a stub (6732a9c5). `radius_level_m` is written unrounded (e40f8f32).

## Correction: the 1024 road counts were my measuring tool's error

The figures for roads off their grade at 1024 in the entries above and in commit messages (39,
40 and 41, "mostly the 8 m texel on sidelong ground", including 630e7884's) are wrong, and that
diagnosis is disproved. My scratch tool sampled the heights half a texel off, which is 4 m
diagonally at 1024. test_roads' own sampler has no such offset.

Measured correctly, on the same 1024 builds, 7 roads are off their grade, by 2.3 to 3.6 m against
allowances of 2.3 to 2.4. The one larger miss, Skarlow's street at 6.9 m, is where the street
ends 2.5 m inside the level core and the bilinear sample reaches a texel past the pad's edge,
which a 2 m texel does not.

The earlier river-float figures had the same offset and were corrected above. The 4096 figures
(three roads on rebuild3) came from the test itself and stand.

A cut-and-fill bench with a 1:1 batter was tried for narrow roads on sidelong ground. At 1024 it
made no difference to the corrected count, and a bench wider than the carriageway terraced a
steep road (the Sunken Choir's, 3.6 m). It was not kept.

## Crags and outcrops, and the countryside between the places

**Crags** (e1bf3041, 60881b45). `worldgen/crags.py` sets rock on the land where the land is
steep enough to show it: slabs leaned into faces steeper than 35 degrees, sunk 0.45 of their
depth, sized to the face and turned to face down it; boulders on the crests (topographic position
2.5 m and up). The rock is the region's: cliff slabs (limestone in Skerrow, granite in the north,
from the region's palette) and Cinderlea's new basalt columns. They keep 10 m off roads, 8 m off
water and off every pad, and in a sightline's corridor a piece may not rise within 1 m of the
ray. The 1024 world has 17,438 face pieces and 6,325 crest outcrops, and all 197 sightlines are
still clear. Median draws in a 5 x 5 view went from 969 to 1,069 (worst 1,400 to 1,583).

The basalt columns first came out a pale, plasticky blue-grey. The `basalt` material is now
dark (#1f2023, role dark), and the columns were rebuilt.

**The countryside** (playtest 4). The scatter has a `countryside` rule set per landform, read
after every other rule so none of the existing draws move. It knows three new things about a
point: the field it lies in (`parcel`: the same number the ground textures sow by, so the barley
stands in the fields that are painted as barley), how far it is from a settlement (`near_place`),
and how much wood stands there (`wood_edge`: a wood's margin is its thin outer strip). What it
adds:
- meadow grass as continuous fields on the pasture and open ground, and thicker in the hay
  fields, where buttercups and ox-eye daisies grow through it; buttercup and daisy drifts in
  the pasture;
- barley thick to the headland in the sown fields, thickest near a village, with poppies at the
  hedges and hay bales in the hay fields near a place;
- bracken, foxgloves and bramble at the woods' margins and on the hedgebanks;
- oak saplings in spreading copses, lone veteran oaks in the pasture, hawthorn scrub, and in
  Sedgemire a lone old willow in place of the oak (Sedgemire has no oak of its own, and the
  fallback drew Briarwold's giant oak);
- fallen logs at the woods' edges and under the Briarwold, and the odd one by a hedge.

Birch copses and hazel on the hedgebanks are in the rules but draw nothing until those trees
are built. The tree forge has them.

New in the forge: `meadow_grass`, `buttercup` and `oxeye_daisy` (gen_flora; a head flower's eye
now has its own colour, since the daisy's second colour tinted its petals too) and `fallen_log`
(gen_rocks). They are pinned at the end of TABLES. The weight cap is now 200 MB
(test_output.py says why).

A first cut softened the woods' band below zero, so every field counted as half a wood's edge
and had bracken on it (+150,000 in the world). The band now stops at no wood at all.

At 1024, before and after:
- assets per cell, mean: 33.7 to 39.1;
- draws in a 5 x 5 view, median: 1,077 to 1,233 (worst 1,575 to 1,717);
- flora in the inner 3 x 3: instances, worst 77 k to 143 k; triangles, worst 1.5 M to 2.5 M
  (median 0.6 M to 1.0 M). The graphics density setting thins it in the near ring;
- the build: the scatter goes from 86 s to about 175 s, peaking at 3.3 GB instead of 2.3 GB.
  Most of this is Sedgemire's meadow grass (770 k) and the barley (400 k).
## The opening on the atlas: Phase B

The opening's work carried onto the drawn atlas.

### The Stair Head

* **The way out.**
  * The Wardens' poles, bells, signpost and lamp stand along the way out. That is where the marked way leaves the camp. In the atlas it goes west along the knoll first, not towards the Choir.
  * The way stops 40 m short of the Choir, inside the Naming's 45 m reach radius. The last stone stands where the objective is done, not inside the first colossus.
* **The cart.** The Wardens' cart takes the first of six places that leaves the camp's own way clear. A test holds every solid body within 40 m of the camp off the way's legs.
* **The Cantor's Seat door.** The Choir's side door says what is behind it: its prompt reads "(deadly)" for danger 5 and "(dangerous)" for danger 4. It is left as a detour for the curious, with a warning, and not marked on the way.
* **The Hushline Stair.** The atlas draws it as the road `core:road/stair_head_hushline_stair`, 646 m of switchbacks down the bank.
  * It is laid in stone treads wherever the road rises more than 7 cm a metre.
  * Where one side falls 0.6 m more than the other, a waist-high parapet runs on the downhill side, sloped with the road and solid.
  * The wall stops 5 m short of every bend sharper than 30 degrees, because the next leg of a switchback comes back through the last one's side.
  * `test_the_start` walks the road's middle a body wide and meets no wall. It found 37 wall runs beside the road and none across it.
* **Camp life.** The crows are there. A tethered animal needs a quadruped, and the game has none, so the camp has no animals besides them.

### The opening's shots

* **The Mere.** It looks up the Stride Ness causeway to where it lands in Tollmere's harbour bight, with the Spire at the island's high end. The end key keeps the causeway leading in.
* **The Spire.** It looks in from the Mere to the south-east, 360 m out over the water, with its rock and the town behind. From the island's own hump its rock hid the Spire's foot.
* **The Stair.** It opens low on the bank, with the stair's traverse climbing across it to the camp.

### Fixes sent to the batch

* **Control hints.** They read the interact key on the physics tick. A press and release inside one drawn frame was missed under load.
* **The Warden's talk test.** It finds her again at every step instead of holding a node that could be freed between steps.

## The shores: coasts, coves, stacks, dunes, reed beds and the marsh

`worldgen/shores.py` gives the land where it meets the water its kinds, and shapes them at full
resolution after everything else is laid (off the pads, roads, rivers and sightlines).

**The sea's shores.** Each stretch of coast is planned from the atlas as sand, shingle, rock,
cliff or mud. A cliff path makes it cliff. Otherwise the landform behind decides, and whether the
shore is a bay, a straight or a headland: sand in the bays, rock on the headlands, rock on the
Skerrow shore, mud on Sedgemire's. Each kind blends into the next over about 45 m. Measured only
to the nearest coastline, the seams ran straight out to sea and the shallows came in rectangles.
- A sandy bay has a shallow foreshore (under 3 m deep 110 m out) and a dune belt 90 to 190 m deep
  behind it, 2 to 6.5 m high.
- A shingle beach has a storm berm.
- A rocky shore has a ledge 1 to 2 m up and a reef out into the water.
- The Sedgemire coast has tide-flats under 1.6 m deep for 180 m.
- Most cliffs have a wave-cut platform at their foot, 14 to 62 m wide. It stands just out of the
  water, with pools in sheets, and its lip drops to the sea floor. Where the plan gives no
  platform, the cliff plunges into deep water.
- There are sea stacks off the cliffs (19 at 1024, up to 0.8 of the cliff's height) with the
  stumps of fallen ones round them, and skerries off the rocky shores (44).
- Coves are cut back into the cliffs, each with a sand or shingle beach at its head (3 at 1024,
  all on the east cliffs). Pads, roads and sightlines rule out most of the south coast, and no
  cove goes where the land round it stands over 200 m. The first cut had one in Skerrow's 370 m
  wall: a slot, not a cove.

**The Tide Mouth.** An authored pad of 8 m or less at a cliff's foot gets a lobe of rock at its
level (less 0.35 m) out into the water, with a broken edge and a step down to the platform. The
Tide Mouth's 4 m pad was a two-texel pillar in 10 m of sea. It is now a shelf about 70 m across
at the foot of the 120 m face, and the platform runs to it along the cliff's foot from the
Hushline. test_atlas_map still finds the pad itself 16 m outside the atlas's coast polygon. That
is the atlas's to move, not the build's.

**The marsh.** A delta province's low ground, from 60 m in from the sea, is cut with two sets of
creeks (2.5 to 7 m wide) and pitted with small pools. Both hold water at the marsh's table: the
water maps take them as `extra`, since the opening that keeps the marsh's own pools from
speckling would erase anything that narrow. They are left out of `water_d`: counted as
riverbanks, they had the willows and alders standing over the whole marsh.

**The classes as built** are written to `runtime/shore_1024.u8` (CONTRACTS 6) for the water's foam
and the shore's sound:
- 0 none, 1 sand, 2 shingle, 3 rock, 4 cliff, 5 mud, 6 reeds;
- the land within 60 m of the water carries its own bank's kind, and the water within 60 m the
  kind of the bank it laps;
- lakes and rivers are classed by their banks: steep is rock or cliff, the lake's reed shore or
  gentle marsh ground is reeds, other gentle ground is mud, the rest shingle.
The textures fold them in: sand and dunes on `sand_flats` (grey on Cinderlea's ash), shingle,
rock by region, mud. The water agent has the list.

**Scatter** (`scatter_rules` `shores`, after every other rule so none of their draws move):
- wrack drifts and driftwood along the tide line;
- marram on the dunes, on the crests;
- boulders on the platforms and skerries;
- reed beds out into the lakes' shallows, bulrush, and sedge on the mud;
- sedge tussocks over the wet marsh.
The land's own plants keep off a beach's lower 24 m, off rock at the water, and off the
platforms and ledges. New in the forge: marram (Hearthvale, Cinderlea), sedge tussock and wrack
(Sedgemire), and driftwood (silvered, barkless, on a new `driftwood_log` material; dead bark's
fissures read as cobbles on a log).

At 1024, before and after:
- median draws in a 5 x 5 view: 1,232 to 1,281 (+4%); worst 1,709 to 1,721;
- flora in the inner 3 x 3: unchanged (worst 148 k, 2.5 M triangles);
- the shores stage takes about 5 s;
- the scatter took 167 s before and 221 s after, peaking at 3.2 GB either way. Some of that
  was other load on the machine.

Fixed along the way:
- The first cut laid a rocky shore's ledge over the Hushline's shelf and brought it down to 2 m.
  An authored shelf is now left exactly as drawn.
- The marsh's creeks cut into Oulea's pad, which was then level on only 93% of it. The marsh
  now keeps off every pad.
- test_atlas_world's flat-pad check took a square a texel either side of the pad. At 16 m
  texels that reached the cliff face 16 m behind the Tide Mouth, and it failed on batch3 before
  any of this. It now takes the texels whose centres lie within the pad's core.

## Batch 3's pre-flight, the build's memory, and crags and sea cliffs in cliff ledges

**Pre-flight at 2048** (batch 3 at c8c41767). The build finished clean in 605 s, at a load
average of 16 to 18 on four cores, with a peak of 4.21 GB, reached in the scatter. The heights
stage reached 1.7 GB and the textures 2.1 GB. Stage times (s): regions 100.6, heights 154.1,
roads 50.7, water 27.3, textures 17.4, scatter 199.8, write 28.8; the rest are under 10 s each.
5.73 M scatter instances. The Tide Mouth's pad, moved ashore to (-601, 3780), is level at 4.00 m
with no water in its core, and the shelf still forms in front of it at 3.5 to 3.8 m.

**Where the memory goes.** A second 2048 build recorded the resident memory at the end of each
stage. The build holds 2.07 GB going into the scatter. The texture stage added 0.67 GB of that:
the surface context's patch fields, the regions' soft weights, the dither, the settlements'
footprints, the distance to the sea and the road's profile. The scatter's own rows add 1.78 GB:
5.65 M rows at about 315 bytes each, as Python lists. That part is the same at any size.

The surface context now lets go of everything but the slope once the colour map is made
(`SurfaceContext.release`). At 4096 that is about 1.4 GB not held through the scatter, and a 512
build's output is byte for byte the same with it. The rows could be kept in arrays instead of
lists for about another 1.5 GB at any size; that is a larger change and not made. It rides with
the ledges into batch 4: batch 3 had the memory to spare.

**Cliff ledges.** The settlements agent's forge rock, `cliff_ledge` (a8eeb044, in batch 3 from
165f1212), is a module of bedded rock 5 m wide whose ends are cut to its beds' own profile, so
ledges side by side meet as one face. The crags use it where a region has it:
- **A crag on a face** is a run of 2 to 7 ledges along the face's contour, one level and one scale
  throughout so the ends meet, stacked up to four rows. Each row is set back up the slope until
  its flat back is in the hill, and each ledge's foot is under the ground at its front. A boulder
  covers each end of every row. The tallest ledge that seats on the run's gentlest ground is used.
- **A steep brow** (a slope of 0.55 and over) takes a short run of the smallest ledge instead of a
  boulder. The gentler crests keep their boulders. Cinderlea keeps its basalt columns inland.
- **The sea cliffs** (`coast_walls`): each of the atlas's cliffs of 10 m and over is dressed from
  the water to its top, at a scale that grows with the cliff (1.0 at 45 m, up to 2.2). Every
  column of one cliff takes the same ledge at the same height, so its beds run level along the
  whole cliff; its stacks take the same beds. Each bed stands where the wall's face crosses its
  middle height, a metre proud of it, and only where the wall is steep. A cave's pad at the
  cliff's foot keeps the wall 10 m clear of it up to 14 m over its level.
- **Bug found and fixed:** the beds were laid only to the height the atlas drew the cliff (78 m on
  the line past the Tide Mouth); the land behind stands at 120 m, and the top third was bare.

In the last 1024 build with all of it on (L1024, ee6badc6): 19,163 ledges on the faces, 4,151 on
the brows, and 26,893 on six sea cliffs, 882 of them round the stacks. The worst cell (the
Skerrow's north-west wall) has 2,386 ledges of 4 assets. Draw calls hardly move: a cell has at
most 8 ledge assets, and the worst 5 x 5 view is 1,729 draws against 1,709. Triangles are the
cost: from 40 m out from that wall, the scatter LOD ladder draws 132 ledges whole, 873 at LOD1
and 7,662 at LOD2, 3.75 M triangles (19.9 M were they all whole), where the rock was 2.2 M before.

**Not in batch 3.** The first in-engine look at L1024 had broken ground (below), but it showed
the rock itself: a sea cliff read as a wall of sandbags, every seam lined up from the water to the
top and one mesh repeated every 4.7 m for 300 m, and the crags read as curved walls of blocks. So
batch 3 was built without them, and they lead batch 4 with:
- each bed of a sea cliff and each row of a crag slid along the face by its own share of a
  module, so no seam stands over the one below; each module a little in or out;
- a sea cliff's beds soft (weathered back along the whole cliff, never two together), hard
  (running on across the bays) or between (standing only on the buttresses);
- a real in-engine look at 1024 with the ground drawn, which has not been done yet: test builds
  are held while batch 3 is built and verified.

**Why the 1024 look had no ground.** The terrain import and the game both set Terrain3D's vertex
spacing to 2 m, the 4096 build's texel. A 1024 build went in as one region, a 2 km square in the
north-west corner, and the height at the world's centre came back NaN; the rocks stood over a
bare plane. Both now take the manifest's `spacing_m` (6030dbf6). That is not yet run in Godot.

## Trees grown whole, by species: no more broken wood, and three times the variety

**What the player saw.** "Trees that appear completely broken", and little variety. Every forge
tree was grown by Blender's Sapling and its wood then decimated to a triangle budget
(`lib/tree.trim_to_budget`, and `lib/export.make_lods` for LOD1). A collapse decimator does not
know what a branch is: it cut every limb into loose shards (median piece 6 triangles, the largest
trunk piece 14-57), which the leaves hid from afar and nothing hid up close. Blender 4.2 no longer
carries Sapling, so no tree could have been grown again anyway. The dead ash trees were already
regrown as whole wood by `tools/forge/dead_tree.py` (cherry-picked here); this does the same for
every leafy tree.

**The grower** (`tools/forge/lib/grow.py`, pure numpy). A table of species forms: the habit (a
leader to the top for ash, pine, alder, lime and birch; a trunk forking into co-dominant limbs for
oak, apple and willow; several stems from the root for hawthorn, yew, rowan, juniper and hazel; a
pollard's knuckle of rods), a crown envelope that prunes every branch to the species' silhouette
(dome, round, ovoid, blunt cone, umbrella, vase, shrub), tropism (ash tips lifting, willow whips
hanging, lime boughs arching), gnarl, root flare and surface roots. Every branch is one tapered
tube that starts on its parent's axis, inside the parent, and closes to a point; radii follow the
pipe rule. Ages: a sapling (slim, one stem, the leader winning) and a veteran (squat, thick,
gnarled, a storm-broken limb or two).

**Budgets are met by dropping twigs, never by slicing wood.** The grower ranks branches (finest
level first, least important first, never a branch before the twigs growing from it) and a budget
takes whole branches. `lib/tree.trim_to_budget` now does the same on a mesh, by its per-face rank or,
on a mesh without one, by whole connected pieces; it never decimates. LOD1 is the same tree trimmed
to 900 triangles with fewer sides, branches and twigs drawn at every other ring (the trunk and limbs
keep every ring: a gnarled limb drawn coarser stood a metre off its own bark, and `lod_repair` cut
holes in it), handed to `finish_asset` as an authored level so `make_lods` never collapses it.
`lod_repair` now finds nothing to cut on any tree.

**Bark and leaves.** Bark is one tiling texture per species painted in numpy (`lib/bark.py`):
interlacing furrows for oak, willow, ash and alder, fine ridges for lime, orange plates for pine,
red-brown flakes for yew, scales for apple and hawthorn, smooth grey with lenticels for rowan and
hazel, white with dark bands for birch; UVs run round and along the wood at one scale on every
limb. Leaf-card clumps sit on the finest twigs and along the outer part of every limb, thinned toward
the crown's shell; each card takes the sunlit (warm, light) or the shaded (cool, dark) row of the
species' leaf atlas by how exposed its clump is, so a crown is shaded as one mass, the way a painted
tree is. Willows hang curtains of leaf strands from their whips (`textures.leaf_strand_atlas`); the
Briarwold giants keep their moss beards. A species' bark and leaf maps are shared by all its
variants in `trees/_species/<region>_<kind>/`, normal maps at half the albedo's size.

**Wind.** No wind vertex colour: `foliage_wind.gdshader` sways a card by its height above the
instance's root, and reads COLOR as the MultiMesh instance tint, so a baked sway weight would only
have tinted the leaves.

**Variety.** 20 new trees in the manifest, each with its impostor: a third variant for every species
that had two, saplings (oak, black ash, pine, rowan, alder) and veterans (oak, apple, hawthorn, yew,
lime); and birch and hazel, two each, for the countryside scatter's `trees/birch` and `trees/hazel`.
Their seeds are pinned (`TREE_VARIETY_SEED`, `COUNTRY_TREE_SEED`) and appended after the weapons, not
to `TABLES`, so no table appended there can re-roll them; all 378 existing entries are unchanged.
The world's scatter takes every `<region>_<kind>_*` it finds, so they join the others with no rule of
their own -- but only when the world is next built: the generated cells name their assets, and this
branch does not touch game/world/generated.

**Budgets.** LOD0 wood at most 4200 triangles (the giant oaks 3800), cards 1150 (760 under 6 m):
LOD0 totals 1 221-6 499 against the Sapling trees' 4 114-8 754; LOD1 at most 900 + 420; LOD2 the
impostor's quad. The scatter's level distances are unchanged.

**Weight** (world assets, `test_total_weight`): 161.39 MB before, 153.88 MB after on this branch alone; on the merged head
168.27 MB against batch3's own 175.72 MB. The trees went from 36.67 MB to 29.22 MB with 21 more of
them, because a species' maps are shared by its variants: every species is lighter than it was
(oak, six trees, 3.47 to 2.84 MB; giant oak 3.87 to 1.78; apple 3.43 to 1.93; the two new species
1.1-1.2 MB each).

**Tests.** Forge fast suite (78, with the new `tests/test_grow.py`: every branch starts inside its
parent, a trim keeps whole branches and never orphans one, one connected piece per branch, LOD1 a
subset under 900, twigs end in points, species differ in form, every bark tiles), `test_glb_textures`,
`test_manifest_seeds`, `tools/debug/import_check.py`, and on the merged head `test_scatter_lod` (12)
and `test_world_streamer` (2): all pass. `test_glb_textures` had one failure that came in with batch3:
its stray check called the character heads' `_age.png` maps unreferenced, but `humanoid_model.gd`
loads them by path, so the check now counts them.

**Seen.** A before/after lineup of every species at 1920 (whole tree and under the crown), a variety
sheet of all 54, and two eye-level frames in the world (`trees_plan`-style shots: a Hearthvale oak
copse and a mixed Sedgemire stand; 982 draws / 1.29 M primitives at worst against 939 / 1.04 M
before, inside the 2000 / 1.5 M budget).

**How close to Oblivion or Fable, honestly.** The broken look is gone: no loose shards anywhere, every
limb runs into its trunk, twigs taper to points, the bark reads as bark up close, and the Sedgemire
stand that was a tangle of black flags is now willows with curtains and alders with crowns. The
species read apart at a glance. What is still short of that look:
- *Crowns are card clouds.* A crown is a few hundred flat clump cards; from outside it reads as a
  mass, but at its rim the cards show as flat plates and under it the clumps are separate blobs
  with sky between. Oblivion's trees had the same construction; Fable's crowns are denser and
  softer, with larger, overlapping, hand-painted clusters.
- *The dense woods now close over.* The grown trees stand at the heights the species table asks
  for; the Sapling trees came out at about 60% of it (a hawthorn 2.5-2.9 m against 4-5, a yew 3
  against 5-7). In a copse planted for the smaller trees the canopy closes and the floor goes
  near-black under a morning sun. The scatter's densities, or an instance scale, want a look.
- *The impostors' calibration is stale* until `lod_review.tscn --calibrate` is run on the new trees
  (queued as the first slot job after batch 3's verification): the rebuilt trees take the old
  trees' measured gains, and the 20 new ones the shader's defaults.
- *The willow curtain* reads as strings of sequins at thirty metres rather than as hanging leaves.
- *Pines and yews* are dark, and a pine's clumps are plates.
- *Wind* sways a whole card by height; nothing bends the wood.

### Next, in order

1. **Calibrate the pictures**: `xvfb-run ... godot --path game --rendering-driver opengl3
   res://tools_gd/lod_review.tscn -- --out=<dir> --assets=<the 54 grown trees> --calibrate`, then
   the same on Forward+ (`--rendering-driver vulkan --rendering-method forward_plus`), or drop the
   rebuilt trees' stale `forward_plus` entries so they fall back to the fresh Compatibility ones.
2. **Look at the woods' density** with the true-height trees (Hearthvale copses, Briarwold): the
   scatter's `density` per species, or a per-kind instance scale, not the trees.
3. **Softer crowns**: bigger, overlapping clump cards with painted cluster silhouettes and
   per-card tint; fewer, larger cards at LOD1.
4. **Char stumps and the dead ash** are still the Sapling stump and `dead_tree.py`'s trees; the
   grower has forms for both (`FORMS["char_stump"]`, `FORMS["dead_ash_tree"]`) if they are wanted
   from one generator.

## The opening, Phase B continued, and playtest 6's conversation and compass (2026-09-24/25)

### Verified and handed on
* **The two commits from the last session.**
  * `35404914` (the Wardens' Watch past the avenue's colossi): test_the_start 19/19 on main's world.
  * `4ac030ae` (the Choir shot looking south from the Crown): test_cinematic_paths_clear read
    main's world for the first time and failed it. The end key looked at a point off the map's
    south edge (z 5170), and the frame saw the world's edge 699 m off. `c3f49794` looks 330 m
    south of the camp, 120 m over the water. The frame's nearest line to the edge is now 717 m.
    Captured at 0, 0.5 and 1: the colossi either side, the waystones, the rim and the Hush to the
    horizon, and no edge.
* **Tests that checked nothing.** The tracked world carries only the runtime 8 m heights.
  test_cinematic_paths_clear (3 tests) and three of test_the_start's ground tests returned
  "ok" on it without checking anything. They now read the runtime copy, as the game does. The
  cinematic judges clearance against the highest texel of the cell a camera is over (`a773fb72`).

### The start, read from the manifest
* `PlayerSpawn.manifest_start` reads the manifest's `start` (the atlas's own) when it names the
  opening's place and stands within 60 m of it. It puts the body there, facing `facing_deg`.
* On main's world: (10, 107.66, 3670), facing 333°, the Stair Head's own spot. The bearing to the
  Choir is 333°.
* A start of another place, one that has drifted off its place, or none at all falls back to the
  place. test_the_start is 20/20 (`ac9e052c`).
* `first_fight.json` says its bodies from the Choir, on the built road's last legs.
  `route_check.py` follows the way as the game does and reads the runtime copy.

### The Stair Head to the Choir: 526 m, not 980
On main's world (batch 3, atlas a2775553), the waystones walk the built road
`core:road/stair_head_sunken_choir`: 45 points, 526 m to the last stone, 32 m short of the
Choir's centre. The start test wants 300–650 m and passes. `route_check.py game` says OK: no
slope over 30°, no water, no foe within 50 m, nothing solid on the way. The 980 m was the older
w_final3/4 build. The atlas needs no change for the opening.

### The shots
* **Merrowby**: the town in the foreground and the Cracked Toll on its mound beyond. It holds.
  A tree crosses the bottom-left corner of the end frame.
* **The Roll**: 220 m out and 30 m up, Wardens' Rest was a scatter of cottages in a field. The
  shot now comes in to 88–115 m and 11–14 m up. Wardens' Rest is a fort in the atlas, and its
  dressing is still a hamlet's cottages. Neither the Roll Stone (three thin white pillars) nor
  Ashcombe (one small ruin) made a better subject. Both were scouted and looked at.
* **The Toll**: kept as it was (110/92 m out, 12 m up). The whole bell stands against the dusk
  sky with trees in front. Three closer framings were tried:
  * The first flew through an oak at the field hedge (test_cinematic_paths_clear said where).
  * The second passed through a hawthorn inside the hedge.
  * The third, at 54–56 m and 6.5 m up, cut off the bell's crown and put the mound's texture in
    the front of the frame.
  The mound is the landmark model's green dome with jagged white patches, and it reads as a
  cartoon close up (a model matter, reported).

### Playtest 6
* **Conversation** (`be552d7a`). The body is held while a conversation runs, whichever way it
  ends. W and S move the focus among the answers, and E takes the one in focus. An answer is
  taken once. test_dialogue_keys presses the keys through Input: S twice then E takes the third
  answer. The Warden's talk test holds W for a second of wall time mid-talk and takes the goodbye
  with S and E.
* **The talk test's flake** (`25e0ec2e`). It waits up to 10 s of wall time for Wren to turn and
  the camera to frame her, instead of counting 60 frames. It passed with 12 Godot processes on
  the machine.
* **The compass** (DECISIONS 2026-09-25, DESIGN §5.16). `CompassRules` gives each kind of place a
  range and a notice range, and caps the strip at seven. `tools/capture/plans/compass.json`
  shoots the HUD over a body. What the strip showed (logged), with nothing found, then everything:
  * Merrowby's green: the Cracked Toll (unfound, faint), Larkbourne Ford, Bell Meadow Stones.
    Everything found: seven (the Toll, Tollmere, Wynstead, Stride's Foot, Larkfield, the Pinfold,
    Pennywort Bridge).
  * The Glass Bridge cluster: seven either way, the Choir and Merrowby among them.
  * The emptiest road (West Walk): nothing unfound. Found: Isseva and the Strand Beacon.
  * The Stair Head: the Sunken Choir, faint, from the first moment. The first objective's
    destination is on the strip before it is found.

  Looked at the strips cropped at double size. The faint icons are grey and small, the found ones
  ink, with no crowding. test_compass_rules (7) and test_compass pass. The flake in
  test_talk_to_the_warden is fixed in 25e0ec2e.
## Batch 4's world: falls that step, rock that sits, roads that are planted, and half the memory

What playtest 5 and the batch 3 shots asked of the land, and what was measured of it. Head at the
last 1024 build: 7868bf02 (b4, scratchpad/world-builder/b4).

**Falls stand as towers.** Every waterfall POI's pad was a disc of level ground. The dressing stood
its face of ledges on it with the sky behind, and a river through the pad ran level across it. Now
`worldgen.falls` steps the pad: level at its foot in front of the face, and higher behind each
face by that face's drop. The forms are the dressing's own: a single face 11 m, 6 m behind the
centre; the glass fall 13 m, 7 m back; three tiers of 4.6 m at 2, 8 and 14 m. On a river the step
faces downstream. Its top is no higher than the lowest land the river crosses above it, from its
source down. The river has a point pinned at each face's foot and lip, so its surface drops at the
face and rivers.json has the fall there. pois.json's `fall` says where the step is (CONTRACTS §6).
- On b4 all ten are stepped. Eight have the full drop; the Three Sisters has 12.9 m and the
  Blackgill 4.2 m, since the land below them does not fall further within 450 m. At Whitecut the
  land reads 19.7 m at the centre, 31.0 m 8 m behind and 33.7 m past that, and the Larkbourne
  falls 9.3 m there, into a plunge pool.
- At 8 m texels the 3 m step is smeared over one texel, so on a 1024 the rivers' drops come out
  as cascades, or not at all for the Three Sisters' 4.6 m tiers. That needs a 4096 look.
- First try, found by looking at the numbers: the top had been capped by the land only 300 m up
  the river. Three steps (Whitecut, Foxfire, Wold Force) were cut back to a 3 m slope, because
  keep_channels holds the land near a river to its carve, and the river's surface came to the
  step under its lip.
- **The dressing has to follow.** Shot on b4 with main's dressing: Whitecut and the Foxfire are
  still towers of blocks, now standing sideways to a real step behind them. The dressing picks its
  own facing (grain(): road, water, downhill) and stands its columns from the ground at each one's
  foot. The contract for settlements: take facing_deg, stand the face from foot_m, drop the brow
  where `fall` exists (sent to the coordinator).

**Rock is seated, and comes in groups.** A scattered rock stood upright with the middle of its
foot on the ground, its downhill side over air. Now every rock rule's rock leans back with the
slope (0.45 to 0.8 of its angle, the row's lean pair, about the foot) and sinks until its downhill
edge is in the ground, then 12 to 22% of its height more (never over 55%). Logs and driftwood lie
along it. The crags' crest outcrops, which were the worst (up to 2.2 scale on slopes to 1.2),
are seated the same way. 70% of a boulder rule's boulders have 2 to 5 smaller stones round them,
most of them fallen downhill; parent densities come down about 40% to pay for them. Scatter rock


**Roads are planted.** `roadside.planting` puts a verge along both edges of every road through
open country (about 1.2 plants a metre in the Vale), a hedge or a drystone wall in runs along a
third to a half of it, and the odd tree set back. All of it is by landform, and none of it goes on
pads, water, carriageways or steep ground. On b4: 61,210 rows.

**Nothing stands in the water.** `dry.sweep` takes out every prop and tree inside a river's channel
(measured to the centreline, not the texel) or on the water mask, after everything is placed: 73
on b4, most of them rails and new hedge by fords. The POI dressings were the cart. PoiKit.place and
scatter now move a land prop in water to the nearest dry ground within 9 m, or leave it out.
test_poi_dry found carts, signposts, benches, sacks and a millstone in the water on main's world:
at the Barkbridge (the Briarwold cart), the Larkbourne and Oskel fords, the Narrows, the log boom,
Skarl Mill and the Whitecut. It passes now.

**Memory.** The scatter's rows are float32 columns until they are written (`worldgen.rows.Rows`),
and the cells come out byte for byte the same (9,977,949 bytes of JSON checked against the list
code). Peak at 1024: 3.16 GB (seat1024, before) to 1.53 GB (b4). The builds ran at a load of 20
to 30 on 4 cores, so their times are not comparable: b4 took 626 s, its heights 44.6 s against
14.6 s on a quieter machine.

**A 1024 preview's ground.** 6030dbf6 alone left a 1024 build as one region with NaN at the centre.
Terrain3D's regions lie on a 1024-sample grid from the origin, and at 8 m the world's corner is half
a region off it. The import now pads the maps out to the grid (7868bf02). A 1024 build makes 4
regions, with the Mere at 4.40 m and the Stair Head at 108.37 m, the build's own figure. Main has
both commits.

**What the b4 shots show** (Compatibility, 1280x720, at a load of 15 to 30):
- The Whitecut and the Foxfire are still towers of chalk and dark blocks. They now stand across the
  river beside a real step, with the Larkbourne going over it as white water behind the tower. The
  dressing has to read `fall`; see above.
- The Barkbridge's cart stands on the bank by the bridge, not in the Briarwold's river.
- The roads in the Vale, the lake shoulder, the Briarwold and the fells read as travelled: verge
  growth along both edges, rails, hedge or wall in runs, trees stood back. The Briarwold's foxglove
  verge reads as a row.
- An inland Skerrow crag close to: the ledges stagger, but a face of three rows still reads as rows
  of loaves stacked up the slope.
- The rock shots were framed too near to judge the seating (the camera stood 14 m downhill of the
  biggest leaning rock and was inside a slab or in the dark), and the far ledge shot was under the
  sea. The Glass Falls' camera looked into its own slope. These are the plan's faults, not the
  world's.
- In one frame at the Kharrow Force, the river's water drew as a curved sheet over the ground where
  it cascades 28 m on an 8 m grid: the water surface's, at 1024.
- The worst frame had 1,021 draw calls and 0.96 M primitives, against a budget of 2,000 and 1.5 M.

**Not done.** No 4096 was built on this branch: the coordinator builds batch 4 in the main checkout.
Its peak is estimated at 3.2 to 3.6 GB (6.19 GB before, less the 1.4 GB the surface context lets go
and the rows' ~1.5 GB), not measured. A fall's river drop, as a sheet rather than a cascade, can only
be seen at 4096, where the 3 m step is resolved.
## Between the places: the gap map, and the wayside finds (cartographer, 2026-09-24)

The user's fifth playtest: "the world still feels empty between places." The atlas keeps its
coverage rule: nothing on a road is more than 250 m from a location. The complaint is still true,
because 250 m either side of a thing allows a 500 m walk between two things. The previous
session's gap map and its first wave of finds were never committed and were lost with its
container. This redoes both, as a committed tool.

### The gap map (`tools/world/atlas/gap_map.py`, da9b5513, e6ece2f7)

- **What counts as a thing:** every place and point of interest in the content packs. That
  includes the farmsteads, mills and caves and the new wayside finds (`"wayside": true`). It
  leaves out the edge and deep places. A settlement counts out to its pad radius plus 40 m of
  outskirts.
- **Passing a thing:** coming within 60 m of it.
- **A gap:** a run of built road (the build's roads.json) where you pass nothing.
- **Thin:** a gap over 300 m, which is a minute at the player's jog (5 m/s).
- **Empty country:** walkable ground more than 300 m from any thing. Walkable means dry, under
  35°, and not the closing ranges or the snowfield, as preview.py reads them.
- **What it produces:** the headline figure, a JSON work list of every thin gap, and a picture
  over the built land. `--sites` proposes where finds can stand. A site is 16–28 m off the road,
  110 m from any location including mine mouths, clear of water and roads, and on ground a 14 m
  pad can take (at most 20°, or 27° on a dale side).
- **Why the road total is 120 km:** the atlas reports 80 km over 83 roads as drawn. The "120" is
  the built roads.json: those 83 roads meandered to 116.2 km, plus 52 settlement streets
  (4.3 km). That makes 120.5 km.
- **The old "81 of 120":** this rule does not reproduce it. On the same world it gives
  65.4 km. The old figure comes out of a stricter reading. Passing within 50 m with thin at
  200 m gives 82.4 km. Counting settlements to their pad edge only, at 60 m and 200 m, gives
  80.5 km. The coordinator chose the one-minute rule, and every figure below uses it.

### Wave 1: 54 finds in the Skerrow dales and on the North Shore (3db1c3dd)

- **Where:** the 56 sites `gap_map.py --sites` proposed in the Skerrow provinces and the North
  Shore. Two were left out: a third find within 150 m on the Dreughow road, and one on the
  Clanless Camp's own ground, 137 m from its fire. Each find is a point of interest with
  `"wayside": true`. Its note or object, and any foes, are in `books/`, `items/` and
  `encounters/wayside.json`.
- **Kinds:** only kinds the kit already builds (9 waystones, 10 shrines, 11 camps, 9 vistas,
  4 standing stones, 4 ruins, 3 caves, 2 shielings, 2 giant skulls, 1 wreck).
- **The sentences:** each was written for the variant its builder actually branches on: a
  pebble shrine, an oiled stone, a hawthorn chair, a cold vigil fire, a link-keeper's chimes, a
  kiln, a broken waystone, leaning stones, a cairn or a bench. The emitter printed which words
  each sentence triggers, and none triggers a variant by accident. No find claims a sightline.
- **The voice:** the clans' Rope-Song, blood-price, chain links, bone tokens and the Breath. On
  the North Shore it is the border between the Charter and blood-price, the Tallymen's clerk, the
  eel-trappers and the Wicks of Gullhithe.
- **What lies there:** at every find, something to pick up. That is 49 notes in the voice of
  whoever keeps the place and 5 objects: a notching knife, a twist of salt, a markless bone
  token, a heifer's bell and an old toll-coin. (The WIP commit's "48 and six" was miscounted.)
- **Foes:** five finds stand some up. A scree-hag at the Horn Hole, crag-wolves at the
  Oath-Takers' Fire, clanless outriders at the Unroofed Hold and the Burned Ore-House, and a
  stone-thrall at the Listening Stones after midnight.
- **The figures, on the tracked world:**

  | | thin road (of 120.5 km) | gaps over 300 m | longest | empty country |
  |---|---|---|---|---|
  | before | 65.4 km | 100 | 1680 m | 2.3 of 43.1 km² |
  | after wave 1 | 46.3 km | 89 | 1360 m | 2.0 km² |

  Skerrow's thin road went from 19.6 to 8.1 km, and Brightwater's (the North Shore) from 10.1
  to 3.1 km. The picture is `docs/atlas/gap_map.png` (`python3 tools/world/atlas/gap_map.py
  --out ...`). It was looked at: the dale roads, once red end to end, now show short stretches
  only, on the switchbacks where no ground takes a pad.
- **Checked:**
  - `check_atlas`: 0 errors.
  - `poi_hooks --check`: 317 rows, 0 differ, 0 pay off in nothing.
  - The atlas tests with test_gap_map, run through `python3 -m unittest`: 44 passed. The
    `pytest` on PATH here has no numpy.
  - The Godot filters, each 0 failed with 0 content problems: `test_poi` (64), `test_map_quest`
    (11), `test_content` (43), `test_books` (6) and `test_quest_items` (13).
  - test_gap_map.py holds every find to a built kind, its own region, 100 m from any other
    location, no sightline claims and something lying there.
- **Not done:**
  - The finds get their 14 m pads only when the world is built from a tree carrying the world
    builder's 13b943e0.
  - None has been looked at on the ground.
  - `test_the_maps_finds_lie_in_the_open` covers the map's notes (`encounters/the_map.json`),
    not these. It should take `encounters/wayside.json` after batch 4, when the finds have
    pads.

### The atlas debts in HANDOFF §6.1–6.3, measured on the tracked world

Each debt was measured before anything was changed. The earlier session had already answered
most of them in the atlas, and batch 3's world was built from that atlas. Since then only Skarl
Mill has moved (e21615a3).

- **The Stair Head → Choir walk:** the built road is **542 m** (483 m straight). That is inside
  the 300–650 m the start test wants. The Choir stands at (−210, 3240).
- **The Heron Watch:** at (−2442, −660) it is 35 m from the North Channel's centre and 29 m from
  the built water. Its pad is level to 17.5 m and ends at 25 m, so the pad stays dry
  (9d15f9c9).
- **The Blackgill:** it ends at (2584, −1668) in the Blackgill Pot, a pool at 189 m whose level
  is the river's last surface (8ed4c31d).
- **The Thornmarch:** no province corner lies on x = 3965 any more. The crest wanders between
  about 3925 and 4030 (8ed4c31d).
- **Wat Thatcher's and Jory Wick's schedules:** walked round the water in 9d15f9c9.
- **The sightlines:** the tracked world keeps only `runtime/heights_1024.r32`, and no 4096 build
  exists on this machine. The truth, `test_sightlines` at 4096, cannot be run here. On the 1024
  runtime heights, 199 claims give 6 refusals. Two are hidden valleys, which is allowed (the
  Hidden Tarn and Foxglove Dell). Four are marginal:
  - the Oiled Stone → Mossbridge, 5.7 m over at 288 m;
  - the Rafters' Camp → Barkbridge, 5.4 m over;
  - the Fallen Hand → Rudd Pike Beacon, 5.0 m over;
  - Skarlow → the Giants' Stair, 3.9 m over.

  The old 28 are gone, including every one over 25 m. These four want the batch-4 4096 build's
  `test_sightlines` before anything is moved.


### Waves 2 to 4: the Briarwold, Hearthvale, the Mere's shores, Sedgemire, and a light touch on Cinderlea

- **Wave 2** (a35aaa77): 30 finds in the Briarwold, in the Woodfolk's voice (custom and not law,
  leave never asked, moss graves, tally-sticks, oiled stones, the Hart-Knights' mourning). Two of
  them stand on the Wold road's Vale edge. Two proposed sites were left out, each a second find
  within 145 m on the Moot road by the Antler Chapel.
- **Wave 3** (5a21f557): 29 finds.
  - Hearthvale: the Wardens' Roll and the quiet villages, the Larkbourne Boys, the Chalk Hound.
  - The Mere's shores: the weighbridge, the laundresses, the rafters, the fallen water.
  - Sedgemire: lanterns for the drowned, the Tide account's turning.
  - One site had its name clash with an existing location (the Roll Stone) and was renamed the
    Quiet Mile.
- **Wave 4** (99d892bd): 7 finds. Cinderlea gets finds only on roads empty for over about 470 m,
  one to a road, and one more goes on the Dreughow road. Left out:
  - a site 113 m from the One Poppy, which keeps its square kilometre;
  - two more on the Ash Heath's West Walk road;
  - one on the Grey Hedge's ground and one among the Glass Bridge's crowd;
  - two within 125 m of wave-1 finds, and one on Rudd Beck's bank.

**All four waves:** 120 finds.

| Kind | Finds |
|---|---|
| camps | 28 |
| waystones | 20 |
| shrines | 20 |
| vistas | 17 |
| ruins | 13 |
| standing stones | 10 |
| caves | 5 |
| shielings | 3 |
| wrecks | 2 |
| giant skulls | 2 |

They leave 108 notes and 12 objects, and 16 of them stand foes up.

| | thin road (of 120.5 km) | gaps over 300 m | longest | empty country |
|---|---|---|---|---|
| before | 65.4 km | 100 | 1680 m | 2.3 km² |
| wave 1 | 46.3 km | 89 | 1360 m | 2.0 km² |
| wave 2 | 32.9 km | 71 | 1248 m | 1.9 km² |
| wave 3 | 20.5 km | 45 | 1248 m | 1.7 km² |
| wave 4 | 18.0 km | 44 | 925 m | 1.7 km² |

By region, thin road before and after:

| Region | before | after |
|---|---|---|
| Skerrow | 19.6 km | 7.9 km |
| the Briarwold | 15.3 km | 1.7 km |
| Brightwater | 10.1 km | 0.3 km |
| Cinderlea | 9.8 km | 7.4 km |
| Hearthvale | 7.1 km | 0.3 km |
| Sedgemire | 3.4 km | 0.3 km |

**What is still thin** is mostly Skerrow's dale switchbacks, in runs of 300–500 m where no ground
takes a pad, plus the Ash Heath and the Ashgrid, which are meant to be quiet. The empty country
off the roads (1.7 km², in blobs of at most 0.09 km²) wants finds off the road. Those should be
the fold, the cairn and the tally-post when settlements builds them.

The atlas preview's density figures went from 320 locations before any find to 440, 6.8 to 9.3 a walkable km²,
and a nearest-location mean of 180 to 159 m (ATLAS §2). docs/atlas/gap_map.png is the map after
wave 4.

**Checked on waves 1 to 4 together (99d892bd):**
- The Godot filters, each 0 failed with 0 content problems: `test_poi` (64), `test_map_quest` (11),
  `test_content` (43), `test_books` (6) and `test_quest_items` (13).
- `check_atlas`: 0 errors.
- `poi_hooks --check`: 383 rows, 0 differ, 0 bare.
- The atlas tests and test_gap_map: 44 passed.

### Planned, not emitted: wave 5, off the road (waits for settlements' cairn, tally_post, fold, grave, well and lantern_post)

`gap_map.py --switchbacks` and `--offroad` (64fff3f5) propose 29 sites. Each is seen from a road
30–320 m away: an eye 1.65 m over the road sees the top of something 2.2 m tall. The sight line
is the find's reason to leave the track. The switchback sites are 35–95 m up or down the dale
side from a thin run, and the rest are one to a patch of empty country. With all 29 placed, the
road measures 14.1 km thin (18.0 now) and the empty country 1.04 km² (1.7 now).

| Where | Kind | Why here |
|---|---|---|
| **Skerrow switchbacks:** the Ruddow–Fallen Hand road (837, −2993) | cairn | a herders' cairn over the Rust Scar, where Ruddow's dead are carried down past it |
| the Windgate road above the Bier Stone (527, −2807) | cairn | a corpse-road cairn, the last sight of the Hold for the dead |
| the Ruddow road above Kharrow Hole (559, −2103) | tally_post | a debt too small for the Hole, hung where it was incurred |
| the Rudd Beck bank (727, −1799) | fold | Merrowhithe's goat-fold, where the clan herds are counted before the shore |
| the Frostmother road, in the snow (154, −3779) | cairn | an ice-cutters' marker, capped with a block that has not melted |
| the Low Road by the Drove Chain (−1591, −1985) | tally_post | the chain's unpaid news, knotted |
| below Kharrow Gate (−273, −2175) | tally_post | the travellers who would not say the law, a knot each |
| between the Tinkers' Camp and the Brakh's Eye (−2655, −2177) | fold | a fold shared by Ghast and Oskel, its gate tied with both clans' knots |
| the Ghast Dale road (−2369, −2221) | cairn | the Ghast's forgiveness cairn, a stone for each year sung |
| Skarldale (2520, −2371) | fold | the Drovers' Bothy's night-fold for the herds on the Neither Grass |
| the Moot Beacon's slope (1625, −2314) | cairn | the beacon-keepers' marker for the peat road |
| the Skerr Stone (−524, −1964) | tally_post | the Charter quarrel of 942, still owed |
| the North Shore, Gullhithe road (−1150, −1443) | cairn | a gulls' cairn the eggers build to mark the cliff nests |
| the Clanless road (−1576, −2119) | fold | a fold the Clanless took and keep, its gate facing the overhang |
| the Moot road, Ribdale (1551, −1902) | cairn | the sponsors' stones for kept oaths, moved down from the bench |
| **Off the road:** the Skarl Fells (1820, −2892) | fold | the Winter Cairns' living herd |
| the North Fen (−3588, −1764) | lantern_post | the fen's safe way to the Drowned Road |
| the Delta (−2252, 348) | lantern_post | the peat-cutters' way home in fog |
| the Mere shore by Sedgehithe (−1484, 500) | cairn | the old shoreline's water-mark |
| the Mere shore below the Limekilns (596, 508) | well | a spring the lime-burners drink from, the only sweet water on that shore |
| the West Downs by Pennywort's Mill (−684, 1164) | fold | a fold on the down above the mill that turns with no water |
| the East Downs (1052, 1812) | well | a dew-well on the down, which the Vale says Ansel dug |
| the Ash Heath west (−2988, 2052) | cairn | a pilgrims' cairn half ash |
| the Brow above Coldharbour (1900, 2404) | fold | the barrow's own flock, never counted |
| the Brow's cliff end (3388, 3260) | grave | the last field's ploughman, buried facing the Hush |
| the Brow between Candle Cross and the Naming Stone (1956, 3348) | well | the well the Naming water is drawn from |
| the Ash Heath, seen from the Stair Head road (188, 3356) | cairn | the first cairn a new game's walker can leave the road for |
| the Ashgrid by the Tower of Vaelost (−2620, 3644) | grave | a scavenger's grave with a bell on a stake |

The sentences will be written against each kind's builder once it lands, so that each words its
variants the way the builder reads them.

**The quest walker** on c3777208 (waves 1–4 plus main merged, on the tracked world): `./run.sh
quests` finished with 77 of 77 quests ending every way they can, 228 of 228 walks with branches on,
0 world notes and 0 logged errors, in 31 min.

## Foes along the roads and weapons in the country (cartographer, playtest 6)

The user's sixth playtest: "no enemies other than the starter area's; same with weapons". The
country's own spawns are kept 14 m off every road and fade out 120–420 m round every settlement.
So a road-keeper meets only what the authored encounters stand up at the places the road passes.
No weapon lay anywhere in the open world.

**Measured** with `gap_map.py --threats`. A threat is a place an encounter def stands foes up at,
met from a road within 80 m. A quiet run is more than 900 m of road with none. The safe way is
left out: the Naming's roads to Merrowby, and anything within 1.5 km of the Stair Head.

| | threats met | road outside the safe way | one every | quiet runs over 900 m |
|---|---|---|---|---|
| before (a8149f4d) | 55 | 105.8 km | 1923 m | 41, 60.8 km |
| after (a182c45f) | 114 | 105.8 km | 928 m | 4, 4.4 km |

- **Armed finds:** 46 wayside finds on the quiet roads stand foes up, in their province's own kinds
  and at hours that suit each find. Not armed: finds within 250 m of a settlement, and the
  peaceable ones (a pedlar's fire, the cart-wards, the Namers' Fire, a lamp-shrine).
- **New road encounters:** 13, each with a note (ATLAS §17).
- **Foes that stand and wait:** a warden, a Hart-Knight and the licensed bark-strippers stand at
  their places and fight only whoever strikes first.
- **Still quiet:** two of the four remaining quiet runs are Cinderlea's, meant to stay quiet.
- **Weapons:** 10 lie where the story puts them, one or two to a province, better ones deeper in.
  - The early one is an **Ashen Sword at the Last Meal Stone**, 1.0 km from the Stair Head and off
    the Naming's way. It was raised from iron because Wren now gives the Foundling a Wardens' iron
    sword.
  - The Lone Barrow's became an Iron Greatsword for the same reason.
  - The deepest is a Bell-Bronze Axe at the Windgate's Old Toll-House.

**Looked at in the engine** before batch 4: a 1024 preview built with the world builder's 14 m
wayside pads, in a throwaway worktree (removed). Twelve of sixteen shots came in before the
40-minute limit. What each showed:

| Find | Where | The pad | From the road | Floating, sunk or wet |
|---|---|---|---|---|
| the Gorge Porters | the gorge floor | sits | reads | none |
| the Link-Keeper's Fire | a knoll | sits | the chimes read | none |
| the Salt Barn | the Mere's beach | sits | reads | dry |
| Brindle's Luck | a dale side | sits | reads | none |
| the Lantern Hummock | the Delta | sits | reads | none |
| the Bowing Stones | the Choir plateau | sits | reads | none |
| the Debtors' Lean | a levelled shelf on a dale side | sits | reads | none |
| the Beacon Shieling | a dale side | marginal | reads | none |
| the Horn Hole, the Oskel Drip (caves) | dale sides | — | reads wrong | — |
| the Moss Bed | the Greatwood | too dark to judge | too dark to judge | — |
| the Rafters' Locker | the Wold Water's bank | the camera was in the foliage | — | — |

- **The Beacon Shieling:** the pad shows as a terrace with a hard front edge on the dale side,
  which 8 m texels can't settle.
- **The two caves:** each was a black block with rock heaped on its top, standing in the open.
  The throwaway worktree lacked main's 58a11764 ("a cave on a level shelf turns its back to the
  cliff over it"), so they are to be judged again on the batch-4 world with main's code.
- **The Moss Bed:** too dark under the Greatwood canopy at the shrine hour to judge.
- **The Rafters' Locker:** inconclusive, because the camera stood in the foliage.
- **Everything else:** nothing floating, sunk or in water.
- **The pads:** the build gave every one of the 120 finds a 14 m pad, and on its heights no find's
  level core (9.8 m) takes water.

**Checked on ca90b8a2:** the Godot filters, each 0 failed with 0 content problems: `test_poi`
(64), `test_map_quest` (12, including the wayside finds' open-ground test: 142 notes, objects and
weapons at 133 finds, all in the open), `test_content` (43), `test_books` (6) and
`test_quest_items` (13). check_atlas has 0 errors, and poi_hooks --check has 396 rows with 0
differing.

**Checked on d8a8fdef:** the quest walker gives 77 of 77 quests ending every way they can, 228 of
228 walks, 0 world notes and 0 logged errors, in 26 min.

**Sightlines on batch 4's world** (w4096c, the 4096 heights), using tools/sightlines.py's ray:
- 199 claims. Four were refused: the two hidden valleys, which is allowed, plus the Rafters' Camp
  to the Barkbridge (5.2 m over) and Skarlow to the Giants' Stair (4.9 m over).
- Those two now run from vantages that see their targets clear: the Oiled Stone to the Barkbridge
  (3f4b6c1b, with the id corrected in d8a8fdef), and the Black Keep to the Giants' Stair.
- Re-measured: none refused except the hidden valleys.

**The caves on w4096c with main's code** (f7eef232), in a throwaway worktree, now removed:
- **Two wave-1 caves and one batch-3 cave read the same way,** as a black block standing on the
  slope with boulders heaped on its top. They are the Horn Hole, the Briar Root, and Kharrow Hole
  (batch 3, in main since then). It is the cave dressing, not where the finds stand. It belongs to
  settlements: the mouth wants cutting into the slope, not standing on it.
- **The Oskel Drip:** its shot's camera stood inside the dale side, so it shows nothing. The POI
  capture plan puts cameras on the approach side at eye height, and on a steep slope that is in the
  hill.
- The run was stopped after four of ten shots, because the disk was at 87%.
## The water: falls, rivers in their channels, lakes and the sea

Everything that draws water: `world/water_surface.gd`, `world/river_falls.gd` (the painted-look
agent's draft of c1a927c7, reworked), and the shaders `painted_water`, `waterfall`,
`plunge_pool`, `water_spray` and `falling_water`. Seen on software Compatibility; the before and
after sheets are in the report.

**Falls.** Every fall in rivers.json is drawn (56 on the 10:44 world):
- The sheet is one mesh in two layers, the body and a looser veil of spray in front of it. The
  streaks are ropes laid out in falling time, so they stretch as the water accelerates. There is a
  green tongue at the lip, the water is white from about a third of the way down, and the edges
  are ragged and see-through. A `fall` leaves its lip in an arc. A `cascade` lies on the river's
  own carved line down the face, in steps whose spacing wanders and whose breaks waver across it.
- Where it lands there is a churning disc over the file's pool (or over the river where there is
  none): foam carried outward, rings of ripple, deep in the middle.
- Spray and mist are particles scaled by the height, with their own soft-puff shader.
- One looping 3D voice of the `waterfall` ambience moves to whichever fall is nearest the camera
  (AmbienceMixer has beds and one-shots, no positional emitter).
- The river's ribbon stops at every lip and starts again at the foot.
- A waterfall place no river runs through (Whitecut, Foxfire, the Three Sisters) has its plain
  `Fall<n>` sheet, `Pool<n>` and puffs replaced by the same fall. The fall is drawn from the
  place's `lip<n>` markers, and `RiverFalls.dress_place` is called from `PoiDressing.build`. The
  `Fall` node keeps its name, so the capture framing still finds it. Where a river's fall is
  drawn, the settlements' `river_draws_the_water` (`RiverFalls.near`) leaves the place no water of
  its own. The Glass Falls is dry by design; its glass now keeps the fall's ropes as ridges, so the
  sky runs down it.

**Rivers.** The ribbon carries its flow in its vertices: metres across and along, the current's
speed from the slope of its surface, how hard it bends, and its direction. The river variant of
the water shader (`WATER_RIVER`) does the following:
- flow-maps its normals, two phases crossfaded so a change of speed never smears them;
- runs rougher where it is fast and turns eddies on the inside of bends;
- streaks foam where it is fast, thickest along the banks and on the outside of bends;
- takes its depth colour from the channel the builder carved (hydro.py's parabola), clear over the
  bed at its edges;
- thins to nothing at the waterline.

The ribbon also:
- sits at the builder's surface with no lift;
- is lowered to the lower of its banks where a pad or road lies under that surface (never by more
  than most of the channel's depth);
- fades out into open water.

**Lakes and the sea.** The sheet was a plane lifted to the level map at vertices 90 m apart, so
wherever two waters at different levels were nearer than that, it drew the water between them at
a level in between: Weaver's Linn stood 13 m over itself, and a blue slab stood in the Rudd Beck's
gorge. The sheet is now laid as cells over the water only (16 m at High), each corner at its
water's level, with flat open water merged into fans eight cells wide (57 k triangles at High).
It also:
- discards where a river's ribbon or a fall's pool draws the water (a claim map, a texel and a
  half round each; open water is never claimed);
- discards where a cell between two waters would still stand above its own;
- shows gusts (cat's paws that darken and roughen the water) and slicks (smooth lanes down the
  wind);
- has a sea whose foam line surges up the shore and draws back, with surf lines shoaling in;
- takes its foam by the shore classes (`runtime.shore`, read by name): broken surf on rock, a
  swash on sand and shingle, almost none on mud or in the reeds.

The shore classes reach the water only after the next world build. The region look is kept, and
it tints the falls as well.

**The Water setting** (`graphics/water_quality`, Low to Painted, already in the Graphics tab) now
also sets the falls' particle counts (0.35, 0.65, 1.0 and 1.4 of High), the shaders' fine detail
and how far the mirror searches for the far shore (8 to 18 steps), besides the sheet's cell (32 m
down to 12 m).

### Tests

`test_river_falls` (10) and `test_water_look` (9) check that:
- every fall in rivers.json is drawn from lip to foot, with its pool;
- a place at a drawn fall draws no water of its own;
- a place with none gets the proper fall, and it follows the region and the quality setting;
- the ribbon is cut over a fall;
- no river water drawn stands above its carved bed by more than the carve's depth and the height
  map's tolerance (3,468 points, one over tolerance before the lake fade, none after);
- the sheet covers every wet texel with every corner at its water's level;
- the shore classes are read by name.

Filtered water, river_falls, poi_kinds and graphics_settings all pass. `./run.sh perf` passes
(interiors, worst 96 draws). The Merrowby budget shot is 783 draws and 1.05 M primitives, of which
water is 13 draws and 64 k. The worst of the water shots is 866 draws and 1.31 M primitives.

### After the first hand-over: strokes, white water, the wedge, a faster sheet

Four more changes, checked on the batch-3 world in before-and-after shots from the same cameras
(software Compatibility, 1600x900):
- **Strokes down the current.** A river's flow-mapped ripples are calmed away with distance, as a
  lake's are, so from a hill a river was one flat teal strip. Long bands of lighter and darker water
  now run down the current, carried on the flow map's two phases so they never smear, in the
  body colour and in what it gives back. From 45 m above a steep Skerrow beck and a Vale river the
  bands read. On the Vale river they are subtle.
- **White water holds at a distance.** The foam faded with distance whatever the current. A slow
  reach's flecks still fade, but a fast reach's white water now holds, and the steep beck's rapids
  stay white from the hill.
- **No wedge of lake water over a river's bank.** The claim that leaves a river's water to its
  ribbon reached 4 m past the channel, and a wet texel one off the line stayed the lake sheet's.
  Where a pad lies under the river's level, that texel stood over the bank as a slab of water. The
  reach is 12 m (a texel and a half) now. In the before shot of the steep beck, two blue slabs
  stand beside the river above the chain bridge; in the after shot they are gone. Open water is
  never claimed, so no lake loses its edge to a river running into it.
- **Slicks down the wind** on open water, between the cat's paws. From 70 m above the Mere's north
  shore the lake is too far off for them to show in a 1600x900 frame.
- **The sheet laid in 0.24 s instead of 0.9 s** at High (0.42 s instead of 1.4 s at Painted), on every
  world load. It reads the level map directly instead of asking the provider a quarter of a million
  times, and the sheet is the same vertex for vertex.

Verified on the branch with main (938d03d4) merged in: `test_water_look` 9/9 and
`test_river_falls` 10/10. In the full suite, 1890 tests ran and 4 failed: three in
`test_cinematic_player` and one in `test_talk_to_the_warden`, all wall-clock checks that ran at a
load of 14-26 on 4 cores. Both files pass alone (10/10 and 1/1). The suite has 0 content problems
and 0 dead lambda captures, with the warning count at the baseline, 137.

### Still short of the bar

- A tall cascade down a steep face (the 73 m one at 188,-2991) draws as a blue ribbon with streaks
  more than as white water.
- The Mere's slicks and gusts are not seen from any shot I have. It still wants a shot from a
  shore at a grazing angle.
- The Weaver's Linn was never seen whole, and the Three Sisters shot in look.json now stands inside
  the ground (the world moved under it).
- Once the batch-4 world is built, each waterfall POI has a carved step and a `fall` block
  (`facing_deg`, `top_m`, `foot_m`). The falls' lips, feet and facing need checking against it, on
  the 4096 world, since a 1024 build smears a fall into a cascade.
- No reeds are placed by the water code. The world build scatters the land agent's reed beds
  (shore class 6).

## Batch 4 on the 4096, and playtest 6: tree feet, road runs, the terraced falls

**The falls on rivers.** On the 1024 (b4), every stepped fall on a river was missing from
rivers.json: seven, counting the terraced tiers. At 8 m the 3 m step is smeared over two texels,
and the river's surface, read off the land, ramped down it under FALL_DROP_GRADE. The surface now
takes the step's own levels (hydro.step_surface, ba671089). The terraced tiers of 1.3 to 2.9 m are
forced falls between the lip and foot points each face falls between (916235a4). On w4096b,
test_falls BuiltWorld passes: every face of all six river steps is a fall at its lip. The world had
62 falls.

**Memory at 4096** (not investigated beyond this): w4096 peaked at 6.28 GB, reached in the
textures stage (3.1 GB going in, 6.3 GB out of it). The rows as arrays saved their 1.5 GB in the
scatter, which comes after the peak. At 4096 a full-resolution float field is 64 MB, so the stage
holds about fifty at once. SF.control_maps and SF.colour_map are where to look next.

**Shots on w4096b** (Compatibility, 1280x720, 26 frames; the plan from make_world_look_plan):
- Whitecut: the land steps and the Larkbourne goes over the lip as a sheet into its pool. The
  dressing in this worktree does not read `fall` yet (e689df50 is settlements'), so its blocks stand
  beside the fall. The step's face is bare terrain with the grass stretched down it; a pad keeps the
  crags off it.
- The Three Sisters: three tiers up a real hill with the stairs beside them. It reads as a hillside
  with falls, still in white blocks. The Glass Falls: a hill with the face at its front.
- Kharrow: the old dressing again, a white tower beside the step.
- Road runs in the Vale and the lake shoulder: the rails follow the ground and read as a field's
  edge. The Briarwold road had rails in a wood: the old random frontage, which 3df788e1 removes.
- A Skerrow drystone module stood out over a brow with its end in the air, and wall pieces stood
  alone in pairs on the snow (both fixed: 20b62ba0).
- A Skerrow crag near: one row of ledges lying along a ridge top reads as a wall laid on the hill.
  The crest ledges want to be boulders, or sunk into the ridge.
- The Hearthvale "rock" camera stood at a sea cliff's foot (a plan fault, fixed). Seen from the foot,
  the sea cliff's dressing is ranks of alike ledge tops: still masonry.
- The tree shots stood in foliage or shadow and show nothing of the feet. The feet were measured
  instead: of 19,524 trees in every seventh cell, 19,440 have a foot point more than 0.15 m over
  the ground (median 0.44 m, and 4.5 to 5.7 m for the giant oaks' 90th percentile).

**Tree feet** (d7fd49dc, ea503ed6). tools/world/tree_contacts.py reads each tree's foot off the forge's
mesh. worldgen.trees.seat sets every tree so that the highest foot point is 0.05 m under its own
ground, capped at 0.45 m plus 5% of the tree's height. Simulated on w4096b's heights and cells, the
median tree goes down 0.19 m and 10% are held by the cap, most of them giant oaks. **The forge's
part:** the three Briarwold giant oaks stand on a flared rim 0.35 to 1.6 m over their pivot, 4.5
to 6.5 m out, with one or two root spikes reaching the plane. Within 4 m of the axis the lowest
wood is 1 to 3 m up. That is 1.webp's tree. Seating sinks them about 1.5 m, but the roots want
regrowing to meet the ground.

**Road runs** (3df788e1, 20b62ba0). A rail, hedge or wall along a road is now one field's frontage,
from boundary to boundary, 1.2 m short of each end and at least 12 m long. Each field is railed,
lined or left open, never two of them. There is none where the road has no field beside it. Every
piece takes the ground under it, is set down at both its ends, and no run of one or two is left.

### Later on 2026-09-25: Wren's sword, two leaks between worlds, and the start as the flow sees it
* **Wren arms the Foundling.** When the first talk ends, the Naming's `wake` stage runs a new
  effect, `arm`. It gives one iron sword and puts it in the main hand if that hand is empty or
  holds a weaker weapon (by the `weapon` block's damage). A dagger is put down for it; the
  cragborn's axe hits as hard and stays in the hand.
  * Quest `notify` effects now reach the screen (before, only a conversation flushed them).
    The player sees "Wren puts a Wardens' sword in your hand. 'Issue. I'll want it back.'"
  * Wren's road line names the Last Meal Stone, west of the Choir, as where better steel is.
    The cartographer is asked to put something better than iron there.
  * The quest walker checks `arm` as it checks `give_item`.
  * test_wren_arms_the_foundling has 4 tests.
* **A death's respawn came back for the wrong body** (`3e5a9e0f`, cherry-picked to main as
  a67a2fd0).
  * The Hearth's 3 s timer outlived the world whose body died, and brought back the next
    world's player at a stale stone.
  * In the suite, that put the Warden-test's player at (0, 0, 0), 3.7 km off, in the middle of
    the conversation: the "flake".
  * A player hits it by dying, then loading or starting a new game within 3 s.
  * The Hearth now brings back only the body that died.
  * Player.teleport takes a reason (door, load, respawn, opening, arrest, moved). A move of more
    than 50 m with no reason is logged at the debug level, with its caller.
* **A world's services outlived it** (`667c4c80`, for main's batch 4).
  * Each system's `ensure()` parents its service to the current scene. Under the test runner
    that is the runner or the root, so every test world left 8 services behind, enabled.
  * A left-over QuestFoes stood the Choir's wights itself, and test_kill_places' own counted
    them as already standing and had no group.
  * GameServices now keeps what it installs inside its host. In the game nothing moves.
  * test_world_services_go_with_the_world fails on main's code, naming the 8, and passes with
    the fix.
  * Other timers that outlive a world were checked. Progression's timed modifiers, the job
    station's shifts and the enemy's parry timer are all bound to methods on nodes that go
    with them, or guarded by a shift id. The Hearth was the only one holding a stale target.
* **The start as the flow sees it** (New Game, 111 checks, captures in `captures/flow`).
  * **The first moment of control:** the Choir's colossi stand on the skyline dead ahead, and
    its mark, faint and unfound, is on the compass. The objective line says to speak to the
    Warden, and Wren is at her fire 10 m in front.
  * **A clash on that frame:** the Cinderlea region card fades out over the middle of the
    same frame, and the two fight for the eye.
  * **The talk** is a two-shot on her face.
  * **After it:** the sword notice shows, and the objective is "Walk the waystones north to
    the Sunken Choir".
  * **The walk** is 526 m on the built road: about 1 min 45 s at a jog, 3 min walking.
  * **The fight:** the three ash-wights at the Choir, the first of the game.
  * The flow stops after the talk, so the walk and the fight are not filmed yet.

## The crags as rock, the texture stage's memory, and the falls' step faces

**Crests and sea cliffs** (96e87959). The w4096b shots had a crest row of ledges reading as a wall
laid on the ridge, and a sea cliff seen from its foot as ranks of one ledge top. The crests are
seated boulders now, with smaller stones fallen below over half of those on a slope. A sea cliff's
beds still run level along it and round its stacks, but:
- each bed has its own thickness (a 0.6 to 1.5 vertical stretch, through the row's ninth field);
- each bed has its own set-back, wandering along the cliff;
- each bed has its own dip of 0.8 to 3 degrees along the cliff;
- 8% of a bed's modules are missing and 7% slumped;
- blocks lie fallen at the foot at 40% of the columns.
Not yet looked at in a build.

**The texture stage's memory** (3c780021). At 4096 the build peaked at 6.28 GB, reached in the
textures stage, which took it from 3.1 GB to 6.3 GB. The rules and the colour map now run in bands
of 256 rows, with the patches kept on their 1024 lattice and upsampled a band at a time. The maps
are the same texel for texel (0 texels differ against the committed code at 512 and at 2048). On a
synthetic 2048 world the stage's peak fell from 1,100 MB to 430 MB. w4096c (6.27 GB) was built
without it; the next 4096 measures it.

**A fall's step face** (9c446477, bb3623de, cd19cd58). The Kharrow shot's bare face was not a
texture fault: the control map there is limestone and granite (chalk at Whitecut). The step runs
across the whole pad and its skirt, and nothing dressed it past the dressing's face. The dressing
now owns the face out to the pad's flat radius (settlements' b663f632). crags.fall_faces lays the
region's ledges from there, less 0.5 m, out to where the drop is under 1.5 m, in columns from the
foot to the top.

## Trunks, fences, walls and rocks a body walks into; and the Hushline over the Stair Head's brow (graphics, 2026-09-25)

### The solid scatter

Playtest 5 walked through trees, fences and rocks: nothing the streamer scatters had a collider.
`world/scatter_solids.gd` now stands the near ring's solid scatter on the physics server. There
are no nodes: each 32 m block of a near-ring cell with anything solid in it is one static body.
Each shape comes from the forge's meta:

* a tree or a stump is a cylinder of its trunk radius, up to 4.5 m, so the crown is walked under;
* a wall, a hedge, a fence module or a bale is the box of its bounds;
* a rock is the hull of its coarsest mesh that still has a shape, or of its `*_col.glb`;
* the wayside's rail runs, fingerposts and gates add their own boxes and posts. A gate stands its
  shutting post and its leaf: a shut gate closes its gap, and an open one is swung back out of it.

The wayside hands a cell's drystone runs and hedges back as scatter rows, stretched to meet, so
they are stood as the boxes of their fitted rows. The batch-4 roads plant the same hedge and wall
pieces and the same trees. A test holds every tree the forge makes to a trunk, and every wall,
hedge, fence, hurdle and bale to a box. The settlements' and the POIs' own walls and fences
already had bodies.

Grass, flowers, bushes, scree and driftwood, and anything under 0.45 m as it stands, stay
passable. The layer is 13, "scatter". The player, the foes and the people have it in their
masks. The camera's arm, sight, arrows, footsteps and the quests' ground rays do not see it (every
ray and shape query in the game was checked; the only one that sees it is the impact stains'
ground ray, which is harmless). A villager or a foe that has walked into it and got nowhere for a
second walks through it for a moment and a half. The player's mantle climbs it. A POI's rocks
collide unless the builder says otherwise.

**From the keys** (`tests/unit/test_walking_into_the_scatter.gd`): on a flat Terrain3D with its
own collision, the cell is stood as the streamer stands one, and W is held at walk, jog and
sprint. The distances below are from the body's middle; the capsule's radius is 0.35 m.

| Walked into | Stops at | Check |
|---|---|---|
| an oak, square on and 0.3 m off centre | 0.77 m from its middle | trunk radius 0.417 m + capsule 0.35 m |
| a roadside rail run | 0.45 m from its line | |
| a drystone wall | 0.62 m from its line | |
| a hedge | 0.80 m from its line | |
| a boulder | 2.00 m from its middle | the drawn full mesh stops a body at 1.98 m: 0.02 m off the drawn face (the test holds it to 0.1 m) |

The boulder's 2.0 m is the rock's own size (3.5 m across), not a fat hull. Jog and sprint cross a
bed of long grass at pace. A jump at the fence climbs it and a jump at the oak does not. The
camera behind a trunk keeps its arm.

**Seen**: `tools/capture/plans/scatter_stops.json` (the capture runner now takes a list of gaits,
and a run can be filmed from behind). It walks the body into an oak, a fence and a boulder near
Merrowby on the built world, from the side and over the shoulder. The body stands a hand's width
off the bark, against the rails, and at the boulder's foot with its shins at the rock. There is no
gap to see and nothing inside the stone or the bark.

**What it costs** (the solids probe, `tools_gd/solids_probe.tscn`, on a quiet machine with a
one-minute load of 2.5 to 4.7):

| place | shapes / bodies | worst tick | 99th percentile | stood in, all ticks |
|---|---|---|---|---|
| densest wood (3200, 2688) | 8940 / 571 | 3.8 ms | 2.1 ms | 142 ms |
| Merrowby's street (900, 2350), three runs | 6498 / 554 | 2.4, 1.6, 3.0 ms | 2.4, 1.6, 3.0 ms | 117, 60, 62 ms |
| the Stair Head | 930 / 299 | 2.1 ms | 2.1 ms | 39 ms |

The first layout's worst tick at Merrowby was **2.4 s** (50 ms in the wood), for four reasons:

* 24 shapes were stood between looks at the clock;
* an asset seen for the first time was made mid-tick (its meta read and a rock's hull made, up to
  15 ms);
* one body a cell joined the space from its first shape;
* the ring was re-sorted with a GDScript comparison (11 to 16 ms at Merrowby).

Now the clock is read after every shape, and a new asset is made only at the start of a tick that
has joined nothing. Each block joins the space at the start of the tick after it is whole:
166 / 123 / 45 ms of ticks in all against 221 / 147 / 84 ms joining shape by shape (the probe's
`--join-each`). The ring is sorted on packed integer keys (0.2 to 0.6 ms). What is left over the
budget is a new asset (up to 2.3 ms, once a session each) or a tick of shapes and a join together
(3.0 ms at worst). A walking body's `move_and_slide` costs about the same with the scatter in its
mask and without it.

On the machine at a load of 18 to 30 (eleven heavy runs on 4 cores), the same probe's worst ticks
were 20 to 32 ms. The median cost of a shape was 15 µs in one run and 109 µs in the next. A wall
clock there measures the other processes, so the probe logs each tick's work beside its time.

### The Hushline, the beacons and the skyline plan

These are eight commits from the last session, verified again here only through the suite, the
journey and the flow.

* **The curtain stands out over the Hush.** From the Stair Head the knoll's own shoulder, 36 m
  ahead, hides everything over the Hush below about 100 m; from the Choir's Crown the brow hides
  everything below 115 to 120 m. The old bank was 150 m tall and had thinned out by then. The
  curtain now stands at z 4000, 130 m off the Landing. It rises from the water to 260 m, is thick
  to 170 m, and runs the south coast from x -3600 to 4080, thinning at either end. It is cut into
  512 m lengths that are culled and sorted on their own, and it fades out at the view distance. It
  thins by the eye's distance across the ground, not by the distance to each point, so a stretch
  thins from foot to top together.
* **Its light.** It takes the horizon sky's light drained of colour, and at night the larger of
  that and an eighth of the moon's. Before this an unshaded sheet stood white all night, and then
  black against the sky.
* A test measures the brow from the Stair Head and from the middle of the Choir's Crown against
  the runtime heights.
* **A beacon on the skyline** (the horizon layer's lights) glows at 24, not 14. At 14 the
  Grandfather's knots were one dim pixel from the Choir's Crown, 4.1 km off.
* **The skyline plan** stands the Choir's two shots in the middle of the Crown (-156, 3386), not
  inside a colossus's hollow body. The Stair Head gains its view south over the Hush.
* **A headless world builds no skyline**: the unit suite builds dozens of worlds, and the stand-ins
  and bands were most of a second each.

### Checked

On the branch with main merged, on the batch-4 worlds installed uncommitted:

* w4096c:
  * `--filter=scatter`: 28 of 28, with the same stop distances as on the flat test ground;
  * `./run.sh journey`: 16 of 16;
  * `./run.sh flow`: New Game 111 of 111, load 33 of 33, Continue 36 of 36, with no
    errors logged.
* w4096b, `./run.sh test`: 1912 tests, 1 failed, 0 script errors. The failure is
  test_talk_to_the_warden (she faces away at 2.5 m), and main's own run on that world fails it
  with the same numbers.
* A flow run on w4096b failed "a new game plays the opening after the Naming". The cause was the
  shared `user://settings.cfg`, which another run had left with `play_opening=false`; it was set
  back to the shipped default.

### Not done
* The Hushline curtain has not been looked at again over the Stair Head's crest since these
  commits; nor have the night lights from open views.
* Still queued for this area: the Thornmarch reshoot, the Low and Medium street shots, the 4 poor
  LOD1s, attributing High `--no-lod`'s 1.71 M primitives, and Merrowby's budget on the batch-3
  world.

### The Naming's first fight in view, and the services' teardown without engine errors (2026-09-25)
* **The first fight** (`dcdc3d3c`).
  * Shot from the end of the waystones, one ash-wight stood at the first colossus's plinth and two
    stood behind it: the Choir's position is its primary colossus, and the fight was ringed round it.
  * A kill objective may now say where its foes stand (`stand_at`, a place spec). The Naming's is
    42 m out towards the way in.
  * The walk to the Choir is now done at 120 m, so the three are stood about 80 m ahead in the
    avenue. From 70 m they stand in the open before the primary colossus, with the lamp and the
    last stones leading to them.
  * Checks at that head: suite 1937/0, walker 77/77 (228/228 walks), journey 16/16.
* **e60658a8's teardown** (`1818d4ea`, measured, reworded here rather than amended).
  * It called `remove_child` while the root was busy removing the world: 25 engine errors in a
    full suite (the census's `errors 25`).
  * It now only frees the node. Suite 1937/0, census `errors 0`, 0 "Parent node is busy".
    test_world_services_go_with_the_world passes.
## The painted look: stone that belongs to its slope, mist on each region's own ground, and a start that is not murk

All frames below are Compatibility (llvmpipe), 1600x900, on the batch-4 world before it was
committed (w4096c) unless said, from this worktree's `scratchpad/painted-look/`, which does not
survive the session. The plans that make them are committed.

### Rocks (playtest 5 "rocks jut from slopes", playtest 6 "cliffside rocks flat and out of place")

The world builder seats, tilts and clusters the rock; this pass is how a rock looks.
`world/rock_paint.gd` swaps the forge's StandardMaterial3D for `assets/shaders/painted_rock.gdshader`
on every rock the game loads (the scatter's multimeshes, with or without their LOD ladder, and a
POI's placed copies), keeping the forge's albedo, normal and occlusion; no re-import.

* **Value.** The forge painted Hearthvale's and Skerrow's ledges and slabs at 0.33-0.44 linear, four
  to eight times the grass they stand in (the "white paper" of playtest 6), and Cinderlea's fused
  stone and basalt at 0.016-0.02 (holes in the frame at the start). `tools/world/rock_values.py`
  measures each rock's mean over the texels its faces use (the atlas padding is a third of a
  boulder's picture) into `world/rock_values.json`; every stone is drawn between 0.028 and 0.24
  (bone 0.3). A lifted stone's picture is pulled toward its own mean so the fused stone's flow
  bands stay faint.
* **Light.** Two tones with a soft step (a custom `light()`), a shadow plane of 0.27. The forge's
  normal map does not reach that light: its strata, stepped by it, drew zebra stripes on every
  boulder; its relief is painted into the colour instead. All the stone's patterns are drawn in
  metres off its own pivot: in world metres 3.5 km out the hashes fell into stripes.
* **Belonging.** The region's stone hue; the forge's occlusion painted into the recesses; dark
  undersides; the region's soil over the last half metre above the ground line (the runtime height
  map, corrected at each scattered rock by the exact height there, carried in its tint's alpha,
  so it holds for any sink, lean or a sea-cliff bed's fitted [sx, sy, sz]); the region's turf grown
  onto up-facing ledges near the ground on the green slopes; moss and lichen on the weather side.
* Measured: a Hearthvale crag band read sRGB (97, 87, 80) unpainted, (42, 36, 34) in the first cut,
  and shows its blocks' lit tops and stepped faces after the shadow lift (`r2_ledges.png`).
* `tests/unit/test_rock_paint.gd` (9): placed and scattered rocks painted with their own textures,
  wood left alone, the ground correction through an 8-bit tint alpha, a bare row padded, a
  9-field ledge row kept, the dark stone at its floor, no stone near white, every rock measured.
* `WM_ROCK_PAINT=0` and `WM_GROUND_MIST=0` turn each off for a before on the same build;
  `asset_review --painted` draws rocks painted.

### Each region's mist and lamps

`world/ground_mist.gd` and `assets/shaders/ground_mist.gdshader`: a screen quad marches each
pixel's line of sight over the runtime region, height and water maps, so a region's mist lies on
its own country (in the hollows and on the water, thinning with height over the ground) whichever
region the camera is in. Keys `mist_*` per region; off indoors and with Distance haze off.
`NightLights` gives the country's windows, doors, lanterns, braziers and fires their region's
`lamp_tint` and `lamp_energy`. Both are on and have been in every frame since; neither has been
judged on its own at dawn or at night yet.

### The start (playtest 6: "a gloomy brown-grey haze")

Cinderlea's far fog is a pale ash-lavender instead of brown, thinner, with more of the sky in the
distance; the low haze under half as thick and held 30 m under the eye; and, from two trials laid
over the pack per shot (the capture runner's new per-shot `"light"`), a warmer, stronger low-sun
fill (low_sun_fill 5, ambient 1.5, `#b4a8b0`, exposure 1.15). Hearthvale's grade 1.16 -> 1.06
saturation and a less yellow sun. The camp's ash is greyer (0.40), soft-edged and stretched 2.6
times down the westerly, so it lies in drifts and no longer reads as mould or snow
(`ash_pair.png`). A grey day at noon at the Stair Head (still_grey, ashfall) now reads as warm
earth under a cream sky: ground sRGB (68, 47, 30). A region `overcast_color` key was tried and
dropped: the sky under cloud changed by under one sRGB unit.

`tools/capture/plans/first_ten.json` is the first ten minutes' cameras (the Stair Head, the Choir,
the Wardens' Rest, Merrowby); `ft_pairA/B/C.png` before and after. Honestly: the pairs differ
less than they should; the ash plateau is still one smooth brown at every scale. Its ground rules
(ash in hollows and on lee faces, pale stone on windward noses, deep burn patches) went to the
world builder as a spec, to fold in with its steep-ground rules; landform break-up on the Hush's
mounds is the world builder's too.

Landed in main at 5760b9fb: suite 1935 tests 0 failed (the warning census back at 137 after a
ternary in seat_rows), journey 16/16, flow PASS new 112 / load 34 / continue 37, 0 errors.

### Found for others

The blue slab on a Hearthvale slope is a hedge segment drawn without its leaves (graphics).
Hearthvale's mustard fields are the terrain colour map (chroma x2, a floor of 0.40, the gold
second voice at up to 55%); the world builder's tint1024 preview carries 1.3 / 0.72 / a*0.3.
1024 builds drew no ground in the game while Terrain3D's spacing was pinned to 2 m (fixed in
a998cd3e). Rock rows at y ~0.2 under 111 m ground in one Hearthvale cell (world builder).

### The Cracked Toll (not landed)

`tools/forge/gen_landmarks.py`: a bell's profile (a concave waist to a flared lip, a flatter
crown over a turned shoulder), the crack carried round the waist with branches down three flanks,
mould bands, a low turf heave at the lip, and the mound cut to a shoulder of earth and turf
against its back (no chalk: up close the old one was "a green dome with jagged white patches").
`lib/scene._AUTO_SMOOTH` asks the RNA: under this container's Blender 4.0.2 `hasattr` on the
class was False and every landmark died. Rendered in Blender from four bearings at 150 and 600 m
it reads as a bell from all four (`toll_sheet.png`); in the game, only an earlier cut has been
seen (a green dome with a small bell: the mound). Its assets are not in main yet.

### Not done

The drop test was not re-measured this session (0.79 on the old world); the full default sheet
on the batch-4 world is the way to do it, and did not fit the machine's queue. No Forward+ frame
was taken. The grass tint on tint1024 is not shot yet.


## The ground probe: every place stood at, every road walked on the keys, and an instrument that cannot report an empty county

Debug and errors, batch 4. Two tools that tell every other area whether the world is sound where a
body stands in it, and the capture guard that never reached main, written again.

**A capture that photographs nothing fails (the port of 125a8c4c).** On 2026-09-22 three street
shots came back at a third of their real cost because the scatter had not loaded, and every signal
said the run was healthy. The fix was on a branch that never landed, and the capture runner has
moved on since, so it is written again against today's runner: a shot with cells loaded and not
one scatter instance is `"unstreamed"` in perf.json, left out of the worst frame and the verdict,
named on the sheet (`shots_measured`, `shots_unstreamed`), and fails the run. The wait asks for
instances as well as a built ring. `test_capture_runner.gd` holds it over sample dictionaries.

**The teleport tour (`./run.sh tour`, `tools_gd/ground_probe.gd`).** Boot attaches the probe on
`--tour=<dir>` and starts a new game without the opening. The probe reads every place and point
of interest from `game/world/generated/pois.json` (323 on the batch-3 world: 60 places and 263
POIs), gives each one index in one order over the whole map (nearest hop first from the
north-west corner), and at each:
- puts the body a metre over the ground there, the way the console's `tp` does;
- waits for the streamer's full ring, and lands the body in 45 physics ticks (the eight-a-frame
  cap is lifted for the landing, since a software frame here is seconds long);
- records the engine errors, script errors and warnings said since the jump (ErrorLog's reports,
  diffed), the frame (wall ms, render CPU ms, draw calls, primitives, objects), and what the body
  stands on (the ground, or the named thing under it);
- flags it when it is under the ground, fell through while landing, is in water or deep water,
  inside something solid (the quest walker's capsule test, the ground's own collision left out),
  or in the air;
- takes a picture of what the player sees.
One JSON row a place, written as it goes.

It is made to be taken in pieces between other people's heavy runs: `--region=`, `--only=`,
`--minutes=`, `--limit=`; the next run skips every place already in tour.jsonl and appends.
`tools/debug/ground_report.py` writes report.md: the totals, the worst thirty places, a table by
region, every line the engine said, and the contact sheets (the worst, with what is wrong under
each; every place, a red frame round each fault). With `--against <an earlier tour>` it adds what
each place gained or lost since: broken, fixed, wrong another way, still wrong.

**The tour's guard.** A stop is `unstreamed` when its ring is still coming in at the limit, when it
is built with not one thing in any cell, or when there is no Terrain3D region under the body (the
1024-at-4096 fault: cells full of trees standing over fog). It is left out of the costs, named at
the top of the report, and fails the run.

**The road walk (`./run.sh roads`).** Headless at a fixed 60 ticks, so a walk costs what the
machine needs rather than real time. The body is put at each road's start in roads.json (136) and
walked to its end on the keys: W and Shift held down as key events, the view turned to the road six
metres ahead as a mouse turns it. No way made in a second of the game's time is a snag, and the
probe records what is at the knee and at the chest, the rise ahead, the water and whether the body
is inside something. Then it tries what a player tries: a jump, then a step to either side. Six
seconds without way is a trap: recorded, and the body is put down fifteen metres on. Wading deeper
than half a metre is noted with its deepest point. It is built for graphics' streamed physics ring:
the traps it finds are the places a solid tree or fence shuts a road.

**What it has found so far.**
- *The foes (playtest 6, "no enemies other than the starter area's").* `./run.sh foes` on the batch-4
  world (w4096b), headless: at 30 points over the six regions the near ring stood 158 foes. That is
  112 of 112 cell spawns within 400 m and 46 of 46 open POI encounter foes, with no point short.
  A jump 2 km away and back stood the same 5. A kilometre of road in each region met 0-5 foes within
  60 m and 2-14 within 200 m. So none are missing; the roads are simply quiet (the cartographer's
  road encounters answer it). Ten poachers dropped a weapon on 2 kills against the table's 28.2% of
  2000 rolls, and ten bravos on 2 against 20.6%.
- *Bell Street shut the Greyfold road.* The Cinderlea kilometre made 161 m in 460 s of game time.
  Walked whole, greyfold_builders_harbour held the body at Poi_bell_street/Masonry at (-2056, 2978):
  245 snags, 734 of 2556 m in 1082 s. A ruined hall is laid along the road's grain on the place's
  middle, so the road ran in at one gable and out at the other. The hall now stands to the side the
  place is on, 4 m off the road's middle, but only where a road passes through (`_off_the_road`,
  test_ruins_off_the_road). The road walk's trap counter had counted movement, so the step aside it
  tries reset it and that body was never called trapped. It counts way made along the road now.
  `./run.sh roads --only=regressions` walks this road and fails if the body is trapped or does not
  reach the end.
- *The first tour pieces* (batch 3's tracked world, 640x360, llvmpipe): six places, all sound, with
  0 errors, 822-1098 draws and the ring in within 3-12 s.

**Warnings: 137 down to 49 in the game's scripts.** Two of the analyzer's warnings were bugs.
HUD._on_boss_defeated and MusicDirector._on_boss_defeated cleared a parameter that shadowed the
member they meant to clear, so once a boss fell the HUD took the next foe struck for the boss. The
rest were fixed without changing behaviour:
- scoped renames of whatever hid a property, method or member;
- `@warning_ignore` on intended integer divisions, on values that may be a number or text, on
  static calls through an autoload, and on GameState.seed and CinematicPath.ease, whose names saves
  and plans use;
- EconomyService.trade_requested marked as an API.

The event bus keeps its ignore region. All 72 of its signals are emitted somewhere; ten are heard by
nothing yet. The 49 left are in files other areas are editing now: humanoid_model 15, enemy 14,
player 7, character_appearance 4, night_lights 3, world_streamer 3, world 2, animation_driver 1.

**A user:// for each checkout.** Every worktree is the project "Wickmere", and Godot keeps user://
by project name, so they all shared one settings.cfg, one set of saves and one log folder. A write
of play_opening=false at 02:24 failed every branch's flow at the opening. tools/godot_env.sh now
points XDG_DATA_HOME at <repo>/.godot_user (checked: OS.get_user_data_dir() follows it). run.sh and
the scripts that launch Godot themselves use it for everything except play. Each run starts with
no settings.cfg; the flow removes it before each of its three ways in and checks "the settings come
in as shipped". The test runner puts off-default settings right before the first test.

**Logs that keep what they were told.** `| tee /dev/stderr` reopened a redirected stderr and
truncated it, so `./run.sh flow > f 2>&1` kept only the Continue. run.sh's show_and_keep writes
through the inherited stderr instead. tools/debug/test_run_logs.sh proves it with a stand-in Godot:
it fails on the old run.sh and passes on this one, and `./run.sh test` runs it.

**test_audio_guard under load.** It now waits for a fresh mix for ten frames' time, and at least
2 s, instead of sampling once 0.2 s after the barrier. A barrier that held the lock still fails it.

**Checks** (on 3b7e48d4, the tracked world):
- `./run.sh test`: 1899 tests, 0 failed, 0 script errors, 0 dead lambda captures, census PASS at 49.
- `./run.sh flow`: PASS on ec4f0f95, all three ways in, the first check "the settings come in as
  shipped".

- `./run.sh journey`: 16 of 16 on ec4f0f95.
- The regression walk on w4096c with the hall moved: greyfold_builders_harbour walked 2552 of 2556 m
  in 375 s of game time, reaching its end (it made 734 m before). The walk still fails, on one trap
  of 6 s at (-3122, 3080): a barrel of Sulion's dressing (Poi_sulion/briarwold_barrel_a) with
  collision, standing on the road at knee height. That is settlements' dressing, and the regression
  walk will pass once no solid prop stands on the road there.

**Not done.**
- The whole tour: its batch-3 baseline and its batch-4 run, a region at a time.
- The full road walk, and a look at where graphics' solid trees trap a body.


## The water after batch 4: the water where you stand, shores at their waterline, the sea to the horizon

Water agent, on wip/water-2 with main 037a886d (batch 4) merged. Shot on the batch-4 world
(software Compatibility, 1600x900), before and after from the same cameras.

**`WaterSurface.at(x, z)`** (27e68a9e) is the query swimming stands on. It returns `has`, `y`,
`depth`, `flow` and `kind` for rivers (the ribbon as drawn, at its sloping surface, cut over falls),
falls' pools, lakes and the sea. `WaterSurface.under(point)` says how far a point is below the
surface, and `UnderwaterView` washes the frame toward the region's deep water while the camera is
under. `test_water_surface_query`: 5 tests, 0 failed. It checks a river mid-channel (at its surface,
running downstream, dry 30 m aside), the Mere and the sea at their levels and still, the start dry,
a pool at its level with a camera 0.5 m under, and the cost of a query (under 200 µs; the test
enforces it). Player-feel's swimmer calls it (cherry-picked as 81891ede on wip/player-feel).

**Shores (playtest 6, "water doesn't eclipse shores right").** The lake in the user's shot is Lark
Pool (level 46, shingle and mud shore). The sheet was cut where the 8 m water mask crossed 0.5 and
faded by the 8 m height map. On the batch-4 world, 17.9% of the shore band just outside the 1024
mask has 2 m ground below the water's level (35,787 texels more than 1 m below), so the sheet ended
as a raised edge over a lower beach. Now:
- the sheet runs a texel past the mask and fades out over it, filtered by hand, so there are no
  8 m steps;
- near the camera, in the shallows only, it thins to nothing at the true waterline, measured from
  the frame's depth buffer;
- it leaves water that is not level (a river running out of a lake) to the ribbon. At Lark Pool,
  that had laid a tilted pane of lake water over the beach beside the Larkbourne;
- a river's mouth below the sea's or a lake's level counts as open water;
- the height map is filtered by hand, so the Mere's shallows foam is no longer cut into 8 m
  squares (the staircase right of the Long Stride).
The Lark Pool shot shows the lake meeting its shingle at a soft line, with no slab or pane.

**The sea's edge.** The grey plane in the world builder's Skerrow frame was the sky's underside.
Past the world's edge the water mask clamps to its last row, and where that row is land (the Skerrow
wall) the sea skirt was discarded in a band out to the horizon. The skirt now starts at the world's
edge, and outside the world the shader draws open sea that deepens away from the land, with no foam.
The Skerrow north-edge shot now shows sea to the horizon.

**Tall cascades** whiten with their height (a slide takes 0.22 of the break instead of 0.55 on a
45 m face). On the 73 m cascade it is a small change.

**Checks** on 9b4ab073: full suite 1925 tests, 0 failed, 0 content problems, 0 dead lambda
captures, warnings 137 (the baseline). Journey 16/16. Flow PASS on New Game 112/112, Load 34/34 and
Continue 37/37.

### Still short of the bar
- Looking out to sea from the Sedgemire and western Skerrow coasts, a faint straight line still
  shows where the world's water meets the skirt: shallow sheet one side, deep skirt the other.
  The skirt's depth should continue the edge's own depth rather than start from it.
- The Larkbourne's ribbon sits 1.4-1.6 m below its banks on the 2 m ground, in a trench, where the
  2 m build carves the channel deeper than the ribbon's surface. That is the builder's channel
  against the water's surface, to settle with the world builder.
- Kharrow Force on the batch-4 world: the front shot framed the fall well (a sheet at the face, the
  ribbon meeting its pool). The side camera stood inside a ledge block.
- Wildlife (birds and fish rising) is written in the scratchpad and not yet in the game.

### The Naming's first fight in view, and the services' teardown without engine errors (2026-09-25)
* **The first fight** (`dcdc3d3c`).
  * Shot from the end of the waystones, one ash-wight stood at the first colossus's plinth and two
    stood behind it: the Choir's position is its primary colossus, and the fight was ringed round it.
  * A kill objective may now say where its foes stand (`stand_at`, a place spec). The Naming's is
    42 m out towards the way in.
  * The walk to the Choir is now done at 120 m, so the three are stood about 80 m ahead in the
    avenue. From 70 m they stand in the open before the primary colossus, with the lamp and the
    last stones leading to them.
  * Checks at that head: suite 1937/0, walker 77/77 (228/228 walks), journey 16/16.
* **e60658a8's teardown** (`1818d4ea`, measured, reworded here rather than amended).
  * It called `remove_child` while the root was busy removing the world: 25 engine errors in a
    full suite (the census's `errors 25`).
  * It now only frees the node. Suite 1937/0, census `errors 0`, 0 "Parent node is busy".
    test_world_services_go_with_the_world passes.


## The attack clips audited: blows that carry through, and heavy weapons that gather rather than drift

The user's playtest said "attacking animations still need revising". This round filmed every
player swing, light and heavy, for each clip set, in the motion studio: Forward+, real key
presses, a fixed 60 fps. It looked at the films frame by frame and measured the clips at 120 Hz in
the forge's own sampling. The before films are in `scratchpad/player-feel/film_before`, the after
films in `film_after`. Two faults were under nearly everything.

**Every blow popped and then stood still.** The forge eased each key of a swing on its own. A strike
key used `snap` (1-(1-x)^5): it leaves at five times its mean speed and arrives at rest. The
follow-through key after it used `out`, leaving at three times. So a blade left its cocked pose at
full speed with no build-up and stopped dead at the next key, which lies inside the hit window.
Then it set off again. At 120 Hz the grip's speed jumped by 19-34 m/s in one sample (the tip reached
109 m/s), and the slowest moment of every clip's hit window was 0.00 of its peak. On film, the
sword's first cut went from overhead to horizontal in one frame. Then the blade hung level in front
of the chest for three frames, the whole of its live window. The greatsword's chop hung there for
six.

Now a swing's keys *flow* (`Track.flow`, `anim.flow_slopes` / `flow_at`): a monotone cubic
through the keys, with the speed continuous through every key. The motion stops only where it
turns back or holds (the cocked blade, the end of the follow-through). The first key leaves at its
segment's mean rate, so a press still moves the body at once. A flowing strike needs a little
longer to reach the blow from rest. So the strike keys (the cocked key, the end of the hold and the
blow) moved earlier by 14-111 ms each, and each clip's `hit_start` is unchanged to the millisecond.
`hit_end` moved by 1-15 ms, except the two-handed sweep's (0.582 s to 0.549 s). The grip now
changes speed by at most 3.8 m/s in a 120th in the first cut, the heavies, the two-handed chop and
the dagger's slash. The backhand, the rising cut and the sweep keep a one-sample twitch of 11-16.5
m/s where their grip is out of the arm's reach and the straight arm's roll is loose. The tip
peaks at 25-40 m/s (it was 75-109), and the slowest moment of a cut's hit window is 0.09-0.33 of
its peak. The stab, the punches, the riposte and the backstab have their windows set by hand. Their
points were fully out 30-80 ms before the window opened, then held there. Flowing, the point is 90%
of the way out within 35 ms of `hit_start`. The riposte's and the backstab's drives were shortened
(0.17 s to 0.13 and 0.16 to 0.12), and they peak at 9 m/s.

Two things in the arm's solve went with this. Where a flowing swing carried the hand over the
shoulder, the arm's pole switched from "down and back" to "out" in one sample, and the elbow
jumped 30 cm (40 m/s). The pole now turns over as the hand rises from 10 cm below the shoulder to
40 cm above it, and the arm bones keep the low pole's roll (`sign_pole`). The elbow's fastest now
ranges from 6 to 25 m/s, apart from the rising cut's 45 m/s, where the grip passes 30 cm from the
shoulder and the folded arm swings about it. The backhand's and the sweep's follow-throughs laid
the blade along the forearm, where the wrist's solve has no twist to hold to, and the hand spun
116 degrees in a 120th. They are laid back further now (lead 40 and 30), and no hand turns more
than 48 degrees in a 120th.

**A slow weapon swung in slow motion.** A weapon's `speed` scales its swing's timeline (DECISIONS
2026-09-22), and the rig was stretched evenly to fit it. A greatsword (0.7), a hammer (0.6) and a
mace (0.85) played the whole clip slowly, the blow too. On film the greatsword's heavy leaned back
with its blade overhead for over a second and came down in three frames at a twentieth. The
timeline is kept. Only the picture changes (`AnimationDriver.weighty_plan`): the clip is drawn back
at the weapon's pace (never slower than half the clip's), held a moment at the cocked blade,
creeping, and struck at the clip's own pace. It reaches its blow on the timeline's frame. A
greatsword's chop now holds its cocked blade for 0.11 s and strikes in 0.23 s. A foe whose attack
the timeline plays slower than its clip, but not slow enough for its held telegraph
(`windup_plan`), gets the same.

**A charged heavy waited halfway through its strike.** Holding the heavy key held the timeline
0.05 s short of the blow. With a strike that had popped, that was inside the cocked hold. With one
that flows, it was halfway down the strike. The forge now marks `strike`, the key the strike
leaves from, and a charge is held where the picture reaches it
(`AnimationDriver.timeline_at_rig_event`). A charged heavy now lands 0.12 s after the release with a
sword and 0.15 s with a greatsword, where it was 0.05 s.

**Filmed** in the motion studio, before and after, from real key presses at a fixed 60 fps. The
plans are `scratchpad/player-feel/audit.json`, `audit2.json` and `final.json`. They cover the
sword's chain, heavy and charged heavy; the greatsword's chain (from the side and the front) and
heavy; the spear's chain from the side and the front; the hammer's heavy; the dagger's chain; the
foes' cold sweeps (`foe_swings.json`); and the backstab (from `impacts.json`).
- *The sword's first cut:* before, the blade went from overhead to level in one frame (1/30 s) and
  stood level for three. After, it is overhead, forward, level, down-forward and down on five
  successive frames, and it keeps moving through the window.
- *The charged heavy:* the blade is held back over the shoulder while charging. Let go, it goes up
  over the head, level and down in 0.25 s.
- *The greatsword's chop:* it holds the cocked blade for about a quarter of a second (it had drifted
  overhead for half a second), strikes over six frames, and carries down through the window. Its
  heavy still leans back for over a second. That is the clip's own drawn-out wind-up at 0.7 of its
  pace (`hit_start` is 1.76 s after the press, the timeline's), not a hold.
- *The spear's chain:* seen from the front, the butt passes in front of the chest in the hand-over
  from the chop to the sweep and in the sweep's wind-up. It never goes into the body.
- *The foes' cold sweeps* (the raider's step-through, the hart knight's antler toss, the
  bell-bearer's crushing step, all on the two-handed sweep): each sets its weapon level in the
  first frame of the hand-over from the guard (0.07 s), winds to the right, holds its telegraph
  there, and sweeps through in one to two frames at 15 a second. There is no flick to the left
  before the wind-up.
- *The backstab:* raised over the shoulder, driven forward and down, and the point goes into the
  small of the foe's back from the fourth frame of the drive.

**Tests.** The forge gains `test_a_blow_carries_through_its_window` and
`test_a_thrust_arrives_with_its_window` (`tools/forge/tests/test_rig_contract.py`: 31 pass). The
game gains `test_attack_motion.test_a_slow_weapon_holds_its_cocked_blade_and_strikes_at_the_clips_pace`,
which drives the driver frame by frame for a greatsword, a bell hammer and a sword. It finds the
rig's blow within a frame of the timeline's, the cocked blade held for 7 and 14 frames, and none
held for the sword. The attack audit (`test_attack_motion`, `test_enemy_attack_motion`,
`test_attack_windows`) passes on the new bake: no blade, butt or hand in the torso past 0.3 cm,
wrists at most 87 degrees, edges leading 0.87-0.91. The first flowing bake failed it three ways,
and all three were fixed before this bake:
- a spear's butt went 3.2 cm into the chest while the heavy set off from rest;
- two wrists bent 102-104 degrees under a twist-steadying that was then dropped;
- the sweep's edge led 0.79 of the cut, and leads 0.91 with its strike laid back 20 degrees.

`./run.sh fights`: 66 fights, 0 checks failed, PASS. Full suite: 1891 tests, 1 failed, 0 content
problems, 0 script errors, 0 dead lambda captures, 4 logged errors. The failure was
`test_talk_to_the_warden`: at 2.5 m the Warden faced away. Run alone it passed. It has nothing to
do with the attack clips, and the load average was over 20 at the time. `./run.sh journey`: 16 of 16, 0 logged errors. `./run.sh flow`: PASS for New Game, Load and
Continue, every check ok, 0 errors logged.

### Found, and not fixed
* *(Done 2026-09-26: "Three swings brought up to the bar".)* **The rising cut's elbow** still swings 45 m/s for a sample, where the grip passes 30 cm from
  the shoulder: the arc's centre wants moving out, not the solve.
* **The backhand's, the rising cut's and the sweep's grip twitch** 11-16.5 m/s in one 120th, where
  the grip is out of the arm's reach and the straight arm's roll is loose.
* *(Done 2026-09-26: "Three swings brought up to the bar".)* **The two-handed heavy's wind-up is long by design.** At 0.7 of its pace it leans back for over a
  second before the blow. The telegraph is the point of it, but a player may want a shorter
  gather on the greatsword and a longer hold.
* *(Done 2026-09-26: "Three swings brought up to the bar".)* **The light's draw-back is nearly as quick as its strike** (the tip's peak 30 against 40 m/s in
  the sword's first cut). A cut reads more clearly when the strike is two or three times the
  draw. A shallower cocked angle for the lights would give that.

### What a pair of hands should check
On a real GPU, at speed: whether the strike now reads as a blow that carries, and whether the
greatsword's held cocked blade reads as weight rather than a pause. Check whether the charged
heavy's 0.12-0.15 s from release to blow feels late, having been 0.05 s.

## Characters, batch 4: running legs through the clothes, measured and fixed at the source

Playtest 5 (the user, on batch 3): "running legs clip the clothes".

### Measuring it: clipcheck

`tools/forge/preview/clipcheck.py` poses the body and a part GLB with the rig GLB's own animations
(the clips the game plays, not the forge's Python ones) and counts the body vertices that were
under the cloth and are drawn outside it in a pose. A vertex counts when its nearest garment point
is inside the sheet (not on a hem, cuff or neckline), it stands more than 2 mm outside, and it can
be seen from the front, the back or a side (a depth buffer splatted from the meshes). It can
wear trousers under a tunic (`--under`), count only the legs (`--bones`), skin a part again as
the forge would with a candidate weight rule (`--reweight`, `--reweight-cloak`), pose the arms as
the game's ArmRoom does (`--hold`, `--arm-out`), and draw the worst sample with the body red
where it came through (`--png`).

### What it found

- **A floor under every skirt.** The tunic's skirt, the skirt, dress, robe, wrap skirt, kilt and
  coat are each a solid loft cut by a plane at the hem, and a solid is meshed closed: each had a
  flat floor across its bottom, about 0.05 m² inside the legs, with the legs standing through it.
  At rest it could not be seen. In a stride it swung up with the thighs and the legs cut through
  it, and in the long skirts it stood out from a raised knee as a board. `Garment.open_below`
  drops it after meshing; the built parts now have 0.0001–0.0007 m² facing down at the hem.
- **The kilt did not go with the thighs.** It kept 55 % of their swing at the hip and 90 % at
  the hem and gave the rest to the hips, so a running thigh came out through its front and the
  trailing one through its back. The skirts now go with the thighs whole, parted between them
  over 5 cm.
- **The long ones hang from the knee.** Hung from the thighs alone, the robe, the wrap skirt and
  the coat swung up over a raised knee, and the trailing heel kicked out through their backs.
  Below the knee they give 85 % of each thigh's share to the shin behind and 50 % in front
  (`_skirt_weights` `shin_back`, `shin_front`).

Leg vertices drawn through at the worst of 8 samples of Walk / Run / Sprint, on the built parts:

| part | before (as shipped) | after |
|---|---|---|
| kilt | 49 / 97 / 115 | 0 / 2 / 2 |
| tunic over trousers | 19 / 35 / 58 | 0 / 3 / 5 |
| skirt | (floor only) 0 / 3 / 9 | 0 / 3 / 3 |
| dress | (floor only) 0 / 5 / 9 | 1 / 3 / 2 |
| coat over trousers | (floor only) 5 / 28 / 30 | 5 / 5 / 8 |
| robe | (floor only) 40 / 75 / 70 | 2 / 7 / 14 |
| wrap skirt | (floor only) 20 / 35 / 46 | 5 / 10 / 25 |

"Floor only" is the shipped part with its floor dropped in numpy (`--open-hem`): with the floor,
every count was dominated by the legs through it.

What is left: at the full stretch of the Sprint a shin still comes out under a raised knee in the
narrow wrap skirt and the robe to the ankle, and the robe's back stretches into a long sheet to
the trailing heel. Linear skinning on the rig's bones cannot hang cloth from a knee any better;
skirt bones driven from the thighs would.

`tools/tests/test_garment_clips.py` holds both: no floor under any skirt (the child cuts too),
and the counts above with a margin, in the Run and the Sprint.

Two forge fixes the rebuild found: collapse decimation left the open coat with a polygon the
glTF exporter could not triangulate, and it wrote no mesh (`decimate` validates now); and that
failure raised `SystemExit`, which `_guarded` did not catch, so the run threw away every part
after it.

### Seen in the engine

`tools/forge/preview/looks.sh` with `looks/stride.json` (the Vale tunic over trousers, the dress,
the Lakefolk coat, the Clans kilt, the Reedfolk wrap skirt, the Ash-Pilgrim robe), held at
Sprint@0.15, Sprint@0.45 and Run@0.26, from four sides:
- The tunic over trousers, the Vale's and most people's, is clean in every frame. The kilt is
  clean: the raised knee comes out under its hem, as a kilt's does. The skirt and the coat are
  clean but for a stretched sheet behind the trailing knee.
- The dress shows paler patches on its front in the Run: the knee wear painted into every
  garment's bake (`_worn`), which on a skirt reads as fading, not as a knee.
- The robe is not good enough. In the Run and the Sprint its front stretches from the raised
  knee to the trailing foot into a pale sheet, and the raised knee still shows through it in two
  or three small patches. clipcheck counts it at 7 and 14 vertices, fewer than the eye does.
- The wrap skirt shows a small patch of the raised knee in the Sprint.

The faces frame (`--frame=face`, the five people of `looks/outfits.json`) shows the faces pass
in the engine: lids on the eyeballs, open nostrils, cheeks and lips coloured, each person off
true. The brows are still heavy. The hawk head's nose tip reads dark in front light.

### Faces: lighter brows, and the heads' UVs no longer fold over themselves

In the engine's face frame after the faces pass, the brows read as two dark bars and the hawk
head's nose tip read dark and blotched. The brows were a 9.5 mm stroke at 82 %. They are now
7.2 mm at the tail and 8.4 at the head, at 70 % (`paint.skin_paint`). The nostrils are painted
only where the surface faces down.

The nose was not the paint. Every head was UV'd by projecting onto a cylinder round the skull. That
projection folds wherever the face is not a height over the axis: under the nose, the brow ridge,
the lids, the lips. Each fold shares texels with what lies over it, and 1,057 to 1,345 of each
head's 6,400 triangles overlapped. The hawk's nostrils and the shadow under its long nose were
painted over the front of the nose; the blotches were in the albedo, the normal and all four
marks channels at the tip. The same folds mottled the brows.

`bodylib.head_islands` (numpy) replaces the projection:
- It keeps the cylinder wrap, one piece, with its long seam down the back of the head under the
  hair.
- The wrap is stretched so the face gets three times the texels of the rest. At 1024 that is
  20–22 texels/cm on the face and 12–13 on the back of the head, against 20 and 25 before.
- What the wrap turns over or piles up (the nostrils and the underside of the nose, under the
  brow, the lids, under the lips and the chin, the crown) is cut out, laid flat by the way its
  faces look, and packed in a band above the wrap. A triangle that still shares texels goes on
  its own. The seams run round the eyes, the nostrils and the sides of the nose, in the creases.
- The head is triangulated first. Cut per triangle of a polygon's fan, the hawk kept 51
  overlapping triangles where the exporter split quads along the other diagonal.
- Each head island bleeds 8 texels, not 4.

Two things were tried first and not built. smart_uv cuts islands by angle, so its seams can fall
across a cheek. Blender's own unwrap of a face island with seams marked round it failed to solve
on 2 of 10 islands.

`tools/tests/test_head_uv.py` checks every head for triangles that share texels. The built heads
have none.

Seen in the engine, close up (the face frame) from the front, three-quarter, side and back: the
nose tip and the brows are clean, and no seam shows on the face, the neck or the back of the head.
The shading under the cheekbone in the side views is painted and the same as before.


## Falls on their steps, Wardens' Rest a fort, props off the roads, and where you are set down (settlements, 2026-09-25)

**The six commits of the last session** (crag ledges, their LOD ladders, the cave on a shelf, the
farm keeper's spot, whole standing stones, the fall's runtime brow) went into main as df2a602a.
On the merged tree: test 1894 tests, 1 failed (test_talk_to_the_warden, which passes alone; its
facing was measured 60 physics frames after the talk, before the turn had begun under load), 0
script errors, census 137; journey 16/16; smoke PASS; flow PASS on all three starts at the second
try (the first was OOM-killed at the opening's first shot).

**The falls on the world's step** (`fall` on a waterfall's pois.json entry, CONTRACTS section 6).
e689df50 stands the face from `foot_m`, facing `facing_deg`, with no brow, and draws no water
where a river falls there. The first shots on w4096b showed two faults, fixed in b663f632:
- Kharrow Force's river goes over 10.2 m to one side of the POI's centre, and the channel stood
  dry beside it (Whitecut 2.6 m, Foxfire 2.4 m). The channel now centres on the rivers.json fall
  whose foot is on the face's line.
- The river's sheet leans back 2.5–3 m from foot to lip, and it stood inside the channel's
  ledges. The channel is set back up its height along the lean.
On w4096c (15 frames, all opened) the river falls in front of the notch at Whitecut, Foxfire and
Kharrow, the Three Sisters read as three tiers with the river down them, and no column stood a
tower. What still read wrong: faces as walls, alternating tall and short columns where a valley
had cut the step back, and an even top. On the branch for the next 4096 (not in main): a taper
from the channel's height, a crest that rises and falls with no two neighbours level, varied
courses, turf and moss over the top edge, and each column on `fall.line`'s forward offset, its
height scaled by the line's drop share. Shot on w4096c with the taper: continuous faces; the
Glass Falls still a dark wall, the rocks near-white (the painted look's rock values follow).

**Caves** (`cave`, the next build): the mouth on the raised face's line at `mouth_behind_m`, its
throat level into the hill under the face's top, its first ring the region's stone, cliff ledges
either side, a lip of stones and ferns, nothing heaped on the roof. Without `cave`, a bank of the
ground raised over the throat. The first bank was a dome over the throat; on w4096c it read as a
smooth green hemisphere with the mouth buried under its front, and it is now a heightfield of the
ground with the mouth left open. Not yet shot again.

**Wardens' Rest is a fort** (d59bf37d, for the next landing): a palisade of pointed stakes on
the houses' outer ring, a gatehouse of two stone towers where each road comes through with a walk
over the way and the Wardens' banner hung from it, an 11 m watch tower at the back, and a drill
yard on the square. Looked at on w4096c from the opening's 210 m, the Roll's 100 m and the gate:
it reads as a walled fort from each.

**Props off the roads** (the Sulion barrel on the road at knee height, the Bell of the Pilgrims'
house-sized bell across its road): PoiKit keeps every prop's foot 2.2 m plus its half-width from a
road's line. test_pois checks every POI against the built roads.

**Arrival points**: PoiDressing.arrival() and arrival_for(id), used by the console's tp: open, dry
ground clear of every collider, nearest the middle on the road's side, or the nearest shore. The
first version took every trimesh for floor, and set people down on tents and ribs (36 POIs); only
the dressing's own laid earth is floor now. test_pois checks every POI with a physics capsule
query: 22/22 on batch 4's world.

**Street cameras**: tools/capture/make_streets_plan.py stands each on its street, 42 m out,
looking down the road; they looked at back gardens.

**Not done**: the pen fences (timber grain, woven hurdles) are written and not shot; the eleven
wayside kinds and the cart wreck wait on the rock values and a reshoot (the fold, cairn and tally
post frames were mostly the camera looking into a 35-degree slope; the plan now raises it until
its line of sight is clear); the dome at playtest 6's top left is the Cracked Toll landmark.


## Steep ground, the ash round the start, river banks, and the lines on the slopes (world builder, 2026-09-25)

**Walls, hedges and rails on steep ground** (a96e04f9). No line piece was ever pitched: each was set
level at the lower of its two ends, so on a steep bank its uphill end went into the ground (1,728
w4096c wall pieces were buried by more than a metre of their 1.42 m). A piece now follows the ground
along its run, up to 20 degrees for a wall and 24 for a hedge or rail. Where the ground is steeper,
a wall or hedge piece is stepped: split into up to three shorter pieces. Re-seated on w4096c's
cells, no end is buried more than a metre. Frame 12's "upright wall" was a level piece running
straight away from a camera 3 m off it.

**Nothing in the air or under the hill** (b2da2089). offground.sweep is the last pass over the
scatter. It takes out a row whose foot stands more than 2 m over all the ground under its
footprint, or whose top is more than 2 m under all of it. On w4096c that was 72 of 5.7 M rows, all
cliff ledges; on a 1024 it is 1.2% of the ledges, from the texel smear on sheer faces. The boulders
reported "under the hill" lie on a beach under a 116 m sea cliff.

**Steep ground is earth, scree and rock** (b8e045a6). The playtest-6 bank had grass painted down a
wall. surface.STEEP gives each region three thresholds, each the middle of an 8-degree band that
wanders 12%. From the first the earth shows, from the second scree and rock, and from the third,
just past the 45 degrees a player can walk, the ground is bare rock:

| Region | Earth | Scree | Bare rock |
|---|---|---|---|
| Downs | 34° | 44° | 50° |
| Lake basin | 31° | 42° | 49° |
| Delta | 30° | 41° | 48° |
| Forest | 30° | 40° | 48° |
| Ash plateau | 28° | 38° | 47° |

Turf thins in patches and holds longer in hollows. On a 1024, the grass on 45-60 degree ground fell
from about a third to 0-4% in every region.

**The ground's tint** (85784181): chroma gain 1.3 over a floor of 0.72, and the downs' gold at a
third. The Hearthvale's median colour-map blue went from 0.50 to 0.77, so its grass is no longer
mustard.

**Cinderlea round the start**:
- 0f5eb8e9: the painted look's ash-ground rules, ported onto STEEP. Ash drifts into hollows and
  onto the lee faces, grey grass holds the flats, stone breaks through on the windward noses, and
  the burn leaves black patches.
- 1d16c6e3 and 38a96b14: landforms.ash_erosion. It cuts rills and gullies up to 7 m where the
  water gathers, terracettes, slump scars and wind hollows, down to the shore (held off the water
  below 6 m of height).
- 6eab07a5 and c03945f1: the erosion is held off a road only 1.5 m past its carriageway and three
  quarters of a texel, fading over 6 m. So the slope the Hushline Stair zigzags down (every 16 m)
  is no longer one smooth mound. test_ash_erosion.NearTheRoads: no cut deeper than 0.5 m within
  3 m of the stair's line, and rills between its legs.
- 8e9ce120: a sea cliff's dressing stops 12 m past the drawn cliff's ends. The walk along the face
  ran on round the ends of the Hush's two 78 m cliffs, and put 458 ledges on the stair's slope in
  rows of white blocks.

**River banks** (47fb7ef3). The water lay 1.4-1.6 m down a trench under its banks. The valley floor
was carved to the water plus a metre, and the channel's bank rose to its lip over the whole bank
band. Now the lip is 0.35 m over the water within 0.8 m of its edge, and the floor meets it at 0.45
m. test_river_valleys.BanksBuilt checks every river of a 4096 build: the ground a texel past each
bank may be at most 0.55 m over the water (median) and 1 m (80th percentile).

**Falls** (8697e8c7): a step's face bows with the dressing and its wings swing round the pool
(`fall.line` in pois.json). **Caves** (d583ff38, 4b54f697) have a shelf or a knoll to go into, and
an authored landing keeps its level to its radius.

**Sheer faces stretched on the 1024 shots.** Terrain3D 1.0.2's shader (in its binary) has no
Compatibility branch for projection: the only `CURRENT_RENDERER` guard defines fma and the coarse
derivatives. Projection runs wherever a texel's normal is under `projection_threshold`. Its normal
is taken across one control texel, so on a 1024 preview (8 m texels) a sheer face's normal comes
out steep enough on some texels and not on others, and the texture streaks down the face. The same
three slope shots on the committed 4096 world, on Compatibility, show no streaking (scratchpad
world-builder/proj_compat_sheet.png). The Forward+ frame was not shot: the queue for a 6 GB slot
held it, and the 4096 frames settle it. The runtime now sets `projection_threshold` to 0.86 (31
degrees) instead of the shader's own 0.8 (World.PROJECTION_THRESHOLD).


## The country behind the title, a skip that says so, and the stop captures on batch 4 (graphics, 2026-09-25)

### The title's vista

The user asked for a slow cinematic camera behind the title menu, across several areas of the
game. It is `ui/menus/title_vista.gd` (TitleVista), which the menu starts once it is built and live.

* **Standing up.** The world is stood up behind the menu as a *vista* (`World.vista`): no body,
  no services, and it never calls `GameState.enter_region` or reports a region from its streamer.
  So the music, the HUD and a later game's first region never hear of it.
* **Streaming.** Its own camera leads the streamer. The next shot's start and what it looks at are
  asked for beside the current one (`set_also_around`), so only the current and the next shot's
  country is streamed. A shot is shown only when its cells are in; while they come, the shot before
  holds its last frame, at most 8 s.
* **The shots.** They dip to dark between them. Each has its own hour (the clock is held and given
  back) and its own region light and weather.
* **Shown and gone.** The first shot fades in over the chart the menu always had. Leaving the title
  (New Game, Continue and Load all change the scene) frees the world and everything it streamed.
* **Data.** The shots are `core:cinematic/title`, seven of them: the Choir at golden hour,
  Merrowby and the Cracked Toll, Whitecut falls, the Mere from 150 m, a Briarwold road by Fernhold,
  the Skerrow crags, and a Sedgemire causeway at first light. They are validated like the opening's;
  a `loops` cinematic hands no control back.
* **The setting.** The Graphics tab has "The country behind the title"; Low keeps the chart.

The Hushline from the Stair Head was dropped: `cinematic_paths_clear` found it looking at the
south edge of the world 366 m away. The Briarwold and Sedgemire cameras were moved out of a giant
oak and a willow that the same test found.

**Measured on batch 4.** `test_title_vista`, 5 of 5:

* the menu takes the keys while the world stands up behind it;
* the country came up 15.7 and 18.6 s after the menu, headless;
* every shot round the list was shown with its cells in;
* leaving the title leaves no world, streamer, camera, services or cinematic player, gives the
  clock back, and never reports a region;
* stopping brings the chart back.

`tools_gd/title_film.tscn` poses each shot, waits for its country, and draws it at Medium. On
this machine a frame takes about 16 s, so playing the shots in real time filmed only the first.
Draw calls / primitives per shot:

| shot | draws / primitives |
|---|---|
| the Choir | 671 / 0.56 M |
| Merrowby and the Cracked Toll | 768 / 0.95 M |
| Whitecut falls | 747 / 0.95 M |
| the Mere from 150 m | 256 / 0.62 M |
| a Briarwold road | 893 / 1.02 M |
| the Skerrow crags | 418 / 0.61 M |
| a Sedgemire causeway | 716 / 0.71 M |

The menu took focus at 242 ms; the country came up at 54 s on the software rasteriser. Every
frame was looked at. What they showed:

* The Choir at 19.1 h was already night (now 18.35 h).
* The causeway at 6.1 h was too dark (now 6.9 h).
* The falls and the causeway stood behind the sheet (now in a third of the frame beside it).
* The torn sheet over the vista covers the middle of the picture; the painted look is designing a
  narrower panel in one third.

### A test that could not run is counted as skipped

`TestCase.skip(reason)`. The runner prints `SKIPPED: <test>: <reason>` and the summary reads
`N tests, F failed, S skipped, ...`. `test_cinematic_paths_clear` used to return silently without
the full-resolution `heights.r32`, and read as a pass; it and the eleven tests that printed
"(... skipped)" now report every test they skip.

### Collision on batch 4: the stop captures, and the gates

Checked on the batch-4 world:

* **Stop captures** (`tools/capture/plans/scatter_stops.json`): the body stands at an oak's bark,
  at a field hedge's leaves, and against a drystone run.
* **The leaning boulder** (scale 1.84, leaning 19°): its solid profile, from rays down onto the
  scatter layer, stands 2.2 m in the middle and 0.5 m at the shoulder. At a jog the body slides
  off the round face and steps over the shoulder.
* **Wayside gates** stand their shutting post and leaf (a test).
* **Coverage:** a test holds every forge tree to a trunk, and every wall, hedge, fence, hurdle and
  bale to a box.

### The blue box (in progress)

The painted look's ledge pose on w4096c draws a blue box, reproduced here. It is not a hedge, and
not a missing albedo: an audit of every forge model's imported scene found 0 surfaces without
their albedo texture at any LOD. A capture shot can now `hide` named things; the isolation shots
are queued.

## Swimming, and a slanting walk along a wall (player feel, 2026-09-25)

Playtest 6: there was no swimming. The terrain's collision runs under the water, and the player
walked along a lake bed with the surface overhead. Now the water is read every physics tick, and
past the chest the body floats.

**The water.** `Swimmer` (`actors/player/swimmer.gd`) reads the water at the body through one
call, `Swimmer.water_at`. It calls the water agent's `WaterSurface.at` (cherry-picked as 81891ede
from wip/water-2's 27e68a9e): rivers at their ribbons' own sloping surface with their current,
falls' pools, lakes and the sea, against the 2 m ground. Where no water is built it falls back to
TerrainProvider's 8 m map, with the 2 m ground deciding at a shore. The bed is the first collider
below the soles (the terrain, a rock, a wall), or the heightfield.

**Wading.** Water past the knee holds the legs back: the pace falls to 0.85 at the knee, 0.6 at the
waist and 0.45 at the chest (heights for a 1.8 m body, scaled with it). Past the waist there is no
sprinting, rolling or jumping. Walked into Lark Pool on W at a jog, the fastest pace in each band
was 5.0 m/s dry, 4.3 to the waist and 3.0 to the chest.

**Swimming.** Where the water over the bed is deeper than 1.35 m, the body goes into State.SWIM:
- The capsule rides with its soles 1.45 m under the surface on a spring, never nearer the bed
  than 0.15 m.
- The guard, the lock, the sneak and the sprint are let go, and the weapon goes back on the hip.
  Nothing is swung, cast or rolled. An attack pressed afloat does nothing, and the weapon stays
  sheathed.
- Swimming is 1.6 m/s, easing up at 3 m/s² and gliding down at 2.2. Sprint is a hard stroke at
  2.6 m/s for 10 stamina a second.
- A river carries the swimmer at 0.6 of its current.
- The sneak key dives, down to 3 m under the float and never nearer the bed than 0.15 m, and
  surfaces again. Twenty seconds under runs the breath out, and the body rises until half of it is
  back. There is no drowning.
- A stunned or dead body in deep water is held at the float, not sunk.

**Out of the water.** A bed shallower than 1.2 m hands the body back to the wade; the gap from 1.35
m stops it flickering at the edge. Swimming into a bank, or pressing jump at one, looks up to 1.9 m
ahead for a top between 0.4 m under the surface and 1.0 m over it, flat enough to stand on. The
body is hauled up onto it as a mantle, in up to a second. "Into a bank" means against a wall, on
the bank's slope, or held back by it to under 40% of the stroke's pace.

**The camera.** Over water the third-person camera stays 0.3 m above the surface, so it never looks
up through the sheet. While swimming it rides at 1.95 m over the soles, 0.5 m over the water. The
water agent's `UnderwaterView` washes the frame if a first-person view goes under.

**The clips** (the forge, `anim_clips.swim_clips`, transplanted with every other clip byte for byte):
- **Swim_Idle** treads water, 36 frames. The body stands upright with the hands sculling out and in
  at the chest and the legs beating in turn. The head's base is at the surface and the shoulders
  7-12 cm under it.
- **Swim_Forward** is a breaststroke, 36 frames. The body is laid 66 degrees forward with the head
  held up. The arms glide, pull wide and tuck, and the legs whip. The shoulders ride within 5 cm of
  the surface and the trailing feet 0.44 m under it.
- The model rests in a Swim state (`HumanoidModel.set_swimming`): treading blended into the stroke
  by pace, the stroke played at the pace swum over its 1.6 m/s. The foot planter stands down there.
  A flinch afloat goes back to the swim, not through a walk.

**From the keys, on the built world** (`tests/unit/test_swimming.gd`, the tracked batch-4 world and
the installed w4096c):
- Walked into Lark Pool from its west shore at (166, 2492) on W: the body floats from 3.0 s.
- Afloat, the head's base stands 0.01 to 0.12 m over the surface.
- The soles stay at least 0.29 m off the bed.
- A dive on the sneak key goes 2.62 m down, 0.24 m off the bed, and the body comes back up all
  2.62 m.
- Turned round, it swims back and walks out onto dry ground in 12.5 s.
- At the Mere's steep bank by Tollmere (the water agent's (-262, -330)), found where the ground
  leaves 3.5 m deep water within 3.5 m: swimming into it, the body is out and standing 0.25 m over
  the surface in 2.9 s.

**A slanting walk along a wall.** The graphics branch made trees, fences, walls and rocks solid (the
streamed physics ring). Walking into them square on was already measured there. Walking along them
had a fault: a jog met at 60 degrees slid along a wall, a hedge or the rails at 0.5 m/s, a walk's
pace, where it should keep the half of its 5 m/s that lies along it. `_free_move` had taken a body
making less than its whole pace for one that had run into a wall, and dropped it to the speed made
every few frames. Now it compares the speed made with the share of the pace along the wall.
`test_walking_into_the_scatter.test_a_slanting_walk_slides_along_a_wall_a_hedge_and_the_rails`
walks and jogs at 30 and 60 degrees into each and allows no more than 6 frames running under half
that share. The jog at 60 degrees
now goes along the rails and the wall at 2.50 m/s, all of its share, where it went 0.53. Along the
hedge it goes 1.41, whose rounded joints catch it. The walk at 60 degrees goes 0.90 (0.78 along the
hedge), and at 30 degrees the jog goes 4.33 (2.79). No run is under half its share for a single
frame, and the square-on stops are as they were.

**Filmed.** `tools/capture/plans/swim.json` walks the body into Lark Pool on W
(Compatibility, the built terrain, a fixed 60 fps), filmed from its right. Then a second run holds
Shift. The frames are in `scratchpad/player-feel/swimfilm`, tiled in `swim_sheet.png`.
- The jog slows through the shallows: 5.0, 3.8 and 2.4 m/s at 6, 11 and 14 m in.
- The body leans into the water as the swim blends in (0.35 s).
- From 16 m it swims at 1.6 m/s with its soles steady at 44.55 m, 1.45 m under the 46.0 m surface.
  Over the shelf the clear shallow water shows the whole body laid out in the stroke under the
  surface. Past it, only the head and the shoulders are out of the water, the arms pulling at the
  surface.
- Holding Shift, the hard stroke goes 2.6 m/s and runs the stamina down 10 a second.

### Not done
* NPCs and foes do not swim: they stand on the bed as before, and a foe does not follow the player
  in.
* No breath is shown on the HUD, and nothing is heard differently under water.
* The swim has no rolls, no surface dives from a run, and no climbing onto a boat.

## The breath under water, and foes and villagers in the water (player feel, 2026-09-25)

**The breath gauge.** While the player swims and its breath is short, a short pale bar sits under
the three in the HUD's brass plate. It is the Saying's blue washed toward the water's white. It
runs down while the head is under and fills again at the air, and it lingers 1.2 s once full. Two
and a half seconds into a dive at Lark Pool it read 89%, and it was gone once the body had surfaced
and breathed (`test_swimming`).

**Foes and villagers in the water.** They walked the bed with the water over their heads. Now
`Actor.water_tick` (foes) and `Npc._in_the_water` (villagers) read the same Swimmer as the player:
- past the knee they wade slower;
- in water deeper than the chest they float with their soles 1.45 m under the surface and their
  model in the swim, at no more than a swimmer's pace;
- a dead foe in deep water floats too.
Stood in Lark Pool's deep water, a roadside bandit and a villager each rode with their soles 1.45 m
under the surface. Stood on the knee-deep shelf, both stood on the bed
(`test_swimming.test_a_foe_and_a_villager_float_in_deep_water`).

Not done: a foe afloat still swings; beasts float in their own walk.

## The rider's own clips on the cob (player feel, 2026-09-25)

The tree forge's cob seated its rider in the standing Idle, with a modifier (RideSeat) laying the
legs astride. The rig now has four clips of its own for it (`anim_clips.riding_clips`). They were
transplanted onto the rig with every other clip byte for byte (clipdiff: 84 identical). All four are
made in the saddle's frame: their root is the seat (Socket.Saddle), and the Rider stands the body's
origin on it.

- **Ride** (72 frames, a loop): upright, a give in the small of the back, the hands on the reins
  0.30 m ahead and 0.25 m up. The balls of the feet are on the treads 0.63 m under the seat with the
  heels down 10 degrees, turned out 18 degrees so the knees go round the barrel (0.32 m out).
- **Ride_Gallop** (18 frames, a loop): two-point, the hips 9 cm out of the saddle and forward over
  the withers, the hands along the crest, with a bob each stride. The Rider plays it while the cob
  gallops.
- **Mount_Horse** (1.3 s, `seated` at 1.08 s): from standing on the near side 0.55 m out, the left
  foot goes into the iron turned well out. The body springs, the right leg goes out behind and over
  the croup, and it settles into the Ride pose.
- **Dismount_Horse** (1.1 s, `landed` at 0.98 s): the way down, the right foot out of its iron first
  and back over the croup, landing on the near side. The Rider then steps the body out to where it
  has room (0.35 s).

**Kept out of the horse.** The clips are checked against the cob's own body, its signed distance
field from the tree forge's `horse_body.horse_scene`. A leg's middle must stand its radius (thigh 8
cm, shin 5) off the hide. At the stirrup width first given (0.33 m out) the shins went 6-7 cm into
the barrel. At 0.37 they go 3.2 cm (Ride), 4.4 (Ride_Gallop), 4.0 (Mount_Horse) and 4.6
(Dismount_Horse): the calf pressed against the flank. The tree forge moved its irons out to 0.37 m
(6b6fdaf0, on its next horse build).

**Found on the way.** A looping clip played as an intent (a seat, a hang in the air, a held cast)
went back to the idle after one turn. A rider would have stood up in the saddle 2.4 s after sitting
down. `HumanoidModel` now plays such a clip round until something else is played.

**From the keys** (`test_riding.test_the_rig_mounts_rides_and_gets_down_on_its_own_clips`):
- E plays Mount_Horse, and the seat is Ride with the body's root on the saddle.
- Shift+W gallops the cob, and the body plays Ride_Gallop with its hips out of the saddle.
- E again plays Dismount_Horse, and the body gets down on the near side, clear of the flank, on
  the ground.
- The tree forge's riding tests pass with it, and so do test_player_locomotion,
  test_hit_reactions and test_combat_spells, which play looping intents.

**Filmed.** `tools/capture/plans/ride.json` (the capture runner's gait can now stand the cob with
`"horse": true`, and send keys on a `"timeline"`). It films E, Shift+W for 4 s, a coast, then E,
at a fixed 60 fps on the flat east of the Cracked Toll (`scratchpad/player-feel/ride_sheet3.png`).
- The body steps to the near side, puts its left foot in the iron with the knee turned out beside
  the shoulder, springs, and swings the right leg wide over the croup.
- It sits upright with its hands at the withers, and at the gallop it stands in the irons over the
  neck.
- Getting down, the right leg comes back over the croup. The body lands at the flank and steps
  clear, standing beside the horse.
- The first film had the spring rising a metre over the saddle. It now sits down onto it, within
  the left stirrup's reach (5 cm).
- The film found the rider's `w` shadowed in the dismount's step-off, the GDScript warning the
  coordinator saw in main. It is renamed.

### Not done
* Only the cob's own clips are seen at a canter or trot (Ride at every gait below the gallop);
  a rising trot is not made.

## POI cameras on steep ground and in the Greatwood; wave 5 drafted; batch 4 measured (cartographer, 2026-09-25)

**The POI capture plan's cameras** (`tools/capture/make_pois_plan.py`; a1b58eec, 5a640485, 7aefa321).
It now checks each camera against the land it looks over, as the world builder's look plan does.
- A camera stands on dry land, out of every crown, and clear of each trunk's bark by that trunk's
  own thickness: the forge's collision radius for the asset, times the instance's scale.
- The ground stays under the line of sight up to the POI's own 10 m.
- The line of sight misses every trunk by that trunk's radius.
- Trunks nearer than the POI fill at most 12% of the frame's width, or 30% as a last resort in a
  wood.
- Where the approach-side spot fails, the camera is raised (+3, +7, +14 m), swung round in 20°
  steps and brought nearer until one holds.
- All 391 POI shots on the batch-4 world find a camera; none falls back.

**Looked at** (w4096c for the first three, the tracked batch-4 world for the Moss Bed):

| Find | Before | Now |
|---|---|---|
| the Oskel Drip | the camera stood inside the dale side | sees the cave across its dell |
| the Rafters' Locker | the camera stood in an alder's crown | seen from the bank path, though dark |
| the Beacon Shieling | the pad a terrace with a hard front edge | sits on its ridge shelf and reads |
| the Moss Bed | black, even at 11:00, with bark filling the left of the frame | seen from the open, 24 m off |

The Moss Bed stands under five giant oaks, reaching 26–41 m, whose crowns top out 40–60 m up.
Its old camera was 8.7 m from one oak (scale 1.27). Another oak, 13.6 m off at scale 2.0 and so a
trunk 4.8 m round, filled the left of the frame. The crown model alone did not see it: it counts
trunk centres, not their thickness. From the new camera the bed reads in the middle of the frame,
candle-lit among the trunks. The whole wood is very dark at 17:12 and at 11:00 alike, and that
is the canopy's shade, not the camera.

**Wave 5 drafted** (`tools/world/atlas/drafts/wave5.json`, edd30b75), not in the pack.
- 29 off-road finds: 10 cairns, 7 folds, 4 tally posts, 3 wells, 2 lantern posts, 2 graves and a
  hut.
- Each is written against the keywords of settlements' builders on `wip/settlements`.
- It waits for those kinds to reach main's KINDS_BUILT; main's list does not have them yet.
- The sites were proposed on the batch-3 world. Checked against batch 4's things, 28 of 29 still
  stand more than 100 m from anything. The Hold's Last Look (a cairn) is 51 m from the Hag's Hut,
  so it is to be re-sited before wave 5 goes in. The same road has spots 120 m clear of
  everything round (605, -2962).

**Main merged** (857b8161, batch 4). Measured on the tracked batch-4 world:
- gap map: 17.2 of 120.9 km of road thin (43 gaps over 300 m; longest 669 m); 1.7 km² of empty
  country.
- threats: 114 met along 106.2 km outside the safe way, one every 932 m; 5 quiet runs over 900 m,
  5.3 km in all.
- check_atlas has 0 errors. poi_hooks --check has 396 rows, 0 differing. The gap map (15), atlas and
  atlas-map (31) Python tests pass.

**The ground shots' frames** (`tools/capture/frame_check.py`, 53d79210).
- **Why.** bcf2900c moved briarwold_ground1 and briarwold_ground2 so that test_capture_plan passed
  on batch 4, and the captures of both were bad.
  - ground1 stood 10 m inside the world's east edge and photographed sky over fog.
  - ground2 photographed a giant oak and a cliff ledge.
- **The frame check.** A ground shot now fails on any of these:
  - it or its look-at point stands within 600 m of the world's edge;
  - anything stands within 12 m in front of the lens, by its real extent. That is a tree's trunk,
    or its crown where the lens is level with the crown; a rock's, ledge's or landmark scene's
    bounds; each times its scale.
  - trunks fill 12% or more of the frame;
  - the ground cuts the line of sight within 200 m;
  - half the frame is stopped within 75 m. Nine rays run across the width, against the ground
    and crowns at 0.7 of their reach. A lens on a slope, level with the wood below, sees leaves.
    On the frames looked at, the two leaf walls measured 38 and 70 m, and the good frames 78 m
    and up.
  - it stands within 12 m of a settlement's outskirts, or 30 m from a POI.
- **In the generator.** make_default_plan checks each ground shot with the frame check, with 25%
  spare for the coarser heights the test reads. When a shot fails, it rings out from the spot
  20 m at a time, up to 1 km, turning up to 180°.
- **The test.** test_capture_plan checks every committed ground shot with it, and eight synthetic
  cases. Against bcf2900c's plan it fails both Briarwold shots.
- **Result.** 18 of 18 ground shots are clear on batch 4. They are the generator's own ground shots
  on batch 4's full heights, and no other shot in default.json was touched.
- **Looked at.** All 18 were captured on the tracked batch-4 world and looked at, and each is a
  frame of its region: Briarwold over the canopy and out to the sea, the Vale's meadows and
  crags, the fen, the Skerrow's dales and the ash.
  - sedgemire_ground1 has the Drowned Nave's tilted tower in its top right, 151 m off. It is the
    landmark, not an obstruction.
  - Before the check had a footprint rule, the same shot had stood under the Nave's roof.

**Still to come:** the road encounters and weapons (7a15960f) ride the next 4096 build, because
the 13 new finds need pads.

### For other areas, seen on the ground-shot sheet
Both of these were routed to their owners by the coordinator.
* **The Drowned Nave's tower hangs in the sky like a box** in sedgemire_ground1. The camera is at
  (-3298.4, -1571.3), looking toward (-3038.4, -1121.0).
  - The scene is `sedgemire_drowned_nave_a.glb`, placed at world (-3300.0, 4.08, -1420.0), yaw
    147.
  - Its bounds are 119.5 m tall, from x -40.8 to 22.3 and z -24.1 to 43.5.
* **A bright blue box on the right** of brightwater_ground3. The camera is at (-442.0, -1694.0),
  looking toward (-862.7, -1388.4).
  - It is a `brightwater_boulder_a.glb` instance at world (-473.84, 37.89, -1695.92), yaw 181.9,
    scale 2.08, in cell 14_9.
  - Its row carries two extra values after the tint, 10.0 and 173.2.

### The POI cameras' frames, and wave 5 in the pack (later on 2026-09-25)
* **POI frames** (0d1aab3f). `frame_check.py --poi` failed 59 of the 391 cameras make_pois_plan
  chose on batch 4. Most had walls or fences against the lens, sat inside a giant oak's crown on
  a slope, or had half the frame stopped short of the POI.
  - The generator now tries every pass with the frame check first, on both the full heights and
    the runtime maps. 68 cameras moved, and all 391 pass.
  - `plans/pois.json` is regenerated on batch 4, with the 120 wayside finds.
  - test_capture_plan: 30 passed, including test_every_poi_frame_holds_its_poi.
  - The worst-12 contact sheet, before and after, is queued behind the world-build lock and not
    yet looked at.
* **wip/atlas-cameras** (3d360703) carried a1b58eec, 5a640485, 7aefa321 and 53d79210 alone onto
  claude/blissful-volta-dg80e6: `python3 -m pytest tools/tests` passed 63.
* **Wave 5** (557e4979). 29 finds in settlements' kinds, the Hold's Last Look moved to
  (550, -2997), 141 m clear.
  - Thin road went from 17.2 to 12.7 of 120.9 km (31 gaps over 300 m).
  - Empty country went from 1.7 to 1.0 km².
  - The locations are now 482, at 10.2 a walkable km².
  - check_atlas has 0 errors. poi_hooks has 425 rows with 0 differing. test_gap_map passed 15
    of 15.
  - The Godot filters are queued. The finds need pads from the next build.

### w4096d (main 70599867), measured and looked at
* **Threats:** 114 met along 106.2 km, one every 931 m. There are 6 quiet runs over 900 m
  (6.2 km); two are the Ash Strand's and the Ashgrid's, which are meant to be quiet.
* **Gap map, on main's pack as built:** 17.3 of 120.8 km thin, longest gap 669 m, 1.7 km² empty.
  With wave 5 once it has pads: 12.8 km thin and 1.0 km² empty.
* **Wave 5 has no pads in w4096d.** Main merged this branch before 557e4979, so the 29 finds wait
  for the next build.
* **Road threats looked at,** in six captures with a player body standing near. Foes stand at:
  - the Drove Gate Toll (a keeper among the tents, by day);
  - the Toll Rope (a cutpurse on the knoll);
  - the Hag's Hut (the hag by the ruin);
  - the Knight's Challenge (the knight among the stones);
  - the Raiders' Perch (two outriders).
  At the Last Meal Stone, with no foes, the Ashen Sword is too small to see from 30 m.
* **Fixed:** wave 5's Shepherd's Complaint description was 77 characters, and test_books wants
  over 80 (05f10019). test_books then had 6 tests and 0 failed.
* **Not ours:** every filtered run exits 1 on the GDScript warning census (50 against a baseline
  of 49), from `world/interiors/house_interior.gd`.


### Wave 6, and the POI plan for waves 5 and 6 (2026-09-26)
* **Wave 6** (b1060139, merged into main as f84608fa): 20 finds at the last long gaps, and four
  threats on runs over 900 m that were not meant to be quiet.
  - The threats are the Clanless fire-ring on the Fallen Hand road, the hewers on the Dreugh
    beacon, the drowned in a sunk trader off the Saeva road, and bandits in the Wynstead ditch.
  - Thin road went from 12.8 to 5.9 of 120.8 km (15 gaps over 300 m). Threats went from 114 to
    118 (one every 900 m). Quiet runs went from 6 to 2 (2.5 km), both meant to be quiet.
  - The locations are 502, at 10.6 a walkable km².
  - Checks: check_atlas 0 errors; poi_hooks 445 rows, 0 differing; test_gap_map 15/15;
    test_poi 94, test_books 6, test_map_quest 12, test_content 43, all with 0 failed.
  - The record is `tools/world/atlas/drafts/wave6.json`, and ATLAS §17 has the section.
* **The POI plan** (cfff3aca): 453 shots. The 49 wave-5 and wave-6 finds that w4096d has not
  placed get cameras at their defs' positions until the build gives them pads.
  - Cameras are checked as they are written, rounded to the decimetre. The Wolf Stones' camera
    had passed unrounded and failed once rounded.
  - The Rafters' Locker has no clear frame on w4096d's regrown oaks, and the test names it with
    its reason.
  - The new finds are not looked at yet: until their pads are built, a capture shows them on
    unlevelled ground.

### The roads signed: fingerposts at the junctions, town stones at the ways in (2026-09-26)
* `tools/world/atlas/signposts.py` writes `signposts.json` from the built roads: 50 fingerposts
  with 139 arms, and 86 town stones at 39 settlements, on w4096d. ATLAS §18 says how.
* **The build:** worldgen/roadside.py stands a signpost row at each fingerpost (world/wayside.gd
  builds the Fingerpost) and a `scenes` entry at each town stone. Settlements builds the
  town_stone scene. Until it lands, the stone is the Vale's milestone model (one path, which
  the test checks exists).
* **The arms:**
  - Each says its distance in Wardens' miles to the quarter ("MERROWBY  ½").
  - The lettering is cut as large as the arm allows, 48 px at 1.6 mm a pixel, and smaller for a
    long name.
  - RoadNetwork now counts points of interest as places a road can end at, so the roads to the
    Three Sisters and the Narrows Bridge are signed.
* **Tests:** test_signposts has 7 tests, all passing (the file is the world's; every parting has a
  post; every arm is real at its distance; posts and stones stand off the road; every road into
  a town passes its stone; the build stands them). test_roadside_planting passes 11. The
  test_wayside filter has 16 tests with 0 failed; it has two new tests and one changed test
  (arms now carry their miles).
* **Not yet looked at:** three junctions are to be captured after the next build.

## Wildlife between the places: herons, ducks, swans, gulls, crows, ravens and fish rising


## The starter area authored: nothing floats, dressed waystones, a carved fingerpost, the camp grouped (opening, 2026-09-25)

The user's playtest of the start: "floating lamps, those white pillars having a gap, the massive
stone pillars not being fully flush with the ground, ... a weird white sheen over some areas,
alongside several seemingly random/floating assets as if it was a testing grounds."

**What floated, and why.** Every lantern along the waystones, the banners and the bells at the
Stair Head hung in the air because their posts were not drawn at all. `SurfaceTool.append_from`
with an indexed primitive (a capsule, a sphere, a cylinder) into a batch of unindexed boxes throws
away the unindexed geometry, so the committed "Timber" was the tripod over the fire alone.
`PoiMasonry.unindexed` expands a primitive before it goes in (limb, ellipsoid, rod, and six calls in
poi_builders.gd). `test_masonry_batches_keep_everything` holds it.

**The colossi.** The plinths were meant to be sunk in `gen_landmarks.choir_colossus` and stood fully
on the ash. `WorldStreamer.seated_depth` sets a `choir_colossus` scene 1.5 m into the ground.

**The waystones.** Cinderlea has no standing stone of its own and borrowed Briarwold's: pale grey,
rough-hewn, with a cleft down the middle. In the evening light the first one, by the camp's
woodpile, was the "tall white translucent sheet", and the rest were the "white pillars with a gap".
They are now dressed pillars of the region's stone (`_dressed_waystones`):
- a foot 0.50 m wide and a narrower head, with a ridge across the top;
- 1.55 m tall and sunk 0.45 m;
- darkened, with no wear (the painted surface polishes whatever is walked on, and a waystone came
  out glossy);
- one silhouette-capable mesh, carrying its stone count, with a body for each stone.

**The fingerpost** at the camp's junction was a pale post with two near-white boards. It is now:
- a chamfered grey oak post with a cap, a knob and wedges at its foot;
- deep green arms with a moulded rail and an iron strap;
- the names cut in Cinzel capitals, cream with the groove's shadow above.

The camp's own forge signpost stood a few metres away with blank arms, and has gone.

**The camp's gear.**
- The cart's load (crate, sack, barrel) is set against the cart's own side, with the rope beside it.
- The pail is at the fire, between two stools.
- The grey grass is in clumps out past the camp. It was 46 single tufts spread evenly from 5 m out,
  which on the ash read as bundles of sticks. It draws from its own random state, so the ewe and the
  Watch still stand where they did.
- The lone fence post and rail have gone.

**The motes** are 30% as many, soft round dots from 0.03 to 0.07 m, where they were 0.06 m squares.

**Nothing floats** (`test_nothing_floats_at_the_start`). It stands at the spawn and at the Choir's
avenue. It checks every drawn thing within 120 m and fails on any whose bottom is more than 0.15 m
over the ground (terrain and physics) under its footprint. Exempt:
- anything marked with `PoiBuilders.hangs`;
- actors and crows;
- far LODs.

It also fails if a colossus plinth is not in the ash. Result: 0 of 176 things float at the spawn,
and 0 of 4030 at the avenue.

**The "white sheen".** Captured on Forward+ with lavapipe:
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run ... godot --rendering-driver vulkan --rendering-method forward_plus`.
A plan of three shots takes about 4 minutes on this machine, and Godot sometimes hangs on quit after
writing its frames, so the run is wrapped in `timeout`.

The sheen was the camp's Ash sheet (`ash_drift.gdshader`), a blend_mix layer over the ground:
- the ash lay at its own alpha, 0.25 to 0.75, so it was a pale half-transparent film;
- a 25% "dusting" ran on past every patch;
- the sheet is drawn after the ground and takes none of the SSAO that darkens the ground under it,
  so on Forward+ the film stood out lighter still.

Now where ash lies it is all but opaque, and how thick it lies is how much of the ground its flecks
cover. The flecks fade in over a wide band, and the ash is a shade darker. The first try, with a
narrow fade, left a thick patch by the cart as a pale spill with a hard edge. The second has soft
grey ash on char in both renderers.

**Frames.** Before is on main 70599867 (the w4096d world); after is this branch. All are in
`scratchpad/opening/`:
- starter_area.json (the user's avenue framing, and the spawn): before4d, after4d;
- starter_camp.json on Compatibility: camp_after;
- Forward+ on the old ash: fp_camp;
- the first view with the ash fixed: ash_gl2 (Compatibility) and ash_fp2 (Forward+).

### Not done
* The ground pad the camp stands on is the world builder's to soften.
* On Forward+, the ground within about 8 m of the spawn is a lighter, sandier texture than the ground
  past it, with a visible line between them. Compatibility shows no such line. It looks like the
  terrain's own shading, not a prop.
* For the fighting-style starts (docs/FIGHTING_STYLE_STARTS.md, the cartographer's), whatever
  arrives at the Stair Head from the north meets the camp from behind its tents. The dressing is
  laid out from the POI towards the Choir.

Water agent (playtest 5, "the world still feels empty between places"). `world/wildlife/`: one
streamed `Wildlife` node under the world. It reads the runtime maps (water and its level, the
shore's class, the region, the lie of the ground) in 128 m cells within 480 m of the eye, and puts
each kind where it lives:
- herons on reed, mud and shingle shores (Sedgemire most);
- ducks and swans on still water near a shore;
- gulls over open water and the sea;
- crows on open fields (the Vale);
- ravens high over Skerrow's crags and Cinderlea;
- fish rising as rings on still inland water.
The same flocks appear on every visit (seeded by cell). Nothing but gulls is put down inside a place.

Every kind is one MultiMesh built in code (140-420 triangles a bird) and posed by one vertex
shader from instance data: wingbeat phase and strength, wings open or folded, neck drawn in, legs
trailed. So a kind is one draw however many flocks there are, and there is no rig.

They react to the player. A heron walked up on flies off low to another stretch of shore. Ducks go
up together, circle, and come down on the water away from you. Swans paddle off without going up.
Crows go up off a field, wheel, and settle again.

The `wildlife` graphics setting (0 to 1.5; Low 0.5, Medium 0.75, High 1.0, Painted 1.25) sets how
many there are.

**Measured** on the batch-4 world at High, the same shots with the setting on and off: Hearthvale
street 990 vs 989 draws, 1.30 M primitives both; the Vale from a hill 803 vs 801; the Mere with
swans 202 vs 198; with ducks 181 vs 177. Under 0.01 M primitives in every shot. Counts round the
Sedgemire marsh at the default: 52 birds within 480 m (5 herons, 25 ducks, 2 swans, 29 gulls);
round the Mere's north shore, 57.

**Looked at** in captures: a heron in the Sedgemire reeds at 35 m, swans and ducks on the Mere at
45 m, crows on a Vale field, gulls wheeling off the Skerrow coast. Two things only the captures
showed, both fixed:
- a MultiMesh with custom data and no instance colours drew its vertex colours black on
  Compatibility, so every swan was a black swan;
- folded wings stood out behind the body as spikes.

`test_wildlife` (11) covers:
- the bodies' wing and neck marks;
- each kind where it lives;
- the same flocks twice;
- the setting;
- a heron, ducks, crows and swans walked up on;
- one draw a kind, culled by the ring round the eye.

**Forge work, agreed with the tree forge:**
- red deer, goats and roe deer on its quadruped rig (WM_Quadruped_v1);
- hare, fox and otter on a paw-and-spine rig, scheduled separately;
- a bind-pose LOD2 of each quadruped, with its legs, neck and tail marked in vertex colours, so far
  herds can be drawn the same way as the birds.

### Still short of the bar
- The Skerrow sea cliff's gulls and the ravens were not framed well in any capture.
- There are no birds on the wing at dusk yet, and no bats.

## Playtest 6's water, continued: the shore's wet band and swash, the swim camera's water, under the surface

Water agent, on the w4096d world, looked at from eye height and from a swimmer's eye (captures
in the scratchpad `water/pt6_after3`):
- **The swim camera's water was black.** In linear light the region's deep colour is all but black
  (#123239 is about 0.03), and from 0.35 m over the Lark Pool that was the whole lake under a dim
  mirror. From a low eye the water is now:
  - a true mirror: the Fresnel cap is lifted toward 0.95 under about 8 m;
  - clear by the length of the ray's path through it (`clarity_m`);
  - lit through from above in its shallows' colour.
  It is teal, gives back the far shore, and the sun's path shows. The view from a hill is unchanged
  (the cap still holds there).
- **Under the surface** (`UnderwaterView`, now a pass in 3D over the whole frame that reads the
  frame's depth): what is seen is murked toward the region's shallow water by its distance (9 m
  to two-thirds), lighter toward the surface. Looking up, the surface is a window of light straight
  overhead and a mirror of the water outside it. The Lark Pool reads as green water with its bed
  fading off, where it was a black screen.
- **The shore band** (`world/shore_band.gd`, `shore_band.gdshader`): a skin on the ground within
  150 m of the eye, 2 m grid, one mesh and one draw, rebuilt only when a 64 m cell comes or goes.
  It lies in the band from 0.3 m under the still water to 1.4 m over it, and draws on it:
  - the swash running up and drawing back, a wave at a time on the sea (0.3-0.6 m) and a breath on a
    lake (about 0.1 m), with a broken foam line at its edge;
  - the wet band above it, darker and glossier, drying toward its top;
  - both by the shore's class: long on sand, short with spray on rock, none on mud or in reeds.
  Seen at the Lark Pool, a subtle dark band borders the water. From 20 m on the Cinderlea strand
  the sea's surf lines read, but the band does not.
- **River banks on the coarse map** (the world builder's finding): see the bank check's commit.

`test_shore_band` checks that the band is found round the lakes and the sea (over 100 cells), lies
round the Lark Pool, and has every triangle touching its band. `test_river_banks_coarse` holds the
bank check to the 2 m heights.

### Still short of the bar
- The wet band and swash are subtle and were judged in stills only; the swash's motion wants a film
  or the user's eye. It is probably worth making the band darker on the sea.
- The surface seen from below, outside its window, is flat.

## Three swings brought up to the bar (player feel, 2026-09-26)

The three items the attack audit left short of the bar. Every hit window is where it was: `hit_start`,
`hit_end` and `cancel_ok` are unchanged on every clip, so the fights' timing is unchanged.

- **The rising cut's elbow.** Where the grip passes 30 cm from the shoulder, the hand reaches up
  and across, straight away from the elbow's pole. With the pole lying along the reach, the bend's
  plane was free to turn: the elbow swung 30 cm in one 120th (45 m/s), and 0.48 m in one baked
  frame (14.5 m/s at 30 fps).
  - `_solve_arm` now leans a flowing swing's pole out to the side as it comes into line with the
    reach (`POLE_LEAN`), so the elbow turns over through its outward side.
  - The rising cut's elbow now peaks at 11 m/s (9.9 at the baked frames). The two-handed chop's
    left elbow, the same case, went from 22.9 to 10.5, and the heavy's from 11.6 to 7.2. No swing's
    elbow is faster than before.
- **The greatsword heavy's lean-back.** A greatsword plays the two-handed heavy at 0.7 of its pace.
  Its wind-up ran to 0.48 of the clip, so it leaned back for 1.3 s and held for 0.2 s before the
  blow.
  - It gathers by 0.34 now (0.93 s at 0.7; the hammer's at 0.6, 1.02 s where it was 1.54), and
    holds, creeping, until the strike.
  - Its follow-through settles by 0.89. At 0.93 it whipped back to the guard at 31 m/s, faster
    than the blow itself (24). It now comes back at 20.
- **The lights' draw-back.** A cut reads as a blow when the strike is two or three times the draw.
  The tip's draw against its strike (m/s):
  - The sword's first cut: 28 against 40, now 19 against 44 (cocked at 0.26 and -40; it was 0.20
    and -46).
  - The backhand: 21 against 33, now 16 against 33 (cocked at 0.24; it was 0.19).
  - The two-handed chop: 22 against 28, now 14 against 30 (cocked at 0.29 and -38; it was 0.212
    and -44).
  - The two-handed sweep's return to the guard whipped at 34 m/s. Its follow-through settles by
    0.76 now (it was 0.82), and it comes back at 24.

**Checked.** The 13 melee clips were re-baked and transplanted onto the rig with the other 77 kept
byte for byte (clipdiff: 75 identical, the 13 differing). The dagger's, the fists' and the backstab's
elbows move by 1-17 cm where the pole now leans; their hands keep their places.
- The forge's tests pass (138), and so do test_attack_motion (every weapon's butt and pommel out
  of the body), test_attack_windows and test_enemy_attack_motion.
- `./run.sh fights`: 66 fights, 0 checks failed.

**Filmed** (`scratchpad/player-feel/polish_film/sheets`, 600 shots at a fixed 60 fps):
- `greatsword_heavy_side`: the blade goes up and back in 0.5 s, and is held laid back over the
  shoulder, creeping, for about a second, then comes down over the head. It had leaned back for
  1.3 s.
- `sword_chain_front`: the rising cut's elbow comes up beside the body, with no turn over the top.
  The first cut draws back over four frames, holds, and strikes from overhead to level in one.
- `greatsword_chain_side`: the chop draws back over seven frames, holds, and comes down over six.
- The spear's chain, the hammer's heavy, the raider's cleave and step-through, the backstab, the
  dagger and the fists were filmed too, and nothing in them is out of place.

**Found on the way.** A blow that landed as its hitbox opened could end the attack inside
`WeaponInstance.on_clip_event` and clear the swing's hit under it: `./run.sh fights` logged three to
five script errors a run, reading `current_hit.heavy` on null. It now keeps the swing's own hit, and
lights a heavy's trail only while the attack still stands.

* **The town stones** are now settlements' scene, res://world/pois/town_stone.tscn (77e093e5, in
  main as 87c30286). It cuts the place's name on both faces, replacing the milestone stand-in.
  signposts.json has been regenerated (the same 86 stones), and test_signposts passes 8.

### The after-build sweep, and Cinderlea's roads for a new character (2026-09-26)
* **`tools/world/atlas/after_build.sh`** is the sweep for right after the next 4096 build:
  - signposts.json against the built roads (rewritten if they moved);
  - the gap map and the road threats;
  - check_atlas and the hook table;
  - the POI plan remade on the new pads (`WORLD=` the build dir, for its full heights) and
    frame-checked, with the capture, signpost and gap-map tests;
  - with `--shoot`, through the gate, the 12 captures of `plans/after_signposts.json`.
  A dry run on w4096d: the checks are all clean, 57 tests passed, and the POI plan comes out
  unchanged.
* **Cinderlea's roads** (ATLAS §17): each road weighed by the foes within their own notice of it,
  where two roadside bandits weigh 1.0.
  - The new-game way (the Stair Head, the Choir, Pilgrim's Ash, Ashwell) weighs 0 except the
    Choir to Pilgrim's Ash, at 7.0. That is the Glass Bridge's wights, and the Glass Falls'
    bell-bearer 23 m off, inside its 28 m hearing.
  - The Bell Garden's bell-bearer stands 2 m off the Choir-Last Camp road.
  - Two country elites stand 24 m off roads.
  - Recommended: the Glass Falls' and the Bell Garden's bell-bearers stand 35 m back or `sit`,
    and the country's elites are kept their notice plus 10 m off the roads. The dead city is
    meant to be hard, and it is.

## The painted look: the Glass Falls and the Glassbed as black glass, and a heath test that walks on heath (2026-09-26)

All frames are Compatibility (llvmpipe) on w4096e, from `~/tools/wickmere-home/painted-look/`
(scratch; it does not survive). The plan is nine cameras on the two places at 16.5, 12 and 8.5–9.

**What it was.** The Glass Falls was a flat 7 m sheet streaked grey-blue. Its basin was a disc at
roughness 0.08, and Compatibility's sky reflection turned it pure white under a low eye (a
puddle, so water). The Glassbed was 38 grey slabs in a row, glinting like tin at noon.

**What it is.** One obsidian shader and one builder serve both (commit message for detail).
* The fall now reads as a pour that stopped. Seen from the front in the morning, when the sun
  reaches its NE face, its ropes carry sharp highlights and drips. In the afternoon it is in
  shadow and reads near-black, with only the cool sheen down its ropes. Its toes and the set
  pool are only visible from close (`falls_close`).
* The bed is a continuous, meandering dark ribbon with flow lines, ragged margins, and plates
  and shards along its edges. The ash-wights still stand under the arch.
* Four things were tried and dropped on the way. The sky reflection in the sun's colour drew
  brown wood at dusk. The rope and shell pattern at small scale on a flat bed read as wood grain
  with knots. Evenly spaced arcs read as a boardwalk. Crack lines filled with ash read as paving.
* Honestly: from the bank at 16.5 the ribbon's near margin still reads a little like a raised
  strip, because the valley floor there is flat to half a metre over 30 m and nothing sinks it.
  The plates' conchoidal rings are still a touch regular.
* Cost: +6 to +11 draw calls and +10 to 36 k primitives a shot.
* **Forward+ check (the user's):** the glass sets SPECULAR 0 and draws its own highlights and sky,
  so SSR and the radiance map should not add a mirror. Check that the pour is not too black in
  the afternoon shade, and that the sharp highlight (pow 700) does not sparkle or alias on the
  ribbon at distance.

Sheets: `before/contact_sheet.jpg`, `after/contact_sheet.jpg`, `pairs/contact_sheet.jpg` (before
and after, side by side).

**The heath test.** On w4096e `_find_slope` picked a 40° run at (-64, 3554) that a cliff slab of
the new kit stands 6 m up. It now waits for the near ring's solids and shape-casts each run at knee
and chest height against the world and scatter layers. On w4096e it found 5–30°, all jogged at 100%;
35° and 40° none within 260 m. `--filter=test_walking_the_heath` 2/2, `--filter=terrain` 16/16.

Tests: test_poi_kinds 28/28, test_pois 22/22. test_poi_encounters 18/19:
`test_the_watch_turns_only_while_its_condition_holds` ("up the stair, not at its foot") fails the
same with the old poi_builders.gd, so it is not this change. The brief's "the glass bed does bleed
damage" is not implemented, and was not before.

### Follow-ups (2026-09-26, later)

* **The Headless Watch's stair test.** It failed on w4096e because of the tilted pad (473f10e4),
  not because of the builder. The ground rises about 6% across the Watch (117.9 to 120.0 m over
  32 m, 119.0 m at its middle). The stair's foot, 11 m out, is about 0.9 m under the middle. The
  knight on the_stair stands at 120.17, 2.06 m up the stair but only 1.17 m over the middle, which
  the test used as the foot. The test now measures from the lowest ground under the Stair mesh.
  test_poi_encounters 19/19.
* **The Glassbed from above.** In the noon high shot its lines read as wooden planks. They now
  wander, gather and break, and broad swells carry wide highlights (`meander`, `swells`). The
  fracture shells are skipped where a material has none, which keeps the cost level.
  `bedpairs/contact_sheet.jpg` shows before and after: no plank grain from above, and broad gloss
  from the bank. The shell rings on the heaved plates are softer but still a little regular.

## The fighting-style starts: the frame, and the Warrior at Wardens' Rest (opening, 2026-09-26)

docs/FIGHTING_STYLE_STARTS.md steps 1 and 2. The frame (2decbc70, in main) makes a style data, a
page of the Naming and an opening of its own; the Warrior is the first style in the pack.

**The frame.**
- `core:style/*` (content/packs/core/styles/), checked by StyleDef: blurb, start, teacher, opening,
  tutorial, tie-in, mount, a kit with the hands it goes in, +1..5 skill bonuses, a picture.
  Progression.apply_style gives the kit, the skills and the sayings on top of the Calling, and the
  save carries `style` beside `calling`.
- The Naming has two pages when the pack has styles: *I. Who you are* and *II. How you fight*, a
  card each (the start town's picture, the teacher, the place) and the kit, the skills and the horse
  below. Be named writes `player_style`, `style_start` and `style_opening_due`, not `new_game`.
- Openings chooses what a new game begins with: the style's `core:opening/<style>`, else the
  fallback `core:opening/new_game`, which opens the Naming at `wake` as before. A style's start
  plays its own film (saves held only while it plays), starts its tutorial and has the teacher
  speak first. `new_game` is up only while the wake's film plays.
- The Naming begins with `down_the_stair`. StairDescent, laid on the stair the camp builds, counts
  its steps (530 on w4096e; the fortieth is 76 m along the road and 5 m below the head), drains the
  colour (Atmosphere.drain) and the sound (Music, SFX, Ambience, to -36 dB) as the body goes down,
  and at the fortieth plays the wake (GameServices.begin_wake): black, the body stood at the top,
  the opening film, and the Warden speaking first. Climbing back to the head gives it all back and
  the Warden says "Good"; the story waits, as the user chose.
- The Warden is "The Warden" to a styled character until the wake (`known_as`), is held at her fire
  from a new game's first frame, and has lines for the meeting, the shout, the refusal, a ridden
  road north and what went down. `the_cart` is `the_road_north`; a save on it or on the old `wake`
  loads on its own stage (QuestLog follows the stage id and `renamed`). The Toll Hums gives the cob
  only to a character with no horse (`if` effects, `has_mount`).
- New vocabulary: `act` objectives (EventBus.act_done: the body's blows, guards, rolls, lock-ons,
  casts, arrows, the descent), `say` effects (Barks: a line out loud with a name on it), `{key:x}`
  in text (the bound key), `start_quest` at a stage, `spots` on a quest (QuestSpots).

**The Warrior.**
- Wardens' Rest's drill yard moved out past the paved square into the widest wedge, so its three
  pells are in a row with room to cut. They are Pell bodies: struck, heard, counted, never felled;
  the middle one carries a straw man that jerks when hit. A roped ring of ten stakes is pegged out
  beside it, and Dole, Tam and the recruit have their places (NpcSpots).
- *First Blood*: the yard (three light blows, two heavy, a lock-on), the ring (Dole steps in as a
  foe with a slow, telegraphed arm, 0.95 s and 1.35 s wind-ups; take two blows on the shield, parry
  one, roll through two; beaten down you are knocked off your feet, helped up and told the one
  thing: Sparring), the boar on the down 160 m south, the Wynstead ditch's two bandits with Tam
  frozen on the verge (riposte and stagger offered, not required), and the report: Hollin, the
  Stair Head's pay and the Roll's new page. Dole has a line for each Calling from far away.
- *The Relief*: south to the Wellspring's Hearthstone halfway (the fast-travel lesson), the Glass
  Bridge (two ash-wights on the road where Tam waits; his letter: Fallowfold struck from a Roll in
  Tollmere), and the Stair Head, where the nameless Warden takes the pay, Tam walks past her fire
  and down to the 48th step, and she shouts. Tam is gone from the world after the wake.
- The film, *Wardens' Rest*: 39 s, four shots (the downs, the fort, the Wynstead road, down into
  the yard behind the recruit), in Dole's voice.

**Measured and looked at.** Tests: test_styles (13), test_start_warrior (10, four on the built world:
the yard's pells, ring and places; a warrior's new game standing at the recruit's place with the
kit in hand and Dole speaking first; the bout; the descent through the wake with Tam gone), and the
opening's own tests, all green. `./run.sh journey --style=core:style/warrior` (new) is 5/5: the
tutorial begins, Dole greets within 14 m, three light-attack presses on a pell close the first
lesson, the ditch stands its two bandits, Hollin is given. Looked at on Compatibility: the fort from
above (the old yard had room for one pell), the recruit's first view (three pells, the straw man,
the ring, Dole and Tam), the ring, the card's picture of the fort, the Naming's styles page, and the
film at mid-shot (the first road shot framed a hedge; moved in to the camp). Yard frames are
0.99-1.10 M primitives, 891-1050 draw calls.

### Not done
- The flow's New Game now picks a style card on the Naming's second page and does the first lesson
  on the keys (`--style=` chooses which); it was not run here (policy), so the final check runs it
  first. With a style in the pack the fallback start can no longer be reached from the title menu,
  only by a pack with no styles and by the tests.
- The straw man is primitives; the forge could make a real one.
- Forward+ lighting of the yard and the film is the user's to see.

## Playtest 09-27, items 10-14: interaction, the Hearthstones, the ring (2026-09-27)

From docs/TRIAGE_2026-09-27.md, the interaction and Hearthstones share.

- **#11, prompts that stuck.** The Interactor takes its prompt down, and the "[E] ..." toast that
  announced it, the moment the thing goes (picked up: its `tree_exiting`), a menu opens, the tree
  pauses, or the body leaves the world; the HUD blanks its prompt on `menu_opened` and takes the
  new body's prompt on a respawn or load. What a thing offers is read afresh every tick (a horse
  mounted, a door opened), and a thing with nothing to say is not offered. Nothing is offered
  while a menu is up. test_interactor_prompt_clears (new, 4).
- **#10, prompts only at one angle.** The Interactor is no longer a 2.6 m ray down the camera's
  view: a sphere query on the interaction layer (bodies and areas) within 2.75 m of a point a
  little below the chest, choosing the nearest and most in front (of the body or of the camera,
  whichever is better), nothing behind you unless touching, nothing through a wall (a ray on the
  world layer), and a margin of reach and of score for what is already offered so neighbours do
  not flicker. Its API is unchanged (`target`, `prompt`, `prompt_changed`, `target_changed`,
  `has_target`, `try_interact`, `update_aim`, `reach`); `player.tscn`'s node is a Node3D now.
  test_interactor_finds (new, 6): a knife at your feet, a person at your side, ahead before beside
  and the view choosing, too far and behind, a wall, no flicker.
- **#14, props without collision.** The Wardens' sparring ring is 4.8 m (was 3.4; 5.4 pushed it
  34 m off across the square at Wardens' Rest, 4.8 keeps it 11 m from the drill yard), fourteen
  stakes, each a body; the rope stays passable. The cheap audit (every builder function that draws
  fabric or commits a mesh with no collider near it) found the POIs covered and, in the settlement
  fabric, a sty's low walls, the drill yard's weapon rack and a non-Vale fort's pell posts drawn
  with nothing to stop you: bodies for each. test_settlements gains the ring's test.
- **#13, the Hearthstones' look.** A standing stone on a two-step seven-sided plinth of dressed
  blocks (the painted surface), a slab cut on the slant with a panel where the names are that
  warms when lit, and before it a bronze bowl: cold ash unlit, coals and a flame when lit
  (`assets/shaders/hearth_flame.gdshader`, a Y-billboarded tongue of fire with scrolling noise,
  additive), with the flickering light as before. Collision is the plinth, the slab and the bowl
  (still world | interact). Rest set-down moved to 1.4 m in front. Looked at once on
  Compatibility in a studio scene (lit and unlit side by side, and close to the lit bowl).
- **#12, fast travel.** Resting at a lit Hearthstone out in the country (pois.json) puts a
  conversation with the stone: every other lit stone, nearest first with its distance, and "Stay by
  the fire." Choosing one (the new dialogue effect `travel`) runs `Hearth.travel_to`: refused inside
  an interior or with a foe that has you within 40 m; fade to black with a loading line, set down at
  `PoiDressing.arrival_for(id)` facing the stone, the clock on by 0.25 h a km (at most 10 h), the
  place discovered, then the fade waits for the country as a load does (`UI.hold_for_the_country`).
  Nothing new is saved: the lit list already is, and where stones stand is the world's.
  test_fast_travel (new, 3).

Tests run (targeted): the new ones, test_interactor_in_a_conversation, test_interactables,
test_riding, test_talk_to_the_warden, test_settlements, test_start_warrior, test_hearth, test_pois,
test_night_lights, test_content_social: all green.

### Not done
- Fast travel from the map screen: only from the stones for now.
- The travel conversation comes up at every rest once a second stone is lit; if that grates, a
  "travel" prompt of its own on the stone would be the next step.
- The Hearthstone's look was judged in a studio scene, not at a real POI in the world.

## Combat from the 2026-09-27 playtest: heavies and rolls that play again, the ring's roll, flow, turns, parry (triage 4-9)

The combat half of docs/TRIAGE_2026-09-27.md, one commit each.

- **4 and 6, one cause** (46c0efbe). The state machine's edge from the legs into a one-shot did not
  reset the clip, so any clip played before went on from its last frame: every heavy after the first
  stood in its follow-through with the blade out in front for the whole swing, and every roll after
  the first slid along in the roll's last pose (the "dash"). The edge now resets
  (HumanoidModel._into_one_shot). The first play of a clip had also stood still through the fade,
  so its blow landed a tenth of a second after the timeline's; that is gone too. test_attack_motion
  no longer counts the first clip's cross-fade from the idle (a 2H swing's first two frames, half
  blended, carry a spear's butt into the chest; it passed before only because the clip was not
  moving). test_clips_play_again plays heavies and rolls three times over. An unlocked roll is
  always Dodge_F toward the way pressed; locked on, the four ways, as before.
- **5** (01d7b66d). A foe's blow going live at a target that is rolling, or 0.3 s out of a roll,
  within its reach, lunge and 2.5 m, is a dodge (Actor.count_dodge from Enemy._open_hitbox), once
  per blow; the i-frame path still counts, not twice. test_rolled_through.
- **7** (4b1223ae). At a swing's cancel_ok the next light (or a new chain after the last), a heavy,
  the feet (a direction held) or the guard come at once; they used to wait out the clip's last
  frames. An attack pressed since the swing began is kept for it, not only the last 0.25 s.
  test_attack_flow: each at 0.58 s of a sword light's 0.78 s.
- **9** (d63b2094). Parry window 0.18 -> 0.25 s (DESIGN and its tests follow); the block's press is
  read with the input in any state, so one pressed at the end of a swing or roll counts; a foe's
  melee blow glints on its weapon 0.4 s before it goes live (Impact.tell: pale to parry, red for an
  `unparryable` blow, dimmer with Less flashing). test_parry_tell.
- **8** (9fc4cd57). AttackTokens: a foe takes one of its target's two tokens to begin an attack
  (0.45 s apart; a boss is never kept waiting but holds one) and gives it back when the attack
  ends; a foe refused circles 1.2 m outside its reach with its guard up. test_attack_turns: three
  bandits, ten seconds, 9 attacks by all three, never more than two at once.

Tests run (targeted): test_clips_play_again, test_attack_motion, test_enemy_attack_motion,
test_impact, test_player_body, test_attack_windows, test_player_locomotion, test_combat_actor,
test_combat_abilities, test_combat_design, test_combat_damage, test_perks_do_what_they_say,
test_combat_brain, test_fights_found, test_combat_boss_fights, test_enemy_summons,
test_start_warrior, test_rolled_through, test_attack_flow, test_parry_tell, test_attack_turns: green.

### Not done
- Nothing was rendered: the tell's glint and the rolls are for the user's eye (Compatibility).
- `./run.sh fights` and the journey were not run (policy); the turns change how groups fight there.

## Playtest 09-27, items 15-17: the fences, the hedges, the towns' paving (2026-09-27)

No world build this pass: the builder's rules changed, and the same rules were swept over the
installed cells so the game has them now.

- **#16, random unconnected fences.** `tools/world/worldgen/linework.py` (`prune`) runs last in the
  build, after every sweep that cuts pieces out, and `tools/world/prune_lines.py` runs it over an
  installed world. It joins pieces into runs (ends within 1 m) and takes out a run that meets
  nothing at an open end (another line within 6 m, a settlement's pad within 30 m) if it is short:
  a hedge under 6 pieces, a wall under 5, a rail under 40 (about 95 m). A frontage's rail was meant
  to meet its field's boundary, and 103 of the 211 rail runs met nothing at either end: those were
  the "random" fences. And a gate post (or a Skerrow wall's end) with no line within 4 m goes: most
  stood on boundaries that were never hedged.
- **#17, hedges.** `prune` first thins the hedges: kept only within 460 m of a settlement's pad,
  never lying along a road within 24 m (a boundary crossing down to the lane still meets it), never
  within 75 m of a road's last 400 m into a place, never beside a wall or rail, and with an 8 m
  gateway every 34 m of straight stretch. `--plot` draws a box of country before and after from
  above: the walk from Merrowby by Strides Foot to Tollmere had a hedge down both sides of the road
  and one round every parcel; now it has none along the road and none in the open between Strides
  Foot and the city, and the fields by the villages keep theirs.
- Installed world, before -> after both: hedge 60,219 -> 11,827; rail 7,167 -> 4,707; gate posts and
  wall ends 2,945 -> 636; drystone wall 28,165 -> 26,130. The sweep is idempotent (a second run
  changes nothing).
- **#15, towns' paving clipping.** `game/tools_gd/paving_probe.tscn` raises every settlement on the
  real terrain and walks its made ground at 0.35 m against the terrain as drawn near (2 m vertices)
  and in the clipmap's outer rings (4, 8, 16 m). The pads are level, so almost all of it was clear;
  the terrain came through where the made ground ran out to a pad's lip and a 3 m patch bridged the
  bend: 0.38 m at Kharrow Hold, 0.30 m at Grandfather Hollow, 0.29 m at the West Walk, 0.06 m at
  Isseva. `Settlement._fit_quad` now looks under each patch (its corners, middle and the terrain's
  vertices; its edges too if those are not level), halves a patch short of its lift by more than
  1 cm down to 0.75 m, and raises what is still short, against the terrain as drawn at 2 m and 4 m.
  A garden's bed and its potato ridge are laid down the fall of the ground. After: nothing over the
  made ground at 2 m or 4 m in any settlement; raising a town costs what it did (Merrowby 1.16 s).
  test_made_ground (new, 2).

Tests run (targeted): test_line_work (new, 14), test_wall_runs, test_rows, test_offground, and
test_settlements, test_made_ground, test_scatter_solids, test_wayside: green.
test_roadside_planting's frontage test fails, as it does without these changes (roadside.py is
untouched).

### Not done
- The clipmap's far rings (8 and 16 m, a few hundred metres off) still put the ground over a pad's
  lip by up to 0.2 m at Grandfather Hollow and 2 m at Skarlow; made ground raised for those would
  float close up.
- The hedge rules were judged from above (plots), not in a render.
- The next world build applies all of it itself; until then the installed cells are the swept ones.

## The fighting-style starts: the Ranger at Fernhold (opening, 2026-09-26; finished 2026-09-27, triage 20)

The WIP of afe328ab (wip/opening), finished on the triage branch. What was written:



**Written.**
- `core:style/ranger` (bow in hand, 40 arrows, the hunting knife kept on quick key 4, +5 archery and
  sneak), `core:opening/ranger` (the line across Fernhold's common, facing the range at 240°),
  `core:mount/rosen_pony` (Nettle: the cob's forge body at 0.86 scale in a grey coat and an
  undyed cloth, through a new `look` on a mount def: Mount scales the model, HorseModel tints its
  coat and tack), the card picture (assets/ui/styles/ranger.jpg, the lodge's common with its well).
- *The Butts and the Briar* (quests/start_ranger.json): three butts (Pell kind `butt`, laid by
  QuestSpots from the quest's `props`) at about 20, 35 and 50 paces, found clear of trees and houses
  by a scratch search over the cells' scatter; the Briar walk (sneak, and Alder's count of the grey
  patches, which sets his own `seen_briar_grey`); a weaver in Fern Gully; the three thornhounds at
  Wold Force, with Rosen's Overwatch (she shoots only under 40% health, and says "I nearly
  didn't."); the report and the pony. Rosen and Alder have holds, greetings for each stage and each
  far Calling, and the lesson and report lines.
- *The Grey Hart*: the hart is a Leads lead (a new `leads` list on a quest: a PlaceholderBody hart,
  a new `hart` variant with antlers, tinted grey) that keeps 55 m ahead of the player by road
  (RoadRoute, a Dijkstra over roads.json with roads joined within 35 m: Wardens' Rest to the Stair
  Head 4.6 km, Fernhold 9.3, Gullhithe 7.4, Moreva 8.3), waits when they fall back, stands at the
  Stair Head, and walks down the stair to the 48th step on the Naming's down_the_stair. Stages:
  Alder's ask, follow to Grandfather Hollow, a thornhound pack stood on the Tamwick road, Ansel's
  Hedge Shrine's Hearthstone halfway, the Warden (her ranger lines) and the shout.
- New vocabulary: acts `sneak`, `swap` (a one-handed weapon on a quick key goes into the hand and
  back: Player.swap_to), `kindle` (a Pell kind `brazier` lit by a fire saying, for the mage);
  `{key:quick_4}` works (the key token takes digits now); plurals in kit words.

**Finished, measured and looked at (2026-09-27).**
- The film out of the trees. test_cinematic_paths_clear had been resolving every film's hand-over at the
  fallback opening (the Stair Head), so a style's last shot was judged 3 km from where it lands (and the
  warrior's yard "saw the edge of the world"); it now stands the body where the film's own opening does
  (PlayerSpawn.pose_for). Its scatter rule counted any camera within a tree's full spread as in it (a
  giant oak at 1.8 scale reaches 37 m), which ruled out the whole clearing; below a grown tree's crown
  (grow.py's crown base, by kind and age) only the trunk is in the way now. With that the title's
  Briarwold road passes too. The lodge shot came down under the crowns (5.5 to 5 m); the line now comes
  in from behind the body (45 to 60 degrees, 4.5 to 3.6 m) instead of swinging round it through the
  black ash east of the common, which the contact sheet showed as a black frame mid-shot.
- One Compatibility contact sheet of the film (the capture runner's cinematic plans take `opening` now,
  to stand the body at a style's start): the Wold over the canopy, the lodge and its well under the
  oaks, the force from 60-70 m with the falls through the leaves (out of the trees), the hand-over
  behind the body on the common. The re-routed line was checked against the scatter, not re-rendered.
- Tests: test_cinematic_paths_clear, test_start_ranger (7; the hart's road from Fernhold, 8.5-11 km, and
  down the stair, headless on the built world), test_start_warrior (10, after the triage merges: the
  wider ring, the roll and the parry), test_styles, test_content_db, test_content_social, test_riding,
  test_quest_walk, test_npc_appearance, test_cinematic_def: green. `./run.sh journey
  --style=core:style/ranger`: 4 of 4 (the first lesson, an arrow, is skipped by the journey), 0 errors.

### Not done
- The hart and a thornhound fight at Wold Force were not rendered; the hart's road is measured, not seen.
- The Mage and the Rogue went to two other agents part-written: branch wip/mage-rogue-starts (715cb7d7),
  whose commit message says what is there (a lockpick screen among it: lockpicking had no screen at all).

## The fighting-style starts: the Mage at Gullhithe and the Lamp (opening, 2026-09-27, triage 20)

docs/FIGHTING_STYLE_STARTS.md §3.3, §3.3a. Written by the opening agent on wip/mage-rogue-starts
(715cb7d7) and finished here; the Rogue in that commit (and its lock-picking) is the Rogue agent's.

**The Mage.**
- `core:style/mage`: the ash staff in hand, Kindle-Bolt, Mend and Ward known, +5 kindling and binding.
  A style's sayings go on the quick keys the belt leaves free (the flask keeps quick 1), the first
  readied (Player._ready_style_sayings). The card is the Lamp over the Mere (assets/ui/styles/mage.jpg).
- `core:opening/mage`: below the Lamp's door, the three braziers down the shore, Tamsin beside it.
- *Good Evening to the Stone* (quests/start_mage.json): the braziers (Pell `brazier`, QuestSpots
  `props`; the near one, then two more from 14 m: `kindle`); the racks (Jory's shingle as a Sparring
  bout `at` a spot, no ring; Ward said, the new `ward` act when a Ward takes a blow (Actor._apply_damage),
  Mend); the cold (Hush-Frost taught, two gutter drakes stood on the Lamp's shore); the boat (two
  smuggler-Sayers on the south shore, 72 m down the bank from the Lamp); the report: Kettle, the Wicks'
  cart-horse (the cob's body at a draught horse's size and coat), and the listening-bell.
- *The Note Under the Water*: hold the bell to your ear; round the Mere by the Eelweir and Sedgehithe to
  Stride's Foot; the bell's buyer at the fingerpost west of it; **the Wellspring's Hearthstone** past
  Ashwell (5.4 km of 7.4: Merrowby, the plan's stop, has no Hearthstone in the built world, and the
  Sedge Hearth at 1.1 km is too near home); the Warden, and the note, loudest down the stair.
- Tamsin has a greeting for each stage and for each far Calling (Cragborn, Wayfarer, Ashwalker,
  Reedborn; a Lantern-Clerk is from the same Mere and gets the plain one); Wren has the mage's meeting,
  down-the-stair and wake lines; the film *The Lamp* (37 s, four shots) is in Tamsin's voice.
- The Gullhithe Wreck's five drakes stand aside (`unless`) while either Mage quest runs: the road out
  passes 27 m from the hull, and the tutorial stands its own two.
- All four styles are offered now (the Rogue landed with StyleDef's `offered`, which held the Mage back
  until this was verified).

**Measured and looked at.** The Lamp's bluff on w4096: flat 18 m up for 45 m round the tower, a 35°
bank to shingle at 60 m, the water 85-90 m south; nothing grows within 25 m of the tower. Tests:
test_start_mage (12, incl. the Wellspring stage, the offered cards and the new game at the Lamp on the
built world), test_styles, test_naming_screen, test_cinematic_paths_clear: green.
Looked at on Compatibility: the card (the Lamp over the Mere; a crown hangs into its top corner), and one
contact sheet of the film, which moved two shots: the tower had a lime's crown across it (now from the
shore below the bank, 50-70 m south), and the landing's crane came down past the tower's trunk (the
start is 16 m from it; the landing now opens west of the body with the Lamp's foot, the three braziers
and the Mere, and comes in behind it). The last frames are the first view: the braziers down the bluff
and the water beyond.
`./run.sh journey --style=core:style/mage`: 5 of 5 (the tutorial begins, Tamsin speaks first a few
paces off, the near brazier lit by the body's own Kindle-Bolt on the key, the two smuggler-Sayers stood
at the Lamp, Kettle given and the tie-in begun), 0 errors. Tests after the Rogue's merge:
test_start_mage, test_styles, test_naming_screen, test_cinematic_paths_clear, test_content_db (50): green.

### Not done
- The ride south, the bell's buyer at Stride's Foot and the smuggler fight at dusk were not rendered;
  the ride is measured (7.4 km by road), not seen.
- The card has a crown hanging into its top-left corner and a dark window mark on the tower; kept.
- The listening-bell keeps its humming description after the wake (Wren and Tamsin say it is silent).

## People who live through their hour, and get round walls (triage 18, 2026-09-27)

"Many NPCs don't behave organically, get stuck, and repeat one animation in place." A headless
probe stood up Merrowby's out-of-doors people at 07:00 -> 10:00 and 16:00 -> 17:30 and watched
them for 25 s each. What it found:
- **Stuck.** There is no navigation mesh, so a walk is a straight line, and ScatterSolids.unstick
  only lets a body through trees. The grocer was stood up inside her stall (a stall's marker is the
  stall) and walked into it for all 25 s; a villager bound for the green and a guard going home
  pressed on house walls. A smith's forge marker was inside the forge.
- **One clip.** Nearly nobody names a work clip, so every worker hammered (a steward at her desk, a
  baker at her counter, a warden at her post), and each played its activity's loop unbroken, in step
  with everyone. A reaction or a talk was the last thing played: a waved-at smith stood idle for the
  rest of his hour, a cowerer cowered on (Cower loops), and after a conversation where the roster
  had nothing new to tell them (no marker) they went on saying Talk_1 to nobody. A villager who fled
  once ran everywhere for the rest of the day (`fleeing` was never cleared). Arriving dropped the
  entry's own clip.

The model's one-shot restart fix (wave 1) did not need repeating for NPC clips: their activity loops
go round (`_loops_until_stopped`), Sit/Sleep loop in their held state; the problem was on the NPC's
side (nothing asked again, `play_intent` refusing the same name twice).

Fixes (a53cb909, 23ee9bf4, c5921c26, aabd2db8):
- `Npc` watches a walk: less than 0.6 m in 1.6 s, or three windows sliding without getting nearer,
  and it steps along the face it is pressed to (collision normal), the same side each try, each
  detour DETOUR_M x tries; after five it gives the leg up (put at the target if the player is 35 m
  off, else the hour goes on where it stands). Destinations inside solids go to the nearest clear
  ground (`free_point_near`, a capsule query on world + scatter layers); a body stood up inside a
  house steps out. Arrival clears `fleeing`, keeps the entry clip; a traveller let go by the road
  steering near the end walks on to their marker.
- `Schedules.work_clip_for_spot`: with no clip named, the spot's words pick one (desk/office Read,
  kitchen/brew Work_Stir, garden/beds Work_Dig, clamps/wood Work_Chop, bench/rack/loom Interact,
  counter/stall/post Idle); Work_Hammer stays the last resort.
- `IdleLife` (new, pure): beats over the activity clip on a per-person seeded clock and tempo (work
  bouts 6-15 s and breathers with a look, a step or a drink; talk turns Talk_1/Talk_2 with listening
  and a laugh; standing broken by looks round, at the nearest person or the player, 1-2.6 m wanders,
  a reach across a counter). `Npc` eases its looks (<= 2.2 rad/s, the model's turn clips see it),
  advances its idle to a random phase at spawn, and returns to its day after reactions (clip length
  or 4.5 s for a loop) and `dialogue_ended`. Guards stand 2-6 s at each patrol point.

After: the probe's people changed clip 3-8 times in 25 s and turned 2-10 rad; one stuck window each
for two walkers (both got there).

Tests: test_npc_getting_round (a wall walked round, a stall destination moved beside it, a body out
of a house, a runner walks again), test_npc_life (bouts, turns, looks, differing clocks; a worker
back at work after a wave, a cower, a conversation), test_schedules (spot clips). Run: those plus
test_npc_actor, test_npc_registry, test_escorts, test_reactions, test_road_travellers: green. The
new body tests fail on the old npc.gd.

### Not done
- Nothing rendered; the look-turns and bouts are for the user's eye in a town.
- No navigation mesh: detours get round a house or a stall, not a maze of yards. A walk that gives
  up in sight of the player stands where it stopped until the next hour or tick moves it.
- NPCs still pass through each other (their mask leaves out the actor layers); wanders avoid landing
  within 0.9 m of somebody, walks do not.
- Interiors (NpcStreamer's indoor people) were not probed.

## Playtest 09-27, item 19: the regions' music rotates (2026-09-27)

"Each region's theme is good but gets too repetitive." Each region now has its theme and five
more pieces, and the director takes turns between them.

- **The pieces** (`tools/audio/compose.py` `VARIATIONS`, rendered by `gen_music.py` to
  `music/<region>/<variation>.ogg`, one mixed file each at OGG quality 3): `day_2` walking
  (x1.15, the progression reordered, the Toll halved and answered, eighth arpeggios), `day_3` an
  air (x0.85, two bars a chord, the Toll stretched and lower, a rolled harp), `night_1` after dark
  (x0.75, one shade darker in mode, a choir, the Toll low and seldom, bells like stars), `night_2`
  the small hours (x0.8, a glass chord high up, Toll fragments, one low held note) and `fight`
  (x1.5 within 84-128 bpm, ostinato, frame and war drums, the Toll halved, whole, turned over).
  Same tonic, instruments and motif as the theme. 30 files, 23 MB: music 42 MB -> 65 MB.
- **The rotation** (`music_director.gd`): by day the theme, `day_2`, `day_3`; by night the two
  night pieces. Entered by day a region opens on its theme, at night on a night piece. A piece
  plays at least two minutes (whole loops), fades in over 6 s and out over 10 s, then 70 % of the
  time 30-90 s of ambience alone, otherwise the next comes in under the fade. Never the same piece
  twice running. It holds indoors, in fights and under bosses, cues and the menu theme.
- **Fights** outdoors crossfade (equal power, on `combat_intensity / ENGAGED_LEVEL`) to the fight
  piece from its top, and back to the piece that was playing, where it was. Interiors are as
  before (the theme's deep mix; a fight is its combat stem). Skerrow and Cinderlea, deep by
  danger, now rotate too: the theme keeps its deep mix there when it is the piece.
- The content defs are `core:music/<region>_<variation>` with `for_region` and `role`; the audit
  has `day piece`, `night piece` and `fight` categories (all 30 clean; the only music flag is the
  opening cue's wrap, which was there before and is played once, not looped).

Tests run (targeted): tools/audio test_compose (4 new), test_audit, the music and stem render
tests; test_music_director (8 new: the rotation, no repeat, night pieces, the silence, the
crossfade into the next piece, a fight into the fight piece and back, a dangerous region's fight),
test_audio_wired, test_cinematic_player: green.

### Not done
- Heard by nobody: every piece is checked by measurement (loudness, peaks, seams, the modal and
  clash rules), not by ear.
- The theme itself was not re-rendered; the rotation reuses its stems as they were.

## Women in Wickmere: a woman's body, her faces, her clothes' fit, and the Naming's Body row (triage 21, 2026-09-27)

Every generic body the forge made was a man's, and `feminine` only changed a villager's height and
her chance of a dress; the Naming offered no body at all.

- **The forge.** `BODY_VARIANTS["woman"]` (`character_forge.py`) shapes the mesh with `feminine`
  and keeps the default rig's joints exactly (`MESH_ONLY`, `variant_skeleton`): `feminine` also
  moves the shoulders 18 mm in `joint_positions`, which would have made her a skeleton of her own
  like the child's. Same 31 bones, same inverse binds (test_women), 9 599 triangles, 1024 maps.
  The bust `body_scene` had (7.7 cm proud, two balls) is toned down (`bust_mass`) and the hips a
  little. Each face is built again as `<name>_f` (woman's jaw, brow, lips; the vault is the same,
  so every hair, hood and helm fits). About 5 min a head, 3 min the body, under the bpy shim.
- **The fit.** A garment fitted to her skin alone split over the bust: its chest triangles are a
  few centimetres across where the man's chest is flat. It is fitted to her body plus a drape
  across the bust (`body.garment_drape`, `cloth.fit_field`), as cloth hangs. `fit_parts.py` wrote
  the `woman` morph target into the 32 grown, skinned garments already built, pure Python, without
  rebuilding them under another Blender (`glb.set_morph_target`); `character_forge parts` fits it
  on every build from now on (`ALWAYS_FITTED`). clipcheck on her (Walk, Run) is at the man's level
  (tunic 6 vertices at 17 mm against his 4 at 10; gambeson 30 against 33).
- **The game.** `CharacterAppearance.is_woman()`, and `body_variant()` is `woman` at any grown
  build (the rig's girth widens her as it widens him); a child is a child's body either way.
  `HumanoidModel` wears the woman's body under clothes cut for her (`WEARABLE_BODIES`,
  `FITTED_BODIES`) and her cut of the chosen face (`head_to_wear`). A fitted garment keeps its
  detail further out (`FITTED_LOD_BIAS`): the importer's LODs were cut on the man, and at seven
  figures' distance her bust came through the tunic's coarse LOD.
- **NPCs.** `random()` takes a def's `feminine` before it rolls (npc.gd passes it, one line):
  laid over the finished roll, a named woman kept the beard and height of the man her seed made.
  Women roll a hand shorter (1.55-1.79 m) and long hair more often. 91 named NPCs given
  `feminine` from their bios and dialogue (the Merrowby placeholders, the dog and the generic
  guards left to the dice); a third of dressed foes (bandits, outlaws, knights) are women.
- **The Naming.** A Body row above Skin, *Woman* / *Man*, held buttons; the portrait follows,
  choosing a woman takes a man's beard off, presets and the lots keep the body (beardless and a
  hand shorter). `feminine` is in the saved record, so `_take_the_naming`, `worn_look` and every
  equip path, and every style's start, read it. The packs speak to the player as "you" and no
  gendered line about the player was found (greetings, rumours, dialogues, quests, titles).

Seen: a lineup of a man and six women (tunic, dress and cloak, coat and cape, reed wrap, kilt and
plaid, brigandine) front, three-quarter, side, back (`tools/forge/preview/looks/women.json`,
Compatibility under xvfb), and the Naming at 1280x720 (`--naming-tour=quick`, 47 checks passed).

Tests: `python3 tools/forge/tests/run.py --fast` 102, two failing that fail without this
(`test_total_weight`, 213 MB of world assets, which counts no characters; a sheep sidecar);
test_women (new, 7). Godot: test_humanoid_model (+4), test_naming_screen (+2), test_player_body
(+1, save and load), test_npc_appearance (+2), test_npc_actor, test_enemy_dress, test_content_db,
test_content_social: green.

### Not done
- No slight or heavy woman's body: the man's slight and heavy are not worn either (no garment
  carries their fit), and one body with the rig's girth covers the build as it does for him.
- No girl's body: a child is a child's body, told by her hair and dress.
- wip/characters rebuilds the heads (faces pass): when it lands, `parts --only feminine_heads`
  must be run again, and its skirt bones need the `woman` fit on any garment it rebuilds (it will
  get one: ALWAYS_FITTED).
- A man's tunic also shows skin at the waist through its coarse LOD at a distance (seen in the same
  lineup); FITTED_LOD_BIAS only covers fitted garments.
- New NPC defs must say `feminine` (test_every_named_person_says_whether_a_woman_or_a_man).

## The fighting-style starts: the Rogue at Moreva (opening, 2026-09-27, triage 20)

docs/FIGHTING_STYLE_STARTS.md §3.4 and §3.4a, step 5. Written on wip/mage-rogue-starts (715cb7d7) and
finished here, on top of the triage branch with the Ranger. The styles page offers the Warrior, the
Ranger and the Rogue; the Mage's def is in the pack with `offered: false` (StyleDef.all_styles skips
it) until its agent finishes it.

**The mechanics, checked first.**
- *Lockpicking did not work in play* (fixed on the WIP branch): nothing answered DoorLock's
  lockpick_started, and a locked chest opened only with its key. Now a shared step (Lockpicking),
  WorldContainer.attempt, EventBus.lockpick_requested and a lockpick screen (ui/inventory/lockpick_screen:
  a sweeping needle and a band, the band's width Sneak's), and a `pick_lock` act.
- *A crouched dagger from behind was only a backstab's x3.* The backstab took the light press before
  the sneak attack was asked, so a dagger's x6 (DamageModel `sneak_dagger`) could be struck from
  anywhere but behind, where a rogue strikes from. Crouched, behind something that has not noticed
  you, the backstab now carries the sneak crit, stays the committed, unblockable blow, and tells both
  lessons (`backstab`, `sneak_attack`). The rogue's sack of eels (Pell kind `sack`) can be backstabbed.
  Measured on the built world: a crouched blow from behind the collector's bravo, one-handed 20,
  sneak x6.0, 62 hp to 6.6.
- *The eye.* Stealth had every number and the player none: crouched in the dark and upright in
  plain sight looked the same from inside. The HUD now says, while crouched, what the most watchful
  foe or person within 40 m has of you, in the meter's own thresholds: Unseen, Noticed, Seen, Found.
- Detection was probed on the built world at the watch's post, 05:00 in mist, sneak 10: crouched 10 m
  in front of her, 0.44 after 4 s; upright 6 m, 1.00; 4 m behind her, upright, 0.00. The bravo in fog
  at 10:00: upright at 20 m, nothing (his sight is cut to 13 m); crouched at 6 m in front, found.
- Pickpocketing: the model (Stealth.pickpocket) resolves, moves goods and records the crime, and is
  tested, but nothing in play offers it to the player; it is not taught (below).

**The start.**
- `core:style/rogue` (an iron dagger in hand and six lockpicks, +5 sneak and one-handed), the card
  (assets/ui/styles/rogue.jpg, Moreva's stilt-houses by lamplight), `core:opening/rogue` (the landing's
  south boards 40 m out, facing the South Channel, before dawn), `core:mount/tithe_bay` (Tally, the
  bravo's bay with the Charter's brand), and the film *Moreva* (37 s in Sauve Mor's voice: the Delta,
  the landing, the channel, down over the roofs to the body; 05:00 to 05:24 in mist).
- *Once, From Behind* (quests/start_rogue.json):
  - *the traps*: crouch, and get past Tella Oul, the Reed Council's night-watch (new, a woman,
    npcs/start_rogue.json, with her own lines), to Sauve at the South Channel's traps. A stage's new
    `unseen` (NightWatch): when her meter reaches a witness's she calls out, Sauve says "Seen", his
    "The traps are up" waits, and you go back to the landing's edge and come again.
  - *the strongbox*: the collector's, a QuestSpots prop of kind `strongbox` (a locked WorldContainer the
    Tallymen own), on the lockpick screen. Sauve does not report the lesson (a personality's
    `crime_reaction` in his def); anybody else who sees it does.
  - *the dagger*: the sack of eels, which faces the landing, so its back is found by going round it.
  - *the bravo*: tithe-day in fog (a new `weather` effect), the collector's bravo walking his round of
    the landing (a kill objective's new `round`: QuestFoes stands the first foe on it, patrolling). He
    is `core:enemy/tithe_bravo`, the Brightwater bravo's hire for a season, 62 hp: a crouched dagger
    from behind ends him or nearly, face to face he parries and it goes badly.
  - *the report*: Tally, the page, and The Unsaid Page begun.
- *The Unsaid Page*: the courier a Leads lead dressed as core:npc/tithe_courier (always gone as a
  person), a field ahead by road out of the Delta and round the Mere; the Dodger's Stone's cutpurses;
  Merrowby, whose green he waits on while you turn east to the Hearthstone at Ansel's Hedge Shrine
  (Merrowby keeps no Hearthstone, which the Mage's agent found); the Warden ("Nobody I want to know, by
  the look of you"), the courier past her fire and down the stair, the Naming at down_the_stair.
- Sauve Mor: holds on the landing and at the traps, a greeting for each stage and for each far Calling
  (Cragborn, Hearthkeeper, Ashwalker, Wayfarer, Lantern-Clerk), the lesson, report and courier lines.
- Everything stood on the landing was moved onto open boards after a probe mapped Moreva at a metre:
  the old start and Sauve's place were inside a garden's fence, the strongbox against one; the start,
  Sauve, the traps, the watch, the strongbox, the sack and every leg of the bravo's round are checked
  clear by test_start_rogue on the built world.

**Measured and looked at.** test_start_rogue (11: the style, the lock and its screen, the sack and the
backstab, the bravo's sizing, the eye, the watch, the lessons, the report and the courier's road and
descent, a far Calling, and a rogue's new game on the built world with the watch at her post and the
bravo on his round), test_combat_design (the crouched dagger from behind, x6), test_cinematic_paths_clear
(the film's last shot had come through a willow), test_stealth, test_crime, test_styles, test_content_*,
test_quests, test_npc_appearance, test_start_warrior, test_start_ranger, test_naming_screen: green; the
warning census at its baseline. `./run.sh journey --style=core:style/rogue`: 5 of 5, 0 errors (the crouch
on the key, the bravo stood, Tally). Looked at on Compatibility: the card; the first view (dark before
dawn, a willow to the right, the channel ahead); the landing from the south in fog; a contact sheet of
the film (the delta, the roofs, the channel back to the houses, the body on the boards). The film's
times and its last shot's first key were changed after the sheet and checked against the scatter, not
re-rendered.

### Not done
- Pickpocketing is not taught and not offered: the doc's "the sleeping collector's key" needs a player
  path (a prompt on an unaware person's back, Stealth.pickpocket, a `pickpocket` act; the word is already
  in QuestLog.ACT_WORDS). The collector himself is not a person in the world yet.
- The ride was not ridden: the courier's road is measured (7-10.5 km) and the Stair Head meeting is
  tested as quest steps; the Dodger's Stone and the rest at Ansel's are not. Forward+ lighting is the user's.
- The watch turns a little on her post (she faced ESE, not the marker's ENE, in the probe); her look is
  still across the way down.

## The Naming fits the screen: Back, Be named and the style cards (triage 23, 2026-09-28)

**What was wrong.** Page I's right column was one stack: the title, the middle column and the
Callings, then the foot (Back, How you fight, Be named). The Body row made the middle column taller
than 720 lines allow, and the stack pushed the foot to y 697-749 on a 720-line screen: Back and Be
named half off it, and the words under the portrait with them. On page II every style card was a
fixed 192 px, and what is drawn on it (the picture's frame, the name, "town · teacher") needs more,
so each card's name and its town hung below the card, over the rule.

**What changed** (`game/ui/character/naming.gd`, layout only):
- the middle column sits in a ScrollContainer (vertical, follows focus); the foot is outside it, so
  it is always on the page. At 1280x720 the column needs 506 px and has 513: it does not scroll;
- "Start from / Cast lots" moved from the bottom of the middle column to under the portrait,
  below Face / Whole figure (a whole look at once, beside the look);
- the frame's inset above and below is 8 px, not 12;
- a style card's height follows what is drawn on it (`minimum_size_changed` of its inner column).
`_open_below` and every meta/text the flow and the tests find controls by are unchanged.

**Resolutions.** The project stretches canvas_items with aspect "expand" from 1280x720, so 1280x720,
1600x900, 1920x1080 and 2560x1440 are all laid out at 1280x720; 1366x768 is 1281x720; 16:10 and 4:3
add height, the ultrawides width. Settings' "Size of the UI" (0.8-1.4) is read only by the films'
subtitles, so it does not change this screen (worth knowing: it changes no menu at all).

**Measured.** `test_every_control_fits_the_screen_at_every_size` (test_naming_screen) lays the Naming
out in a SubViewport at 1280x720, 1281x720, 1280x800, 1280x960, 1720x720 and 2560x720, on both pages,
and asserts every visible Button, Label, LineEdit and slider is inside the screen and a card's words
inside their card; what is in a scroll area needs the area on screen, not squeezed, and no wider than
it; and the middle column needs no scrolling. It failed before the change (the foot, the blurb, all
eight card labels) and passes after. test_naming_screen and test_styles: 32/32. Looked at on
Compatibility (ui_review, both pages at 1280x720 and 1920x1080): everything in, nothing cut.

## Playtest 09-28, item 27: the towns' paving on the terrain's far rings (2026-09-28)

What still clipped, measured (`game/tools_gd/paving_probe.tscn`, now per view distance: a ring
counts only where the made ground is still drawn, 240 m and its fade from its middle, when the
terrain under it has come to that ring by Terrain3D's own geomorph bands; the rings past the first
taken with their quads split either way, since Terrain3D alternates the split there):
- The 16 m ring is never seen under paving (it starts past 420 m at Near, 620 m at Far). The 2 m
  Skarlow and 1.3 m Kharrow figures of the first pass were there and nowhere a player looks.
- The 8 m ring is seen: Kharrow Hold 0.93 m, Skarlow 0.83 m (Near only), Grandfather Hollow 0.36 m,
  and a few cm at Isseva, the West Walk, Ghastfell, Merrowby.
- The 4 m ring (seen from 105 m at Near, 155 m at Far) still clipped 0.62 m at Kharrow Hold on the
  split the first pass did not model, 0.07 m at Grandfather Hollow.
- Roads outside the pads and the pads themselves are painted into the terrain's own texture, so
  they cannot clip. Walls, plinths and joinery on a pad's lip go deeper into the far rings than
  into the near ground: Skarlow's drystone against its crag up to 4.4 m on the 4 m ring (an upper
  bound, both splits), Kharrow's 1.4 m and Grandfather Hollow's fence posts 0.6 m just off their
  pads. That is the clipmap against every object on a steep bank, not the paving; not changed.

The fix: each patch of made ground carries how far it must stand up on the 4, 8 and 16 m rings
(`Settlement._far_lift`: exact, at the patch's corners, where its edges cross the ring's grid
lines and diagonals, and the ring's vertices and quad middles inside it; zero at once where no
ring vertex round the patch is above it, which is almost everywhere). `FabricMesh.carry_lift` /
`quad_lifted` put that in the Paving and Earth meshes' UV/UV2, and painted_surface.gdshader's
`terrain_follow` lifts the patch by it over the same distance bands Terrain3D folds its rings in
(the global `wm_terrain_clipmap`: mesh_size and vertex spacing, from `World.share_clipmap`, kept
current by the view distance setting). Close up the lift is zero, so nothing floats; a few hundred
metres off the paving rides exactly as high as the terrain has come under it.

Probe, seen at Near/Far/Epic, before -> after: 4 m Kharrow 0.62 -> 0.00, Grandfather Hollow 0.07 ->
0.00; 8 m Kharrow 0.93 -> 0.00, Skarlow 0.83 -> 0.00, Grandfather Hollow 0.36 -> 0.00, every other
place -> 0.00 but Ashwell's garden beds (boxes, no lift) 0.03. Raising a town costs about what it
did (Merrowby 1.19 -> 1.30 s). Compatibility shots of Skarlow at Near view distance from 300 m,
230 m and 50 m: the setts lie on the pad, no ground through them, nothing floating.

Tests: test_made_ground (3, one new: a patch by a cut bank carries 0.7-0.8 m on the 8 m ring and
nothing on the level), test_settlements: green.

## People pass round each other, find the way round yards, and stay on a house's floor (triage 26, 2026-09-28)

"Fix NPC behaviour (and walking through each other)." The second pass on item 18. A probe was
written for it (`./run.sh npcs`, tools_gd/npc_probe.gd, headless at 60 ticks): Merrowby's people
watched 30 s after 07:00 -> 10:00, 12:00 -> 13:00 (half the town to the well) and 16:00 -> 17:30,
with the player standing in the middle, then Maud's bakehouse from the inside as her hour turns
from bed to the oven. What it found on the old code:
- Bodies overlapped (0.8 s and 4.5 s of pair-time closer than 0.5 m, 3 pairs each): the scene's mask
  left out the people and the player, so nothing but luck kept them apart.
- 6, 10 and 19 s stuck of walking (7 people in the evening window), with 2-6 walks unfinished.
- **Indoors, Maud stood at y -20 under a house whose floor is at 3000**: a body snapped to the
  terrain's height, which in the interiors' pocket is the ground a kilometre under it. And the
  streamer set every resident back on their room's middle every 0.75 s, so nobody indoors could take
  a step, and one whose hour sent them out walked for coordinates in the town from inside the walls.

What changed:
- **`NpcNav`** (new, systems/npc_life/npc_nav.gd): a navigation mesh per settlement when the player
  comes within 240 m of its pad, and per house the player goes into, baked on a worker thread
  (Recast, 0.15 m cells, a 0.3 m body). It is made from what a body cannot walk through as the
  physics space has it: the town is asked about in squares of 24 m a frame (world and scatter
  layers; the terrain's heightmap pieces are left out after the first square names them), every
  box, trunk, rock hull and house shell goes in as triangles, and the terrain's heights under the
  town (every 2 m, twelve rows a frame) are the ground. On a map of the people's own: a foe steers
  by the world's map whenever it has a region, and would have been routed to the nearest town.
  Taken down past 700 m.
- **`Npc` follows the way**: `_route` asks `NpcNav.path` on every new walk (corners walked in turn,
  then straight on where the mesh stops short, a spot on a deck). A spot on the mesh the way cannot
  reach (a yard with no gate) ends the walk at the nearest point, turned to the spot. Stuck on the
  way, the first try looks for it again from there; the old detours are the fallback. The
  NavigationAgent3D the scene carried (never used) is gone.
- **Passing people** (`_steer`): every person and the player in one list a tick; a walker bends off
  to the side that clears anybody it would come within 0.99 m of in the next 1.8 s (both to their
  right when square on), slowing close in front. The scene's mask now takes in the people and the
  player, so a walker slides round a body rather than through it, and nobody standing is steered or
  shoved. A walk held up by a person waits 0.8-1.8 s for them (up to 6 s a leg) before stepping round.
- **Set down clear of each other**: `make_room` (a spot's marker, the settle on it, the story's
  placing, the stand-up indoors, the roster's settle) moves a body out of walls and to 0.75 m from
  anybody; a shared spot's gather offset is used by NpcSpot and the roster's settle too (they put
  everyone on the well's middle). A walk whose end somebody already stands on ends up to 2.4 m short.
- **Give-ups**: one in sight stops, turns from any wall (`open_yaw`), lives its hour there, and tries
  the walk again in 15-30 s (three times; unseen by then, it is put there). A patrol goes on to its
  next point instead. Arriving at a marked spot turns to the marker's way (round to the middle of a
  shared one); with no marker, never into a wall.
- **Indoors**: a person stood up in a house is the house's (`Npc.indoors`): the floor holds them
  (gravity, not the terrain's height), their spot is the room for their hour (`NpcStreamer.room_spot`,
  now static), the streamer stands them up once, and when their hour is out of doors they walk to
  the Entrance and are taken down there (25 s at most). Out of doors again, a body left in a pocket
  is taken down and stood up in the town.

After (same probe; overlap s / pairs, stuck s, walks, arrivals, unfinished, facing a wall):

| window | before | after |
|---|---|---|
| 07:00 -> 10:00 | 0.80 / 3, 6, 26, 14, 2, 0 | 0.00 / 0, 2, 28, 14, 3, 0 |
| 12:00 -> 13:00 | 0.00 / 0, 10, 30, 24, 4, 0 | 0.00 / 0, 16, 33, 27, 2, 0 |
| 16:00 -> 17:30 | 4.48 / 3, 19, 25, 12, 6, 0 | 0.00 / 0, 1, 22, 13, 3, 1 |
| inside the bakehouse | Maud at y -20.1 (floor 3000) | on the floor (3000.0), out through the door at 03:00 |

No leg was given up short of its spot in either (the probe's "short"). The well window's stuck time
moves between runs (10-24 s over four runs after): it is people waiting their turn round a crowded
well, which the probe counts as stuck. The mesh: Merrowby 354 shapes, 21 227 triangles, 3 314
polygons, 3.7 ms in the worst frame on the main thread and 862 ms on the worker; the bakehouse 33
shapes, 1.5 ms and 21 ms. The people's own cost a tick could not be told from the noise of the
shared box (median physics tick with them 6.7-9.2 ms, with them switched off 3.5-7.7 ms, and the
same spread on the old code, 4.6-7.8 against 7.3-12.3); the steering is a list of ~25 bodies a tick
for each walker, the way one query a walk.

Tests: test_npc_passing (new: two walking at each other pass with room, a walker goes round
somebody standing without shoving them, two set down on one spot, the way into a yard round to its
gate on a baked mesh, a yard with no way in walked to its fence without a give-up, a give-up in
sight turns from the wall and walks again, somebody in a house stands on its floor). Run: those plus
test_npc_* (actor, appearance, registry, life, getting round, streamer), test_schedules, test_escorts,
test_road_travellers, test_reactions, test_start_warrior, test_roster_keeps_company,
test_interiors: green but for test_settlement_people's `tithe_courier` (the rogue start's courier
has no dialogue or place; it fails the same way on the code before this).

### Not done
- Nothing rendered: the passing and the turns are for the user's eye in a town.
- Scatter solids stand over ticks after their cells: a town baked the moment the player arrives
  from far off may miss a tree or a hedge that stood after it (SETTLE_MS is 1.5 s); unstick still
  lets people through trees.
- A town is baked whole (about a second on a worker); there is no rebake when something moves (a
  cart, a door), and a stall's goods on the counter are not solid, so the way goes round the stall.
- The well window is still the worst: a dozen people converge on one spot.

## Picking a pocket: the offer, the screen, being caught, and the Rogue's lesson (triage 25, 2026-09-28)

Stealth.pickpocket rolled, moved the goods and recorded the crime, and nothing in play called it; the
Rogue's start said so ("not taught, not offered; the collector is not a person in the world").

**How it works.**
- *The offer* (`systems/crime/pickpocketing.gd`, Pickpocketing.can_offer): crouched, at a living,
  non-hostile person whose awareness is under the meter's SUSPICIOUS (0.35), the prompt reads "Pick
  Bram Thatchen's pocket" and the interact key asks for the pickpocket screen instead of a talk or a
  trade (Npc.prompt_text and Npc.interact ask it: four lines in npc.gd). Children, dogs, followers,
  somebody fleeing or talking are not marks. The interactor is unchanged: it offers whatever the
  person's prompt says, nearest and in front.
- *Sleepers*: a person whose activity is sleep, or who is playing Sleep_Idle, sees nothing (one line in
  Npc._sense: hearing still works), is a fifth as aware as their meter says, and their pocket is 0.25
  easier (Stealth.pickpocket takes a `bonus`).
- *The pockets*: an Inventory ("Pockets") under the person, filled once from their def's `pockets`
  ({items, marks, table}) or a loot table (`core:loot/pockets_common`, or `pockets_merchant` with one
  light thing from the trader's own stock), kept with what was taken in the `pockets` save section,
  filled again after 72 h.
- *The screen* (`ui/inventory/pickpocket_screen`, menu `pickpocket`, EventBus.pickpocket_requested):
  the purse (all their marks, Stealth.PURSE) and each thing, with its chance and a Lift. The chance is
  Stealth.pickpocket_chance: Sneak, Light Fingers, the mark's awareness, the thing's worth, and now its
  weight (over 0.5 kg, 0.12 a kilo, at most 0.3); each thing already lifted in one go adds 0.08 to the
  mark's awareness. Sneak is practised on every try (there is no pickpocket skill; Sneak governs it).
- *Caught*: Stealth.pickpocket's crime (the mark always a witness, so a bounty follows the usual way),
  then the mark reacts by their personality's crime_reaction (confront, flee, or a hard look: Reactions'
  signal, line and clip), is wary of you for six hours (no offer), and the screen closes.
- *A success* tells the `pickpocket` act (EventBus.act_done, the item id as its detail); an act's
  `against` now reads a person's npc id.
- *Stolen goods* carry no flag in the bag: the crime system has none (a chest's theft is reported at
  close_up, not marked on the things), so the pocket is the same.

**The Rogue's lesson.** Brannock Tole, the Tallymen's collector (`core:npc/tithe_collector`, a man,
greedy/proud/cynical, his own few lines), sleeps on the south boards four paces from his strongbox
(quest spot `collector_doze`, on the bravo's round's clear leg) through the strongbox and dagger
lessons, and is gone otherwise (gone_when). His pocket holds his house key (`core:item/tithe_collector_key`)
and 18 marks. The strongbox stage has an optional `pickpocket` act against him ("He never woke.
That's the whole lesson."), its journal says so, and Sauve answers "And the collector's pocket?".
A new game's hand lifts either about half the time (the screen showed 29% and 31% awake-rules before the sleeper's bonus).

**Also:** test_settlement_people skips people the story keeps out of the world (`is_gone`: the tithe
courier, only a lead's body, and the collector) at noon and at three in the morning, and the courier
has a line of his own (he does not stop); those were its three failures since the Rogue landed. It
also left the NPC streamer switched off after its world went, and test_start_rogue run after it
found nobody on the landing: it switches it back on.

**Measured and looked at.** test_pickpocketing (8: the offer only crouched and unaware, the screen asked
for instead of a talk, the sleeper, the pockets and their chances kept across a new body, a lift and
its act and unwitnessed crime, caught: the witnessed crime, the confrontation and the wariness, the
screen closing on a fumble, the Rogue's lesson counting only the collector's pocket); test_start_rogue
(the collector asleep on his spot in the built world, his pocket offered crouched); test_stealth,
test_crime, test_economy_integration, test_perks_do_what_they_say, test_npc_actor, test_content_*,
test_settlement_people, test_dialogue*: green (178 together, after merging triage 26's NPC movement),
warnings at the baseline. `./run.sh journey --style=core:style/rogue`: 5 of 5, 0 errors. The screen on
Compatibility: the collector's purse and key with their chances.

### Not done
- A sleeping collector lies on open boards; the "stilt-house" of the doc is not an interior he is in.
- Nobody reacts to a pocket picked cleanly later (a mark who finds his purse gone).

## Women in Wickmere, again: her own face, her own hair, her own clothes (triage 22, 2026-09-28)

The second playtest: "woman" changed some body dimensions and nothing else; the face, the hair and
the clothes were a man's. Item 21 had given her a body, faces with a 7 % narrower jaw and a morph
on every garment. This pass makes each of them hers.

- **Faces.** `head_landmarks`, `_face_stations` and `head_scene` take `feminine` much further: the
  jaw 10 % narrower and its angle higher and softer, the chin smaller, set back and the lower face
  shorter (the chin's stations rise; the chin_z and every landmark above the cheekbones stay), the
  jaw bone and the masseter finer, the cheek's fullness carried up onto the apple, hardly a brow
  ridge and a flat glabella, the nose 17 % finer, shorter and a little raised, eyes 5 % larger,
  fuller lips, the neck 1 cm slighter (the body's too). The paint (`skin_paint(feminine=)`): finer,
  level, gently arched brows, a darker lash line running out past the outer corner and a lower
  lash line, rosier lips, colour higher on the cheek. The vault, the eye line and the brow line are
  the man's, so every hair, hood and helm fits (test_women checks it). The first cut had arched
  brows rising from the inner end and they read as a scowl in the engine; they are level now.
  There was no Adam's apple to take off: no head or body had one.
- **Hair.** Five new grooms in `cloth.HAIR_STYLES`: `long_loose` (to mid-back, 124 locks, fuller
  tips: `Groom.taper`), `shoulder`, `twin_braids` (combed to a braid behind each ear and laid
  forward over the shoulders along a path held off the body: `_laid_path`; combed, they slid back
  off them), `crown_braid` (a plait over the top from ear to ear, `_crown_arc`, and a low knot; a
  ring round the head read as a knitted cap's brim), `chignon` (a low knot). The women's styles
  bring the hairline a little lower at the brow and the temples. `_plait` is the plait itself,
  shared with the braid down the back. 4 200-6 000 triangles.
- **Clothes.** Five garments, built on the default body and fitted to hers like the rest:
  `kirtle` (fitted bodice, scooped neck, long close sleeves, waist drawn in, a full 13-fold skirt
  to the ankle), `bodice` (a linen shirt under a laced leather bodice with straps: the leather is a
  layer, tinted as the people's leather), `long_skirt` (clears a shirt's hem), `fitted_tunic`
  (drawn waist, flared to below the knee), `shawl` (a point behind, the ends crossed in a V in
  front). `_culture_outfit` dresses a woman: the Vale in the kirtle (45 %), the dress or the fitted
  tunic over trousers, a shawl as often as a cloak; the Clans in bodice, long skirt and plaid (the
  arisaid); the Lakefolk's coat over a long skirt; the Woodfolk's fitted tunic over the leg wraps; a
  Reedfolk shawl some days; the Ash-Pilgrims' robe is everyone's. The player is dressed through the
  same table, so every Calling's start and every style's start (styles carry no clothes) is in her
  cut; the pack's wool tunic, worn, is her fitted tunic (`cut_for_body`). Armour keeps its morph fit.
  A cut the forge has not built is worn as the man's it stands for (`WOMENS_CUTS`).
- **Body.** Her shoulder shelf 10 % narrower on the same joints, the ribcage 5 %, the waist in and
  the hips out a little more, slighter arms and wrists, hands and feet at 0.93 (`BODY_STYLES`).
  Every garment's `woman` target was fitted again (`fit_parts.py`). That turned up a fault in the
  fit itself: a sampled field is evaluated only inside each primitive's bounds, so 3 cm off the
  torso under the arm the body read 4.5 cm (the arm's distance), and on her narrower torso 13.6: the
  gambeson, the brigandine and the plaid were pulled in 9 cm there. `fit_field` now reads a true
  distance out to where a fit fades (`sdf.Scene.grid(reach=)`), and the base is measured the same
  way; the largest move over every garment is 39 mm. (Less `muscle` for her was tried and dropped:
  under 0.25 the body has no lats at all.) `glb.set_morph_target` writes over a sparse target (the
  exporter's).
- **The game.** `HAIR_STYLES` has all twelve, offered to everyone in the Naming ("Long and loose",
  "To the shoulder", "Two braids", "Plaited crown", "Low knot"); `WOMEN_HAIR` draws 17 in 20 from the
  new ones for villagers and the lots; `MEN_HAIR` is the old seven, so no man's dice moved. Each
  preset carries a `hair_woman`; choosing a body swaps the hair to the same kind of cut on the other
  (`HAIR_ACROSS`: the Naming's opening crop becomes long and loose). A woman foe gets a woman's cut
  of hair and her tunic.
- **Posture.** Not changed: the clips are shared, and turning her arms in would put her hands
  through a full skirt; a hip sway wants clips of its own.

Seen, Compatibility under xvfb: a numpy face lineup, men against women front and profile
(`facepreview.py <out> --lineup`), groom previews without Blender (`hairpreview.py`), the garments
in `garmenttest.py`, then in the engine four face pairs at portrait distance in four views
(`looks/women_faces.json --frame=face`) and a lineup of a man and seven women in their peoples'
cuts (`looks/women_outfits.json`). At the lineup's distance every woman reads as one.

Tests: forge `--fast` 110, the same two failing as before (`test_total_weight`, a sheep sidecar);
test_women +7 (her face's shape and paint, the vault unchanged, the crown on the head, the styles
and cuts listed and built, the game's style list the forge's). Godot: test_npc_appearance (+1),
test_naming_screen (+1), test_enemy_dress (a bandit that rolled a woman wears her tunic),
test_humanoid_model, test_player_body, test_npc_actor: green. test_inventory_equipment's quick-slot
test fails ("a sword is not a quick item"); nothing here touches it.

### Not done
- No new posture or gait for her (above).
- The shawl lies close but reads as a capelet at a distance more than a shawl; a fringe would help.
- The twin braids loop a little wide at the ears before they come forward.
- Named NPCs keep the dice's hair and cut: no def names a part, so all 64 named women are in them.
- The kirtle's skirt and the long skirt were not run through clipcheck in the Run and the Sprint
  (the robe's weights, which measured well, are theirs).

## The Size of the UI is the whole UI's, and fast travel is its own choice (triage 28 and 30, 2026-09-28)

**28, the "Size of the UI" (0.8-1.4) scaled only the films' subtitles.** It is now the root window's
`content_scale_factor` (`Settings.apply_ui_scale`, applied with the accessibility section, live).
The project stretches canvas_items from 1280x720 keeping the aspect ("expand"), so the factor
multiplies that stretch: every menu, the HUD, the Naming, conversations, toasts, the chart, the
prompts and the films' words grow together, and the 3D picture is untouched. At 1.4 a 1280x720
window lays its UI out on 914x514, and much of it had been written for 1280x720 exactly:
- `ui/lib/ui_fit.gd` (UiFit): `inset(frame, h, v)` narrows a page's margins with the canvas
  (full at 1280x720, 14/8 px at 914x514), `fit_height(scroll, frame)` lets a centred list grow
  until its panel would leave the canvas and then scroll, `narrow(node)` says the canvas is under
  1100 wide. Every full-page screen's fixed margins (journal, skills, sayings, save/load, chart,
  trade, benches, job board, books, settings, inventory) go through `inset`.
- Narrow layouts (chosen when a screen is built): the Naming puts the Callings under the look in
  one scroll, its page tabs under the title, the portrait at 290 px, and the style cards scroll
  with what they say; the inventory's worn slots scroll and its columns give up width; skills in
  three columns; sayings, benches and settings narrower columns, settings' notes wrap and its
  Controls grid is one column; the pause menu's entries scroll; the title's mark is smaller.
- The HUD follows the canvas (`_fit_to_canvas`, on the viewport's size_changed): narrow, the
  compass is 400 wide and the tracked quest sits under it, the first minutes' controls go over the
  bars, the subtitle over them, and the prompt is kept above the subtitle.
- The films' own subtitle scale is dropped (it would have squared); the slider applies a drag when
  it is let go (the handle would otherwise run from the pointer), a key or pad step at once.

`test_ui_fits_at_every_scale` (new, 6) lays the Naming (both pages), pause, all six settings tabs,
save/load, the title, inventory, five journal tabs, the chart, skills, sayings, a book, the three
benches, trade, the HUD and a conversation out at 0.8, 1.0 and 1.4 (1600x900, 1280x720, 914x514)
with the UI review's believable state, and asserts every visible Button, Label, RichTextLabel,
LineEdit and Range is on screen or in an on-screen scroll area not squeezed shut, the HUD's pieces
apart, and that the setting sets the window's factor. It failed on eleven screens before. Looked at
on Compatibility: `ui_review --ui-scale=1.4` (new argument), a 12-shot sheet at 1280x720 - all in,
nothing cut, the HUD clear of itself.

**30, fast travel.** Resting at a lit stone only rests (the travel conversation came up at every
rest once two were lit). While you stay by it (5 m), the stone then offers "Travel from the
Hearthstone" as its next use, which puts the road as before. And the chart (`ui/map/map_screen.gd`)
has "The road between the stones" beside it: every lit stone out in the country, nearest to where
you stand first, and a press closes the chart and takes the road from wherever you are. Both go
through `Hearth.travel_to` (fade, set-down, clock, the wait for the country), refused with the reason
said indoors, with a foe on you within 40 m, or (new) with more in the bag than you can carry
(`Inventory.is_overloaded`); on the chart the buttons grey and the reason is written above them.
The Warrior's Wellspring lesson is a rest and still completes. test_fast_travel 9 (new 6: rest then
the road, no road with one stone, indoors and overloaded, the Wellspring lesson, the chart's list,
refusal and journey, no road with nothing lit).

Tests run (targeted): test_ui_fits_at_every_scale, test_fast_travel, test_hearth, test_naming_screen,
test_inventory_screen, test_sayings, test_pad_layout, test_control_hints, test_cinematic_player,
test_waymarks, test_settings*: all green but `test_settings_graphics_screen`, which fails on
`title_vista` (a Graphics knob with no row on the tab), as it did before these changes.

### Not done
- A screen decides its narrow layout when it is built; one already open when the size changes keeps
  its layout (its margins and the pause list do follow). The settings screen itself is the case:
  change the size, and its tab re-lays out when you next pick a tab.
- The toasts (top right, 408 wide) cover more of a 914-wide canvas; on the Naming at 1.4 one lies
  over the title while it shows.
- A stone on the chart cannot be clicked to travel; the list beside it is the way.
- `test_settings_graphics_screen`: the `title_vista` knob needs a row in `GRAPHICS_GROUPS`.
