"""Trees grown as whole wood, by species (pure numpy: no bpy, so it is testable without Blender).

The forge grew its trees with Blender's Sapling and then decimated the wood to a triangle budget.
The decimator does not know what a branch is: it collapsed every limb into loose three-sided
shards (a median piece of 6 triangles, the largest trunk piece 14-57), and up close every tree in
the country read as broken. Blender 4.2 no longer carries Sapling in any case. This grows the tree
directly, the way `dead_tree.py` grows the dead ash, generalised to a table of species forms:

* **Continuous wood.** Every branch is one tapered tube that starts on its parent's axis, inside
  the parent, and closes to a point at its tip, so nothing floats and nothing is sliced. Radii
  follow the pipe rule: a child as long as the rest of its parent is nearly as thick (a fork),
  a short twig is thin.
* **The species' own form.** A trunk habit (a leader to the top, a trunk that forks into
  co-dominant limbs, several stems from the root, a pollard's knuckle of rods), tropism (ash tips
  turning up, willow whips hanging), gnarl, and a crown envelope -- dome, cone, ovoid, umbrella,
  vase -- that prunes every branch to the silhouette the species has.
* **A budget kept by dropping whole twigs.** `trim` removes the least important branches whole,
  never a child before its parent is gone, until the wood fits; LOD1 is the same tree trimmed
  harder and drawn with fewer sides. No triangle of wood is ever collapsed.
* **Leaf clumps on the fine twigs**, each with an exposure (how far out and up in the crown it
  is) so the card builder can give outer clumps the sunlit half of the atlas and inner ones the
  shaded half: the crown is shaded as a mass, the way a painted tree is.

Coordinates are Blender's: Z up, metres, the trunk's foot at the origin.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

# --- species forms ------------------------------------------------------------------------------
#
# habit     excurrent: one leader to the top (pine, alder, lime, ash); decurrent: the trunk forks
#           into `forks` co-dominant limbs at `fork_at` of the height (oak, apple, willow);
#           multistem: `stems` trunks from the root (hawthorn, juniper, yew, rowan);
#           pollard: a squat trunk whose head carries a crown of straight rods.
# crown     (shape, width, base): the envelope's shape, its widest radius over the height, and the
#           fraction of the height where the crown starts.
# levels    per branching level below the trunk: n = children per metre of parent, angle = degrees
#           from the parent's axis, up = tropism (+ toward the sky, - hanging), gnarl = the kink per
#           segment, span = the part of the parent they grow from, reach = length over what is
#           left of the parent above the fork.
# leaf      clump: card size over the height; per_m: clumps per metre of the finest twigs.

FORMS = {
    "oak": dict(
        habit="decurrent", forks=(3, 4), fork_at=(0.30, 0.40), trunk_r=0.040, lean=0.06, gnarl=0.10,
        flare=0.55, roots=5, crown=("dome", 0.72, 0.26), fork_angle=(42, 62), fork_up=-0.05,
        levels=[dict(n=1.2, angle=(55, 82), up=-0.02, gnarl=0.22, span=(0.12, 0.95), reach=0.8),
                dict(n=2.6, angle=(35, 60), up=0.10, gnarl=0.26, span=(0.15, 1.0), reach=0.55),
                dict(n=3.2, angle=(30, 55), up=0.15, gnarl=0.25, span=(0.2, 1.0), reach=0.6)],
        leaf=dict(clump=0.125, per_m=2.2), bark_w=0.55),
    "giant_oak": dict(
        habit="decurrent", forks=(4, 5), fork_at=(0.22, 0.30), trunk_r=0.052, lean=0.04, gnarl=0.08,
        flare=0.9, roots=7, crown=("dome", 0.68, 0.22), fork_angle=(35, 58), fork_up=0.02,
        levels=[dict(n=0.75, angle=(50, 78), up=0.0, gnarl=0.22, span=(0.12, 0.95), reach=0.58),
                dict(n=1.0, angle=(35, 60), up=0.05, gnarl=0.25, span=(0.15, 1.0), reach=0.5),
                dict(n=1.4, angle=(30, 55), up=0.12, gnarl=0.25, span=(0.2, 1.0), reach=0.55)],
        leaf=dict(clump=0.115, per_m=0.9), bark_w=1.1),
    "apple": dict(
        habit="decurrent", forks=(3, 5), fork_at=(0.22, 0.30), trunk_r=0.050, lean=0.12, gnarl=0.14,
        flare=0.35, roots=0, crown=("round", 0.62, 0.25), fork_angle=(38, 58), fork_up=0.0,
        levels=[dict(n=1.7, angle=(40, 70), up=0.0, gnarl=0.28, span=(0.1, 0.95), reach=0.6),
                dict(n=3.0, angle=(30, 60), up=0.25, gnarl=0.25, span=(0.1, 1.0), reach=0.6),
                dict(n=3.5, angle=(25, 50), up=0.35, gnarl=0.2, span=(0.2, 1.0), reach=0.55)],
        leaf=dict(clump=0.13, per_m=2.8), bark_w=0.4),
    "hawthorn": dict(
        habit="multistem", stems=(2, 3), stem_spread=(12, 28), trunk_r=0.034, lean=0.22, gnarl=0.2,
        flare=0.3, roots=0, crown=("round", 0.58, 0.18), wind=0.35,
        levels=[dict(n=2.2, angle=(40, 75), up=0.0, gnarl=0.35, span=(0.15, 0.95), reach=0.62),
                dict(n=3.6, angle=(35, 70), up=0.05, gnarl=0.35, span=(0.1, 1.0), reach=0.6),
                dict(n=4.0, angle=(30, 65), up=0.1, gnarl=0.3, span=(0.2, 1.0), reach=0.55)],
        leaf=dict(clump=0.12, per_m=3.2), bark_w=0.35),
    "yew": dict(
        habit="multistem", stems=(3, 5), stem_spread=(16, 34), trunk_r=0.060, lean=0.05, gnarl=0.06,
        flare=0.5, roots=3, crown=("cone_round", 0.46, 0.06),
        levels=[dict(n=2.6, angle=(50, 80), up=-0.05, gnarl=0.2, span=(0.1, 0.98), reach=0.7),
                dict(n=3.4, angle=(40, 70), up=0.0, gnarl=0.22, span=(0.1, 1.0), reach=0.6),
                dict(n=3.4, angle=(30, 60), up=0.05, gnarl=0.2, span=(0.2, 1.0), reach=0.55)],
        leaf=dict(clump=0.14, per_m=3.6), bark_w=0.4),
    "black_ash": dict(
        habit="excurrent", trunk_r=0.024, lean=0.05, gnarl=0.06, flare=0.4, roots=4,
        crown=("ovoid", 0.34, 0.42), leader_top=0.97,
        levels=[dict(n=2.0, angle=(45, 70), up=0.02, gnarl=0.18, span=(0.40, 0.92), reach=0.55),
                dict(n=1.6, angle=(30, 55), up=0.15, gnarl=0.2, span=(0.15, 1.0), reach=0.55),
                dict(n=2.2, angle=(25, 50), up=0.45, gnarl=0.18, span=(0.2, 1.0), reach=0.55)],
        leaf=dict(clump=0.075, per_m=1.4), bark_w=0.5),
    "hardy_pine": dict(
        habit="excurrent", trunk_r=0.026, lean=0.1, gnarl=0.08, flare=0.35, roots=3,
        crown=("umbrella", 0.46, 0.5), leader_top=0.9, wind=0.2,
        levels=[dict(n=3.0, angle=(62, 88), up=-0.02, gnarl=0.2, span=(0.5, 0.95), reach=0.6),
                dict(n=2.0, angle=(40, 70), up=0.2, gnarl=0.22, span=(0.2, 1.0), reach=0.5),
                dict(n=2.4, angle=(30, 55), up=0.3, gnarl=0.2, span=(0.25, 1.0), reach=0.5)],
        leaf=dict(clump=0.09, per_m=1.8), bark_w=0.45, needle=True),
    "rowan": dict(
        habit="multistem", stems=(2, 3), stem_spread=(10, 22), trunk_r=0.022, lean=0.06, gnarl=0.08,
        flare=0.25, roots=0, crown=("round", 0.5, 0.30),
        levels=[dict(n=1.6, angle=(28, 48), up=0.25, gnarl=0.18, span=(0.3, 0.95), reach=0.55),
                dict(n=2.6, angle=(30, 55), up=0.25, gnarl=0.2, span=(0.15, 1.0), reach=0.55),
                dict(n=3.0, angle=(25, 50), up=0.2, gnarl=0.2, span=(0.2, 1.0), reach=0.55)],
        leaf=dict(clump=0.11, per_m=2.4), bark_w=0.4),
    "juniper": dict(
        habit="multistem", stems=(4, 7), stem_spread=(18, 42), trunk_r=0.05, lean=0.1, gnarl=0.25,
        flare=0.2, roots=0, crown=("shrub", 0.55, 0.04), wind=0.25,
        levels=[dict(n=3.2, angle=(30, 60), up=0.15, gnarl=0.35, span=(0.1, 0.95), reach=0.6),
                dict(n=5.0, angle=(30, 60), up=0.15, gnarl=0.3, span=(0.1, 1.0), reach=0.55),
                dict(n=4.0, angle=(25, 55), up=0.15, gnarl=0.25, span=(0.2, 1.0), reach=0.5)],
        leaf=dict(clump=0.2, per_m=5.0), bark_w=0.25, needle=True),
    "willow": dict(
        habit="decurrent", forks=(3, 4), fork_at=(0.20, 0.28), trunk_r=0.055, lean=0.18, gnarl=0.1,
        flare=0.6, roots=5, crown=("dome", 0.72, 0.2), fork_angle=(30, 52), fork_up=0.12,
        levels=[dict(n=1.0, angle=(35, 60), up=0.0, gnarl=0.2, span=(0.2, 0.98), reach=0.62),
                dict(n=1.4, angle=(40, 70), up=-0.6, gnarl=0.1, span=(0.3, 1.0), reach=0.9, hang=True),
                dict(n=0.0, angle=(20, 40), up=-0.8, gnarl=0.1, span=(0.3, 1.0), reach=0.5, hang=True)],
        leaf=dict(clump=0.085, per_m=1.2), bark_w=0.55, weep=True),
    "alder": dict(
        habit="excurrent", trunk_r=0.024, lean=0.04, gnarl=0.05, flare=0.3, roots=3,
        crown=("cone_round", 0.30, 0.25), leader_top=0.98,
        levels=[dict(n=3.2, angle=(50, 75), up=0.05, gnarl=0.16, span=(0.25, 0.96), reach=0.5),
                dict(n=2.4, angle=(35, 60), up=0.12, gnarl=0.18, span=(0.15, 1.0), reach=0.55),
                dict(n=2.6, angle=(30, 55), up=0.15, gnarl=0.18, span=(0.2, 1.0), reach=0.5)],
        leaf=dict(clump=0.10, per_m=2.0), bark_w=0.45),
    "willow_pollard": dict(
        habit="pollard", trunk_r=0.06, lean=0.1, gnarl=0.1, flare=0.3, roots=0, head=(0.44, 0.56),
        rods=(16, 24), crown=("vase", 0.55, 0.45),
        levels=[dict(n=0.0, angle=(8, 35), up=0.35, gnarl=0.05, span=(0.9, 1.0), reach=1.0),
                dict(n=1.6, angle=(25, 45), up=0.1, gnarl=0.1, span=(0.3, 1.0), reach=0.3),
                dict(n=0.0, angle=(20, 40), up=0.1, gnarl=0.1, span=(0.3, 1.0), reach=0.4)],
        leaf=dict(clump=0.10, per_m=2.6), bark_w=0.4),
    "lime": dict(
        habit="excurrent", trunk_r=0.030, lean=0.03, gnarl=0.05, flare=0.55, roots=4,
        crown=("ovoid", 0.36, 0.26), leader_top=0.95,
        levels=[dict(n=2.6, angle=(40, 70), up=0.05, gnarl=0.15, span=(0.28, 0.94), reach=0.5, arch=0.35),
                dict(n=2.4, angle=(35, 60), up=0.05, gnarl=0.18, span=(0.15, 1.0), reach=0.55),
                dict(n=2.8, angle=(30, 55), up=0.1, gnarl=0.18, span=(0.2, 1.0), reach=0.55)],
        leaf=dict(clump=0.085, per_m=2.0), bark_w=0.5),
    "birch": dict(
        habit="excurrent", trunk_r=0.017, lean=0.08, gnarl=0.05, flare=0.25, roots=2,
        crown=("ovoid", 0.25, 0.35), leader_top=0.97,
        levels=[dict(n=2.4, angle=(35, 60), up=0.15, gnarl=0.14, span=(0.35, 0.95), reach=0.45),
                dict(n=2.6, angle=(35, 60), up=-0.25, gnarl=0.15, span=(0.2, 1.0), reach=0.6),
                dict(n=2.6, angle=(20, 45), up=-0.6, gnarl=0.1, span=(0.25, 1.0), reach=0.6)],
        leaf=dict(clump=0.075, per_m=1.8), bark_w=0.4),
    "hazel": dict(
        habit="multistem", stems=(5, 8), stem_spread=(10, 28), trunk_r=0.03, lean=0.05, gnarl=0.04,
        flare=0.15, roots=0, crown=("round", 0.5, 0.12),
        levels=[dict(n=1.6, angle=(30, 55), up=0.1, gnarl=0.12, span=(0.35, 0.95), reach=0.5),
                dict(n=2.6, angle=(35, 60), up=0.05, gnarl=0.15, span=(0.2, 1.0), reach=0.55),
                dict(n=0.0, angle=(25, 50), up=0.05, gnarl=0.15, span=(0.2, 1.0), reach=0.5)],
        leaf=dict(clump=0.13, per_m=3.0), bark_w=0.3),
    "dead_ash_tree": dict(
        habit="excurrent", trunk_r=0.030, lean=0.12, gnarl=0.1, flare=0.4, roots=3,
        crown=("ovoid", 0.34, 0.35), leader_top=0.8,
        levels=[dict(n=0.9, angle=(25, 50), up=0.2, gnarl=0.25, span=(0.4, 0.95), reach=0.55),
                dict(n=1.4, angle=(25, 50), up=0.2, gnarl=0.3, span=(0.2, 1.0), reach=0.6),
                dict(n=1.8, angle=(22, 48), up=0.1, gnarl=0.3, span=(0.25, 1.0), reach=0.55)],
        leaf=None, bark_w=0.5),
    "char_stump": dict(
        habit="stump", trunk_r=0.16, lean=0.05, gnarl=0.1, flare=0.45, roots=5,
        crown=("round", 0.4, 0.0),
        levels=[dict(n=1.2, angle=(25, 55), up=0.3, gnarl=0.25, span=(0.55, 0.95), reach=0.35),
                dict(n=0.0, angle=(20, 40), up=0.1, gnarl=0.2, span=(0.3, 1.0), reach=0.5),
                dict(n=0.0, angle=(20, 40), up=0.1, gnarl=0.2, span=(0.3, 1.0), reach=0.5)],
        leaf=None, bark_w=0.4),
}

# How an age changes a form: a sapling is a slim young tree whose crown starts low and whose leader
# still wins; a veteran is squat for its height, thick in the trunk, broken and gnarled, its crown
# wide and uneven. (Scale on the height range, on the trunk radius, on the crown width, and on the
# kink per segment.)
AGES = {
    "sapling": dict(height=0.38, trunk_r=0.62, width=0.8, gnarl=0.6, base=0.45, drop_level=2),
    "mature": dict(height=1.0, trunk_r=1.0, width=1.0, gnarl=1.0, base=1.0),
    "veteran": dict(height=0.92, trunk_r=1.45, width=1.18, gnarl=1.6, base=0.8, broken=0.3),
}


## Segments along a tube, by level (min, max): the trunk is drawn round and smooth, a twig is two
## segments. Rings are where a budget goes, so they are spent where the eye is.
RINGS = ((4, 12), (3, 5), (2, 4), (2, 2))


@dataclass
class Branch:
    pts: np.ndarray            # (k, 3) points along the axis, base first
    radii: np.ndarray          # (k,) radius at each point; the last is the tip (0 for a point)
    level: int                 # 0 trunk / stem, 1 limb, 2 branch, 3 twig; roots are level 1
    parent: int = -1
    importance: float = 0.0    # what trimming spends last (length x girth, capped by the parent's)
    root: bool = False
    hang: bool = False
    children: list = field(default_factory=list)
    # a buttress's section is taller than it is wide: its height over its width at each point
    # (None: round). `radii` is then the half-width, and the ring's side axis is kept level.
    tall: np.ndarray = None

    @property
    def length(self) -> float:
        return float(np.linalg.norm(np.diff(self.pts, axis=0), axis=1).sum())


@dataclass
class Tree:
    kind: str
    height: float
    branches: list
    crown: tuple               # (shape, radius, z0, z1, centre xy)
    seed: int = 0
    root_feet: list = None     # (bearing, the trunk's ground radius, the root's height there) per root


# --- small vector helpers -----------------------------------------------------------------------

def _unit(v):
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else np.array([0.0, 0.0, 1.0])


def _perp(d):
    a = np.array([0.0, 0.0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    return _unit(np.cross(d, a))


def _rotate(v, axis, angle):
    axis = _unit(axis)
    c, s = math.cos(angle), math.sin(angle)
    return v * c + np.cross(axis, v) * s + axis * np.dot(axis, v) * (1 - c)


def envelope(shape: str, p: float) -> float:
    """The crown's radius at relative height p (0 = crown base, 1 = top), as a share of its widest."""
    p = min(max(p, 0.0), 1.0)
    if shape == "dome":            # oak: broad from low down, rounded over the top
        return math.sin(math.pi * (0.22 + 0.78 * p)) ** 0.55 if p < 1 else 0.0
    if shape == "round":           # apple, hawthorn: a ball
        return math.sin(math.pi * (0.08 + 0.92 * p)) ** 0.7
    if shape == "ovoid":           # lime, ash: tall, widest below the middle
        return math.sin(math.pi * p ** 0.85) ** 0.75
    if shape == "cone_round":      # yew, alder: a cone with a blunt top and full skirt
        return (1.0 - p ** 1.35) ** 0.9 * (0.75 + 0.25 * min(1.0, p * 6))
    if shape == "umbrella":        # pine: bare below, a flat-topped spread above
        return (0.35 + 0.65 * min(1.0, p / 0.55)) * (1.0 - p ** 5) ** 0.5
    if shape == "vase":            # rowan, pollard: narrow foot, spreading head
        return (0.3 + 0.7 * p ** 0.6) * (1.0 - p ** 6) ** 0.5
    if shape == "shrub":           # juniper: low and ragged
        return math.sin(math.pi * (0.12 + 0.88 * p)) ** 0.45
    return 1.0


