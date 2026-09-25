"""Texture control maps and the colour map.

Every terrain slot in docs/CONTRACTS.md section 5 gets a weight field built from region
membership, slope, height, moisture, road and water masks and noise. The two strongest slots
at each texel become base and overlay, and their relative strength becomes the blend value,
so material borders are soft and irregular rather than stencilled.

The colour map is the region's palette painted with low-frequency noise (plus wetness in the
alpha channel, which Terrain3D reads as a roughness modifier), so that even before props
exist a screenshot says which region it is.
"""
from __future__ import annotations

from collections import OrderedDict

import numpy as np

from scipy import ndimage

from .grid import Grid, lerp, smoothstep
from .noise import NoiseBank, downsample, upsample

SLOTS = {
    "vale_grass": 0, "chalk": 1, "dirt_path": 2, "mud": 3, "peat": 4, "forest_floor": 5,
    "moss": 6, "granite": 7, "limestone": 8, "scree": 9, "snow": 10, "heather": 11,
    "ash_soil": 12, "grey_grass": 13, "fused_stone": 14, "shingle": 15, "cobbles": 16,
    "barley": 17, "orchard_grass": 18, "lake_bed": 19, "sand_flats": 20,
}
SLOT_NAMES = [name for name, _ in sorted(SLOTS.items(), key=lambda kv: kv[1])]
SNOW_LINE = 520.0


## How many full-resolution patch fields a SurfaceContext keeps at once (each is 64 MB at 4096).
## The texture rules ask for some forty; kept them all, they were two and a half gigabytes of a
## build that has to fit beside everything else on the machine. The six that jitter every slot's
## weight are asked for on every slot, so they stay; the rest are made again from the bank's
## 1024 lattice when they come round a second time.
PATCH_KEEP = 10


