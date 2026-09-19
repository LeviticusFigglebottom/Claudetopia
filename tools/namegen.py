#!/usr/bin/env python3
"""Naming-language generator for Wickmere (rules in WORLD_BIBLE.md §5).

  tools/namegen.py --lang valish --kind place --n 12 --seed 3
  tools/namegen.py --lang oroth --kind place --n 8
  tools/namegen.py --check            # scan content JSON for banned real-world names and duplicates
Languages: valish, oroth, skerrish, sedgish. Kinds: place, person.
"""
import argparse, json, os, random, re, sys

VALISH_ROOTS = ["merrow", "hollin", "tam", "wyn", "cad", "brae", "thorn", "ash", "penny", "gos", "lark", "fenn", "hare", "mull", "cress", "bram", "elder", "fallow", "rook", "bell", "wick", "hazel", "orm", "sedge"]
VALISH_SUFFIX = ["by", "wick", "combe", "mere", "stead", "ford", "well", "bourne", "down", "hithe", "fold", "hollow", "cross", "barrow"]
VALISH_FIRST = ["Wren", "Osric", "Maud", "Tobin", "Hesk", "Ansel", "Bram", "Elsie", "Corin", "Ada", "Tam", "Nell", "Pell", "Ivo", "Rosalind", "Gil", "Hob", "Marigold", "Edric", "Tansy", "Jory", "Bea", "Aldous", "Lettie", "Wat", "Cille", "Fenwick", "Dorrie", "Barnaby", "Sorrel"]
VALISH_SURNAME_TRADE = ["Miller", "Tallow", "Brambling", "Ashdown", "Pennywort", "Cresswell", "Thatcher", "Cooper", "Fletcher", "Ropewalk", "Hollins", "Larkin", "Merriweather", "Goslin", "Fennick", "Mullard", "Bellhanger", "Orchard", "Cidery", "Rooke"]
VALISH_FEM = ["a", "ie", "el", "ow"]
VALISH_MASC = ["am", "ick", "ard", "en"]

OROTH_ONSET = ["", "v", "l", "r", "m", "n", "s", "th", "h", "c", "d"]
OROTH_NUC = ["a", "e", "i", "o", "ae", "io", "ei", "ou"]
OROTH_ENDS = ["eth", "ar", "ion", "ael", "ost", "el", "or", "ith"]
OROTH_WORDS = {"oroth": "the note", "vael": "kept", "hesk": "silence", "isse": "water", "cantor": "holder", "thael": "door", "morn": "stone", "anthe": "choir", "sul": "light", "ondr": "deep"}

SKERR_ON = ["Kh", "Br", "Dr", "Gh", "Sk", "R", "Osk", "Ush", "T", "Br", "K", "Dun", "Ghal", "Orr", "Skerr"]
SKERR_MID = ["a", "o", "u", "ar", "or", "ur"]
SKERR_CODA = ["rr", "dd", "gh", "kh", "nn", "ld", "sk", "n", "k", "th"]
SKERR_PLACE_END = ["ow", "crag", "eld", "gate", "fell", "hold", "moor"]
SKERR_CLANS = ["Dreugh", "Kharrow", "Oskel", "Brindle", "Ghast", "Rudd", "Skarl"]

SEDG_ON = ["", "l", "s", "n", "m", "t", "v", "ss", "ll"]
SEDG_NUC = ["a", "i", "e", "o", "au", "ia", "ee", "oa"]
SEDG_PLACE_END = ["eva", "oul", "issa", "nauve", "issane", "ea"]

BANNED = ["london", "paris", "rome", "york", "jerusalem", "babylon", "thor", "odin", "zeus", "jesus", "allah", "krishna", "buddha", "loki", "freya", "athena", "apollo", "hel", "valhalla", "avalon", "camelot", "arthur", "merlin", "gondor", "mordor", "hyrule", "tamriel", "skyrim", "albion", "lordran", "anor", "izalith", "whiterun", "bowerstone", "oakvale", "morrowind", "cyrodiil", "hogwarts", "narnia", "westeros", "winterfell", "edinburgh", "dublin", "cardiff", "glasgow", "oxford", "cambridge"]


def cap(s: str) -> str:
    return s[:1].upper() + s[1:]


