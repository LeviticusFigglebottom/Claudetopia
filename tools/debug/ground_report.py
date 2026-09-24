#!/usr/bin/env python3
"""What the ground probe saw, in a form a person reads in two minutes.

    python3 tools/debug/ground_report.py captures/tour     # after ./run.sh tour
    python3 tools/debug/ground_report.py captures/roads    # after ./run.sh roads
    python3 tools/debug/ground_report.py captures/tour --against captures/tour_batch3
                                                           # and what changed since another tour

Reads tour.jsonl or roads.jsonl (game/tools_gd/ground_probe.gd writes one row a place or a road)
and writes, beside it:

  report.md          the totals, the worst places (or roads) in a table, and every line the engine
                     said, with where it was first said
  contact_worst.png  the pictures of the worst places, each marked with what is wrong (tour)
  contact_all.png    every place's picture in tour order, a red frame round each with a fault (tour)

A place is scored by what a player would meet there: a script error worst, then an engine error, a
body under the ground or through it, in deep water, inside something solid, in the air, a country
that never finished streaming, and a frame over the draw budget. Exits 0; it only reports.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# the draw budget the graphics work holds a view to (PROGRESS, "Trees grown whole")
DRAW_BUDGET = 2000
PRIM_BUDGET = 1_500_000

WEIGHTS = [
    ("script_errors", 50), ("errors", 20),
]
FLAG_WEIGHTS = [
    ("under the ground", 40), ("fell", 40), ("in deep water", 30), ("inside", 25),
    ("in the air", 20), ("in water", 8), ("no body", 50),
]


def load_rows(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass     # a line cut off by a killed run
    # a tour taken in pieces adds rows; the newest row for a place wins
    by_id = {}
    for r in rows:
        by_id[r.get("id")] = r
    return sorted(by_id.values(), key=lambda r: r.get("i", 0))


def faults(r: dict) -> list[str]:
    out = []
    if r.get("script_errors"):
        out.append(f"{r['script_errors']} script errors")
    if r.get("errors"):
        out.append(f"{r['errors']} errors")
    out += list(r.get("stand", {}).get("flags", []))
    if r.get("unstreamed") or r.get("stream_s", 0) < 0:
        ring = r.get("ring", {})
        if ring.get("ground_drawn", True) is False:
            out.append("NO GROUND DRAWN (no terrain region under the body)")
        else:
            out.append(f"UNSTREAMED ({ring.get('cells', '?')} of {ring.get('wanted', '?')} cells, {ring.get('things', '?')} things)")
    if r.get("draws", 0) > DRAW_BUDGET:
        out.append(f"{r['draws']} draws")
    if r.get("primitives", 0) > PRIM_BUDGET:
        out.append(f"{r['primitives'] / 1e6:.2f} M prims")
    if r.get("died"):
        out.append("the body died")
    return out


def score(r: dict) -> float:
    s = 0.0
    for key, w in WEIGHTS:
        s += w * min(int(r.get(key, 0)), 5)
    for flag in r.get("stand", {}).get("flags", []):
        for word, w in FLAG_WEIGHTS:
            if flag.startswith(word):
                s += w
                break
    if r.get("unstreamed") or r.get("stream_s", 0) < 0:
        s += 60
    if r.get("draws", 0) > DRAW_BUDGET:
        s += 10
    if r.get("primitives", 0) > PRIM_BUDGET:
        s += 10
    if r.get("died"):
        s += 15
    return s


def md_cell(s: str) -> str:
    return str(s).replace("|", "/").replace("\n", " ")


def said_table(rows: list[dict], label: str) -> list[str]:
    """Every distinct line the engine said, with how often and where first."""
    seen: dict[tuple, dict] = {}
    for r in rows:
        for s in r.get("said", []):
            key = (s["kind"], s["message"], s.get("source", ""))
            e = seen.setdefault(key, {"n": 0, "first": r.get("name") or r.get("id"), "places": 0})
            e["n"] += int(s.get("n", 1))
            e["places"] += 1
    if not seen:
        return ["Nothing was said by the engine at any " + label + "."]
    out = [f"| kind | times | {label}s | first at | message |", "|---|---:|---:|---|---|"]
    for (kind, msg, src), e in sorted(seen.items(), key=lambda kv: -kv[1]["n"])[:40]:
        where = f" ({src})" if src else ""
        out.append(f"| {kind} | {e['n']} | {e['places']} | {md_cell(e['first'])} | {md_cell(msg[:160])}{md_cell(where)} |")
    return out


def tour_report(d: Path, rows: list[dict]) -> str:
    n = len(rows)
    bad = [r for r in rows if faults(r)]
    tot = lambda k: sum(int(r.get(k, 0)) for r in rows)
    flags: dict[str, int] = {}
    for r in rows:
        for f in r.get("stand", {}).get("flags", []):
            word = next((w for w, _ in FLAG_WEIGHTS if f.startswith(w)), f.split(" ")[0])
            flags[word] = flags.get(word, 0) + 1
    # a frame of an empty county is cheap, so it is not a frame of the country: kept out of the costs
    unstreamed = [r for r in rows if r.get("unstreamed") or r.get("stream_s", 0) < 0]
    measured = [r for r in rows if r not in unstreamed] or [{"frame_ms": 0, "draws": 0}]
    ms = sorted(r.get("frame_ms", 0) for r in measured)
    draws = sorted(r.get("draws", 0) for r in measured)
    streams = [r["stream_s"] for r in rows if r.get("stream_s", -1) >= 0]
    lines = [
        "# The teleport tour",
        "",
        f"{n} places stood at, {len(bad)} with something wrong. "
        f"Engine errors {tot('errors')}, script errors {tot('script_errors')}, warnings {tot('warnings')}, "
        f"the game's own logged errors {tot('game_errors')}.",
        "",
        (f"**{len(unstreamed)} stops where the world did not stream** (still coming in at the limit, or built "
         f"and empty); their frames and footings are pictures of an empty county, left out of the costs below: "
         + ", ".join(str(r.get('name', r['id'])) for r in unstreamed[:20]) + ".\n") if unstreamed else "",
        "Where the body stood: " + (", ".join(f"{k} {v}" for k, v in sorted(flags.items(), key=lambda kv: -kv[1]))
                                   if flags else "sound everywhere") + ".",
        "",
        (f"Frame: median {ms[len(ms) // 2]:.0f} ms, worst {ms[-1]:.0f} ms (software renderer: compare places, "
         f"not machines); draw calls median {draws[len(draws) // 2]}, worst {draws[-1]} (budget {DRAW_BUDGET}). "
         f"The country stood within {max(streams) if streams else 0:.0f} s of a jump at worst; "
         f"costs over {len(measured)} stops that streamed.") if rows else "",
        "",
        "## The worst places",
        "",
        "| # | place | kind | region | what is wrong | on | frame ms | draws |",
        "|---:|---|---|---|---|---|---:|---:|",
    ]
    worst = sorted(bad, key=lambda r: -score(r))[:30]
    for r in worst:
        region = str(r.get("region", "")).split("/")[-1]
        lines.append(f"| {r['i']} | {md_cell(r.get('name', r['id']))} | {r.get('kind', '')} | {region} | "
                     f"{md_cell('; '.join(faults(r)))} | {md_cell(r.get('stand', {}).get('on', ''))} | "
                     f"{r.get('frame_ms', 0):.0f} | {r.get('draws', 0)} |")
    if not worst:
        lines.append("| | nothing wrong anywhere | | | | | | |")
    lines += ["", "Pictures: `contact_worst.png` (these), `contact_all.png` (every place, red frame = a fault).", ""]
    lines += ["## By region", "", "| region | places | with a fault | errors | script errors | median ms | worst draws |",
              "|---|---:|---:|---:|---:|---:|---:|"]
    regions: dict[str, list] = {}
    for r in rows:
        regions.setdefault(str(r.get("region", "")).split("/")[-1] or "?", []).append(r)
    for name, rs in sorted(regions.items()):
        rms = sorted(r.get("frame_ms", 0) for r in rs)
        lines.append(f"| {name} | {len(rs)} | {sum(1 for r in rs if faults(r))} | {sum(int(r.get('errors', 0)) for r in rs)} | "
                     f"{sum(int(r.get('script_errors', 0)) for r in rs)} | {rms[len(rms) // 2]:.0f} | "
                     f"{max(r.get('draws', 0) for r in rs)} |")
    lines += ["", "## What the engine said", ""] + said_table(rows, "place")
    lines += ["", "## Every place", "", "| # | place | x | z | on | wrong | stream s | ms | draws |",
              "|---:|---|---:|---:|---|---|---:|---:|---:|"]
    for r in rows:
        lines.append(f"| {r['i']} | {md_cell(r.get('name', r['id']))} | {r['x']:.0f} | {r['z']:.0f} | "
                     f"{md_cell(r.get('stand', {}).get('on', ''))} | {md_cell('; '.join(faults(r)))} | "
                     f"{r.get('stream_s', -1):.0f} | {r.get('frame_ms', 0):.0f} | {r.get('draws', 0)} |")
    contact_sheets(d, rows, worst)
    return "\n".join(lines) + "\n"


def against(rows: list[dict], base: list[dict]) -> str:
    """What changed at each place between a baseline tour and this one, in the same terms."""
    before = {r["id"]: r for r in base}
    now = {r["id"]: r for r in rows}
    fixed, broke, still, changed = [], [], [], []
    for pid, r in now.items():
        b = before.get(pid)
        if b is None:
            continue
        fb, fn = faults(b), faults(r)
        if fb and not fn:
            fixed.append((r, fb))
        elif fn and not fb:
            broke.append((r, fn))
        elif fn and fb:
            (still if set(fb) == set(fn) else changed).append((r, fb, fn))
    new = [r for pid, r in now.items() if pid not in before]
    gone = [b for pid, b in before.items() if pid not in now]
    tot = lambda rs, k: sum(int(r.get(k, 0)) for r in rs)
    both = [pid for pid in now if pid in before]
    lines = ["## Against the baseline", "",
             f"{len(both)} places stood at in both tours. Fixed {len(fixed)}, broken {len(broke)}, still wrong "
             f"{len(still)}, wrong in another way {len(changed)}; {len(new)} places only in this tour, "
             f"{len(gone)} only in the baseline. Engine errors {tot([before[p] for p in both], 'errors')} -> "
             f"{tot([now[p] for p in both], 'errors')}, script errors {tot([before[p] for p in both], 'script_errors')} -> "
             f"{tot([now[p] for p in both], 'script_errors')} over the places in both.", ""]
    def table(title: str, items: list, cols: str) -> None:
        lines.extend([f"### {title}", ""])
        if not items:
            lines.extend(["None.", ""])
            return
        lines.extend([f"| # | place | region | {cols} |", "|---:|---|---|---|" + ("---|" if cols.count("|") else "")])
        for it in items[:40]:
            r = it[0]
            rest = " | ".join(md_cell("; ".join(x)) for x in it[1:])
            lines.append(f"| {r['i']} | {md_cell(r.get('name', r['id']))} | {str(r.get('region', '')).split('/')[-1]} | {rest} |")
        lines.append("")
    table("Broken since the baseline", broke, "what is wrong now")
    table("Fixed since the baseline", fixed, "what was wrong")
    table("Wrong in another way", changed, "was | is")
    table("Still wrong", still, "what is wrong | same")
    if new:
        lines += ["Only in this tour: " + ", ".join(str(r.get("name", r["id"])) for r in new[:60]), ""]
    if gone:
        lines += ["Only in the baseline: " + ", ".join(str(r.get("name", r["id"])) for r in gone[:60]), ""]
    return "\n".join(lines) + "\n"


def roads_report(rows: list[dict]) -> str:
    n = len(rows)
    walked = sum(r.get("walked_m", 0) for r in rows)
    snags = [(r, s) for r in rows for s in r.get("snags", [])]
    traps = [(r, s) for r in rows for s in r.get("traps", [])]
    wet = [(r, s) for r in rows for s in r.get("wet", []) if s.get("depth", 0) > 1.0]
    lines = [
        "# The road walk",
        "",
        f"{n} roads walked on the keys, {walked / 1000:.1f} km of road, "
        f"{sum(r.get('game_s', 0) for r in rows) / 60:.0f} min of the game's time. "
        f"{sum(1 for r in rows if r.get('reached'))} reached their end. "
        f"Snags {len(snags)}, traps {len(traps)}, wading deeper than 1 m {len(wet)}. "
        f"Engine errors {sum(int(r.get('errors', 0)) for r in rows)}, "
        f"script errors {sum(int(r.get('script_errors', 0)) for r in rows)}.",
        "",
        "## Traps (the body could not go on in six seconds and was put down further along)",
        "",
        "| road | x | z | region | at the knee | at the chest | rise | inside |",
        "|---|---:|---:|---|---|---|---:|---|",
    ]
    for r, s in traps[:60]:
        lines.append(f"| {r['id'].split('/')[-1]} | {s['x']:.0f} | {s['z']:.0f} | {str(s.get('region', '')).split('/')[-1]} | "
                     f"{md_cell(s.get('knee', ''))} | {md_cell(s.get('chest', ''))} | {s.get('rise_deg', 0):.0f} deg | "
                     f"{md_cell(s.get('inside', ''))} |")
    if not traps:
        lines.append("| none | | | | | | | |")
    what: dict[str, int] = {}
    for _, s in snags:
        k = s.get("knee") or s.get("chest") or ("a slope" if abs(s.get("rise_deg", 0)) > 30 else "nothing in front")
        what[k] = what.get(k, 0) + 1
    lines += ["", "## What snags a body", "", "| in front | snags |", "|---|---:|"]
    for k, v in sorted(what.items(), key=lambda kv: -kv[1])[:30]:
        lines.append(f"| {md_cell(k)} | {v} |")
    lines += ["", "## Every road", "", "| road | length m | walked m | reached | game s | snags | traps | deep water | errors |",
              "|---|---:|---:|---|---:|---:|---:|---:|---:|"]
    for r in rows:
        lines.append(f"| {r['id'].split('/')[-1]} | {r.get('length_m', 0):.0f} | {r.get('walked_m', 0):.0f} | "
                     f"{'yes' if r.get('reached') else 'no'} | {r.get('game_s', 0):.0f} | {len(r.get('snags', []))} | "
                     f"{len(r.get('traps', []))} | {sum(1 for s in r.get('wet', []) if s.get('depth', 0) > 1.0)} | "
                     f"{int(r.get('errors', 0)) + int(r.get('script_errors', 0))} |")
    lines += ["", "## What the engine said", ""] + said_table(rows, "road")
    return "\n".join(lines) + "\n"


def contact_sheets(d: Path, rows: list[dict], worst: list[dict]) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("ground_report: no Pillow, so no contact sheets", file=sys.stderr)
        return
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 13)
    except OSError:
        font = ImageFont.load_default()

    def sheet(items: list[dict], cols: int, tw: int, out: Path, captions: int) -> None:
        items = [r for r in items if r.get("picture") and (d / r["picture"]).exists()]
        if not items:
            return
        th = tw * 9 // 16
        cap_h = 16 * captions + 4
        rows_n = (len(items) + cols - 1) // cols
        img = Image.new("RGB", (cols * (tw + 6) + 6, rows_n * (th + cap_h + 6) + 6), (24, 24, 26))
        dr = ImageDraw.Draw(img)
        for k, r in enumerate(items):
            x = 6 + (k % cols) * (tw + 6)
            y = 6 + (k // cols) * (th + cap_h + 6)
            with Image.open(d / r["picture"]) as src:
                img.paste(src.convert("RGB").resize((tw, th)), (x, y))
            f = faults(r)
            if f:
                dr.rectangle([x - 3, y - 3, x + tw + 2, y + th + 2], outline=(220, 40, 40), width=3)
            dr.text((x, y + th + 2), f"{r['i']} {r.get('name', r['id'])}"[: tw // 7], fill=(235, 235, 235), font=font)
            if captions > 1:
                text = "; ".join(f) if f else "sound"
                for line_n in range(captions - 1):
                    part = text[line_n * (tw // 7):(line_n + 1) * (tw // 7)]
                    dr.text((x, y + th + 18 + 16 * line_n), part, fill=(255, 140, 120) if f else (140, 200, 140), font=font)
        img.save(out)
        print(f"ground_report: {out} ({len(items)} pictures)")

    sheet(worst, 5, 320, d / "contact_worst.png", 4)
    sheet(rows, 12, 192, d / "contact_all.png", 1)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = Path(sys.argv[1])
    if (d / "tour.jsonl").exists():
        rows = load_rows(d / "tour.jsonl")
        text = tour_report(d, rows)
        if "--against" in sys.argv:
            base_dir = Path(sys.argv[sys.argv.index("--against") + 1])
            text = text.replace("\n## The worst places", "\n" + against(rows, load_rows(base_dir / "tour.jsonl"))
                                + "\n## The worst places", 1)
    elif (d / "roads.jsonl").exists():
        text = roads_report(load_rows(d / "roads.jsonl"))
    else:
        print(f"ground_report: no tour.jsonl or roads.jsonl in {d}", file=sys.stderr)
        return 2
    (d / "report.md").write_text(text, encoding="utf-8")
    print(f"ground_report: {d / 'report.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