class SurfaceContext:
    """Everything the texture rules read, all at full resolution."""

    def __init__(self, grid: Grid, bank: NoiseBank, H: np.ndarray, regions: list, owner: np.ndarray,
                 water_mask: np.ndarray, water_level: np.ndarray, moisture: np.ndarray,
                 river_d: np.ndarray, road_d: np.ndarray, road_w: np.ndarray, pad_mask: np.ndarray,
                 lake, places: list, rf=None, field_labels=None, field_d=None, sea=None, shore=None):
        self.rf = rf
        # every shore's kind (worldgen.shores), on its own lattice, taken to this grid nearest
        if shore is not None and shore.shape[0] != grid.n:
            k = grid.n // shore.shape[0]
            shore = np.repeat(np.repeat(shore, k, axis=0), k, axis=1)
        self.shore = shore if shore is not None else np.zeros(H.shape, dtype=np.uint8)
        # the enclosed patchwork (worldgen/fields.py): which parcel, and how far to its edge
        self.field_labels = field_labels
        self.field_d = field_d if field_d is not None else np.full(H.shape, 1e6, dtype=np.float32)
        self.grid = grid
        self.bank = bank
        self.H = H
        self.regions = regions
        self.owner = owner
        self.water = water_mask.astype(bool)
        self.water_level = water_level
        self.moisture = moisture
        self.river_d = river_d
        self.road_d = road_d
        self.road_w = road_w
        self.pad = pad_mask
        self.lake = lake
        self.places = places
        n = grid.n
        gy, gx = np.gradient(H, grid.spacing)
        self.slope = np.hypot(gx, gy).astype(np.float32)          # rise over run
        self.X, self.Z = grid.mesh()
        # every province of each biome: a biome's ground is the sum of its provinces'
        self.idx: dict = {}
        for r in regions:
            self.idx.setdefault(r.shape, []).append(r.index)
        # metres from the sea, for the strand and the tide-flats
        if sea is not None and sea.any():
            from .geography import coarse_distance
            self.sea_d = coarse_distance(grid, sea)
        else:
            self.sea_d = np.full(H.shape, 1e6, dtype=np.float32)
        self.n = n
        self._patch_cache: dict = {}
        self._patches: OrderedDict = OrderedDict()
        # roads: on the carriageway, and a slightly wider verge
        self.on_road = road_d <= road_w * 0.5 + 0.6
        self.near_road = road_d <= road_w * 0.5 + 3.5
        self._road_t = None
        # Settlement footprints. `town` is the ground a settlement stands on; `market` is the
        # small open middle of a market town. Paving follows the streets and the market, not the
        # whole disc: a village green is grass, and a hard cobbled circle two hundred metres
        # across with cottages in the middle of it is the most artificial shape a generator can
        # put in a landscape.
        self.town = np.zeros((n, n), dtype=np.float32)
        self.market = np.zeros((n, n), dtype=np.float32)
        for p in places:
            kind = p.get("kind")
            if kind not in ("city", "town", "village", "hamlet", "fort", "lodge", "ruin_village"):
                continue
            from .roads import pad_radius as _pad_radius
            r = _pad_radius(p)
            d = np.sqrt((self.X - p["position"][0]) ** 2 + (self.Z - p["position"][1]) ** 2)
            self.town = np.maximum(self.town, 1.0 - smoothstep(r * 0.8, r * 1.05, d))
            if kind in ("city", "town"):
                self.market = np.maximum(self.market, 1.0 - smoothstep(r * 0.16, r * 0.30, d))

    def release(self) -> None:
        """Let go of everything the texture rules made but the slope, which the build reads to its
        end. The patch fields, the regions' soft weights, the dither, the settlements' footprints,
        the distance to the sea and the road's profile were held through the scatter, whose rows
        are what a build's memory peaks on: at 2048 they were 0.67 GB of the 2.07 GB it held going
        in, and at 4096 four times that."""
        self._patches.clear()
        self._patch_cache.clear()
        for name in ("town", "market", "sea_d", "on_road", "near_road", "water", "shore", "_road_t"):
            setattr(self, name, None)

    def region(self, shape: str) -> np.ndarray:
        ids = self.idx.get(shape, [])
        return np.isin(self.owner, ids) if ids else np.zeros((self.n, self.n), dtype=bool)

    def region_w(self, shape: str) -> np.ndarray:
        """Soft region membership, 0..1, with a noisy border so materials interlock.

        Using the blended weights (rather than the hard owner mask) is what stops a region
        boundary from reading as a stencil cut across the ground.
        """
        key = ("rw", shape)
        if key in self._patch_cache:
            return self._patch_cache[key]
        ids = self.idx.get(shape, [])
        if not ids or self.rf is None:
            out = self.region(shape).astype(np.float32)
        else:
            w = sum(self.rf.weight_at(k, self.n) for k in ids)
            i = ids[0]
            # (the patches made here and let go: kept in the patch cache, twelve full-resolution
            # fields stood through the textures stage for nothing at 4096)
            d = 0.5 * (self.up(self.patch_coarse(560 + i, 45, 260)) - 0.5) \
                + 0.22 * (self.up(self.patch_coarse(580 + i, 16, 70)) - 0.5)
            out = np.clip(smoothstep(0.24, 0.62, w + d), 0.0, 1.0).astype(np.float32)
        self._patch_cache[key] = out
        return out

    def patch(self, salt: int, wl_min: float = 40.0, wl_max: float = 220.0) -> np.ndarray:
        """0..1 patchy noise for breaking up material boundaries.

        Generated on a 1024 lattice and upsampled linearly: patches are hundreds of metres
        across, so the extra resolution would cost seconds and show nothing.
        """
        key = (salt, wl_min, wl_max)
        out = self._patches.get(key)
        if out is not None:
            self._patches.move_to_end(key)
            return out
        out = upsample(self.patch_coarse(salt, wl_min, wl_max), self.n, order=1)
        self._patches[key] = out
        while len(self._patches) > PATCH_KEEP:
            self._patches.popitem(last=False)
        return out

    def patch_coarse(self, salt: int, wl_min: float = 40.0, wl_max: float = 220.0) -> np.ndarray:
        """`patch` on its own lattice (at most 1024), before the upsample; kept, 4 MB each."""
        key = ("coarse", salt, wl_min, wl_max)
        got = self._patch_cache.get(key)
        if got is None:
            gen = min(self.n, 1024)
            f = self.bank.field(salt, beta=1.6, wl_min=wl_min, wl_max=wl_max, n=gen)
            got = self._patch_cache[key] = (0.5 + 0.5 * np.tanh(f)).astype(np.float32)
        return got

    def up(self, a: np.ndarray) -> np.ndarray:
        """A coarse lattice's field at this grid (`upsample`, linear)."""
        return upsample(a, self.n, order=1)

    def gradient(self) -> tuple:
        """(d/dz, d/dx) of the height, metres a metre."""
        return np.gradient(self.H, self.grid.spacing)

    def curvature(self) -> np.ndarray:
        """The Laplacian of the height on an 8 m lattice, normalised by its 95th percentile and
        clipped to +-1 (positive in a hollow): on that lattice, for `_weights` to upsample."""
        key = "curv"
        if key not in self._patch_cache:
            _lap = ndimage.laplace(downsample(self.H, min(self.n, 1024)))
            _lap = _lap / (np.percentile(np.abs(_lap), 95) + 1e-6)
            self._patch_cache[key] = np.clip(_lap, -1.0, 1.0)
        return self._patch_cache[key]

    def dither(self, salt: int) -> np.ndarray:
        """White noise at one value per texel, for breaking the control map's own grid.

        Terrain3D only interpolates between neighbouring control texels on Forward+; on the
        Compatibility renderer each texel takes its own base, overlay and blend, so a material
        boundary is a hard staircase at texel resolution unless the boundary itself is
        dithered. One field is generated and rolled per slot: rolling decorrelates the slots
        (a shared field would scale every weight alike and change no ranking at all) without
        paying for a second full-resolution array.
        """
        if "dither" not in self._patch_cache:
            rng = np.random.default_rng(self.bank.seed ^ 0x5EED)
            self._patch_cache["dither"] = rng.random((self.n, self.n), dtype=np.float32)
        base = self._patch_cache["dither"]
        return np.roll(base, (salt * 37 + 11, salt * 53 + 7), axis=(0, 1))

    def parcel(self, salt: int) -> np.ndarray:
        """A stable 0..1 per enclosed field, for deciding what that field carries."""
        key = ("parcel", salt)
        if key not in self._patch_cache:
            if self.field_labels is None:
                self._patch_cache[key] = self.patch(salt, 90, 380)
            else:
                from .fields import parcel_value
                self._patch_cache[key] = parcel_value(self.field_labels, salt)
        return self._patch_cache[key]

    def road_t(self) -> np.ndarray:
        """Distance from the road centre as a fraction of its half-width: 0 at the crown, 1 at
        the edge of the worn surface, more beyond it.

        The half-width wanders along the road, because a road worn by carts is not a stencil
        of constant width. Everything that draws a road -- the carriageway, the ruts, the
        verge, the crown lightening in the colour map -- reads this one profile, so they
        cannot disagree about where the road is.
        """
        if self._road_t is None:
            wobble = 0.80 + 0.40 * self.patch(416, 22, 130)
            half = np.maximum(self.road_w * 0.5 * wobble, 1.2)
            self._road_t = (self.road_d / half).astype(np.float32)
        return self._road_t

    def near_place(self, short_ids, radius: float) -> np.ndarray:
        out = np.zeros((self.n, self.n), dtype=bool)
        for p in self.places:
            if p["id"].split("/")[-1] in short_ids:
                d2 = (self.X - p["position"][0]) ** 2 + (self.Z - p["position"][1]) ** 2
                out |= d2 < radius * radius
        return out


