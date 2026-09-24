"""Painterly PBR node-material library (Blender, baked by bake.py).

"Painterly" here is a concrete recipe, not a mood: every surface is built from the same
four layers so wood, stone, plaster, iron and cloth read as one hand in every region:

  1. paint_blocks   large soft colour patches through a 3-4 stop ramp (blocked-in colour),
  2. a pattern      medium-scale structure with soft edges (planks, blocks, fissures, weave),
  3. edge wear      convex edges lightened / polished via Pointiness, broken up by noise,
  4. cavity dirt    concave areas darkened and dirtied via the Ambient Occlusion node.

No photographic micro-noise: the finest layer is a low-contrast grain at most. Regions
change the palette, not the language: every builder takes a Palette and mixes a role
colour (earth, light, accent, ...) into its base tones by a small `tint` amount.

Every builder returns a Material whose surface is a single Principled BSDF, so the bake
step can read Base Color / Roughness / Metallic / Normal / Alpha straight off it.
"""
from __future__ import annotations

import colorsys
import math

import bpy

from . import palette as P

# ---------------------------------------------------------------------------------------
# colour helpers (linear rgb in, linear rgb out)
# ---------------------------------------------------------------------------------------

def rgba(c):
    if isinstance(c, (int, float)):
        return (float(c), float(c), float(c), 1.0)
    c = tuple(c)
    return c if len(c) == 4 else (c[0], c[1], c[2], 1.0)


def shade(c, value=1.0, sat=1.0, hue=0.0):
    """Adjust a linear colour in HSV (done in sRGB space, which is what a painter sees)."""
    s = P.linear_to_srgb(c)
    h, sv, v = colorsys.rgb_to_hsv(*s)
    h = (h + hue) % 1.0
    sv = max(0.0, min(1.0, sv * sat))
    v = max(0.0, min(1.0, v * value))
    return P.srgb_to_linear(colorsys.hsv_to_rgb(h, sv, v))


def trio(c, spread=1.0):
    """Painter's three: shadow (darker, a touch more saturated and cooler), base, light
    (lighter, less saturated, warmer). Used as ramp stops everywhere.

    The highlight is pulled back from the top of the range on purpose: a pale surface whose
    light stop clips to white loses all its modelling and reads as flat paper, which is the
    commonest way a painted material goes wrong."""
    dark = shade(c, value=1.0 - 0.42 * spread, sat=1.0 + 0.30 * spread, hue=-0.015 * spread)
    light_v = min(1.0 + 0.30 * spread, 0.93 / max(0.35, _value_of(c)))
    light = shade(c, value=light_v, sat=1.0 - 0.28 * spread, hue=0.012 * spread)
    return dark, c, light


def _value_of(c):
    return max(P.linear_to_srgb(c[:3]))


def _pal(pal):
    return pal if pal is not None else P.Palette(P.NEUTRAL_DEF)


def _tinted(base_hex, pal, role, amount):
    return _pal(pal).tint(P.lin(base_hex), role, amount)


# ---------------------------------------------------------------------------------------
# node builder
# ---------------------------------------------------------------------------------------

