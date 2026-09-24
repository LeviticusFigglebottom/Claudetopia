# systems/combat

Stamina-driven, committed melee, ranged and magic combat. Formulas are DESIGN.md §5.3 and are
normative; everything tunable is content, everything pure is a `static func`.

## Pieces

| File | Role |
|---|---|
| `damage_model.gd` | `DamageModel`: all pure formulas and constants (damage, crits, resists, block, poise, stamina costs, parry window, input buffer, dodge/i-frame tables by load, facing/backstab tests). No state. |
| `hit_data.gd` | `HitData`: one hit in flight (amount, kind, poise, crit, knockdown, statuses, attacker, origin). Copied per swing. |
| `hitbox.gd` / `hurtbox.gd` | `Hitbox` (layer `hitbox`) opens on `hit_start` and closes on `hit_end`, hitting each `Hurtbox` (layer `hurtbox`) **once per swing**. `Hurtbox` forwards to `Actor.take_hit()`. |
| `weapon_instance.gd` | `WeaponInstance`: reads an item's `weapon` block, owns the hitbox sized by `reach`, maps attacks to CONTRACTS §3 clip names, supplies per-attack timing and builds the `HitData`. |
| `stamina_component.gd` | Pool, costs, sprint drain, 30/s regen after 0.8 s (halved while blocking). |
| `poise_component.gd` | Poise damage, 4/s regen after 1.5 s, stagger at 0 (then resets), hyper-armour threshold. |
| `status_effects.gd` | burning, chilled, webbed, bleeding, poisoned, silenced, quieted, stagger, knockdown, warded — durations, ticks and stacking rules in one `RULES` table. |
| `enemy_abilities.gd` | `EnemyAbilities`: the pure decisions behind the bestiary's special behaviours and the boss fights — whether a voice attack may be used, how much a cutpurse takes, what a lure does this frame, whether greed has roused a guardian, when a duelist presses its guard, which limb comes off next, what breaks a held note, how wide a shockwave reaches, whether a combo's second beat may be thrown, how many lights a renown tier keeps burning. No state, no nodes; `Enemy` and `BossArena` do the acting. |
| `../actors/enemy/boss_arena.gd` | `BossArena`: the fog gate, and the floor of the fight. `radius`/`shrink()` hold the player to a piece of ground and put whoever leaves it in the thorns; `light_by_renown()` puts the room out except for the few lamps their renown keeps burning, and `lit_at()` answers whether a point is standing in one. `for_boss()` finds a placed arena or improvises one around the boss. |
| `projectile.gd`, `arrow.tscn` | Swept-ray kinematic projectile with a gravity arc; arrows stick into geometry, bolts vanish. |
| `spell_runtime.gd` | Pure spell rules: cost and cast time by skill, silence check, whether the saying has been taught, school → skill and damage kind, effect → `HitData`. |
| `spell_caster.gd` | Runtime casting: mana pool, cast timer, and the five implemented cast types (`projectile`, `self`, `aura`, `target`, `summon`). `known_lookup` asks whether this caster was ever taught the saying; unset means yes, which is what an enemy's own def wants. |
| `impact.gd`, `impact_fx.gd`, `weapon_trail.gd` | How a blow lands for the eye and the ear, never the numbers: `Impact.land` (from `Actor.take_hit`) holds both bodies' pictures a few frames (`HumanoidModel.hit_stop`, 0.035-0.115 s by the weapon's weight; the AnimationDriver's timeline does not move), kicks the camera (`CameraRig.shake`), throws sparks, dust, chips, splinters or blood and a stain (`ImpactFx`), and lays `impact_edge` / `impact_weight` over the material's sound. `Impact.trail` streaks a heavy swing while its blow is live. A heavy's knockback comes from `Impact.knockback_for`. Settings: accessibility.hit_pause, accessibility.camera_shake, accessibility.reduce_flashing, gameplay.blood. |
| `lock_on.gd` | Targeting service: best target in a 30 m cone, cycling left/right with wrap, drops dead or distant targets. |

