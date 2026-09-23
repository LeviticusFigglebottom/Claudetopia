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
| locations | **297**: 57 places and 240 points of interest (60 places counting the three edge places) |
| density | **6.3 locations a walkable km²** |
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
the Oroth stair goes down from its seaward edge into the water and the mist. From the Landing
**the Stair** climbs the bank in one long traverse to the rim. **The Stair Head**, the Wardens'
camp, stands at (10, 3670) on the Stair Knoll, about 110 m up over the Hush, facing **333°**.

In a heights build of this atlas, the first view (DESIGN 5.1a) has:

* **a landmark silhouette**: the Sunken Choir's ring of headless colossi on the Choir's Crown,
  483 m ahead and dead on the facing, and the Cantor's Seat's cold light below it (244 m).
* **a road**: the waystones walking north across the heath to the Choir (the Stair Path). Beyond
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
* **The Greatwood** (150 m, hills; granite stair, tors): the ancient wood. **Grandfather Hollow**
  is the town inside the Grandfather. The Wold Water comes down the Foxgill past Foxfire Falls
  and under the Foxgill Arch. Weaverdeep is below Weaver's Gill, and Fern Gully is its back
  door. The Grey Man and Hollin Tor stand in it.
* **The High Wold** (232 m, ridged north–south): the rise to the Thornmarch, with Fernhold, the
  Standing Moot on Moot Tor, Rookhold, Wold Force and the Hart Bones. The Woodfolk's gate-stones
  (Hearthstones) stand along the rampart.
* **The Northwold** (170 m, hills; tors): between the Wold and the fells. Ormhold, the Blackgill,
  Harrow Tor, the Wardstone Line and the Silked Camp are here.
* **The Thornmarch**: a granite rampart the length of the east edge with the Briar grown on it,
  sheer on the Wold's side. It closes the east. The Briar's End, where it gives out against the
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

**Roads.** The **Stair Path** (track) runs from the Stair Head to the Choir. The **Ash Road**, the
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
  to the Grey Sea. The North Channel and the Greyreed are the delta's other channels. The Oskel,
  Weaver's Gill and the Blackgill join other rivers. Every river falls from source to mouth and
  ends in water (tested).
* **The small waters**: the Lark Pool (46 m), the Hidden Tarn (520 m), Blackwater Tarn (415 m),
  Hesk Pool (56 m), Mormere and Lissane Mere (a hand over the fen). Each is drawn to its setting:
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

## 10. Kinds the map wants next

* **cave**: a mouth in a slope or a cliff, 4–8 m, with dark going in 10 m. Limestone in Skerrow,
  a root-cave in the Briarwold, a sea-cave under the Hushline. (Faked today as ruins or a
  hidden valley.)
* **farmstead**: a cob house, a barn, a walled yard, a well and a dog. The Vale needs a dozen.
  (Faked as camps with a job board.)
* **mill**: a building with a wheel on a leat, or sails. Rook Mill, Brindle Mill and the Pennywort
  mill-bridge point at it. (Faked as the camp's millstone variant.)
* **waystone**: one stone with notches and a bowl for coins. The pilgrims' road counts them.
  (Faked as standing stones.)
* **market field**: a walled field, a bell-post, stalls on market days (Kharrow Foot).
* **quarry**: a white or grey face with a spoil heap and a crane (the Chalk Pit, the Flint Pits,
  the Old Quarry, the Oskel Rake).
* **shieling**: a turf hut and a fold on the high fell.
* **vista**: a cairn or a bench where a view is the point (the Last Look, the Larkmouth bench).

## 11. For the builder

* **The landing under the Stair Head** is drawn with the fields agreed with the land builder.
  `coast.shelves` holds the shelf at 4 m, with a 90 m bank down to it from the rim. The coast
  polygon carries a lobe over the bank, with a 4 m cliff along its seaward edge and the 78 m
  cliffs split around it. The road `core:road/stair_head_hushline_stair` is of kind "stair",
  and the opening's camp builder looks for that id. A pad pins core:poi/hushline_stair to the
  shelf at 4 m (radius 26). The Stair is one traverse at about 77° to the fall line, turning
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
  against the built world once it is rebuilt.

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
| `core:place/hushline` | -1900, 4000 | 0, 3990 | The Ash Heath |
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
| `core:poi/heron_watch` | -2100, -400 | -2460, -640 | The Delta |
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

The places (with their residents) are in bold. "Where" gives the province and the position.

#### Hearthvale (45 new)

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
| The Pinfold | ruins | The Vale of the Larkbourne (520, 1450) | Every morning there is one more sheep in the Pinfold than anybody put there, and nobody in the Vale will own it. |
| The Wellspring | shrine, Hearthstone | The Vale of the Larkbourne (215, 2578) | A pilgrim's flask comes back up the glass bed full, and the woman who filled it is written on the Chapter Roll as gone on. |
| Fallowfold | **hamlet** | The West Downs (-620, 2080) | A ewe came back from the south pasture grey to the skin and will not go into the pond; the shepherd wants her named, and does not know by whom. |
| Ash Watch | tower | The West Downs (-380, 2310) | The beacon was lit last night and nobody on the Ash Watch roll admits to lighting it. |
| The Chalk Cell | ruins | The West Downs (-1150, 1050) | Bread left at the cell's door is being taken again, after thirty years. |
| The Roll Stone | stones | The West Downs (-360, 1600) | A fifth name has been cut beneath the four in a Warden's hand, and struck through, and nobody at the Rest will say whose. |
| The Warden Barrow | ruins | The West Downs (-1150, 1900) | The youngest at the Rest has stopped ringing the bells, because one of them rings back. |
| Wolf Holt | ruins | The West Downs (-1450, 1350) | The pack's leader wears a Warden's collar-bell, and the Wardens would like to know whose. |

#### Cinderlea (33 new)

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

#### Brightwater (27 new)

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

#### The Briarwold (32 new)

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

#### Skerrow Heights (49 new)

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
