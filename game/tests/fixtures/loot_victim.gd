extends Node3D
## Test fixture: a dead thing that names its own loot instead of relying on an enemy def.
## LootDrops reads `loot_table` and `marks_range` off the victim when they are set.

var loot_table: String = "core:loot/wolf_carcass"
var marks_range: Array = [5, 9]