def _weights(ctx: SurfaceContext):
    """Yield (slot_id, weight) for every terrain material, region by region."""
    s = ctx.slope
    H = ctx.H
    m = ctx.moisture
    flat = 1.0 - smoothstep(0.12, 0.45, s)
    steep = smoothstep(0.35, 0.85, s)
    verysteep = smoothstep(0.7, 1.3, s)
    dry = 1.0 - m
    # The ground's shape, for the fells: which way it faces and whether it holds or sheds. The
    # Laplacian of the height is positive in a hollow (the ground rises all round) and negative
    # on a nose; it is taken on an 8 m grid, so it sees dales, benches and knolls, not stones.
    sheer = smoothstep(0.7, 1.1, s)
    curv = ctx.up(ctx.curvature())
    concave = np.clip(curv, 0.0, 1.0)
    convex = np.clip(-curv, 0.0, 1.0)
    _gz, _gx = ctx.gradient()
    # +Z is south (CONTRACTS 1), so a slope whose gradient points north faces away from the sun
    shaded = np.clip(-_gz / (np.hypot(_gx, _gz) + 1e-4), 0.0, 1.0)

    downs = ctx.region_w("downs")
    basin = ctx.region_w("lake_basin")
    delta = ctx.region_w("delta")
    forest = ctx.region_w("forest_rise")
    karst = ctx.region_w("mountains")
    ash = ctx.region_w("ash_plateau")
    shore_band = np.exp(-((ctx.lake.sd) / 34.0) ** 2)
    river_band = np.exp(-(ctx.river_d / 14.0) ** 2)
    # The shores by kind (worldgen.shores): a sandy beach and the dunes behind it, a shingle
    # beach, rock at the water (a ledge, a platform, a stack) and mud at a marsh's or a lake's
    # edge. Folded into the slots below that own each material.
    from .shores import SAND, SHINGLE, ROCK, CLIFF, MUD, REEDS
    sc = ctx.shore
    on_land = (~ctx.water).astype(np.float32)
    by_sea = 1.0 - smoothstep(30.0, 45.0, ctx.sea_d)
    by_lake = np.exp(-(np.maximum(ctx.lake.sd, 0.0) / 14.0) ** 2) + river_band
    at_edge = np.clip(by_sea + by_lake, 0.0, 1.0)
    beach = (sc == SAND) * (on_land * by_sea * 3.0 + (1.0 - on_land) * 1.4 * (H > -3.0))
    dunes = (sc == SAND) * on_land * (1.0 - by_sea) * (1.0 - smoothstep(170.0, 210.0, ctx.sea_d)) \
        * (1.25 + 0.6 * ctx.patch(430, 20, 90))
    stones = (sc == SHINGLE) * (on_land * at_edge * 3.0 + (1.0 - on_land) * 1.2 * (H > -2.0))
    rock_edge = ((sc == ROCK) | (sc == CLIFF)) * (H < 12.0) * (H > -3.0) * np.clip(at_edge + (1.0 - on_land), 0.0, 1.0) * 3.2
    mud_edge = ((sc == MUD) | (sc == REEDS)) * np.clip(at_edge + (1.0 - on_land), 0.0, 1.0) * 2.6

    # A road is a worn surface with a verge of trodden grass, not a stripe of one material.
    # The carriageway wanders in width and fades out rather than ending, and where the downs'
    # turf is worn through, the chalk under it shows. Each slot may only be yielded once
    # below, so these terms are folded into the material rules that own them.
    # A 4-6 m road is only two or three control texels wide, so two thin wheel ruts cannot be
    # drawn; what reads at that resolution is a carriageway whose surface varies along its
    # length, and a verge wide enough to be seen.
    # Along every field boundary there is a strip the plough never reaches: rough grass, nettles
    # and the foot of a hedge. It is what makes the patchwork visible from a hilltop.
    # wide enough to survive being seen from a kilometre away: a hedge, its bank and the
    # strip either side of it that the plough never reaches is six or seven metres, and
    # at 2 m texels anything narrower is a line that disappears at any distance
    hedge_line = np.exp(-(ctx.field_d / 6.5) ** 2)

    road_t = ctx.road_t()
    out_town = 1.0 - ctx.town
    carriage = 1.0 - smoothstep(0.70, 1.15, road_t)
    worn = carriage * (0.30 + 0.85 * ctx.patch(417, 14, 70) ** 1.3)
    verge = smoothstep(1.0, 1.4, road_t) * (1.0 - smoothstep(2.0, 3.4, road_t))

    # --- Hearthvale: chalk downs, barley, orchards -------------------------------------
    yield SLOTS["vale_grass"], downs * (0.75 + 0.35 * flat + 0.9 * hedge_line) \
        + basin * (0.20 + 0.5 * ctx.patch(410, 60, 300) ** 1.4) * (1.0 - 0.5 * shore_band) \
        + basin * 0.8 * hedge_line \
        + karst * 1.3 * flat * (0.4 + 0.6 * m) * (1.0 - smoothstep(260.0, 420.0, H)) \
        * (0.5 + ctx.patch(411, 50, 260)) \
        + karst * 1.1 * flat * concave * (1.0 - smoothstep(470.0, 540.0, H))
    yield SLOTS["chalk"], downs * (0.25 + 1.5 * steep + 0.7 * smoothstep(112.0, 150.0, H) * dry * ctx.patch(401)) \
        + basin * 1.3 * verysteep * ctx.lake.cliffness \
        + downs * out_town * 2.2 * worn + downs * rock_edge
    # Crops go in by the field. A parcel carries barley or it does not, all the way to its
    # hedge; a noise blob that runs across three fields and stops in the middle of a fourth is
    # the thing that makes farmed country read as wallpaper.
    # About a quarter of parcels carry a crop and a few more are bare under the plough. A
    # patchwork of two values reads as a chequerboard; the third value -- turned earth -- is
    # what makes it read as a year's work in progress.
    parcel = ctx.parcel(402)
    sown = smoothstep(0.70, 0.79, parcel) * (1.0 - hedge_line)
    ploughed = smoothstep(0.60, 0.67, parcel) * (1.0 - smoothstep(0.67, 0.72, parcel)) \
        * (1.0 - hedge_line)
    yield SLOTS["barley"], downs * 1.7 * sown * flat * dry * (1.0 - smoothstep(128.0, 154.0, H)) \
        * (0.7 + 0.5 * ctx.patch(403, 30, 140))
    yield SLOTS["orchard_grass"], downs * 1.25 * ctx.near_place({"tamwick", "merrowby"}, 210.0) * flat \
        + basin * (0.7 * ctx.near_place({"gullhithe"}, 170.0) * flat
                   + 0.45 * ctx.patch(413, 45, 210) ** 2 * flat) \
        + (downs + basin) * out_town * 1.1 * verge * flat

    # --- Brightwater: the Mere, its shingle shores, the black island -------------------
    under_water = ctx.water.astype(np.float32)
    yield SLOTS["lake_bed"], 2.2 * under_water * (1.0 - smoothstep(0.0, 1.0, np.abs(ctx.lake.sd) / 4000.0)) \
        * (ctx.lake.sd < 0).astype(np.float32) + 0.9 * under_water * (H > -1.0)
    yield SLOTS["shingle"], 1.9 * shore_band * (1.0 - steep) * (0.45 + 0.9 * ctx.patch(415, 20, 95)) + 0.9 * river_band * (1.0 - ctx.water) * basin \
        + stones + ash * 0.9 * beach \
        + basin * 0.55 * ctx.patch(411, 40, 180) ** 2 * (1.0 - smoothstep(120.0, 500.0, ctx.lake.sd))
    # Tollmere's island is fused black stone (the region's geology). The rule took every island in
    # the lake: Willow Isle and Gull Holm were three-quarters black glass, and look.json's Mere
    # camera, which stands on Willow Isle, saw shingle stones on black. They keep the basin's own
    # turf and shingle; 650 m from the city takes all of Tollmere's island (506 m) and neither of
    # theirs (779 m and more).
    yield SLOTS["fused_stone"], 2.4 * (ctx.lake.island_sd < 20.0).astype(np.float32) \
        * ctx.near_place({"tollmere"}, 650.0).astype(np.float32) \
        + ash * (0.5 * ctx.patch(403, 60, 260) ** 2
                 + 1.5 * ctx.near_place({"sunken_choir", "cantors_seat"}, 190.0) + rock_edge
                 + 0.9 * ctx.near_place({"greyfold", "pilgrims_ash"}, 150.0))
    # Paving goes where feet and wheels go: the streets that cross the place, the market in the
    # middle of a market town, and the causeways over the lakes. The rest of a settlement's ground
    # is the region's own turf with trodden patches in it.
    yield SLOTS["cobbles"], 3.0 * ctx.town * carriage + 2.4 * ctx.market * (1.0 - steep) \
        + 0.8 * ctx.town * (1.0 - steep) * np.clip(ctx.patch(420, 12, 60) - 0.62, 0.0, 1.0) * 3.0 \
        + 2.0 * (ctx.lake.causeway > 0.5)

    # --- Sedgemire: peat, mud, tide-flats ----------------------------------------------
    yield SLOTS["peat"], delta * (1.1 + 0.8 * ctx.patch(404) * flat) * smoothstep(250.0, 600.0, ctx.sea_d) \
        + karst * 1.6 * flat * concave * (0.3 + 0.7 * m) * (1.0 - smoothstep(470.0, 540.0, H))
    yield SLOTS["mud"], delta * (0.6 + 1.7 * m * (1.0 - flat * 0.3)) + 1.2 * river_band * (delta + basin * 0.6) + mud_edge \
        + 0.8 * m * downs * (1.0 - flat) * 0.3 + basin * 0.7 * m * ctx.patch(412, 40, 190) ** 2
    yield SLOTS["sand_flats"], delta * 2.4 * (1.0 - smoothstep(300.0, 700.0, ctx.sea_d)) \
        + 1.6 * (H < 0.6) * (ctx.sea_d < 500.0) + beach * (1.0 - 0.7 * ash) + dunes

    # --- The Briarwold: forest floor, moss, granite ------------------------------------
    yield SLOTS["forest_floor"], forest * (1.15 + 0.5 * flat * dry)
    yield SLOTS["moss"], forest * (0.55 + 1.3 * m * ctx.patch(405) + 0.9 * river_band) \
        + karst * 0.35 * m * flat * (1.0 - smoothstep(300.0, 420.0, H))
    yield SLOTS["granite"], forest * (1.7 * steep + 0.9 * verysteep) + (forest + delta + basin) * rock_edge \
        + karst * 1.5 * sheer * (0.4 + 0.6 * smoothstep(0.35, 0.7, ctx.patch(406)))

    # --- Skerrow: limestone pavement, scree, heather, snow -----------------------------
    # The fells are grass and heather on the gentle ground and rock where the ground falls away:
    # rock on the flats everywhere made them a pavement of blue-grey cells with no grass on them.
    # The limestone takes the steep ground and the high tops, the grass (the dales' own, tinted
    # by the colour map) the low gentle ground, the heather the gentle ground above it.
    # The crags are rock: limestone on the faces (granite where they are sheer, above), scree
    # only on the steep-but-not-sheer hollows under them, where it falls to. With scree's
    # steep weight above the limestone's every dale wall was a pale scree stripe. The heather
    # is a patchwork on the dry noses and benches, not a blanket: the hollows take grass, and
    # the wet ones peat (above).
    yield SLOTS["limestone"], karst * rock_edge + karst * (0.35 + 1.3 * steep + 1.0 * sheer + 0.8 * flat * smoothstep(380.0, 500.0, H)) \
        * (1.0 - smoothstep(SNOW_LINE - 60.0, SNOW_LINE + 40.0, H))
    yield SLOTS["scree"], karst * steep * (1.0 - sheer) * (0.25 + 2.2 * concave)
    yield SLOTS["heather"], karst * flat * (0.3 + 1.6 * ctx.patch(407, 70, 300) ** 1.2) * (0.35 + 0.65 * convex) \
        * (0.5 + 0.5 * dry) * smoothstep(150.0, 260.0, H) * (1.0 - smoothstep(470.0, 540.0, H)) + downs * 0.45 * ctx.patch(407, 70, 300) * smoothstep(120.0, 146.0, H) \
        + basin * 0.75 * ctx.patch(407, 70, 300) ** 1.6 * smoothstep(16.0, 40.0, H)
    # Snow lies where snow can lie. It slides off anything steep, it fills hollows and ledges,
    # and it survives longest on the shaded side -- so a face that faces away from the sun keeps
    # it hundreds of metres lower than one that faces into it. Scattering it evenly across steep
    # rock at a single height reads as a dither over the mountain rather than as weather on it.
    # Only the highest tops hold it in the open; lower down it keeps to the north faces and the
    # hollows. It used to lie on 59% of the flat ground above the line.
    line = SNOW_LINE + 130.0 - 160.0 * shaded - 100.0 * concave
    holds = (1.0 - smoothstep(0.55, 1.05, s)) * (0.1 + 0.9 * np.maximum(shaded, concave))
    yield SLOTS["snow"], 3.0 * smoothstep(0.0, 130.0, H - line) * np.clip(holds, 0.0, 1.4)

    # --- Cinderlea: ash and grey grass --------------------------------------------------
    yield SLOTS["ash_soil"], ash * (0.95 + 0.7 * dry * (1.0 - flat))
    yield SLOTS["grey_grass"], ash * (0.75 + 1.5 * flat * ctx.patch(408, 80, 320) ** 0.7)

    # --- roads everywhere ---------------------------------------------------------------
    yield SLOTS["dirt_path"], downs * 1.5 * ploughed * flat * (0.75 + 0.5 * ctx.patch(421, 6, 30)) \
        + out_town * (3.0 * carriage + 0.85 * verge) \
        + 1.4 * ctx.pad * out_town * (1.0 - steep) * ctx.patch(409, 30, 120) \
        + 0.5 * (downs + basin) * np.clip(ctx.patch(414, 25, 110) - 0.82, 0.0, 1.0) * 1.4 * (1.0 - flat * 0.4)


