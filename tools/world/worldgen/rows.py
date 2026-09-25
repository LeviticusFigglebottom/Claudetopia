"""A cell's instances of one asset, kept as arrays until they are written.

The scatter's rows were Python lists, [x, y, z, yaw, scale, "#rrggbb"] and the lean pair, about
315 bytes each: 5.65 million of them were 1.78 GB of a 2048 build's peak, the same at any size, and
the most a build held at once. `Rows` keeps the scatter's in float32 columns and a packed colour,
28 to 36 bytes a row, and gives each one back as the list it was when the cell is written, value for
value: every value is rounded as it was when the row was a list, and a float32 holds the world's
metres to the centimetre, degrees to the tenth and scales to the thousandth that round back to the
same figures. What every other placer hands in as lists (rails, ledges, hedges; a few hundred
thousand at most) is kept as it came, in order after what came before it.
"""
from __future__ import annotations

import numpy as np


class Rows:
    """Instances of one asset in one cell: array chunks from the scatter and list chunks from the
    rest, in the order they were added. Iterates, and `json` writes it (`default=Rows.as_json`),
    as the list of rows it stands for."""

    __slots__ = ("_chunks", "_n")

    def __init__(self):
        self._chunks: list = []
        self._n = 0

    # --- adding -----------------------------------------------------------------------------
    def add_arrays(self, x, y, z, yaw, scale, rgb, lean=None, toward=None) -> None:
        """`rgb` is uint32 0xRRGGBB (the `cells._hex` of the tint), the rest float arrays; `lean`
        and `toward` both or neither."""
        cols = {"x": np.asarray(x, np.float32), "y": np.asarray(y, np.float32), "z": np.asarray(z, np.float32),
                "yaw": np.asarray(yaw, np.float32), "scale": np.asarray(scale, np.float32),
                "rgb": np.asarray(rgb, np.uint32)}
        if lean is not None:
            cols["lean"] = np.asarray(lean, np.float32)
            cols["toward"] = np.asarray(toward, np.float32)
        k = int(cols["x"].size)
        if k:
            self._chunks.append(cols)
            self._n += k

    def extend(self, rows) -> None:
        """Rows as lists (or another Rows), after what is here."""
        if isinstance(rows, Rows):
            self._chunks.extend(rows._chunks)
            self._n += rows._n
            return
        rows = list(rows)
        if rows:
            self._chunks.append(rows)
            self._n += len(rows)

    def append(self, row) -> None:
        self.extend([row])

    # --- reading ----------------------------------------------------------------------------
    def __len__(self) -> int:
        return self._n

    def __iter__(self):
        for c in self._chunks:
            if isinstance(c, list):
                yield from c
                continue
            x, y, z = c["x"].tolist(), c["y"].tolist(), c["z"].tolist()
            yaw, scale, rgb = c["yaw"].tolist(), c["scale"].tolist(), c["rgb"].tolist()
            lean = c["lean"].tolist() if "lean" in c else None
            toward = c["toward"].tolist() if "toward" in c else None
            for i in range(len(x)):
                row = [round(x[i], 2), round(y[i], 2), round(z[i], 2), round(yaw[i], 1), round(scale[i], 3),
                       "#%06x" % rgb[i]]
                if lean is not None:
                    row += [round(lean[i], 1), round(toward[i], 1)]
                yield row

    def __eq__(self, other) -> bool:
        if isinstance(other, (Rows, list)):
            return list(self) == list(other)
        return NotImplemented

    def __repr__(self) -> str:
        return "Rows(%d)" % self._n

    def xz(self) -> np.ndarray:
        """[n, 2] float64 of every row's x and z, in order."""
        parts = []
        for c in self._chunks:
            if isinstance(c, list):
                parts.append(np.array([(float(r[0]), float(r[2])) for r in c], dtype=np.float64).reshape(-1, 2))
            else:
                parts.append(np.stack([c["x"], c["z"]], axis=1).astype(np.float64))
        return np.concatenate(parts) if parts else np.zeros((0, 2))

    def keep(self, mask: np.ndarray) -> None:
        """Keep the rows where `mask` (one bool a row, in order) is true."""
        mask = np.asarray(mask, dtype=bool)
        out, at = [], 0
        for c in self._chunks:
            k = len(c) if isinstance(c, list) else int(c["x"].size)
            m = mask[at:at + k]
            at += k
            if isinstance(c, list):
                c = [r for r, w in zip(c, m) if w]
                if c:
                    out.append(c)
            elif m.any():
                out.append({name: col[m] for name, col in c.items()})
        self._chunks = out
        self._n = int(mask.sum())

    @staticmethod
    def as_json(obj):
        """`json.dump`'s `default`: a Rows is written as its list of rows."""
        if isinstance(obj, Rows):
            return list(obj)
        raise TypeError("%r is not JSON serialisable" % (obj,))


def pack_rgb(tints: np.ndarray) -> np.ndarray:
    """uint32 0xRRGGBB of [n, 3] colours in 0..1, as `cells._hex` writes them (int(c * 255))."""
    c = (np.asarray(tints, dtype=np.float64) * 255.0).astype(np.int64)
    return ((c[:, 0] << 16) | (c[:, 1] << 8) | c[:, 2]).astype(np.uint32)