def valish(rng: random.Random, kind: str) -> str:
    if kind == "place":
        root = rng.choice(VALISH_ROOTS)
        suf = rng.choice(VALISH_SUFFIX)
        if root.endswith(suf[0]):
            suf = suf[1:]
        return cap(root + suf)
    first = rng.choice(VALISH_FIRST)
    if rng.random() < 0.3:
        stem = rng.choice(["Ros", "Hal", "Wil", "Mer", "Tor", "Bel", "Cal", "Lin"])
        first = stem + rng.choice(VALISH_FEM + VALISH_MASC)
    return f"{first} {rng.choice(VALISH_SURNAME_TRADE)}"


def oroth(rng: random.Random, kind: str) -> str:
    if kind == "place" and rng.random() < 0.4:
        a, b = rng.sample(list(OROTH_WORDS), 2)
        return f"{cap(a)}-{cap(b)}"
    syl = rng.randint(1, 2)
    parts = []
    last_onset = None
    for _ in range(syl):
        onset = rng.choice([o for o in OROTH_ONSET if o != last_onset and o != ""] + [""])
        nuc = rng.choice(OROTH_NUC[:4]) if rng.random() < 0.8 else rng.choice(OROTH_NUC[4:])
        parts.append(onset + nuc)
        last_onset = onset
    w = "".join(parts) + rng.choice(OROTH_ENDS)
    w = re.sub(r"([aeiou])\1", r"\1", w)
    w = re.sub(r"[aeiou]{3,}", lambda m: m.group(0)[:2], w)
    return cap(w)


def skerrish(rng: random.Random, kind: str) -> str:
    stem = rng.choice(SKERR_ON) + rng.choice(SKERR_MID) + rng.choice(SKERR_CODA)
    if kind == "place":
        return cap(stem.lower()) + rng.choice(SKERR_PLACE_END)
    given = cap(stem.lower())
    return f"{given} ko-{rng.choice(SKERR_CLANS)}"


def sedgish(rng: random.Random, kind: str) -> str:
    syl = rng.randint(1, 2)
    parts = []
    for i in range(syl):
        onset = rng.choice(SEDG_ON[1:]) if i > 0 or rng.random() < 0.6 else ""
        nuc = rng.choice(SEDG_NUC[:4]) if rng.random() < 0.8 else rng.choice(SEDG_NUC[4:])
        parts.append(onset + nuc)
    w = "".join(parts)
    w = re.sub(r"[aeiou]{3,}", lambda m: m.group(0)[:2], w)
    if kind == "place":
        end = rng.choice(SEDG_PLACE_END)
        if w[-1] in "aeiou" and end[0] in "aeiou":
            w = w[:-1]
        return cap(w + end)
    if rng.random() < 0.15:
        w = w[:2] + "'" + w[2:]  # the drowned
    second = rng.choice(["Tal", "Mor", "Lissa", "Nauve", "Sa", "Oul"])
    return f"{cap(w)} {second}"


GENS = {"valish": valish, "oroth": oroth, "skerrish": skerrish, "sedgish": sedgish}


def check(root: str) -> int:
    names = {}
    problems = 0
    for dirpath, _, files in os.walk(root):
        for f in files:
            if not f.endswith(".json"):
                continue
            p = os.path.join(dirpath, f)
            try:
                data = json.load(open(p))
            except Exception as e:
                print(f"{p}: JSON error {e}"); problems += 1; continue
            entries = data if isinstance(data, list) else [data]
            for e in entries:
                if not isinstance(e, dict):
                    continue
                n = e.get("name") or e.get("title")
                if not n:
                    continue
                low = n.lower()
                for b in BANNED:
                    if re.search(rf"\b{b}\b", low):
                        print(f"{p}: '{n}' contains banned real-world name '{b}'"); problems += 1
                t = e.get("id", "?").split(":")[1].split("/")[0] if ":" in e.get("id", "") else "?"
                key = (t, low)
                if key in names and names[key] != e.get("id"):
                    print(f"{p}: duplicate {t} name '{n}' ({names[key]} and {e.get('id')})"); problems += 1
                names[key] = e.get("id")
    print(f"checked {len(names)} names, {problems} problems")
    return 1 if problems else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", choices=GENS, default="valish")
    ap.add_argument("--kind", choices=["place", "person"], default="place")
    ap.add_argument("--n", type=int, default=10)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--root", default=os.path.join(os.path.dirname(__file__), "..", "game", "content", "packs"))
    a = ap.parse_args()
    if a.check:
        return check(a.root)
    rng = random.Random(a.seed)
    seen = set()
    while len(seen) < a.n:
        seen.add(GENS[a.lang](rng, a.kind))
    for n in sorted(seen):
        print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
