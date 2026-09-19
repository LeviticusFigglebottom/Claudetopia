# systems/interiors

Interiors are separate scenes ("cells") loaded into a pocket far from the overworld
(x ≈ 50 km, y = 3 km) so the streamer sees nothing around them and no scene switch is
needed. Doors teleport the player between the overworld and the interior.

* `Interiors` autoload (`interior_manager.gd`): `enter(interior_id, door)`, `exit()`,
  `current_id`, `in_interior()`, `return_point`. Save section `interiors`.
* `door.tscn` (`door.gd`): interactable door. Exterior doors carry `interior_id` and
  `spawn_marker` (a Marker3D name inside the interior, default "Entrance"). Interior exit
  doors set `is_exit = true`. Locks are a child node named `DoorLock` (owned by the crime
  system) queried by duck typing: `is_locked()`, `try_open(actor) -> bool`.
* Interior scene contract: root Node3D; a Marker3D per entrance (default "Entrance");
  at least one exit Door; the `interior` content def (`name, scene, resident, story,
  unique_object`) is looked up by id.

Emits `EventBus.interior_entered(id)` / `interior_exited(id)`; sets
`GameState.current_interior_id`; asks the Atmosphere (group "atmosphere") to switch to
interior mode (`set_interior(bool)`).
