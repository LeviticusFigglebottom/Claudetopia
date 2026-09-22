# A candid assessment of Wickmere

Written by the person who built it, for somebody deciding whether it is worth continuing.
Everything measurable in here was measured today and is reproducible with the commands in
`README.md`. Where I am giving an opinion rather than a number I say so.

This is not a summary of `PROGRESS.md`. That file says what is done and what is missing.
This one says what I think it is actually worth, where it is weak, and what I got wrong.

---

## What it is, in numbers

| | |
|---|---|
| World | 8192 m square, 67 km², six regions, one seed, rebuilt deterministically in about 340 s |
| Content | 912 definitions: 236 items, 89 rumours, 76 NPC defs (68 named people), 64 dialogues, 48 POIs, 40 quests, 40 books, 34 places, 26 enemies, 25 interiors, 21 recipes, 15 sayings, 8 factions, 6 callings, 5 bosses |
| Interiors | 24 hand-built: 15 houses and 9 deep places, each generated from an authored recipe |
| Standing in the country | all 55 places and POIs dressed, 16 Hearthstones in the open, 3.47 M scatter instances |
| Assets | 311 forged meshes at 161 MB; two fonts and one terrain plugin are the only third-party files |
| Code | ~71k lines of GDScript, ~36k lines of Python tooling |
| Tests | 1226 unit tests, a 16-step scripted journey through the built world, a flow probe that presses the way in from the boot scene, a smoke run over every region and interior, and a perf probe |
| Frame cost | worst measured frame, a village street: **1470 draw calls** inside the 2000 budget, and **1.55 M primitives against a 1.5 M budget**. Next worst 1.23 M, median 0.68 M |
| Suite hygiene | 0 script errors, 0 freed-lambda captures, 0 duplicate-connection errors. All three were non-zero and unread for the whole of this project's life: 113, 171 and 27 a run |

## The one thing I would tell you before anything else

**Fifteen finished systems in this project had never once run.**

_Session three, 2026-09-22: it was not fifteen. A third pass found nine more, and the count
is not the point — the shape is. What follows is this project's original account of the
first fifteen; the nine are listed under "What the third pass found" below, and the reason
they keep coming is that every one of them was plausible from the outside._

Not broken. Not half-built. Complete, correct, covered by passing tests, and never called by
anything in the running game. The suite was green the entire time.

* `NpcRegistry.spawn()` had one caller and it was a unit test, so every village in the world
  was empty while its schedules ran, its dispositions changed and its guards watched for
  crimes that no bodies were there to commit.
* `Bounty.commit()` was reached by picking a lock and picking a pocket, and by neither of the
  two crimes a player is most likely to commit. You could take a man's strongbox and his life
  and no guard in the region would ever hear of it.
* `WorldContainer.take_all()` had no caller at all. Every chest, barrel and cupboard in eight
  kilometres of country was scenery.
* Nothing opened the trade screen, so thirteen shopkeepers were people you could only talk to.
* `HumanoidModel.apply_appearance()` was called by the character-creation screen and by
  nothing else, so every villager the world stood up was the naked rig.
* `WorldStreamer._first_mesh_of()` took the first mesh of a multi-mesh asset, so four hundred
  thousand trees were drawn as bare trunks with the canopies silently dropped — and three
  rounds of art review called that a colour problem.
* The animation tree's root was typed `GROUPED`, so every `travel()` was rejected outright,
  once per frame per walking actor, and the locomotion system had never succeeded at the
  thing it was written to do.
* 147 written greeting lines, 78 schedule entries and 65 rumours were unreachable in play.
* `teach_recipe` called a method `Crafting` has never had, so six craftable items had no way
  into a player's hands.

Nine was the count after the first day's sweep. A second pass with the same two questions
found six more, and there is no reason to think it is finished:

* **The belt.** `Equipment` binds a quick slot, counts what is in the bag behind it, uses it,
  saves it and tells the HUD; the HUD draws four slots and dims the empty ones. Both ends were
  shut. The inventory screen offers Equip only to things `is_equippable()` calls equippable —
  weapons and armour — so a potion got a Use button and nothing else, and at the other end the
  quick keys read a *second* `quick_slots` array on the Player that nothing filled. Four dim
  slots on screen read exactly like "you have nothing worth putting there".
* **Finding places by going to them.** `GameState.discover()` had two callers: a dialogue
  effect, and resting at a Hearthstone. You could walk the length of the country and arrive
  with blank paper. The `surveyed:<place>` flag the map reads for its much wider reveal was set
  by nothing outside the UI review's fake save, and the 90 authored `visible_from` sightlines
  that DESIGN §4 mandates were read by no code at all.