class NB:
    """Tiny node-graph DSL over a fresh Principled material."""

    def __init__(self, name: str):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        self.mat = mat
        self.nt = mat.node_tree
        self.nodes = self.nt.nodes
        self.links = self.nt.links
        self.bsdf = self.nodes["Principled BSDF"]
        self.out = self.nodes["Material Output"]
        self.bsdf.inputs["Roughness"].default_value = 0.7
        self.bsdf.inputs["Specular IOR Level"].default_value = 0.35
        self._n = 0
        self.uses_ao = False
        self._coord = None

    # -- plumbing -------------------------------------------------------------------------
    def node(self, kind: str, **props):
        n = self.nodes.new(kind)
        self._n += 1
        n.location = (-300 - 200 * (self._n % 7), 600 - 150 * (self._n // 7))
        inputs = props.pop("inputs", {})
        for k, v in props.items():
            setattr(n, k, v)
        for k, v in inputs.items():
            self.set(n.inputs[k], v)
        return n

    def set(self, socket, val):
        """Link a socket to `val` if it is an output socket, else set its default value."""
        if val is None:
            return
        if isinstance(val, bpy.types.NodeSocket):
            self.links.new(val, socket)
            return
        if socket.type == "RGBA":
            socket.default_value = rgba(val)
        elif socket.type == "VECTOR":
            socket.default_value = tuple(val)[:3]
        else:
            socket.default_value = P.luminance(val) if isinstance(val, (tuple, list)) else float(val)

    # -- coordinates ----------------------------------------------------------------------
    def coord(self, scale=1.0, space="Object", rotation=(0, 0, 0), location=(0, 0, 0)):
        tc = self._coord or self.node("ShaderNodeTexCoord")
        self._coord = tc
        if isinstance(scale, (int, float)):
            scale = (scale, scale, scale)
        m = self.node("ShaderNodeMapping", vector_type="POINT")
        self.links.new(tc.outputs[space], m.inputs["Vector"])
        m.inputs["Scale"].default_value = scale
        m.inputs["Rotation"].default_value = tuple(math.radians(a) for a in rotation)
        m.inputs["Location"].default_value = location
        return m.outputs["Vector"]

    # -- textures -------------------------------------------------------------------------
    def noise(self, vec, scale=1.0, detail=2.0, rough=0.5, distortion=0.0):
        n = self.node("ShaderNodeTexNoise", noise_dimensions="3D",
                      inputs={"Vector": vec, "Scale": scale, "Detail": detail, "Roughness": rough, "Distortion": distortion})
        return n

    def voronoi(self, vec, scale=4.0, feature="F1", randomness=1.0, smoothness=0.0):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature=feature, distance="EUCLIDEAN",
                      inputs={"Vector": vec, "Scale": scale, "Randomness": randomness})
        if feature == "SMOOTH_F1":
            n.inputs["Smoothness"].default_value = smoothness
        return n

    def vwarp(self, vec, source, amount=0.5):
        """Offset a coordinate by a noise vector.

        Any procedural pattern with straight walls — a Voronoi cell field above all — reads
        as a crystal lattice or an ink drawing unless its lookup wanders. Warping the
        coordinate is what turns cells into weathered facets.
        """
        sc = self.node("ShaderNodeVectorMath", operation="SCALE", inputs={0: source})
        sc.inputs["Scale"].default_value = amount
        add = self.node("ShaderNodeVectorMath", operation="ADD",
                        inputs={0: vec, 1: sc.outputs["Vector"]})
        return add.outputs["Vector"]

    def wave(self, vec, scale=4.0, distortion=1.0, detail=1.0, detail_scale=1.0, direction="X", profile="SIN", kind="BANDS"):
        n = self.node("ShaderNodeTexWave", wave_type=kind, bands_direction=direction, wave_profile=profile,
                      inputs={"Vector": vec, "Scale": scale, "Distortion": distortion, "Detail": detail, "Detail Scale": detail_scale})
        return n

    def brick(self, vec, scale=4.0, c1=(0.5, 0.5, 0.5), c2=(0.4, 0.4, 0.4), mortar=(0.2, 0.2, 0.2),
              mortar_size=0.02, mortar_smooth=0.3, bias=0.0, width=0.5, height=0.25, offset=0.5, squash=1.0):
        n = self.node("ShaderNodeTexBrick", offset=offset, squash=squash,
                      inputs={"Vector": vec, "Scale": scale, "Color1": c1, "Color2": c2, "Mortar": mortar,
                              "Mortar Size": mortar_size, "Mortar Smooth": mortar_smooth, "Bias": bias,
                              "Brick Width": width, "Row Height": height})
        return n

    def musgrave(self, vec, scale=3.0, detail=3.0, dimension=1.5, lacunarity=2.0):
        n = self.node("ShaderNodeTexMusgrave", musgrave_dimensions="3D",
                      inputs={"Vector": vec, "Scale": scale, "Detail": detail, "Dimension": dimension, "Lacunarity": lacunarity})
        return n

    # -- maths / colour -------------------------------------------------------------------
    def ramp(self, fac, stops, interp="EASE"):
        """stops: [(pos, colour-or-float), ...] -> Color output socket."""
        n = self.node("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.interpolation = interp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        while len(cr.elements) > len(stops):
            cr.elements.remove(cr.elements[-1])
        for e, (pos, col) in zip(cr.elements, stops):
            e.position = pos
            e.color = rgba(col)
        self.set(n.inputs["Fac"], fac)
        return n.outputs["Color"]

    def mix(self, fac, a, b, blend="MIX", clamp=True):
        n = self.node("ShaderNodeMixRGB", blend_type=blend, use_clamp=clamp, inputs={"Fac": fac, "Color1": a, "Color2": b})
        return n.outputs["Color"]

    def math(self, op, a, b=0.0, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.set(n.inputs[0], a)
        self.set(n.inputs[1], b)
        return n.outputs["Value"]

    def map_range(self, v, fmin=0.0, fmax=1.0, tmin=0.0, tmax=1.0, clamp=True):
        n = self.node("ShaderNodeMapRange", clamp=clamp,
                      inputs={"Value": v, "From Min": fmin, "From Max": fmax, "To Min": tmin, "To Max": tmax})
        return n.outputs["Result"]

    def rgb(self, c):
        n = self.node("ShaderNodeRGB")
        n.outputs[0].default_value = rgba(c)
        return n.outputs[0]

    def value(self, v):
        n = self.node("ShaderNodeValue")
        n.outputs[0].default_value = float(v)
        return n.outputs[0]

    def hsv(self, color, hue=0.5, sat=1.0, val=1.0, fac=1.0):
        n = self.node("ShaderNodeHueSaturation", inputs={"Hue": hue, "Saturation": sat, "Value": val, "Fac": fac, "Color": color})
        return n.outputs["Color"]

    def invert(self, v):
        n = self.node("ShaderNodeInvert", inputs={"Fac": 1.0, "Color": v})
        return n.outputs["Color"]

    def attribute(self, name, out="Color"):
        n = self.node("ShaderNodeAttribute", attribute_name=name)
        return n.outputs[out]

    def separate_z(self, vec=None):
        """Height (object Z) as a float socket."""
        if vec is None:
            vec = self.coord(1.0)
        n = self.node("ShaderNodeSeparateXYZ", inputs={"Vector": vec})
        return n.outputs["Z"]

    def height_mask(self, z0, z1):
        """0 below z0 rising to 1 above z1 (object space); grime gradients, snow caps."""
        return self.map_range(self.separate_z(), z0, z1, 0.0, 1.0)

    # -- geometry masks -------------------------------------------------------------------
    def pointiness(self, lo=0.5, hi=0.62):
        """0 on flat/concave, 1 on sharp convex edges."""
        g = self.node("ShaderNodeNewGeometry")
        return self.map_range(g.outputs["Pointiness"], lo, hi, 0.0, 1.0)

    def concavity(self, lo=0.5, hi=0.38):
        g = self.node("ShaderNodeNewGeometry")
        return self.map_range(g.outputs["Pointiness"], lo, hi, 0.0, 1.0)

    def ao(self, distance=0.2, samples=8, only_local=True):
        """1 in the open, 0 in tight cavities (stochastic: the bake uses more samples)."""
        self.uses_ao = True
        n = self.node("ShaderNodeAmbientOcclusion", samples=samples, only_local=only_local, inside=False,
                      inputs={"Distance": distance})
        return n.outputs["AO"]

    def bump(self, height, strength=0.3, distance=0.02, normal=None, invert=False):
        n = self.node("ShaderNodeBump", invert=invert, inputs={"Strength": strength, "Distance": distance, "Height": height})
        if normal is not None:
            self.set(n.inputs["Normal"], normal)
        return n.outputs["Normal"]

    # -- output ---------------------------------------------------------------------------
    def finish(self, base_color=None, roughness=None, metallic=None, normal=None, alpha=None,
               emission=None, emission_strength=None, specular=None):
        b = self.bsdf.inputs
        self.set(b["Base Color"], base_color)
        self.set(b["Roughness"], roughness)
        self.set(b["Metallic"], metallic)
        self.set(b["Normal"], normal)
        self.set(b["Alpha"], alpha)
        self.set(b["Specular IOR Level"], specular)
        if emission is not None:
            self.set(b["Emission Color"], emission)
            self.set(b["Emission Strength"], emission_strength if emission_strength is not None else 1.0)
        self.mat["forge_uses_ao"] = self.uses_ao
        return self.mat


# ---------------------------------------------------------------------------------------
# painterly layers
# ---------------------------------------------------------------------------------------

def paint_blocks(nb: NB, vec, colors, distortion=0.9, detail=1.5, rough=0.45, positions=None):
    """Large soft colour patches: one noise through a few-stop ramp. `colors` are 3-4
    linear colours dark -> light."""
    n = nb.noise(vec, scale=1.0, detail=detail, rough=rough, distortion=distortion)
    k = len(colors)
    if positions is None:
        positions = [0.32, 0.5, 0.68] if k == 3 else [0.3 + 0.4 * i / (k - 1) for i in range(k)]
    return nb.ramp(n.outputs["Fac"], list(zip(positions, colors)), interp="EASE")


def strokes(nb: NB, vec_scale, base, strength=0.12, scale=5.0, along="Z", detail=1.0):
    """Directional brush streaks: noise stretched along one axis, applied as a soft
    multiply/screen so the surface reads as laid-in strokes rather than spray."""
    # "XZ" names a plane rather than an axis (see wood_planks); the strokes still run along
    # its first axis, so it stretches the same way "X" does.
    s = {"X": (0.15, 1.0, 1.0), "Y": (1.0, 0.15, 1.0), "Z": (1.0, 1.0, 0.15),
         "XZ": (0.15, 1.0, 1.0)}[along]
    v = nb.coord((vec_scale * s[0], vec_scale * s[1], vec_scale * s[2]))
    n = nb.noise(v, scale=scale, detail=detail, rough=0.4, distortion=0.3)
    tone = nb.ramp(n.outputs["Fac"], [(0.35, 1.0 - strength), (0.65, 1.0 + strength)], interp="EASE")
    return nb.mix(1.0, base, tone, blend="MULTIPLY")


def edge_wear(nb: NB, base, worn, amount=0.5, lo=0.52, hi=0.64, breakup_vec=None, breakup_scale=6.0):
    """Lighten/expose convex edges. `amount` 0..1 scales both coverage and opacity."""
    if amount <= 0.0:
        return base, None
    mask = nb.pointiness(lo, hi)
    if breakup_vec is not None:
        bn = nb.noise(breakup_vec, scale=breakup_scale, detail=2.0, rough=0.5)
        gate = nb.map_range(bn.outputs["Fac"], 0.55 - 0.3 * amount, 0.75, 0.0, 1.0)
        mask = nb.math("MULTIPLY", mask, gate, clamp=True)
    mask = nb.math("MULTIPLY", mask, min(1.0, 0.35 + amount), clamp=True)
    return nb.mix(mask, base, worn), mask


def cavity_dirt(nb: NB, base, dirt, amount=0.5, distance=0.15, breakup_vec=None, cheap=False):
    """Darken and dirty concave areas.

    By default this uses the AO node, which traces real occlusion and gives the soft,
    believable falloff a painted surface wants. `cheap=True` swaps in the free
    curvature-based concavity, for meshes where the AO rays would cost more than they are
    worth (a tree trunk has no cavities to speak of, and there are a lot of samples)."""
    if amount <= 0.0:
        return base, None
    if cheap:
        mask = nb.concavity(0.5, 0.4)
    else:
        occ = nb.ao(distance=distance)
        mask = nb.map_range(occ, 0.25, 0.95, 1.0, 0.0)
    if breakup_vec is not None:
        bn = nb.noise(breakup_vec, scale=3.0, detail=2.0, rough=0.5)
        mask = nb.math("MULTIPLY", mask, nb.map_range(bn.outputs["Fac"], 0.3, 0.7, 0.4, 1.0), clamp=True)
    mask = nb.math("MULTIPLY", mask, amount, clamp=True)
    return nb.mix(mask, base, dirt), mask


def base_grime(nb: NB, base, grime, z0=0.0, z1=0.35, amount=0.5, vec=None):
    """Ground dirt: darkens toward the bottom of the object, broken by noise."""
    if amount <= 0.0:
        return base
    m = nb.map_range(nb.separate_z(), z1, z0, 0.0, 1.0)
    if vec is not None:
        bn = nb.noise(vec, scale=2.5, detail=2.0, rough=0.5)
        m = nb.math("MULTIPLY", m, nb.map_range(bn.outputs["Fac"], 0.3, 0.7, 0.3, 1.0), clamp=True)
    m = nb.math("MULTIPLY", m, amount, clamp=True)
    return nb.mix(m, base, grime)


def rough_var(nb: NB, vec, base=0.7, spread=0.12, scale=2.0):
    n = nb.noise(vec, scale=scale, detail=1.0, rough=0.4)
    return nb.map_range(n.outputs["Fac"], 0.3, 0.7, base - spread, base + spread)


# ---------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------

def wood_planks(pal=None, wear=0.4, age=0.5, scale=1.0, tint=0.18, plank_len=1.2, plank_w=0.18,
                paint=None, name=None, along="Z", base_hex="#8a6a42", relief=1.0, grain=1.0, **_):
    """Sawn oak planks. `paint` = linear colour of a painted finish (chips off at edges).

    `relief` scales the grain and plank bump, whose distance is an absolute 15 mm. That is
    right for a table top and absurd for a spoon: the bump's amplitude does not follow
    `scale`, so shrinking the features only makes the corrugation finer, never shallower,
    and a 16 mm handle comes out fluted. Anything hand-sized wants a tenth of it.

    `grain` is the other half of the same fault and the half that survived the first pass,
    because it is in the albedo and a lowered `relief` cannot touch it. The grain is a wave
    laid down in a space scaled by `scale`, so its bands land every `scale`/22.5 metres --
    31 mm at the 0.70 a hammer haft asks for, on a haft 18 mm thick. Ten dark rings around
    a stick is not ash; it is a screw thread, and it was plain in the first render of the
    hammer, the spear and the spoon. `grain` divides that frequency: a quarter puts two or
    three soft bands along a haft, which is what one length of cleft ash looks like.

    Both default to 1.0 so every board, barrel, cart and landmark built before this bakes
    to exactly the same maps as it did."""
    nb = NB(name or "wood_planks")
    pal = _pal(pal)
    base = pal.tint(P.lin(base_hex), "earth", tint)
    base = shade(base, value=1.0 - 0.25 * age, sat=1.0 - 0.2 * age)
    dark, mid, light = trio(base, 1.0)
    v = nb.coord(1.0 / scale)
    blocks = paint_blocks(nb, nb.coord(0.7 / scale), [dark, mid, light])
    # planks: long bricks along `along`; each plank gets its own tone through Color1/Color2
    # `along` names the direction the boards run. The three axis names put the boards in the
    # plane of the two remaining axes taken in the obvious order; "XZ" is the odd one out and
    # says boards along X stacked up Z, which is what a panel standing on its edge needs. A
    # shield built flat and then stood up carries its own rotation into object space, so
    # "X" would run its planks through the twelve millimetres of board thickness and show
    # nothing at all.
    rot = {"Z": (0, 90, 0), "X": (0, 0, 0), "Y": (0, 0, 90), "XZ": (90, 0, 0)}[along]
    pv = nb.coord(1.0 / scale, rotation=rot)
    br = nb.brick(pv, scale=1.0 / plank_w, c1=(1.0, 1.0, 1.0), c2=(0.78, 0.74, 0.70), mortar=(0.35, 0.3, 0.28),
                  mortar_size=0.012, mortar_smooth=0.6, bias=0.0, width=plank_len / plank_w, height=1.0, offset=0.45)
    col = nb.mix(1.0, blocks, br.outputs["Color"], blend="MULTIPLY")
    # grain: soft wave bands along the plank direction
    g = 2.5 * grain / scale
    gv = nb.coord((g, g, g), rotation=rot)
    wave = nb.wave(gv, scale=9.0, distortion=4.0, detail=1.5, detail_scale=0.6, direction="X")
    grain = nb.ramp(wave.outputs["Fac"], [(0.3, 0.88), (0.6, 1.0), (0.9, 1.08)], interp="EASE")
    col = nb.mix(0.7, col, nb.mix(1.0, col, grain, blend="MULTIPLY"))
    col = strokes(nb, 1.0 / scale, col, strength=0.08, scale=4.0, along=along)
    if paint is not None:
        pdark, pmid, plight = trio(paint, 0.7)
        pcol = paint_blocks(nb, nb.coord(1.3 / scale), [pdark, pmid, plight])
        pcol = nb.mix(0.5, pcol, nb.mix(1.0, pcol, grain, blend="MULTIPLY"))
        chip = nb.pointiness(0.5, 0.6)
        cn = nb.noise(v, scale=5.0, detail=2.0, rough=0.5)
        chip = nb.math("MULTIPLY", chip, nb.map_range(cn.outputs["Fac"], 0.45 - 0.3 * wear, 0.7, 0.0, 1.0), clamp=True)
        chip = nb.math("ADD", chip, nb.map_range(cn.outputs["Fac"], 0.7 - 0.25 * wear, 0.85, 0.0, 1.0), clamp=True)
        col = nb.mix(chip, pcol, col)
    col, _ = edge_wear(nb, col, shade(light, 1.12, 0.7), amount=wear * 0.8, breakup_vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.55, 1.1), amount=0.35 + 0.4 * age, distance=0.12)
    height = nb.math("ADD", nb.math("MULTIPLY", wave.outputs["Fac"], 0.35), nb.math("MULTIPLY", br.outputs["Fac"], 0.65))
    normal = nb.bump(height, strength=0.25, distance=0.015 * relief)
    rough = rough_var(nb, v, 0.62 + 0.15 * age, 0.1)
    return nb.finish(col, rough, 0.0, normal)


def painted_wood(pal=None, role="accent", **kw):
    pal = _pal(pal)
    return wood_planks(pal, paint=pal.role(role), name=kw.pop("name", "painted_wood"), **kw)


def carved_wood(pal=None, **kw):
    kw.setdefault("plank_len", 3.0)
    kw.setdefault("plank_w", 0.6)
    kw.setdefault("base_hex", "#6d4c2c")
    return wood_planks(pal, name=kw.pop("name", "carved_wood"), **kw)


def driftwood(pal=None, scale=1.0, **kw):
    kw.setdefault("base_hex", "#8b8577")
    kw.setdefault("age", 0.9)
    kw.setdefault("wear", 0.7)
    return wood_planks(pal, name=kw.pop("name", "driftwood"), scale=scale, **kw)


def _bark_common(nb, pal, base, fissure_scale, stretch, depth, tint, moss=0.35, lichen=0.0,
                 lichen_col=None, scale=1.0, streaks=0.0, rot=0.0):
    """`scale` is the size of the bark's features in metres.

    Every bark was fixed at one metre, which is right for an ordinary trunk and hopeless on
    a thirty-metre bole: the Grandfather came out speckled like concrete because its
    fissures were a thirtieth of its width. Hero pieces pass a larger scale; everything
    else keeps 1.0 and is unchanged.

    `streaks` runs weathering down the wood (grain-long bands, silvered and darkened), and
    `rot` lays soft umber rot and a green-black damp over the lower wood; both are 0 for a
    living bark and change nothing there.
    """
    dark, mid, light = trio(base, 1.1)
    v = nb.coord(1.0 / scale)
    blocks = paint_blocks(nb, nb.coord(0.8 / scale), [dark, mid, light], distortion=1.2)
    fv = nb.coord((fissure_scale, fissure_scale, fissure_scale * stretch))
    vor = nb.voronoi(fv, scale=1.0, feature="DISTANCE_TO_EDGE", randomness=1.0)
    fis = nb.map_range(vor.outputs["Distance"], 0.0, 0.18, 0.0, 1.0)  # 0 in cracks
    crack_col = shade(dark, 0.5, 1.15)
    col = nb.mix(nb.invert(fis), blocks, crack_col)
    # plate mottling
    pn = nb.noise(nb.coord(3.0), scale=1.0, detail=2.0, rough=0.5)
    col = nb.mix(0.35, col, nb.mix(1.0, col, nb.ramp(pn.outputs["Fac"], [(0.35, 0.85), (0.65, 1.12)]), blend="MULTIPLY"))
    if moss > 0:
        g = nb.ramp(nb.noise(nb.coord(1.5), scale=1.0, detail=2.0, rough=0.5, distortion=0.5).outputs["Fac"],
                    [(0.5 - 0.15 * moss, 0.0), (0.72, 1.0)])
        # moss favours the lower trunk and the north side (object -Y)
        low = nb.map_range(nb.separate_z(), 3.0, 0.3, 0.0, 1.0)
        m = nb.math("MULTIPLY", g, nb.math("ADD", low, 0.35, clamp=True), clamp=True)
        m = nb.math("MULTIPLY", m, moss, clamp=True)
        mossc = pal.tint(P.lin("#5d7a2e"), "green", 0.35)
        col = nb.mix(m, col, mossc)
    if lichen > 0:
        ln = nb.noise(nb.coord(6.0), scale=1.0, detail=2.0, rough=0.6)
        lm = nb.map_range(ln.outputs["Fac"], 0.68 - 0.12 * lichen, 0.8, 0.0, 1.0)
        col = nb.mix(lm, col, lichen_col or P.lin("#9aa08c"))
    if streaks > 0:
        # long bands down the grain (object Z), some silvered by the weather and some stained
        sn = nb.noise(nb.coord((9.0 / scale, 9.0 / scale, 0.35 / scale)), scale=1.0, detail=3.0, rough=0.55)
        silver = nb.map_range(sn.outputs["Fac"], 0.58, 0.75, 0.0, streaks * 0.55)
        stain = nb.map_range(sn.outputs["Fac"], 0.42, 0.28, 0.0, streaks * 0.7)
        col = nb.mix(silver, col, shade(light, 1.0, 0.7))
        col = nb.mix(stain, col, shade(dark, 0.72, 1.1))
    if rot > 0:
        # soft rot in patches, heavier toward the foot of the wood, and damp black-green in it
        rn = nb.noise(nb.coord(1.1 / scale), scale=1.0, detail=3.0, rough=0.6, distortion=0.6)
        low = nb.map_range(nb.separate_z(), 2.5, 0.2, 0.0, 1.0)
        patch = nb.map_range(rn.outputs["Fac"], 0.56 - 0.1 * rot, 0.7, 0.0, 1.0)
        rm = nb.math("MULTIPLY", patch, nb.math("ADD", low, 0.25, clamp=True), clamp=True)
        rm = nb.math("MULTIPLY", rm, rot, clamp=True)
        col = nb.mix(rm, col, pal.tint(P.lin("#3b2e25"), "dark", 0.2))
        damp = nb.math("MULTIPLY", rm, nb.math("MULTIPLY", low, 0.6, clamp=True), clamp=True)
        col = nb.mix(damp, col, pal.tint(P.lin("#262a20"), "dark", 0.15))
    # Bark's own fissures already carry the cavity reading, and a trunk is a big mesh to
    # trace AO rays across, so use the free curvature term here.
    col, _ = cavity_dirt(nb, col, shade(dark, 0.6), amount=0.4, distance=0.2, cheap=True)
    height = nb.math("ADD", nb.math("MULTIPLY", fis, 0.7), nb.math("MULTIPLY", pn.outputs["Fac"], 0.3))
    normal = nb.bump(height, strength=depth, distance=0.03)
    rough = rough_var(nb, v, 0.85, 0.08)
    return nb.finish(col, rough, 0.0, normal)


def oak_bark(pal=None, age=0.5, tint=0.15, scale=1.0, name=None, **_):
    pal = _pal(pal)
    base = pal.tint(P.lin("#5b4a3a"), "earth", tint)
    nb = NB(name or "oak_bark")
    return _bark_common(nb, pal, base, fissure_scale=4.0, stretch=0.22, depth=0.55, tint=tint, moss=0.3 + 0.3 * age, scale=scale)


def black_ash_bark(pal=None, age=0.5, tint=0.2, scale=1.0, name=None, **_):
    pal = _pal(pal)
    base = pal.tint(P.lin("#2a2320"), "dark", tint)
    nb = NB(name or "black_ash_bark")
    return _bark_common(nb, pal, base, fissure_scale=3.0, stretch=0.35, depth=0.5, tint=tint, moss=0.25,
                        lichen=0.5, lichen_col=P.lin("#8f9a8a"), scale=scale)


def pine_bark(pal=None, age=0.5, tint=0.15, scale=1.0, name=None, **_):
    pal = _pal(pal)
    base = pal.tint(P.lin("#6e4a33"), "warm", tint)
    nb = NB(name or "pine_bark")
    return _bark_common(nb, pal, base, fissure_scale=6.0, stretch=0.6, depth=0.45, tint=tint, moss=0.1, lichen=0.2, scale=scale)


def willow_bark(pal=None, age=0.5, tint=0.15, scale=1.0, name=None, **_):
    pal = _pal(pal)
    base = pal.tint(P.lin("#6b6455"), "mid", tint)
    nb = NB(name or "willow_bark")
    return _bark_common(nb, pal, base, fissure_scale=3.5, stretch=0.15, depth=0.5, tint=tint, moss=0.45, scale=scale)


def dead_bark(pal=None, age=0.9, tint=0.25, scale=1.0, name=None, **_):
    """Weathered, barkless dead wood: ash-grey, streaked down the grain, rotting at the foot
    (Cinderlea's ash trees and char stumps).

    It was white-grey (#b9b3a8 leaned to the palette's light), and over the ash heath's black
    soil every dead tree read as crumpled white paper. Silvered wood is a mid grey, not a white;
    its light is in the streaks."""
    pal = _pal(pal)
    base = pal.tint(P.lin("#77716a"), "mid", tint)
    nb = NB(name or "dead_bark")
    return _bark_common(nb, pal, base, fissure_scale=5.0, stretch=0.12, depth=0.24, tint=tint, moss=0.0,
                        lichen=0.0, scale=scale, streaks=0.8, rot=0.35 + 0.35 * age)


def birch_bark(pal=None, age=0.4, tint=0.1, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "birch_bark")
    base = pal.tint(P.lin("#e6e2d8"), "light", tint)
    dark, mid, light = trio(base, 0.6)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.9 / scale), [dark, mid, light])
    # horizontal lenticels: wave bands along Z, distorted, thresholded soft
    w = nb.wave(nb.coord((1.0 / scale, 1.0 / scale, 1.0 / scale)), scale=14.0, distortion=2.5,
                detail=2.0, detail_scale=1.5, direction="Z")
    band = nb.map_range(w.outputs["Fac"], 0.78, 0.92, 0.0, 1.0)
    gate = nb.noise(nb.coord(2.0 / scale), scale=1.0, detail=1.0, rough=0.5)
    band = nb.math("MULTIPLY", band, nb.map_range(gate.outputs["Fac"], 0.35, 0.6, 0.0, 1.0), clamp=True)
    col = nb.mix(band, col, P.lin("#3a322c"))
    # peel patches
    pn = nb.noise(nb.coord(1.2), scale=1.0, detail=2.0, rough=0.5, distortion=0.8)
    peel = nb.map_range(pn.outputs["Fac"], 0.66 - 0.1 * age, 0.78, 0.0, 1.0)
    col = nb.mix(peel, col, P.lin("#a68f7a"))
    col, _ = cavity_dirt(nb, col, shade(dark, 0.6), amount=0.35, distance=0.2)
    normal = nb.bump(nb.math("ADD", band, nb.math("MULTIPLY", pn.outputs["Fac"], 0.5)), strength=0.25, distance=0.01)
    return nb.finish(col, rough_var(nb, v, 0.7, 0.08), 0.0, normal)