# --- growing ------------------------------------------------------------------------------------

class _Grower:
    def __init__(self, kind: str, form: dict, rng: np.random.Generator, height: float, age: str):
        self.kind, self.f, self.rng, self.h = kind, form, rng, height
        self.age = AGES.get(age, AGES["mature"])
        self.branches: list[Branch] = []
        shape, width, base = form["crown"]
        self.shape = shape
        self.R = width * height * self.age["width"]
        self.z0 = height * min(0.9, base * self.age["base"]) if age != "sapling" else height * base * 0.45
        self.z1 = height
        self.cxy = np.zeros(2)
        self.seg = max(0.25, height / 22.0)
        self.gnarl_k = form.get("gnarl", 0.1) * self.age["gnarl"]
        wind = form.get("wind", 0.0)
        a = rng.uniform(0, 2 * math.pi)
        self.wind = np.array([math.cos(a), math.sin(a), 0.0]) * wind

    # the envelope, measured from the crown's axis
    def allowed(self, z: float) -> float:
        if z < self.z0 * 0.6:
            return self.R * 0.35
        p = (z - self.z0) / max(self.z1 - self.z0, 1e-3)
        if p > 1.0:
            return 0.0
        return self.R * max(envelope(self.shape, p), 0.0 if p > 0.98 else 0.08)

    def inside(self, pt) -> bool:
        r = float(np.hypot(pt[0] - self.cxy[0], pt[1] - self.cxy[1]))
        return pt[2] <= self.z1 * 1.02 and r <= self.allowed(pt[2]) * 1.02

    def fit_length(self, base, d, length) -> float:
        """Shorten a straight shoot from `base` along `d` until its tip is inside the crown."""
        if self.inside(base + d * length):
            return length
        lo, hi = 0.0, length
        for _ in range(10):
            mid = (lo + hi) * 0.5
            if self.inside(base + d * mid):
                lo = mid
            else:
                hi = mid
        return lo

    def stem(self, base, d, length, r0, level, up=0.0, gnarl=0.1, taper=1.0, hang=False,
             arch=0.0, tip=0.0, seg=None):
        """Grow one tube's axis: returns (pts, radii)."""
        rng = self.rng
        seg = seg or self.seg * (1.0 if level == 0 else 0.8 if level == 1 else 0.65 if level == 2 else 0.55)
        lo, hi = RINGS[min(level, 3)]
        n = min(hi, max(lo, int(math.ceil(length / seg))))
        step = length / n
        pts = [np.array(base, dtype=float)]
        d = _unit(np.array(d, dtype=float))
        bend_axis = _perp(d)
        for i in range(n):
            t = (i + 0.5) / n
            kink = rng.normal(0, gnarl, 3)
            d = d + kink
            # tropism: toward the sky (+) or hanging (-), growing with distance along the shoot
            d = d + np.array([0.0, 0.0, up * (0.35 + t)]) * (0.55 if not hang else 1.0)
            if arch:
                # arching limbs (lime's lower boughs): rise, then bow outward and down
                d = d + np.array([0.0, 0.0, -arch * t * t])
            if self.wind is not None and level <= 1:
                d = d + self.wind * 0.25 * t
            if hang and d[2] > -0.2 and t > 0.35:
                d[2] -= 0.35
            d = _unit(d)
            pts.append(pts[-1] + d * step)
        pts = np.array(pts)
        s = np.linspace(0.0, 1.0, len(pts))
        radii = r0 * (1.0 - s * (1.0 - tip)) ** (0.6 * taper + 0.4)
        radii[-1] = r0 * tip
        return pts, radii

    def add(self, pts, radii, level, parent, importance, root=False, hang=False, tall=None) -> int:
        b = Branch(pts=pts, radii=radii, level=level, parent=parent, importance=importance, root=root, hang=hang,
                   tall=tall)
        self.branches.append(b)
        i = len(self.branches) - 1
        if parent >= 0:
            self.branches[parent].children.append(i)
        return i

    # the parts of the tree ----------------------------------------------------------------------

    def trunk_radius(self) -> float:
        return self.h * self.f["trunk_r"] * self.age["trunk_r"]

    def trunk_flare(self) -> float:
        """How far the trunk's own foot swells (a share of its radius). A tree with buttress roots
        takes half of it from the trunk and the rest from the buttresses, whose ridges and hollows
        make an old tree's foot: the whole flare on a round trunk read as a smooth bell."""
        f = self.f.get("flare", 0.3) * (1.4 if self.age is AGES["veteran"] else 1.0)
        rooted = int(self.f.get("roots", 0)) > 0 and self.age is not AGES["sapling"]
        return f * (0.5 if rooted else 1.0)

    def flare(self, pts, radii, r0):
        f = self.trunk_flare()
        z = pts[:, 2]
        radii *= 1.0 + f * np.exp(-np.maximum(z, 0.0) / max(r0 * 1.6, 0.05))
        return radii

    def grow_trunk(self):
        f, rng, h = self.f, self.rng, self.h
        r0 = self.trunk_radius()
        habit = f["habit"]
        lean = np.array([rng.normal(0, f.get("lean", 0.05)), rng.normal(0, f.get("lean", 0.05)), 1.0])
        if habit == "excurrent":
            top = h * f.get("leader_top", 0.95)
            pts, radii = self.stem(np.array([0.0, 0.0, -0.25]), lean, top + 0.25, r0, 0, up=0.3,
                                   gnarl=self.gnarl_k * 0.35, taper=1.3, tip=0.0)
            radii = self.flare(pts, radii, r0)
            ti = self.add(pts, radii, 0, -1, 1e9)
            self.cxy = pts[-1, :2] * 0.7
            self.limbs_on(ti, 0)
        elif habit == "decurrent":
            fork = h * rng.uniform(*f["fork_at"])
            # the trunk runs on through the fork as one of the co-dominant stems, bending away
            # from the others: a fork is a branch leaving a trunk, never a trunk that stops
            k = int(rng.integers(f["forks"][0], f["forks"][1] + 1))
            phase = rng.uniform(0, 2 * math.pi)
            tilt0 = math.radians(rng.uniform(*f["fork_angle"])) * 0.6
            lead = np.array([math.cos(phase) * math.sin(tilt0), math.sin(phase) * math.sin(tilt0), math.cos(tilt0)])
            n1 = max(3, int(math.ceil((fork + 0.25) / self.seg)))
            lower, lr = self.stem(np.array([0.0, 0.0, -0.25]), lean, fork + 0.25, r0, 0, up=0.2,
                                  gnarl=self.gnarl_k * 0.5, taper=0.0, tip=0.72)
            upper_len = max(h * 0.3, (h - fork) * rng.uniform(0.75, 0.95))
            upper_len = max(upper_len * 0.5, self.fit_length(lower[-1], lead, upper_len))
            upper, ur = self.stem(lower[-1], lead, upper_len, lr[-1], 0, up=f.get("fork_up", 0.05),
                                  gnarl=self.gnarl_k, taper=1.0, tip=0.0)
            pts = np.vstack([lower, upper[1:]])
            radii = np.r_[lr, ur[1:]]
            radii = self.flare(pts, radii, r0)
            ti = self.add(pts, radii, 0, -1, 1e9)
            self.cxy = lower[-1, :2]
            top = lower[-1]
            ax = _unit(lower[-1] - lower[-2])
            radii_top = lr[-1]
            for j in range(1, k):
                a = phase + 2 * math.pi * j / k + rng.normal(0, 0.3)
                tilt = math.radians(rng.uniform(*f["fork_angle"]))
                side = _rotate(_perp(ax), ax, a)
                d = _unit(ax * math.cos(tilt) + side * math.sin(tilt))
                length = (h - fork) * rng.uniform(0.7, 0.95)
                length = max(length * 0.4, self.fit_length(top, d, length))
                rc = radii_top * rng.uniform(0.62, 0.82)
                cp, cr = self.stem(top - ax * radii_top * 1.2, d, length, rc, 0, up=f.get("fork_up", 0.05),
                                   gnarl=self.gnarl_k, taper=1.0, tip=0.0)
                ci = self.add(cp, cr, 0, ti, 1e8)
                self.limbs_on(ci, 0)
            self.limbs_on(ti, 0)
        elif habit in ("multistem",):
            k = int(rng.integers(f["stems"][0], f["stems"][1] + 1))
            if self.age is AGES["sapling"]:
                k = 1
            phase = rng.uniform(0, 2 * math.pi)
            for j in range(k):
                a = phase + 2 * math.pi * j / k + rng.normal(0, 0.4)
                tilt = math.radians(rng.uniform(*f["stem_spread"])) if k > 1 else math.radians(rng.uniform(0, 6))
                d = _unit(np.array([math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)])
                          + lean * np.array([1, 1, 0]))
                rs = r0 * (1.0 if j == 0 else rng.uniform(0.6, 0.85)) / math.sqrt(max(1.0, k * 0.55))
                # a stem stops inside the crown and its side shoots, fitted to the envelope, make the
                # top: a stem run out to the full height stood above the leaves as a bare spike
                length = h * (0.8 if j == 0 else rng.uniform(0.6, 0.78))
                base = np.array([math.cos(a), math.sin(a), 0.0]) * r0 * 0.35 + np.array([0, 0, -0.2])
                pts, radii = self.stem(base, d, length, rs, 0, up=0.25, gnarl=self.gnarl_k * 0.6,
                                       taper=1.1, tip=0.0)
                radii = self.flare(pts, radii, rs)
                ti = self.add(pts, radii, 0, -1, 1e9 - j)
                self.limbs_on(ti, 0)
        elif habit == "pollard":
            head = h * rng.uniform(*f["head"])
            pts, radii = self.stem(np.array([0.0, 0.0, -0.25]), lean, head + 0.25, r0, 0, up=0.2,
                                   gnarl=self.gnarl_k * 0.5, taper=0.0, tip=0.85)
            radii = self.flare(pts, radii, r0)
            # the knuckle: the trunk swells where it has been cut back, year after year, and
            # closes over in a rounded boss the rods break out of
            radii[-4:-1] *= np.array([1.12, 1.28, 1.2])
            head_top = pts[-1] + _unit(pts[-1] - pts[-2]) * radii[-2] * 0.9
            pts = np.vstack([pts, head_top])
            radii = np.r_[radii[:-1], radii[-2] * 0.75, 0.0]
            ti = self.add(pts, radii, 0, -1, 1e9)
            top = pts[-2]
            self.cxy = top[:2]
            k = int(rng.integers(*f["rods"]))
            lv = f["levels"][0]
            for j in range(k):
                a = 2 * math.pi * j / k + rng.normal(0, 0.25)
                tilt = math.radians(rng.uniform(*lv["angle"]))
                d = np.array([math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)])
                base = top + np.array([math.cos(a), math.sin(a), 0]) * radii[-3] * 0.55
                length = (h - head) * rng.uniform(0.6, 1.0)
                rc = radii[-3] * rng.uniform(0.09, 0.15)
                cp, cr = self.stem(base, d, length, rc, 1, up=lv["up"], gnarl=lv["gnarl"], taper=1.0, tip=0.0)
                ci = self.add(cp, cr, 1, ti, length * rc)
                self.shoots_on(ci, 2)
        elif habit == "stump":
            top = h
            pts, radii = self.stem(np.array([0.0, 0.0, -0.2]), lean, top + 0.2, r0, 0, up=0.1,
                                   gnarl=self.gnarl_k * 0.8, taper=0.1, tip=0.55)
            radii = self.flare(pts, radii, r0)
            ti = self.add(pts, radii, 0, -1, 1e9)
            # the broken top: a few charred spikes where the trunk snapped
            for j in range(int(rng.integers(3, 6))):
                a = rng.uniform(0, 2 * math.pi)
                d = _unit(np.array([math.cos(a) * 0.3, math.sin(a) * 0.3, 1.0]))
                base = pts[-1] + np.array([math.cos(a), math.sin(a), 0.0]) * radii[-1] * 0.45 - np.array([0, 0, 0.1])
                cp, cr = self.stem(base, d, rng.uniform(0.15, 0.6) * h * 0.4 + 0.1, radii[-1] * rng.uniform(0.3, 0.5),
                                   2, up=0.3, gnarl=0.2, tip=0.0)
                self.add(cp, cr, 2, ti, 1e6)
            self.limbs_on(ti, 0)
        self.grow_roots(r0)

    def grow_roots(self, r0):
        """The foot of an old tree: buttresses thick where they leave the trunk, curving down into
        the soil within a few trunk-radii, and the odd long surface root snaking out low and half
        buried. They vary: thickness, reach and spacing, a knuckle here, a split there, a gap where
        one has rotted away.

        A buttress's round section follows its top line: its radius is half the top's height, so
        it sits on the ground from the trunk out, as wide as it is tall, until the top line dives
        and the root goes under. (Roots were long, thin, evenly tapered spikes radiating over the
        surface -- spider legs, playtest 6 -- and before that tubes half underground that lifted
        the whole tree onto their tips.) `root_feet` keeps where each meets the trunk, for the
        forge's moss and litter."""
        n = int(self.f.get("roots", 0))
        if self.age is AGES["sapling"]:
            n = 0
        self.root_feet = []
        if n <= 0 or not self.branches:
            return
        rng = self.rng
        trunk = 0
        old = 1.35 if self.age is AGES["veteran"] else 1.0
        r_ground = r0 * (1.0 + self.trunk_flare())
        phase = rng.uniform(0, 2 * math.pi)
        slots = [phase + 2 * math.pi * (j + rng.uniform(-0.28, 0.28)) / n for j in range(n)]
        # a gap where one rotted away (an old tree more often)
        if n >= 4 and rng.random() < 0.25 * old:
            slots.pop(int(rng.integers(len(slots))))
        surface = set(rng.choice(len(slots), size=min(len(slots), int(rng.integers(1, 3))), replace=False).tolist())
        for j, a in enumerate(slots):
            if j in surface:
                self._surface_root(trunk, a, r0, r_ground)
            else:
                self._buttress(trunk, a, r0, r_ground, old)

    def _root_path(self, a: float, start: float, reach: float, k: int, wander: float):
        """Points out from the trunk's axis at bearing `a`: horizontal (x, y) at t = 0..1, and the
        distance of each from the trunk's ground-level surface (0 at the surface)."""
        rng = self.rng
        out = np.array([math.cos(a), math.sin(a), 0.0])
        side = np.array([-out[1], out[0], 0.0])
        t = np.linspace(0.0, 1.0, k)
        swing = np.cumsum(rng.normal(0, wander, k)) * t
        d = start + reach * t
        return out[None, :] * d[:, None] + side[None, :] * swing[:, None], t

    def _buttress(self, trunk: int, a: float, r0: float, r_ground: float, old: float, depth: int = 0):
        rng = self.rng
        # reach past the trunk's foot: 1-2 trunk radii (1.5-3 m on a giant oak)
        reach = r0 * rng.uniform(1.0, 2.0) * (0.6 if depth else 1.0)
        top0 = r0 * rng.uniform(1.0, 1.7) * old * (0.55 if depth else 1.0)
        start = 0.0            # from the trunk's axis (or the parent root's), inside the wood
        span = (r_ground - start) + reach
        k = 12
        xy, t = self._root_path(a, start, span, k, 0.05 * r0)
        # the top line: steep off the trunk, easing over, then down into the soil
        dist = np.linalg.norm(xy[:, :2], axis=1)
        u = np.clip((dist - r_ground) / reach, 0.0, 1.0) if not depth else t
        top = top0 * (1.0 - u) ** 1.8 - 0.2 * top0 * u ** 3
        if not depth:
            # inside the trunk's foot it keeps rising into the wood, so it flares in with no seam
            top = np.where(dist < r_ground, top0 * (1.0 + 0.5 * (r_ground - dist) / max(r_ground, 1e-3)), top)
        hh = np.maximum(top, 0.0) * 0.5                 # half the height: the section sits on the ground
        # a plank at the trunk (2.4 times as tall as wide), rounding off to a round root as it dives
        tall = 1.0 + 1.4 * np.clip(1.0 - u, 0.0, 1.0) ** 0.7
        radii = np.maximum(hh / tall, r0 * 0.05 * (1.0 - t))
        # a knuckle, now and then: a smooth swelling over a few rings
        if rng.random() < 0.45:
            c = rng.uniform(0.3, 0.65)
            bump = 1.0 + rng.uniform(0.15, 0.3) * np.exp(-((t - c) / 0.08) ** 2)
            radii = radii * bump
        radii[-1] = 0.0
        z = np.where(top > 0.0, hh * 1.0, top) - np.where(top > 0.0, 0.0, radii * tall)
        pts = np.column_stack([xy[:, :2], z])
        if depth:
            # it leaves its parent from the parent's own axis, easing down to its own line
            base = self._split_from
            pts = pts + np.array([base[0], base[1], 0.0])
            pts[:, 2] += (base[2] - pts[0, 2]) * (1.0 - t) ** 2
        bi = self.add(pts, radii, 1, trunk, 1e7 - depth, root=True, tall=tall)
        if not depth:
            self.root_feet.append((float(a), float(r_ground), float(top0)))
            # a split: a second buttress leaving this one's flank
            if rng.random() < 0.3 * old:
                kk = int(k * rng.uniform(0.25, 0.4))
                self._split_from = pts[kk].copy()
                self._buttress(bi, a + rng.choice([-1.0, 1.0]) * rng.uniform(0.45, 0.8), r0, 0.0, old, depth=1)

    def _surface_root(self, trunk: int, a: float, r0: float, r_ground: float):
        """A long root snaking over the ground, low and rounded, more under the soil than over it."""
        rng = self.rng
        reach = r0 * rng.uniform(3.0, 5.5)
        k = 16
        xy, t = self._root_path(a, 0.0, r_ground + reach, k, 0.22 * r0)
        rb = r0 * rng.uniform(0.2, 0.3)
        radii = rb * (1.0 - t) ** 0.8 + r0 * 0.03
        radii[-1] = 0.0
        # at the trunk it rises into the flare; out along the ground the soil covers half of it or more
        lift = r0 * 0.5 * (1.0 - np.clip(t * 4.0, 0.0, 1.0)) ** 2
        z = radii * rng.uniform(-0.35, 0.05) + lift + rng.normal(0, 0.05 * r0, k) * t - 0.25 * rb * t ** 4
        # its last stretch goes under: the end is in the soil, never lifted out of it
        z = z - np.clip((t - 0.8) / 0.2, 0.0, 1.0) ** 1.5 * (radii + rb * 0.6)
        pts = np.column_stack([xy[:, :2], z])
        self.add(pts, radii, 1, trunk, 1e7 - 1, root=True)
        self.root_feet.append((float(a), float(r_ground), float(rb)))

    def limbs_on(self, bi: int, level: int):
        """Grow the next level's branches along branch `bi` (at `level`), then recurse."""
        lv_i = level  # index into levels: children of a level-0 stem use levels[0]
        levels = self.f["levels"]
        if lv_i >= len(levels):
            return
        lv = levels[lv_i]
        if lv.get("n", 0) <= 0:
            return
        drop = self.age.get("drop_level")
        if drop is not None and level + 1 > drop + 1:
            return
        rng = self.rng
        b = self.branches[bi]
        pts, radii = b.pts, b.radii
        seglen = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        cum = np.r_[0.0, np.cumsum(seglen)]
        L = float(cum[-1])
        if L < 1e-3:
            return
        s0, s1 = lv["span"]
        if level == 0 and b.parent < 0:
            # no limbs below the crown on a trunk: find where the bole ends along it
            zb = self.z0 * 0.85
            above = np.nonzero(pts[:, 2] >= zb)[0]
            if len(above):
                s0 = max(s0, cum[above[0]] / L)
        span_len = L * max(0.0, s1 - s0)
        count = int(round(lv["n"] * span_len * (10.0 / max(self.h, 3.0)) ** 0.35 * rng.uniform(0.85, 1.15)))
        if level >= 1:
            count = max(count, 1 if span_len > 0.2 else 0)
        if count <= 0:
            return
        us = np.sort(rng.uniform(s0, s1, count))
        # even out the spacing a little so shoots do not bunch
        us = 0.5 * us + 0.5 * np.linspace(s0, s1, count + 2)[1:-1]
        phyl = rng.uniform(0, 2 * math.pi)
        broken = self.age.get("broken", 0.0)
        for k, u in enumerate(us):
            at = u * L
            i = int(np.searchsorted(cum, at) - 1)
            i = min(max(i, 0), len(pts) - 2)
            w = (at - cum[i]) / max(seglen[i], 1e-9)
            here = pts[i] * (1 - w) + pts[i + 1] * w
            r_here = radii[i] * (1 - w) + radii[i + 1] * w
            ax = _unit(pts[i + 1] - pts[i])
            phyl += math.radians(137.5) + rng.normal(0, 0.35)
            side = _rotate(_perp(ax), ax, phyl)
            if level == 0 and self.f["habit"] == "decurrent":
                # limbs on the co-dominant stems face outward, away from the crown's axis
                outward = here.copy()
                outward[2] = 0.0
                outward[:2] -= self.cxy
                if np.linalg.norm(outward) > 1e-3:
                    side = _unit(side + _unit(outward) * 1.2)
            tilt = math.radians(rng.uniform(*lv["angle"]))
            d = _unit(ax * math.cos(tilt) + side * math.sin(tilt))
            remain = L - at
            length = remain * lv["reach"] * rng.uniform(0.75, 1.2)
            if level == 0:
                # limbs off a trunk or leader: sized to reach the crown's edge at their height
                z = here[2]
                edge = self.allowed(z + length * d[2] * 0.5)
                length = max(length, edge * rng.uniform(0.8, 1.1) / max(0.35, math.sqrt(max(1e-3, 1 - d[2] ** 2))))
            if not lv.get("hang"):
                length = self.fit_length(here, d, length)
            if length < self.seg * 0.5:
                continue
            if broken and level == 0 and rng.random() < broken:
                length *= rng.uniform(0.35, 0.6)       # a limb lost in a storm, long ago
            rc = r_here * float(np.clip((length / max(remain, 1e-3)) ** 0.7, 0.22, 0.78))
            rc = max(rc, self.h * 0.0022)
            rc = min(rc, r_here * 0.85)
            cp, cr = self.stem(here, d, length, rc, level + 1, up=lv["up"], gnarl=lv["gnarl"] * self.age["gnarl"],
                               taper=1.0, hang=bool(lv.get("hang")), arch=lv.get("arch", 0.0), tip=0.0)
            ci = self.add(cp, cr, level + 1, bi, min(length * rc, b.importance), hang=bool(lv.get("hang")))
            if level + 1 < 3:
                self.limbs_on(ci, level + 1)

    def shoots_on(self, bi: int, level: int):
        """Short side shoots on a pollard's rods (the rods are level 1)."""
        self.limbs_on(bi, level - 1)