* **Work.** `JobBoard` and `JobStation` are complete, tested, self-placing nodes and **no file
  in the project outside their own two scripts and the tests ever named either class.** There
  was no notice post in any settlement and no bellows, mash tun or eel trap in eight kilometres
  of country.
* **Buying a house from the world.** `PropertySign` was placed by nothing; `deed_confirm.tscn`
  was opened by nothing; and the screen's own Take-the-key was a *second implementation* of
  buying a house that took the marks, set a flag `owns:<id>` that nothing else reads, and left
  `PropertyRegistry.owns()` saying no. The journey passed throughout, because it calls `buy()`
  directly — the one way in that a player cannot use.
* **Making things.** `station_screen.tscn` draws the forge, the alembic and the Name-table
  (DESIGN §5.8), `UI.MENUS` has had "crafting" registered from the start, and **nothing in the
  game ever called `UI.open("crafting")`**. Smithing, alchemy, enchanting and twenty-one
  recipes sat behind a door with no handle, because there was no forge, no still and no bench
  anywhere in eight kilometres of country that a player could walk up to. Enchanting was worse
  than unreachable: the Name-table is named in DESIGN, in the enchanting skill's own
  definition and in two item descriptions, and no interior in the world contained one.
* **Shopping.** `Merchant` is the whole of DESIGN §5.14 — region, stock, disposition, Speech,
  temper, what they deal in, what they can afford, and the Vale's refusal to serve the deeply
  Hollow. The trade screen was handed an npc id and went looking for *"any Inventory that is
  not the player's"*, so a shop opened against whatever bag was first in the scene tree at base
  value times a flat multiplier. `buy_price_of` had ten passing tests and no caller.

Every one was invisible because the fallback was plausible. A villager standing at their home
place instead of their work spot looks like a schedule. A bare trunk looks like winter. A
conversation that ends immediately looks like a terse NPC. **A green test suite tells you
nothing about whether anything is connected**, and this project is the clearest demonstration
of that I have seen. `tools/unwired.py` exists now to ask the question directly — *does
anything outside a test ever call this?* — as a counterpart to `tools/dead_data.py`, which
asks what the data promises that the code never reads. Run both before believing anything.

The six in the second pass sharpen the lesson rather than repeating it. Four of them were
found by a question narrower than "is this called?": **does anything place this in the world?**
A `JobBoard` is not a function you forget to call, it is a node nobody puts anywhere, and no
amount of reading `job_board.gd` tells you that. Two more were found by the opposite question —
*is there a second implementation of this?* The deed screen and the trade screen had each
quietly grown their own version of a system that already existed, and both versions passed
their own tests.

There is a third habit now, and it is the one I would insist on. **Write the test that presses
the button.** Every one of the six had a passing test of the function underneath the button,
and the button either did not exist or called something else. `test_inventory_screen.gd`,
`test_job_board_screen.gd`, `test_deed_screen.gd` and `test_trade_screen.gd` find the control
by the words on it, press it, and then ask the *system* — not the screen — whether anything
happened. They are slower and clumsier than calling the function directly and they are the only
kind of test that would have caught what was actually wrong.

If you continue this project, those are the habits to keep. Between them they found more real
defects in two days than any amount of additional test writing would have.

## What the third pass found

Nine more, and the two worst had been true since the day they were written.

* **The acceptance test had not been loadable since the day it grew a sixteenth step.** A
  commit added `await _step_make_something()` and never wrote the function: sixteen calls,
  fifteen definitions, which GDScript refuses at parse time, so the scene would not load at
  all. Its own message said "NOT YET VERIFIED BY A COMPLETE JOURNEY RUN", and then README and
  PROGRESS went on advertising that the journey passes every promise in the built world, and
  four later commits claimed a verification they could not have had. The step is written now
  and sixteen of sixteen pass.
* **Death had never cost anything.** The Echo is an `Area3D` spawned where you fell, and for
  the three seconds of the respawn delay your body is still lying on that spot — so it
  detected its own player and handed every mark back within a frame of your dying. This is
  the consequence the whole frame of the game rests on, and it had never once happened. It
  also explains the flake recorded here as unexplained: which of the journey's five conditions
  came back false depended only on whether a physics tick landed between two of its checks.
