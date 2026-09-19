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
| `enemy_abilities.gd` | `EnemyAbilities`: the pure decisions behind the bestiary's special behaviours — whether a voice attack may be used, how much a cutpurse takes, what a lure does this frame, whether greed has roused a guardian, when a duelist presses its guard, which limb comes off next. No state, no nodes; `Enemy` does the acting. |
| `projectile.gd`, `arrow.tscn` | Swept-ray kinematic projectile with a gravity arc; arrows stick into geometry, bolts vanish. |
| `spell_runtime.gd` | Pure spell rules: cost and cast time by skill, silence check, school → skill and damage kind, effect → `HitData`. |
| `spell_caster.gd` | Runtime casting: mana pool, cast timer, and the four implemented cast types (`projectile`, `self`, `aura`, `target`). `summon` is deliberately refused, not faked. |
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
  own swings) and `flee_after_steal`/`flee_time`. `limbs[{name, remove_attacks[], add_attacks[],
  poise_loss, speed_mult, say}]` come off one per poise break, changing the moveset as they go.
* `spell` defs — `{school, cast_type, cost, cast_time, range, speed, radius, duration, effects[]}`
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
`Enemy.telegraph/attack_launched/phase_changed/limb_broken/mark_dropped`, `Interactor.prompt_changed`.

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
godot --path game -- --arena                    # play the flat test arena
xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
  --audio-driver Dummy -- --arena --verify --out=$PWD/captures/arena
```

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
