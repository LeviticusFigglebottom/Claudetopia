# Fighting-style starts: the plan

A plan for the user's approval, not code. It carries out DECISIONS 2026-09-25, "A new game
starts with a fighting style's own intro; the Hushline comes after". DESIGN §5.1 and §5.1a will be
rewritten from it once it is approved. Sources:
- DESIGN §5.1 and §5.1a;
- WORLD_BIBLE §1.5, §3, §4 and §6;
- docs/ATLAS.md (settlements and roads);
- `core:quest/the_naming` in quests/main.json, and `core:opening/new_game` in opening.json;
- the NPC defs of the four teachers, who already live where their starts are;
- the opening agent's notes on its own code, folded into §4, §5.2, §5.3, §5.5 and §5.6.

## 1. The shape of a new game

```
character creation (the Naming): name, looks, Calling, and now a fighting style
      |
      v
the style's start town  --  a 10-15 minute tutorial in that way of fighting, ending in a first
      |                     real fight that feels like it; the teacher hands over a horse
      v
the style's tie-in quest  --  a thread that leads south to the Stair Head. The player may leave it
      |                     and explore; the main quest waits for them at the Stair.
      v
the Stair Head  --  the character sees something go down the Hushline Stair and follows it into
      |             the mist. Around the fortieth step the colour goes, the picture fades to grey,
      |             and the opening cinematic plays: "{name}. There. Said out loud, and heard."
      v
the Naming as it is now, from the wake: Wren at her fire, the waystones to the Choir, three
ash-wights, the Hearthstone at Pilgrim's Ash, then (new) ride to Merrowby on your own horse
      |
      v
The Toll Hums, and the rest of the main thread as written
```

## 2. The premise, rewritten so it still holds

WORLD_BIBLE §1.5: "The Hushline is where it has finished ... The player came out of it, which
should be impossible." The one shared start had the player come up the Stair with no past. The
style starts give the player a past, a town, a teacher and a horse, so the premise becomes:

> **You went down into the Hush after something, and you came back up.** Nobody who goes down
> comes back. Wren has stood at the top of the stair for nineteen years and watched grey people
> walk down it. "Nobody has ever walked up it. Then, this morning, you did."

The design truth is kept, and it is sharper than before:
- the player did the impossible thing, and saw themselves do it;
- the Hush cost them something: the colour went from their hands, and their name thinned until
  Wren said it back;
- each start leaves one thing down there, the recruit, the hart, the courier or the note, and
  that thing is a thread the later game can pick up (§3, "What stays down there").

The opening cinematic keeps its words, its shots and its music (`core:cinematic/opening`,
`core:music/opening`). Only when it plays changes: at the wake, not at New Game. Its first line
fits better than it did, because the player now has a name the Hush was taking and Wren gives it
back. Its last line is the payoff of the descent.

## 3. The four starts

| Style | Start | Province (atlas xz) | Teacher | First real fight | Horse | Road to the Stair Head |
|---|---|---|---|---|---|---|
| Warrior | Wardens' Rest | the West Downs (-700, 1640) | Sergeant Dole | the Wynstead ditch bandits | Hollin, the Wardens' cob | 4.3 km (2.2 straight) |
| Ranger | Fernhold | the High Wold (3350, 230) | Rosen Wyke | a thornhound pack at Wold Force | Rosen's forest pony | 8.7 km (4.8) |
| Mage | Gullhithe and the Lamp | the Mere's north shore (-1300, -960) | Tamsin Wick, Keeper of the Lamp | smuggler-Sayers come for the sul-stone | the Wicks' cart-horse | 7.2 km (4.8) |
| Rogue | Moreva | the Delta (-2790, -1000) | Sauve Mor | the Tallymen's bravo, from behind | the bravo's own horse | 8.0 km (5.4) |

The four are in four regions (Hearthvale, the Briarwold, Brightwater, Sedgemire). None is in
Cinderlea, which is where they all end up, and none uses a main-quest place (Merrowby, Tollmere,
Grandfather Hollow, Isseva) as a tutorial ground, so the main thread still arrives somewhere new.
Every teacher already exists as an NPC who lives in their start town. Every enemy used exists.
Each start ends with a signed road south: the fingerposts (ATLAS §18) name the next place the
whole way.

### 3.1 Warrior: Wardens' Rest

**Why here.**
- The Wardens of the Hearth are the militia. Their fort on the West Downs is where recruits learn
  the shield and the sword.
- The Wardens' cob, Hollin, is theirs to give.
- Wren Tallow is a Warden, so the warrior's road to her is the Wardens' own business.
- It is the nearest start to the Stair: 4.3 km by road, by Merrowby, Wynstead, Ashwell and
  Pilgrim's Ash.

**The teacher.** Sergeant Dole (`core:npc/wardens_dole`: brave, cynical, proud). He drills
recruits in the fort's yard and says each thing once. His voice is short and dry. He counts, and
he is kind only by accident:

> "Shield up. Up. That is your roof. Nobody fights in the rain without a roof."
> "You swung twice. The bandit swung once and meant it. Mean it."
> "Good. Now do it tired."

**The tutorial (about 12 minutes).**
1. *The yard (3 min).* Dole's pells and a straw man:
   - the light swing, then the heavy (charged) swing;
   - stamina, and why the heavy costs it;
   - lock-on.
   A second recruit, Tam Hobb, drills beside you. Tam matters in the tie-in.
2. *The ring (3 min).* Dole spars with a blunt blade and teaches:
   - the block, on its own;
   - the parry window, which he telegraphs slowly;
   - the roll, and its i-frames.
   Losing only knocks you down; he helps you up and says the one thing you did wrong.
3. *The down (2 min).* A bristleback boar roots in the dry valley behind the fort. It charges,
   and you learn to side-step and roll through a charger and strike its flank.
