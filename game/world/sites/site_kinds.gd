class_name SiteKinds
extends RefCounted
## What each kind of large site is made of: how its rock is cut, how big its rooms run, how they
## are joined, what lights them, what stands in them and which set-pieces it may hold. The layout
## (SitePlan), the shell (SiteField) and the dressing (SiteDress) all read their kind from here, so
## a region agent writing a site names a kind and gets all of it; anything here can be overridden
## per site under the def's `site.theme` (docs/WORLD_LIFE_INTERIORS.md).
##
## `style`: "rock" rooms are noisy ellipsoids with flat floors and round bores between them; "built"
## rooms are boxes with vaulted roofs, square passages and stairs. `formation` picks the rock
## shader's look (CaveInterior.ROCK_BY_FORMATION). Sizes are half-extents in metres: x and z across,
## y the height to the roof.

const SIZES := {
	"tight": Vector3(3.0, 2.8, 3.0),
	"small": Vector3(4.5, 3.4, 4.5),
	"medium": Vector3(6.5, 4.4, 6.5),
	"large": Vector3(9.0, 5.8, 9.0),
	"huge": Vector3(12.5, 7.5, 12.5),
}

## How many rooms a site of each size has when its rooms are not written out (the boss, the secret
## and the shortcut's rooms are extra).
const ROOM_COUNTS := {"small": 5, "medium": 7, "large": 9, "huge": 12}

const KINDS := {
	"cave": {
		"style": "rock", "formation": "water", "voxel": 0.55,
		"noise": 0.95, "noise_freq": 0.11, "tunnel_r": 1.9, "tunnel_len": [5.0, 11.0],
		"drop": [-3.0, 1.0], "turn": [35.0, 80.0],
		"palette": ["#8c8577", "#5f5a50", "#a39b8a"],
		"lights": ["fungus", "torch"], "light_colour": "#ffb066",
		"props": ["rocks", "bones_light"], "camp": false,
		"set_pieces": ["underground_lake", "daylight_shaft", "chasm_bridge", "fungus_grotto"],
		"loot": "core:loot/common_chest", "container": "chest",
	},
	"mine": {
		"style": "rock", "formation": "mining", "voxel": 0.5,
		"noise": 0.45, "noise_freq": 0.16, "tunnel_r": 1.6, "tunnel_len": [6.0, 12.0],
		"drop": [-3.5, 0.0], "turn": [0.0, 60.0], "square_tunnels": true,
		"palette": ["#7d7466", "#524b41", "#9a8f7c"],
		"lights": ["lantern", "torch"], "light_colour": "#ffbe70",
		"props": ["timbering", "mine_gear"], "camp": false,
		"set_pieces": ["forge_hall", "chasm_bridge", "collapsed_shaft", "ore_gallery"],
		"loot": "core:loot/common_chest", "container": "crate",
	},
	"crypt": {
		"style": "built", "formation": "crypt", "voxel": 0.5,
		"noise": 0.12, "noise_freq": 0.2, "tunnel_r": 1.4, "tunnel_len": [4.0, 9.0],
		"drop": [-3.0, 0.0], "turn": [90.0, 90.0],
		"palette": ["#a59d8b", "#6e675a", "#bdb4a0"],
		"lights": ["brazier", "candles"], "light_colour": "#ffae5e",
		"props": ["tombs", "bones"], "camp": false,
		"set_pieces": ["ossuary", "collapsed_shaft", "chasm_bridge"],
		"loot": "core:loot/wight_barrow", "container": "sarcophagus",
	},
	"keep": {
		"style": "built", "formation": "builder", "voxel": 0.5,
		"noise": 0.06, "noise_freq": 0.2, "tunnel_r": 1.5, "tunnel_len": [4.0, 8.0],
		"drop": [-3.2, 0.0], "turn": [90.0, 90.0],
		"palette": ["#9a927f", "#615a4d", "#b4ab96"],
		"lights": ["torch", "brazier"], "light_colour": "#ffb25c",
		"props": ["stores", "barracks"], "camp": false,
		"set_pieces": ["forge_hall", "barracks", "cellar_store"],
		"loot": "core:loot/rich_chest", "container": "chest",
	},
	"ruined_hall": {
		"style": "built", "formation": "builder", "voxel": 0.5,
		"noise": 0.35, "noise_freq": 0.14, "tunnel_r": 1.6, "tunnel_len": [4.0, 9.0],
		"drop": [-2.5, 0.5], "turn": [90.0, 90.0],
		"palette": ["#8f8a7c", "#5a574d", "#aaa392"],
		"lights": ["daylight", "brazier"], "light_colour": "#ffb870",
		"props": ["rubble", "roots"], "camp": false,
		"set_pieces": ["collapsed_shaft", "ossuary", "chasm_bridge"],
		"loot": "core:loot/common_chest", "container": "chest",
	},
	"bandit_cave": {
		"style": "rock", "formation": "creature", "voxel": 0.55,
		"noise": 0.85, "noise_freq": 0.11, "tunnel_r": 1.9, "tunnel_len": [5.0, 10.0],
		"drop": [-2.5, 1.0], "turn": [30.0, 75.0],
		"palette": ["#857c6c", "#5a5347", "#9d937f"],
		"lights": ["campfire", "torch", "lantern"], "light_colour": "#ffa14f",
		"props": ["camp", "stores", "rocks"], "camp": true,
		"set_pieces": ["daylight_shaft", "underground_lake", "chasm_bridge"],
		"loot": "core:loot/tithe_strongbox", "container": "chest",
	},
	"sea_cave": {
		"style": "rock", "formation": "water", "voxel": 0.55,
		"noise": 1.05, "noise_freq": 0.1, "tunnel_r": 2.1, "tunnel_len": [5.0, 11.0],
		"drop": [-2.0, 1.0], "turn": [40.0, 85.0],
		"palette": ["#8d948f", "#5a615e", "#b3b2a4"],
		"lights": ["daylight", "fungus"], "light_colour": "#9fd0d8",
		"props": ["shore", "rocks"], "camp": false, "wet": true,
		"set_pieces": ["underground_lake", "daylight_shaft", "chasm_bridge"],
		"loot": "core:loot/common_chest", "container": "chest",
	},
	"lava_tube": {
		"style": "rock", "formation": "creature", "voxel": 0.55,
		"noise": 0.7, "noise_freq": 0.075, "tunnel_r": 2.4, "tunnel_len": [6.0, 12.0],
		"drop": [-2.5, 0.5], "turn": [25.0, 60.0], "tube": true,
		"palette": ["#3d3835", "#26221f", "#5a4f47"],
		"lights": ["lava", "ember"], "light_colour": "#ff7a2e",
		"props": ["basalt", "ash"], "camp": false,
		"set_pieces": ["lava_chasm", "daylight_shaft", "chasm_bridge", "obsidian_grotto"],
		"loot": "core:loot/common_chest", "container": "chest",
	},
}

