#!/usr/bin/env python3
"""Quest softlocks, found in the content before a player finds them (triage 77-79).

A softlock is a quest that can no longer be finished although nothing says it failed: the Mage's
braziers lit from too near (the objective unmoved, nothing left to light), the Rogue seen by the
watch with no way back. QuestWalk (game/systems/quests/quest_walk.gd) asks whether the thing each
objective waits for exists in the game; this asks whether a player can spoil it on the way. Each
check is a class of bug that has happened, or the guard the game now relies on to stop it:

  unseen       a stage's `unseen` (NightWatch) names a `fail_stage` that is a `detour` stage whose
               objective sends the quest back to the watched stage; seen, the try fails, and is
               never stuck.
  detour       a `detour` stage is sent to by something (a `fail_stage`, a quest_stage effect), and
               leaves again (an on_complete quest_stage, or its objective's line does).
  consumed     an `act` on a prop the act uses up (a brazier lit, a strongbox picked) has enough
               props for the stage's counts, and one with a condition that can refuse the act
               (`min_range`, `in_turn`, `prop`) says why with `refused` (QuestLog undoes the act).
  supply       an `act` whose doing uses up an item the player carries (an arrow, a lockpick)
               says how the teacher hands more (`supply`), so running out is not the end.
  gone         nobody an objective needs (talk, deliver, escort, a choice's `with`) is taken out
               of the world (`gone_when`) while that stage is open.
  choice       a choice has at least one option without conditions.
  waits        a stage with no objectives that is not `auto` is moved on by something.
  topic        a `talk` objective's `topic` is a node of the person's dialogue that a line leads to.

    python3 tools/quests/softlock_check.py            # every finding, exit 1 if any
    python3 tools/quests/softlock_check.py --json     # the same as JSON

tools/tests/test_quest_softlocks.py runs it in the suite.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from typing import Any, Iterable

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACK = os.path.join(ROOT, "game", "content", "packs", "core")

# acts that use their prop up: the prop kind they are done to
CONSUMING_ACTS = {"kindle": "brazier", "pick_lock": "strongbox"}
# acts whose doing uses up something carried
SPENDING_ACTS = {"arrow_hit": "arrows", "pick_lock": "lockpicks"}
# objective fields that can refuse an act the objective is otherwise about
REFUSING = ("min_range", "in_turn", "prop")


def _load(pattern: str) -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []
    for path in sorted(glob.glob(os.path.join(PACK, pattern))):
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        rows = data if isinstance(data, list) else [data]
        for row in rows:
            if isinstance(row, dict) and "id" in row:
                out.append((os.path.relpath(path, ROOT), row))
    return out


def _walk(node: Any) -> Iterable[dict]:
    if isinstance(node, dict):
        yield node
        for v in node.values():
            yield from _walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v)


class Pack:
    def __init__(self) -> None:
        self.quests = [(f, q) for f, q in _load("quests/*.json") if isinstance(q.get("stages"), list)
                       and "template" not in q]
        self.npcs = {q["id"]: q for _, q in _load("npcs/*.json")}
        self.dialogues = {d["id"]: d for _, d in _load("dialogues/*.json")}
        self.all_json = [row for pattern in ("quests/*.json", "dialogues/*.json", "npcs/*.json", "*.json")
                         for _, row in _load(pattern)]
        # every quest_stage / start_quest-at / complete_quest effect anywhere in the pack
        self.sent_to: dict[str, set[str]] = {}
        self.completed_by: set[str] = set()
        self.flag_set_at: dict[str, list[tuple[str, int]]] = {}
        for row in self.all_json:
            for d in _walk(row):
                for key in ("quest_stage", "start_quest"):
                    v = d.get(key)
                    if isinstance(v, list) and len(v) >= 2:
                        self.sent_to.setdefault(str(v[0]), set()).add(str(v[1]))
                v = d.get("complete_quest")
                if v is not None:
                    self.completed_by.add(str(v[0] if isinstance(v, list) else v))
        for _, q in self.quests:
            for si, s in enumerate(q["stages"]):
                for d in _walk(s):
                    v = d.get("set_flag")
                    if v is not None:
                        flag = str(v[0] if isinstance(v, list) else v)
                        self.flag_set_at.setdefault(flag, []).append((q["id"], si))
            u = None
            for si, s in enumerate(q["stages"]):
                u = s.get("unseen")
                if isinstance(u, dict) and u.get("fail_stage"):
                    self.sent_to.setdefault(q["id"], set()).add(str(u["fail_stage"]))

    def stage_index(self, q: dict, stage: Any) -> int:
        stages = q["stages"]
        if isinstance(stage, (int, float)):
            i = int(stage) - 1
            return i if 0 <= i < len(stages) else -1
        for i, s in enumerate(stages):
            if s.get("id") == stage:
                return i
        return -1


# --- the checks --------------------------------------------------------------------------------

def check(pack: Pack) -> list[dict]:
    found: list[dict] = []

    def say(kind: str, q: dict, stage: dict | None, text: str) -> None:
        found.append({"check": kind, "quest": q["id"], "stage": (stage or {}).get("id", ""), "text": text})

    for _, q in pack.quests:
        stages: list[dict] = q["stages"]
        props: dict[str, int] = {}
        for p in q.get("props", []):
            if isinstance(p, dict):
                props[str(p.get("kind", "pell"))] = props.get(str(p.get("kind", "pell")), 0) + 1
        for si, s in enumerate(stages):
            objs = [o for o in s.get("objectives", []) if isinstance(o, dict)]
            # unseen: a fail with somewhere to go
            u = s.get("unseen")
            if isinstance(u, dict):
                fail = str(u.get("fail_stage", ""))
                fi = pack.stage_index(q, fail) if fail else -1
                if fi < 0:
                    say("unseen", q, s, "an `unseen` with no `fail_stage` (or one that is no stage): seen, the try has nowhere to go")
                else:
                    f = stages[fi]
                    if not f.get("detour"):
                        say("unseen", q, s, "its fail_stage `%s` is not a `detour`: the stage before it would walk into it in order" % fail)
                    if not f.get("objectives"):
                        say("unseen", q, s, "its fail_stage `%s` has no objective to put the try right" % fail)
                    back = [e for e in _walk(f.get("on_complete", [])) if isinstance(e.get("quest_stage"), list)
                            and pack.stage_index(q, e["quest_stage"][1]) == si]
                    if not back:
                        say("unseen", q, s, "its fail_stage `%s` does not send the quest back to `%s`" % (fail, s.get("id")))
            # detour: sent to, and leaves
            if s.get("detour"):
                if str(s.get("id")) not in pack.sent_to.get(q["id"], set()):
                    say("detour", q, s, "a `detour` nothing sends the quest to")
                leaves = any(isinstance(e.get("quest_stage"), list) for e in _walk(s.get("on_complete", [])))
                if not leaves:
                    say("detour", q, s, "a `detour` with no on_complete quest_stage: finished, it would walk on in order")
            # waits: an empty stage is moved on
            if not objs and not s.get("auto") and si < len(stages) - 1:
                later = {str(st.get("id")) for st in stages[si + 1:]} | {str(i + 1) for i in range(si + 1, len(stages))}
                if not (pack.sent_to.get(q["id"], set()) & later) and q["id"] not in pack.completed_by:
                    say("waits", q, s, "a stage with no objectives, not `auto`, and nothing sends the quest on from it")
            counts: dict[str, int] = {}
            for o in objs:
                t = str(o.get("type", ""))
                target = str(o.get("target", ""))
                if t == "act":
                    against = str(o.get("against", ""))
                    kind = CONSUMING_ACTS.get(target)
                    if kind and against == "prop:" + kind:
                        counts[kind] = counts.get(kind, 0) + max(1, int(o.get("count", 1)))
                        if any(o.get(k) for k in REFUSING) and not o.get("refused"):
                            say("consumed", q, s, "`%s` on a %s can be refused (%s) and says nothing when it is: add `refused`"
                                % (target, kind, ", ".join(k for k in REFUSING if o.get(k))))
                    spends = SPENDING_ACTS.get(target)
                    if spends and not o.get("optional") and not isinstance(o.get("supply"), dict):
                        say("supply", q, s, "`%s` spends %s and nothing hands more when they run out: add `supply`" % (target, spends))
                if t == "choice":
                    opts = o.get("options", [])
                    free = [op for op in opts if not (isinstance(op, dict) and (op.get("conditions") or op.get("requires")))]
                    if opts and not free:
                        say("choice", q, s, "every option of the choice `%s` has conditions: one unmet by all is a softlock" % target)
                if t == "talk" and o.get("topic"):
                    _check_topic(pack, q, s, target, str(o["topic"]), say)
                for npc in _people(o):
                    _check_gone(pack, q, si, s, npc, say)
            for kind, need in counts.items():
                # a lighting may count for two objectives at once (the near brazier from far off),
                # so the stage needs no more props than its largest count of either, and at most the sum
                have = props.get(kind, 0)
                most = max(max(1, int(o.get("count", 1))) for o in objs if CONSUMING_ACTS.get(str(o.get("target", ""))) == kind)
                if have < most:
                    say("consumed", q, s, "the stage asks for %d %s act(s) and the quest lays %d %s" % (most, kind, have, kind))
    return found


def _people(o: dict) -> list[str]:
    out = []
    t = str(o.get("type", ""))
    if t in ("talk", "deliver", "escort") and str(o.get("target", "")).startswith("core:npc/"):
        out.append(str(o["target"]))
    w = str(o.get("with", ""))
    if w.startswith("core:npc/"):
        out.append(w)
    return out


def _check_topic(pack: Pack, q: dict, s: dict, npc: str, topic: str, say) -> None:
    d_id = str(pack.npcs.get(npc, {}).get("dialogue", ""))
    d = pack.dialogues.get(d_id)
    if d is None:
        say("topic", q, s, "talk to %s on `%s`: %s has no dialogue" % (npc, topic, npc))
        return
    nodes = d.get("nodes", {})
    if topic not in nodes:
        say("topic", q, s, "talk to %s on `%s`: no such node in %s" % (npc, topic, d_id))
        return
    led = d.get("start") == topic or any(e.get("next") == topic or e.get("else") == topic for e in _walk(nodes))
    if not led:
        say("topic", q, s, "talk to %s on `%s`: no line in %s leads to it" % (npc, topic, d_id))


def _gone_now(pack: Pack, cond: Any, q_id: str, si: int, stage_id: str) -> bool | None:
    """Whether gone_when holds for certain while quest `q_id` is at stage `si` (True), for certain
    does not (False), or cannot be told without the rest of the game's state (None)."""
    if isinstance(cond, list):
        vals = [_gone_now(pack, c, q_id, si, stage_id) for c in cond]
        if any(v is False for v in vals):
            return False
        return True if vals and all(v is True for v in vals) else None
    if not isinstance(cond, dict):
        return None
    if "not" in cond:
        v = _gone_now(pack, cond["not"], q_id, si, stage_id)
        return None if v is None else not v
    if "any" in cond:
        vals = [_gone_now(pack, c, q_id, si, stage_id) for c in cond["any"]]
        if any(v is True for v in vals):
            return True
        return False if vals and all(v is False for v in vals) else None
    if "all" in cond:
        return _gone_now(pack, cond["all"], q_id, si, stage_id)
    if "quest_at" in cond:
        qq, st = cond["quest_at"][0], cond["quest_at"][1]
        if qq != q_id:
            return None
        return st == stage_id or (isinstance(st, (int, float)) and int(st) - 1 == si)
    if "flag" in cond:
        # a flag this quest raises only in a later stage is down now
        sets = pack.flag_set_at.get(str(cond["flag"]), [])
        if sets and all(qq == q_id and at > si for qq, at in sets):
            return False
        return None
    return None


def _check_gone(pack: Pack, q: dict, si: int, s: dict, npc: str, say) -> None:
    gone = pack.npcs.get(npc, {}).get("gone_when")
    if not gone:
        return
    if _gone_now(pack, gone, q["id"], si, str(s.get("id"))) is True:
        say("gone", q, s, "%s is taken out of the world (gone_when) while this stage needs them" % npc)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    pack = Pack()
    found = check(pack)
    if args.json:
        print(json.dumps(found, indent=1))
    else:
        for f in found:
            print("SOFTLOCK %-9s %s / %s: %s" % (f["check"], f["quest"], f["stage"], f["text"]))
        print("%d quests, %d finding(s)" % (len(pack.quests), len(found)))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
