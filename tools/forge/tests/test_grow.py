"""The tree grower (lib/grow.py) and the species bark (lib/bark.py): pure numpy, no Blender.

What they promise is what the Sapling trees broke: wood that is whole. Every branch is one
connected tube that starts inside its parent and closes to a point; a budget is met by taking
whole branches away, never a branch before the finer ones growing from it; LOD1 is a subset.
"""
from __future__ import annotations

import unittest

import numpy as np

from lib import bark as BK
from lib import grow as G

HEIGHTS = {"oak": 10.0, "giant_oak": 30.0, "apple": 5.0, "hawthorn": 4.4, "yew": 6.2, "black_ash": 16.0,
           "hardy_pine": 11.0, "rowan": 6.6, "juniper": 2.1, "willow": 9.0, "alder": 8.0,
           "willow_pollard": 4.5, "lime": 11.0, "birch": 11.0, "hazel": 4.5, "dead_ash_tree": 9.0,
           "char_stump": 2.0}


def _pieces(T: np.ndarray, nverts: int) -> int:
    parent = np.arange(nverts)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for a, b, c in T:
        for x, y in ((a, b), (b, c)):
            rx, ry = find(x), find(y)
            if rx != ry:
                parent[rx] = ry
    used = np.unique(T.reshape(-1))
    return len({find(v) for v in used})


def _dist_to_polyline(p, pts):
    best = 1e9
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        t = float(np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12), 0, 1))
        best = min(best, float(np.linalg.norm(a + ab * t - p)))
    return best