* **The Naming's choices never reached the body.** The screen kept its own vocabulary of
  swatch indices and a height key the record does not read, so the skin arrived as the text
  "1", the height was never applied, and with no clothing parts the preview was the naked rig
  whatever you chose. Nothing read the flags afterwards either, so the body at the Hushline
  Stair had no name, no look, and none of its Calling's three skill bonuses. And Continue,
  Load and `--load` all wrote a pending-slot flag that nothing read, so every one of them
  silently started a new character while the save sat untouched on disk.
* **The world ran behind an opaque rectangle.** Both menus fade to black before changing
  scene, the fade lives on an autoload that outlives the change, and nothing ever faded back
  in. A player saw black and concluded the game had not loaded. It had.
* **There were no Hearthstones in the open country at all** — only inside caves. A player
  walking the world had nowhere to rest or respawn.
* **Every faction line and every side quest could be started and none could be finished.**
  `QuestLog.choose()` could not answer an option written as an object, and every quest in the
  pack but one writes them that way.
* **The authored boss arena was placed by nothing**, so the fog gate the design promises
  never appeared in any fight. When it was finally loaded it turned out its fog plane was a
  collision shape handed to a mesh — it could never have drawn.
* **Tempering had no way in**, though the forge tab's own header advertised it.
* **Nothing that draws a point of interest would have loaded**, from a variable shadowed in a
  merge: each branch compiled alone, only the pair did not.

The lesson the original account draws is still the right one, and this pass sharpened it in
one place. **Four of the six diagnoses recorded in this file were wrong**, and the
measurements that disproved them were worth more than the fixes would have been. The cave
floors did not ripple from noise applied before flattening — they are flat to a millimetre
over five hundred cells, and the shells simply shipped without normals, so the engine was
flat-shading three hundred thousand facets a cave. The tunic sleeves are not too wide — they
sit two millimetres over their own design, and the garment that puffs is a padded jack, which
is what padding is. The country had no shadows not because the terrain refuses them but
because the sun stood between 60 and 94 degrees up at four regions' own review hours, putting
every shadow underneath the thing that cast it. And 145 errors a run blamed on eleven lambda
sites were one closure in the toast notification.

So: **before fixing what this file tells you is broken, measure it.** The file has been wrong
four times out of six, and it is the most careful document in the project.

## What is genuinely good

**The world generates and it is coherent.** Heights, rivers, roads, region masks, settlement
pads, field enclosures, scatter and encounters all come out of one deterministic pipeline from
one seed. The most convincing evidence is something nobody engineered: when the Hearthvale
escarpment was added, Merrowby, Warden's Rest, Pennywort's Mill and the Cracked Toll all
turned out to be in the vale beneath it at 18–30 m, and Tamwick, Hollin Barrow and the Chalk
Hound on the tops at 100–121 m. Nobody placed them. The pads landed where the places already
were and the land arrived underneath them.

**The content is specific and it is written, not generated.** Hallam Ashdown "shoes horses,
mends ploughs, and has made exactly one sword, which he keeps under the bed and does not
discuss", and the way to learn the bell-bronze pattern is to get him to take it out from under
there — after which the village knows, because Bessa's boy carries to the forge on a Tollday
and could not hold water. That is content that knows about itself. The four cosmologies in
`WORLD_BIBLE.md` contradict each other on purpose and the books argue with each other in
their own voices.

**The interiors answer "who was here, and what happened?"** Each is generated from a recipe
naming a resident, a trade, a wealth, a household and their habits, and each habit becomes
specific evidence on the floor. Twenty-four of them, each with a `unique_object` no other
interior shares, enforced by a test.

**The forge is honest.** Every mesh, texture, character, animation and sound is generated by
this project. When the trees looked wrong, the answer was not to buy better trees; it was to
find that all fifteen species tables set `attractUp` negative and pulled their branches
downward. One fault stated once and repeated fifteen times, and it is fixed at the source.

**The art review loop works, when it is used properly.** Every significant visual finding
today came from rendering the thing and looking at it — the naked villagers, the grey village,
the roof slabs tilted into open wings, the leg-of-mutton sleeves, the 434 white monoliths on
the downs, the camera inside a hawthorn. None of them would have been caught by a metric, and
two of them were caught *against* a metric that said the geometry was fine.

The sharpest statement of this came from the person who built the forge, about their own work,
and it is worth quoting: **the forge had no bug that a careful reading would have caught, and
none that a screenshot did not.** Their four were a two-mesh asset handed to a one-mesh API,
`attractUp` set negative in all fifteen species tables, a bark feature size fixed at one metre,
and a rock noise scale that divided by radius so that larger rocks got finer noise. Every one
is defensible line by line and obvious the moment it is drawn.