def plaster_limewash(pal=None, wear=0.4, age=0.4, tint=0.35, scale=1.0, name=None, base_hex="#e4dcc9", under_hex="#8f7a52", **_):
    pal = _pal(pal)
    nb = NB(name or "plaster_limewash")
    base = pal.tint(P.lin(base_hex), "light", tint)
    # A white wall still needs a painter's range in it; at low spread the whole surface
    # collapses to one value and reads as blank paper.
    dark, mid, light = trio(base, 1.0)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.6 / scale), [dark, mid, light], distortion=1.4)
    # water streaks running down
    w = nb.wave(nb.coord((1.0 / scale, 1.0 / scale, 0.12 / scale)), scale=6.0, distortion=1.5, detail=1.0, direction="X")
    streak = nb.ramp(w.outputs["Fac"], [(0.4, 1.0), (0.75, 0.93)], interp="EASE")
    col = nb.mix(0.6 * age, col, nb.mix(1.0, col, streak, blend="MULTIPLY"))
    col = strokes(nb, 1.0 / scale, col, strength=0.06, scale=3.0, along="Z")
    # chipped plaster shows the cob/under colour on edges and in noisy patches
    under = pal.tint(P.lin(under_hex), "earth", 0.3)
    col, _ = edge_wear(nb, col, under, amount=wear * 1.3, lo=0.52, hi=0.66, breakup_vec=v, breakup_scale=4.0)
    pn = nb.noise(nb.coord(1.5 / scale), scale=1.0, detail=3.0, rough=0.55, distortion=0.6)
    patch = nb.map_range(pn.outputs["Fac"], 0.62 - 0.22 * wear, 0.72, 0.0, 1.0)
    col = nb.mix(patch, col, under)
    # a darker halo just inside each chip, where the lime has lifted but not fallen away
    halo = nb.math("SUBTRACT", nb.map_range(pn.outputs["Fac"], 0.56 - 0.22 * wear, 0.68, 0.0, 1.0), patch,
                   clamp=True)
    col = nb.mix(nb.math("MULTIPLY", halo, 0.7), col, shade(under, 0.72, 1.1))
    col = base_grime(nb, col, shade(dark, 0.7, 1.1), 0.0, 0.6, amount=0.5 * age, vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.7), amount=0.35, distance=0.2)
    height = nb.math("ADD", nb.math("MULTIPLY", nb.noise(nb.coord(3.0 / scale), scale=1.0, detail=2.0, rough=0.5).outputs["Fac"], 0.45),
                     nb.math("MULTIPLY", nb.invert(patch), 0.55))
    normal = nb.bump(height, strength=0.45, distance=0.014)
    return nb.finish(col, rough_var(nb, v, 0.82, 0.06), 0.0, normal)