## The foes a site of a region is peopled with when it names none: [rank and file, archers, heavy].
const REGION_FOES := {
	"hearthvale": [["core:enemy/roadside_bandit", "core:enemy/hedge_wight"], ["core:enemy/poacher"], ["core:enemy/larkbourne_bruiser"]],
	"brightwater": [["core:enemy/cutpurse", "core:enemy/gutter_drake"], ["core:enemy/smuggler_sayer"], ["core:enemy/bravo"]],
	"sedgemire": [["core:enemy/leech_hound", "core:enemy/bog_drowned"], ["core:enemy/wisp"], ["core:enemy/tithe_bravo"]],
	"briarwold": [["core:enemy/thornhound", "core:enemy/weaver"], ["core:enemy/poacher"], ["core:enemy/hart_knight"]],
	"skerrow": [["core:enemy/clanless_outrider", "core:enemy/crag_wolf"], ["core:enemy/scree_hag"], ["core:enemy/clanless_hewer"]],
	"cinderlea": [["core:enemy/ash_wight"], ["core:enemy/chorister"], ["core:enemy/bell_bearer"]],
}

## Every set-piece a site may ask for, and the room size it needs at least.
const SET_PIECES := {
	"underground_lake": "large", "daylight_shaft": "medium", "chasm_bridge": "large",
	"fungus_grotto": "medium", "forge_hall": "large", "collapsed_shaft": "medium",
	"ore_gallery": "medium", "ossuary": "medium", "barracks": "medium", "cellar_store": "small",
	"lava_chasm": "large", "obsidian_grotto": "medium", "ledge": "large", "boss_arena": "huge",
}


## The kind's table with a site's `theme` laid over it.
static func of(kind: String, theme: Dictionary = {}) -> Dictionary:
	var base: Dictionary = (KINDS.get(kind, KINDS["cave"]) as Dictionary).duplicate(true)
	for k in theme:
		base[k] = theme[k]
	base["kind"] = kind if KINDS.has(kind) else "cave"
	return base


static func size_of(word: String) -> Vector3:
	return SIZES.get(word, SIZES["medium"])


static func bigger(a: String, b: String) -> String:
	var order := ["tight", "small", "medium", "large", "huge"]
	return a if order.find(a) >= order.find(b) else b