4. *The first real fight (4 min).* The Wynstead road: two roadside bandits camp in a dry ditch
   and have taken the milestone for a table. This is the Wynstead Ditch Camp, a wave-6 find 670 m
   from the fort, which already stands its two bandits by day. Dole sends you and Tam. It should
   feel like the warrior:
   - two on one, because Tam freezes;
   - the shield takes the first rush;
   - a parry opens one bandit for a riposte (DamageModel's riposte crit);
   - a heavy swing staggers the other.
   You carry the milestone back to the verge. The find's own hook already says the milestone
   keeps walking back, which is a nice echo.

**The horse.** Dole signs Hollin out of the Wardens' stable to you, because Wren is short of a
cob at the Stair and "you'll ride it there, and she'll ride it back". `give_mount` on Dole's
last line, homed at Wardens' Rest. From then on, *The Toll Hums* does not hand over a second
cob (§5.4).

**The tie-in: "The Relief".** Dole gives you the Stair Head's month's pay and the Roll's new
page, for Wren. Tam is to ride with you.
- At the Glass Bridge, Tam goes quiet in the way the Wardens are taught to watch for. He has had
  a letter: Fallowfold's name was struck from a Roll in Tollmere.
- At the Stair Head, Wren takes the pay. Then Tam walks past her fire and down the stair. Wren
  shouts that nobody comes back up. You go after him, because a Warden does not leave a Warden
  unnamed.

**What stays down there.** Tam Hobb. His name goes on the Roll at Wardens' Rest as one of the
quiet. It is a thread for the Wardens' questline, *The Roll of Names* (WORLD_BIBLE §4.1), and
for the Tolling Order's "escort a pilgrim into the Hushline and bring back what she leaves".

### 3.1a Warrior: the ground, measured (cartographer)

Measured on the built world w4096d, with waves 5 and 6 and the signposts in the pack. The capture
plan is `tools/capture/plans/starts_warrior_ranger.json`.

**The Wynstead Ditch Camp and the tutorial.**
- **Where it is.** 665 m from the fort, on a bearing of 121° (east-south-east), and 39 m lower.
  The way down is open, dry down, and passes 21 m from the Old Sheepwash, an empty ruin.
- **Its foes.** Two roadside bandits, by day only, standing on the pad's rim about 9 m from its
  centre. The first fight has to be by day. The camp is 30 m off the Wynstead-Fallowfold road.
- **It is off the ride.** The camp is 309 m from the ride's road at its closest, so the ride south
  does not wake it.
- **Keep the yard and the down clear of the Watchtower.** The Tumbled Watchtower is 372 m
  west-north-west of the fort (306°). It stands five bandits and a smuggler-Sayer. Country
  bristlebacks root 422 m west, and the Wolf Holt's three down-wolves are 804 m out on the same
  side.
- **Put the boar's down south of the fort,** at about (-700, 1800), 160 m out. The ground there is
  open (slope 0.08). It is 484 m from any encounter, 210 m from any other thing and 114 m off the
  road. The tutorial should stand its own bristleback there, not borrow the country's.
- **One more foe nearby.** A country hedge-wight stands 338 m east-north-east, at (-399, 1486).
  It is not within 80 m of the ride.

**The ride to the Stair Head: 4.7 km, about 11 minutes at a canter.**
- **The way.** Wardens' Rest, then Merrowby (1.2 km), Wynstead (1.8), Ashwell (2.4), Pilgrim's Ash
  (3.1), the Sunken Choir (4.2) and the Stair Head (4.7).
- **Threats within 80 m of the road:**
  - the Larkbourne Ford (0.85 km): two bandits, at night only;
  - the Glass Bridge (3.2 km, 3 m off the road): four ash-wights under the arch, always;
  - the Glass Falls (3.8 km, 23 m off): a bell-bearer on the lip.
  The last two are on all four rides, since they share the last 1.6 km, and §3.5 does not cover
  them. Either stand them only from the Naming's stage after the wake, or accept that a rider
  crosses over the wights' arch. No country spawn is within 80 m of the ride.
- **Fingerposts passed:**
  - Ashwell's junction, 2.1 km: Ashwell ¼ | Wynstead ¼ | The Hare and Hurdle 1;
  - east of Pilgrim's Ash, 3.2 km;
  - the Glass Bridge, 3.3 km: The Glass Bridge ¼ | The Sunken Choir ½ | Greyfold 1¼;
  - under the Choir, 4.2 km: The Stair Head ¼ | The Last Camp ½ | Pilgrim's Ash ¾;
  - the Stair Head's own.
- **Town stones passed:** Wardens' Rest, and both ways into Merrowby, Wynstead, Ashwell and
  Pilgrim's Ash.
- **Thin road.** One stretch, 4.2 to 4.6 km: the Choir to the Stair Head, the Naming's way, which
  is kept quiet.
- **The Hearthstone stop is the Wellspring,** at 2.7 km, 42 m off the road: the stone nearest
  the ride's midpoint (2.35 km), as the user asked for a stop halfway (§3.6). Merrowby, at
  1.2 km, stays a sight on the way for the Toll teaser of §3.5. The Pilgrims' Bell (2.85 km, on
  the road) is the next nearest.

**The three captures.**
- `warrior_first_view`: from the fort's yard, 16 m north-west of its centre, across the down to
  the ditch camp. 09:00.
- `warrior_first_fight`: a body 19 m from the camp on the fort's side, turned to the bandits.
  11:00.
- `warrior_ride_glass_bridge_post`: the Glass Bridge fingerpost from the road, 5 m off. 14:00.

### 3.2 Ranger: Fernhold

**Why here.**
- The user's example was "a small forest town". Fernhold is the foresters' lodge on the High
  Wold, with its antler hall.
- Its keeper, Alder Wyke, walks the Briar every morning and counts the grey patches, "and the
  count is going up". The Briar is the wall the Oroth grew to keep the Hush in the south
  (WORLD_BIBLE §10.6), so the ranger's start points at the Hush from its first line.
- The Wold's thornhounds and weavers are a bow's natural prey, within 500 m of the lodge. The
  thornhounds drink at Wold Force (431 m) and lie up at the Silence Stones (315 m), and weavers
  are on Fern Gully's bridges (456 m).

**The teacher.** Rosen Wyke (`core:npc/rosen_wyke`: brave, proud, cynical, quiet, kind). She
is Fernhold's other hunter, the one who shoots: "the lodge eats because she does." She has never
been able to make her father say so. Her voice is spare and exact, with a hunter's patience, and
she is quick to be proud of you and slow to say it:

