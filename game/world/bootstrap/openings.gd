class_name Openings
extends RefCounted
## Which `core:opening/*` a new game begins with, and which one the wake plays (DESIGN §5.1a).
##
## A new game has two openings. The **style's start** is the opening whose `style` matches the
## character (`core:opening/<style>`): its own town, a short film in the teacher's voice, the
## tutorial quest and the teacher's first words. The **wake** (`role: "wake"`) comes later, when the
## character follows something down the Hushline Stair: the opening film, the Stair Head and the
## Naming from its `wake` stage. A character with no style (a pack with none, a test, an old save)
## gets the **fallback**, `core:opening/new_game`, which opens straight on the wake as the game
## always did.
##
## The flags, all in GameState and so all in the save:
##   new_game            up only while the wake's film plays (and on the fallback's first frame):
##                       what holds saving (SaveSystem.hold_saves) and the Warden at her fire
##   style_start         up from the Naming of a styled character until the wake: the tutorial, the
##                       ride and the descent. It holds the Warden at the Stair Head for the meeting
##   style_opening_due   one frame's worth: the Naming wrote a styled character and the world has
##                       not begun its start yet (its film, its quest, its kit)

const FALLBACK := "core:opening/new_game"
const WAKE_ROLE := "wake"
const NEW_GAME := "new_game"
const STYLE_START := "style_start"
const STYLE_DUE := "style_opening_due"


## The opening a new game begins with now: the character's style's, else the fallback.
static func for_new_game() -> Dictionary:
	var style := StyleDef.of_character()
	if not style.is_empty():
		var own := StyleDef.opening_of(style)
		if not own.is_empty():
			return own
	return ContentDB.get_or_empty(FALLBACK)


## The wake: the opening with `role: "wake"`, else the fallback (whose film and place it is).
static func wake() -> Dictionary:
	for def in ContentDB.all("opening"):
		if str(def.get("role", "")) == WAKE_ROLE:
			return def
	return ContentDB.get_or_empty(FALLBACK)


## Whether this opening is a style's start rather than the wake or the fallback.
static func is_style_start(opening: Dictionary) -> bool:
	return not str(opening.get("style", "")).is_empty()


## Whether a new game's first frame is still to be begun: the fallback's `new_game`, or a styled
## character the Naming has just written.
static func begin_due() -> bool:
	return GameState.has_flag(NEW_GAME) or GameState.has_flag(STYLE_DUE)
