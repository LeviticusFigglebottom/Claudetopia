# The Atlas of Wickmere

Wickmere used to come out of a seed. Where the hills went, where the towers stood and how much
empty country lay between them were all the generator's to decide. The playtest put it plainly:
the player was dropped off at the edge of the map into vast hilly nothingness with the odd
tower standing in it, and the seed took the mystique away. This document is the map that
replaces it. Somebody drew it, the way the maps in the games Wickmere wants to stand beside were
drawn: every range, river, road and village is where it is for a reason that can be said.

The map is data in `tools/world/atlas/atlas.json` (the shape is `tools/world/atlas/SCHEMA.md`).
Places and points of interest stay in the content packs, each at its `position`. This document
says what the atlas means and why. Where it and the atlas disagree, the atlas is what gets
built, so change both.

**The drawing:** `docs/atlas/wickmere_atlas.png`. `python3 tools/world/atlas/render_map.py`
draws it from the atlas. With `--world DIR` it draws the heights and water of a world built
from the atlas instead, with each lake's shore where the build put its water. With `--coverage`
it shades the ground that is far from anything, and over a built world it also tints the edge
of each lake that the build left dry.

---

## 1. The shape of it

The Mere is in the middle: a lake three kilometres across with Tollmere on its island, reached
by the Long Stride. The six regions ring it, and each one's ground says which one you are in.

* **North: Skerrow Heights.** A limestone wall of summits along the top edge of the world, a high
  moor under it, and seven dales running down between seven edges to the fells' foot. The
  Skerrow Water comes out of the Hidden Tarn and down Kharrow Gorge to the Mere's Narrows.
* **East: the Briarwold.** Forest rising eastward over granite, from oak in the Lower Wold through
  the ancient Greatwood (the Grandfather stands in it) to the High Wold and the Thornmarch, the
  Briar grown on a granite rampart that closes the east.
* **West: Sedgemire.** The Mere drains west through the Reed Arm and the Eelweir into the Outfall,
  which braids across the delta to the Grey Sea: reed beds, carr, stilt-towns, tideflats.
* **South of the Mere: Hearthvale.** Chalk downs, with the Whitecut standing over the Mere's south
  shore (the white scar the Toll cut when it fell) and the Vale of the Larkbourne running up
  between the downs to the Lark Pool.
* **South-west and south: Cinderlea.** Grey ash heath over the Builders' dead city (the Ashgrid),
  the Choir on its plateau, and the Hushline cliffs where the world ends in mist, which is where
  the game begins.

The four edges close the world as the fiction says (DESIGN §4.2). The Skerrow Wall closes the
north, with the Windgate its one pass. The Thornmarch closes the east. The tideflats run out
into the Grey Sea on the west, and the Hushline cliffs stand over the Hush to the south.

## 2. Size, and whether it is full

The world stays **8192 m square**. It is full at that size, so there is no case for shrinking
it. The figures below are from `tools/world/atlas/preview.py`, the atlas's own coarse reading of
its land: 8 m cells, walkable meaning dry land under about 35° that is below the snowline and
on this side of a closing range's crest.

