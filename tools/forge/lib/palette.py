"""Region palettes for the forge (pure Python, no bpy).

A region's identity.palette is six hex colours in no fixed order. Generators ask for
*roles* (light, dark, accent, warm, cool, green, earth, mid) which are derived from the
colours by simple scoring, so every region answers every role and the same generator
can be tinted by any region.
"""
from __future__ import annotations

import colorsys
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
REGIONS_JSON = REPO_ROOT / "game" / "content" / "packs" / "core" / "regions" / "regions.json"

ROLES = ("light", "dark", "accent", "warm", "cool", "green", "earth", "mid")

# Used when a generator runs without --palette (unit tests, neutral props).
NEUTRAL_DEF = {
    "id": "forge:region/neutral",
    "name": "Neutral",
    "identity": {
        "palette": ["#b9a789", "#4d6b3a", "#e6e1d6", "#3b3a36", "#8a4b32", "#6f7f93"],
        "flora": [],
        "materials": [],
    },
}


def hex_to_srgb(h: str) -> tuple[float, float, float]:
    h = h.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        raise ValueError("bad hex colour %r" % h)
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_hex(c) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v * 255)))) for v in c[:3])


def srgb_channel_to_linear(v: float) -> float:
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def linear_channel_to_srgb(v: float) -> float:
    v = max(0.0, v)
    return v * 12.92 if v <= 0.0031308 else 1.055 * (v ** (1 / 2.4)) - 0.055


def srgb_to_linear(c) -> tuple[float, float, float]:
    return tuple(srgb_channel_to_linear(v) for v in c[:3])


def linear_to_srgb(c) -> tuple[float, float, float]:
    return tuple(linear_channel_to_srgb(v) for v in c[:3])


def lin(h: str) -> tuple[float, float, float]:
    """Hex sRGB -> linear rgb (what Blender node inputs expect)."""
    return srgb_to_linear(hex_to_srgb(h))


def luminance(lin_rgb) -> float:
    r, g, b = lin_rgb[:3]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def mix(a, b, t: float):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def scale(c, k: float):
    return tuple(min(1.0, v * k) for v in c[:3])


def _hsv(srgb):
    return colorsys.rgb_to_hsv(*srgb[:3])


class Palette:
    """Six region colours plus derived roles. Colours are exposed as hex, sRGB floats and
    linear floats; `role()` returns linear rgb for direct use in node sockets."""

    def __init__(self, region_def: dict):
        ident = region_def.get("identity", {})
        hexes = list(ident.get("palette", []))
        if len(hexes) < 3:
            raise ValueError("palette needs at least 3 colours: %r" % (hexes,))
        self.id: str = region_def.get("id", "forge:region/unknown")
        self.short: str = self.id.split("/")[-1]
        self.name: str = region_def.get("name", self.short)
        self.hexes: list[str] = hexes
        self.srgb = [hex_to_srgb(h) for h in hexes]
        self.linear = [srgb_to_linear(c) for c in self.srgb]
        self.flora: list[str] = list(ident.get("flora", []))
        self.materials: list[str] = list(ident.get("materials", []))
        self.light_recipe: dict = dict(ident.get("light", {}))
        self._roles = self._derive_roles()

    # --- role derivation -------------------------------------------------------------
    def _derive_roles(self) -> dict[str, int]:
        lums = [luminance(c) for c in self.linear]
        hsvs = [_hsv(c) for c in self.srgb]
        idx = list(range(len(self.srgb)))
        roles: dict[str, int] = {}
        roles["light"] = max(idx, key=lambda i: lums[i])
        roles["dark"] = min(idx, key=lambda i: lums[i])
        # accent: saturated and not too dark
        roles["accent"] = max(idx, key=lambda i: hsvs[i][1] * (0.35 + hsvs[i][2]))
        roles["warm"] = max(idx, key=lambda i: (self.srgb[i][0] - self.srgb[i][2]) + 0.3 * hsvs[i][1])
        roles["cool"] = max(idx, key=lambda i: (self.srgb[i][2] - self.srgb[i][0]) + 0.3 * hsvs[i][1])
        roles["green"] = max(idx, key=lambda i: self.srgb[i][1] - max(self.srgb[i][0], self.srgb[i][2]) + 0.15 * hsvs[i][1])
        # earth: brownish mid tones (r > g > b, moderate saturation, mid luminance)
        def earth_score(i):
            r, g, b = self.srgb[i]
            order = 1.0 if (r >= g >= b) else 0.3
            return order * (0.5 - abs(lums[i] - 0.22)) * (0.4 + hsvs[i][1])
        roles["earth"] = max(idx, key=earth_score)
        med = sorted(lums)[len(lums) // 2]
        roles["mid"] = min(idx, key=lambda i: abs(lums[i] - med))
        return roles

    def role_index(self, role: str) -> int:
        if role not in self._roles:
            raise KeyError("unknown palette role %r (have %s)" % (role, ", ".join(ROLES)))
        return self._roles[role]

    def role(self, role: str) -> tuple[float, float, float]:
        """Linear rgb of the colour playing this role."""
        return self.linear[self.role_index(role)]

    def role_hex(self, role: str) -> str:
        return self.hexes[self.role_index(role)]

    def color(self, i: int) -> tuple[float, float, float]:
        return self.linear[i % len(self.linear)]

    def tint(self, base_linear, role: str, amount: float):
        """Mix `amount` of a role colour into a base colour (both linear)."""
        return mix(base_linear, self.role(role), max(0.0, min(1.0, amount)))

    def has_flora(self, key: str) -> bool:
        return key in self.flora

    def to_meta(self) -> dict:
        return {"id": self.id, "colors": list(self.hexes), "roles": {r: self.hexes[i] for r, i in self._roles.items()}}

    def __repr__(self) -> str:
        return "Palette(%s %s)" % (self.short, " ".join(self.hexes))


def load_regions(path: Path | str | None = None) -> list[dict]:
    p = Path(path) if path else REGIONS_JSON
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = [data]
    return [d for d in data if isinstance(d, dict) and "id" in d]


def region_ids(path: Path | str | None = None) -> list[str]:
    return [r["id"] for r in load_regions(path)]


def get_palette(region: str | None, path: Path | str | None = None) -> Palette:
    """Accepts 'hearthvale', 'region/hearthvale' or 'core:region/hearthvale'. None or
    'neutral' gives the neutral palette."""
    if not region or region in ("neutral", "none"):
        return Palette(NEUTRAL_DEF)
    short = region.split("/")[-1].split(":")[-1]
    for r in load_regions(path):
        if r["id"] == region or r["id"].split("/")[-1] == short:
            return Palette(r)
    raise KeyError("unknown region %r; known: %s" % (region, ", ".join(region_ids(path))))


def all_palettes(path: Path | str | None = None) -> list[Palette]:
    return [Palette(r) for r in load_regions(path)]
