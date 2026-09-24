# The atlas

`tools/world/atlas/atlas.json` is the map of Wickmere as somebody drew it: where the coast runs,
which province is which, where the ranges stand and how high, where every river rises and where
it meets the sea, where the lakes lie, the woods, the roads, and where a new game begins. The
world builder makes the land from it. Noise is only the detail between the lines: the seed
decides how a hillside is broken, never where the hills are.

```
python3 tools/world/atlas/check_atlas.py                 # check the committed atlas
python3 tools/world/atlas/check_atlas.py other.json      # or any other
./run.sh world                                           # build the world from it
python3 tools/world/build_world.py --atlas other.json --out /tmp/w --size 1024   # a quick look
python3 tools/world/atlas/render_build.py --world /tmp/w --atlas other.json --out /tmp/map.png
```

This document is the contract the builder is written to; where the two disagree, the builder is
wrong. `render_build.py` draws a built world's heights, water, roads and rivers with the atlas over
them, which is the quickest way to see whether the land is the map.

The check reads `atlas.schema.json` (the shape of the document, which an editor can also use)
and then what a shape cannot say: that every region named exists in the content packs, that no
polygon crosses itself, that every river ends in water, that every place stands on land in a
province of its own region, that every road runs between places that exist. An **error** is
something the builder cannot make a world from, or that makes a world the game's own tests
refuse. A **warning** is probably a slip. Fix the errors; read the warnings.

What the atlas does *not* hold: places and points of interest. They stay in the content packs
(`game/content/packs/core/places/places.json`, `pois/pois.json`), each with its `position`
and `region`, and every one gets a flattened pad wherever it stands. Move a town by moving it
there; the atlas only has to agree with it (the check says where it does not).

## Conventions

* **Metres**, **x east**, **z south**, origin at the centre. The world is 8192 m square, so
  every coordinate lies in -4096..4096. North is **-z**: a point at z = -3000 is in the north.
* **Heights** are metres above the sea, which is at 0.
* **Bearings** (`facing_deg`, `grain_deg`) are compass bearings: 0 is north (-z), 90 east (+x),
  180 south (+z), 270 west (-x). The direction of bearing b is (x, z) = (sin b, -cos b).
* A **polygon** is a list of `[x, z]` corners, at least three, in either winding, not closed
  (the last corner joins the first by itself), and must not cross itself.
* A **path** is a list of `[x, z]` points, at least two, in order.
* A few hundred corners for a coast or a province is plenty. The builder rasterises at 4 m and
  blends every border, so there is no need to follow a line closer than about 20 m.
* Ids are lower case with underscores. Rivers, roads and places use the content packs' own
  form (`core:river/larkbourne`, `core:place/merrowby`).

## The document

```json
{
  "version": 1,
  "name": "Wickmere",
  "world_size_m": 8192,
  "sea_level_m": 0,
  "provinces": [ ... ],
  "coast":     { ... },
  "ranges":    [ ... ],
  "peaks":     [ ... ],
  "valleys":   [ ... ],
  "rivers":    [ ... ],
  "lakes":     [ ... ],
  "forests":   [ ... ],
  "roads":     [ ... ],
  "pads":      [ ... ],
  "start":     { ... }
}
```

`version`, `world_size_m` (8192) and `sea_level_m` (0) are fixed for now. `provinces` and
`coast` are required; every other list may be empty or left out. `_doc` may hold a note.

### How the land is made from it, in order

1. **Provinces** give the ground its level and the grain of its hills: each province's
   `base_height_m` is its low ground, and its hills rise `relief_m` over it in its `character`,
   blended with its neighbours across `blend_m` of border.
2. **Ranges** stand at their crest heights and **peaks** at theirs, blended into that ground.
3. **Valleys** are cut into it.
4. **The coast**: outside the coast polygon the land falls to the seabed; along a `cliffs` path
   it stands to the water and drops sheer. **Lakes** are carved to their beds and their shores
   raised a little above the water.
