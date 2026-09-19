# ui — the theme, the HUD and every screen

**Purpose.** Everything the player reads (DESIGN §5.16, §5.17, §5.19, §9). One identity —
"tended paper": warm parchment, brass and dark oak, Cinzel for display type, Spectral for
body and the handwritten journal italic, hand-drawn icons, elements that fade in from ink.
Deep places and dangerous regions swap brass and oak for cold bronze and ash.

## Where things are

| Path | What it is |
|---|---|
| `ui/ui.gd` | the `UI` autoload: the CanvasLayer stack, the menu stack, toasts, the screen fade, the active input device |
| `ui/theme/theme_builder.gd` | builds a `Theme` from the generated textures and `ui_textures.json` |
| `ui/theme/wickmere_theme.tres`, `..._deep.tres` | the saved themes, written by `tools_gd/build_theme.tscn` |
| `ui/lib/ui_kit.gd` | `UiKit`: the builders every screen uses (labels, pages, rules, item icons, ink-in, focus chains, markdown-lite) |
| `ui/boot/` | the first scene; routes to the main menu, the world, the smoke run or a capture plan |
| `ui/menus/` | main menu, pause, settings (with `rebind_capture.gd`), save/load |
| `ui/hud/` | `hud.gd`, `compass.gd` (static bearing maths), `stat_bar.gd` (damage-lag ghost) |
| `ui/dialogue/` | the conversation page and the gesture wheel |
| `ui/journal/`, `ui/books/` | the journal's four tabs; the two-page reader |
| `ui/inventory/`, `ui/skills/`, `ui/crafting/`, `ui/trade/`, `ui/property/` | the system screens |
| `ui/map/` | the chart, its fog shader is `assets/shaders/map_fog.gdshader` |
| `ui/character/` | the Naming, and `valish_names.gd` |

Screens are `.tscn` files whose root script builds the controls in code from `UiKit`. That
keeps one place to change a rule (how a page is framed, how a list row reads) instead of
forty scene files that drift apart.

## The UI autoload

Layers: HUD 5, dialogue 12, menus 20, toasts 30, fade 40. The debug console sits at 100 and
must stay above all of them.

```gdscript
UI.open("journal", {"tab": 2})   # pauses the tree, frees the mouse, emits menu_opened
UI.close()                        # or close("journal") / close_all()
UI.is_menu_open("map") -> bool    UI.top_menu() -> String
UI.hud_visible = false            UI.show_hud() / hide_hud() / hud()
UI.toast("text", "quest")         # also fires from EventBus.notify
UI.fade_to_black(0.3) / fade_from_black()
UI.prompt_for("interact") -> "E" or "A", following the last device used
await UI.confirm("Write over it?", "…")  -> bool
UI.set_variant("deep")            # or let region danger, deep places and bosses decide
```

`MENUS` maps a menu id to its scene; a screen may implement `setup(args: Dictionary)` and
`closing()`. Add a screen by adding a line there.

## What it reads from other streams

By group and by duck typing, so every screen works before the stream it talks to exists:
`player` (health/stamina/mana, `stats_changed`, `lock_on_changed`, a child with
`prompt_changed`), `inventory`, `equipment`, `progression`, `crafting`, `quest_log`,
`dialogue_runner` — see CONTRACTS §8. Content types read: `item`, `skill`, `perk`, `calling`,
`recipe`, `effect`, `book`, `gesture`, `rumour`, `enemy`, `boss`, `place`, `poi`, `region`.

Emitted: `EventBus.menu_opened/closed`, `gesture_performed`, `transaction`,
`property_purchased`, `notify`. Consumed: `notify`, `book_opened`, `region_entered`,
`place_discovered`, `interior_entered/exited`, `boss_started/defeated`, `status_applied`,
`damage_dealt`, `player_spawned`, `player_died`, `echo_recovered`, `item_equipped`,
`Interiors.transition`.

Save section: none. The Naming writes the GameState flags `player_name`, `player_calling`,
`player_appearance` and `new_game`; the map reads `surveyed:<place_id>`; the journal reads
`rumour:<id>` and `bestiary:<id>` and `killed:<enemy_id>`.

## Regenerating the art

```
python3 tools/ui/gen_ui_textures.py            # game/assets/ui/ + ui_textures.json
python3 tools/ui/gen_map.py                    # game/assets/ui/map/world_map.png
godot --headless --path game --import
godot --headless --path game --audio-driver Dummy res://tools_gd/build_theme.tscn
```

`gen_map.py` reads `game/world/generated/` when the world builder has run and falls back to
the region definitions when it has not; the committed chart is that fallback.

## Looking at it

```
xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
    --audio-driver Dummy --resolution 1280x720 res://tools_gd/ui_review.tscn -- --out=captures/ui
```

Every screen with believable data, screenshotted. `--only=hud,map` narrows it and
`--settle=<seconds>` changes how long each shot is given to arrive. The harness builds the
real Inventory, Equipment, Progression and Crafting nodes from real content, so a screenshot
is evidence a screen works and not only that it draws.

## Tests

`tests/unit/test_ui_theme.gd` (both themes load, fonts resolve, every texture the manifest
promises exists, an icon for all 32 names, a marker for every place and POI kind, the layer
stack, opening and closing screens, the theme variant following danger),
`test_compass.gd` (bearings and strip offsets), `test_rebind_capture.gd` (press-to-rebind
with synthetic events). Outside the engine: `tools/ui/tests/test_gen_map.py`.