def grow(kind: str, seed: int, height: float, age: str = "mature") -> Tree:
    form = FORMS[kind]
    rng = np.random.default_rng(seed)
    g = _Grower(kind, form, rng, height, age)
    g.grow_trunk()
    t = Tree(kind=kind, height=height, branches=g.branches,
             crown=(g.shape, g.R, g.z0, g.z1, tuple(g.cxy)), seed=seed)
    t.root_feet = list(getattr(g, "root_feet", []))
    return t


# --- trimming to a budget -------------------------------------------------------------------------

SIDES = {"normal": (8, 5, 4, 3), "hero": (10, 6, 5, 3), "lod1": (6, 4, 3, 3), "small": (7, 5, 4, 3)}


def sides_for(b: Branch, table) -> int:
    if b.root:
        # a buttress's plank needs more sides than a round limb, or its crest is a hard crease
        return max(table[0] - 2, 5)
    return table[min(b.level, len(table) - 1)]


def tube_tris(n_pts: int, sides: int) -> int:
    """Triangles in a tube of n_pts rings closed to a point at its tip."""
    return 2 * sides * max(0, n_pts - 2) + sides


def _ring_keep(n: int, stride: int) -> np.ndarray:
    if stride <= 1 or n <= 3:
        return np.arange(n)
    return np.unique(np.r_[np.arange(0, n - 1, stride), n - 1])