## The texture rules and the colour map are worked a band of rows at a time (`_Band`): every one
## of the forty-odd fields the rules make is then a band's size and not the world's. Worked whole,
## a 4096 build rose from 3.1 GB to 6.3 GB in the textures stage, its peak. Each field is the same
## number it was, texel for texel: the patches and the curvature are upsampled band by band with
## the interpolation `ndimage.zoom` uses, and the height's gradient is taken with a row either side.
BAND_ROWS = 256


def _band_up(a: np.ndarray, n: int, r0: int, r1: int) -> np.ndarray:
    """Rows r0..r1 of `upsample(a, n, order=1)`, value for value (grid_mode zoom, mode nearest)."""
    m = a.shape[0]
    if m == n:
        return a[r0:r1]
    if m > n:
        step = m // n
        return a[::step, ::step][r0:r1].copy()
    z = m / n
    ri = (np.arange(r0, r1) + 0.5) * z - 0.5
    ci = (np.arange(n) + 0.5) * z - 0.5
    I, J = np.meshgrid(ri, ci, indexing="ij")
    return ndimage.map_coordinates(a, [I, J], order=1, mode="nearest").astype(np.float32)


class _Slice:
    """An object's (n, n) arrays, rows r0..r1 of them."""

    def __init__(self, obj, r0: int, r1: int, n: int):
        self._o, self._r0, self._r1, self._n = obj, r0, r1, n

    def __getattr__(self, name):
        v = getattr(self._o, name)
        if isinstance(v, np.ndarray) and v.ndim >= 2 and v.shape[0] == self._n and v.shape[1] == self._n:
            return v[self._r0:self._r1]
        return v


