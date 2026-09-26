# Fighting-style starts: the plan

A plan for the user's approval, not code. It carries out DECISIONS 2026-09-25, "A new game
starts with a fighting style's own intro; the Hushline comes after". DESIGN §5.1 and §5.1a will be
rewritten from it once it is approved. Sources:
- DESIGN §5.1 and §5.1a;
- WORLD_BIBLE §1.5, §3, §4 and §6;
- docs/ATLAS.md (settlements and roads);
- `core:quest/the_naming` in quests/main.json, and `core:opening/new_game` in opening.json;
- the NPC defs of the four teachers, who already live where their starts are.

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
1. *The traps before dawn (4 min).* Sauve lifts the North Channel traps, and you follow him
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

## 4. The Stair Head: the descent and the wake

This is shared by all four and built once.
- **The meeting.** The player reaches the camp by the tie-in's road. Wren is at her fire, and
  she greets them as whoever sent them: Dole's recruit, Alder's tracker, Tamsin's girl or boy,
  or nobody she wants to know. That is one line of hers per style, keyed on the style flag. She
  does not give her name ("I'm the Warden. That's all the name the Stair needs."), so the
  cinematic's "The Warden" label still holds.
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
- `GameServices.begin_new_game()` picks the opening whose `style` matches the character.
- The current `core:opening/new_game` stays, as the fallback for a pack with no styles and for
  tests.
- The Stair Head opening cinematic is no longer played by `begin_new_game`. It is played by an
  effect, `{"play_cinematic": "core:cinematic/opening"}`, on the descent's trigger. The skip, the
  setting that turns it off, and the pause menu's *How it began* keep working, because they are
  the player's and not the new game's.

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
  - Her `holds` move from "from the moment a new game is named" to "from `down_the_stair` until
    the Choir".
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

- `style` goes in the character record. The current opening's `holds` state and the new
  descent's progress are quest stages and flags like any other, so they save and load with no
  new machinery.
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
  - test_the_start splits into the Stair Head's own checks (the camp, the stair, the waystones,
    nothing floating), which stay;
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