def _straight(b: Branch, stride: int, tol: float = 0.08) -> bool:
    """Whether dropping every `stride`-th ring moves no point of the axis more than `tol` metres
    off the chord that replaces it (a coppice rod, a young stem)."""
    keep = _ring_keep(len(b.pts), stride)
    for a, c in zip(keep[:-1], keep[1:]):
        p0, p1 = b.pts[a], b.pts[c]
        ab = p1 - p0
        L2 = float(np.dot(ab, ab)) or 1e-12
        for i in range(a + 1, c):
            t = float(np.clip(np.dot(b.pts[i] - p0, ab) / L2, 0.0, 1.0))
            if float(np.linalg.norm(p0 + ab * t - b.pts[i])) > tol:
                return False
    return True


def _stride(b: Branch, stride: int, loose: bool = False) -> int:
    """Rings skipped at a coarse level: never on the trunk and the limbs, whose kinks and flare are
    the silhouette (a limb of a giant oak drawn every other ring cuts a kink by a metre, and
    lod_repair then cuts the triangles out); only on branches and twigs. `loose` also strides a
    trunk or limb that is straight enough for it to cost nothing (see trim's fallback)."""
    if b.level >= 2:
        return stride
    return stride if (loose and stride > 1 and _straight(b, stride)) else 1