class TestGrow(unittest.TestCase):
    def test_every_species_grows_every_age(self):
        for kind in G.FORMS:
            for age in G.AGES:
                t = G.grow(kind, 11, HEIGHTS[kind] * G.AGES[age]["height"], age)
                self.assertGreater(len(t.branches), 0, "%s %s" % (kind, age))
                top = max(b.pts[:, 2].max() for b in t.branches)
                self.assertGreater(top, t.height * 0.5, "%s %s is stunted" % (kind, age))

    def test_every_branch_starts_inside_its_parent(self):
        """The whole point: nothing floats. A child's foot is on its parent's axis (or within its
        wood), and no thicker there than the parent, so the joint is closed from outside."""
        for kind in G.FORMS:
            t = G.grow(kind, 3, HEIGHTS[kind])
            for i, b in enumerate(t.branches):
                if b.parent < 0:
                    continue
                par = t.branches[b.parent]
                d = _dist_to_polyline(b.pts[0], par.pts)
                self.assertLessEqual(d, float(par.radii.max()) * 1.3 + 1e-3,
                                     "%s branch %d starts %.2f m off its parent" % (kind, i, d))

    def test_a_trim_takes_whole_branches_and_never_a_parent_first(self):
        for kind in ("oak", "yew", "juniper", "lime"):
            t = G.grow(kind, 5, HEIGHTS[kind])
            for budget in (4200, 900):
                keep = G.trim(t.branches, budget, G.SIDES["normal"])
                kept = set(keep)
                for i in keep:
                    p = t.branches[i].parent
                    self.assertTrue(p < 0 or p in kept, "%s keeps a branch whose parent is gone" % kind)
                V, N, UV, T, R = G.wood_mesh(t, keep, G.SIDES["normal"])
                self.assertLessEqual(len(T), max(budget, sum(
                    G.tube_tris(len(t.branches[i].pts), G.sides_for(t.branches[i], G.SIDES["normal"]))
                    for i in keep if t.branches[i].parent < 0)), "%s over budget" % kind)

    def test_the_wood_is_one_piece_per_branch_and_no_shards(self):
        """The Sapling trees' wood was hundreds of loose 6-triangle pieces. Here each kept branch
        is exactly one connected piece, however the budget cut the tree."""
        for kind in ("oak", "hawthorn", "willow", "hardy_pine"):
            t = G.grow(kind, 9, HEIGHTS[kind])
            keep = G.trim(t.branches, 4200, G.SIDES["normal"])
            V, N, UV, T, R = G.wood_mesh(t, keep, G.SIDES["normal"])
            self.assertEqual(_pieces(T, len(V)), len(keep), kind)
            smallest = min(np.bincount(R)[keep])
            self.assertGreaterEqual(smallest, 9, "%s has a branch drawn in %d triangles" % (kind, smallest))

    def test_lod1_is_the_same_tree_with_twigs_taken_away(self):
        t = G.grow("oak", 4, 10.0)
        keep0 = G.trim(t.branches, 4200, G.SIDES["normal"])
        keep1 = [i for i in G.trim(t.branches, 900, G.SIDES["lod1"], stride=2) if i in set(keep0)]
        self.assertTrue(set(keep1) <= set(keep0))
        self.assertIn(0, keep1, "the trunk survives any budget")
        V, N, UV, T, R = G.wood_mesh(t, keep1, G.SIDES["lod1"], stride=2)
        self.assertLessEqual(len(T), 900)

    def test_every_species_lod1_fits_its_budget(self):
        """LOD1 wood is 900 triangles at most for every species, a coppice of eight rods included:
        gen_trees strides a tree's straight stems too when trimming twigs alone cannot fit it."""
        for kind in G.FORMS:
            for seed in (1, 2, 3):
                t = G.grow(kind, seed, HEIGHTS[kind])
                k0 = set(G.trim(t.branches, 4200, G.SIDES["normal"]))
                k1 = [i for i in G.trim(t.branches, 900, G.SIDES["lod1"], stride=2) if i in k0]
                n = len(G.wood_mesh(t, k1, G.SIDES["lod1"], stride=2)[3])
                if n > 900:
                    k1 = [i for i in G.trim(t.branches, 900, G.SIDES["lod1"], stride=2, loose=True) if i in k0]
                    n = len(G.wood_mesh(t, k1, G.SIDES["lod1"], stride=2, loose=True)[3])
                self.assertLessEqual(n, 900, "%s seed %d" % (kind, seed))

    def test_twigs_end_in_points(self):
        t = G.grow("rowan", 2, 6.6)
        for b in t.branches:
            self.assertEqual(b.radii[-1], 0.0)

    def test_leaf_clumps_sit_in_the_crown(self):
        rng = np.random.default_rng(1)
        t = G.grow("oak", 6, 10.0)
        keep = G.trim(t.branches, 4200, G.SIDES["normal"])
        P, O, S, E = G.leaf_points(t, keep, G.FORMS["oak"], rng, 1150)
        self.assertGreater(len(P), 800)
        self.assertLessEqual(len(P), 1150)
        self.assertTrue(((E >= 0) & (E <= 1)).all())
        self.assertGreater(P[:, 2].min(), 0.0)

    def test_species_differ_in_form(self):
        """An oak is broader than it is tall-and-narrow; a pine and an ash are the reverse."""
        def ratio(kind):
            t = G.grow(kind, 8, HEIGHTS[kind])
            pts = np.vstack([b.pts for b in t.branches if not b.root])
            w = max(np.ptp(pts[:, 0]), np.ptp(pts[:, 1]))
            return w / np.ptp(pts[:, 2])
        self.assertGreater(ratio("oak"), ratio("black_ash"))
        self.assertGreater(ratio("oak"), ratio("alder"))


class TestBark(unittest.TestCase):
    def test_every_species_has_a_bark_that_tiles(self):
        for kind in G.FORMS:
            alb, nrm, orm = BK.paint(kind, 128, 3)
            self.assertEqual(alb.shape, (128, 128, 3))
            # tiles: the wrap-around step is no bigger than an ordinary neighbour step
            a = alb.astype(float)
            inner = np.abs(np.diff(a, axis=1)).mean()
            seam = np.abs(a[:, 0] - a[:, -1]).mean()
            self.assertLess(seam, inner * 3.0 + 4.0, kind)


if __name__ == "__main__":
    unittest.main()