> "Breathe out. Loose on the empty. The arrow doesn't care how brave you are."
> "Wind's in your face. Good. It can't smell you. It can hear you, so stop talking."
> "Don't chase it. Let it come round. Everything comes round."

**The tutorial (about 13 minutes).**
1. *The butts behind the antler hall (3 min).*
   - Draw, hold and loose.
   - Arrow drop over 20, 40 and 60 m.
   - The held draw's stamina.
   - Picking up arrows from a target.
2. *The morning walk (4 min).* Rosen takes you along the Briar with Alder, and teaches:
   - sneak, and walking into the wind;
   - reading tracks: the hart's slots, then the thornhounds' prints over them;
   - arrows as a thing that runs out, and picking them up again.
   Alder counts a grey patch out loud. It is one more than yesterday.
3. *The weaver (2 min).* On Fern Gully's bridges, a weaver drops from the canopy on the path.
   You learn to back off and shoot up, or roll clear, because a ranger does not stand under
   things.
4. *The first real fight (4 min).* Wold Force, where the thornhounds drink. Rosen puts you on
   the lip above the pool at dusk with the pack coming down to it. It should feel like the
   ranger:
   - two go down to arrows before they find you;
   - the third closes, and you learn the knife (the hunting knife) and the roll back to range;
   - Rosen does not shoot unless you are hurt, and says afterwards that she nearly did.

**The horse.** Rosen's old forest pony, a sure-footed grey-dun she rode as a girl. It is too
small for her now, she says, which is not true. The mount is new: kin of the cob, smaller, with a
Woodfolk saddle-cloth. It is homed at Fernhold.

**The tie-in: "The Grey Hart".** At dawn the hart whose slots you read is out on the Wold, and it
has gone grey. It walks south, away from the Briar and out of the wood, and it does not run
from you.
- Alder asks you to follow it and find where it goes, "because I know where it goes, and I want
  to be wrong".
- The ride goes south from the Briarwold by Grandfather Hollow and the Standing Moot, then over
  the East Downs and Hound Down (Hollin Barrow, the Hare and Hurdle, Bramcombe) to Pilgrim's Ash.
  It follows the hart's trail and the fingerposts.
- At the Stair Head the hart walks past Wren's fire and down the stair. You follow it. Wren has
  never seen a beast go down.

**What stays down there.** The grey hart. It is a thread for *The Briar's Purpose*: the Briar
is failing, and its creatures are walking south.

### 3.2a Ranger: the ground, measured (cartographer)

**The tutorial's ground.**
- Wold Force is 431 m due south of the lodge (184°). Its three thornhounds are always there.
- The Silence Stones' two thornhounds stand by day, 315 m from the lodge.
- The weavers are on Fern Gully's bridges.
- The fall's lip, where Rosen puts you, is the high ground about 27 m east-south-east of the pool,
  17 m above it. The waterfall builder's `lip` marker is the exact spot, and the first-fight
  capture takes the bearing from it.

**The ride, as §3.2 draws it, is 11.9 km and passes the boss.** Its way is by Grandfather Hollow,
the Standing Moot and Hazelcombe, then Hollin Barrow, the Hare and Hurdle and Bramcombe.
- At the Standing Moot (3.6 km) the Hart of Thorns stands in the circle, 1 m off the road. A
  level-one ranger would ride into the main quest's boss.
- It also passes the Antler Chapel's Hart-Knight (5.5 km, 2 m off) and the Hunter's Stand poachers
  (2.9 km, 40 m off). The Sentinels and the Burnt Lodge have Wardens at dusk. The Lamb's Bottom
  down-wolves are 60 m off at 8.9 km.

**The recommended ride: 10.1 km, about 24 minutes at a canter.** Fernhold, then Grandfather
Hollow (2.0 km), Tamwick (5.4), Merrowby (6.6), Wynstead (7.2), Ashwell (7.8), Pilgrim's Ash
(8.5) and the Stair Head (10.1). It is the shortest road, and it does not touch the Moot. Keeping
Hound Down instead (by Tamwick and Hollin Barrow, 10.8 km) passes a down-wolf pack 15 m off the
road at 5.6 km, and Lamb's Bottom.
- **The hart's trail.** Say that it goes round the Moot, which is where the Briar's failing and
  the Hart of Thorns meet.
- **Foes near the road by day:**
  - the Silence Stones' thornhounds (1.3 km, 9 m off), the tutorial's own ground;
  - Wenna's House's weaver (3.4 km, 11 m off, always);
  - country spawns: a Hart-Knight (3.3 km, 31 m off), a thornhound pack of five (4.4 km, 43 m) and
    two bristlebacks (4.75 km).
  The Webbed Lodge, Root Hollow, Sawyer's Bench and the Hart Snares come out only at night. The
  Glass Bridge and the Glass Falls are as on the Warrior's ride.
- **Fingerposts:** the Greatwood junction (3.5 km: Hazelcombe ½ | Grandfather Hollow 1 |
  Tamwick 1¼), and the Warrior's last four.
- **Town stones:** Fernhold, Grandfather Hollow, Tamwick, Merrowby, Wynstead, Ashwell and
  Pilgrim's Ash.
- **Thin road.** Only the Choir to the Stair Head.
- **The Hearthstone stop is Ansel's Hedge Shrine,** at 6.0 km, 14 m off the road: the stone
  nearest the ride's midpoint (5.05 km, §3.6). The Oiled Stone (2.6 km) comes before it.
  Merrowby (6.6 km) carries the same Toll teaser as the Warrior's ride.

**The three captures.**
- `ranger_first_view`: from the lodge's north side, south over the Wold to Wold Force. 07:30.
- `ranger_first_fight`: a body on the lip, 27 m east-south-east of the pool, turned to the pack.
  18:12, dusk.
- `ranger_ride_greatwood_post`: the Greatwood fingerpost from the road, 5 m off, with Wenna's
  House beyond. 10:30.

### 3.3 Mage: Gullhithe and the Lamp

**Why here.**
- The Lamp, the lighthouse on the Mere's north shore, is lit by an Oroth sul-stone, and a
  village woman wakes it every dusk. That is magic the Sayers do not own. It suits a small start
  better than the Sayers' Spire, whose city (Tollmere) is the main thread's third quest.