class _Band(_Slice):
    """A SurfaceContext seen through rows r0..r1: what `_weights` reads, each a band of the world's."""

    def __init__(self, ctx: SurfaceContext, r0: int, r1: int):
        super().__init__(ctx, r0, r1, ctx.n)
        self.lake = _Slice(ctx.lake, r0, r1, ctx.n)
        self.Z = ctx.Z[r0:r1]

    def up(self, a: np.ndarray) -> np.ndarray:
        return _band_up(a, self._n, self._r0, self._r1)

    def gradient(self) -> tuple:
        ctx, r0, r1 = self._o, self._r0, self._r1
        a, b = max(r0 - 1, 0), min(r1 + 1, ctx.n)
        gz, gx = np.gradient(ctx.H[a:b], ctx.grid.spacing)
        return gz[r0 - a:r0 - a + (r1 - r0)], gx[r0 - a:r0 - a + (r1 - r0)]

    def patch(self, salt: int, wl_min: float = 40.0, wl_max: float = 220.0) -> np.ndarray:
        return self.up(self._o.patch_coarse(salt, wl_min, wl_max))

    def region_w(self, shape: str) -> np.ndarray:
        return self._o.region_w(shape)[self._r0:self._r1]

    def parcel(self, salt: int) -> np.ndarray:
        return self._o.parcel(salt)[self._r0:self._r1]

    def road_t(self) -> np.ndarray:
        # (the road's profile as `SurfaceContext.road_t` makes it, for these rows)
        wobble = 0.80 + 0.40 * self.patch(416, 22, 130)
        half = np.maximum(self.road_w * 0.5 * wobble, 1.2)
        return (self.road_d / half).astype(np.float32)

    def dither(self, salt: int) -> np.ndarray:
        ctx, r0, r1 = self._o, self._r0, self._r1
        ctx.dither(0)                                           # (makes the field)
        base = ctx._patch_cache["dither"]
        a, b = salt * 37 + 11, salt * 53 + 7
        rows = (np.arange(r0, r1) - a) % ctx.n
        return np.roll(base[rows], b, axis=1)

    def near_place(self, short_ids, radius: float) -> np.ndarray:
        out = np.zeros((self._r1 - self._r0, self._n), dtype=bool)
        for p in self.places:
            if p["id"].split("/")[-1] in short_ids:
                d2 = (self.X - p["position"][0]) ** 2 + (self.Z - p["position"][1]) ** 2
                out |= d2 < radius * radius
        return out