| | |
|---|---|
| land inside the coast | 61.4 km² (the rest is the Grey Sea and the Hush) |
| open water on land | the Mere 4.7 km², six small waters 0.13 km², fourteen rivers |
| walkable country | **47.2 km²** |
| locations | **320**: 57 places and 263 points of interest (60 places counting the three edge places) |
| quests | **76** authored, 41 of them written with the map (§15): work in every one of the 39 settlements, a quest to each of the other 18 places, and a payoff at each of the 263 points of interest (§16) |
| density | **6.8 locations a walkable km²** |
| distance to the nearest location | mean **180 m**, 95% of the ground within **312 m**, furthest **501 m** (a col on the Wall's face) |
| ground more than 400 m from anything | **0.1%** of the walkable country, in three slivers of under 0.01 km² each |
| roads | 83, **80 km**: 5 highway (3 km), 21 road (25 km), 18 lane (13 km), 36 track (36 km), 2 causeway (1.6 km), 1 stair (0.6 km) |
| road more than 250 m from a location | none further than **289 m** (the Lake Road west of the Stride's Foot) |

The brief's rule was no walkable point more than about 400 m from somewhere notable, and nothing
on a road more than about 250 m. The map keeps both within the "about". Where it overshoots, the
figures above give the worst case. `tools/world/tests/test_atlas_map.py` holds the map to them
with a margin, so a later edit that opens a hole fails a test.

For scale: the walkable country is a little larger than the figure usually quoted for
Oblivion's Cyrodiil (about 41 km²), with somewhat fewer map markers (Wickmere has 6.3 a km²).
Content is densest near the start: 15 locations within 1 km of the Stair Head, 29 within
1.5 km and 45 within 2 km.

## 3. The start

The Foundling comes up out of the Hush by the Hushline Stair. They reach **the Landing**, a
rock shelf 4 m above the sea under the cliff. The stage-two ash-wights are fought there, and
the Oroth stair goes down from its seaward edge into the water and the mist. The Hushline
itself (`core:place/hushline`, the line a pilgrim is walked down to) is on the Landing at
(10, 3870), by the notch where that stair leaves; the grey starts a few paces out. From the Landing
**the Stair** climbs the bank in one long traverse to the rim. **The Stair Head**, the Wardens'
camp, stands at (10, 3670) on the Stair Knoll, about 110 m up over the Hush, facing **333°**.

In a heights build of this atlas, the first view (DESIGN 5.1a) has:

* **a landmark silhouette**: the Sunken Choir's ring of headless colossi on the Choir's Crown,
  483 m ahead and dead on the facing, and the Cantor's Seat's cold light below it (244 m).
* **a road**: the waystones (the Stair Path), which go west from the camp over the neck that
  joins the knoll to the plateau, then up the avenue of colossi past the Cantor's Seat to the
  Choir. It is 560 m, a couple of minutes' walk. It climbs 24 m and never goes down into the
  heath's trough, which it used to cross. That way was 980 m of zigzags down the knoll and back
  up the plateau's scarp. Beyond
  the Choir, the Pilgrim Road comes down off the plateau through the notch in its north lip.
* **smoke and roofs**: Pilgrim's Ash's fires by the Glass Bridge (790 m, 13°), and past them
  Ashwell's roofs, where the green of the Vale begins (1.4 km). Both show over the heath because
  the camp stands on its knoll and the heath's own hills are low.
* **water**: the Hush, behind the player and over the rim. Ahead, the Lark Pool, where the
  Vale's green begins, sits 3 m under the line of sight from the camp and comes into view on the
  way to Pilgrim's Ash. The Glass Falls pour off the far side of the plateau's lip, so the Stair
  Path reaches them before the eye does.
* **within ten minutes' walk**: the Hush Bell on the cliff to the east (650 m, in view), the Bell
  Garden and the Last Camp to the west, the Row of Mouths, the Tenth Waystone, the Thirteenth
  Colossus, and the Last Look, where the downs begin (in view).

On the way, so that no minute of the opening's walk is empty (the survey is in §11):

* **the Turning Cairn** (215, 3720), on the Stair Path's last bend: the bells of pilgrims who went
  down the Stair and came back up, tied silent. The first thing to find on the climb.
* **the Novices' Seats** (-300, 3620), on the plateau's lip west of the camp: three seats facing
  the Hush where the Order's novices count their first night. The view over the grey.
* **the Sweeper's Lean-To** (-60, 2960), on the Choir road between the Choir and the Glass Bridge:
  Arn Sweeting, a pilgrim who came back, sweeps the grey off the road and keeps what his broom
  turns up. He gives **The Swept Road**, and his box has something new each time the main line
  moves on.
* **the Hayward's Perch** (260, 2150), south of Wynstead: a stilt lookout over the common fields,
  the hayward's count of strays cut into its posts.

Walking north, the Pilgrim Road goes from the ash through the Vale (Ashwell, Wynstead, Merrowby)
and down Stride Coombe past the Cracked Toll. It comes out at the Stride's Foot, where the Long
Stride runs out along the Ness and over the last water to the city. The player reaches Tollmere
along the spine of the map, through three regions, in about four kilometres.

## 4. The provinces

Twenty-two provinces make the six regions. A province is one kind of ground: its low ground,
how its hills rise, its landforms and its woods. Borders that are not a ridge, a river or a shore
are drawn ragged, and the builder blends across them, so one country thins into the next over a
few hundred metres instead of stopping at a line.

### Skerrow Heights: bone and slate

*Cold clear light, wind, chains, drystone and turf roofs, holds cut into cliffs, giant bones.*

* **The Skerrow Wall** (mountains, low ground 470 m): a limestone wall of thirteen summits, from
  the Grey Sow in the west to the Last Tooth in the east. Oskeld Crown (790 m) is the highest,
  and the Anvil is a mesa. Ten gills come down its face from the cols between. The **Windgate** is
  the lowest col (478 m), under the Long Snow, reached up the Windgate Cleft from the moor. Snow
  lies above 520 m. It is the north edge of the world, and nothing is asked of anyone past its
  crest.
* **The High Moor** (360 m, rolling): heather, cotton-grass, shakeholes and limestone scars.
  Blackwater Tarn is a ragged peat pool. The Hidden Tarn is a cirque tarn under its back wall,
  where the Skerrow Water rises. The Fallen Hand lies here, palm up, with the Finger Shrine's
  bone in a sinkhole below it. Rudd Pike and Brindle Knott stand over the moor.
* **The Upper Dales** (250 m, hills) and **the Lower Dales** (110 m, rolling): seven edges run
  south off the moor (Oskel, Ghast, Swale, Brindle, Kharrow, Rudd and Rib Edge), each falling
  from about 450 m to nothing at the fells' foot. Between them lie Oskeld Dale, Ghast Dale,
  Swaledale, Brindledale, **Kharrow Gorge** (92 m deep), Ruddale and Ribdale. Each dale has its
  clan: Oskelcrag and Oskeld Mine, Ghastfell, Dreughow, Brindlecrag's headframes, **Kharrow
  Hold** carved into Kharrow Edge's west face across the Chain Bridge, Ruddow, and the Rib
  Cathedral.
* **The Skarl Fells** (280 m, hills): the broad eastern fells under the Skarl Ridge, with
  Skarldale and Skarlow. The Bonefield, the Giants' Stair and Ghorrow, the eighth hold, are
  up here.

**Roads.** The **North Road** leaves the Narrows Bridge, climbs Kharrow Gorge past Kharrow Gate
and the Blood-Price Stones, and reaches the Chain Bridge and the Hold. From there the **Windgate
Track** goes on past Kharrow Force and the Snow Shelter to the Watch of the Gate and the pass.
The **Low Road** runs west along the fells' foot, south of where each edge runs out, from
Kharrow Gate by the Skerr Stone, the Three Sisters, the Clanless Camp, the Drove Chain, Ghastfoot
and the Tinkers' Camp to Oskelcrag, then down the Oskel to the Drowned Nave. The **East Fell
Lane** goes round the foot of Kharrow Edge by Kharrow Foot to Ruddale Bridge, Ruddow and the
Fallen Hand. Tracks climb Ribdale, Skarldale and Ghast Dale.

### Brightwater: lake glass

*High clear light, white lime walls, slate, brass lamps, gulls and buoy-bells.*

* **The Mere and its Shores** (13 m, flat; raised beaches, dune ridges): **the Mere** stands at
  8 m. It is drawn in features of three hundred metres and more, so that it reads on a map. The
  shores have names:
  * **the Narrows**, a funnel up to the Skerrow Water's mouth under the Narrows Bridge;
  * **the Rudd shore** under the Rudd Cliffs;
  * **Smokehouse Bay**, open-mouthed under Merrowhithe, where Rib Beck and the Skarl Water come in;
  * **Holm Point**, a headland reaching for Gull Holm;
  * **the Rafts** at the Wold Water's mouth;
  * **Lime Bay**, as wide as it is deep, with the Cressbourne at its head under the Lime Bridge;
  * **the Lime shore** under the kilns;
  * **the Stride Ness**, half a kilometre of land reaching for the city, with the Ness Market on it
    and the Long Stride along its spine and over the last water to the city's harbour;
  * **Willow Bay**, closed by **Willow Point**, with Willow Isle off its tip;
  * **the Reed Arm**, a funnel narrowing west through the reeds to the Eelweir, where the Mere
    leaves as the Outfall;
  * **Gullhithe's shingle**, and the Lamp on its promontory;
  * **Gull Bay** under the Gull Cliffs.

  **Tollmere's island** has a harbour bight facing the Long Stride. The Spire Rock stands at its
  north-east end, under the Sayers' Spire, and a low tail runs west where the Undercroft has its
  water-gate. The Mere has fallen ten metres since the Toll came down, and its old beaches step
  up the east shore.
* **The North Shore** (26 m, hills): the lake-basin country between the cliffs and the fells.
  The cliff-top road runs behind the Gull Cliffs; the Pilgrim Stair goes down them into the
  water. Merrowhithe smokes its pike in the Standing Arches' last spans. Here too are the
  Counting Tower, the Charter Stone and Brindle Mill.

**Roads.** The **Long Stride** (causeway) runs from the Stride's Foot along the Ness and over the water to the city. The **Lake Road**
goes west by the Larkmouth Bridge, the Wash-Stones, the Tallyman's Folly and Sedgehithe to the
Eelweir. The **west shore road** runs from the Eelweir by the Dry Jetty to Gullhithe. The
**cliff road** goes behind the Gull Cliffs to the Narrows Bridge. The **Rudd road** runs behind
the Rudd Cliffs by the Counting Tower, the Stair Bridge and the Standing Arches to Merrowhithe.
The **east shore road** goes south from Merrowhithe by the Rafters' Camp, the Listening Post and
the Strandline Stones to the Lime Bridge and the Stride's Foot. The Mere can be walked all the
way round.

### Sedgemire: drowned lantern

*Low fog, lantern amber, indigo cloth, stilts and boardwalks, rounds sung across water.*

* **The North Fen** (1.5 m, marsh; oxbows): the Carr and Mormere, a black peat pool. The Oskel
  comes out of its dale here to join the North Channel below **the Drowned Nave**, which leans
  out of the carr. Here too are the Old Crannog, the Drowned Road running into the sea, the
  Grey Gull ashore on the carr's edge, and the Knuckle Cairn where the clans' country ends.
* **The Delta** (1.0 m, marsh; levees, oxbows): the Outfall braids west from the Eelweir. The
  North Channel leaves it at Nauve's Landing, and the Greyreed comes down out of the south.
  **Isseva** is the stilt-town on the Outfall, reached from Nauve's Landing by the Lantern
  Causeway. Moreva, Saeva and Nauvissa are its hamlets. Lissane Mere, Eelfathom Pool, the
  Sallow King and Saoul, the lantern-pool, are here too.
* **The Tideflats** (0.5 m, flat): mud and salt out to the Grey Sea, with Oulea, the Cockle Beds,
  the Salt Pans, the Eel-Boat Graveyard, the Tideflat Stones and the Traders' Post.

**Roads.** The **Westway** comes over from the Vale to the Boardwalk Gate and Nauvissa, then down
to Isseva. A road runs from the Eelweir to Nauve's Landing, and the Lantern Causeway on to Isseva.
The **Channel track** goes by Heron Watch, Moreva and Isse's Stair to the Nave. Tracks go out to
Oulea, Saeva and the Traders' Post.

### The Briarwold: green cathedral

*Dim under canopy, shafts of amber light, colossal trunks, moss, foxglove, the Briar.*

* **The Lower Wold** (70 m, hills; granite stair): the oak wood on the Wold's western slope. Its
  edge is ragged, with tongues reaching down the Wold Water toward the Rafts and outliers
  (Horn Copse, the Spinneys, the Smoke Coppice) standing out on the Brightwater side. In it are
  Hazelwick, Elderhold, the Barkbridge, the Old Quarry and Pellow's Pale.
* **The Greatwood** (150 m, hills; granite stair, tors): the ancient wood. The Wold Water comes
  down the Foxgill past Foxfire Falls and under the Foxgill Arch. Weaverdeep is below Weaver's
  Gill, and Fern Gully is its back door. The Grey Man and Hollin Tor stand in it.

  **Grandfather Hollow** is the town inside the Grandfather. The town and the tree share one
  centre, (2750, 450), in a hollow flat to about 64 m. The tree's model reaches 38.8 m, so the town
  is laid round it:
  * a ring street 48 m out, which the four roads end on;
  * houses on the ring's outer side;
  * a spur on the Vale side (304°) to a door in the trunk's foot at 40 m, into **the Hollow**.

  The Hollow is the first rooms the women planked into the heartwood the winter the tree died.
  Cille Tamwood, the Keeper of Knots, lives there, and the Hearth-Roll lies on the hall shelf, a
  line for every hearth the Hollow has lit. The ring and the spur are the builder's to lay, and
  widening the flat to 72 m wants a pad entry. The fabric already keeps the trunk's footprint
  clear.
* **The High Wold** (232 m, ridged north–south): the rise to the Thornmarch, with Fernhold, the
  Standing Moot on Moot Tor, Rookhold, Wold Force and the Hart Bones. The Woodfolk's gate-stones
  (Hearthstones) stand along the rampart.
* **The Northwold** (170 m, hills; tors): between the Wold and the fells. Ormhold, the Blackgill,
  Harrow Tor, the Wardstone Line and the Silked Camp are here.
* **The Thornmarch**: a granite rampart the length of the east edge with the Briar grown on it,
  sheer on the Wold's side. It closes the east. Its crest wanders between about x 3925 and 4030,
  bellying out and drawing back every few hundred metres, so the face seen from the Wold is a
  broken line and not a ruled one. It keeps 80 m or more clear of everything at its foot. The Briar's End, where it gives out against the
  fells, is walled with bones.

**Roads.** The **Wold Road** runs from Tamwick by the Weighing Stone, the Rod Stacks, the Sawpit and
the Oiled Stone to Grandfather Hollow. The **Wold Water road** goes by Foxfire Falls and Hazelwick
to the Barkbridge and down the north bank to the Rafters' Camp. A lane goes to Fernhold and a
track on to the Thornmarch. The Skarl road runs from Merrowhithe to the Skarl Bridge, and forest
tracks link Elderhold, Rookhold, Ormhold and the Moot.

### Hearthvale: harvest gold

*Warm low sun, chalk white, hedge green, thatch, painted doors, skylarks and a mill wheel.*

* **The Vale of the Larkbourne** (44 m, rolling; lynchets): the Larkbourne rises in the Lark Pool,
  a spring pool under Hound Down held by an old mill-dam, and runs north to fall over the
  Whitecut into the Mere at the Whitecut Falls. On it are Ashwell, Wynstead, **Merrowby** and the
  Cracked Toll, the bronze bell half-buried above the town and seen from the whole Vale.
* **The West Downs** (62 m, rolling; barrows, lynchets): Wardens' Down, with **Wardens' Rest**,
  Pennywort Mill in the Old Bourne, Fallowfold, the Roll Stone and the Tumbled Watchtower.
* **The East Downs** (68 m, rolling; lynchets, barrows): Harewell Down and Barrow Down, with
  Cress Coombe running down to Lime Bay. **Tamwick** is among its orchards, and here too are
  Cressbourne, Hollin Barrow, Hazelcombe, the Singing Yew and Foxglove Dell.
* **Hound Down and the Brow** (96 m, hills; barrows): Hound Down, where the Chalk Hound is cut,
  Bram Down, and the Brow over the Hush cliffs with Beacon Hill (182 m). Bramcombe, Rookdown and
  the Hare and Hurdle are here, and on the cliff edge the Hush Steps and the Cliff Graves.
* **The Whitecut**: the chalk scarp along the Mere's south shore, broken by the Stride Coombe
  (the highway), the Whitecut Falls (a path) and Cress Coombe (a track).

**Roads.** The **Pilgrim Road** (highway) runs down the Vale from the ash to the Mere. The
**Westway** crosses at the Larkbourne Ford by the Roll Stone to Wardens' Rest and on to the
delta, and the **Eastway** goes by the Pinfold and Ansel's Hedge Shrine to Tamwick. The **Brow
road** runs from Pilgrim's Ash by the Last Look, Hound Watch and Bramcombe to Candle Cross and
Rookdown. Lanes cross the downs from Ashwell to the Hare and Hurdle and on to Bramcombe, and from
Tamwick by Hollin Barrow to Hazelcombe.

### Cinderlea: ember ash

*A low sun always near the horizon, ash motes, grey grass, one red poppy, a held note underneath.*

* **The Choir Plateau** (118 m, a level top stepped at its edges): the Choir's Crown, with the
  Sunken Choir's ring round the Cantor's Seat. The Glass Scarp and the North Lip are its northern
  and eastern edges, and the Pilgrim Road comes down through the notch between them. The Glass
  Falls pour off the lip into the Glassbed, the dry bed of fused glass that the Glass Bridge
  crosses. The Row of Mouths runs west into the ash, and the Bell Garden and the Last Camp are
  on the rim.
* **The Ashgrid** (70 m, flat; buried streets): the Builders' dead city, its street grid showing
  through the ash. It holds Greyfold, Bell Street, the Sunk Plaza, Anthem Hall, the Tower of
  Vaelost, the Cistern of Isse, the Weighhouse, the Silent Market, Sulion (the harbour light
  whose stone is in the Lamp), the North Gate and the Builders' Harbour on the cliff. Hesk-Morn
  stands on the rim.
* **The Ash Heath** (62 m, rolling): the grey country from the Vale's border to the sea. Here are
  Pilgrim's Ash, the West Walk, the White Wood of dead ash trees, Hesk Pool (a Builders' basin
  with steps going down), the waystones, the Greyline Stones where the Wardens mark the grey
  each year, and the Hush Bell.
* **The Ash Strand** (14 m, flat): the grey beach on the Grey Sea, with the Grey Wreck, the Strand
  Beacon and the Driftwood Camp.

**Roads.** The **Stair Path** (track) runs from the Stair Head over the neck onto the plateau,
and up the avenue of colossi to the Choir. The **Ash Road**, the
pilgrims' old road, goes from the Glass Bridge by the Tenth and Ninth Waystones, the Ash-Winter
Carts and Hermit's Gate to Greyfold, then on through the dead city by Bell Street, the Weighhouse
and the Cistern of Isse to the Builders' Harbour. The **Wardens' Walk** comes from Wardens' Rest
by the Greyline Stones to the West Walk and on to the Strand Beacon. Tracks run along the rim
from the Choir to the Last Camp and Greywatch, and through the Sunk Plaza to the Tower of Vaelost.

## 5. Water

* **The Mere**, 8 m, 16 m deep. Its shore is §4 above. The reed shore is the west side
  (`reed_shore_deg` 262) and the cliff shore the north (350).
* **Fourteen rivers.** The Skerrow Water, Brindle Beck, Rudd Beck, Rib Beck, the Skarl Water, the
  Wold Water, the Larkbourne and the Cressbourne all run into the Mere. The Outfall runs from it
  to the Grey Sea. The North Channel and the Greyreed are the delta's other channels. The Oskel
  joins another river. The Blackgill ends at its falls, in the Blackgill Pot under them, and goes
  on under the ground; the woodfolk say it comes up in the Mere. Weaver's Gill ends the same way,
  in the Weaver's Linn at the foot of its fall, and Fern Gully below is a dry ravine that holds
  the mist. Every river falls from source to mouth and ends in water (tested).
* **How they bend.** The seven that come down out of the heights fall 10 to 26 in a hundred: the
  Skerrow Water, Brindle Beck, the Oskel, Rudd Beck, Rib Beck, the Skarl Water and the Wold Water.
  Water that steep does not meander, so their bends are drawn, at chart scale: whole swings of
  200 to 650 m, 40 to 170 m out, each put on the side where the ground beside the old line was
  lower, so a river goes round a spur rather than over it. They are 3 to 9 in a hundred longer
  than the straight lines they were, with a point every 150 m or less. Every bridge, ford and fall on the
  water is a fixed point, with 60 m of straight either side, and the last 140 m into the lake
  stays as it was. A drawn point is an exact anchor for the builder, whose own meanders ride on
  top of these and fade to nothing at 15 in a hundred. The slow rivers (the Larkbourne, the
  Cressbourne, the Outfall, the North Channel and the Greyreed, 0.3 to 9 in a hundred) keep their
  drawn lines and the builder meanders them.
* **The small waters**: the Lark Pool (46 m), the Hidden Tarn (520 m), Blackwater Tarn (415 m),
  Hesk Pool (56 m), the Blackgill Pot (189 m), the Weaver's Linn (113 m), Mormere and Lissane
  Mere (a hand over the fen). Each is drawn to its setting:
  a millpond held by its dam, a cirque tarn under its back wall, a peat pool eaten ragged by the
  hags, a Builders' basin square once with steps down one side, a black pool in the carr, a reed
  mere in lobes.
* **The coast**: the Grey Sea on the west, the Hush on the south. The cliffs are 112 m under the
  Brow, 78 m under the heath at the Stair, 66 m under the Ashgrid, 24 m at the Ash Strand and
  95 m on Skerrow's sea-cliffs. The shore is broken at a walker's scale everywhere except at the
  Stair Head, where the rim is drawn exactly.

## 6. Ranges, peaks and passes

There are 21 ranges and 22 peaks. The Wall's thirteen summits and its cols are above. The
Skerrow edges each have a knoll and a saddle along them rather than a ruled fall. There is the
Skarl Ridge. The Gull and Rudd Cliffs are scarps facing the Mere. The Whitecut is a scarp facing
the Mere, never lower than the downs behind it. Wardens' Down, Hound Down, Harewell Down, Barrow
Down, Bram Down and the Brow are rounded chalk downs. The Glass Scarp and the North Lip are
fused-stone scarps. The Thornmarch is a granite rampart. The tors are the Grey Man, Hollin Tor,
Harrow Tor and Moot Tor.

There are two passes. The Windgate (478 m) goes out of the world. The Stride Coombe carries the
Pilgrim Road down through the Whitecut to the Mere. The coombes (Stride, Cress, Watch), the gills
and the dales are valleys drawn so that roads and rivers have somewhere to go.

## 7. Borders

A region's border is where the ground changes, not a line. The chalk thins into the grey over the
Greyline Stones. The downs give way to the Wold at the Hare Stone, where Vale folk touch the hare
and Woodfolk the leaf. The Mere's reed shore becomes the delta at the Eelweir. The fells' foot is
the Low Road and the Skerr Stone. The Briarwold's edge on the Brightwater side goes in and out
with the woods. Every border that is not a ridge, a river or a shore is drawn with a pen's wobble
at a few hundred metres. Neighbouring provinces share their border point for point, so the region
the game reads underfoot is the one the map shows.

## 8. What moved

Everything that existed is still there under the same id. The 34 places and 49 points of
interest were all moved to where this map puts them, and none was deleted or renamed. The door
plans moved with their places. The table is in §12.

## 9. What is new

There are 26 new places: hamlets, lodges, a fort and a camp, each with the one person who lives
there, written with a schedule, a dialogue and a habit of their own. There are 191 new points of
interest: 53 ruins, 39 camps, 29 standing stones, 23 towers, 18 bridges, 13 shrines, 6
waterfalls, 6 giant bones and 4 wrecks. With the older ones that makes 22 Hearthstones. Each
has a name in its culture's language, a feature no other location shares, a story, and one line
of the quest or story it could anchor, which is in the tables below. Hooks are hooks: no quest
is written.

Every kind is one the POI dressing kit already builds, and the unique features are worded so
that its variants pick the right dressing: a "mill wheel" gets the mill, "stilts" the stilt
tower, "steps" the processional ruin, "seven" the seven-stone ring, "chain" the chain bridge or
the wind-chime camp, "boardwalk" the boardwalk, "barrow" or "grave" the barrow. Kinds the map
would still like the kit to build (with how they are faked today) are in §10.

## 10. The kinds the map asked for

The eight kinds the drawn map wanted and faked are built (`PoiDressing.KINDS`, the settlements
branch), and the map now uses them:

* **cave**: a mouth facing downhill with ten metres of dark behind it. Kharrow Hole in the dale
  side above Kharrow Foot (limestone), the Root Hollow under a fallen oak by the ridge road
  (Briarwold), and the Tide Mouth, a sea-cave at the cliff foot west of the Landing, on a shelf
  its own pad raises over the water at 4 m, as the Landing's does.
* **farmstead**: a lived-in house, barn, yard and well, a pace off the road. Twelve in the Vale:
  Hurdlegate, Brow End, Hatchmoor, Coldharbour, Pennywort Fields, Ashway, the Last Farm at the
  Grey End, Southgate, Ridgeway, Fallowgate, Larkfield and Hazel Bottom, on ground under 6
  degrees and 180 m clear of anything.
* **mill**: a wheel in a stone leat, or a windmill where its sentence says sails. Cress Mill, Lark
  Mill, Skarl Mill and Rudd Mill, each within 30 m of its river by a hamlet; Rook Mill and
  Brindle Mill are mills now.
* **waystone**: the Tenth Waystone and the Skerr Stone (broken).
* **market field**: Kharrow Foot.
* **quarry**: the Chalk Pit, the Flint Pits and the Old Quarry. The Oskel Rake stays ruins: a
  mile-long trench is not a face.
* **shieling**: Skarl Shieling and Oskel Shieling.
* **vista**: the Last Look, with a pilgrims' bench beside its leaning stone.

Every new place has a note lying there in the voice of whoever keeps it (§16).

## 11. For the builder

* **The landing under the Stair Head** is drawn with the fields agreed with the land builder.
  `coast.shelves` holds the shelf at 4 m, with a 90 m bank down to it from the rim. The coast
  polygon carries a lobe over the bank, with a 4 m cliff along its seaward edge and the 78 m
  cliffs split around it. The road `core:road/stair_head_hushline_stair` is of kind "stair",
  and the opening's camp builder looks for that id. A pad pins core:poi/hushline_stair to the
  shelf at 4 m (radius 26), and another pins core:place/hushline beside it at 4 m (radius 20),
  so the line an escort ends at is on the Landing and not on an islet in the Hush. The Stair is one traverse at about 77° to the fall line, turning
  only at the rim and at the bank's foot. On a 1024 heights build it is nowhere steeper than
  about 0.6. Three switchbacks were tried first; their corners sat mid-bank and ran 1.6 there.
  Drawn, the shelf's seaward edge is a smooth arc, and the builder breaks it up. Spurs and bites
  take the edge up to 7 m in and out, and blocks fallen from the face lie in the water at its
  foot. A notch is cut where the Oroth stair leaves the shelf (`coast.shelves[].notches`, one at
  (44, 3902), on the line from the Stair Head through the Stair's pad).
* **The Stair Knoll** (a 110 m dome under the camp) is what lets the first view see over the
  heath. The heath's own relief is kept low (18 m) for the same reason.
* **A lake's water stands about 36 m inside its polygon** (24 to 56 m on a 1024 build), because
  the builder raises the shore there. A cove drawn narrower than about a hundred metres closes up
  and leaves a round bump in the built shore. The Mere was once drawn with many small coves,
  and its built shore came out scalloped. So the lakes are drawn in features of three hundred
  metres and more. The polygon's line is the landward edge of the shore, and the water begins
  about 36 m inside it.
* **Valleys are cut relative to the ground,** so a dale's valley stops where the dale does. The
  Oskeld Dale once ran out onto the fen and cut 70 m below the sea there.
* **The High Moor is rolling, not a plateau.** A stepped plateau stood 250 m over the dale heads,
  and the Windgate Track had to climb Kharrow Edge to get up it.
* **Buried streets are the Ashgrid's alone.** On the open heath and the Choir's precinct they read
  as graph paper.
* **Sightlines.** A new point of interest claims to be seen from somewhere only where it plainly
  is: the Hush Bell from the Stair Head. The moved points of interest keep claims that were
  checked against the preview's land. `tools/world/tests/test_sightlines.py` checks them all
  against the built world once it is rebuilt. The first 4096 build of the atlas (w_final4)
  refused 28 of 201 lines. Each was answered against that build's ground, measured the way the
  game sees and the way the builder cuts. In 24 lines the vantage is now one that sees the place
  clear without a cut. Kharrow Force sees the Chain Bridge, for one, and Harrow Tor sees the
  Northgate Stone and the Skarl Bridge. Two places moved to where their lines hold: Ghorrow
  85 m up the cliff to (2025, -3335), where the Fallen Hand sees it, and the Smeltings 67 m down
  the slope to (-790, -2480), in Brindlecrag's view. Two lines had no vantage anywhere in sight
  range and were dropped. Those places keep a line that holds: Dreughow for the Clanless Camp, the
  Seven Stones for the Snow Shelter. That leaves 199 lines, none refused.

### The opening's walk, minute by minute

The walk from the Hushline Stair to Merrowby is 5.7 km, 19 minutes at a jog (300 m a minute).
Surveyed on the rebuilt atlas world (atlas e11343a1) with the game's own sightline model:

* Something authored is in sight within 700 m at every 75 m of the road.
* No dry ground within 2 km of it is 450 m from anything authored.

Before the places above it had three thin stretches:

* **Minute 7**, from the Choir to the Glass Bridge: nothing new to find and nobody. The Sweeper's
  Lean-To is there now.
* **Minutes 11 to 14**: the Pilgrim's Ash road climbed to a via point on a knoll 60 m over the
  valley and came back the same way, 2197 m for a hop of 590 m. Its via now keeps to the valley
  floor past the Wellspring.
* **Minute 17**, from Ashwell to Wynstead: two things in sight. The Hayward's Perch is there now.

The skyline the survey reports, such as Merrowby from the Stair Head and the Grandfather from
above Pilgrim's Ash, is the model's answer. The game builds only the streamed ring, so it is not
on screen past about 0.6 km. `docs/HORIZON.md` is the list a horizon layer draws from.

## 12. The tables

### What moved

| Id | Was at | Now at | Province |
|---|---|---|---|
| `core:place/merrowby` | 900, 2350 | 250, 1330 | The Vale of the Larkbourne |
| `core:place/tamwick` | 1900, 2900 | 1300, 1420 | The East Downs |
| `core:place/wardens_rest` | 300, 3100 | -700, 1640 | The West Downs |
| `core:place/hollin_barrow` | 1700, 1900 | 1750, 1960 | The East Downs |
| `core:place/pennywort_mill` | 600, 1900 | -450, 1230 | The West Downs |
| `core:place/chalk_hound` | 1400, 3300 | 500, 2150 | Hound Down and the Brow |
| `core:place/cracked_toll` | 1000, 2150 | 190, 1130 | The Vale of the Larkbourne |
| `core:poi/larkbourne_ford` | 729, 2314 | -30, 1520 | The Vale of the Larkbourne |
| `core:poi/hedge_shrine_of_ansel` | 1300, 2580 | 780, 1560 | The East Downs |
| `core:poi/tumbled_watchtower` | 320, 2120 | -1000, 1420 | The West Downs |
| `core:poi/gosling_pit` | 1600, 3150 | 430, 2280 | The Vale of the Larkbourne |
| `core:poi/singing_yew` | 1900, 2300 | 1520, 1720 | The East Downs |
| `core:poi/whitecut_falls` | 700, 1300 | -40, 990 | The Vale of the Larkbourne |
| `core:poi/bell_meadow_stones` | 1120, 2090 | 420, 1090 | The Vale of the Larkbourne |
| `core:poi/foxglove_dell` | 2200, 2500 | 1880, 1640 | The East Downs |
| `core:place/pilgrims_ash` | -1500, 2200 | 190, 2900 | The Ash Heath |
| `core:place/greyfold` | -2300, 2900 | -1750, 2650 | The Ashgrid |
| `core:place/sunken_choir` | -1900, 3300 | -210, 3240 | The Choir Plateau |
| `core:place/cantors_seat` | -1900, 3500 | -130, 3470 | The Choir Plateau |
| `core:place/hushline` | -1900, 4000 | 10, 3870 | The Ash Heath |
| `core:poi/glass_bridge` | -1700, 2450 | 60, 2860 | The Ash Heath |
| `core:poi/bell_of_the_pilgrims` | -1320, 2500 | 270, 2720 | The Ash Heath |
| `core:poi/headless_watch` | -2120, 3200 | -750, 2990 | The Choir Plateau |
| `core:poi/the_one_poppy` | -2500, 2500 | -1150, 3200 | The Ashgrid |
| `core:poi/thirteenth_colossus` | -1480, 3280 | 380, 3060 | The Ash Heath |
| `core:poi/cold_fire_camp` | -2260, 2760 | -1600, 2830 | The Ashgrid |
| `core:poi/glass_falls` | -1860, 3030 | -80, 3030 | The Ash Heath |
| `core:poi/hushline_stair` | -1900, 3900 | 40, 3872 | The Ash Heath |
| `core:poi/stair_head` | -1922, 3708 | 10, 3670 | The Ash Heath |
| `core:place/tollmere` | 0, -150 | 40, -300 | The Mere and its Shores |
| `core:place/gullhithe` | 1500, -900 | -1300, -960 | The Mere and its Shores |
| `core:place/the_lamp` | 1750, -1250 | -1060, -1115 | The Mere and its Shores |
| `core:place/sayers_spire` | 60, -230 | 120, -390 | The Mere and its Shores |
| `core:place/undercroft` | -80, -100 | -40, -240 | The Mere and its Shores |
| `core:place/sunken_barge` | -700, -700 | -700, -1320 | The North Shore |
| `core:poi/long_stride` | 0, 600 | 62, 60 | The Mere and its Shores |
| `core:poi/shingle_shrine` | 300, 1100 | -215, -1865 | The North Shore |
| `core:poi/north_cliff_beacon` | -580, -1520 | -560, -1470 | The North Shore |
| `core:poi/gullhithe_wreck` | 1700, -700 | -1310, -880 | The Mere and its Shores |
| `core:poi/eelweir` | -1400, -100 | -1620, -275 | The Mere and its Shores |
| `core:poi/pilgrim_stair` | 1300, -200 | -760, -1330 | The North Shore |
| `core:poi/willow_isle` | -520, 200 | -590, 240 | The Mere and its Shores |
| `core:poi/buoy_bell_field` | 600, -600 | 560, -700 | The Mere and its Shores |
| `core:place/isseva` | -2900, -500 | -2600, 50 | The Delta |
| `core:place/nauves_landing` | -2200, 200 | -2140, -190 | The Delta |
| `core:place/drowned_nave` | -3500, -1300 | -3300, -1420 | The North Fen |
| `core:place/eelfathom` | -2500, -1400 | -2330, -980 | The Delta |
| `core:poi/lantern_causeway` | -2550, -150 | -2380, -40 | The Delta |
| `core:poi/drowned_bell_shrine` | -2800, -900 | -2880, -330 | The Delta |
| `core:poi/sallow_king` | -3300, 0 | -3230, 180 | The Delta |
| `core:poi/reed_wreck` | -3700, -500 | -3000, 700 | The Delta |
| `core:poi/stair_of_isse` | -3300, -1100 | -3120, -1180 | The North Fen |
| `core:poi/wisp_hollow` | -2300, -800 | -2950, -780 | The Delta |
| `core:poi/tideflat_stones` | -3900, -200 | -3790, 450 | The Tideflats |
| `core:poi/heron_watch` | -2100, -400 | -2442, -660 | The Delta |
| `core:place/grandfather_hollow` | 3000, 250 | 2750, 450 | The Greatwood |
| `core:place/grandfather` | 3000, 250 | 2750, 450 | The Greatwood |
| `core:place/fernhold` | 2300, 1100 | 3350, 230 | The High Wold |
| `core:place/standing_moot` | 3600, 1400 | 3470, 1200 | The High Wold |
| `core:place/weaverdeep` | 3400, -700 | 2990, 150 | The Greatwood |
| `core:place/thornmarch` | 4000, 0 | 3880, 100 | The High Wold |
| `core:poi/mossbridge` | 2600, 480 | 2180, 720 | The Lower Wold |
| `core:poi/oiled_stone_shrine` | 2800, 900 | 2420, 880 | The Greatwood |
| `core:poi/hunters_stand` | 3300, 900 | 3120, 1000 | The Greatwood |
| `core:poi/foxfire_falls` | 2540, -220 | 2460, 245 | The Greatwood |
| `core:poi/hart_bones` | 3480, 660 | 3560, 780 | The High Wold |
| `core:poi/briar_breach` | 3990, -240 | 3880, 520 | The High Wold |
| `core:poi/charcoal_camp` | 2700, -100 | 2770, 680 | The Greatwood |
| `core:poi/fern_gully` | 3500, -1000 | 3150, -180 | The Greatwood |
| `core:place/kharrow_hold` | 400, -2700 | 300, -2740 | The Upper Dales |
| `core:place/brindlecrag` | -900, -2500 | -880, -2660 | The Upper Dales |
| `core:place/fallen_hand` | 1200, -3300 | 900, -3230 | The High Moor |
| `core:place/oskeld_mine` | -600, -3200 | -2680, -3100 | The Upper Dales |
| `core:place/frostmothers_cradle` | 800, -3800 | 470, -3790 | The Skerrow Wall |
| `core:place/windgate` | 200, -4000 | -230, -3990 | The Skerrow Wall |
| `core:poi/chain_bridge` | 250, -2580 | 150, -2640 | The Upper Dales |
| `core:poi/rib_cathedral` | 1000, -2940 | 1380, -2720 | The Upper Dales |
| `core:poi/three_sisters_falls` | -300, -2800 | -1100, -2220 | The Lower Dales |
| `core:poi/clanless_camp` | -1300, -3100 | -1520, -2270 | The Lower Dales |
| `core:poi/sinkhole_shrine` | 600, -3100 | 1060, -3010 | The Upper Dales |
| `core:poi/watch_of_the_gate` | 370, -3850 | -220, -3820 | The Skerrow Wall |
| `core:poi/lichen_stones` | -40, -3520 | -520, -3400 | The High Moor |
| `core:poi/hidden_tarn` | 700, -3600 | 395, -3530 | The High Moor |

### Every new location, and the story it could anchor

The places (with their residents) are in bold. "Where" gives the province and the position. §16
ties each hook to the ids that pay it off in the game.

#### Hearthvale (60 new)

| Location | Kind | Where | The story it anchors |
|---|---|---|---|
| Bramcombe | **hamlet** | Hound Down and the Brow (1650, 2780) | Every tally in the combe is one sheep short every morning, and no sheep is missing. |
| Rookdown | **hamlet** | Hound Down and the Brow (2760, 3280) | The grey patch on the green has reached the well: half the village wants to leave and half says leaving is how a village goes quiet, and they want somebody from outside to say which half is right. |
| The Hare and Hurdle | **lodge** | Hound Down and the Brow (1480, 2330) | The innkeeper's board of who owes whom a drink has one debt on it, in chalk that will not rub off, owed to a man nobody can remember. |
| Candle Cross | shrine, Hearthstone | Hound Down and the Brow (2230, 3160) | A candle has been burning in the north niche since midsummer, and it has not got any shorter. |
| Hanging Coombe | camp | Hound Down and the Brow (3150, 2700) | Take the boundary-bells back to their hedges; one of the hedges no longer bounds anything. |
| Hound Watch | tower | Hound Down and the Brow (900, 2760) | The keeper has started ringing the alarm at the colossi. He says they moved. |
| Hurdle Fold | camp | Hound Down and the Brow (2250, 2620) | The wolves have learned the lantern; the shepherds want somebody to sit the night with them and the crook. |
| Hushwatch | stones | Hound Down and the Brow (1500, 3690) | A child said a name between the stones that nobody in the Vale knows, and the name is on the Wardens' deep lines. |
| Lamb's Bottom | ruins | Hound Down and the Brow (1150, 3020) | A bounty on the Lamb's Bottom pack, and in the hut a crook carved with a name the Roll struck. |
| Rook Mill | camp | Hound Down and the Brow (3080, 3460) | Flour has been found on the mill floor, fine and grey, and it tastes of ash. |
| Tallow Barrow | ruins | Hound Down and the Brow (2850, 2150) | The new wall has a door-shaped gap in it this spring, and the chalk round the gap is warm. |
| The Brow Beacon | tower | Hound Down and the Brow (2420, 3540) | Lit twice this spring by a keeper who swears the Hush came up the cliff like a tide and went back down. |
| The Chalk Pit | camp | Hound Down and the Brow (2700, 2550) | A pick was found standing in the chalk face this spring with a Tallyman's mark on the haft. |
| The Cliff Graves | ruins | Hound Down and the Brow (2950, 3760) | One headstone has turned in the night to face inland. |
| The Cliff Hearth | shrine, Hearthstone | Hound Down and the Brow (3700, 3100) | The ash was warm on the morning the Foundling came up the Stair, and nobody on the Brow had lit it. |
| The Dewpond Fold | camp | Hound Down and the Brow (1000, 2200) | On still nights the dew pond shows the stars at noon, and the shepherds have stopped mentioning it. |
| The Flint Pits | camp | Hound Down and the Brow (1250, 3350) | The deepest shaft rings when struck; the knappers want a Sayer, a Warden or anyone braver than them to go down. |
| The Grey End | ruins | Hound Down and the Brow (3860, 3700) | Both Briar pamphleteers want a grey thorn from the Grey End as evidence, for opposite reasons. |
| The Hush Steps | ruins | Hound Down and the Brow (2000, 3750) | A lit lantern has been left on the last step, tied with a Sedgish lantern-knot. |
| The Lambing Fold | camp | Hound Down and the Brow (2950, 2950) | A lamb was born in the fold this spring with a face as grey as ash, and the ewe that bore it belongs to nobody. |
| The Last Field | ruins | Hound Down and the Brow (3420, 3610) | The plough has moved a furrow since the Southcotes left it. |
| The Last Look | stones | Hound Down and the Brow (610, 2840) | The stone leans a little further toward the Choir every year; this year it moved a hand's breadth in one night. |
| The Naming Stone | shrine, Hearthstone | Hound Down and the Brow (1820, 3050) | The stone has a name worn into it that no child on the Brow was ever given. |
| The Southgate Stone | shrine, Hearthstone | Hound Down and the Brow (3820, 2560) | Someone has been leaving the south gate unbarred at night, from the inside. |
| The Turned Hut | ruins | Hound Down and the Brow (800, 3300) | There is fresh straw in the hut, and the ash round the door has been swept. |
| The Warrener's Camp | camp | Hound Down and the Brow (3450, 2250) | The ferrets will not go down one burrow, and every rabbit on the down comes out of it. |
| Cressbourne | **hamlet** | The East Downs (1120, 1190) | The top bed came up grey overnight, and the Cresswells want to know whether it is the water, the chalk or the Toll before the city tastes it. |
| Hazelcombe | **hamlet** | The East Downs (2250, 1850) | The Wardens have ordered a mile of hurdles for new pens on the grey border, and the weavers want to know what the pens are for before they weave them. |
| Orm's Long Barrow | ruins | The East Downs (2080, 2100) | The robbers left a roll in the cist older than the Wardens' own, and Tamwick is on it twice. |
| The Cress Bridge | bridge | The East Downs (1160, 1450) | Somebody is taking the coins, one a night, and the Cressbourne has started to run low. |
| The Hare Stone | stones | The East Downs (2650, 1700) | Somebody has cut a third mark on the top of the stone overnight, a bell, and left the chisel in the grass. |
| The Rod Stacks | camp | The East Downs (2000, 1250) | The Woodfolk have stopped selling the Vale its rods, and the cutters want to know who in the Wold is saying no, and why. |
| The Weighing Stone | stones | The East Downs (1700, 1260) | Dorrie's slate says the ridge road has eaten a cart and a half of goods in twenty years; the beam says it has not. |
| Ashwell | **hamlet** | The Vale of the Larkbourne (330, 2330) | The notch on the well-house post is above last year's for the first time in a century, and the well-warden wants someone to walk the glass bed to the Choir and say why. |
| Wynstead | **hamlet** | The Vale of the Larkbourne (190, 1870) | Someone has been opening the sluices at night, and the flood is drowning the lane where Gosford's name used to be; the sluice-keeper thinks that is the point. |
| Pennywort Bridge | bridge | The Vale of the Larkbourne (-58, 1270) | The cracked millstone has turned a quarter in the parapet, and there is fresh mortar dust in the road. |
| The Old Sheepwash | ruins | The Vale of the Larkbourne (-230, 1950) | The spring is moving again, a yard a day, toward Fallowfold's gate. |
| The Hayward's Perch | tower | The Vale of the Larkbourne (260, 2150) | The newest cut on the south post is a notch under and a notch over, and the hayward says he did not cut it. |
| The Pinfold | ruins | The Vale of the Larkbourne (520, 1450) | Every morning there is one more sheep in the Pinfold than anybody put there, and nobody in the Vale will own it. |
| The Wellspring | shrine, Hearthstone | The Vale of the Larkbourne (215, 2578) | A pilgrim's flask comes back up the glass bed full, and the woman who filled it is written on the Chapter Roll as gone on. |
| Fallowfold | **hamlet** | The West Downs (-620, 2080) | A ewe came back from the south pasture grey to the skin and will not go into the pond; the shepherd wants her named, and does not know by whom. |
| Ash Watch | tower | The West Downs (-380, 2310) | The beacon was lit last night and nobody on the Ash Watch roll admits to lighting it. |
| The Chalk Cell | ruins | The West Downs (-1150, 1050) | Bread left at the cell's door is being taken again, after thirty years. |
| The Roll Stone | stones | The West Downs (-360, 1600) | A fifth name has been cut beneath the four in a Warden's hand, and struck through, and nobody at the Rest will say whose. |
| The Warden Barrow | ruins | The West Downs (-1150, 1900) | The youngest at the Rest has stopped ringing the bells, because one of them rings back. |
| Wolf Holt | ruins | The West Downs (-1450, 1350) | The pack's leader wears a Warden's collar-bell, and the Wardens would like to know whose. |
| Hurdlegate Farm | farmstead | (749, 2302) | Somebody has been sleeping in the hay-loft and leaving the eggs they did not eat in a neat row on the sill. |
| Brow End | farmstead | (2496, 3185) | The byre door has been painted again overnight, red over red, and the pot is not the farm's. |
| Hatchmoor | farmstead | (1537, 2554) | A dove came home to the cote this week wearing the ring of a beacon that has not been manned in forty years. |
| Coldharbour | farmstead | (1674, 2137) | The stone put back last Tollday was back in the farm wall by morning. |
| Pennywort Fields | farmstead | (-250, 1240) | The door-quern has been turning at night, and in the morning there is cold flour in the trough and no grain gone from the store. |
| Ashway Farm | farmstead | (1390, 2927) | This spring the last furrow was ploughed, and the grey was on the near side of it in the morning. |
| The Last Farm | farmstead | (3644, 3679) | The lamp was found out one morning and the window open, and Maud says she did not open it. |
| Southgate Farm | farmstead | (3272, 2444) | A drover watered his beasts at the trough last week and paid with news of a village nobody has heard of. |
| Ridgeway Farm | farmstead | (2332, 1564) | The oak at the Wold end of the yard has started putting out Vale apple blossom. |
| Fallowgate | farmstead | (-407, 2051) | The fallow field has come up in wheat on its own this spring, in straight drills, as if sown. |
| Larkfield | farmstead | (174, 1642) | There are two nests in the ring this spring, and the second one is empty and warm. |
| Hazel Bottom | farmstead | (1945, 1950) | A stretch of hedge has been laid overnight, beautifully, in a style the family's grandmother said died with her grandmother. |
| Cress Mill | mill | (961, 1029) | The wheel has been turning backward at night, against the water, and the barley in the hopper comes out as whole grain. |
| Lark Mill | mill | (83, 1715) | The mill's water-clock has started keeping a different hour from the Toll's, a quarter behind, and the Larkbourne has risen to match it. |

#### Cinderlea (37 new)

| Location | Kind | Where | The story it anchors |
|---|---|---|---|
| The West Walk | **fort** | The Ash Heath (-2250, 2150) | Someone has been working Ossel's forge at night, and what they are making is a bell-bearer's clapper. |
| Ashcombe | ruins | The Ash Heath (-2800, 1780) | Put Ashcombe back on the Roll: find a name for each house, one chimney at a time. |
| The Ash-Winter Carts | ruins | The Ash Heath (-950, 2450) | The carter's day-book lists a delivery to Greyfold made after the village had walked south. |
| The Bell Pit | ruins | The Ash Heath (-2750, 2250) | One of the buried bells has been dug up in the night, hung from a dead tree, and rung once. |
| The Bell Wood Stone | shrine, Hearthstone | The Ash Heath (-2350, 1950) | Every bell in the wood is a person: the Wardens want the names written down, and the Order says the bells already are the names. |
| The Driftwood Camp | camp | The Ash Heath (-3250, 1890) | The sea brought in a Tollmere barge last week with her cargo sealed and her crew gone. |
| The Grey Hedge | ruins | The Ash Heath (-1950, 1900) | One hawthorn in the grey hedge has come into leaf. |
| The Greyline Stones | stones | The Ash Heath (-1620, 1960) | This year's stone was set in front of last year's: the ash has gone back. |
| The Hush Bell | tower | The Ash Heath (660, 3700) | The bell has been rung: the rope is new, and wet with sea-water. |
| The Last Hearth | shrine, Hearthstone | The Ash Heath (-1350, 2300) | The chalk the fire is banked with has turned grey overnight, right through. |
| The Ninth Waystone | stones | The Ash Heath (-620, 2560) | The bell-counts on the stone stop in 1024 and start again this spring, in a hand the Order does not know. |
| The Tenth Waystone | stones | The Ash Heath (-280, 2700) | The coins taken from the tenth waystone turn up in the fire at the Stair Head, melted. |
| The Turning Cairn | shrine | The Ash Heath (215, 3720) | One bell on the cairn has been untied, and it has been rung: the thread lies on the stones beside it, cut clean. |
| The Builders' Harbour | ruins | The Ash Strand (-3480, 2980) | The harbour bells rang last night; the reedfolk say a Salt Isles ship is due, and none has been seen in forty years. |
| The Grey Wreck | wreck | The Ash Strand (-3500, 2420) | The barge's chart has the Salt Isles on it, and a line ruled from them to the Choir. |
| The Strand Beacon | tower | The Ash Strand (-3420, 1950) | Sit a night at the Strand Beacon and see who lights it. |
| Bell Street | ruins | The Ashgrid (-2050, 2980) | The bell that is not hollow: a Sayer wants it measured, the Order wants it left alone. |
| Greywatch | stones | The Ashgrid (-1600, 3700) | A name has been read at Greywatch every night for a month that is on no Chapter Roll. |
| Hesk Pool | ruins | The Ashgrid (-2000, 2380) | The Sayers say Hesk Pool and Eelfathom are the same water, and that something stands in between. |
| Hesk-Morn | ruins | The Ashgrid (-1150, 3700) | The door has been found open, and the ash beyond it holds footprints that walk out onto the air. |
| Sulion | tower | The Ashgrid (-3120, 3080) | The empty socket glows on moonless nights, and on those nights the Lamp at Gullhithe dims. |
| The Anthem Hall | ruins | The Ashgrid (-1850, 3500) | A lecture given here reaches the whole heath; the Circle would like to give one, and the Order would like them not to. |
| The Cistern of Isse | ruins | The Ashgrid (-2750, 3150) | Carry water from the Wellspring down the stair: something at the bottom wants to know whether it is still water. |
| The Hermit's Gate | ruins | The Ashgrid (-1250, 2750) | The hermit says the door opens for a name, as the Undercroft's does, and he has been trying names for thirty years. |
| The Kneeling Colossus | ruins | The Ashgrid (-2300, 3620) | The Thirteenth's diggers want to dig this one too; the Order says a thing covering its ears has earned being left alone. |
| The Last Milestone | stones | The Ashgrid (-2950, 2650) | Walk the road the milestones count down and find the Builders' Harbour on the strand. |
| The North Gate | ruins | The Ashgrid (-2450, 2600) | Something passes through the gate at the same hour every night, leaving the ash disturbed and no tracks. |
| The Silent Market | ruins | The Ashgrid (-3100, 3450) | One stall at the edge of the square has fresh goods on it every morning: bread, a knife, a child's shoe. |
| The Sunk Plaza | ruins | The Ashgrid (-1600, 3280) | The Order counts the fountain's bells every spring, and this year there is one more bell than there were pilgrims. |
| The Tower of Vaelost | tower | The Ashgrid (-2550, 3350) | The top course has a name cut in it, and the Order will pay to know whose. |
| The Weighhouse | ruins | The Ashgrid (-2450, 3080) | The scales have moved: the other pan is down now. |
| The Last Camp | **camp** | The Choir Plateau (-700, 3660) | A pilgrim who has waited three years asks for the one thing she has not been able to find out: whether anybody would say her name if she stayed. |
| The Bell Garden | ruins | The Choir Plateau (-650, 3480) | Struck in the right order the garden plays a line, and the Cantor's Seat's door answers it. |
| The Row of Mouths | ruins | The Choir Plateau (-530, 3210) | At dusk one mouth is heard singing a single note, a different pillar every night, and the Order is counting which. |
| The Tide Mouth | cave | (-601, 3780) | The tide went out this morning and left a pilgrim's bell on the shell sand, clapper tied, with no name on it. |

| The Novices' Seats | stones | The Choir Plateau (-300, 3620) | One of the seats has been turned in the night to face the Choir, and it is a single stone the size of a cart. |
| The Sweeper's Lean-To | camp | The Choir Plateau (-60, 2960) | The broom turned up a hand-bell with a name scratched on it, and the name is not a pilgrim's. |

#### Brightwater (28 new)

| Location | Kind | Where | The story it anchors |
|---|---|---|---|
| Sedgehithe | **hamlet** | The Mere and its Shores (-1290, 170) | The reed fringe is dying back from the shore in a straight line, as if something were drawing a rule across the water. |
| Stride's Foot | **hamlet** | The Mere and its Shores (180, 800) | One traveller a week is entered in the toll-ledger going out to the city and never coming back, always in the same hand, and the hand is not a clerk's. |
| Gull Holm | ruins | The Mere and its Shores (1100, -980) | The egg-collectors bring back one egg a year that is warm, from a room with no nest in it. |
| The Beached Barge | wreck | The Mere and its Shores (1580, -900) | The oak growing through the hold is older than the barge. |
| The Dry Jetty | bridge | The Mere and its Shores (-1540, -600) | Every morning this spring the jetty's last pile has been wet to the knee, and the field round it dry. |
| The Heronry | tower | The Mere and its Shores (-1500, 800) | The herons have left all at once, in the middle of the nesting, and flown west. |
| The Larkmouth Bridge | bridge | The Mere and its Shores (-90, 790) | Somebody sits on the bench every night until dawn, and the old men will only say that he is waiting for the city's lamps to go out. |
| The Lime Bridge | bridge | The Mere and its Shores (945, 745) | This spring the bridge came up grey under the whitewash, like the third kiln's lime, and the white will not take. |
| The Limekilns | camp | The Mere and its Shores (650, 840) | The lime from the third kiln has come out grey, and the Tallymen want to know whether they can still sell it. |
| The Listening Post | tower | The Mere and its Shores (1430, 120) | The clerk says the hum changed pitch on the night the Foundling came up the Stair. |
| The Log Boom | bridge | The Mere and its Shores (1760, -205) | A raft was let go with nobody on it, and it went up the Wold Water, not down. |
| The Ness Market | camp | The Mere and its Shores (130, 430) | The Tallymen have put a clerk at the Ness's tip overnight, with a ledger and no warrant. |
| The Rafters' Camp | camp | The Mere and its Shores (1560, -430) | A raft came down the Wold Water with a forester tied to it, alive, silent, and not saying who. |
| The Sedge Hearth | shrine, Hearthstone | The Mere and its Shores (-1440, 0) | The plank to the island has been taken up, from the island side. |
| The Strandline Stones | stones | The Mere and its Shores (1350, 520) | A Sayer's measuring-rod stands by the stones: the water fell a finger's width this spring, the first change in a century. |
| The Tallyman's Folly | ruins | The Mere and its Shores (-1080, 520) | The masons' names on the lintel are a debt the Tallymen never closed, and the Quiet Hands want it copied before the lintel is recut. |
| The Wash-Stones | stones | The Mere and its Shores (-640, 620) | A shirt came up in the wash that none of the laundresses brought: a Sayer's, with a name in the collar that the Circle unsaid. |
| Merrowhithe | **hamlet** | The North Shore (1220, -1260) | The dry aqueduct has started to drip, and there is nothing upstream of it but Skerrow. |
| Brindle Mill | camp | The North Shore (-1060, -1650) | The wheel turns against the current, and for a stride below the mill the beck runs uphill. |
| The Charter Stone | stones | The North Shore (-1500, -1600) | The brass pins are being drawn out, one a night, and there are two left. |
| The Counting Tower | tower | The North Shore (180, -1600) | The clerk has stopped counting; the tower's ledger is being kept by someone else, in Oroth numerals. |
| The Eggers' Camp | camp | The North Shore (-1330, -1300) | This year the cut rope was cut from below. |
| The Narrows Bridge | bridge | The North Shore (-185, -1820) | The clan mark and the guild mark were both chiselled off the Narrows Bridge in the same night. |
| The Net Field | camp | The North Shore (-1750, -1050) | A net came back from the water mended with Sedgish knots, by nobody in Gullhithe. |
| The Smoke Coppice | camp | The North Shore (1700, -1520) | One stool has put up a shoot overnight as thick as a man's arm, and the coppicers will not cut it. |
| The Stair Bridge | bridge | The North Shore (580, -1470) | A Merrowhithe mason says the stair went up to something before it was a bridge, and wants to know what. |
| The Standing Arches | ruins | The North Shore (930, -1450) | The channel along its top is wet this spring from end to end, and drips at the break. |
| Skarl Mill | mill | (1370, -1143) | The three hoppers were found mixed one morning, and all three clans are waiting to hear whose fault it was. |

#### Sedgemire (31 new)

| Location | Kind | Where | The story it anchors |
|---|---|---|---|
| Moreva | **hamlet** | The Delta (-2790, -1000) | The eel-traps have started coming up full of something that is not eels, with a lantern-maker's knot tied round it. |
| Nauvissa | **hamlet** | The Delta (-2250, 1080) | The grey moves up the Greyreed a reed-bed a year; Nauvissa wants to know which of the four accounts is right before they decide whether to move. |
| Saeva | **hamlet** | The Delta (-3000, 380) | A lantern came back up the channel against the current, in a weave the lantern-makers stopped using eighty years ago. |
| Saoul | ruins | The Delta (-3250, 1250) | The lanterns are relit every night, and the reedfolk swear that none of them does it. |
| The Boardwalk Gate | bridge | The Delta (-1850, 1230) | The lanterns were found lit at noon, and the boardwalk wet with footprints coming out of the delta. |
| The Eel Hurdles | camp | The Delta (-3200, -400) | Every morning the traps are full of eels swimming the wrong way, out to sea. |
| The Eel Stews | ruins | The Delta (-2000, -650) | The high-walled pond has been found empty with its sluice shut, and its wall is wet on the outside. |
| The Fog Bell | tower | The Delta (-3300, -700) | The Fog Bell stopped last night, and the ringer is not in the tower. |
| The Greyreed Decoy | camp | The Delta (-2800, 1250) | The decoy dog has started leading something else up the pipes at night, and the nets are torn from inside. |
| The Indigo Beds | camp | The Delta (-2560, -350) | Find out where the indigo's colour is going: the dyers have noticed the pale beds are the ones nearest the Nave. |
| The Long Jetty | bridge | The Delta (-2760, 850) | Somebody has been leaving lanterns with names on them at the Long Jetty, and the names are all from the Vale. |
| The Peat Hags | camp | The Delta (-2000, 620) | The cutters have dug up a Warden, perfectly kept, with a roll of names in his hand; the Wardens and the Order both want him. |
| The Reed Bridge | bridge | The Delta (-2360, 790) | The bridge has sunk to the water overnight, two hundred years of reed pressed flat as if something very heavy had crossed. |
| The Round Stones | stones | The Delta (-2550, 520) | Sing the second voice slightly flat on the fourth line and an old woman on the far islet begins to weep. |
| The Salt Pans | camp | The Delta (-3550, 1150) | A pan dried to a crust overnight with footprints across it from the sea side, and none coming back. |
| The South Stilts | tower | The Delta (-2450, 1480) | The watchman says the grey has started coming in at night and going back by day, and nobody believes him. |
| The Tide Hearth | shrine, Hearthstone | The Delta (-3400, 650) | A knot has been tied for a name nobody in Sedgemire knows, and it stays dry in the spray. |
| The Withy Beds | camp | The Delta (-1850, 180) | The withies have grown a yard since the new moon, and every one of them has grown toward the Mere. |
| Crookstilts | tower | The North Fen (-2350, -1600) | The marsh-hag has Tessane's name, and will trade it. |
| Mor'oul | ruins | The North Fen (-2150, -1350) | Under the water Mor'oul's own lanterns are still lit. |
| Oskel Ford | bridge | The North Fen (-3245, -1570) | Ore-carts have been found in the fen with the silver still aboard and the carters gone, and the Oskel clan want the ford watched. |
| The Drowned Arch | bridge | The North Fen (-2650, -1350) | An eel-boat went through the Drowned Arch the wrong way and came out at dawn with its crew a day older than they should be. |
| The Drowned Road | ruins | The North Fen (-3700, -1400) | At the lowest tide this spring the road showed a milestone further out than anyone had seen, cut with a number. |
| The Grey Gull | wreck | The North Fen (-3650, -2200) | The figurehead's face has been recognised: a reedfolk woman of Moreva, alive, who has never been to sea. |
| The Knuckle Cairn | stones | The North Fen (-3150, -2050) | The knuckle-bone has been turned to point into the fen, which in clan sign means follow. |
| The Old Crannog | ruins | The North Fen (-2800, -1900) | Somebody has been sleeping in it every night, and leaves the fire laid for the next. |
| Oulea | **hamlet** | The Tideflats (-3620, -380) | The tide came in over the shell bank for the first time in anyone's memory, and left something on the pans. |
| The Cockle Beds | camp | The Tideflats (-3800, 0) | Every stake on the beds was found moved one row toward the sea. |
| The Eel-Boat Graveyard | wreck | The Tideflats (-3800, -780) | Ollo Nauve built one of the boats that moved, and wants it back where he left it. |
| The Sunken Tower | tower | The Tideflats (-3550, -980) | The face carved on the fourth course is the face of the Thirteenth colossus. |
| The Traders' Post | camp | The Tideflats (-3760, 880) | This midsummer a trader's chart was pinned to a tent-pole, and there was no boat on the sea. |

#### The Briarwold (33 new)

| Location | Kind | Where | The story it anchors |
|---|---|---|---|
| Hollin Tor | stones | The Greatwood (2520, -1180) | One of the bows on Hollin Tor has been restrung. |
| Mossgrave | ruins | The Greatwood (2650, -350) | One moss has been let go that somebody still remembers. |
| The Antler Chapel | ruins | The Greatwood (3050, 1500) | A knight asks for the antlers the poachers sold in Tollmere as Oroth relics to be brought back. |
| The Foxgill Arch | bridge | The Greatwood (3110, 340) | The railings have been cut through on the Fernhold side. |
| The Grey Man | stones | The Greatwood (3050, -820) | From the top of the Grey Man the Moot's hum is audible, and it has a word in it. |
| The Knight's Mound | ruins | The Greatwood (2620, -700) | The cup was drunk from this midwinter. |
| The Sentinels | stones | The Greatwood (2950, 1100) | The wardens have started standing at the Sentinels by day as well, all facing the Briar. |
| Rookhold | **lodge** | The High Wold (3600, -680) | The Old Gate's doors were found open at dawn, from the far side. |
| Countwatch | tower | The High Wold (3700, 300) | The count went down by one overnight; the patch did not heal, it moved. |
| The Antler Boilers | camp | The High Wold (3700, 1750) | The Ledger of Prices lists Oroth antler at forty marks; the boilers' account book lists it at two. |
| The Briar Nursery | camp | The High Wold (3750, -250) | The cuttings have begun to lean east, every one, as if the sun were outside. |
| The Fallen Firewatch | tower | The High Wold (3050, -1400) | Somebody has climbed the fallen tower and hung a lantern at its top, which is now its side. |
| The Moot Gate Stone | shrine, Hearthstone | The High Wold (3820, 1650) | A Hart-Knight has knelt at the Moot Gate Stone three days and will not say what he is waiting for. |
| The Old Gate Stone | shrine, Hearthstone | The High Wold (3820, -760) | Every keeper has sworn facing the Wold; the youngest swore hers facing the gate, and the doors opened that night. |
| The Poachers' Lee | camp | The High Wold (3780, 1050) | The poachers have gone in a hurry and left their catch: a hart with antlers of bone-white wood. |
| The Verderer's Tower | tower | The High Wold (3650, -1400) | The verderer saw a fire on the far side of the Thornmarch, outside the world, and has not come down since. |
| Wold Force | waterfall | The High Wold (3320, 660) | Alder Wyke and a Sayer have been sitting on the bench at Wold Force for two days. |
| Elderhold | **lodge** | The Lower Wold (2100, -700) | The elder doorposts have flowered out of season, and the lodge wants the Standing Moot's opinion without going to ask for it. |
| Hazelwick | **hamlet** | The Lower Wold (1950, 350) | One of the stools has not grown back after cutting, the first in seven hundred years, and the family it belongs to wants it named before the Roll takes theirs. |
| Barkbridge | bridge | The Lower Wold (2075, 50) | A poacher sleeps under Barkbridge's roof every night and nobody moves him on, because that is the custom, and he is counting on it. |
| Pellow's Pale | ruins | The Lower Wold (1750, 800) | The gate has been unlocked from inside, with a key the Tallymen swear was never cut. |
| The Bark Camp | camp | The Lower Wold (2120, -330) | One stripped oak has grown its bark back in a week. |
| The Old Quarry | ruins | The Lower Wold (2250, -1350) | The half-cut block has Oroth writing on its hidden face: the Stride's own dedication, never laid. |
| The Sawpit | camp | The Lower Wold (2220, 1180) | One brother asks for a message to be carried down the pit to the other. |
| The Tally Hearth | shrine, Hearthstone | The Lower Wold (2200, -1000) | The notches outnumber the new trees by forty this spring, and the Woodfolk want to know who has been cutting. |
| Ormhold | **lodge** | The Northwold (2750, -2050) | The Listeners left a trunk at Ormhold in 1038 and never came back for it; it has started to smell of the sea. |
| Blackgill Falls | waterfall | The Northwold (2600, -1700) | A woodfolk child fell into Blackgill and came up in the Mere two days later, dry. |
| Harrow Tor | stones | The Northwold (3700, -2050) | The road to the northern gate is clear again every morning, and there are no keepers. |
| The Northgate Stone | shrine, Hearthstone | The Northwold (3820, -2250) | The Circle wants the northern gate opened for a second expedition; Rookhold will not, and the northern gate has no keepers. |
| The Silked Camp | camp | The Northwold (3080, -2240) | Six hunters' bows are missing from Hollin Tor's thousand; the Wold counts them as hung. |
| The Skarl Bridge | bridge | The Northwold (2060, -1850) | Somebody has been paying blood-price at the middle of the bridge for a death on the Woodfolk side. |
| The Wardstone Line | ruins | The Northwold (3520, -1850) | Measure the line against the Briar and settle which way it has moved. |
| The Root Hollow | cave | (2450, 1380) | The milk bowl was found full this morning, of something that was not milk, and warm. |

#### Skerrow Heights (51 new)

| Location | Kind | Where | The story it anchors |
|---|---|---|---|
| Kharrow's Cairns | stones | The High Moor (420, -3450) | Dunna ko-Kharrow wants the cairns' names checked against the Rope-Song, and one of them is not in it. |
| Oskel Shieling | camp | The High Moor (-2550, -3500) | The shieling fire went out, and for a night the mine's singing stopped. |
| Rudd Pike Beacon | tower | The High Moor (860, -3420) | Rudd Pike Beacon burned last night, and the Windgate snow did not move. |
| The Breathing Stones | stones | The High Moor (-1200, -3550) | The hole has stopped breathing out. |
| The Jawbone | giant bones | The High Moor (-2350, -3350) | Every beast in a herd balked at the Jawbone this spring. |
| The Red Moor | stones | The High Moor (-1650, -3280) | A new stone stands on the Red Moor, and nobody has died. |
| The Snow Shelter | camp | The High Moor (60, -3640) | The shelter bell rang on a clear night, and whoever rang it was gone when the gate-warden came. |
| Oskelcrag | **hamlet** | The Lower Dales (-2880, -2500) | An Oskel child walked up the mine road in her sleep and came back humming. |
| Ghast's Broken Bridge | bridge | The Lower Dales (-2150, -2650) | Cross it, and read the mark on the far anchor that belongs to no clan. |
| Ghastfoot | ruins | The Lower Dales (-2150, -2090) | The skull has been taken from the keystone and a clay one left in its place, very well painted. |
| Kharrow Foot | camp | The Lower Dales (420, -1930) | The bell-post rang on a day with no market, and every clan came down to answer it. |
| Kharrow Gate | tower | The Lower Dales (-100, -2120) | A traveller refused to say the law back and walked on; the clans want to know what she is. |
| Ruddale Bridge | bridge | The Lower Dales (800, -2100) | Kharrow's toll-keeper has started standing on Ruddale Bridge, saying nothing. |
| The Blood-Price Stones | stones | The Lower Dales (-70, -2330) | There is coin in the grooves for a death nobody has reported. |
| The Bone Ford | giant bones | The Lower Dales (1255, -1800) | The vertebrae have been counted at thirty-one for a thousand years; this spring there are thirty-two. |
| The Dale Watch | tower | The Lower Dales (-2100, -2380) | The horn was blown at midnight, and nobody in the watch-house blew it. |
| The Drove Chain | stones | The Lower Dales (-1830, -2040) | The chain was found lifted and the price paid in news: a name, spoken to the chain-ward by someone he cannot now describe. |
| The Moot Beacon | tower | The Lower Dales (1750, -2200) | The beacon was lit last night, and the Moot is not sitting. |
| The Skerr Stone | stones | The Lower Dales (-560, -2070) | The Valish has been cut back in overnight, badly, in a hand like a child copying letters. |
| The Smeltings | camp | The Lower Dales (-760, -2420) | The silver has come out of the kiln with a ring in it, and struck it hums a note the smiths refuse to name. |
| The Tappers' Camp | camp | The Lower Dales (1300, -2250) | The resin in one stand of pines has come out red, and the tappers will not go near it. |
| The Tinkers' Camp | camp | The Lower Dales (-2600, -2080) | The tinkers are packing to leave early, and say only that the chains have been ringing with no wind. |
| The Wading Giant | giant bones | The Lower Dales (-3560, -2520) | Each winter's storms uncover more of him, and this winter they uncovered a hand, closed on something. |
| Skarlow | **hamlet** | The Skarl Fells (2600, -2800) | Skarl's herders have seen a line of lights moving north along the Briar, beyond the wall, where there is no road. |
| Ghorrow | ruins | The Skarl Fells (1950, -3380) | Ghorr, the Bone Clan: the hold that kept their name, and the door that goes down to whoever is holding it. |
| Skarl Shieling | camp | The Skarl Fells (3200, -3250) | The cattle came down at dusk to a verse nobody sang. |
| Skarl Spout | waterfall | The Skarl Fells (2480, -2980) | Something came out of Skarl Spout with the water: a clan token of no clan. |
| The Black Keep | tower | The Skarl Fells (2300, -2250) | Somebody has been relaying the keep's stair stone by stone, at night, and the Moot wants to know which clan. |
| The Bonefield | giant bones | The Skarl Fells (3250, -2950) | The Bonefield's bones have started to lie in order. |
| The Briar's End | ruins | The Skarl Fells (3700, -3100) | The bone wall has been pushed outward in the night, from this side. |
| The Clan Stones | stones | The Skarl Fells (3500, -2650) | A stone has been found standing in the eighth socket, unpainted, and no clan will touch it. |
| The Drovers' Bothy | camp | The Skarl Fells (2470, -2520) | The bothy fire was found lit with a herd's worth of hoofprints round it, going up the dale in spring, when nothing goes up. |
| The Winter Cairns | stones | The Skarl Fells (2000, -2550) | Every morning this month a pebble has been added to every cairn, and there are four thousand cairns. |
| The Frost Moot | ruins | The Skerrow Wall (-3150, -3700) | The snow is brushed off one seat every morning, and it is never the same seat twice. |
| The Giants' Stair | ruins | The Skerrow Wall (2800, -3550) | Climb to where the Giants' Stair stops and read what is cut in the last riser. |
| The Hanging Falls | waterfall | The Skerrow Wall (-1700, -3800) | It thawed this spring on the wrong day, and has been running for a week. |
| The Watcher | giant bones | The Skerrow Wall (3750, -3550) | The skull has turned in the scree, a hand's breadth south, toward the rest of Wickmere. |
| Dreughow | **hamlet** | The Upper Dales (-1560, -2780) | Someone has painted an eighth verse on a Dreughow door overnight, in no clan's hand. |
| Ghastfell | **hamlet** | The Upper Dales (-2060, -2900) | Ghast want the bridge mended and the song of forgiveness stopped; Kharrow want neither. |
| Ruddow | **hamlet** | The Upper Dales (740, -2580) | Rudd have finally asked for the forty head, through the player as Kharrow's go-between, and the reason is on the roll of their dead. |
| Brindle Swallow | stones | The Upper Dales (-960, -3120) | Drop a bell into Brindle Swallow and listen for it at Brindlecrag's spring. |
| Kharrow Force | waterfall | The Upper Dales (300, -3150) | Cross the lip of Kharrow Force and the clans will name you for it. |
| Old Eld | ruins | The Upper Dales (-1280, -3050) | Open the bone door at Old Eld. |
| The Deadground | ruins | The Upper Dales (-2800, -2810) | Grass has begun to grow on the Deadground, in a single line, toward the mine. |
| The Giant's Spine | giant bones | The Upper Dales (1500, -3080) | Count the vertebrae. |
| The Oskel Rake | ruins | The Upper Dales (-3050, -2950) | Picks are heard in the rake at night, and every morning another yard of the vein is open. |
| The Rope Cairn | stones | The Upper Dales (-350, -2900) | A rope has been added that no Brindle family owns, knotted in a fashion nobody has tied for two hundred years. |
| The Rust Scar | waterfall | The Upper Dales (790, -2890) | The water ran clear for one day this spring, and every Rudd child born that day has been named for it. |
| The Skerry Watch | tower | The Upper Dales (-3430, -3120) | Somebody has been sweeping the Skerry Watch, and leaving the broom. |
| Rudd Mill | mill | (850, -2361) | The mill has been heard grinding at noon, with the wheel chained and the hold asleep. |
| Kharrow Hole | cave | (510, -2276) | A tally-string at the mouth has been cut down and the debt on it marked paid, and nobody will say who paid it. |

## 13. The quiet villages

The Wardens' Roll names four villages that are no longer on the map (WORLD_BIBLE §7.1). They are
not on this one either, but it knows where the Roll says they were. Standing there should find
nothing but ground:

* **Mullbourne**, "a mill that never worked, on a stream that moved": the Old Bourne, the dry
  valley west of Merrowby, near (−500, 1200). Pennywort Mill's wheel turns with no water a
  valley away.
* **Harewell**, "a hare was cut into the well lip": on Harewell Down, near (1350, 1190).
* **Larkstead**, "known for its singing; they stopped": the Vale's head by the Lark Pool, near
  (60, 2250).
* **Gosford**, "went quiet during the eleven days the Toll hummed": the Larkbourne's ford below
  the Gosling Pit, near (160, 2080).

## 14. Changing the map

Edit `tools/world/atlas/atlas.json` and the packs' positions together. Then run:

```
python3 tools/world/atlas/check_atlas.py                 # the schema and the packs: 0 errors
python3 -m pytest tools/world/tests/test_atlas.py tools/world/tests/test_atlas_map.py
python3 tools/world/atlas/render_map.py --coverage       # see what is far from anything
python3 tools/world/build_world.py --atlas tools/world/atlas/atlas.json --only heights --size 1024 --out /tmp/w
python3 tools/world/atlas/render_map.py --world /tmp/w   # the land that makes
```

Neighbouring provinces share their border vertex for vertex. Move a border in both, or the check
finds the gap. The preview is coarse on purpose. It is right about what the atlas asks for and
wrong about the detail, and the build is right about the ground.

## 15. The quests that follow the map

When the map was drawn, the pack's 35 authored quests reached 25 of its 57 places and 15 of its 240
points of interest, and most of the country's hamlets had a resident with nothing to ask of
anybody. Forty-one side quests are written with it (`game/content/packs/core/quests/the_map.json`),
in the provinces' voices, so that:

* every one of the 39 settlements has work, given by somebody who lives there, keeps a day and
  has lines of their own (the table at the end of this section);
* every one of the 18 places that is not a settlement is somewhere a quest sends you: eight deep
  places from the Sunken Barge to Frostmother's Cradle, five landmarks including the Grandfather,
  Pennywort's Mill, and four places the packs keep as points of interest;
* every one of the 263 points of interest pays off in something the game puts there (§16).

Each quest has 3 to 6 stages and sends you from its giver's home to 1 to 4 other locations.
Twelve of them cross from one region into the next. Every one comes to a decision (123 options in
all), and each option moves something the game reads: standing, Hearth or Hollow, renown, coin, a
deed, who lives where. The person who asked greets you afterwards with what came of it. Every
where, marker and escort is a place id, never a coordinate. The quests and hooks leave 105 books
lying about, each with an item copy to carry: 12 that the quests send you to find or read, and 93
notes put down at points of interest by encounter defs that stand nobody up. Five of the quests'
books are read where they lie (`in_place`): a keeper-roll hung inside a tower door is not
something you carry off. Every talk closes on its own line (`topic`), not on whatever you last
said to the person, and every resident the map added can be asked what work is going where they
live (`offer_work`).

`game/tests/unit/test_map_quests.gd` holds all of it:

* the work in every settlement can begin;
* every objective resolves to a place, a person, a spawn or an item the game places;
* every row of §16 is true, and every hook §12 wrote leads somewhere;
* every decision is remembered by somebody, once the quest is done.

`game/tests/unit/test_map_quest_ground.gd` raises what the world raises at each place the quests
fight at or leave something at: a dressing, a landmark with its collision, a settlement's fabric.
It holds every foe QuestFoes stands and every find QuestItems puts down there to open ground,
with room for a body and sky over it. A landmark's collision is a hollow shell, and a spot inside
one touches nothing.

The quest's id follows its name. "Where it sends you" leaves out the giver's own settlement.
"The decision" names each option by its id.

### Skerrow Heights (7)

| Quest | Given by | Where it sends you | The decision | What rides on it |
|---|---|---|---|---|
| **The Ninth Door** `the_ninth_door` | Brann ko-Dreugh, Dreughow | The Skerr Stone, the Rope Cairn, Ghorrow | paint it over · leave both · to the memory keeper | standing with the Clan-Moot, renown |
| **A Debt With a Nicer Voice** `a_debt_with_a_nicer_voice` | Dagga ko-Ghast, Ghastfell | The Dale Watch, Ghast's Broken Bridge, the Red Moor, Kharrow Hold | mend it · keep climbing · sing it at ghastfell | standing with the Clan-Moot, renown, Hearth or Hollow |
| **Aske's Tune** `askes_tune` | Ebba ko-Oskel, Oskelcrag | Oskel Shieling, the Deadground, the Oskel Rake | keep the fire · teach her the verse · send her to the sayers | standing with the Clan-Moot and the Sayers' Circle, Hearth or Hollow, renown |
| **Forty Head and a Hearth** `forty_head_and_a_hearth` | Ushra ko-Rudd, Ruddow | Kharrow Hold, Ruddale Bridge, the Blood-Price Stones | take the coin · ask in the hall · bring kun home | standing with the Clan-Moot, renown, Hearth or Hollow |
| **Nine Lights** `nine_lights` | Varra ko-Skarl, Skarlow | Skarl Shieling, the Briar's End, the Watcher | rebuild the wall · face east · tell rookhold | standing with the Clan-Moot and the Woodfolk, renown |
| **Answer It** `answer_it` | Brodd ko-Brindle, Brindlecrag | Brindle Swallow, Old Eld, the Smeltings | hang it · under a lintel · sell it down the pass | standing with the Clan-Moot, renown, coin, Hearth or Hollow |
| **What the Ice Keeps** `what_the_ice_keeps` | Dunna ko-Kharrow, Kharrow Hold | Kharrow's Cairns, the Finger Shrine, Frostmother's Cradle | sing him · give the token to rudd · leave him to the ice | standing with the Clan-Moot, renown, Hearth or Hollow |

### Brightwater and the Mere (6)

| Quest | Given by | Where it sends you | The decision | What rides on it |
|---|---|---|---|---|
| **The Third Arch** `the_third_arch` | Berrit Smoker, Merrowhithe | The Standing Arches, the Stair Bridge, the Rust Scar, Ruddow | catch it · let it drip · stop it | standing with the Clan-Moot, Hearth or Hollow, renown, coin |
| **The Ruled Line** `the_ruled_line` | Maudie Punt, Sedgehithe | The Heronry, the Eelweir, the Sedge Hearth | the tide · the circle · cut to the line | standing with the Reed Council and the Sayers' Circle, renown, coin |
| **The Same Hand** `the_same_hand` | Corin Stilyard, Stride's Foot | The Larkmouth Bridge, Tollmere | strike them · send word · leave the book open | standing with the Tallymen, Hearth or Hollow, renown, a deed |
| **The Stride's Dedication** `the_stride_dedication` | Cassa Binder, Tollmere | The Old Quarry, the Long Stride, Elderhold | print it · sell to the guild · to the wold | standing with the Sayers' Circle, the Tallymen and the Woodfolk, renown, coin |
| **The Charter Pins** `the_charter_pins` | Orrin Quill, Tollmere | The Charter Stone, the Narrows Bridge, the Counting Tower | repin it · let it break · two pins | standing with the Clan-Moot and the Tallymen, Hearth or Hollow, coin, renown |
| **Cut From Below** `cut_from_below` | Jory Wick, Gullhithe | The Eggers' Camp, the Pilgrim Stair, the Sunken Barge | the serpent · the sayer · say nothing | standing with the Sayers' Circle, renown, Hearth or Hollow, coin |

### Sedgemire (6)

| Quest | Given by | Where it sends you | The decision | What rides on it |
|---|---|---|---|---|
| **Knots Round Nothing** `knots_round_nothing` | Sauve Mor, Moreva | The Fog Bell, Mor'oul | ring the bell · send them out · put them back | standing with the Reed Council, Hearth or Hollow, renown |
| **Which Account** `which_account` | Ossa Lissa, Nauvissa | The South Stilts, the Boardwalk Gate, the Greyreed Decoy | wait · go north · keep the watch | standing with the Reed Council and the Tolling Order, Hearth or Hollow, renown |
| **What the Tide Left** `what_the_tide_left` | Meo Sa, Oulea | The Cockle Beds, the Salt Pans, the Traders' Post, the Builders' Harbour | put up the tent · write it true · to the spire | standing with the Reed Council and the Sayers' Circle, Hearth or Hollow, renown |
| **Against the Current** `against_the_current` | Lisse Tal, Saeva | Saoul, the Tide Hearth | send it out · hang it at saoul · sell it to the order | standing with the Reed Council and the Tolling Order, Hearth or Hollow, coin |
| **The Boat That Moved** `the_boat_that_moved` | Ollo Nauve, Nauve's Landing | The Eel-Boat Graveyard, the Eel Stews | haul it back · into a new boat · to the stews | standing with the Reed Council, Hearth or Hollow, renown |
| **The Slow Reflection** `the_slow_reflection` | Ismay Ondrael, Tollmere | Eelfathom Pool, Hesk Pool, the Peat Hags | to the wardens · to the order · leave him | standing with Wardens of the Hearth, the Tolling Order and the Sayers' Circle, renown |

### The Briarwold (6)

| Quest | Given by | Where it sends you | The decision | What rides on it |
|---|---|---|---|---|
| **Flowered in the Frost** `flowered_in_the_frost` | Wenna Holt, Elderhold | The Grey Man, the Tally Hearth, the Log Boom, the Rafters' Camp | plant forty · slowly · make them pay | standing with the Woodfolk and the Tallymen, Hearth or Hollow, coin |
| **The Fennick Stool** `the_fennick_stool` | Aggie Coppice, Hazelwick | The Rod Stacks, Mossgrave | keep the name · plant the rods · let it go | standing with the Woodfolk, Hearth or Hollow |
| **The Listeners' Trunk** `the_listeners_trunk` | Nessa Ashby, Ormhold | Harrow Tor, the Northgate Stone | open it · send it to the circle · leave it at the gate | standing with the Sayers' Circle and the Woodfolk, renown, coin |
| **Opened From the Far Side** `opened_from_the_far_side` | Edda Thornby, Rookhold | The Old Gate Stone, the Verderer's Tower, Countwatch | sleep against it · leave the bar · tell fernhold | standing with the Woodfolk, Hearth or Hollow, renown |
| **The Restrung Bow** `the_restrung_bow` | Edric Fletcher, Grandfather Hollow | Hollin Tor, the Silked Camp, Weaverdeep, Ormhold | hang them · to ormhold · burn the silk | standing with the Woodfolk, Hearth or Hollow, renown |
| **The Two Hundred and Seventh** `the_two_hundred_and_seventh` | Cille Tamwood, Grandfather Hollow | The Grandfather, Barkbridge, the Oiled Stone | let it burn · put it out · give him a bench | standing with the Woodfolk, Hearth or Hollow |

### Hearthvale (11)

| Quest | Given by | Where it sends you | The decision | What rides on it |
|---|---|---|---|---|
| **The Notch on the Post** `the_notch_on_the_post` | Ada Welling, Ashwell | The Wellspring, the Greyline Stones, Ash Watch, Pilgrim's Ash | put her down · let her walk · tell the order | standing with Wardens of the Hearth and the Tolling Order, Hearth or Hollow |
| **The Twelfth Sluice** `the_twelfth_sluice` | Hal Wynstead, Wynstead | The Roll Stone, Merrowby | name it · nail it · tell the wardens | standing with Wardens of the Hearth, a deed, Hearth or Hollow, coin |
| **Thistle** `thistle` | Gil Fallow, Fallowfold | The Old Sheepwash, the Ninth Waystone, Greywatch | keep her · let her go · read his name | standing with the Tolling Order, Hearth or Hollow |
| **The Top Bed** `the_top_bed` | Lin Cresswell, Cressbourne | The Cress Bridge, the Lime Bridge, the Limekilns | put them back · to the toll house · keep them | standing with the Tallymen, Hearth or Hollow, coin |
| **Pens With No Gate** `pens_with_no_gate` | Tam Withy, Hazelcombe | Wardens' Rest, the Rod Stacks, Hazelwick | as ordered · a gate south · refuse | standing with Wardens of the Hearth and the Woodfolk, coin, Hearth or Hollow |
| **One Short** `one_short` | Pell Brambling, Bramcombe | The Pinfold, the Lambing Fold | claim it · leave it · to the lambing fold | Hearth or Hollow, coin |
| **The Grey on the Green** `the_grey_on_the_green` | Tor Rookwright, Rookdown | The Last Field, Rook Mill, the Cliff Graves, the Brow Beacon | stay · go · turn the stone | standing with Wardens of the Hearth, a deed, Hearth or Hollow, renown |
| **The Warrener's Burrow** `the_warreners_burrow` | Tor Rookwright, Rookdown | The Warrener's Camp, the Flint Pits, Tallow Barrow | wall it · leave it · ferrets to tamwick | standing with Wardens of the Hearth, renown, Hearth or Hollow, coin |
| **One to Dunn** `one_to_dunn` | Cal Merriweather, the Hare and Hurdle | Hound Watch, the Last Look | pour it · write his name · tell the rest | standing with Wardens of the Hearth, Hearth or Hollow, renown |
| **Tamwick Twice** `tamwick_twice` | Hob Tamwick, Tamwick | Orm's Long Barrow, the Singing Yew | twenty turns · to the rest · back in the cist | standing with Wardens of the Hearth, Hearth or Hollow |
| **Ashcombe on the Roll** `ashcombe_on_the_roll` | Pellam Ashcombe, Merrowby | The West Walk, Ashcombe | onto the roll · leave the doors · bring a door home | standing with Wardens of the Hearth and the Tolling Order, a deed, Hearth or Hollow |

### Cinderlea (5)

| Quest | Given by | Where it sends you | The decision | What rides on it |
|---|---|---|---|---|
| **Would Anybody Say It** `would_anybody_say_it` | Nella Candlewright, the Last Camp | Merrowby, Candle Cross, Greywatch, the Wellspring | stay · go home · go on | standing with the Tolling Order, Hearth or Hollow, a deed, Nella moves to Merrowby or leaves |
| **Ossel's Forge** `ossels_forge` | Merrit Ash, the West Walk | The Bell Pit, the North Gate | quench it · let her finish · bury it | standing with the Tolling Order, renown, Hearth or Hollow |
| **The Late Delivery** `the_late_delivery` | Nan Greyfold, Greyfold | The Ash-Winter Carts, the Silent Market | set the tables · leave the stall · to the wardens | standing with Wardens of the Hearth, Hearth or Hollow, renown |
| **The Sealed Barge** `the_sealed_barge` | Wat Thatcher, Pilgrim's Ash | The Driftwood Camp, the Strand Beacon | break the seal · send to the guild · give it to the strand | standing with the Tolling Order and the Tallymen, coin, Hearth or Hollow, renown |
| **The Swept Road** `the_swept_road` | Arn Sweeting, the Sweeper's Lean-To | The Turning Cairn | tie it · ring it · keep it | Arn's greeting, and his box after the main line moves on |

### Where the work is

Every settlement, who in it gives work, and the work. Quests written with the map are in bold.

| Settlement | Kind | Who gives work | The work |
|---|---|---|---|
| Brindlecrag | village | Brodd ko-Brindle | **Answer It** |
| Dreughow | hamlet | Brann ko-Dreugh | **The Ninth Door** |
| Ghastfell | hamlet | Dagga ko-Ghast | **A Debt With a Nicer Voice** |
| Kharrow Hold | town | Dunna ko-Kharrow, Skardd ko-Skarl | A Hand on the Rope, **What the Ice Keeps**; Four Hundred and Twelve |
| Oskelcrag | hamlet | Ebba ko-Oskel | **Aske's Tune** |
| Ruddow | hamlet | Ushra ko-Rudd | **Forty Head and a Hearth** |
| Skarlow | hamlet | Varra ko-Skarl | **Nine Lights** |
| Gullhithe | village | Jory Wick, Tamsin Wick | **Cut From Below**; The Lamp Is Dimmer |
| Merrowhithe | hamlet | Berrit Smoker | **The Third Arch** |
| Sedgehithe | hamlet | Maudie Punt | **The Ruled Line** |
| Stride's Foot | hamlet | Corin Stilyard | **The Same Hand** |
| Tollmere | city | Aldith Sulion, Orrin Quill, Ismay Ondrael, Cassa Binder | In Council, Louder; **The Charter Pins**; The Long Measurement, **The Slow Reflection**, The Unsaid Woman; **The Stride's Dedication** |
| Isseva | town | Loa Oul, Tallissa Oul | The Lantern That Would Not Go Out; What the Water Kept |
| Moreva | hamlet | Sauve Mor | **Knots Round Nothing** |
| Nauve's Landing | hamlet | Ollo Nauve | **The Boat That Moved** |
| Nauvissa | hamlet | Ossa Lissa | **Which Account** |
| Oulea | hamlet | Meo Sa | **What the Tide Left** |
| Saeva | hamlet | Lisse Tal | **Against the Current** |
| Elderhold | lodge | Wenna Holt | **Flowered in the Frost** |
| Fernhold | lodge | Alder Wyke | The Briar's Purpose |
| Grandfather Hollow | town | Tansy Thornby, Edric Fletcher, Cille Tamwood | The Fawning Months; **The Restrung Bow**; **The Two Hundred and Seventh** |
| Hazelwick | hamlet | Aggie Coppice | **The Fennick Stool** |
| Ormhold | lodge | Nessa Ashby | **The Listeners' Trunk** |
| Rookhold | lodge | Edda Thornby | **Opened From the Far Side** |
| Ashwell | hamlet | Ada Welling | **The Notch on the Post** |
| Bramcombe | hamlet | Pell Brambling | **One Short** |
| Cressbourne | hamlet | Lin Cresswell | **The Top Bed** |
| Fallowfold | hamlet | Gil Fallow | **Thistle** |
| Hazelcombe | hamlet | Tam Withy | **Pens With No Gate** |
| Merrowby | town | Merrick Gosling, Pellam Ashcombe, Robin Ashdown, Corwen Mullard, Osric Pennywort, Wren Tallow, Hesta Hollins | A Verse About You; **Ashcombe on the Roll**, The Last Name of Mullbourne; Bramble; Cask and Press; Grist; Louder Than Books, The Lane That Isn't, The Naming, The Toll Hums; Seventeen Bells |
| Rookdown | hamlet | Tor Rookwright | **The Grey on the Green**, **The Warrener's Burrow** |
| Tamwick | hamlet | Hob Tamwick | **Tamwick Twice** |
| The Hare and Hurdle | lodge | Cal Merriweather | **One to Dunn** |
| Wardens' Rest | fort | Roll-Keeper Hesk | The Deep Lines, The Reading, The Roll of Names |
| Wynstead | hamlet | Hal Wynstead | **The Twelfth Sluice** |
| Greyfold | ruin village | Nan Greyfold | **The Late Delivery** |
| Pilgrim's Ash | camp | Cadwen Ash, Wat Thatcher, Toren Ash | At the Gate, Forty-One Places, The Held Note, Vigil; The Cold Fire, **The Sealed Barge**; The Names in the Chapter Book |
| The Last Camp | camp | Nella Candlewright | **Would Anybody Say It** |
| The West Walk | fort | Merrit Ash | **Ossel's Forge** |

## 16. What every point of interest pays off in

Each point of interest's one-line hook (§12) is tied to the ids the game has for it in
`core:table/poi_hooks` (`game/content/packs/core/tables/poi_hooks.json`). `tools/poi_hooks.py`
writes it from the pack, and `--check` says which rows have gone stale. test_map_quests holds each
row true: the quests it names send you there, the things lying there are put down there, the
encounters stand somebody up there, and the Hearthstone is the place's own. 110 are sent to by a
quest, 95 have something lying there to take or read, 85 stand an encounter up and 22 keep a
Hearthstone. Nothing in the game reads the table itself. It is the index, and the test keeps it
honest.

### Skerrow Heights (54)

| Point of interest | Quests that send you | Lying there | Encounter | Hearthstone |
|---|---|---|---|---|
| Brindle Swallow | `answer_it` |  |  |  |
| Ghast's Broken Bridge | `a_debt_with_a_nicer_voice` |  | `ghasts_broken_bridge` |  |
| Ghastfoot |  | `item/note_ghastfoot` |  |  |
| Ghorrow | `the_ninth_door` |  | `ghorrow` |  |
| Kharrow Foot |  | `item/note_kharrow_foot` |  |  |
| Kharrow Force |  | `item/note_kharrow_force` |  |  |
| Kharrow Gate |  | `item/note_kharrow_gate` |  |  |
| Kharrow's Cairns | `what_the_ice_keeps` |  |  |  |
| Old Eld | `answer_it` |  | `old_eld` |  |
| Oskel Shieling | `askes_tune` |  |  |  |
| Rudd Pike Beacon |  | `item/note_rudd_pike_beacon` |  |  |
| Ruddale Bridge | `forty_head_and_a_hearth` |  |  |  |
| Skarl Shieling | `nine_lights` |  |  |  |
| Skarl Spout |  |  | `skarl_spout` |  |
| The Black Keep |  | `item/note_black_keep` |  |  |
| The Blood-Price Stones | `forty_head_and_a_hearth` |  |  |  |
| The Bone Ford |  | `item/note_bone_ford` |  |  |
| The Bonefield |  |  | `the_bonefield` |  |
| The Breathing Stones |  | `item/note_breathing_stones` |  |  |
| The Briar's End | `nine_lights` |  |  |  |
| The Chain Bridge |  |  | `chain_bridge` |  |
| The Clan Stones |  | `item/note_clan_stones` |  |  |
| The Clanless Camp | `four_hundred_and_twelve` |  | `clanless_camp` |  |
| The Dale Watch | `a_debt_with_a_nicer_voice` |  |  |  |
| The Deadground | `askes_tune` |  |  |  |
| The Drove Chain |  | `item/note_drove_chain` |  |  |
| The Drovers' Bothy |  | `item/note_drovers_bothy` |  |  |
| The Finger Shrine | `what_the_ice_keeps` |  |  | yes |
| The Frost Moot |  | `item/note_frost_moot` |  |  |
| The Giant's Spine |  |  | `giants_spine` |  |
| The Giants' Stair |  |  | `giants_stair` |  |
| The Hanging Falls |  | `item/note_hanging_falls` |  |  |
| The Hidden Tarn |  |  | `hidden_tarn` |  |
| The Jawbone |  |  | `the_jawbone` |  |
| The Moot Beacon |  | `item/note_moot_beacon` |  |  |
| The Oskel Rake | `askes_tune` |  | `oskel_rake` |  |
| The Red Moor | `a_debt_with_a_nicer_voice` |  |  |  |
| The Rib Cathedral |  |  | `rib_cathedral` |  |
| The Rope Cairn | `the_ninth_door` |  |  |  |
| The Rust Scar | `the_third_arch` |  |  |  |
| The Seven Stones |  | `item/note_lichen_stones` |  |  |
| The Skerr Stone | `the_ninth_door` |  |  |  |
| The Skerry Watch |  | `item/note_skerry_watch` |  |  |
| The Smeltings | `answer_it` |  |  |  |
| The Snow Shelter |  | `item/note_snow_shelter` |  |  |
| The Tappers' Camp |  | `item/note_tappers_camp` |  |  |
| The Three Sisters |  |  | `three_sisters_falls` | yes |
| The Tinkers' Camp |  | `item/note_tinkers_camp` |  |  |
| The Wading Giant |  | `item/note_wading_giant` |  |  |
| The Watch of the Gate |  | `item/note_watch_of_the_gate` |  |  |
| The Watcher | `nine_lights` |  | `the_watcher` |  |
| The Winter Cairns |  | `item/note_winter_cairns` |  |  |
| Rudd Mill |  | `item/note_rudd_mill` |  |  |
| Kharrow Hole |  | `item/note_kharrow_hole` |  |  |

### Brightwater and the Mere (33)

| Point of interest | Quests that send you | Lying there | Encounter | Hearthstone |
|---|---|---|---|---|
| Brindle Mill |  | `item/note_brindle_mill` |  |  |
| Gull Holm |  |  | `gull_holm` |  |
| North Cliff Beacon | `the_lamp_is_dimmer` |  | `north_cliff_beacon` |  |
| Shingle Shrine | `the_long_measurement` |  |  | yes |
| The Beached Barge |  | `item/note_beached_barge` |  |  |
| The Bell Buoys |  | `item/note_bell_buoys` |  |  |
| The Charter Stone | `the_charter_pins` |  |  |  |
| The Counting Tower | `the_charter_pins` |  |  |  |
| The Dry Jetty |  | `item/note_dry_jetty` |  |  |
| The Eelweir | `the_ruled_line` |  | `eelweir` |  |
| The Eggers' Camp | `cut_from_below` |  |  |  |
| The Gullhithe Wreck | `a_thing_nobody_reported` |  | `gullhithe_wreck` |  |
| The Heronry | `the_ruled_line` |  |  |  |
| The Larkmouth Bridge | `the_same_hand` |  |  |  |
| The Lime Bridge | `the_top_bed` |  |  |  |
| The Limekilns | `the_top_bed` |  |  |  |
| The Listening Post |  | `item/note_listening_post` |  |  |
| The Log Boom | `flowered_in_the_frost` |  |  |  |
| The Long Stride | `the_stride_dedication` |  | `long_stride` |  |
| The Narrows Bridge | `the_charter_pins` |  |  |  |
| The Ness Market |  | `item/note_ness_market` |  |  |
| The Net Field |  | `item/note_net_field` |  |  |
| The Pilgrim Stair | `cut_from_below` |  |  |  |
| The Rafters' Camp | `flowered_in_the_frost` |  |  |  |
| The Sedge Hearth | `the_ruled_line` |  |  | yes |
| The Smoke Coppice |  | `item/note_smoke_coppice` |  |  |
| The Stair Bridge | `the_third_arch` |  |  |  |
| The Standing Arches | `the_third_arch` |  |  |  |
| The Strandline Stones |  | `item/note_strandline_stones` |  |  |
| The Tallyman's Folly |  |  | `tallymans_folly` |  |
| The Wash-Stones |  | `item/note_wash_stones` |  |  |
| Willow Isle | `the_last_column` | `book/saying_ward` |  |  |
| Skarl Mill |  | `item/note_skarl_mill` |  |  |

### Sedgemire (35)

| Point of interest | Quests that send you | Lying there | Encounter | Hearthstone |
|---|---|---|---|---|
| Crookstilts |  |  | `crookstilts` |  |
| Drowned Bell Shrine |  |  | `drowned_bell_shrine` | yes |
| Heron Watch |  | `item/note_heron_watch` |  |  |
| Mor'oul | `knots_round_nothing` |  | `mor_oul` |  |
| Oskel Ford |  | `item/note_oskel_ford` |  |  |
| Saoul | `against_the_current` |  | `saoul` |  |
| The Boardwalk Gate | `which_account` |  |  |  |
| The Cockle Beds | `what_the_tide_left` |  |  |  |
| The Drowned Arch |  | `item/note_drowned_arch` |  |  |
| The Drowned Road |  | `item/note_drowned_road` |  |  |
| The Eel Hurdles |  | `item/note_eel_hurdles` |  |  |
| The Eel Stews | `the_boat_that_moved` |  |  |  |
| The Eel-Boat Graveyard | `the_boat_that_moved` |  | `eelboat_graveyard` |  |
| The Fog Bell | `knots_round_nothing` |  |  |  |
| The Grey Gull |  | `item/note_grey_gull` |  |  |
| The Greyreed Decoy | `which_account` |  |  |  |
| The Indigo Beds |  | `item/note_indigo_beds` |  |  |
| The Knuckle Cairn |  | `item/note_knuckle_cairn` |  |  |
| The Lantern Causeway |  |  | `lantern_causeway` |  |
| The Long Jetty |  |  | `long_jetty` |  |
| The Old Crannog |  |  | `old_crannog` |  |
| The Peat Hags | `the_slow_reflection` |  | `peat_hags` |  |
| The Reed Bridge |  | `item/note_reed_bridge` |  |  |
| The Reed Wreck |  | `item/salt_isles_guide` | `reed_wreck` |  |
| The Round Stones |  | `item/note_round_stones` |  |  |
| The Sallow King |  |  | `sallow_king` |  |
| The Salt Pans | `what_the_tide_left` |  |  |  |
| The South Stilts | `which_account` |  |  |  |
| The Stair of Isse |  |  | `stair_of_isse` |  |
| The Sunken Tower |  |  | `sunken_tower` |  |
| The Tide Hearth | `against_the_current` |  |  | yes |
| The Tideflat Stones |  | `item/note_tideflat_stones` |  |  |
| The Traders' Post | `what_the_tide_left` |  |  |  |
| The Withy Beds |  | `item/note_withy_beds` |  |  |
| Wisp Hollow | `the_lantern_still_lit` |  | `wisp_hollow` |  |

### The Briarwold (37)

| Point of interest | Quests that send you | Lying there | Encounter | Hearthstone |
|---|---|---|---|---|
| Barkbridge | `the_two_hundred_and_seventh` |  |  |  |
| Blackgill Falls |  |  | `blackgill_falls` |  |
| Countwatch | `opened_from_the_far_side` |  |  |  |
| Fern Gully |  |  | `fern_gully` |  |
| Foxfire Falls |  |  | `foxfire_falls` |  |
| Harrow Tor | `the_listeners_trunk` |  |  |  |
| Hollin Tor | `the_restrung_bow` |  |  |  |
| Mossbridge |  |  | `mossbridge` |  |
| Mossgrave | `the_fennick_stool` |  | `mossgrave` |  |
| Pellow's Pale |  | `item/note_pellows_pale` |  |  |
| The Antler Boilers |  |  | `antler_boilers` |  |
| The Antler Chapel |  |  | `antler_chapel` |  |
| The Bark Camp |  | `item/note_bark_camp` |  |  |
| The Breach | `the_briars_purpose` |  | `briar_breach` |  |
| The Briar Nursery |  | `item/note_briar_nursery` |  |  |
| The Charcoal Camp | `the_fawning_months` |  |  |  |
| The Fallen Firewatch |  | `item/note_fallen_firewatch` |  |  |
| The Foxgill Arch |  | `item/note_foxgill_arch` |  |  |
| The Grey Man | `flowered_in_the_frost` |  |  |  |
| The Hart Bones |  |  | `hart_bones` |  |
| The Hunters' Stand | `the_fawning_months` |  | `hunters_stand` |  |
| The Knight's Mound |  |  | `knights_mound` |  |
| The Moot Gate Stone |  |  |  | yes |
| The Northgate Stone | `the_listeners_trunk` |  |  | yes |
| The Oiled Stone | `the_two_hundred_and_seventh` |  |  | yes |
| The Old Gate Stone | `opened_from_the_far_side` |  |  | yes |
| The Old Quarry | `the_stride_dedication` |  | `old_quarry` |  |
| The Poachers' Lee |  |  | `poachers_lee` |  |
| The Sawpit |  | `item/note_the_sawpit` |  |  |
| The Sentinels |  |  | `the_sentinels` |  |
| The Silked Camp | `the_restrung_bow` |  | `silked_camp` |  |
| The Skarl Bridge |  | `item/note_skarl_bridge` |  |  |
| The Tally Hearth | `flowered_in_the_frost` |  |  | yes |
| The Verderer's Tower | `opened_from_the_far_side` |  |  |  |
| The Wardstone Line |  |  | `wardstone_line` |  |
| Wold Force |  |  | `wold_force` |  |
| The Root Hollow |  | `item/note_root_hollow` |  |  |

### Hearthvale (60)

| Point of interest | Quests that send you | Lying there | Encounter | Hearthstone |
|---|---|---|---|---|
| Ansel's Hedge Shrine | `the_lane_that_isnt`, `the_reading` |  |  | yes |
| Ash Watch | `the_notch_on_the_post` |  |  |  |
| Bell Meadow Stones |  | `item/note_bell_meadow` |  |  |
| Candle Cross | `would_anybody_say_it` |  |  | yes |
| Foxglove Dell |  |  | `foxglove_dell` |  |
| Gosling Pit | `wardens_roll_of_names` |  | `gosling_pit` |  |
| Hanging Coombe |  |  | `hanging_coombe` |  |
| Hound Watch | `one_to_dunn` |  |  |  |
| Hurdle Fold |  |  | `hurdle_fold` |  |
| Hushwatch |  | `item/note_hushwatch` |  |  |
| Lamb's Bottom |  |  | `lambs_bottom` |  |
| Larkbourne Ford |  |  | `larkbourne_ford` |  |
| Orm's Long Barrow | `tamwick_twice` |  | `orms_long_barrow` |  |
| Pennywort Bridge |  | `item/note_pennywort_bridge` |  |  |
| Rook Mill | `the_grey_on_the_green` |  |  |  |
| Tallow Barrow | `the_warreners_burrow` |  | `tallow_barrow` |  |
| The Brow Beacon | `the_grey_on_the_green` |  |  |  |
| The Chalk Cell |  | `item/note_chalk_cell` |  |  |
| The Chalk Pit |  | `item/note_chalk_pit` |  |  |
| The Cliff Graves | `the_grey_on_the_green` |  |  |  |
| The Cliff Hearth |  |  |  | yes |
| The Cress Bridge | `the_top_bed` |  |  |  |
| The Dewpond Fold |  | `item/note_dewpond_fold` |  |  |
| The Flint Pits | `the_warreners_burrow` |  |  |  |
| The Grey End |  |  | `the_grey_end` |  |
| The Hare Stone |  | `item/note_hare_stone` |  |  |
| The Hayward's Perch |  | `item/note_haywards_perch` |  |  |
| The Hush Steps |  | `item/note_hush_steps` |  |  |
| The Lambing Fold | `one_short` |  |  |  |
| The Last Field | `the_grey_on_the_green` |  | `the_last_field` |  |
| The Last Look | `one_to_dunn` |  |  |  |
| The Naming Stone |  |  |  | yes |
| The Old Sheepwash | `thistle` |  |  |  |
| The Pinfold | `one_short` |  |  |  |
| The Rod Stacks | `pens_with_no_gate`, `the_fennick_stool` |  |  |  |
| The Roll Stone | `the_twelfth_sluice` |  |  |  |
| The Singing Yew | `tamwick_twice` |  |  |  |
| The Southgate Stone |  |  |  | yes |
| The Tumbled Watch | `a_verse_about_you`, `wardens_roll_of_names` |  | `tumbled_watchtower` |  |
| The Turned Hut |  | `item/note_turned_hut` |  |  |
| The Warden Barrow |  | `item/note_warden_barrow` |  |  |
| The Warrener's Camp | `the_warreners_burrow` |  |  |  |
| The Weighing Stone |  | `item/note_weighing_stone` |  |  |
| The Wellspring | `the_notch_on_the_post`, `would_anybody_say_it` |  |  | yes |
| Whitecut Falls |  |  | `whitecut_falls` |  |
| Wolf Holt |  |  | `wolf_holt` |  |
| Hurdlegate Farm |  | `item/note_hurdlegate_farm` |  |  |
| Brow End |  | `item/note_brow_end_farm` |  |  |
| Hatchmoor |  | `item/note_hatchmoor_farm` |  |  |
| Coldharbour |  | `item/note_coldharbour_farm` |  |  |
| Pennywort Fields |  | `item/note_pennywort_fields` |  |  |
| Ashway Farm |  | `item/note_ashway_farm` |  |  |
| The Last Farm |  | `item/note_grey_end_farm` |  |  |
| Southgate Farm |  | `item/note_southgate_farm` |  |  |
| Ridgeway Farm |  | `item/note_ridgeway_farm` |  |  |
| Fallowgate |  | `item/note_fallowgate_farm` |  |  |
| Larkfield |  | `item/note_larkfield_farm` |  |  |
| Hazel Bottom |  | `item/note_hazel_bottom_farm` |  |  |
| Cress Mill |  | `item/note_cress_mill` |  |  |
| Lark Mill |  | `item/note_lark_mill` |  |  |

### Cinderlea (44)

| Point of interest | Quests that send you | Lying there | Encounter | Hearthstone |
|---|---|---|---|---|
| Ashcombe | `ashcombe_on_the_roll` |  | `ashcombe` |  |
| Bell Street |  |  | `bell_street` |  |
| Greywatch | `thistle`, `would_anybody_say_it` |  |  |  |
| Hesk Pool | `the_slow_reflection` |  |  |  |
| Hesk-Morn |  | `item/note_hesk_morn` |  |  |
| Sulion |  | `item/note_sulion` |  |  |
| The Anthem Hall |  |  | `anthem_hall` |  |
| The Ash-Winter Carts | `the_late_delivery` |  | `ashwinter_carts` |  |
| The Bell Garden |  |  | `bell_garden` |  |
| The Bell Pit | `ossels_forge` |  | `bell_pit` |  |
| The Bell Wood Stone |  |  |  | yes |
| The Builders' Harbour | `what_the_tide_left` |  |  |  |
| The Cistern of Isse |  | `item/note_cistern_of_isse` |  |  |
| The Cold Fire | `the_cold_fire` |  | `cold_fire_camp` |  |
| The Driftwood Camp | `the_sealed_barge` |  |  |  |
| The Glass Bridge |  |  | `glass_bridge` |  |
| The Glass Falls |  |  | `glass_falls` |  |
| The Grey Hedge |  | `item/note_grey_hedge` |  |  |
| The Grey Wreck |  |  | `grey_wreck` |  |
| The Greyline Stones | `the_notch_on_the_post` |  |  |  |
| The Headless Watch | `the_names_in_the_chapter_book` |  |  |  |
| The Hermit's Gate |  | `item/note_hermits_gate` |  |  |
| The Hush Bell |  |  | `hush_bell` |  |
| The Hushline Stair |  |  | `hushline_stair` | yes |
| The Kneeling Colossus |  | `item/note_kneeling_colossus` |  |  |
| The Last Hearth |  |  |  | yes |
| The Last Milestone |  | `item/note_last_milestone` |  |  |
| The Ninth Waystone | `thistle` |  |  |  |
| The North Gate | `ossels_forge` |  | `north_gate` |  |
| The Novices' Seats |  | `item/note_novices_seats` |  |  |
| The One Poppy |  | `item/note_the_one_poppy` |  |  |
| The Pilgrims' Bell |  |  |  | yes |
| The Row of Mouths |  |  | `row_of_mouths` |  |
| The Silent Market | `the_late_delivery` |  | `silent_market` |  |
| The Stair Head |  |  |  | yes |
| The Strand Beacon | `the_sealed_barge` |  |  |  |
| The Sunk Plaza |  |  | `sunk_plaza` |  |
| The Sweeper's Lean-To | `the_swept_road` |  |  |  |
| The Tenth Waystone |  | `item/note_tenth_waystone` |  |  |
| The Thirteenth |  |  | `thirteenth_colossus` |  |
| The Tower of Vaelost |  |  | `tower_of_vaelost` |  |
| The Turning Cairn | `the_swept_road` |  |  |  |
| The Weighhouse |  | `item/note_weighhouse` |  |  |
| The Tide Mouth |  | `item/note_hushline_cave` |  |  |
