# World life: conventions for the region agents

Six agents, one a region (hearthvale, briarwold, brightwater, cinderlea, sedgemire, skerrow), each
fixing its weak places, adding larger ones and filling empty land, at the same time and without a
world build between them. This page is how to do that without editing the same files,
and how to see what you made before the world is built again.

The starting point for each region is its audit: `docs/review/world_life/audit_<region>.md` and
its map `audit_<region>.png`, made from the w4096f world (2026-09-28).

## 1. Which files are yours

| What | Where | Owner |
|---|---|---|
| POI defs | `game/content/packs/core/pois/<region>.json` | the region |
| POI encounters (foes, a find lying there) | `encounters/pois_<region>.json` | the region |
| wayside finds' encounters, items, notes | `encounters/wayside_<region>.json`, `items/wayside_<region>.json`, `books/wayside_<region>.json` | the region |
| anything else new for your places (NPCs, dialogue, quests, books, items) | a **new** file named for your region, e.g. `npcs/poi_people_<region>.json`, `quests/places_<region>.json`, `dialogues/places_<region>.json` | the region |
| a place's own builder | `game/world/pois/regions/<region>.gd` (see 3) | the region |
| the hook table `tables/poi_hooks.json` | generated: `python3 tools/poi_hooks.py` | everyone; on a merge conflict, take either side and run it again |
| `tools/world/worldgen/poi_order.json` | frozen (the order the one-file registry had, so the split changed no build) | nobody: never edit |
| `places/places.json` (settlements), `tools/world/atlas/atlas.json` (roads, pads) | shared | nobody in this work: a new road or settlement is the coordinator's |
| the kinds' builders `poi_builders*.gd`, `poi_kit.gd`, `poi_masonry.gd` | shared by every region | avoid; a fix to a kind changes that kind in all six regions. Ask the coordinator, or build your variant in your region's file |