def _bands(n: int):
    for r0 in range(0, n, BAND_ROWS):
        yield r0, min(r0 + BAND_ROWS, n)


def control_maps(ctx: SurfaceContext, blend_curve: float = 0.7, dither_scale: float = 0.30):
    """base id, overlay id and blend per texel, worked a band of rows at a time (`_Band`)."""
    n = ctx.n
    base = np.zeros((n, n), dtype=np.uint8)
    overlay = np.zeros((n, n), dtype=np.uint8)
    blend = np.zeros((n, n), dtype=np.uint8)
    for r0, r1 in _bands(n):
        b, o, w = _control_band(_Band(ctx, r0, r1), blend_curve, dither_scale)
        base[r0:r1], overlay[r0:r1], blend[r0:r1] = b, o, w
    return base, overlay, blend


def _control_band(ctx, blend_curve: float = 0.7, dither_scale: float = 0.30):
    """base id, overlay id and blend (0-255) per texel, from the two strongest materials.

    Two things decide whether a material boundary reads as landscape or as a jigsaw.

    The blend byte is the *fraction of the overlay*: Terrain3D weights the base by
    ``1 - blend/255`` and the overlay by ``blend/255``. Where two materials are equally
    strong the honest value is therefore 127 -- half of each. Driving it to 255 there (as
    the old ratio curve did) makes each side of the seam show the other side's material at
    full strength, which mirrors the two materials across the boundary and is exactly the
    hard edge it was meant to soften.

    And the boundary's shape is broken at texel resolution. Terrain3D only interpolates
    between neighbouring control texels on Forward+; on Compatibility each texel takes its
    own base and overlay, so a smoothly-moving boundary lands on the texel grid as
    right-angled steps 2 m across. Jittering each slot's weight by per-texel white noise
    flips the ranking only where the top two are already within the jitter, so the seam
    frays into a dither a few texels wide and dissolves at any distance.
    """
    shape = ctx.slope.shape
    best = np.zeros(shape, dtype=np.float32)
    second = np.zeros(shape, dtype=np.float32)
    base = np.zeros(shape, dtype=np.uint8)
    overlay = np.zeros(shape, dtype=np.uint8)
    jitter_scale = 0.22
    for slot, w in _weights(ctx):
        w = np.asarray(w, dtype=np.float32)
        # three shared patch fields make the boundary wander over tens of metres...
        w = w * (1.0 + jitter_scale * (ctx.patch(500 + (slot % 3), 22, 90) - 0.5)
                 + 0.5 * jitter_scale * (ctx.patch(510 + (slot % 3), 6, 26) - 0.5))
        # ...and a per-slot dither breaks it at the texel itself
        w = w * (1.0 + dither_scale * (ctx.dither(slot) - 0.5))
        is_best = w > best
        is_second = (~is_best) & (w > second)
        # the old best slides down into second place; a mid-ranking slot takes second only
        overlay = np.where(is_best, base, np.where(is_second, np.uint8(slot), overlay)).astype(np.uint8)
        second = np.where(is_best, best, np.where(is_second, w, second))
        base = np.where(is_best, np.uint8(slot), base).astype(np.uint8)
        best = np.where(is_best, w, best)
    # overlay fraction, 0 where nothing competes and 0.5 where the two are equal
    frac = np.divide(second, np.maximum(best + second, 1e-4), dtype=np.float32)
    # a curve below 1 widens the band in which both materials are visible at all
    blend = np.clip(0.5 * np.power(np.clip(2.0 * frac, 0.0, 1.0), blend_curve) * 255.0,
                    0, 255).astype(np.uint8)
    overlay = np.where(second <= 1e-4, base, overlay).astype(np.uint8)
    # Terrain3D skips the overlay lookup when the two ids match, and would then draw the base
    # at only 1 - blend; a texel with no real second material must say so.
    blend = np.where(overlay == base, np.uint8(0), blend).astype(np.uint8)
    return base.astype(np.uint8), overlay, blend