def drop_order(branches: list) -> list:
    """Branch indices in the order a budget gives them up: the finest level first, the least
    important of that level before the rest, so a trimmed tree is thinned evenly all round rather
    than stripped on one side; a branch never goes before a finer branch growing from it."""
    return sorted(range(len(branches)), key=lambda i: (-branches[i].level if not branches[i].root else -1,
                                                        branches[i].importance, -i))


def trim(branches: list, budget: int, table=SIDES["normal"], stride: int = 1, loose: bool = False) -> list:
    """The indices of the branches kept under `budget` triangles. Whole twigs are dropped, finest
    and least important first, a branch only after everything growing from it; wood is never cut."""
    cost = [tube_tris(len(_ring_keep(len(b.pts), _stride(b, stride, loose))), sides_for(b, table)) for b in branches]
    total = sum(cost)
    alive = [True] * len(branches)
    for i in drop_order(branches):
        if total <= budget:
            break
        if branches[i].level == 0 and branches[i].parent < 0:
            continue                          # never the trunk itself
        alive[i] = False
        total -= cost[i]
    # a branch whose parent was dropped goes too (drop_order makes that rare; this makes it certain)
    for i, b in enumerate(branches):
        if b.parent >= 0 and not alive[b.parent]:
            alive[i] = False
    return [i for i in range(len(branches)) if alive[i]]


