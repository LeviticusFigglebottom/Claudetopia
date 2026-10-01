"""The quest softlock checker (tools/quests/softlock_check.py): the pack is clean, and each check
catches the bug it is for when the pack is spoilt the way a player once found it spoilt."""
import copy
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "quests"))
import softlock_check as sc  # noqa: E402

PACK = sc.Pack()


def _quest(pack, qid):
    for _, q in pack.quests:
        if q["id"] == qid:
            return q
    raise KeyError(qid)


def _stage(q, sid):
    return next(s for s in q["stages"] if s["id"] == sid)


def _spoilt():
    return copy.deepcopy(PACK)


def _checks(pack, qid):
    return {f["check"] for f in sc.check(pack) if f["quest"] == qid}


def test_the_pack_has_no_softlocks():
    found = sc.check(PACK)
    assert found == [], "\n".join("%(check)s %(quest)s/%(stage)s: %(text)s" % f for f in found)


def test_the_pack_is_read_whole():
    ids = {q["id"] for _, q in PACK.quests}
    for qid in ("core:quest/first_mage", "core:quest/first_rogue", "core:quest/first_warrior", "core:quest/first_ranger"):
        assert qid in ids
    assert len(ids) > 100


def test_a_watch_with_no_fail_stage_is_a_softlock():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_rogue")
    del _stage(q, "the_traps")["unseen"]["fail_stage"]
    assert "unseen" in _checks(pack, q["id"])


def test_a_fail_stage_walked_into_in_order_is_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_rogue")
    del _stage(q, "seen")["detour"]
    assert "unseen" in _checks(pack, q["id"])


def test_a_detour_that_never_comes_back_is_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_rogue")
    _stage(q, "seen")["on_complete"] = []
    found = _checks(pack, q["id"])
    assert "unseen" in found and "detour" in found


def test_a_refusable_lighting_that_says_nothing_is_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_mage")
    for o in _stage(q, "the_braziers")["objectives"]:
        o.pop("refused", None)
    assert "consumed" in _checks(pack, q["id"])


def test_too_few_braziers_for_the_lesson_is_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_mage")
    q["props"] = [p for p in q["props"] if p["name"] != "brazier_far"][:1]
    assert "consumed" in _checks(pack, q["id"])


def test_arrows_with_nobody_to_hand_more_are_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_ranger")
    for o in _stage(q, "the_butts")["objectives"]:
        o.pop("supply", None)
    assert "supply" in _checks(pack, q["id"])


def test_somebody_gone_while_their_stage_is_open_is_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_rogue")
    # the collector gone through the strongbox stage, where his pocket is picked (a `talk` to him
    # stands in for any objective that needs him)
    pack.npcs["core:npc/tithe_collector"]["gone_when"] = [{"quest_at": ["core:quest/first_rogue", "the_strongbox"]}]
    _stage(q, "the_strongbox")["objectives"].append({"type": "talk", "target": "core:npc/tithe_collector"})
    assert "gone" in _checks(pack, q["id"])


def test_a_choice_with_no_open_option_is_found():
    pack = _spoilt()
    for _, q in pack.quests:
        for s in q["stages"]:
            for o in s.get("objectives", []):
                if o.get("type") == "choice" and o.get("options"):
                    o["options"] = [{"id": str(op.get("id") if isinstance(op, dict) else op), "conditions": [{"flag": "never"}]}
                                    for op in o["options"]]
                    assert "choice" in _checks(pack, q["id"])
                    return
    raise AssertionError("no choice in the pack")


def test_a_stage_nothing_moves_on_is_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_mage")
    s = _stage(q, "the_racks")
    s["objectives"] = []
    s.pop("auto", None)
    assert "waits" in _checks(pack, q["id"])


def test_a_topic_no_line_leads_to_is_found():
    pack = _spoilt()
    q = _quest(pack, "core:quest/first_rogue")
    _stage(q, "seen")["objectives"][0]["topic"] = "no_such_node"
    assert "topic" in _checks(pack, q["id"])