There is a corollary worth keeping. When I named that pattern to them — a constant that is
right at ordinary scale and hopeless past it — they did not agree with me, they went and
audited all 43 material builders and found fourteen more instances, four of them barks they had
already fixed for one hero asset and left everywhere else. Naming a class of fault is only
useful if somebody then goes looking for the rest of the class.

## What is weak, or absent

**~~The settlements are built but not planned, and one of them is over budget.~~** The
draw-call half is answered. `Building` raised every wall, roof slope, gable, ridge, chimney,
door part and window part as its own instance and drew each once for the eye and twice more
for the sun's cascades: 1093 of the street's 2438 draws, with 1535 of the total being shadow
passes. A house is four merged meshes now and a whole settlement's filler fabric is four
more, and the same frame is 1470 draws — and the filler houses gained plinths, gables,
overhanging eaves, chimneys, lintels and shuttered windows on the way, at no draw cost.
**The frame is now over the *primitive* budget instead**, at 1.55 M against 1.5 M, from the
hedge and orchard trees the cover pass planted; nothing else in the 42-shot sheet exceeds
either budget. The streets themselves are still rings around a green rather than planned.

**The drop test still fails, and one axis went backwards.** Colour now separates the six
regions at 0.74 and the two axes together at 0.71, against a 0.80 bar — both better than the
0.64 and 0.55 recorded below. The landform axis went **0.21 to 0.12**, under the 0.17 chance
line, and the reason is understood rather than guessed: ground cover was added at roughly
equal density to all six regions, which makes the bottom of every frame equally busy, and
that is exactly what the axis measures. The next lever is cover that differs in *structure*
between regions, not in tint. That sheet was also shot without the 55 dressed points of
interest, which are the towers, bridges and stone settings the landform axis most needs.

The paragraph below is the previous sheet's reading, kept because its reasoning about what a
single number can and cannot separate is still the right reasoning. That is worth exactly one
cheer and no more: three things changed between the two sheets at once — the Hearthvale
escarpment, six shots a region instead of three, and a rewritten metric — and one number cannot
separate them. What can be said is that 0.06 measured the photographer and 0.21 measures the
country. It is also the first sheet that will *reproduce*: two salted Python string hashes were
making the landmark facings and the ground shots different on every build, so no two earlier
sheets were ever comparable with each other.

**There is no combat feel.** Every mechanism in DESIGN §5 exists and is tested — stamina,
poise, i-frames, parry windows, hitstop, lock-on. Whether any of it is *satisfying* is
unknown, because nobody has played it with hands on a controller. The journey proves a
Thornhound takes 11 damage. It cannot tell you whether swinging feels like anything.

**The characters are a pass and a half, not two.** Faces, bodies, hands, garments and six
distinguishable culture silhouettes all landed today, and the honest weak list from the person
who built them is: the bald cranium is still an egg, tunic sleeves are wider than the forearm
under them, the shoulder cape reads as a lampshade, and the plate breastplate stops at the
collarbone with bare shoulders above it. The 70 animation clips were not re-tuned against the
new proportions, so hand-to-prop contacts may have drifted.

**Struck from that list since: the sleeves.** Measured as the distance from every sleeve
vertex to the body surface under it, the tunic's median standoff is 19 mm at the shoulder,
14 at the upper arm and 13 at the forearm, against its own design of 11 (3 gap, 8 cloth).
It is the closest-fitting sleeved garment in the set. What reads as a leg-of-mutton sleeve
in a character lineup is the **gambeson**, at 31-38 mm, which is a padded jack and is meant
to be; half the presets in that render wear one. The numbers for all five sleeved garments
are in `lib/cloth.torso_region`'s docstring, so the next person to look at a lineup and
reach for the sleeve width finds the measurement first.

**Balance is uncalibrated, and now at least it is measured.** There has still never been a
playthrough, so there is no pacing data and no idea whether a fight is fun. But the numbers
themselves are data and the formulas are three static functions, so `tools/balance.py` reads
the curves out of the pack. Three things are out of shape and it says so itself:
**Brightwater is safer than Hearthvale** (13.1 hits to kill you against 6.9) though the world
puts it second; **Sedgemire pays less than either** at 19 marks a fight while being more
dangerous than both; and **flat armour takes the light/heavy choice away in late fights** —
against the Stone-Thrall King's 30 armour a mid-gear light attack does not get through at all
and is clamped to the 1-point minimum, 1600 hits against 67 for a charged heavy. The rest
reads healthy: the worst single hit rises evenly from 30% of your health to 58% across the six
regions, and a boss with late gear is 7 to 34 heavy hits. Nothing has been retuned on the
strength of this, because changing balance without playing is how a considered guess becomes a
worse one.