def _hex_to_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


# Which palette entries carry each region's ground colour, its second voice and its accent.
# (Region palettes are ordered as written in the region defs; see WORLD_BIBLE.md section 6.)
COLOUR_VOICES = {
    "downs": (1, 0, 2, 0.30),          # clover green, harvest gold, chalk white
    "lake_basin": (1, 2, 3, 0.26),     # lime white, slate, brass
    "delta": (0, 1, 3, 0.34),          # teal, reed gold, bruise purple
    "forest_rise": (0, 3, 1, 0.34),    # deep green, moss lime, black-ash bark
    # bone white leads, slate blue only shades it: with slate leading, the doubled chroma
    # multiplied the fells' grey-brown rock by up to (0.65, 0.95, 1.40), blue-grey plastic that
    # no grade could take out. The cold belongs in the air and the distance, not on the stone.
    "mountains": (1, 0, 2, 0.30),      # bone white, slate blue, heather purple
    "ash_plateau": (0, 2, 1, 0.26),    # ash grey, bone, char black
}


def colour_map(ctx: SurfaceContext, rf, strength: float = 0.84, work_n: int = 1024) -> np.ndarray:
    """RGBA8 tint map: region palettes broken up by low-frequency noise; alpha = wetness.

    Computed on a coarse lattice (the tint is all low-frequency) and upsampled to the grid.
    """
    n = min(ctx.n, work_n)
    H = downsample(ctx.H, n)
    slope = downsample(ctx.slope, n)
    moist = downsample(ctx.moisture, n)
    water = downsample(ctx.water.astype(np.float32), n)
    acc = np.zeros((n, n, 3), dtype=np.float32)
    total = np.zeros((n, n), dtype=np.float32)
    for r in ctx.regions:
        pal = [_hex_to_rgb(c) for c in (r.palette or ["#ffffff"])]
        while len(pal) < 6:
            pal.append(pal[-1])
        w = rf.weight_at(r.index, n)
        a = 0.5 + 0.5 * np.tanh(ctx.bank.field(600 + r.index, beta=1.9, wl_min=240, wl_max=1100, n=n))
        b = 0.5 + 0.5 * np.tanh(ctx.bank.field(620 + r.index, beta=1.8, wl_min=90, wl_max=380, n=n))
        i0, i1, i2, accent = COLOUR_VOICES.get(r.shape, (0, 1, 2, 0.3))
        c0, c1, c2 = pal[i0 % len(pal)], pal[i1 % len(pal)], pal[i2 % len(pal)]
        # the ground colour leads; the second voice and the accent only shade it, otherwise
        # averaging three palette entries lands on grey and every region tints the same
        a2 = a * 0.55
        mix = (c0[None, None, :] * (1.0 - a2)[..., None] + c1[None, None, :] * a2[..., None])
        b2 = accent * b * 0.5
        mix = mix * (1.0 - b2)[..., None] + c2[None, None, :] * b2[..., None]
        acc += mix * w[..., None]
        total += w
    acc /= np.maximum(total, 1e-6)[..., None]
    # Terrain3D multiplies this map over the albedo, so the tint must shift chroma without
    # darkening: normalise each palette colour to mean 1, then blend from neutral toward it.
    chroma = acc / np.maximum(acc.mean(axis=-1, keepdims=True), 0.04)
    # a tint, not a paint: the multiplier stays near 1 so the terrain textures still set the
    # value -- but the hue deviation is amplified, or a palette that is nearly neutral (slate,
    # bone, ash) would tint nothing at all and the regions would look alike under one sun.
    chroma = 1.0 + (chroma - 1.0) * 2.0
    chroma = np.clip(chroma, 0.40, 1.95)
    tint = lerp(np.ones_like(acc), chroma, strength)
    # height and slope shading so the land reads even under flat light
    shade = 1.0 + 0.10 * np.tanh((H - 60.0) / 260.0) - 0.10 * smoothstep(0.35, 1.1, slope)
    tint *= shade[..., None]
    # snow lightens everything it covers
    # Snow is not neutral: its lit face is warm-white and its shadow side is blue, and a snow
    # field with no blue in it blows out to paper against dark rock.
    snow_t = smoothstep(SNOW_LINE - 60.0, SNOW_LINE + 80.0, H)[..., None]
    cold = np.array([0.90, 0.95, 1.06], dtype=np.float32)[None, None, :]
    tint = lerp(tint, np.broadcast_to(cold, tint.shape), snow_t * 0.72)
    wet = np.clip(0.75 * moist + 0.9 * water, 0.0, 1.0)
    alpha = np.clip(0.5 - 0.38 * wet, 0.0, 1.0)
    coarse_rgba = np.concatenate([np.clip(tint, 0.0, 1.0), alpha[..., None]], axis=-1)
    del tint, alpha, acc, total, chroma, shade
    # the full-resolution half a band of rows at a time (`_Band`)
    out = np.zeros((ctx.n, ctx.n, 4), dtype=np.uint8)
    for r0, r1 in _bands(ctx.n):
        out[r0:r1] = _colour_band(_Band(ctx, r0, r1), coarse_rgba)
    return out