- Gullhithe is a fishing village of eel-racks under the Lamp. Its smugglers include Sayers who
  sell the Circle's secrets on the side (Brightwater's `smuggler_sayer`).

**The teacher.** Tamsin Wick, Keeper of the Lamp (`core:npc/tamsin_wick`: brave, generous,
cynical, gossip, humble, kind). She "wakes the sul-stone every dusk, turns the eel-racks every
noon, and has not slept a whole night through in thirty years". She is no Sayer and says so.
Her voice is a busy, wry woman's who talks while she works and teaches by chores:

> "Don't *push* it. It's a stone, not a mule. Say it louder than it's saying itself."
> "The Sayers charge by the hour for that. I charge by the eel-rack. Turn those."
> "There. You're a lamp now. Try not to set the racks on fire."

**The tutorial (about 12 minutes).**
1. *Waking the stone (3 min).* At the Lamp's top, Tamsin teaches:
   - casting from the hand;
   - the Saying's pool (magicka) and its regeneration;
   - the first spell, Kindle Bolt, lighting the sul-stone and then a line of harbour braziers
     at range.
2. *The racks (3 min).* Mending and Warding, taught as chores:
   - Mend on a burned hand, a salt-cut, and yourself;
   - Ward against thrown shingle from Jory, her nephew, who enjoys it too much.
3. *The cold (2 min).* Hush Frost (the hush school) on the channel's eels. It slows, and
   Tamsin's point is that a slowed thing is a thing you have time for.
4. *The first real fight (4 min).* At dusk two smuggler-Sayers row in to take the sul-stone.
   It should feel like the mage:
   - Ward takes their first bolts;
   - Hush Frost slows the one who rushes the stair;
   - Kindle Bolt at range while you keep the stair between you;
   - you are never meant to be in reach.
   If you do end up in reach, the lesson is to back off and re-cast.

**The horse.** The Wicks' old cart-horse, which pulled the eel-cart to Tollmere until the
Tallymen priced the barrow off the Row. That is Jory's grievance, already in his def. The
mount is new: kin of the cob, heavier, with a draught horse's feathers. It is homed at Gullhithe.

**The tie-in: "The Note Under the Water".** The smugglers carried a Sayers' listening-bell, a
tuning instrument. Held to the ear, it hums with the Toll. Tamsin says it hums loudest when it
points south.
- She sends you to hear where the note comes from: "the Circle would charge you for this, and
  they'd be wrong".
- The ride goes round the Mere's west shore by Sedgehithe and Stride's Foot, south through the
  Vale past Merrowby (the Toll is humming), then by Wynstead and Ashwell to Pilgrim's Ash. The
  bell grows louder the whole way.
- At the Stair Head it is loudest down the stair. You go down to hear it.

**What stays down there.** The note. The bell comes back silent, and the Hush has the note.
This is a thread for *Louder Than Books* and *The Held Note*, where "the Cantor's Seat is
holding something" (WORLD_BIBLE §10).

### 3.3a Mage: the ground, measured (cartographer)

Measured on the built world w4096d, with waves 5 and 6 and the signposts in the pack. The capture
plan is `tools/capture/plans/starts_mage_rogue.json`.