# --- the mesh -------------------------------------------------------------------------------------

def tube(b: Branch, sides: int, bark_w: float, stride: int = 1, twist: float = 0.0):
    """Vertices, normals, UVs and triangles of a tapered tube closed to a point at its tip.

    UVs: u runs once round the wood `wraps` times the bark's width (an integer, so the seam
    matches), v runs along it in bark-widths, so a tiling bark has one scale on every limb."""
    keep = _ring_keep(len(b.pts), stride)
    pts, radii = b.pts[keep], b.radii[keep]
    tall = b.tall[keep] if b.tall is not None else None
    k = len(pts)
    V, N, UV, T = [], [], [], []
    d0 = _unit(pts[1] - pts[0])
    n0 = _perp(d0)
    # round the section's real girth: a buttress's plank is `tall` times its half-width high, and
    # wrapped by its half-width alone its bark was stretched into zigzag bands up the plank
    h0 = float(tall[0]) if tall is not None else 1.0
    girth = 2 * math.pi * float(radii[0]) * math.sqrt((1.0 + h0 * h0) / 2.0)
    wraps = max(1, int(round(girth / bark_w)))
    along = 0.0
    for i in range(k - 1):
        d = _unit(pts[min(i + 1, k - 1)] - pts[max(i - 1, 0)])
        if tall is not None:
            # the side axis level, the other as near up as the axis allows
            lv = np.cross(np.array([0.0, 0.0, 1.0]), d)
            n0 = _unit(lv) if np.linalg.norm(lv) > 1e-4 else _unit(n0 - d * np.dot(n0, d))
        else:
            n0 = _unit(n0 - d * np.dot(n0, d))
        bn = np.cross(d, n0)
        if bn[2] < 0.0 and tall is not None:
            bn = -bn
        h = float(tall[i]) if tall is not None else 1.0
        if i > 0:
            along += float(np.linalg.norm(pts[i] - pts[i - 1]))
        for j in range(sides + 1):
            a = 2 * math.pi * j / sides + twist * along
            rad = math.cos(a) * n0 + math.sin(a) * bn * h
            V.append(pts[i] + rad * radii[i])
            nrm = math.cos(a) * n0 + math.sin(a) * bn / h
            # lean the normal along the taper so a cone shades as a cone
            N.append(_unit(_unit(nrm) + d * max(0.0, (radii[i] - radii[i + 1])) / max(1e-4, np.linalg.norm(pts[i + 1] - pts[i]))))
            UV.append((j / sides * wraps, along / (bark_w * 2.0)))
    along += float(np.linalg.norm(pts[-1] - pts[-2]))
    apex = len(V)
    V.append(pts[-1])
    N.append(_unit(pts[-1] - pts[-2]))
    UV.append((0.5 * wraps, along / (bark_w * 2.0)))
    for i in range(k - 2):
        for j in range(sides):
            a = i * (sides + 1) + j
            c = a + sides + 1
            T += [(a, a + 1, c), (a + 1, c + 1, c)]
    last = (k - 2) * (sides + 1)
    for j in range(sides):
        T.append((last + j, last + j + 1, apex))
    return (np.array(V, dtype=np.float32), np.array(N, dtype=np.float32),
            np.array(UV, dtype=np.float32), np.array(T, dtype=np.int64))