def chalk_cob(pal=None, wear=0.4, age=0.5, tint=0.3, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "chalk_cob")
    base = pal.tint(P.lin("#d2c4a4"), "light", tint)
    dark, mid, light = trio(base, 1.15)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.7 / scale), [dark, mid, light], distortion=1.0)
    # straw flecks
    # Straw in the cob: short stretched cells, not round specks, and enough of them to see.
    fv = nb.coord((11.0 / scale, 1.6 / scale, 11.0 / scale))
    vor = nb.voronoi(fv, scale=1.0, feature="F1")
    fleck = nb.map_range(vor.outputs["Distance"], 0.04, 0.26, 1.0, 0.0)
    gate = nb.noise(nb.coord(2.0 / scale), scale=1.0, detail=1.0, rough=0.5)
    fleck = nb.math("MULTIPLY", fleck, nb.map_range(gate.outputs["Fac"], 0.35, 0.65, 0.0, 1.0), clamp=True)
    col = nb.mix(fleck, col, pal.tint(P.lin("#a8842e"), "warm", 0.35))
    col = strokes(nb, 1.0 / scale, col, strength=0.12, scale=2.5, along="Z")
    col = base_grime(nb, col, shade(dark, 0.55, 1.15), 0.0, 0.7, amount=0.7 * age, vec=v)
    col, _ = edge_wear(nb, col, shade(light, 1.05, 0.8), amount=wear * 0.6, breakup_vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.65), amount=0.4, distance=0.2)
    lump = nb.noise(nb.coord(2.5 / scale), scale=1.0, detail=2.0, rough=0.45)
    normal = nb.bump(nb.math("ADD", nb.math("MULTIPLY", lump.outputs["Fac"], 0.75),
                             nb.math("MULTIPLY", fleck, 0.25)), strength=0.55, distance=0.025)
    return nb.finish(col, rough_var(nb, v, 0.85, 0.06), 0.0, normal)


def stone_blocks(pal=None, wear=0.4, age=0.5, tint=0.2, scale=1.0, block_w=0.9, block_h=0.4, name=None,
                 base_hex="#8e8778", mortar_hex="#6a655c", **_):
    pal = _pal(pal)
    nb = NB(name or "stone_blocks")
    base = pal.tint(P.lin(base_hex), "mid", tint)
    dark, mid, light = trio(base, 0.8)
    v = nb.coord(1.0 / scale)
    blocks = paint_blocks(nb, nb.coord(0.5 / scale), [dark, mid, light], distortion=1.0)
    br = nb.brick(nb.coord(1.0 / scale, rotation=(90, 0, 0)), scale=1.0 / block_h, c1=(1.0, 1.0, 1.0), c2=(0.8, 0.79, 0.76),
                  mortar=(0.55, 0.53, 0.5), mortar_size=0.035, mortar_smooth=0.5, width=block_w / block_h, height=1.0, offset=0.5)
    col = nb.mix(1.0, blocks, br.outputs["Color"], blend="MULTIPLY")
    mortar = pal.tint(P.lin(mortar_hex), "dark", 0.2)
    mort_mask = nb.map_range(br.outputs["Fac"], 0.5, 1.0, 0.0, 1.0)
    col = nb.mix(mort_mask, col, mortar)
    col = strokes(nb, 1.0 / scale, col, strength=0.07, scale=3.0, along="X")
    col, _ = edge_wear(nb, col, shade(light, 1.08, 0.75), amount=wear * 0.8, breakup_vec=v)
    col = base_grime(nb, col, shade(dark, 0.6, 1.1), 0.0, 0.5, amount=0.5 * age, vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.55), amount=0.45, distance=0.25)
    pits = nb.noise(nb.coord(4.0 / scale), scale=1.0, detail=2.0, rough=0.5)
    height = nb.math("ADD", nb.math("MULTIPLY", nb.invert(mort_mask), 0.75), nb.math("MULTIPLY", pits.outputs["Fac"], 0.25))
    normal = nb.bump(height, strength=0.45, distance=0.03)
    return nb.finish(col, rough_var(nb, v, 0.8, 0.08), 0.0, normal)


def drystone(pal=None, wear=0.4, age=0.5, tint=0.2, scale=1.0, name=None, base_hex="#8a8578", moss=0.3, **_):
    pal = _pal(pal)
    nb = NB(name or "drystone")
    base = pal.tint(P.lin(base_hex), "mid", tint)
    dark, mid, light = trio(base, 0.9)
    v = nb.coord(1.0 / scale)
    blocks = paint_blocks(nb, nb.coord(0.6 / scale), [dark, mid, light])
    sv = nb.coord((3.0 / scale, 3.0 / scale, 7.0 / scale))
    edge = nb.voronoi(sv, scale=1.0, feature="DISTANCE_TO_EDGE")
    cells = nb.voronoi(sv, scale=1.0, feature="F1")
    stone = nb.map_range(edge.outputs["Distance"], 0.0, 0.09, 0.0, 1.0)
    percell = nb.ramp(cells.outputs["Color"], [(0.0, 0.82), (1.0, 1.15)], interp="LINEAR")
    col = nb.mix(1.0, blocks, percell, blend="MULTIPLY")
    gap = shade(dark, 0.45, 1.1)
    col = nb.mix(nb.invert(stone), col, gap)
    if moss > 0:
        mn = nb.noise(nb.coord(1.5 / scale), scale=1.0, detail=2.0, rough=0.5)
        mm = nb.math("MULTIPLY", nb.map_range(mn.outputs["Fac"], 0.55, 0.75, 0.0, 1.0), nb.invert(stone), clamp=True)
        mm = nb.math("MULTIPLY", mm, moss * 2.0, clamp=True)
        col = nb.mix(mm, col, pal.tint(P.lin("#6a7f34"), "green", 0.4))
    col, _ = edge_wear(nb, col, shade(light, 1.05, 0.8), amount=wear * 0.6, breakup_vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.55), amount=0.4, distance=0.2)
    normal = nb.bump(nb.math("ADD", nb.math("MULTIPLY", stone, 0.8), nb.math("MULTIPLY", cells.outputs["Distance"], 0.2)), strength=0.6, distance=0.04)
    return nb.finish(col, rough_var(nb, v, 0.82, 0.08), 0.0, normal)


def _rock_common(nb, pal, base, spread, tint_role, tint, wear, age, speckle=0.0, speckle_col=None,
                 bands=0.0, pits=0.3, lichen=0.0, lichen_col=None, sheen=0.0, scale=1.0, cavity=0.5,
                 grime=0.5, facet=0.45, bed_relief=0.0, relief=1.0):
    """Shared body of every quarried stone. `relief` scales the surface bump, whose
    distance is an absolute 50 mm -- chosen for a boulder and a cliff slab, where it is the
    swell of the rock face, and a quarter of the whole object on a 0.22 m mortar. It is the
    fifth instance of the fault the forge README's "scale constant" section lists. Only
    `granite` passes it so far because only `granite` has been asked for at hand size; the
    others take it in one line each the day something small is built out of them."""
    dark, mid, light = trio(base, spread)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.45 / scale), [dark, mid, light], distortion=1.3, detail=2.0)
    col = strokes(nb, 1.0 / scale, col, strength=0.09, scale=2.5, along="X")
    if bands > 0:
        # Nearly two bands a metre painted every stone with corduroy. A bedded rock shows a
        # few broad partings, not a woven cloth.
        w = nb.wave(nb.coord((0.6 / scale, 0.6 / scale, 0.6 / scale)), scale=1.1, distortion=2.5, detail=1.0, direction="Z")
        band = nb.ramp(w.outputs["Fac"], [(0.3, 1.0 - 0.14 * bands), (0.7, 1.0 + 0.06 * bands)], interp="EASE")
        col = nb.mix(1.0, col, band, blend="MULTIPLY")
    if speckle > 0:
        sn = nb.noise(nb.coord(14.0 / scale), scale=1.0, detail=1.0, rough=0.5)
        sp = nb.map_range(sn.outputs["Fac"], 0.62, 0.75, 0.0, speckle)
        col = nb.mix(sp, col, speckle_col or shade(dark, 0.7))
    if pits > 0:
        pv = nb.voronoi(nb.coord(5.0 / scale), scale=1.0, feature="F1")
        pit = nb.map_range(pv.outputs["Distance"], 0.05, 0.2, 1.0, 0.0)
        pg = nb.noise(nb.coord(1.2 / scale), scale=1.0, detail=1.0, rough=0.5)
        pit = nb.math("MULTIPLY", pit, nb.map_range(pg.outputs["Fac"], 0.5, 0.7, 0.0, pits), clamp=True)
        col = nb.mix(pit, col, shade(dark, 0.75))
    else:
        pit = None
    if lichen > 0:
        ln = nb.noise(nb.coord(3.0 / scale), scale=1.0, detail=2.0, rough=0.55, distortion=0.6)
        lm = nb.map_range(ln.outputs["Fac"], 0.68 - 0.1 * lichen, 0.78, 0.0, 1.0)
        up = nb.node("ShaderNodeNewGeometry").outputs["Normal"]
        upz = nb.node("ShaderNodeSeparateXYZ", inputs={"Vector": up}).outputs["Z"]
        lm = nb.math("MULTIPLY", lm, nb.map_range(upz, -0.2, 0.6, 0.2, 1.0), clamp=True)
        col = nb.mix(lm, col, lichen_col or P.lin("#a9a56a"))
    col, _ = edge_wear(nb, col, shade(light, 1.08, 0.75), amount=wear, lo=0.51, hi=0.6, breakup_vec=v, breakup_scale=3.0)
    col = base_grime(nb, col, shade(dark, 0.6, 1.15), 0.0, 0.4, amount=grime * age, vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.5, 1.1), amount=cavity, distance=0.35, breakup_vec=v)
    # Relief: broad lumps plus the edges of a Voronoi cell field, so the surface has facets
    # and grain rather than a soft haze. Without the cell term the baked normal map comes
    # out almost flat and the stone reads as painted paper.
    hn = nb.noise(nb.coord(2.0 / scale), scale=1.0, detail=3.0, rough=0.5)
    # Facets, but weathered stone rather than cut crystal. Three things keep the cell field
    # from baking a lattice of hard black creases into the normal map: the lookup is warped
    # so no wall runs straight, the ramp is wide so a crease is a slope instead of a step,
    # and the floor is lifted off zero so the cell interiors are gently domed planes.
    fwarp = nb.noise(nb.coord(1.3 / scale), scale=1.0, detail=2.0, rough=0.55)
    cell = nb.voronoi(nb.vwarp(nb.coord(3.2 / scale), fwarp.outputs["Color"], 0.5),
                      scale=1.0, feature="DISTANCE_TO_EDGE", randomness=0.9)
    facet_mask = nb.map_range(cell.outputs["Distance"], 0.0, 0.34, 0.25, 1.0)
    height = nb.math("ADD", nb.math("MULTIPLY", hn.outputs["Fac"], 1.0 - facet),
                     nb.math("MULTIPLY", facet_mask, facet))
    if bed_relief > 0.0:
        # Karst limestone is bedded: the ledges are what make a pavement read as one.
        # Coarse. At 2.4 cycles a metre the bedding came out as corduroy over the whole
        # rock rather than as the few partings a bedded stone actually shows.
        bw = nb.wave(nb.coord((0.5 / scale, 0.5 / scale, 0.7 / scale)), scale=2.0, distortion=2.0,
                     detail=1.0, direction="Z", profile="SAW")
        height = nb.math("ADD", height, nb.math("MULTIPLY", bw.outputs["Fac"], bed_relief))
    if pit is not None:
        height = nb.math("SUBTRACT", height, nb.math("MULTIPLY", pit, 0.4))
    # 0.8 read as embossed sheet metal once the facets were in; the relief has to be felt
    # at a glance and not analysed, so it is strong but well short of self-shadowing.
    normal = nb.bump(height, strength=0.5, distance=0.05 * relief)
    rough = rough_var(nb, v, 0.85 - 0.4 * sheen, 0.08)
    if sheen > 0:
        rough = nb.mix(nb.pointiness(0.5, 0.6), rough, 0.35)
    return nb.finish(col, rough, 0.0, normal)