Every reader reads every file in a content folder: the game's ContentDB always did, and the tools
(`tools/world/worldgen/content.py`, `rows()` / `poi_registry()`) now do too. So a new file under
`pois/` (another agent's `pois/_interiors_showcase.json`, say) just works. A POI file named for a
region holds only that region's POIs; a file whose name starts with `_` may hold any.

Other agents at work: 0-B (road encounters, caravans, ambushes), 0-C (large interiors; may add
`pois/_interiors_showcase.json`), the Ranger film (atmosphere, cinematics). Stay out of their files.

## 2. Ids and defs

- An id is `core:poi/<snake_case>`, unique in the whole pack (places included), named for the place
  (`core:poi/drovers_hall`, not `core:poi/hearthvale_new_3`). Never reuse or rename an existing id:
  saves, quests and the hook table name them.
- A def needs `id`, `name`, `region`, `kind` (one of `PoiDressing.KINDS_BUILT`), `position` [x, z]
  on the region's own dry ground (a bridge, wreck, waterfall or `strange` may stand in water),
  `hearthstone` (true/false), `unique_feature` (the brief the builder answers) and `story`.
  `encounter` (a sentence), `visible_from`, `ward`, `path`, `wayside` as before.
- **`pad_radius_m`** (new, 8-60): a larger place asks for a larger pad. Without it a POI gets 25 m (a
  camp 22, a wayside find 14). The build flattens the pad's level core to 0.7 of it and blends
  the skirt over 0.9 of it past that, so a place whose pieces reach 30 m from its middle wants
  about `pad_radius_m: 36`. The audit's `past_pad` says when pieces stand off the pad.
- **`builder`** (new): the name of a static function in `game/world/pois/regions/<region>.gd` that
  builds this place instead of its kind's builder (section 3).
- Keep a new place 200 m and more from the next where the audit shows empty land; never put its
  pad on top of another's or across a settlement's, nor a road through its level core (unless it
  is road furniture: a bridge, a waystone, a well ...), nor on ground steeper than 18 degrees on
  average under the pad (the build cuts and fills it into an embankment).

## 3. A region's own builders

`game/world/pois/regions/<region>.gd` (one a region, already there) holds static functions
`static func <name>(d: PoiDressing) -> void`. A def with `"builder": "<name>"` is built by it in
place of its kind's builder; it may call the kind's builder first and add to it:

```gdscript
static func drovers_hall(d: PoiDressing) -> void:
    await PoiDressing.kind_builders().LAND.farmstead(d)   # the kind's own (LAND, WAYSIDE: its consts)
    var k := d.kit                                         # PoiKit: on_ground, props, masonry, hearthstone ...
```

The kind stays the def's `kind` (the tests, the map and the audit know a place by it). A name
the script does not have is said in the log and the place is built as its kind
(`tests/unit/test_poi_preview.gd`).

## 4. Seeing it without a world build

The build (`./run.sh world`, over an hour) stays the source of truth: its pad also answers the
roads, the sightlines and the water, and the next build's entry replaces a preview. Do not build
or install the world; the coordinator does that once the regions are merged.

**Previews** (`game/world/pois/poi_preview.gd`, `PoiPreview`): when the world stands up, every
POI def the installed `world/generated/pois.json` does not have is stood up where its def says,
on a pad laid then on the ground as it is (Terrain3D's heights and the runtime map), the build's
shape of pad: level at the median of the ground under 0.75 of its radius, blended back over its
skirt. The cells' scatter is cleared off the pad and moved with the skirt. This happens in the
game, the tests and the capture runs alike, with no flag. A POI the build *has* but you moved
or resized is previewed only when asked: `--preview-pois=a,b` on Godot's command line,
`WICKMERE_PREVIEW_POIS=a,b` in the environment, or `"preview_pois": [ids]` in a capture plan.

**A contact sheet of one place** (Compatibility renderer under xvfb, four views: three from about
eye height, the first from the nearest road's side, and one from above):

```
GODOT=$HOME/godot/Godot_v4.7.2-stable_linux.x86_64 ~/bin/heavy python3 tools/world/poi_sheet.py drovers_hall
    -> captures/poi_sheet/drovers_hall.jpg (each tile labelled with its draw calls and primitives)
       --time 20.5 for dusk; several ids at once; --built for the built world's own, for a before/after;
       --plan-only writes captures/poi_sheet/<name>/plan.json for ./run.sh shots
```

It prints each view's cost against the budgets below and deletes its PNGs. It stands the whole
world up drawn, so it takes 5 minutes on a quiet machine and 25 or more when other renders share it:
run it in the background and wait, and do not wrap it in a short `timeout`. Delete the sheets you
no longer need (`captures/` is not committed; the disk is shared). Commit a sheet you want kept
under `docs/review/world_life/<region>/`.

**In a test**: stand the world up as usual (`world.tscn`): a new POI is there, on its pad, and
raised when the streamer reaches it. `PoiPreview.ask([...])` before the world stands previews an
edited one. `PoiPreview.pads` lists the pads laid.

## 5. The audit

```
python3 tools/world/region_audit.py <region>           # a minute; reads the committed probe
GODOT=... ~/bin/heavy python3 tools/world/region_audit.py <region> --probe   # re-measure every POI (few minutes)
python3 tools/world/region_audit.py all --probe         # all six from one Godot run (~15 min)
```

Writes `docs/review/world_life/audit_<region>.md`, `.png`, and with `--probe`
`probe_<region>.json` (tools_gd/poi_probe.gd via `./run.sh poi-probe`: each POI raised headless on
its own, measured, and put through the seat audit). A POI not yet built counts where its def
stands, with its future pad, so your new places close gaps in the report before any build.

- **(a) Empty land**: land a body walks (dry, no steeper than 32 degrees, 250 m in from the map's
  edge) further than 200 m from the edge of every place's, POI's and signpost's or milestone's pad,
  in stretches, largest first: middle, area, extent, slope, province and biome, road, and up to
  three suggested sites (gentle ground, as far from everything as the stretch allows, near a road
  where one is near). The map: magenta is the empty land, `+` the sites.
- **(b) POIs**, weakest first, with the **impact score**: size (reach from the middle to the
  furthest piece: <8 m 0, <14 1, <22 2, <32 3, else 4); interactables in the dressing 1 each up to
  3; foes 1, and 1 more for four or more; loot (an encounter's `lies`, a find, a container) 1;
  NPCs living or standing there 1, 2 for two or more; a quest that sends you there 2; an interior
  2; a landmark model 2; a Hearthstone 1. **Weak** is 3 or under, **strong** 8 or more, **small**
  a reach under 10 m. Wayside finds are small by design and counted apart.
- **(c) Placement**: the seat audit over each POI's own pieces (floating, buried, sunk, standing in
  a road, overlapping, a lamp hung from nothing), `past_pad`, `steep_skirt` (a cut or embankment),
  `steep_site` (a new POI on steep ground), `overlap_pad`, `road_through`, `in_water`.

## 6. Definition of done, per region

```
python3 tools/world/region_check.py <region>                              # seconds: content, placement, density
GODOT=... ~/bin/heavy python3 tools/world/region_check.py <region> --godot   # and raise the new POIs in Godot
    --edited a,b    POIs you moved or resized: previewed where their defs now say, and checked as new
GODOT=... ~/bin/heavy ./run.sh test --filter=objects_seated_<region>,test_poi_preview,test_pois
python3 -m pytest -q tools/world/tests/test_content_split.py tools/world/tests/test_region_check.py
```

`region_check.py` prints PASS or FAIL for three parts and exits 1 on any FAIL:

1. **Content**: files and ids as in sections 1 and 2; every encounter, enemy, boss, item and book
   named exists; the atlas check says nothing against your POIs; the hook table is current.
2. **Placement** of your new and edited POIs: no pad on another's or over a settlement's, no road
   through a level core, no steep site; with `--godot`, nothing floating, buried, sunk or in a road
   among its pieces, no piece more than 4 m past its pad, and the place's own cost within budget.
3. **Density**: your region against `tools/world/region_targets.json` (today's baseline beside
   each): the share of walkable land further than 200 m from anything, the largest empty stretch,
   the weak share of the non-wayside POIs (at most 25%, Skerrow 30%), the count of strong POIs and
   of POIs. All six fail density today; meeting it is the work.

When done, run the audit with `--probe` for your region and commit the report, map and probe.

## 7. Budgets

The frame budget is DESIGN.md section 11's worst view: **2000 draw calls and 1.5 M primitives**
(Compatibility, 1600x900), anywhere. A place's views must stay under it with room for the people,
the foes and the weather a sheet does not show:

| Measure | Aim | Limit |
|---|---|---|
| a view at a place (each `poi_sheet.py` tile) | 1400 draws, 1.1 M primitives | 2000 draws, 1.5 M primitives |
| one place's own pieces (the probe's `draws` / `primitives`, before shadows) | 150 draws, 250 k triangles | 300 draws, 600 k triangles (`region_check --godot` fails past it) |
| a large place (pad 40 m and more) | 250 draws, 400 k | 300 draws, 600 k |

Today's places run from 2 to 96 draws each (median 21; the Stair Head 245) and up to 540 k
triangles (median 58 k): the audit's table has each. Masonry merged by the kit
is one draw a material; many loose props are one draw each. Reuse the kit's meshes and let it
merge, and keep lights to the NightLights pool (a dressing's fires are sources, not lights).

## 8. The machine

Shared: 4 cores, 15 GB. Run every Godot or other heavy command as
`GODOT=$HOME/godot/Godot_v4.7.2-stable_linux.x86_64 ~/bin/heavy <cmd>`, one at a time, and render
only what must be seen, one sheet at a time. Tests: `./run.sh test --filter=a,b`. Delete scratch
renders when done. Never `pgrep -f`/`pkill -f` a pattern that matches your own shell.