def _colour_band(ctx, coarse_rgba: np.ndarray) -> np.ndarray:
    """colour_map's full-resolution half, for the rows `ctx` (a _Band) covers."""
    rgba = np.stack([ctx.up(coarse_rgba[..., c]) for c in range(4)], axis=-1)
    # The road is drawn at full resolution, after the upsample: a 5 m carriageway is smaller
    # than one texel of the coarse tint lattice and would smear into the fields either side.
    # A used road is lighter and greyer along its crown, where the surface is packed and dusty,
    # and throws a little pale dust onto the verge; the wheel tracks stay darker and damper.
    # Along every field boundary there is a strip the plough never reaches: rough grass, nettles
    # and the foot of a hedge. It is what makes the patchwork visible from a hilltop.
    # wide enough to survive being seen from a kilometre away: a hedge, its bank and the
    # strip either side of it that the plough never reaches is six or seven metres, and
    # at 2 m texels anything narrower is a line that disappears at any distance
    hedge_line = np.exp(-(ctx.field_d / 6.5) ** 2)

    # A hedge and its shadow are darker than the field either side, and that single dark line
    # is what tells a hilltop view that the country is farmed.
    hedge = np.exp(-(ctx.field_d / 5.0) ** 2) * (0.55 + 0.75 * ctx.patch(419, 12, 60))
    rgba[..., :3] *= (1.0 - 0.30 * np.clip(hedge, 0.0, 1.0))[..., None]

    # Grazed turf is not one colour. The tint above is computed on a 1024 lattice -- eight
    # metres to a texel -- and upsampled, so every variation in it is broader than a house,
    # and from eye height the ground reads as a billiard table with plants standing on it.
    # This is the missing octave: a few metres across, at full resolution, shifting value and
    # a little hue, which is what makes the ground between the tufts look like ground. It
    # costs nothing at runtime -- it is baked into the colour map the terrain already samples.
    fine = ctx.patch(422, 3.5, 17.0)
    coarse = ctx.patch(423, 14.0, 46.0)
    grain = (0.93 + 0.14 * fine) * (0.95 + 0.10 * coarse)
    rgba[..., :3] *= grain[..., None]
    # the drier patches go a touch yellow and the damper ones a touch blue, which is the
    # colour difference between grazed and rank grass
    warm = (fine - 0.5) * 0.09
    rgba[..., 0] *= (1.0 + warm)
    rgba[..., 2] *= (1.0 - warm)

    road_t = ctx.road_t()
    out_town = 1.0 - ctx.town
    crown = (1.0 - smoothstep(0.15, 1.15, road_t)) * out_town
    ruts = np.exp(-((road_t - 0.75) / 0.34) ** 2) * out_town
    dust = np.exp(-((road_t - 1.45) / 0.55) ** 2) * out_town
    grain = 0.85 + 0.3 * ctx.patch(418, 8, 44)
    # packed dust carries less of the region's colour than the turf either side...
    neutral = np.clip(0.70 * crown + 0.35 * dust, 0.0, 0.8)
    rgba[..., :3] = lerp(rgba[..., :3], np.ones_like(rgba[..., :3]), neutral[..., None])
    # ...and then the crown is lifted, so the road reads lighter than the field, not darker
    lift = 1.0 + (0.22 * crown + 0.11 * dust - 0.09 * ruts) * grain
    rgba[..., :3] *= lift[..., None]
    # the ruts hold water: rougher there, drier on the crown
    rgba[..., 3] = np.clip(rgba[..., 3] + 0.12 * crown - 0.10 * ruts, 0.0, 1.0)
    return (np.clip(rgba, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