def granite(pal=None, wear=0.5, age=0.5, tint=0.18, scale=1.0, name=None, lichen=0.35,
            base_hex="#6f6d6a", tint_role="cool", facet=0.6, relief=1.0, **_):
    """Weathered granite. `lichen`, `base_hex` and `tint_role` are for the same stone put
    to a different use: a boulder on a hillside has spent a century growing lichen, and a
    millstone under a roof, wetted and dressed and swept every day, has grown none at all
    and is the warmer, drier colour of a quarried grit. The defaults are the hillside.

    `relief` scales the surface bump, an absolute 50 mm: right for the boulder it was
    chosen for, and a quarter of the whole object on a 0.22 m mortar. A hand-sized stone
    wants about a fifth of it."""
    pal = _pal(pal)
    nb = NB(name or "granite")
    base = pal.tint(P.lin(base_hex), tint_role, tint)
    return _rock_common(nb, pal, base, 1.05, tint_role, tint, wear, age, speckle=0.75,
                        speckle_col=P.lin("#2e2d30"), pits=0.25, lichen=lichen,
                        lichen_col=P.lin("#a3a878"), scale=scale, facet=facet, relief=relief)


def limestone(pal=None, wear=0.5, age=0.5, tint=0.12, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "limestone")
    base = pal.tint(P.lin("#9a9382"), "light", tint)
    return _rock_common(nb, pal, base, 1.0, "light", tint, wear, age, bands=1.2, pits=0.5, lichen=0.3,
                        lichen_col=P.lin("#b0a758"), scale=scale, facet=0.35, bed_relief=0.55)


def chalk_rock(pal=None, wear=0.5, age=0.4, tint=0.12, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "chalk_rock")
    # Chalk is the brightest stone in the game, which makes it the easiest to blow out;
    # the base sits well below white so the highlight has somewhere to go.
    # Lighter than this and a chalk boulder bakes out near white, which carries no region
    # at all; the highlight needs room above the base, not the base sitting in it.
    base = pal.tint(P.lin("#b6ae99"), "earth", tint + 0.06)
    # Chalk weathers round, not faceted: soft lumps, flint specks, no crystal edges.
    return _rock_common(nb, pal, base, 0.9, "light", tint, wear, age, bands=0.5, pits=0.3,
                        speckle=0.3, speckle_col=P.lin("#5a564e"), scale=scale, grime=0.7,
                        facet=0.12)


def lake_stone(pal=None, wear=0.35, age=0.6, tint=0.16, scale=1.0, name=None, relief=1.0, **_):
    """Brightwater's lake stone: near-black, close-grained, never quite dry.

    The region is named for the water and this is the stone under it. It is not the warm
    grey of the other rocks and it must not be mistaken for a slab that happens to be dark:
    what makes it read as lake stone is that the light coming back off a wet edge is the
    sky's, so the highlight is cold and blue while the body stays almost black.

    `relief` scales the bedding bump, whose distance is an absolute 40 mm and does not
    follow `scale`. That is a soft swell on a boulder and a flight of steps on a hone: the
    first whetstone the forge made was a 40 mm block carrying a 40 mm bump, and its sides
    came out as courses of stacked slate. Anything hand-sized wants about a tenth. The
    default is 1.0 so every slab and step built before this bakes as it did.
    """
    pal = _pal(pal)
    nb = NB(name or "lake_stone")
    base = pal.tint(P.lin("#1a1f25"), "cool", tint)
    dark, mid, light = trio(base, 1.3)
    cold = P.lin("#7796b0")
    light = tuple(l * 0.42 + c * 0.58 for l, c in zip(light, cold))
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.5 / scale), [dark, mid, light], distortion=1.1, detail=2.0)
    # Close grain: fine parallel bedding rather than the blocky facets of a quarried stone.
    w = nb.wave(nb.coord((0.7 / scale, 0.7 / scale, 5.0 / scale)), scale=3.0, distortion=1.6,
                detail=2.0, detail_scale=0.6, direction="Z")
    band = nb.ramp(w.outputs["Fac"], [(0.25, 0.8), (0.6, 1.0), (0.9, 1.25)], interp="EASE")
    col = nb.mix(0.9, col, nb.mix(1.0, col, band, blend="MULTIPLY"))
    col = strokes(nb, 1.0 / scale, col, strength=0.07, scale=3.0, along="X")
    col, _ = edge_wear(nb, col, light, amount=wear * 0.85, lo=0.5, hi=0.58, breakup_vec=v)
    col = base_grime(nb, col, P.lin("#2a3a32"), 0.0, 0.45, amount=0.5 * age, vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.6, 1.1), amount=0.35, distance=0.3, breakup_vec=v)
    hn = nb.noise(nb.coord(2.4 / scale), scale=1.0, detail=3.0, rough=0.5)
    bedding = nb.wave(nb.coord((0.6 / scale, 0.6 / scale, 4.0 / scale)), scale=2.5, distortion=1.2,
                      detail=1.0, direction="Z", profile="SAW")
    height = nb.math("ADD", nb.math("MULTIPLY", hn.outputs["Fac"], 0.55),
                     nb.math("MULTIPLY", bedding.outputs["Fac"], 0.45))
    normal = nb.bump(height, strength=0.4, distance=0.04 * relief)
    # Wet: low roughness everywhere, lower still on the edges the water runs off.
    rough = rough_var(nb, v, 0.4, 0.1)
    rough = nb.mix(nb.pointiness(0.5, 0.62), rough, 0.16)
    return nb.finish(col, rough, 0.0, normal)


def drowned_stone(pal=None, wear=0.3, age=0.8, tint=0.3, scale=1.0, name=None, **_):
    """The part of a stone that has been under peat water: green-black, slick, silted.

    Paired with a dressed stone above the silt line, this is what says the fen came up and
    took something that was built.
    """
    pal = _pal(pal)
    nb = NB(name or "drowned_stone")
    base = pal.tint(P.lin("#22302a"), "green", tint)
    dark, mid, light = trio(base, 1.15)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.7 / scale), [dark, mid, light], distortion=1.5, detail=2.5)
    # weed and silt clinging in patches rather than an even coat
    wn = nb.noise(nb.coord(2.6 / scale), scale=1.0, detail=3.0, rough=0.6, distortion=0.8)
    weed = nb.map_range(wn.outputs["Fac"], 0.48, 0.72, 0.0, 1.0)
    col = nb.mix(weed, col, pal.tint(P.lin("#3d5a2e"), "green", 0.35))
    silt = nb.noise(nb.coord(1.1 / scale), scale=1.0, detail=2.0, rough=0.5)
    col = nb.mix(nb.map_range(silt.outputs["Fac"], 0.55, 0.78, 0.0, 0.55), col,
                 P.lin("#4a4433"))
    col, _ = cavity_dirt(nb, col, P.lin("#141c18"), amount=0.55, distance=0.25, breakup_vec=v)
    hn = nb.noise(nb.coord(3.2 / scale), scale=1.0, detail=3.0, rough=0.55)
    normal = nb.bump(hn.outputs["Fac"], strength=0.3, distance=0.03)
    rough = rough_var(nb, v, 0.3, 0.12)
    return nb.finish(col, rough, 0.0, normal)


def fused_stone(pal=None, wear=0.4, age=0.7, tint=0.15, scale=1.0, gilding=0.0, name=None, **_):
    """Oroth builder-stone: black, glassy, faintly flowing, with old gilding in the hollows."""
    pal = _pal(pal)
    nb = NB(name or "fused_stone")
    base = pal.tint(P.lin("#1d1d21"), "dark", tint)
    dark, mid, light = trio(base, 1.5)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.4 / scale), [dark, mid, light], distortion=1.6)
    w = nb.wave(nb.coord((0.8 / scale, 0.8 / scale, 0.8 / scale)), scale=2.0, distortion=6.0, detail=2.0, detail_scale=0.5, direction="Z")
    # The Builders' stone is poured, not cut: the flow lines are the whole point of it.
    flow = nb.ramp(w.outputs["Fac"], [(0.18, 0.55), (0.5, 1.0), (0.85, 1.85)], interp="EASE")
    col = nb.mix(0.95, col, nb.mix(1.0, col, flow, blend="MULTIPLY"))
    col = strokes(nb, 1.0 / scale, col, strength=0.06, scale=3.0, along="Z")
    col, _ = edge_wear(nb, col, shade(light, 1.25, 0.6), amount=wear * 0.7, lo=0.5, hi=0.6, breakup_vec=v)
    if gilding > 0:
        gold = pal.tint(P.lin("#b08a3e"), "warm", 0.3)
        occ = nb.ao(distance=0.4)
        gm = nb.map_range(occ, 0.3, 0.85, 1.0, 0.0)
        gn = nb.noise(nb.coord(2.0 / scale), scale=1.0, detail=2.0, rough=0.5)
        gm = nb.math("MULTIPLY", gm, nb.map_range(gn.outputs["Fac"], 0.45, 0.7, 0.0, gilding * 1.5), clamp=True)
        col = nb.mix(gm, col, gold)
        metal = gm
    else:
        metal = 0.0
    col = base_grime(nb, col, P.lin("#5a5652"), 0.0, 0.8, amount=0.5 * age, vec=v)
    col, _ = cavity_dirt(nb, col, P.lin("#6a6660"), amount=0.35, distance=0.4, breakup_vec=v)
    normal = nb.bump(nb.math("ADD", nb.math("MULTIPLY", w.outputs["Fac"], 0.65),
                             nb.math("MULTIPLY", nb.noise(nb.coord(1.5 / scale), scale=1.0, detail=2.0).outputs["Fac"], 0.35)),
                     strength=0.45, distance=0.03)
    # Glassy: low roughness overall, polished further on the ridges, with the flow lines
    # themselves catching light differently from the hollows.
    rough = nb.mix(nb.map_range(w.outputs["Fac"], 0.2, 0.8, 0.0, 1.0), rough_var(nb, v, 0.22, 0.06), 0.46)
    rough = nb.mix(nb.pointiness(0.5, 0.6), rough, 0.14)
    return nb.finish(col, rough, metal, normal)