5. **Erosion**: a drainage network is cut into the land by biome, so valleys branch the way
   water finds them down to the sea and the lakes; then the coast and the lakes are laid again
   over it, so the drawn water wins.
6. **Causeways** are raised across the lakes they cross.
7. **Pads**: every place and POI in the content packs gets a platform, flattened at the height
   of the ground under it (raised clear of standing water).
8. **Rivers** are cut along their authored paths in valleys of their own, the water falling from
   source to mouth all the way, whatever the land does.
9. **Roads** are routed on the ground between their ends and through their `via` points,
   graded and cut in; a road that crosses a river crosses at a ford.
10. Each province's **landforms** go on at a walking scale, off the roads and the pads.
11. Two-metre **detail** noise, by biome.

The authored water always wins: nothing laid later may dam a river or fill a lake.

## provinces

The land is divided into provinces. A province is one kind of country: one biome, one level,
one grain of hills. Provinces should tile the land. Where two overlap, a point belongs to the one
it is deeper inside; a gap belongs to the nearest. A region of the content packs (its name,
music, weather, danger and creatures) may be made of several provinces, and every region needs
at least one, or nothing of it can be entered.

```json
{
  "id": "hearthvale_downs",
  "name": "The Hearthvale Downs",
  "region": "core:region/hearthvale",
  "polygon": [[x, z], ...],
  "biome": "downs",
  "base_height_m": 38,
  "relief_m": 55,
  "character": "rolling",
  "landform": ["lynchets", "barrows"],
  "grain_deg": 38,
  "roughness": 0.3,
  "blend_m": 300
}
```

| field | |
|---|---|
| `id`, `name` | the province's own name, for the debug map and the build's log |
| `region` | the content region it belongs to (`core:region/...`). This is what the game calls the place you are standing in. |
| `polygon` | its outline |
| `biome` | its ground: textures, flora, trees, rocks, colour (below) |
| `base_height_m` | its low ground -- the floors of its valleys, the plain its hills stand on -- before ranges, peaks and valleys: -5 to 800 |
| `relief_m` | how high its own hills rise over that, trough to crest: 0 to 600 (a `flat` province shows a tenth of it) |
| `character` | the shape of those hills (below) |
| `landform` | its walking-scale features, any number (below); none by default |
| `grain_deg` | optional: the bearing its hills and valleys run along. Without it they run every way. |
| `roughness` | optional, 0 to 1: how broken the hills are at the small scale; 0.3 by default |
| `blend_m` | optional: how wide its border with a neighbour blends, 50 to 1500; 300 by default. A border between two provinces of very different height wants more. |

**Biomes.** A biome is a set of rules the builder already has: which terrain textures, which
flora and trees, which rocks, what colour the ground is tinted and how deep the valleys erode.
There are six, one per region of the old world, and a new one is a change to the generator
(ask for it; do not invent a name, the check refuses it).

| biome | ground |
|---|---|
| `downs` | chalk grassland: turf, chalk showing on the slopes, barley and orchard fields, hedgerows, oak copses and hawthorn (the Hearthvale) |
| `lake_basin` | shingle and grass round open water: pollard willows at the water, limes along the lanes, reed fringes (Brightwater) |
| `delta` | marsh: peat and mud, reeds, willow and alder carr, standing pools in its lowest hollows, where the ground is under its water table, three quarters of a metre over its low ground (Sedgemire) |
| `forest_rise` | old forest on granite: forest floor and moss, giant oaks and black ash, fern and bracken, granite breaking through (the Briarwold) |
| `mountains` | karst: limestone and scree, heather moor, hardy pine and juniper and rowan, snow above 520 m (Skerrow) |
| `ash_plateau` | the ash: grey ash soil, fused stone, dead ash trees and stumps, grey grass and single poppies (Cinderlea) |

**Characters.** The shape the province's `relief_m` takes.