def wood_mesh(tree: Tree, keep: list, table=SIDES["normal"], bark_w: float = 0.5, stride: int = 1,
              loose: bool = False):
    """One mesh of the kept branches: (V, N, UV, T, rank) where rank is each triangle's branch."""
    Vs, Ns, UVs, Ts, R = [], [], [], [], []
    off = 0
    for bi in keep:
        b = tree.branches[bi]
        v, n, uv, t = tube(b, sides_for(b, table), bark_w, stride=_stride(b, stride, loose))
        Vs.append(v)
        Ns.append(n)
        UVs.append(uv)
        Ts.append(t + off)
        R.append(np.full(len(t), bi, dtype=np.int64))
        off += len(v)
    return (np.concatenate(Vs), np.concatenate(Ns), np.concatenate(UVs), np.concatenate(Ts), np.concatenate(R))


# --- leaves ---------------------------------------------------------------------------------------

def leaf_points(tree: Tree, keep: list, form: dict, rng: np.random.Generator, target: int):
    """Where the leaf clumps sit: spread along the finest kept twigs, and one at every kept tip.

    `target` clumps are shared out along the carriers by length, so a tree trimmed of half its
    twigs keeps its leaf mass on the twigs it still has instead of losing half its crown.
    Returns (positions (n,3), axis (n,3), size (n,), exposure (n,)): exposure is 0 deep inside
    and low in the crown, 1 at its sunlit top and rim."""
    leaf = form.get("leaf")
    empty = (np.zeros((0, 3)), np.zeros((0, 3)), np.zeros(0), np.zeros(0))
    if not leaf or target <= 0:
        return empty
    h = tree.height
    shape, R, z0, z1, cxy = tree.crown
    kept = set(keep)
    finest = max((tree.branches[i].level for i in keep if not tree.branches[i].root), default=0)
    carriers = []          # (branch, start fraction, weight)
    tips = []
    for bi in keep:
        b = tree.branches[bi]
        if b.root:
            continue
        kids = [c for c in b.children if c in kept]
        # the finest twigs carry most of it; every limb carries leaves over its outer part too,
        # so a limb whose side shoots the budget took is not left as a bare pole to the rim
        if b.level >= finest:
            carriers.append((b, 0.25, 1.0))
        elif b.level >= max(1, finest - 1):
            carriers.append((b, 0.45, 1.0))
        elif b.level >= 1 or not kids:
            carriers.append((b, 0.6 if kids else 0.4, 0.7))
        elif b.pts[-1, 2] > z0:
            # a trunk's or stem's own top: clothed, or the leader stands out of the crown bare
            carriers.append((b, 0.85, 0.8))
        if b.pts[-1, 2] > z0 * 0.7 or b.level >= 2:
            tips.append(b)
    total = sum(b.length * (1 - s0) * w for b, s0, w in carriers) or 1.0
    n_body = max(0, int(target * 1.7) - len(tips))
    P, O = [], []
    for b, s0, wt in carriers:
        seglen = np.linalg.norm(np.diff(b.pts, axis=0), axis=1)
        cum = np.r_[0.0, np.cumsum(seglen)]
        L = float(cum[-1])
        n = n_body * L * (1 - s0) * wt / total
        n = int(n) + (1 if rng.random() < n - int(n) else 0)
        for k in range(n):
            u = s0 + (1 - s0) * ((k + rng.uniform(0.2, 0.9)) / max(n, 1))
            at = min(u, 1.0) * L
            i = int(min(max(np.searchsorted(cum, at) - 1, 0), len(b.pts) - 2))
            w = (at - cum[i]) / max(seglen[i], 1e-9)
            p = b.pts[i] * (1 - w) + b.pts[i + 1] * w
            ax = _unit(b.pts[i + 1] - b.pts[i])
            P.append(p + _perp(ax) * rng.normal(0, leaf["clump"] * h * 0.08))
            O.append(ax)
    for b in tips:
        ax = _unit(b.pts[-1] - b.pts[-2])
        # the clump sits over the last of the shoot, not beyond it: a card past the tip of a
        # leader is a flag on a pole above the crown
        P.append(b.pts[-1] - ax * leaf["clump"] * h * 0.2)
        O.append(ax)
    if not P:
        return empty
    P = np.array(P)
    O = np.array(O)
    # a clump deep inside the crown is never seen: move leaf mass out to the shell
    rel0 = np.hypot(P[:, 0] - cxy[0], P[:, 1] - cxy[1])
    zc0 = np.clip((P[:, 2] - z0) / max(z1 - z0, 1e-3), 0, 1)
    al0 = np.array([max(0.3, R * envelope(shape, float(z))) for z in zc0])
    shell = np.clip(rel0 / al0, 0, 1) ** 2 + np.clip(zc0 - 0.55, 0, 1)
    keep_p = np.clip(0.25 + 0.9 * shell, 0.25, 1.0)
    keep = rng.random(len(P)) < keep_p
    if keep.sum() > 8:
        P, O = P[keep], O[keep]
    if len(P) > target:
        pick = rng.permutation(len(P))[:target]
        P, O = P[pick], O[pick]
    rel = np.hypot(P[:, 0] - cxy[0], P[:, 1] - cxy[1])
    zc = (P[:, 2] - z0) / max(z1 - z0, 1e-3)
    allowed = np.array([max(0.3, R * envelope(shape, float(z))) for z in np.clip(zc, 0, 1)])
    radial = np.clip(rel / allowed, 0.0, 1.2)
    exposure = np.clip(0.5 * radial + 0.6 * np.clip(zc, 0, 1) - 0.12 + rng.normal(0, 0.12, len(P)), 0.0, 1.0)
    size = leaf["clump"] * h * rng.uniform(0.8, 1.25, len(P))
    return P, O, size, exposure


def tip_points(tree: Tree, keep: list, levels=(2, 3)) -> np.ndarray:
    """The tips of the kept branches at these levels (where a willow's whips hang from)."""
    out = [tree.branches[i].pts[-1] for i in keep if tree.branches[i].level in levels and not tree.branches[i].root]
    return np.array(out) if out else np.zeros((0, 3))


def trunk_radius_at(tree: Tree, z: float) -> float:
    b = tree.branches[0]
    i = int(np.argmin(np.abs(b.pts[:, 2] - z)))
    return float(b.radii[i])