def slate_tiles(pal=None, wear=0.4, age=0.5, tint=0.25, scale=1.0, tile_w=0.3, tile_h=0.25, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "slate_tiles")
    base = pal.tint(P.lin("#565c66"), "cool", tint)
    dark, mid, light = trio(base, 0.8)
    v = nb.coord(1.0 / scale)
    blocks = paint_blocks(nb, nb.coord(0.8 / scale), [dark, mid, light])
    br = nb.brick(nb.coord(1.0 / scale), scale=1.0 / tile_h, c1=(1.0, 1.0, 1.0), c2=(0.82, 0.84, 0.88), mortar=(0.3, 0.32, 0.36),
                  mortar_size=0.02, mortar_smooth=0.2, width=tile_w / tile_h, height=1.0, offset=0.5)
    col = nb.mix(1.0, blocks, br.outputs["Color"], blend="MULTIPLY")
    col = strokes(nb, 1.0 / scale, col, strength=0.08, scale=6.0, along="Y")
    col, _ = edge_wear(nb, col, shade(light, 1.1, 0.7), amount=wear * 0.7, breakup_vec=v)
    ln = nb.noise(nb.coord(2.0 / scale), scale=1.0, detail=2.0, rough=0.5)
    lm = nb.map_range(ln.outputs["Fac"], 0.66, 0.8, 0.0, 0.7 * age)
    col = nb.mix(lm, col, P.lin("#9a9a7a"))
    col, _ = cavity_dirt(nb, col, shade(dark, 0.6), amount=0.35, distance=0.15)
    normal = nb.bump(br.outputs["Fac"], strength=0.5, distance=0.02, invert=True)
    return nb.finish(col, rough_var(nb, v, 0.6, 0.1), 0.0, normal)


def _thatch_common(nb, pal, base, age, scale, along, fibre_scale, grey_hex, courses=0.0):
    """Thatch and straw are bundles of stems, so the surface needs discrete strands rather
    than a smooth grain: a Voronoi field squashed hard along the lay direction gives each
    stem its own tone and its own edge, and a coarse band on top reads as the courses a
    thatcher lays."""
    dark, mid, light = trio(base, 1.0)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.6 / scale), [dark, mid, light], distortion=0.8)
    # squash across the lay direction so cells become long stems
    s = {"X": (0.06, 1.0, 1.0), "Y": (1.0, 0.06, 1.0), "Z": (1.0, 1.0, 0.06)}[along]
    sv = nb.coord((fibre_scale * s[0] / scale, fibre_scale * s[1] / scale, fibre_scale * s[2] / scale))
    stems = nb.voronoi(sv, scale=1.0, feature="F1", randomness=1.0)
    stem_tone = nb.ramp(stems.outputs["Color"], [(0.0, 0.62), (0.45, 0.95), (1.0, 1.22)], interp="LINEAR")
    col = nb.mix(1.0, col, stem_tone, blend="MULTIPLY")
    edge = nb.voronoi(sv, scale=1.0, feature="DISTANCE_TO_EDGE")
    gap = nb.map_range(edge.outputs["Distance"], 0.0, 0.05, 0.0, 1.0)
    col = nb.mix(nb.invert(gap), col, shade(dark, 0.45, 1.1))
    fib = nb.noise(sv, scale=2.0, detail=3.0, rough=0.6, distortion=0.4)
    col = nb.mix(0.35, col, nb.mix(1.0, col, nb.ramp(fib.outputs["Fac"], [(0.3, 0.85), (0.7, 1.12)]),
                                   blend="MULTIPLY"))
    if courses > 0.0:
        cw = nb.wave(nb.coord((0.9 / scale, 0.9 / scale, 0.9 / scale)), scale=3.2, distortion=1.4,
                     detail=1.0, direction="Z", profile="SAW")
        col = nb.mix(courses, col, nb.mix(1.0, col,
                     nb.ramp(cw.outputs["Fac"], [(0.05, 0.72), (0.35, 1.0), (1.0, 1.08)], interp="EASE"),
                     blend="MULTIPLY"))
    grey = P.lin(grey_hex)
    gn = nb.noise(nb.coord(0.9 / scale), scale=1.0, detail=2.0, rough=0.5, distortion=0.7)
    gm = nb.map_range(gn.outputs["Fac"], 0.55 - 0.2 * age, 0.75, 0.0, age)
    col = nb.mix(gm, col, grey)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.55), amount=0.45, distance=0.25, cheap=True)
    height = nb.math("ADD", nb.math("MULTIPLY", gap, 0.7), nb.math("MULTIPLY", fib.outputs["Fac"], 0.3))
    normal = nb.bump(height, strength=0.85, distance=0.035)
    return nb.finish(col, rough_var(nb, v, 0.92, 0.05), 0.0, normal)


def thatch(pal=None, age=0.5, tint=0.3, scale=1.0, along="Y", name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "thatch")
    base = pal.tint(P.lin("#c19a45"), "warm", tint)
    return _thatch_common(nb, pal, base, age * 0.8, scale, along, 22.0, "#8a8574", courses=0.7)


def reed_thatch(pal=None, age=0.5, tint=0.3, scale=1.0, along="Y", name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "reed_thatch")
    base = pal.tint(P.lin("#8f8a55"), "accent", tint * 0.5)
    return _thatch_common(nb, pal, base, age, scale, along, 36.0, "#6f7468", courses=0.55)


def straw(pal=None, age=0.3, tint=0.3, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "straw")
    base = pal.tint(P.lin("#c9a852"), "warm", tint)
    return _thatch_common(nb, pal, base, age, scale, "X", 30.0, "#9a9070")


def _metal_common(nb, pal, base, rough_base, age, wear, corrosion_col, corrosion_rough, dent=0.25, scale=1.0,
                  corrosion_metal=0.15, streaks=0.0):
    dark, mid, light = trio(base, 0.7)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.8 / scale), [dark, mid, light], distortion=0.7)
    col = strokes(nb, 1.0 / scale, col, strength=0.07, scale=5.0, along="Z")
    # corrosion (rust / patina) grows in cavities and in noisy patches, more with age
    occ = nb.ao(distance=0.15)
    cav = nb.map_range(occ, 0.3, 0.95, 1.0, 0.0)
    cn = nb.noise(nb.coord(3.0 / scale), scale=1.0, detail=2.0, rough=0.55, distortion=0.5)
    patch = nb.map_range(cn.outputs["Fac"], 0.72 - 0.35 * age, 0.85, 0.0, 1.0)
    cor = nb.math("ADD", nb.math("MULTIPLY", cav, 0.4 + 0.6 * age), patch, clamp=True)
    if streaks > 0:
        w = nb.wave(nb.coord((1.0 / scale, 1.0 / scale, 0.1 / scale)), scale=8.0, distortion=1.5, detail=1.0, direction="X")
        st = nb.map_range(w.outputs["Fac"], 0.6, 0.9, 0.0, streaks * age)
        cor = nb.math("ADD", cor, st, clamp=True)
    cor = nb.math("MULTIPLY", cor, min(1.0, 0.2 + age), clamp=True)
    # convex edges stay bright metal
    edge = nb.pointiness(0.5, 0.62)
    cor = nb.math("MULTIPLY", cor, nb.map_range(edge, 0.0, 1.0, 1.0, 0.25), clamp=True)
    cdark, cmid, clight = trio(corrosion_col, 0.8)
    ccol = paint_blocks(nb, nb.coord(2.0 / scale), [cdark, cmid, clight])
    col = nb.mix(cor, col, ccol)
    bright = shade(light, 1.15, 0.8)
    col, _ = edge_wear(nb, col, bright, amount=wear * 0.7, lo=0.52, hi=0.66, breakup_vec=v)
    dents = nb.voronoi(nb.coord(6.0 / scale), scale=1.0, feature="SMOOTH_F1", smoothness=0.8)
    height = nb.math("ADD", nb.math("MULTIPLY", dents.outputs["Distance"], dent), nb.math("MULTIPLY", cor, 0.5))
    normal = nb.bump(height, strength=0.3, distance=0.01)
    rough = nb.mix(cor, rough_var(nb, v, rough_base, 0.08), corrosion_rough)
    rough = nb.mix(edge, rough, rough_base * 0.6)
    metal = nb.mix(cor, 1.0, corrosion_metal)
    return nb.finish(col, rough, metal, normal)


def iron(pal=None, age=0.5, wear=0.5, tint=0.05, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "iron")
    base = pal.tint(P.lin("#3d3f44"), "dark", tint)
    return _metal_common(nb, pal, base, 0.55, age, wear, P.lin("#7a3f22"), 0.9, dent=0.3, scale=scale, streaks=0.5)


def steel(pal=None, age=0.2, wear=0.8, tint=0.04, scale=1.0, name=None, **_):
    """Worked blade iron, ground and kept: grey and light, bright along every edge, rust only in
    the pits. `iron` is the smith's raw stock and the fittings, near black under the review's
    exposure; a blade in it read as a stick of charcoal."""
    pal = _pal(pal)
    nb = NB(name or "steel")
    base = pal.tint(P.lin("#7f848c"), "cool", tint)
    return _metal_common(nb, pal, base, 0.36, age, wear, P.lin("#6b4a30"), 0.85, dent=0.12, scale=scale,
                         streaks=0.2)


def bronze(pal=None, age=0.5, wear=0.5, tint=0.1, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "bronze")
    base = pal.tint(P.lin("#8a5f30"), "warm", tint)
    return _metal_common(nb, pal, base, 0.42, age, wear, P.lin("#3f7f6a"), 0.85, dent=0.2, scale=scale, streaks=0.4)


def brass(pal=None, age=0.4, wear=0.5, tint=0.1, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "brass")
    base = pal.tint(P.lin("#b08a3e"), "warm", tint)
    return _metal_common(nb, pal, base, 0.35, age * 0.7, wear, P.lin("#5a4a2a"), 0.7, dent=0.15, scale=scale, corrosion_metal=0.6)


def bell_bronze_patina(pal=None, age=0.85, wear=0.5, tint=0.1, scale=1.0, name=None, **_):
    """Old bell metal: mostly green-blue patina with bare bronze on rubbed edges and long
    streaks running down."""
    pal = _pal(pal)
    nb = NB(name or "bell_bronze_patina")
    base = pal.tint(P.lin("#7a5a30"), "warm", tint)
    return _metal_common(nb, pal, base, 0.5, age, wear, pal.tint(P.lin("#4c8a78"), "cool", 0.25), 0.9, dent=0.15,
                         scale=scale, streaks=1.0)


def blackened_iron(pal=None, age=0.4, wear=0.6, tint=0.05, scale=1.0, name=None, **_):
    """The Ash-knights' iron: fire-blackened, greyed where the ash has worked into it, bright
    only where an edge is kept."""
    pal = _pal(pal)
    nb = NB(name or "blackened_iron")
    base = pal.tint(P.lin("#232326"), "dark", tint)
    return _metal_common(nb, pal, base, 0.62, age, wear, P.lin("#6f6a64"), 0.95, dent=0.25, scale=scale,
                         streaks=0.3, corrosion_metal=0.1)