| character | |
|---|---|
| `flat` | a plain: the relief is a gentle undulation, as if a tenth of it |
| `marsh` | a plain at the water table: low islands of peat among braided hollows that fill with water in a `delta` province |
| `rolling` | broad rounded hills and wide shallow valleys: downland |
| `hills` | steeper, closer hills with sharper valleys between |
| `ridged` | long crests and gullies running along `grain_deg` (every way without it) |
| `plateau` | a level top stepped at its edges, cut by steep-sided valleys |
| `mountains` | massifs with sharp crests and crags, the relief at full height |

**Landforms.** The features a person walking notices, a few metres to a few tens of metres
high, laid on last (`worldgen/landforms.py`). They are held off every pad, every road and
every authored sightline's line.

| landform | |
|---|---|
| `raised_beaches` | level benches round a lake at the heights it once stood, each backed by the low cliff it cut (a lake in or beside the province) |
| `dune_ridges` | ridges parallel to a lake's shore, a steep face to the water and a long back |
| `levees` | silt banks either side of every river through the province, the only dry lines in a marsh |
| `oxbows` | crescent hollows where a river used to loop, with low rims |
| `granite_stair` | the rise goes up in benches, not ramps |
| `tors` | outcrops standing on the lips of the benches |
| `limestone_scars` | long level bands of cliff with a pavement above and scree below, across every hillside at the same heights |
| `shakeholes` | sinks pocking the moor |
| `buried_streets` | a straight grid of sunken streets and mounded blocks under the ground (the Builders' city under the ash) |
| `lynchets` | a slope stepped where it was ploughed along the contour |
| `barrows` | round mounds in lines behind a crest |

## coast

```json
{
  "polygon": [[x, z], ...],
  "islands": [[[x, z], ...], ...],
  "seabed_m": -26,
  "shelf_m": 350,
  "beach_m": 60,
  "cliffs": [{"path": [[x, z], ...], "height_m": 30}],
  "shelves": [{"polygon": [[x, z], ...], "height_m": 4, "bank_m": 90, "notches": [[x, z]]}]
}
```

`polygon` is the mainland: everything outside it is sea. `islands` are more land. Offshore the
ground falls to `seabed_m` (-26 by default) over `shelf_m` (350 m); ashore it comes down to
the water's edge over `beach_m` (60 m), which is a beach, a strand or a tide-flat depending on
the biome behind it. Along a `cliffs` path (within about 60 m of it) the land holds its height
to the shore and drops `height_m` to the sea.

A `shelves` entry is a flat rock shelf at `height_m` (1 to 200): a landing at the foot of a cliff,
a ledge over the sea. Its polygon is land even where the coast polygon does not reach, the ground
inside it is flat to a few centimetres, and within `bank_m` (60 m by default) the land behind it
comes down to it as a steep bank -- steep enough to want a `stair`, not a sheer face. The sea past
its seaward edge is the coast's: draw a low `cliffs` entry along that edge to stand it up out of
the water. A place on a shelf gets a pad at the shelf's height; a `pads` entry makes sure of it.

The seaward edge is not built as the clean line it is drawn as. It wanders in and out by up to
7 m (spurs and bites some thirty to ninety metres apart), and blocks fallen from it lie in the
water at its foot. Near the land behind, where the edge runs into the coast, it tapers back to
the drawn line. A pad's footprint is left whole. `notches` are points on the seaward edge where
the shelf is cut down into the water: a slot 8 m wide through the face, 4 m into the shelf,
with its floor falling from a couple of metres under the shelf into the sea, for a stair or a
slipway to go down. A notch more than 20 m from the shelf's edge is an error.

The world stops at its square edge. Close it: sea, or a range too steep to climb. A province
that runs flat into the edge is a place a player walks off the map. If the coast polygon covers
the whole square, there is no sea.

## ranges

A range is a line of high ground: a crest you give the heights of, falling away either side.

```json
{
  "id": "the_north_wall", "name": "The North Wall",
  "ridge": [[x, z, crest_m], [x, z, crest_m], ...],
  "width_m": 1600,
  "profile": "ridge",
  "face": "left",
  "rock": "limestone"
}
```

| field | |
|---|---|
| `ridge` | the crest, point by point, each with its height above the sea; the crest height runs straight between points, and a notch (a pass) is a low point in it |
| `width_m` | foot to foot, across the crest |
| `profile` | `ridge` (a sharp crest, even sides; the default), `rounded` (a whaleback), `scarp` (one steep face, one long gentle back), `massif` (a broad high block with a broken top) |
| `face` | for a `scarp`: which side is the steep one, `left` or `right` walking the ridge from its first point to its last (with north up, walking north, left is west) |
| `rock` | what shows where it is steep: `granite`, `limestone`, `chalk`, `fused_stone` or `scree`. Checked, and not yet read by the texture rules: a range's flanks take the rock of the biome under them until they are |

At its crest a range is the height drawn for it, whatever the provinces put there, and it
blends into their ground over its width: it rises out of low ground, and a pass drawn low in a
range across high ground is low (draw a valley through it if a road is to reach it from lower
country). Its crest is broken by noise of a few metres to a few tens of metres, more on a
`massif`, so a range drawn as a straight line still does not look ruled.

## peaks

```json
{"id": "grey_man", "name": "The Grey Man", "at": [x, z], "height_m": 690, "radius_m": 600, "shape": "cone"}
```

A single summit: `height_m` above the sea at `at`, its foot `radius_m` out. `shape` is `cone`
(the default), `dome`, `crag` (steep and broken) or `mesa` (flat-topped, steep-sided). A peak
never lowers the ground.

## valleys

```json
{"id": "the_long_dale", "path": [[x, z], ...], "depth_m": 40, "width_m": 400, "profile": "u"}
```

A valley is cut `depth_m` below the land beside it, `width_m` from rim to rim, along its path.
`profile` is `u` (a flat floor and steep sides, as ice leaves; the default), `v` (as water
leaves) or `gorge` (sheer walls, a narrow floor). A river may run down a valley, and usually
should; the valley does not make the river.

## rivers

```json
{"id": "core:river/larkbourne", "name": "The Larkbourne",
 "path": [[x, z], ...], "width_m": [4, 8], "valley_m": 300}
```

`path` runs from the source to the mouth, and the mouth must be in water: the sea, a lake, or
another river (within 40 m of its path; a tributary joins at its own level). The water falls
all the way down, whatever the land does: where the path crosses high ground the river cuts a
gorge through it. `width_m` is the width at the source and at the mouth. `valley_m` is the
width of the valley it runs in (by default twelve times its width at that point); 0 leaves the
land alone apart from the channel and its banks. A river rising in a lake is its outflow and
leaves at the lake's level.

Between its drawn points the builder lets a river wander: meanders on flat ground, a gentler
sway in steep country, straight through every drawn point and near any place or point of
interest beside it. Draw the bends the valley makes; the builder draws the river's own. An
optional `"meander"` (0 to 1.5, default 1) scales that wander: 0 keeps the river to its drawn
line, as in a slot gorge.

## lakes

```json
{"id": "the_mere", "name": "The Mere",
 "polygon": [[x, z], ...], "level_m": 8, "depth_m": 14,
 "islands": [{"name": "Tollmere", "polygon": [[x, z], ...], "height_m": 17}],
 "cliff_shore_deg": 0, "reed_shore_deg": 270}
```

The polygon is the landward edge of the lake's shore. The water stands at `level_m` inside it,
beginning some thirty metres in (24 to 56 m on a built lake): the first metres inside the line are
a shingle shore held a metre and a half over the water, and a cove drawn narrower than about a
hundred metres closes up into a bump in the built shore, so draw a lake in features of a few
hundred metres (docs/ATLAS.md, section 11). The bed falls to `depth_m` below the level toward the
middle. The land round it is held a metre or two above the water for a few hundred metres, so
there are no dry hollows under the lake's level beside it, and no landform digs one there.
`islands` stand in it to their `height_m`. `cliff_shore_deg`, when given, is the bearing from the lake's middle of a stretch of
shore that stands in a low cliff at the water; `reed_shore_deg` the bearing of one that runs out
in a shallow reed shelf. A lake must be on land. One with no river out of it is a still water,
which is allowed.

`shore_m` (10 to 320, default 320) is how far the lake's shore and bank reach from its line.
Every distance above scales with it: the thirty metres inside the line before the water, the
shingle, the bank back to the land, and the few hundred metres held over the water. The default
suits a lake in a basin. Give a pool under a fall, or in a gorge, a short one (about 40): at 320,
the Weaver's Linn flattened a basin three hundred metres across into the wold, fall and all.

## forests

```json
{"id": "the_briarwood", "polygon": [[x, z], ...], "kind": "ancient", "density": 0.9}
```

A wood: its trees at `density` (0 to 1, 1 a closed canopy) inside the polygon, thinning over
the last 40 m of its edge. The biome's own copses, hedgerow trees and waterside willows grow
everywhere else as before, so a province without a forest is not treeless; it is open country.

| kind | trees |
|---|---|
| `oakwood` | oak, hawthorn and yew |
| `ancient` | giant oak and black ash, fern and bracken under them |
| `pine` | hardy pine, juniper and rowan |
| `wetwood` | willow and alder carr |
| `limewood` | lime and pollard willow |
| `deadwood` | dead ash and char stumps |
| `orchard` | apples in rows |

## roads

```json
{"from": "core:place/merrowby", "to": "core:place/gullhithe",
 "via": [[x, z], ...], "kind": "road"}
```

A road from one place or POI to another (both must be in the content packs), through each `via`
point in order. Between those points the builder finds the way on the ground: round a hill
rather than over it, up a slope in turns, across a river at its narrowest. `via` is how you say
which side of the hill, which pass, which ford. `kind` sets its width: `highway` 6 m, `road`
5 m (the default), `lane` 4 m, `track` 3.5 m; `causeway`, 6 m raised on a bank across open
water (the Long Stride), laid straight between its points over the water; or `stair`, 3 m, laid
straight from point to point with no routing and graded as steep as thirty-five degrees (0.7):
steps cut into a bank, a cliff path. Give a stair its switchbacks as via points, each leg no
steeper than that over the ground it crosses. `id` is optional
(`core:road/<from>_<to>` by default).

Only the roads listed are built, and a settlement with none is only reached across country (the
check warns). Every town and village gets a street through it along its two most opposed roads,
and a cross street where a third road comes in across them.

## pads

```json
{"place": "core:poi/hushline_stair", "level_m": 5, "radius_m": 30}
```

Every place and POI gets a flattened pad where the content packs put it, at the median height of
the ground under it and clear of standing water. A `pads` entry says instead where that one pad
stands: at `level_m` exactly, and `radius_m` across (by default the size its kind gets). It is for
the places whose ground cannot say it: a landing at the foot of a cliff, a shelf over the sea, a
ledge. The pad is flat to 0.7 of its radius and blends into the land (or the sea) by 1.6, so a
landing drawn at the water's edge stands as a shelf with the sea falling away past its rim. The
check refuses a pad within a metre of the water it stands over: whatever stands or fights on it
would be awash.

## start

```json
{"at": [x, z], "facing_deg": 350, "place": "core:place/stair_head"}
```

Where a new game puts the character down, and which way they face. It must be on dry land.
The builder writes it to the world manifest (`start`, with the ground height there); `place`,
when given, is the place the opening names, and the check makes sure it exists.

## Checking the atlas

`tools/world/tests/test_atlas.py` holds the checker to this document, one mistake at a time, and
holds the committed atlas to the real content packs.