**The tutorial's ground: the Lamp.**
- **Where it is.** The Lamp stands on a headland 283 m east-south-east of Gullhithe's centre. The
  Mere is 90 to 110 m off on every side but the west, where the land runs back to the village.
  The tower is 34 m to its gallery (the forge's meta).
- **The smugglers row in from the south.** The water there is 90 m off, and the sector from
  150° to 210° is clear of any foe for 450 m. Land them on that shore, so the stair between you
  and them is the Lamp's own.
- **Keep the fight off the north side.** The Three Rights' two cutpurses stand 354 m north of
  the Lamp, at night only. A dusk fight is on the edge of their hour, so the smugglers' landing
  and the stair should face away from them.
- **The Gullhithe Wreck is the start's one real danger.** It has five gutter drakes, always, in
  the hull 81 m south of the village's centre and 343 m from the Lamp, and it is 27 m off the
  road the ride leaves by. A level-one mage walks out of the village past five drakes.
  - Recommendation: stand the wreck's drakes only from the Naming's stage after the wake, as the
    Glass Bridge wights and the Glass Falls bell-bearer are.
  - Or make the wreck the tutorial's optional last lesson, Kindle Bolt from the shore at range,
    with two drakes and not five.
- **Other foes nearby.** Two country smuggler-Sayers are 560 m south-south-east of the Lamp, over
  the water. North Cliff Beacon's Sayer and two cutpurses are 613 m north-east. Neither is in
  reach of the tutorial.

**The ride to the Stair Head: 7.4 km, about 17 minutes at a canter.**
- **The way.** Gullhithe, then the Eelweir (0.8 km), Sedgehithe (1.3), Stride's Foot (3.1),
  Merrowby (3.9), Wynstead (4.5), Ashwell (5.1), Pilgrim's Ash (5.7), the Sunken Choir (6.9) and
  the Stair Head (7.4). This is the shortest road, and it is §3.3's way round the Mere's west
  shore.
- **Threats within 80 m of the road:**
  - by day: the Laundry Punt's cutpurse (2.0 km, 16 m off) and the Dodger's Stone's two
    cutpurses (2.5 km, 3 m off);
  - at night only: the Eelweir's three leech-hounds (0.8 km, 3 m off), the Tallyman's Folly's
    three cutpurses (1.75 km), and the False-Light House's smuggler-Sayer (3.2 km, 38 m off);
  - the Glass Bridge and the Glass Falls, as on every ride (gated after the wake).
  The mage should set out in the morning, after the dusk fight and a night at the Wicks'. The
  False-Light House's smuggler-Sayer is the same trade as the tutorial's, a sight on the way.
  No country spawn is within 80 m of the ride.
- **Fingerposts passed:**
  - the Eelweir, 0.8 km: Nauve's Landing ¼ | Sedgehithe ¼ | Gullhithe ½;
  - west of Stride's Foot, 3.0 km: Stride's Foot ¼ | Pennywort's Mill ½ | Sedgehithe 1;
  - east of Stride's Foot, 3.2 km: Stride's Foot ¼ | Merrowby ½ | The Rafters' Camp 1¼;
  - then the Warrior's last five, from Ashwell's junction to the Stair Head's own.
- **Town stones passed:** Gullhithe, and both ways into Sedgehithe, Stride's Foot, Merrowby,
  Wynstead, Ashwell and Pilgrim's Ash.
- **Thin road.** Only the Choir to the Stair Head.
- **The Hearthstone stop is Merrowby,** at 3.9 km, on the road: the stone nearest the ride's
  midpoint (3.7 km, §3.6), with the Toll teaser of §3.5. The Sedge Hearth (1.1 km) comes before.

**The three captures.**
- `mage_first_view`: from the Lamp's gallery, 31 m up on its west side, over Gullhithe and the
  Mere. 16:30.
- `mage_first_fight`: a body 16 m south of the Lamp, on the smugglers' shore, turned to them.
  18:18, dusk.
- `mage_ride_strides_foot_post`: the fingerpost west of Stride's Foot, from the road, 5 m off.
  10:00.

### 3.4 Rogue: Moreva

**Why here.**
- Moreva is an eel-landing of stilt-houses strung with wicker eel-traps like washing. The
  Delta's fog is up 40% of the time.
- Its eldest trapper lifts a hundred and forty traps before dawn and sells to Gullhithe "through a
  man he has never met". That is a smuggler, and a good stealth teacher.
- The Tallymen tax the eels through a collector with a hired bravo, so the rogue's first mark
  is in the charter's own economy.
- The Quiet Hands (WORLD_BIBLE §4, "they practise Hush") are Tollmere's, and Sauve's man is one.
  That makes this start a path into their questline, *The Unsaid Ledger*.

**The teacher.** Sauve Mor (`core:npc/sauve_mor`: quiet, brave, humble, cynical, generous).
His voice is a man who talks as little as his traps do. He teaches by being unseen and then
being behind you:

> "Mud's quieter than boards. Boards are quieter than water. You're quieter than none of them."
> "They look where it's loud. Be where it isn't."
> "Once. From behind. Then gone. Twice is a fight, and you don't fight."

**The tutorial (about 14 minutes).**
1. *The traps before dawn (4 min).* Sauve lifts the South Channel traps, and you follow him
   without being seen by the Reed Council's night-watch. You learn:
   - sneak, and the eye, the detection state;
   - light and shadow, and fog;
   - boards against mud against water;
   - hiding in the reeds.
2. *The collector's stilt-house (3 min).* Before the tithe-day, Sauve teaches the lock and the
   purse, and the Tallymen's rule that a lock picked is a crime and a crime is a bounty
   (`systems/crime`):
   - lockpicking a strongbox;
   - pickpocketing the sleeping collector's key.
3. *The dagger (2 min).* Sauve hands you an iron dagger and shows what a blade from behind does
   to a sack of eels. That is the sneak-dagger crit (DamageModel `sneak_dagger` x6), and the
   backstab facing test.
4. *The first real fight (5 min).* Tithe-day, in the fog. The collector's bravo, the Tallymen's
   elite hire, walks his round of the landing. It should feel like the rogue:
   - you stalk him along the stilts;
   - one blow from behind in the fog (x6) ends it, or nearly ends it;
   - if he turns, the lesson is to break line of sight, drop into the reeds, and come again;
   - a straight fight with a bravo is meant to go badly.

**The horse.** The bravo's own horse, tethered at the landing's end with the Tallymen's
charter-brand on its flank.
- Sauve says a horse with no rider is nobody's.
- It is a theft that no one reports, because the one witness is the collector, and he is now
  in the reeds with a very good reason to say nothing.
- The mount is new: kin of the cob, a leggy bay under a brass-studded Tollmere saddle. It is
  homed at Moreva, and Sauve keeps it.

**The tie-in: "The Unsaid Page".** The collector's satchel holds a Tallymen's ledger page. It
lists a village's debt, and "UNSAY" is written across it: somebody has paid to have a
village's name struck.
- Sauve's man in Gullhithe wants the page. So does the collector's courier, who runs south at
  dawn with the other copy, grey-faced, as if he means to deliver it to the Hush itself.
- The ride goes out of the Delta by Nauve's Landing and the Eelweir, round the Mere by
  Sedgehithe and Stride's Foot, and south through the Vale by Merrowby. The courier is a grey
  figure always a field ahead.
- The courier walks past Wren's fire and down the stair. You follow the page.

**What stays down there.** The courier and his copy of the page. The village is not unsaid,
because the Hush got the page and not the Circle. That leaves a thread for *The Unsaid Ledger*,
and the player has the only other copy.

### 3.4a Rogue: the ground, measured (cartographer)

**The tutorial's ground: Moreva.**
- **Where it is.** Moreva's landing is 41 m across. Water lies 80 to 150 m off to the south and
  south-west, and 220 to 250 m to the north. The east is dry for 250 m.
- **The traps are the South Channel's.** §3.4 first said the North Channel. The north is not
  safe before dawn:
  - two country sallowjaws are 362 m north-north-west, and two more 371 m north-east;
  - five country bog-drowned are 581 m north;
  - the south, from 150° to 210°, is clear of any foe for 600 m, with the water 90 to 150 m off.
  Keep the traps within about 200 m of the landing, between 160° and 200°.
- **Keep off the Wisp Hollow and the Settled House.**
  - The Wisp Hollow's three wisps stand always, 272 m south-west (216°), on the South Channel's
    west edge.
  - The Settled House's two bog-drowned stand at night, 287 m east-south-east (124°), which is
    the hour of the traps.
  - The Stair of Isse's three bog-drowned stand always, 376 m west-north-west.
  None is in reach of a route that keeps within 200 m.
- **The tithe-day fight is on the landing itself,** by day and in fog. Nothing stands up within
  270 m of it by day, and the bravo's round is the tutorial's own.

**The ride to the Stair Head: 8.2 km, about 19 minutes at a canter.**
- **The way.** Moreva, then Nauve's Landing (1.1 km), the Eelweir (1.6), Sedgehithe (2.2),
  Stride's Foot (3.9), Merrowby (4.7), Wynstead (5.3), Ashwell (6.0), Pilgrim's Ash (6.6), the
  Sunken Choir (7.7) and the Stair Head (8.2). It is the shortest road and §3.4's way. From the
  Eelweir on, it is the Mage's ride.
- **Threats within 80 m of the road:**
  - the Settled House's two bog-drowned (0.3 km, 30 m off), at night only;
  - the rest of the Mage's ride: the Eelweir, the Tallyman's Folly, the Laundry Punt, the
    Dodger's Stone, the False-Light House, and the Glass Bridge and the Glass Falls.
  The courier "a field ahead" leaves at dawn, so the ride is by day, and only the Laundry Punt's
  and the Dodger's Stone's cutpurses are up. They are the Tallymen's own trade, as the courier
  and the collector are: a sight on the way. No country spawn is within 80 m of the ride.
- **Fingerposts passed:** the Eelweir (1.6 km), and then the Mage's: west and east of Stride's
  Foot, Ashwell's junction, and the Warrior's last four.
- **Town stones passed:** Moreva, and both ways into Nauve's Landing, Sedgehithe, Stride's Foot,
  Merrowby, Wynstead, Ashwell and Pilgrim's Ash.
- **Thin road.** Only the Choir to the Stair Head.
- **The Hearthstone stop is Merrowby,** at 4.7 km, on the road: the stone nearest the ride's
  midpoint (4.1 km, §3.6). The Sedge Hearth, at 2.0 km, is 2 km from halfway.

**The three captures.**
- `rogue_first_view`: from the landing's south edge, 30 m out, down the South Channel in the
  fog before dawn. 05:24.
- `rogue_first_fight`: a body on the landing's boards, 14 m south-south-east of its centre, in
  fog, turned to the bravo. 10:00.
- `rogue_ride_eelweir_post`: the Eelweir fingerpost from the road, 5 m off, in mist. 09:00.

### 3.5 What the rides pass on the way

All four rides reach the Stair Head the same way. From Pilgrim's Ash the road runs by the Glass
Bridge and past the Sunken Choir to the camp: the only road to the Stair. So every character
passes the Naming's later places before the descent. This is kept, and handled:
- **The Choir's three ash-wights** are the Naming's own quest foes, stood up by its `ash_wights`
  stage. They are not there on the ride south. On the way down the player sees the colossi
  empty, and on the way back they are not.
- **Pilgrim's Ash's Hearthstone** can be touched on the ride south. The Naming's `hearthstone`
  stage completes on reaching it and resting there after the wake, as now. The Tolling Order
  there says the Stair is "two miles on, and nobody's business".
- **The three rides from the west pass Merrowby,** with the Toll humming, a day before *The Toll
  Hums* starts there. It is a teaser. Nothing in Merrowby moves until the main quest's stage
  does.

### 3.6 The Hearthstone stop on each ride

The user asked for a stop halfway. Each ride's stop is the Hearthstone nearest its midpoint,
along the road, measured on w4096d:

| Start | Ride | Midpoint | The stop | Where on the ride |
|---|---|---|---|---|
| Warrior, Wardens' Rest | 4.7 km | 2.35 km | the Wellspring | 2.7 km, 42 m off the road |
| Ranger, Fernhold | 10.1 km | 5.05 km | Ansel's Hedge Shrine | 6.0 km, 14 m off |
| Mage, Gullhithe | 7.4 km | 3.7 km | Merrowby | 3.9 km, on the road |
| Rogue, Moreva | 8.2 km | 4.1 km | Merrowby | 4.7 km, on the road |

Merrowby is the Mage's and the Rogue's stop, and a sight on the way for the Warrior and the
Ranger. In every case it carries the Toll teaser of §3.5.

## 4. The Stair Head: the descent and the wake

This is shared by all four and built once.
- **The approach.** The Stair Head's dressing is laid out from the POI's position towards the
  Choir. A rider arriving from the north, down the waystones, meets the camp from behind the
  tents and comes to the Stair past the two Oroth piers. The opening agent says this is a fine
  approach. Capture it before the descent's shots are designed.
- **The meeting.** Wren is at her fire; the opening agent's advice is that an empty camp reads as
  the "test ground" the user complained about. She greets them as whoever sent them: Dole's
  recruit, Alder's tracker, Tamsin's girl or boy, or nobody she wants to know. That is one line of
  hers per style, keyed on the style.
  - **This exchange stays nameless.** She shouts, and does not introduce herself ("I'm the
    Warden. That's all the name the Stair needs."). So the cinematic's "The Warden" label, and its
    "she has not told you her name yet", still hold. Her dialogue gives her name at the wake, as
    it does now.
- **The thing goes down.** It walks past her fire and down the stair: Tam, the hart, the
  courier, or the note in the bell. Wren shouts: "Nobody comes back up!"
- **The descent (player control, 20-40 s).**
  - The player walks down the Oroth stair from the camp. The stair the opening already flies is
    there, 77 m down the cliff.
  - Each step drains the colour a little: saturation to zero by the fortieth, as the wake
    journal already says. The sound drains with it, and the thing ahead fades into the mist.
  - A trigger at the fortieth step fades the picture to grey and starts `core:cinematic/opening`
    exactly as it plays now, ending on the gameplay camera at the camp.
  - A player who turns back before the fortieth step just walks back up. Wren says "Good", and
    the thing is gone.
    - The Naming still starts, from Wren. She asks the name; the cinematic's first shot is her
      saying it.
    - Wren then plays a short scripted version of the descent herself, the one she has seen
      nineteen years of others walk. This is open question 2.
- **The wake.** From here the Naming runs as built, from its `wake` stage (Wren at her fire, "There
  you are. Eyes working? Good."), rewritten to know what they just did (§5.3).

## 5. What changes

### 5.1 Character creation

- The Naming screen gets a fourth section, **Fighting style**: four cards, Warrior, Ranger, Mage
  and Rogue. Each card shows:
  - a picture of its start town;
  - the teacher's name;
  - the starting kit;
  - one line about the start ("Wardens' Rest, on the West Downs: Sergeant Dole teaches the
    shield and the sword").
- **Callings stay** as backgrounds. Their +10 to three skills and signature item stand. A style
  adds:
  - its **starting kit**, all existing items:
    - warrior: an iron sword and an oak round shield;
    - ranger: a hunting bow, iron arrows and a hunting knife;
    - mage: an ash staff and three spells (Kindle Bolt, Mend, Ward); Hush Frost is learned in the
      tutorial;
    - rogue: an iron dagger and lockpicks;
  - **+5 to two style skills**:
    - warrior: one-handed and block;
    - ranger: archery and sneak;
    - mage: kindling and binding;
    - rogue: sneak and one-handed.
  This does not replace the Calling.
- **Data:** `content/packs/core/styles/styles.json`, one `core:style/<id>` def each, holding:
  - name and blurb;
  - the kit;
  - the skill bonuses;
  - the start's opening id;
  - the teacher;
  - the tie-in quest;
  - the mount.
  A `StyleDef` validator checks each def, like `CallingDef`.
- **The character record** gains `style` (a style id) beside `calling`, in the save.

### 5.2 `core:opening/new_game`

- `opening.json` gets four openings, `core:opening/<style>`, each with:
  - `role: "new_game"` and a `style` key;
  - its own place, region, quest (the style's tutorial quest) and greeter (the teacher);
  - an optional short cinematic of its own: three or four shots of its region and town in the
    same style, 30-40 s, and skippable.
- **`GameServices.begin_new_game()` is split in two.** Today it is one call, gated on the
  `new_game` flag: it plays the cinematic, clears the flag and starts `the_naming`.
  - *The new game* picks the opening whose `style` matches the character. `PlayerSpawn` stands
    the body at `opening.place` (the start town), from the manifest's `start` pose or the
    opening's own. It starts the style's tutorial quest, and raises a flag of its own,
    `style_start`.
  - *The wake* is the second half. It is fired by the descent's trigger at the fortieth step, as
    an effect at the end of the tie-in quest. It fades to grey, raises `new_game` (or a `wake`
    flag), plays `CinematicPlayer.play_opening` as now, then clears the flag and starts
    `the_naming` at `wake`.
  - The split is the opening agent's reading of its own code: its note is that "everything else
    keyed on `new_game`" must not stay up through a 15-minute tutorial. `SaveSystem.hold_saves`
    blocks saving while the opening plays, and a slot saved before the hand-over "gets the story
    and not the pictures". So `new_game` goes up only at the descent, and the tutorial and ride
    can be saved like any other play.
- The current `core:opening/new_game` stays, as the fallback for a pack with no styles and for
  tests.
- The skip, the setting that turns the cinematic off, and the pause menu's *How it began* keep
  working, because they belong to the player and not to the new game.

### 5.3 The Naming and Wren's lines

- **A new first stage, `down_the_stair`.** Reach the Stair Head, watch the thing go down, and
  follow it down. It is started by each tie-in quest's last stage. Its objective is `reach` the
  descent trigger, with a stand-at at the fortieth step.
- **`wake`.** The journal is rewritten from "Behind you, down a flight of Oroth stairs, is a grey
  mist" to the same moment after going down:
  > "You went down after it, and at about the fortieth step the colour went out of your hands.
  > You do not remember turning round. You remember the Warden saying your name, over and over,
  > the way you would call a dog you were not sure was yours."
  The stage still hands off to nothing: the name was chosen in character creation. The flag
  `named` is set on the wake, as it is now.
- **`the_choir`, `ash_wights`, `hearthstone`:** unchanged.
- **`the_cart` becomes `the_road_north`.** "Wren says the Vale is warmer than this ... Ride to
  Merrowby." The objective is to reach Merrowby, and the Foundling's Token is still given. The
  cart and carter stay in the world for players who lose their horse. The cart is Wren's fallback
  line if the player has no mount.
- **Wren's dialogue (`dialogues/wren_tallow.json`):**
  - a greeting for the meeting, one line per style;
  - the shout;
  - after the wake, a first line that knows what went down ("Tam Hobb. He was Dole's. I'll
    write it in myself.", "A hart. I've never seen a beast go down.", "Whatever that was, it was
    carrying paper.", "You were listening for something. Did you hear it?");
  - her `the_hush` line ("nineteen years ... watching grey people walk *down*"), unchanged,
    because it is now what the player just saw.
  - **Her hold** (npcs/merrowby.json) keeps her at `wren_stair_head` while `new_game` is set,
    or while the_naming is at `wake` or `the_choir`. It gains `style_start` and `down_the_stair`,
    so she is at her fire from the moment a new game begins until the player reaches the Choir.
    That covers the whole tutorial and ride, for the meeting.
- **The Toll Hums:** `arrive`'s `give_mount` of the Wardens' cob becomes conditional on having
  no mount, which is only the fallback opening.

### 5.4 Each style's own content

Each start adds its own content:
- a tutorial quest, `core:quest/first_<style>`, with 4-5 stages;
- a tie-in quest, `core:quest/<tie_in>`, with 3-4 stages ending in `start_quest the_naming` at
  `down_the_stair`;
- the teacher's lessons in their dialogue file;
- a handful of tutorial markers and props in the town:
  - pells and a sparring ring at Wardens' Rest;
  - butts and a hide at Fernhold;
  - braziers at Gullhithe;
  - the tithe strongbox at Moreva;
- one new NPC for the warrior (Tam Hobb) and one for the rogue (the courier);
- one mount def for each of the three new horses.

The tutorial prompts (the on-screen "RMB block") come from the input prompts player-feel already
shows. A lesson's stage completes on the act itself (`block`, `parry`, `backstab`, `cast`,
`hit_at_range`), and those events get quest objective types where they do not already have them.

### 5.5 The save

- `style` goes in the character record. The tutorial, the ride and the descent's progress are
  quest stages and flags like any other, so they save and load with no new machinery. Saving is
  held only while the wake's cinematic plays, as it is now, because only then is `new_game` up.
  A save made on the stair above the fortieth step resumes there.
- **Old saves:**
  - a save made after the Naming is untouched;
  - a save made during the old Naming (at `wake` or `the_choir`, with no `style`) loads as the
    fallback start: it keeps the old stages, and its Toll Hums still gives the cob.
- No new game plays the old opening unless the pack has no styles.

### 5.6 Tests

- **Content:** `StyleDef`, and every style's opening, quests, teacher, mount and kit resolve
  (test_content). Each start place, teacher home and mount home is a real place (test_map_quest).
- **The quest walker:** `QuestWalk` walks each style's tutorial and tie-in into `the_naming`, and
  the Naming's new first stage. That is four new walk routes, and it runs in the one full main
  check at the end, not per landing.
- **The journey:** `./run.sh journey` gets a `--style` switch. It walks one style's first minutes
  from New Game: the teacher greets, the first lesson completes, the first fight stands up its
  foes, and the horse is given.
- **The start:**
  - test_the_start keeps its Stair Head checks, run from the wake rather than from New Game:
    - the Foundling at the POI's own position;
    - Wren 4-10 m in front, facing them;
    - the first view up the waystones to the Choir;
    - the HUD objective "Walk the waystones north to the Sunken Choir";
    - the camp, the stair and the waystones on the ground.
    The opening agent confirms that all of these still hold if the wake is where the_naming
    starts, whatever came before.
  - one check per start town: the teacher's spot, the tutorial markers on the ground, the first
    fight's foes within reach and off the tutorial's route, and nothing floating.
- **The descent:** colour at the fortieth step, the cinematic starts on the trigger and hands
  back at the camp, and turning back before the trigger still starts the Naming.
- **The flow:** New Game, Continue and Load for each style. A loaded game never plays the
  cinematic, and a mid-descent save resumes at the top of the stair.
- **The map:** the tie-in roads are signed the whole way (test_signposts), and each ride's
  road threats are within what the start's gear can handle. The cartographer checks the threat
  measure along the four routes.

## 6. The order, the sizes and who builds what

S is about a session, M two or three, L more. One start lands at a time, each verified before
the next begins (DECISIONS: "each landing when it is verified").

| # | Work | Size | Who |
|---|---|---|---|
| 0 | Approve this plan. Rewrite DESIGN §5.1 and §5.1a from it. | S | opening |
| 1 | **The frame:** styles data and `StyleDef`; the character-creation section (UI); the save field; per-style openings; the cinematic moved to the descent trigger; the Naming's `down_the_stair`, `wake` and `the_road_north`; Wren's lines; the cob made conditional; the fallback start kept. | L | opening (quests, openings, Wren), characters (the creation UI and the style card art), player-feel (the descent's colour and sound drain) |
| 2 | **Warrior at Wardens' Rest.** The existing cob, teacher and bandits are ready. Build the yard's pells and ring, Dole's lessons, Tam Hobb, *First Blood* and *The Relief*. | M | opening (quest, dialogue, Tam), settlements (the yard, ring and pells), player-feel (block, parry and heavy objectives, the prompts), cartographer (the route, the ditch camp's placement check, the captures) |
| 3 | **Ranger at Fernhold.** The butts, the hide, the hart and its grey walk south; Rosen and Alder's lessons; the forest pony. | M | opening, settlements (butts and hide), characters or tree forge (the pony, and the grey hart as a walking creature), player-feel (the draw, drop and range objectives), cartographer (the hart's route) |
| 4 | **Mage at Gullhithe.** The braziers, the Lamp's top as a casting stage, the smugglers' boat; Tamsin's lessons; the cart-horse; the listening-bell item. | M | opening, settlements (braziers, the Lamp's gallery), player-feel (cast and ward objectives, the spell prompts), characters (the cart-horse), cartographer (the ride round the Mere) |
| 5 | **Rogue at Moreva.** The detection states in fog, the strongbox, the tithe-day round; Sauve's lessons; the courier; the bravo's horse. Check the stealth systems first: sneak, backstab and the lock are all in DamageModel and systems/crime. | M-L | opening, settlements (stilts, the strongbox, the round's markers), player-feel (the detection read, the sneak-dagger objective), characters (the bay horse), cartographer (the grey-edge route) |

- **The cartographer's share on every start:**
  - place the tutorial markers and foes on real ground, with the POI camera and frame checks;
  - measure the tie-in's ride (road threats, signposts, gaps);
  - capture the start's first view, the first fight and the ride.
- **The order:**
  - Warrior goes first because it needs the least new.
  - Rogue goes last because its lessons lean on systems (detection in fog, lockpicking) that
    need checking before they are taught.
- **Rough whole:** the frame and four starts come to about 10-14 sessions of work across the five
  areas. Most of it is data and dialogue in the opening's area.

## 7. Open questions for the user

1. **Should the start follow the style, or the Calling?** A Cragborn ranger is a clan-born hunter
   starting at a Woodfolk lodge. **Recommendation:** the style picks the start, and the teacher
   has one line for a Calling from far away ("You're a long way from the fells, Cragborn. The
   wood won't mind.").

2. **What if the player won't go down the stair?** **Recommendation:** they can refuse, and the
   story waits. The thing is gone, and nothing forces the descent. Wren's dialogue offers it
   again ("It's still down there. You're still up here. One of those can change."). The Naming,
   and with it the main thread, starts only on the descent. A player who never goes down plays
   the open world with their style, horse and Calling, which is the user's "free to explore
   instead". The alternative is that Wren describes it and the main thread starts without it,
   but that loses the moment the whole premise stands on.

3. **Are the tie-in rides too long?** They are 4.3 km for the warrior and 7-9 km for the others:
   ten to twenty minutes in the saddle across two or three provinces. **Recommendation:** keep
   them. It is the first long ride and the guided way through the world the user asked for, with
   the fingerposts naming the road and the thread item (the pay, the hart, the bell, the page)
   pulling south. Give each a stop halfway, and one road threat met on the way. The stop is a
   Hearthstone to touch, so the fast-travel lesson lands: Merrowby's for the three western rides,
   and Grandfather Hollow's for the ranger's. It is not Pilgrim's Ash, which the Naming keeps.
   Measure both before each start lands.

4. **Should each start have its own short cinematic before the tutorial?** **Recommendation:**
   yes, 30-40 s and skippable. It uses three or four shots of the region, and the town in the
   same eased style and captioned voice as the opening, spoken by the teacher. It costs little,
   since the cinematic player and the music composer already take shot lists. It keeps the
   Stair Head cinematic special, as the moment everything turns.