def rope(pal=None, age=0.4, tint=0.15, scale=1.0, name=None, axis="Z", **_):
    """Twisted hemp; the twist runs around the object's `axis`."""
    pal = _pal(pal)
    nb = NB(name or "rope")
    base = pal.tint(P.lin("#a6895a"), "earth", tint)
    base = shade(base, 1.0 - 0.2 * age, 1.0 - 0.15 * age)
    dark, mid, light = trio(base, 0.9)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(2.0 / scale), [dark, mid, light])
    rot = {"Z": (0, 0, 0), "X": (0, 90, 0), "Y": (90, 0, 0)}[axis]
    w = nb.wave(nb.coord(1.0 / scale, rotation=rot), scale=40.0, distortion=0.8, detail=1.0, direction="DIAGONAL", kind="BANDS")
    tone = nb.ramp(w.outputs["Fac"], [(0.2, 0.7), (0.55, 1.0), (0.9, 1.15)], interp="EASE")
    col = nb.mix(1.0, col, tone, blend="MULTIPLY")
    col, _ = cavity_dirt(nb, col, shade(dark, 0.6), amount=0.4, distance=0.05)
    normal = nb.bump(w.outputs["Fac"], strength=0.5, distance=0.006)
    return nb.finish(col, rough_var(nb, v, 0.9, 0.05), 0.0, normal)


def dyed_cloth(pal=None, role="accent", color=None, age=0.4, wear=0.3, tint=0.6, scale=1.0, name=None, **_):
    """Woven cloth in a palette colour (or an explicit linear `color`)."""
    pal = _pal(pal)
    nb = NB(name or "dyed_cloth")
    base = color if color is not None else P.mix(P.lin("#8a7f6a"), pal.role(role), tint)
    base = shade(base, 1.0 - 0.15 * age, 1.0 - 0.2 * age)
    dark, mid, light = trio(base, 0.8)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(1.2 / scale), [dark, mid, light], distortion=1.2)
    wx = nb.wave(nb.coord(1.0 / scale), scale=90.0, distortion=0.2, detail=0.0, direction="X")
    wy = nb.wave(nb.coord(1.0 / scale), scale=90.0, distortion=0.2, detail=0.0, direction="Y")
    weave = nb.math("MULTIPLY", wx.outputs["Fac"], wy.outputs["Fac"])
    col = nb.mix(0.35, col, nb.mix(1.0, col, nb.map_range(weave, 0.0, 1.0, 0.88, 1.06), blend="MULTIPLY"))
    col = strokes(nb, 1.0 / scale, col, strength=0.08, scale=4.0, along="Z")
    col, _ = edge_wear(nb, col, shade(light, 1.1, 0.6), amount=wear * 0.8, lo=0.5, hi=0.6, breakup_vec=v)
    col = base_grime(nb, col, shade(dark, 0.55, 1.1), 0.0, 0.3, amount=0.6 * age, vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.7), amount=0.3, distance=0.1)
    normal = nb.bump(weave, strength=0.15, distance=0.003)
    return nb.finish(col, rough_var(nb, v, 0.88, 0.05), 0.0, normal)


def canvas(pal=None, **kw):
    kw.setdefault("color", P.lin("#c8bd9d"))
    return dyed_cloth(pal, name=kw.pop("name", "canvas"), **kw)


def leather(pal=None, age=0.5, wear=0.5, tint=0.15, scale=1.0, name=None, base_hex="#6e4a2b", **_):
    pal = _pal(pal)
    nb = NB(name or "leather")
    base = pal.tint(P.lin(base_hex), "earth", tint)
    dark, mid, light = trio(base, 0.9)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(1.5 / scale), [dark, mid, light], distortion=1.0)
    pores = nb.voronoi(nb.coord(60.0 / scale), scale=1.0, feature="F1")
    col = nb.mix(0.15, col, nb.mix(1.0, col, nb.map_range(pores.outputs["Distance"], 0.0, 0.5, 0.9, 1.05), blend="MULTIPLY"))
    cr = nb.noise(nb.coord(4.0 / scale), scale=1.0, detail=3.0, rough=0.6, distortion=1.5)
    crease = nb.map_range(cr.outputs["Fac"], 0.3, 0.42, 1.0, 0.0)
    col = nb.mix(nb.math("MULTIPLY", crease, 0.5 * age), col, shade(dark, 0.6))
    col, _ = edge_wear(nb, col, shade(light, 1.15, 0.7), amount=wear, lo=0.5, hi=0.62, breakup_vec=v)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.55), amount=0.4, distance=0.08)
    normal = nb.bump(nb.math("ADD", nb.math("MULTIPLY", pores.outputs["Distance"], 0.3), nb.math("MULTIPLY", crease, 0.7)), strength=0.25, distance=0.006)
    return nb.finish(col, rough_var(nb, v, 0.6, 0.1), 0.0, normal)


def moss(pal=None, age=0.3, tint=0.35, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "moss")
    base = pal.tint(P.lin("#4f7a2a"), "green", tint)
    dark, mid, light = trio(base, 1.0)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(2.0 / scale), [dark, mid, light], distortion=1.0)
    clumps = nb.voronoi(nb.coord(12.0 / scale), scale=1.0, feature="SMOOTH_F1", smoothness=0.6)
    tone = nb.ramp(clumps.outputs["Distance"], [(0.0, 1.15), (0.35, 1.0), (0.7, 0.72)], interp="EASE")
    col = nb.mix(1.0, col, tone, blend="MULTIPLY")
    dn = nb.noise(nb.coord(1.0 / scale), scale=1.0, detail=2.0, rough=0.5)
    col = nb.mix(nb.map_range(dn.outputs["Fac"], 0.6, 0.8, 0.0, 0.6 * age), col, P.lin("#7a6a3a"))
    col, _ = cavity_dirt(nb, col, shade(dark, 0.6), amount=0.35, distance=0.1)
    normal = nb.bump(clumps.outputs["Distance"], strength=0.6, distance=0.02, invert=True)
    return nb.finish(col, rough_var(nb, v, 0.95, 0.03), 0.0, normal)


def wet_mud(pal=None, age=0.5, tint=0.2, scale=1.0, name=None, base_hex="#4a3a2a", **_):
    """Churned wet ground. `base_hex` is for the other thing this surface is: cut peat,
    which is the same substance dug out and stood up to dry and is two stops darker than
    a puddle's edge."""
    pal = _pal(pal)
    nb = NB(name or "wet_mud")
    base = pal.tint(P.lin(base_hex), "dark", tint)
    dark, mid, light = trio(base, 0.8)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(1.0 / scale), [dark, mid, light], distortion=1.4)
    pn = nb.noise(nb.coord(2.5 / scale), scale=1.0, detail=2.0, rough=0.5)
    low = nb.map_range(pn.outputs["Fac"], 0.35, 0.55, 1.0, 0.0)
    col = nb.mix(low, col, shade(dark, 0.7, 1.1))
    normal = nb.bump(pn.outputs["Fac"], strength=0.3, distance=0.02)
    rough = nb.mix(low, 0.6, 0.2)
    return nb.finish(col, rough, 0.0, normal)


def bone(pal=None, age=0.5, wear=0.4, tint=0.2, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "bone")
    base = pal.tint(P.lin("#dfd6c2"), "light", tint)
    base = shade(base, 1.0 - 0.15 * age, 1.0 + 0.2 * age)
    dark, mid, light = trio(base, 0.6)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(0.5 / scale), [dark, mid, light], distortion=1.2)
    w = nb.wave(nb.coord((1.0 / scale, 1.0 / scale, 0.25 / scale)), scale=4.0, distortion=3.0, detail=1.0, direction="X")
    grain = nb.ramp(w.outputs["Fac"], [(0.3, 0.92), (0.7, 1.05)], interp="EASE")
    col = nb.mix(0.6, col, nb.mix(1.0, col, grain, blend="MULTIPLY"))
    pores = nb.voronoi(nb.coord(8.0 / scale), scale=1.0, feature="F1")
    pm = nb.map_range(pores.outputs["Distance"], 0.05, 0.18, 1.0, 0.0)
    pg = nb.noise(nb.coord(0.8 / scale), scale=1.0, detail=1.0, rough=0.5)
    pm = nb.math("MULTIPLY", pm, nb.map_range(pg.outputs["Fac"], 0.55, 0.75, 0.0, 0.8), clamp=True)
    col = nb.mix(pm, col, shade(dark, 0.7))
    col = strokes(nb, 1.0 / scale, col, strength=0.06, scale=3.0, along="Z")
    col, _ = edge_wear(nb, col, shade(light, 1.05, 0.7), amount=wear * 0.5, breakup_vec=v)
    col = base_grime(nb, col, P.lin("#6f6252"), 0.0, 0.5, amount=0.6 * age, vec=v)
    col, _ = cavity_dirt(nb, col, P.lin("#7a6e5e"), amount=0.45, distance=0.3, breakup_vec=v)
    normal = nb.bump(nb.math("ADD", nb.math("MULTIPLY", w.outputs["Fac"], 0.3), nb.math("MULTIPLY", pm, 0.7)), strength=0.3, distance=0.02)
    return nb.finish(col, rough_var(nb, v, 0.55, 0.1), 0.0, normal)


def ceramic(pal=None, role="accent", glaze=0.5, age=0.4, tint=0.4, scale=1.0, name=None, base_hex="#a8845c",
            relief=1.0, glaze_z=(0.05, 0.25), **_):
    """Earthenware with a partial glaze in a palette colour (running down from the rim).

    Two lengths in metres live in here, and both were chosen for a mug (see the forge
    README's section on the scale constant, which this is a fourth instance of):

    * `glaze_z` is where the glaze starts and finishes, in **object space metres**, not in
      units of `scale`. At its default the glaze fades in between 50 mm and 250 mm off the
      base, which is a mug, a jug and a cooking pot. On a 90 mm bowl every texel is below
      50 mm, so the whole of that term reads zero and the only glaze left is the drip; on a
      metre-tall vessel the glaze stops a quarter of the way up. Pass the object's own rim
      and shoulder heights and the glaze pours from the rim, which is where it is poured.
    * `relief` scales the fine bump, whose distance is an absolute 4 mm. That is a soft
      swell on a jug and a cobbled surface on a 90 mm bowl.

    Both default to the values that keep every vessel built before this byte-identical."""
    pal = _pal(pal)
    nb = NB(name or "ceramic")
    clay = pal.tint(P.lin(base_hex), "earth", 0.2)
    dark, mid, light = trio(clay, 0.6)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(2.0 / scale), [dark, mid, light])
    gl = P.mix(P.lin("#6a8a8a"), pal.role(role), tint)
    gdark, gmid, glight = trio(gl, 0.7)
    gcol = paint_blocks(nb, nb.coord(3.0 / scale), [gdark, gmid, glight])
    top = nb.height_mask(glaze_z[0], glaze_z[1])
    drip = nb.wave(nb.coord((1.0 / scale, 1.0 / scale, 0.15 / scale)), scale=10.0, distortion=1.0, detail=0.0, direction="X")
    gm = nb.math("ADD", top, nb.math("MULTIPLY", nb.map_range(drip.outputs["Fac"], 0.6, 0.9, 0.0, 1.0), 0.6), clamp=True)
    gm = nb.math("MULTIPLY", gm, glaze * 2.0, clamp=True)
    col = nb.mix(gm, col, gcol)
    col, _ = cavity_dirt(nb, col, shade(dark, 0.6), amount=0.3 * age, distance=0.08)
    rough = nb.mix(gm, rough_var(nb, v, 0.8, 0.05), 0.2)
    normal = nb.bump(nb.noise(nb.coord(6.0 / scale), scale=1.0, detail=1.0).outputs["Fac"], strength=0.1,
                     distance=0.004 * relief)
    return nb.finish(col, rough, 0.0, normal)