**Audio is indexed, not judged.** Six region themes, seven stingers, 43 ambience entries and
70 foley ids exist and load. Nobody has listened to them in the world.

**One test flakes and I cannot explain it.** The journey's death step failed once in five runs
and once independently on a loaded machine. It now names which of its five conditions broke
and waits two frames at each settling point, which has held since. That is not a diagnosis and
`PROGRESS.md` records it as unexplained rather than fixed.

## What I got wrong

I am listing these because a reviewer should know how much to trust the judgement in the rest
of this document.

* **I called the horizon artefact a water plane.** It was a hard step in the sky shader at
  `EYEDIR.y == 0`. The world stream disproved my guess with controls — disabling the water,
  switching the terrain background, varying the clipmap — and then painted one branch of the
  sky shader magenta and watched the bar turn magenta.
* **I told a stream the roads did not reach the settlement centres.** They measured; every
  settlement has one to four road polylines with a vertex at 0.0 m from its centre. I had
  inferred it from an aerial and handed it over as a fact.
* **I asked for the tree colour to be fixed, three times.** The trees were not being drawn.
* **I asked for blue in the snow's shadow.** The snow texture already had it; the fault was
  that ambient light in shadow was not tinted by the sky. Taking my note at face value would
  have cost a pass repainting a correct texture.
* **My alias table put ten-metre white towers across the downs.** I mapped `chalk_boulder`
  onto `cliff_slab` by reasoning about what the two names mean, without looking at the shape
  the forge builds, which is a 6.5 m upright slab.
* **I wrote a landform metric that measured the camera.** It included the absolute horizon
  height and the sky fraction, so moving the review camera from 48 m to eye height moved the
  score by a factor of eight.
* **I shipped a landmark placement system without checking the set it places was complete.**
  A region's landmark shot was pointed at an empty tidal flat for a day.

The pattern is consistent: **every one of these was me reasoning from a description instead of
going and looking at the thing.** The streams that disagreed with me were right every time
they did, and the project is better for their having pushed back rather than complied.

## If you continue it

In the order I would do them.

1. **Play it.** Nothing in this document can tell you whether the game is any good, because
   nobody has held a controller. Everything below is guessing until that happens.
2. **Close the drop test, and give the landform axis structure rather than density.** Colour
   is at 0.74 and the pair at 0.71 against a 0.80 bar. Landform is at 0.12, under chance,
   because uniform near-field cover makes every frame's foreground alike — so the question is
   what makes the *shape* of one region's ground differ from another's. Re-shoot with the
   dressed points of interest standing, which the last sheet did not have.
3. **Plan the settlements.** Streets rather than rings; the mechanism is there and the roads
   now cross the pads. And bring the street's 1.55 M primitives back under 1.5 M.
4. **Calibrate.** One playthrough with instrumentation gives you the economy curve, the
   difficulty curve and the pacing, and every guessed number in the content becomes a tuned one.
5. **Keep running `unwired.py` and `dead_data.py`, and keep asking the third question.** The
   two tools ask what is never called and what the data promises that nothing reads. The third
   is *what does nothing place in the world?* — it found four of the last six, because a node
   nobody instantiates is invisible to both tools. A fourth is narrower still and found the
   worst of them: *what is registered in `UI.MENUS` that nothing ever opens?* Fifteen dead
   systems in two days, and no reason to believe the list is finished.

## The honest summary

This is a large, coherent, entirely original world with a great deal of specific writing in it,
a generation pipeline that produces a landscape whose settlements sit where the land says they
should, and every system in the design document implemented and tested. It is also a project in
which twenty-four of those systems had never once executed — fifteen found over two days by
two people asking the same question, and nine more in a third pass, including the acceptance
test that had not been loadable for days while four commits claimed it passed, and the death
mechanic the whole frame of the game rests on, which returned your marks within a frame of
your dying. That should tell you how much of "it is implemented" is worth without somebody
going and looking. It should also tell you what to do with this document: four of its six
diagnoses were wrong when they were finally measured.

What it is not yet is a game anybody has played. The systems are wired together now and the
world is populated and the country reads as country. Whether it is any good is a question the
next person has to answer with their hands, and I would not trust anybody — including me — who
told you the answer from here.