Actors live in `actors/`: `actors/shared/actor.gd` (the base that owns these components and
resolves hits), `actors/player/`, `actors/enemy/`.

## Data it reads

* `item` defs — `weapon{class, damage, poise_damage, stamina_light, stamina_heavy, speed, reach,
  clips_set, parry, stability}`, `armour{slot, armour, weight_class, stability, parry?}`, plus
  `ranged{draw_time, speed, ammo_tag, ammo_item}` on bows and `projectile{scene, damage, kind,
  poise_damage, gravity}` on ammo.
* `enemy` defs — `stats`, `attacks[{name, clip, damage, poise_damage, range, min_range?,
  hit_range?, telegraph, hit_window, recovery, cooldown, weight, knockdown?, statuses?, kind?}]`,
  `perception`, `behaviour`, `loot`, `marks`, `limbs[]`, `phases[]` for bosses.
  An attack's `kind` is one of `charge` (run them down), `leap` (a charge with `leap_up` metres
  per second of lift: the weaver's drop), `burst` (everything inside `radius` at once: the
  scree-hag's shriek, the bell-bearer's toll), `projectile` (`speed`, `gravity`, `sticks`,
  `projectile_colour`: an arrow, a thrown stone, a sung note), `spell` (`spell` is a spell id,
  cast through `SpellCaster`), or absent for an ordinary swing. An attack may also carry
  `voice: true` (refused while the attacker is `silenced`), `steal{marks:[min,max], share?}`
  (cuts the player's purse and adds it to what the body drops) and `drain_stamina`/`drain_heal`.
  `behaviour` adds `lure{lure_distance, lure_break, lure_patience, lure_speed}` (a wisp keeps its
  distance while you follow), `guards{radius, wrath}` (a sentinel roused by looting near its
  post), `parries{parry_chance, parry_delay, guard_stability}` (an elite that guards between its
  own swings) and `flee_after_steal`/`flee_time`. `limbs[{name, breaks_at, damage,
  remove_attacks[], add_attacks[], poise_loss, speed_mult, say}]` come off one at a time —
  when the creature's poise breaks (`breaks_at: "poise"`, the default) or once it has taken
  `damage` since the last one went (`breaks_at: "damage"`) — and a phase change re-applies
  them, so nothing grows back.
* `boss` defs — everything an `enemy` def has, plus `arena` (the place it is fought in), `drops`
  (unique items handed over on death, guaranteed, never rolled), `resists` and
  `phases[{name, hp, say, attacks[], engage_range, circle, aggression, hyper_armour,
  retreat_threshold, speed, renown_lights_arena}]`. Boss attacks add `channel` (seconds held:
  it pulses every `channel_tick`, heals `heals_self` spread evenly across those pulses, and is
  cut short by a silence when it is a `voice` note or by `interrupt_damage` when it is
  `interruptible`), `shockwave` (metres of radial follow-through at `shockwave_share` of the
  blow that threw it), `arena_wide` (the radius is the arena's), `combo_from`/`combo_window`
  (may only be thrown after a named other attack), `shrinks_arena` (metres of floor taken and
  kept), `spares_lit` (the share of the damage that lands on anyone standing in a surviving
  light) and `summons{enemy, count, radius, cap}`.
* `spell` defs — `{school, cast_type, cost, cast_time, range, speed, radius, duration, effects[]}`
  Who may cast one is not in the def: the player's `SpellCaster.known_lookup` asks the
  `progression` node, so `can_cast` refuses with `"not_known"` whatever put the id in the slot.
  A staff's `casting{school, power_mult}` lends its power to sayings of that school.
  with effect types `damage`, `status`, `heal`, `shield`, `cleanse`.

Weapon and attack timing is placeholder-generated from `speed` and the attack's telegraph until
the forge ships clips with real `hit_start`/`hit_end` events; the event names are identical, so
nothing above `AnimationDriver` changes when the real model arrives.

## Signals

Emits on `EventBus`: `damage_dealt(attacker, victim, amount, kind)`, `entity_killed(victim,
killer, enemy_id)`, `status_applied(target, effect_id)`, `skill_used(skill_id, xp)`,
`player_spawned`, `player_died(position)`, `boss_started/boss_defeated(boss_id)`,
`detection_changed(observer, level)`, `notify(text, kind)`.

Consumes: `EventBus.hearthstone_rested(id)` — non-boss enemies reset to their spawn.

Local signals worth connecting to: `Actor.health_changed/stats_changed/died/hit_taken/staggered/
knocked_down/riposte_opened`, `Player.state_changed/lock_on_changed/attack_started/dodge_started`,
`Enemy.telegraph/attack_launched/phase_changed/limb_broken/summoned/channel_started/
channel_pulse/channel_ended/mark_dropped`, `BossArena.arena_entered/arena_cleared/bound_changed/
lights_dimmed`, `Interactor.prompt_changed`.

## Save

Combat has no save section of its own; it saves **via actors**. `Actor.to_save()` writes health,
position, yaw, dead flag and active statuses. `Player` adds name, level, attributes, stamina and
mana pools, equipped items, quick slots, skills and arrows, and registers itself under the
`player` section (`save_summary()` feeds the slot list). `Enemy.to_save()` adds its def id, brain
state, post and boss phase. Death, respawn and the Echo belong to `systems/hearth`: combat only
emits `EventBus.player_died(position)` and implements `full_restore()` / `respawn(pos, yaw)`.

## Running it

```
./run.sh test                                   # unit tests, content validation included
./run.sh test --filter=test_combat_design       # DESIGN §5.3 measured: grep MEASURE for the table
./run.sh fights [--calling=cragborn] [--only=pack,boss] [--trace=boss]
godot --path game -- --arena                    # play the flat test arena
xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
  --audio-driver Dummy -- --arena --verify --out=$PWD/captures/arena
```

`./run.sh fights` (`tests/arena/fights.gd`) is a scripted level-1 player of each starting
Calling against one foe of every archetype, headless, at a fixed 60 fps and a seeded RNG, so a
run repeats exactly and a change can be measured against the run before it. It prints a row
per fight (outcome, seconds, blows taken, damage taken, hits of swings, damage per hit, foe
health left) and a CHECK per promise (telegraphs, lock-on, parry inside and outside the window,
i-frames, stagger, the fight being heard); a failed check exits 1, a lost fight does not.
`--trace=<archetype>` prints where everybody is twice a second.

The driver keeps the time: every clip's gameplay events fire off `AnimationDriver`'s own
timeline (the caller's timing, else the rig's sidecar), and the forged rig is stretched so its
blow lands where the timeline says. A swing is live between `hit_start` and `hit_end` in a band
from shin to crown (`Hitbox.set_swing`); knockback is metres (`Actor.SHOVE_DECEL`).

The last line is the scripted verification (`tests/arena/arena_verify.gd`), 16 checks driven
through real input actions: an attack damages a bandit; stamina drains 18 and regenerates; a
parry opens a riposte and the riposte triples damage; dodge i-frames deny a hit that lands once
the roll ends; a raised shield cuts damage and costs stamina; an enemy staggers at zero poise;
a cast costs mana, lands its bolt, and is refused outright while silenced; the bow draws and
looses an arrow that damages its target; the player mantles a low ledge; a signpost shows an
interaction prompt that clears when you walk away; the wolf pack takes separate bearings; the
bristleback telegraphs, charges and knocks the player down; boss phases swap attack sets and
emit `boss_started`/`boss_defeated`; and death hands over to `systems/hearth`, which respawns
the player at the rest point. It exits non-zero on any failure (and 2 if it stalls) and writes
screenshots to `--out`. In-game, the `Debug` console exposes `arena_report`, `arena_spawn`,
`arena_hurt`, `arena_give`, `arena_kill_enemies`, `arena_reset` and `arena_verify`.