def parchment(pal=None, age=0.5, tint=0.15, scale=1.0, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "parchment")
    base = pal.tint(P.lin("#d9c9a3"), "light", tint)
    base = shade(base, 1.0 - 0.2 * age, 1.0 + 0.3 * age)
    dark, mid, light = trio(base, 0.5)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(3.0 / scale), [dark, mid, light], distortion=1.2)
    fox = nb.noise(nb.coord(8.0 / scale), scale=1.0, detail=2.0, rough=0.6)
    col = nb.mix(nb.map_range(fox.outputs["Fac"], 0.66, 0.8, 0.0, 0.7 * age), col, P.lin("#8a6a42"))
    col, _ = edge_wear(nb, col, shade(dark, 0.8), amount=0.4 * age, breakup_vec=v)
    return nb.finish(col, rough_var(nb, v, 0.85, 0.05), 0.0, nb.bump(fox.outputs["Fac"], strength=0.08, distance=0.003))


def bread(pal=None, bake=0.6, flour=0.4, tint=0.14, scale=1.0, name=None, **_):
    """A baked crust: dark where the oven caught it, pale where the flour stayed.

    Bread is the one surface in the library whose whole read is a *gradient within one
    object* rather than a pattern laid across many. A loaf is not a material with loaves
    cut out of it; it is a thing that was pale, went brown from the outside in, and kept
    flour on the parts the blade did not open. So the tone comes off the surface's own
    curvature -- the crown is baked and the crease under the score is not -- with the
    paint blocks only breaking up what the curvature gives. `bake` is how long it was in;
    `flour` is how much was thrown on the peel.

    Deliberately no bump beyond a fine one: the split crust is modelled geometry in
    `gen_props.loaf`, and adding a second, finer crust relief on top of it turned the
    scores into gravel at the only distance a loaf on a shelf is ever seen from."""
    pal = _pal(pal)
    nb = NB(name or "bread")
    crumb = pal.tint(P.lin("#e3cfa2"), "light", tint * 0.7)
    crust = pal.tint(P.lin("#8a5322"), "earth", tint)
    crust = shade(crust, value=1.0 - 0.30 * bake, sat=1.0 + 0.18 * bake)
    dark, mid, light = trio(crust, 0.8)
    v = nb.coord(1.0 / scale)
    col = paint_blocks(nb, nb.coord(1.1 / scale), [dark, mid, light], distortion=1.1, detail=2.0)
    # The crown catches the heat: convex is browner, and the shaded crease keeps the crumb.
    col, _ = edge_wear(nb, col, shade(dark, 0.72, 1.12), amount=0.45 * bake, lo=0.52, hi=0.66,
                       breakup_vec=v)
    col, _ = cavity_dirt(nb, col, crumb, amount=0.55 + 0.35 * flour, distance=0.05,
                         breakup_vec=v)
    # Flour: a soft dusting, broken up so it sits in patches the way thrown flour does.
    dust = nb.noise(nb.coord(3.4 / scale), scale=1.0, detail=3.0, rough=0.6)
    col = nb.mix(nb.map_range(dust.outputs["Fac"], 0.52, 0.80, 0.0, 0.75 * flour), col,
                 shade(crumb, 1.06, 0.55))
    col = strokes(nb, 1.0 / scale, col, strength=0.06, scale=4.0, along="X")
    grain = nb.noise(nb.coord(11.0 / scale), scale=1.0, detail=3.0, rough=0.55)
    normal = nb.bump(grain.outputs["Fac"], strength=0.22, distance=0.0016)
    return nb.finish(col, rough_var(nb, v, 0.78 - 0.10 * bake, 0.07), 0.0, normal)


def wax(pal=None, color=None, name=None, **_):
    nb = NB(name or "wax")
    base = color if color is not None else P.lin("#e8dcb8")
    dark, mid, light = trio(base, 0.35)
    v = nb.coord(1.0)
    col = paint_blocks(nb, nb.coord(4.0), [dark, mid, light])
    col, _ = cavity_dirt(nb, col, shade(dark, 0.8, 1.1), amount=0.3, distance=0.03)
    return nb.finish(col, 0.45, 0.0, nb.bump(nb.noise(nb.coord(15.0), scale=1.0, detail=1.0).outputs["Fac"], strength=0.1, distance=0.003))


def glass(pal=None, name=None, color=None, **_):
    """Old lantern glass: opaque-ish pale glass (Godot gets no transmission; keep it simple)."""
    nb = NB(name or "glass")
    base = color if color is not None else P.lin("#cfe0dc")
    col = paint_blocks(nb, nb.coord(6.0), list(trio(base, 0.3)))
    return nb.finish(col, 0.12, 0.0, None, specular=0.6)


def ember(pal=None, name=None, heat=1.0, **_):
    """Charcoal with glowing cracks (emissive; glTF emissive -> Godot emission)."""
    nb = NB(name or "ember")
    v = nb.coord(1.0)
    dark = P.lin("#1a1512")
    col = paint_blocks(nb, nb.coord(6.0), [dark, P.lin("#2a2320"), P.lin("#3a2e26")])
    vor = nb.voronoi(nb.coord(10.0), scale=1.0, feature="DISTANCE_TO_EDGE")
    crack = nb.map_range(vor.outputs["Distance"], 0.0, 0.08, 1.0, 0.0)
    glow = nb.ramp(crack, [(0.0, (0, 0, 0)), (0.5, P.lin("#c8320a")), (1.0, P.lin("#ffb340"))], interp="EASE")
    return nb.finish(col, 0.9, 0.0, nb.bump(vor.outputs["Distance"], strength=0.4, distance=0.01),
                     emission=glow, emission_strength=3.0 * heat)


def soot(pal=None, name=None, **_):
    nb = NB(name or "soot")
    col = paint_blocks(nb, nb.coord(3.0), list(trio(P.lin("#1e1c1b"), 0.6)))
    return nb.finish(col, 0.95, 0.0, None)


def snow(pal=None, name=None, **_):
    nb = NB(name or "snow")
    col = paint_blocks(nb, nb.coord(1.5), list(trio(P.lin("#f4f6f8"), 0.2)))
    return nb.finish(col, 0.6, 0.0, nb.bump(nb.noise(nb.coord(3.0), scale=1.0, detail=2.0).outputs["Fac"], strength=0.2, distance=0.02))


def water_still(pal=None, name=None, **_):
    pal = _pal(pal)
    nb = NB(name or "water_still")
    col = paint_blocks(nb, nb.coord(1.0), list(trio(pal.tint(P.lin("#2e5a66"), "cool", 0.4), 0.5)))
    return nb.finish(col, 0.08, 0.0, None, specular=0.7)


# ---------------------------------------------------------------------------------------
# image-based materials (foliage cards, grass): the textures are drawn by textures.py
# ---------------------------------------------------------------------------------------

def _load_image(path, srgb=True):
    img = bpy.data.images.load(str(path), check_existing=True)
    img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    img.alpha_mode = "CHANNEL_PACKED" if srgb else "NONE"
    return img


def image_material(name, albedo_path, normal_path=None, orm_path=None, alpha_clip=False, double_sided=False,
                   alpha_threshold=0.5, roughness=0.75, metallic=0.0, emission_path=None):
    """Principled BSDF fed by baked/drawn textures; the only material shape exported.
    The ORM image feeds Roughness (G) and Metallic (B); Occlusion (R) goes to the glTF
    Material Output group so the exporter writes one occlusionTexture."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    alb = nodes.new("ShaderNodeTexImage")
    alb.image = _load_image(albedo_path, srgb=True)
    alb.interpolation = "Linear"
    alb.location = (-600, 300)
    links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha_clip:
        links.new(alb.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.blend_method = "CLIP"
        mat.alpha_threshold = alpha_threshold
        mat.shadow_method = "CLIP"
    if normal_path:
        nrm = nodes.new("ShaderNodeTexImage")
        nrm.image = _load_image(normal_path, srgb=False)
        nrm.location = (-600, -300)
        nm = nodes.new("ShaderNodeNormalMap")
        nm.location = (-300, -300)
        links.new(nrm.outputs["Color"], nm.inputs["Color"])
        links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if orm_path:
        orm = nodes.new("ShaderNodeTexImage")
        orm.image = _load_image(orm_path, srgb=False)
        orm.location = (-600, 0)
        sep = nodes.new("ShaderNodeSeparateColor")
        sep.location = (-300, 0)
        links.new(orm.outputs["Color"], sep.inputs["Color"])
        links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        grp = _gltf_settings_group()
        gn = nodes.new("ShaderNodeGroup")
        gn.node_tree = grp
        gn.location = (0, -150)
        links.new(sep.outputs["Red"], gn.inputs["Occlusion"])
    if emission_path:
        em = nodes.new("ShaderNodeTexImage")
        em.image = _load_image(emission_path, srgb=True)
        links.new(em.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    mat.use_backface_culling = not double_sided
    return mat


def _gltf_settings_group():
    name = "glTF Material Output"
    grp = bpy.data.node_groups.get(name)
    if grp is None:
        grp = bpy.data.node_groups.new(name, "ShaderNodeTree")
        grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        inp = grp.nodes.new("NodeGroupInput")
        inp.location = (-200, 0)
    return grp


def foliage_material(name, albedo_path, normal_path=None, orm_path=None, threshold=0.45):
    """Leaf/grass card material. The name must end in _foliage so the Godot import step
    swaps in the wind shader (CONTRACTS.md §4)."""
    if not name.endswith("_foliage"):
        name = name + "_foliage"
    return image_material(name, albedo_path, normal_path, orm_path, alpha_clip=True, double_sided=True,
                          alpha_threshold=threshold, roughness=0.7)


# ---------------------------------------------------------------------------------------
# registry (for tests and generators that pick materials by name)
# ---------------------------------------------------------------------------------------

BUILDERS = {
    "lake_stone": lake_stone, "drowned_stone": drowned_stone,
    "wood_planks": wood_planks, "painted_wood": painted_wood, "carved_wood": carved_wood, "driftwood": driftwood,
    "oak_bark": oak_bark, "black_ash_bark": black_ash_bark, "birch_bark": birch_bark, "pine_bark": pine_bark,
    "willow_bark": willow_bark, "dead_bark": dead_bark,
    "plaster_limewash": plaster_limewash, "chalk_cob": chalk_cob, "stone_blocks": stone_blocks, "drystone": drystone,
    "granite": granite, "limestone": limestone, "chalk_rock": chalk_rock, "fused_stone": fused_stone,
    "slate_tiles": slate_tiles, "thatch": thatch, "reed_thatch": reed_thatch, "straw": straw,
    "iron": iron, "bronze": bronze, "brass": brass, "bell_bronze_patina": bell_bronze_patina,
    "rope": rope, "dyed_cloth": dyed_cloth, "canvas": canvas, "leather": leather, "moss": moss, "wet_mud": wet_mud,
    "bone": bone, "ceramic": ceramic, "parchment": parchment, "wax": wax, "glass": glass, "ember": ember,
    "soot": soot, "snow": snow, "water_still": water_still,
}


def by_name(name: str, pal=None, **kw):
    if name not in BUILDERS:
        raise KeyError("unknown material %r; have %s" % (name, ", ".join(sorted(BUILDERS))))
    return BUILDERS[name](pal, **kw)
