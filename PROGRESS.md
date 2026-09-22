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

Colour and the two together moved a long way and the test still fails, on both bars. (Measured before the last change of the pass: Cinderlea's sun was raised from 3.2 degrees to 9.2 at its own hour afterwards, because at 3.2 the energy curve had already halved it and the region's ground shots came back nearly black. That is a change to one region's light which these numbers do not include.) The
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
