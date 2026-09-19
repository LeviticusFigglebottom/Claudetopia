# systems/hearth

Hearthstones (checkpoints), death, and the Echo (dropped currency you can go back for).

* `Hearth` autoload (`hearth_system.gd`): last Hearthstone, respawn point, the Echo record,
  lit stones. Save section `hearth`.
* `hearthstone.tscn` (`hearthstone.gd`): interactable stone with a flame. Resting: full
  restore of the player (`full_restore()`), sets respawn, lights the stone, emits
  `EventBus.hearthstone_rested(id)` (enemies reset on it), autosaves to the `auto` slot.
* `echo.tscn` (`echo.gd`): the faint figure standing where you died, holding your marks.
  Walking into it restores them (`EventBus.echo_recovered(marks)`). Dying again while an
  Echo stands lets the old one go quiet (marks lost).

Reads: player (group "player": `full_restore`, `respawn(pos, yaw)`, `is_dead`,
`set_input_enabled`), inventory (group "inventory": `marks`, `add_marks`, `remove_marks`).
Consumes `EventBus.player_died(position)`. Emits `hearthstone_rested`, `player_respawned`,
`echo_recovered`, `notify`.
