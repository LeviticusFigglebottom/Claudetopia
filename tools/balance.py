#!/usr/bin/env python3
"""The economy and difficulty curves, read straight out of the content pack.

`ASSESSMENT.md` says every threshold in this game is a considered guess, because there has
never been a playthrough to calibrate against. That is still true of *pacing* — how long a
player takes to get anywhere — and it does not have to be true of the numbers themselves.
Damage, health, armour, loot, prices and XP are all data, and the formulas that combine them
are three static functions in `damage_model.gd` and `leveling.gd`. So they can be read.

This reads them and prints the curves: how many hits each region's enemies take and give, what
an hour of each region is worth in marks, and what the things you want cost in units of the
thing you do. It does not know how long a fight *feels*, and it says so.

The formulas are duplicated here from the GDScript on purpose — a second opinion is the point,
and `test_balance.gd` asserts the two agree. Usage: tools/balance.py [--vigour 10] [--skill 20]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import statistics

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "game", "content", "packs", "core")

MIN_DAMAGE = 1.0
HEAVY_ATTACK_MULT = 1.6
MAX_CHARGE = 1.5           # a heavy held to full
## Three points on a plausible career: what the Naming hands you, what a middle region arms
## you with, and the best the smiths of Wickmere can make. Reporting one of them makes the
## late regions look impossible and the early ones look trivial; reporting three shows which
## part of the curve each region is actually written for.
LOADOUTS = [
    ("start", 14.0, 20.0),    # iron sword, a little practice
    ("mid", 18.0, 50.0),      # ashen sword
    ("late", 25.0, 85.0),     # bell-bronze axe, well practised
]


def load(folder: str) -> list:
    out = []
    for path in sorted(glob.glob(os.path.join(PACK, folder, "*.json"))):
        data = json.load(open(path, encoding="utf-8"))
        out.extend(data if isinstance(data, list) else [data])
    return out


def by_id(defs: list) -> dict:
    return {d.get("id", ""): d for d in defs}


# --- the formulas, mirrored from the game ------------------------------------------------

def hp_max(vigour: int) -> float:
    return 60.0 + 4.0 * vigour


def skill_mult(skill: float) -> float:
    return 1.0 + max(skill, 0.0) / 200.0


def hit(weapon_base: float, skill: float, armour: float, heavy: bool = False) -> float:
    raw = weapon_base * skill_mult(skill)
    if heavy:
        raw *= HEAVY_ATTACK_MULT * MAX_CHARGE
    return max(MIN_DAMAGE, raw - max(armour, 0.0))


def level_threshold(level: int) -> int:
    if level <= 1:
        return 0
    l = level - 1
    return 10 * l + 5 * l * l


# --- what a fight costs and pays ----------------------------------------------------------

def loot_value(table_id: str, tables: dict, items: dict) -> float:
    """Expected marks from one roll of a loot table, counting items at their own value."""
    t = tables.get(table_id)
    if not t:
        return 0.0
    entries = t.get("entries", [])
    total_weight = sum(float(e.get("weight", 1)) for e in entries) or 1.0
    per_roll = 0.0
    for e in entries:
        share = float(e.get("weight", 1)) / total_weight
        if "marks" in e:
            lo, hi = e["marks"] if isinstance(e["marks"], list) else (e["marks"], e["marks"])
            per_roll += share * (lo + hi) / 2.0
        elif "item" in e:
            count = e.get("count", 1)
            lo, hi = count if isinstance(count, list) else (count, count)
            value = float(items.get(e["item"], {}).get("value", 0))
            per_roll += share * value * (lo + hi) / 2.0
    rolls = t.get("rolls", [1, 1])
    lo, hi = rolls if isinstance(rolls, list) else (rolls, rolls)
    return per_roll * (lo + hi) / 2.0


def enemy_rows(enemies: list, tables: dict, items: dict, vigour: int) -> list:
    player_hp = hp_max(vigour)
    rows = []
    for e in enemies:
        stats = e.get("stats", {})
        hp = float(stats.get("hp", 1))
        armour = float(stats.get("armour", 0))
        attacks = e.get("attacks", [])
        if not attacks:
            continue
        # A weighted hit, the way the brain picks: each attack by its own weight.
        w = sum(float(a.get("weight", 1)) for a in attacks) or 1.0
        avg_dmg = sum(float(a.get("damage", 0)) * float(a.get("weight", 1)) for a in attacks) / w
        worst = max(float(a.get("damage", 0)) for a in attacks)
        blows = {name: hit(base, sk, armour) for name, base, sk in LOADOUTS}
        marks = e.get("marks", [0, 0])
        lo, hi = marks if isinstance(marks, list) else (marks, marks)
        pay = (lo + hi) / 2.0 + loot_value(str(e.get("loot", "")), tables, items)
        rows.append({
            "id": e.get("id", ""),
            "name": e.get("name", ""),
            "region": e.get("region", ""),
            "hp": hp,
            "armour": armour,
            "hits": {name: hp / blow for name, blow in blows.items()},
            "immune_to": [name for name, base, sk in LOADOUTS
                          if base * skill_mult(sk) - armour <= MIN_DAMAGE],
            "hits_to_kill_you": player_hp / max(avg_dmg, 0.01),
            "worst_hit_share": worst / player_hp,
            "pay": pay,
        })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--vigour", type=int, default=10, help="the player's Vigour")
    ap.add_argument("--skill", type=float, default=20.0, help="the player's weapon skill")
    a = ap.parse_args()

    items = by_id(load("items"))
    tables = by_id(load("loot"))
    regions = load("regions")
    enemies = load("enemies")
    bosses = load("bosses")
    rows = enemy_rows(enemies, tables, items, a.vigour)
    player_hp = hp_max(a.vigour)

    print("A player with Vigour %d (%.0f health), at three points in a career:" % (a.vigour, player_hp))
    for name, base, sk in LOADOUTS:
        print("  %-6s weapon %.0f, skill %.0f" % (name, base, sk))
    print()

    print("DIFFICULTY, by region, in the order the world puts them")
    print("  %-13s %-6s %5s %6s  %-26s %s"
          % ("region", "danger", "kinds", "marks", "hits to kill it (start/mid/late)",
             "hits to kill you"))
    for r in sorted(regions, key=lambda d: d.get("danger", 0)):
        here = [x for x in rows if x["region"] == r["id"]]
        if not here:
            continue
        cols = "/".join("%.0f" % statistics.mean(x["hits"][name] for x in here)
                        for name, _b, _s in LOADOUTS)
        d = statistics.mean(x["hits_to_kill_you"] for x in here)
        pay = statistics.mean(x["pay"] for x in here)
        immune = sorted({name for x in here for name in x["immune_to"]})
        note = ""
        if immune:
            note = "   %s gear cannot hurt %d of them" % ("/".join(immune),
                   sum(1 for x in here if x["immune_to"]))
        print("  %-13s %-6d %5d %6.0f  %-26s %.1f%s"
              % (r["id"].split("/")[-1], r.get("danger", 0), len(here), pay, cols, d, note))

    print("\n  The hardest single hit in each region, as a share of your health:")
    for r in sorted(regions, key=lambda d: d.get("danger", 0)):
        here = [x for x in rows if x["region"] == r["id"]]
        if not here:
            continue
        worst = max(here, key=lambda x: x["worst_hit_share"])
        print("    %-14s %-28s %3.0f%%%s" % (r["id"].split("/")[-1], worst["name"],
              worst["worst_hit_share"] * 100.0,
              "   <- one hit kills you" if worst["worst_hit_share"] >= 1.0 else ""))

    print("\nBOSSES  (hits to kill, at start / mid / late gear)")
    for b in sorted(bosses, key=lambda d: float(d.get("stats", {}).get("hp", 0))):
        stats = b.get("stats", {})
        hp = float(stats.get("hp", 0))
        armour = float(stats.get("armour", 0))
        light = "/".join("%.0f" % (hp / hit(base, sk, armour)) for _n, base, sk in LOADOUTS)
        heavy = "/".join("%.0f" % (hp / hit(base, sk, armour, True)) for _n, base, sk in LOADOUTS)
        atks = [float(x.get("damage", 0)) for p in b.get("phases", [{}])
                for x in p.get("attacks", b.get("attacks", []))] or [0.0]
        print("  %-28s %5.0f hp  armour %2.0f  light %-14s heavy %-11s worst hit %3.0f%%"
              % (b.get("name", ""), hp, armour, light, heavy,
                 max(atks) / player_hp * 100.0))
    best_weapon = max(float(i.get("weapon", {}).get("damage", 0)) for i in items.values())
    hardest = max(bosses, key=lambda d: float(d.get("stats", {}).get("armour", 0)))
    hard_armour = float(hardest.get("stats", {}).get("armour", 0))
    light_blow = hit(best_weapon, 85.0, hard_armour)
    heavy_blow = hit(best_weapon, 85.0, hard_armour, True)
    print("\n  Armour is subtracted flat, before anything else, so it decides late fights more"
          "\n  than anything else in the model. Against %s's %.0f armour the best weapon in"
          "\n  Wickmere (%.0f damage) lands %.1f as a light and %.1f as a fully charged heavy,"
          "\n  a %.1f-fold spread. At mid gear the same boss is %s light hits and %s heavy ones."
          % (hardest.get("name", ""), hard_armour, best_weapon, light_blow, heavy_blow,
             heavy_blow / light_blow,
             "%.0f" % (float(hardest["stats"]["hp"]) / hit(18.0, 50.0, hard_armour)),
             "%.0f" % (float(hardest["stats"]["hp"]) / hit(18.0, 50.0, hard_armour, True))))

    # --- the economy ----------------------------------------------------------------------
    print("\nECONOMY: what things cost, in fights")
    vale = [x for x in rows if x["region"].endswith("hearthvale")]
    per_fight = statistics.mean(x["pay"] for x in vale) if vale else 1.0
    print("  A Hearthvale fight pays about %.0f marks.\n" % per_fight)
    wants = {}
    for i in items.values():
        prop = i.get("property", {})
        if prop:
            wants["a house: " + str(prop.get("name", ""))] = int(prop.get("price", 0))
    for i in sorted(items.values(), key=lambda d: -float(d.get("value", 0))):
        if i.get("property"):
            continue
        if len(wants) > 11:
            break
        wants[str(i.get("name", ""))] = int(i.get("value", 0))
    for label, price in sorted(wants.items(), key=lambda kv: -kv[1]):
        if price <= 0:
            continue
        print("  %-36s %6d marks %6.0f fights" % (label[:36], price,
                                                  price / max(per_fight, 1.0)))

    # --- progression ----------------------------------------------------------------------
    print("\nPROGRESSION: skill gains needed for each character level")
    print("  %-7s %-10s %s" % ("level", "gains", "at ~1 gain a fight"))
    for lvl in [2, 3, 5, 8, 12, 20]:
        t = level_threshold(lvl)
        print("  %-7d %-10d %.0f fights" % (lvl, t, t))
    print("\n  Read this as a shape, not a schedule. It cannot tell you how long a fight takes,")
    print("  whether the Vale has enough bandits in it, or whether any of it is any fun.")

    # --- what the shape says ---------------------------------------------------------------
    print("\nWHAT THE CURVES SAY")
    ordered = [r for r in sorted(regions, key=lambda d: d.get("danger", 0))
               if any(x["region"] == r["id"] for x in rows)]
    said = 0

    def region_stat(r, key):
        here = [x for x in rows if x["region"] == r["id"]]
        return statistics.mean(x[key] for x in here)

    # Danger should mean danger, and later should mean richer.
    danger = [(r["id"].split("/")[-1], region_stat(r, "hits_to_kill_you")) for r in ordered]
    for (an, a_), (bn, b_) in zip(danger, danger[1:]):
        if b_ > a_ + 0.5:
            said += 1
            print("  * %s is SAFER than %s (%.1f hits to kill you against %.1f), though the"
                  % (bn, an, b_, a_))
            print("    world puts it later. A danger rating is a promise to the player." )
    pay = [(r["id"].split("/")[-1],
            statistics.mean(x["pay"] for x in rows if x["region"] == r["id"])) for r in ordered]
    for (an, a_), (bn, b_) in zip(pay, pay[1:]):
        if b_ < a_ * 0.9:
            said += 1
            print("  * %s pays LESS than %s (%.0f marks a fight against %.0f) for a more"
                  % (bn, an, b_, a_))
            print("    dangerous fight. Nothing in the design asks for that." )

    # Flat armour against the best weapon in the game.
    best = max(float(i.get("weapon", {}).get("damage", 0)) for i in items.values())
    for b in bosses:
        armour = float(b.get("stats", {}).get("armour", 0))
        light = hit(best, 85.0, armour)
        heavy = hit(best, 85.0, armour, True)
        if light > 0 and heavy / light >= 3.5:
            said += 1
            print("  * %s: the best weapon in Wickmere does %.1f as a light and %.1f as a"
                  % (b.get("name", ""), light, heavy))
            print("    charged heavy — %.0f times. Flat armour has taken the choice away."
                  % (heavy / light))
    if said == 0:
        print("  Nothing out of shape.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
