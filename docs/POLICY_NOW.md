# Policy from the user, 2026-09-25 ~18:00 UTC (supersedes the landing checks in AGENT_RULES and HANDOFF §7 until further notice)
- The full checks are suspended. Do NOT run the full `./run.sh test`, journey, flow, quests (the quest walker) or the §7 chain. Cancel any of those you have queued, and remove your gate tickets for them.
- Run only targeted tests for what you change (`--filter=`, single pytest files), plus the captures you need to LOOK at your work. Looking at your output is still required.
- The machine's capacity goes to building. MAX_HEAVY stays 4. Short targeted runs take GATE_PRIORITY=1.
- Commit each finished piece as soon as it is done, and tell the coordinator its head in a message of two or three lines. No long reports. The coordinator merges finished work into main straight away, checked only by an import.
- Keep merging the session branch (claude/gifted-brahmagupta-29u39r, the same as main) into your wip branch, so conflicts stay small.
- One full main check runs at the end, after every workflow is complete. Leave your branch clean for it.
