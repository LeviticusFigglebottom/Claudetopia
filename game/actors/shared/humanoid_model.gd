class_name HumanoidModel
extends Node3D
## Composes a humanoid from the forge's modular parts and drives its animation.
##
## Loads `humanoid_rig.glb` (rig + default body + every clip from CONTRACTS.md §3), attaches
## whatever parts an `appearance` Dictionary asks for to the one shared `Skeleton3D`, creates
## the `BoneAttachment3D` sockets from CONTRACTS.md §2, and exposes a small intent API over
## an `AnimationTree`:
##
##     model.set_locomotion(Vector2(0.0, 5.0), false)   # jogging ahead at 5 m/s, not sneaking
##     model.play_intent("Attack_1H_Light_1")
##     model.clip_event.connect(...)                    # hit_start / footstep_l / ...
##
## Clip events come from the `<model>.clips.json` sidecar rather than from method tracks in
## the GLB, so the forge can retime a clip without re-authoring anything in the engine.

signal clip_event(name: String)
signal clip_finished(name: String)
signal appearance_changed()

const RIG_PATH := "res://assets/models/characters/humanoid_rig/humanoid_rig.glb"
const CLIPS_JSON := "res://assets/models/characters/humanoid_rig/humanoid_rig.clips.json"
const PARTS_ROOT := "res://assets/models/characters/"
## Slot -> folder under PARTS_ROOT. One folder per part family (CONTRACTS.md §4).
const SLOT_DIRS := {
	"head": "heads", "hair": "hair", "beard": "beards", "torso": "clothing", "legs": "clothing",
	"feet": "clothing", "hands": "clothing", "belt": "clothing", "back": "clothing",
	"headgear": "clothing", "attachment": "attachments", "body": "bodies",
}
## CONTRACTS.md §2 socket bones, exposed as BoneAttachment3D children.
const SOCKETS := {
	"Socket.WeaponR": "WeaponR", "Socket.WeaponL": "WeaponL", "Socket.ShieldL": "ShieldL",
	"Socket.Back": "Back", "Socket.HipL": "HipL", "Socket.Head": "Head", "Socket.Lantern": "Lantern",
}
## Recolours the iris band of an eyeball and leaves the white alone (see the shader).
const IRIS_SHADER := preload("res://assets/shaders/eye_iris.gdshader")
## Skin: the Compatibility renderer has no subsurface scattering, so the shader wraps the light
## past the terminator and tints what it adds towards blood (see the shader).
const SKIN_SHADER := preload("res://assets/shaders/skin.gdshader")
## Cloth, leather and metal: a grain that tiles over the bake, mottling, dirt from the ground.
const GARMENT_SHADER := preload("res://assets/shaders/garment.gdshader")
## A person's brows, scar, moles and face paint, drawn over the head's skin (triage 39).
const FACE_MARKS_SHADER := preload("res://assets/shaders/face_marks.gdshader")
## The morph targets on a head, and on what is worn over the face, that are the face's sliders
## (the forge's lib/face_morphs.py): `face_<slider>` and `face_age`.
const FACE_TARGET := "face_"
## A woman's bust (item 46): the woman's body carries `bust`, each garment fitted to her
## `woman_bust`, both at the full end (CharacterAppearance.bust_weight).
const BUST_TARGETS := ["bust", "woman_bust"]
## Hair and beards: a band of shine across the strands, fine strands over the painted clumps and
## a broken outline, off each style's flow map (tools/forge/face_textures.py; see the shader).
const HAIR_SHADER := preload("res://assets/shaders/hair.gdshader")
const STUBBLE_SHADER := preload("res://assets/shaders/stubble.gdshader")
## Hair and beards as strand cards (triage 47): each style's GLB carries `<name>_cards` beside its
## shell (tools/forge/hair_cards.py), drawn with the shared strand atlas and the cap's grain. The
## cards are worn within CARDS_RANGE metres of the camera, the shell beyond it: past a few metres
## a head of hair is a handful of pixels and the shell is the cheaper draw.
const HAIR_CARDS_SHADER := preload("res://assets/shaders/hair_cards.gdshader")
const HAIR_STRANDS := "hair_strands.png"
const HAIR_GRAIN := "hair_grain.png"
const CARDS_RANGE := 10.0
const CARDS_RANGE_MARGIN := 1.0
const CARDS_LOD_BIAS := 100.0
## Skin's pores and fine creases, tiled over the UVs (skin.gdshader `detail_normal`): so many
## repeats over a head's UV square (the face has most of it) and over a body's.
const SKIN_DETAIL := "skin_detail_normal.png"
const SKIN_DETAIL_SCALE_HEAD := 44.0
const SKIN_DETAIL_SCALE_BODY := 90.0
const DETAIL_DIR := "res://assets/textures/characters/"
## kind -> [shader kind, detail normal map, repeats over the UV square, normal depth]
const GARMENT_KINDS := {
	"cloth": [0, "weave_normal.png", 34.0, 0.45],
	"leather": [1, "grain_normal.png", 16.0, 0.9],
	"iron": [2, "hammer_normal.png", 9.0, 0.25],
}
static var _detail_cache: Dictionary = {}
## Headgear that covers the crown. Hair is combed for a bare head; under one of these the
## chosen style would stand through the helm or the hood, so the close style is worn instead.
const COVERS_HEAD := {"headgear": ["helm", "hood"], "back": ["hooded_cloak", "ragged_cloak"]}
const UNDER_A_HOOD := "hood_friendly"
const DEFAULT_BLEND := 0.12
## Cross-fades on the state machine edges: into a one-shot fast, back to locomotion softer.
const ONE_SHOT_BLEND_IN := 0.08
const ONE_SHOT_BLEND_OUT := 0.14
## A swing, a riposte or a backstab hands over to the next swing, a roll or a flinch across this
## long (s), along an edge of its own. With no edge between two one-shots the state machine
## restarted on the new clip's first frame: a 1H chain's hand-over moved a hand 46 cm in one
## frame (test_attack_motion), four times as far as the swing itself moves it in one.
## The edge switches at once, and the model blends the two poses itself (_blend_handover).
const ONE_SHOT_HANDOVER := 0.1
## The longest a landed blow holds the picture still (hit_stop), and how fast it catches up after.
const HIT_STOP_MOST_S := 0.14
const HIT_STOP_CATCH_UP := 2.0
## The most the picture may owe the timeline: a blow's wait for the blade to reach the body
## (Impact.MOST_WAIT_S) and its hold together, with room. Past it the picture would stay behind.
const HIT_STOP_OWED_MOST := 0.5
## The clips a fight hands over from, and the ones it hands over to.
const HANDS_OVER := ["Attack_", "Riposte", "Backstab"]
const TAKES_OVER := ["Attack_", "Dodge_", "Hit_", "Stagger", "Knockdown", "Block_Hit", "Parry", "Death_"]
const LOCOMOTION_STATE := "Locomotion"
## A body in deep water (set_swimming) rests in this state instead of Locomotion: treading water
## (Swim_Idle) blended into a breaststroke (Swim_Forward) by the pace it swims at.
const SWIM_STATE := "Swim"
const SWIM_CLIPS: Array[String] = ["Swim_Idle", "Swim_Forward"]
## The pace the stroke is all in at, m/s, and how fast the swim eases between treading and the stroke.
const SWIM_STROKE_FROM := 0.9
const SWIM_BLEND_S := 0.3
## Locomotion into the water and out of it.
const SWIM_IN_S := 0.35
## One-shots that end in a pose the body keeps -- a corpse, a man knocked flat, a sleeper -- until
## something else is played. Everything else goes back to locomotion when it ends, and so, until
## this list, did the dead: a fallen bandit stood up again 2.3 s after dying.
const HOLD_LAST_POSE: Array[String] = ["Death_A", "Death_B", "Death", "Knockdown", "Sleep_Idle", "Sit_Idle"]
## The clips the moving branch of the Locomotion graph plays, all on one stride timeline.
const MOVE_CLIPS: Array[String] = ["Walk", "Trot", "Run", "Sprint", "Walk_Back", "Strafe_L", "Strafe_R", "Sneak_Walk"]
## A walk carries on up to this much faster than it was authored, at a quicker cadence, before
## it starts turning into a run.
const BRISK_WALK := 1.33
## However slowly or fast the body moves, a clip plays between these shares of its own cadence:
## a crawl of a stride looks wrong sooner than a small slide does. The floor lets go as the body
## comes to a stand (below MOVING_FULL), so a stop freezes the stride where it is and settles it
## into the idle, rather than stepping on the spot at half pace while the feet skate.
const RATE_MIN := 0.5
const RATE_MAX := 1.6
const SNEAK_BLEND_S := 0.25
## The speed the graph is driven at eases toward the body's over this long, so a velocity that
## ticks at 60 Hz, or hitches on a step, does not shake the blend.
const SPEED_SMOOTH_S := 0.08
## Below MOVING_FROM m/s the body is standing (the idle plays); above MOVING_FULL it is all gait.
const MOVING_FROM := 0.08
const MOVING_FULL := 0.7
## Stances held over whatever the legs are doing: the upper body takes the clip, the hips and legs
## keep walking. Played as a whole-body state, a raised guard froze the legs in its stance and the
## body glided across the ground at 1.56 m/s with its feet still.
##
## The bow's clips are stances too (triage 55): an archer walks, strafes and creeps with the bow
## drawn. Held as a stance, a clip is played from its start each time it is asked for
## (`stance_seek`), at the AnimationDriver's pace (`stance_rate`, as a one-shot is), and one of
## STANCE_ENDS lets the upper body go back to the legs' when it has played through.
const STANCE_CLIPS: Array[String] = ["Block_Idle", "Bow_Draw", "Bow_Aim", "Bow_Release"]
const STANCE_ENDS: Array[String] = ["Bow_Release"]
## What a stance leaves to the legs, and a hand-over between stances leaves as the legs have it.
const LEGS: Array[String] = ["Root", "Hips", "UpperLeg.L", "LowerLeg.L", "Foot.L", "Toe.L",
		"UpperLeg.R", "LowerLeg.R", "Foot.R", "Toe.R"]
## Stances played at the timeline's pace (the others are loops, at their own).
const STANCE_TIMED: Array[String] = ["Bow_Draw", "Bow_Release"]
## The bow's stances, which turn the upper body to the aim (aim_pitch) and work the bow (BowHands).
const BOW_STANCES: Array[String] = ["Bow_Draw", "Bow_Aim", "Bow_Release"]
## How far the aim turns the spine and chest (the rest is the head's), and how fast it comes and goes.
const AIM_SPINE := 0.45
const AIM_CHEST := 0.55
const AIM_MOST := deg_to_rad(65.0)
const AIM_BLEND_S := 0.15
## First person (triage 57; see `first_person`): the slots drawn into the shadows only, the carry's
## clip and the bones it holds, and how fast the carry comes and goes.
const FP_HEAD_SLOTS: Array[String] = ["head", "hair", "beard", "headgear"]
const CARRY_CLIP := "Idle_Combat"
const CARRY_BONES: Array[String] = ["Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
		"Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R"]
const CARRY_BLEND_S := 0.16
## Where the eyes are in the Head bone's frame when the rig's eyeballs cannot say (m), and how far
## ahead of the eyeballs the first-person camera stands, clear of a hood's rim and a collar.
const EYE_IN_HEAD := Vector3(0.0, 0.105, 0.061)
const EYE_AHEAD := 0.04
## Where the carry holds the hands in the view (_hold_in_view), metres from the eyes: across to the
## right, up, ahead. The right hand with a weapon; a shield's or a lantern's left hand; a bow's left
## hand, and an empty right beside it. The blade's way in the view (across, up, ahead) and a carried
## bow's. A swing, a saying, a parry and a guard have both arms turned up FP_LIFT_DEG, in and out
## over FP_LIFT_S.
const FP_HOLD_R := Vector3(0.2, -0.25, 0.42)
const FP_HOLD_L := Vector3(-0.24, -0.3, 0.4)
const FP_HOLD_BOW := Vector3(-0.14, -0.24, 0.46)
const FP_HOLD_FREE_R := Vector3(0.19, -0.3, 0.36)
const FP_BLADE := Vector3(-0.32, 0.74, 0.6)
const FP_BOW_AXIS := Vector3(0.18, 0.95, 0.25)
## The guard raised in first person (Block_Idle): the weapon hand up and to the right, the blade
## across the view and a little up; a shield's hand up before the left of the view.
const FP_GUARD_R := Vector3(0.2, -0.12, 0.44)
const FP_GUARD_BLADE := Vector3(-0.9, 0.38, 0.22)
const FP_GUARD_L := Vector3(-0.1, -0.16, 0.4)
const FP_LIFT_DEG := 12.0
const FP_LIFT_S := 0.12
## In a swing each hand is kept within this share of the view's half-width across, and between these
## shares of its half-height down and up, and at least FP_NEAREST ahead of the eyes, so the arc the
## clip draws wide and low is drawn where it is seen; a left hand within FP_TWO_HANDS_M of the right
## hand's weapon is gripping it and goes with it.
const FP_ACROSS := 0.62
const FP_BELOW := 0.5
const FP_ABOVE := 0.4
const FP_NEAREST := 0.4
const FP_TWO_HANDS_M := 0.13
## A torch in the left hand is held up and a little out, its head above the hand, in both views
## (the owner's playtest, 2026-09-30): at the arm's rest it hung head-down by the thigh, out of the
## first-person picture and burning into the leg. Third person: from the chest joint (+X the body's
## left, +Z ahead), the haft leaning TORCH_UP_3P. First person: a place in the view (x right, y up,
## z ahead) at the picture's lower left, the haft leaning TORCH_UP_FP.
const TORCH_HOLD_3P := Vector3(0.26, -0.16, 0.34)
const TORCH_UP_3P := Vector3(0.08, 1.0, 0.3)
## A pole at rest (`rests_poles`: a foe's staff, spear, hook or lamp-pole longer than POLE_FROM_M):
## the right hand down by the hip and a little ahead, from the chest joint, and the haft standing up
## beside the body, leaning out and ahead (POLE_UP_3P). Held at the clips' rest it lay across the
## body and through the cloak, and nine bosses at a distance were the same black diagonal.
const POLE_HOLD_3P := Vector3(-0.27, -0.3, 0.16)
const POLE_UP_3P := Vector3(-0.1, 1.0, 0.16)
const POLE_FROM_M := 1.25
const TORCH_HOLD_FP := Vector3(-0.27, -0.22, 0.48)
const TORCH_UP_FP := Vector3(-0.12, 1.0, 0.28)
const FP_LIFTS: Array[String] = ["Attack_", "Riposte", "Backstab", "Cast_", "Parry", "Throw", "Interact", "Pick_Up"]
## The bones a stance owns: everything above the hips, and what hangs off it.
const UPPER_BODY: Array[String] = ["Spine", "Chest", "Neck", "Head",
		"Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
		"Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
		"Socket.WeaponR", "Socket.WeaponL", "Socket.ShieldL", "Socket.Back", "Socket.Head", "Socket.Lantern"]
const STANCE_BLEND_S := 0.12
## The bones a swing from the legs does not blend in: they take the swing's pose at once
## (_begin_handover says why).
const SWING_ARMS: Array[String] = ["Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
		"Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R", "Socket.WeaponR", "Socket.WeaponL", "Socket.ShieldL"]
## The gait and the idle hand over across this long, from the moment the body's own speed says
## so. Read off the smoothed speed, a stop from a jog held the legs split mid-stride for a tenth
## of a second after the body stood (the smoothing still thought it was moving) and then snapped
## them together in the next tenth.
const MOVE_BLEND_S := 0.2
## Whichever way the body goes, its legs play one of four clips (ahead, back, either side), the one
## whose way is nearest, and the hips are turned the rest of the way toward where it goes, the
## chest turned back to face ahead (_turn_the_hips). Ahead and back each take the ways within
## SIDE_FROM of them, the side-steps the rest; a way is left only SECTOR_HOLD past its edge, and
## the legs hand over across SECTOR_BLEND_S. Blended half and half, a side-step and a run put the
## planted foot on a line between the two, and a locked-on diagonal slid at 28% of its speed.
const SIDE_FROM := deg_to_rad(67.5)
const SECTOR_HOLD := deg_to_rad(10.0)
const SECTOR_BLEND_S := 0.15
## The hips come round to the way the body goes over about this long, and the chest turns back
## this share of the hips' turn to face ahead.
const HIPS_TURN_S := 0.08
const CHEST_BACK := 0.8
## The ways, clockwise from ahead: what each plays, and where it points (radians, + to the right).
enum Way { AHEAD, RIGHT, BACK, LEFT }
const WAY_ANGLE := [0.0, PI * 0.5, PI, -PI * 0.5]
## Turning on the spot (standing, below TURN_BELOW m/s over the ground): the turn clips are played
## at the rate the body turns, a cycle for every `turn` degrees in their sidecar, the way the gaits
## are played at the ground's speed. A turn starts above TURN_FROM and ends below TURN_UNTIL
## (rad/s); one begun faster than PIVOT_FROM is an about-face, the quicker, wider turn. Slower than
## TURN_FROM, the planted feet step round by themselves (FootPlanter).
const TURN_CLIPS := {"left": "Turn_L90", "right": "Turn_R90", "pivot_left": "Turn_L180", "pivot_right": "Turn_R180"}
const TURN_BELOW := 0.3
const TURN_FROM := deg_to_rad(60.0)
const TURN_UNTIL := deg_to_rad(30.0)
const PIVOT_FROM := deg_to_rad(200.0)
## a turn clip plays at no more than this share of its own pace; faster, the feet turn with the body
const TURN_RATE_MAX := 2.5
## A turn comes in almost at once (its first frame is the stance the feet stand in) and goes out
## over TURN_BLEND_S with the feet held under it.
const TURN_IN_S := 0.03
const TURN_BLEND_S := 0.1
## The yaw rate is read off the body's own turning, eased over this long.
const TURN_SMOOTH_S := 0.05
## A turn of more than this in one frame is a body put down facing a new way, not a turn.
const SNAP_TURN := 0.8
## Braking (slowing faster than BRAKING_FROM m/s², its rate eased over ACCEL_SMOOTH_S) the legs keep
## the gait they were in and shorten nothing: they go on at the ground's pace, however slow, until
## the body stands and the feet are planted. Blended down through the slower gaits as it slowed, a
## run's feet and a walk's, which are down for different shares of a stride, took turns sliding:
## 40 cm along the ground in a stop from a jog (the mean of eight stops at eight points of the
## stride), 35 cm from a sprint. The hold lets go once the body gathers speed again.
## Braking with both feet off the ground (a run's flight), the stride goes on at its own pace,
## since no foot is on the ground to slide: the body comes down on a foot and brakes on it, and a
## body that stands in the air finishes the flight (for FLIGHT_MOST_S at the most) before its feet
## are planted. Slowed with the body, a stop from a sprint stood still in the air with both feet
## up for as long as 0.36 s. A flight begun slower than FLIGHT_FROM m/s (the last push-off of a
## stop, a centimetre from standing) is not played on, or the legs would run a stride in place
## after the body stood; the planter sets the lower foot down instead.
const BRAKING_FROM := -6.0
const FLIGHT_MOST_S := 0.25
const FLIGHT_FROM := 1.5
const ACCEL_SMOOTH_S := 0.05

@export var appearance_dict: Dictionary = {}:
	set(value):
		appearance_dict = value
		if is_inside_tree() and not _applying:
			apply_appearance(value)

var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var appearance: CharacterAppearance = CharacterAppearance.new()

var _rig_root: Node3D
var _state_machine: AnimationNodeStateMachinePlayback
var _clip_data: Dictionary = {}          ## clip name -> {loop, length, events[]}
var _default_meshes: Dictionary = {}     ## logical name -> MeshInstance3D from the rig GLB
var _default_eyes: Array[MeshInstance3D] = []   ## both of the rig's eyeballs
var _part_meshes: Dictionary = {}        ## slot -> Array[MeshInstance3D]
## Which `bodies/*` mesh is standing in for the rig's own body, or "" for the rig's own.
## Readable because the part node cannot answer it: every variant's mesh is called `Body`
## inside its own glTF, so they all arrive here named `body_Body`.
var body_variant_worn := ""
## The body this much broader than its build makes it, across and front to back (a boss that stands
## over its people in more than height: EnemyDress `breadth`). 1 for everyone else.
var breadth := 1.0
## Turns the arms out from a padded or heavy body and holds them in under a long cloak (see
## ArmRoom), set with each appearance.
var arm_room: ArmRoom = null
## Poses a skirt's bones from the thighs (see SkirtDrive); eased off while swimming or in the saddle.
var skirt_drive: SkirtDrive = null
const SKIRT_BLEND_S := 0.25
var _cloak_hold := 0.0                   ## ARM_HOLD for the cloak worn
## How closed each hand is, "L" and "R": 0 open, as the hand is modelled, 1 a fist round a haft on
## the weapon socket's axis (set_grip), and where each is easing to.
var _grip := {"L": 0.0, "R": 0.0}
var _grip_to := {"L": 0.0, "R": 0.0}
var _sockets: Dictionary = {}            ## socket bone name -> BoneAttachment3D
var _one_shot := ""
var _stop_left := 0.0
var _stop_owed := 0.0
var _one_shot_time := 0.0
var _one_shot_length := 0.0
var _fired: Dictionary = {}              ## event index -> true, for the running one-shot
var _locomotion := Vector2.ZERO          ## ground velocity asked for, m/s, the body's frame
var _loco_now := Vector2.ZERO            ## ...eased (SPEED_SMOOTH_S)
var _sneaking := false
var _sneak_w := 0.0
var _move_w := 0.0                       ## gait against idle, eased over MOVE_BLEND_S
var _stance := ""                        ## a STANCE_CLIPS clip held over the legs, or ""
var _stance_w := 0.0                     ## ...eased over STANCE_BLEND_S
var _has_stance_layer := false
var _stance_time := 0.0                  ## seconds into the stance's clip, at its own pace
var _stance_node: AnimationNodeAnimation = null
## Where the body aims while a bow is up (triage 55): radians up (+) and to the left (+) of the way
## it faces, set by whoever aims it (Player). The spine and chest turn that way over the legs.
var aim_pitch := 0.0
var aim_yaw := 0.0
## A held draw's tremble, radians at its widest (Player: a bow held past its steady time).
var aim_tremble := 0.0
var _aim_w := 0.0
var _tremble_t := 0.0
var _pre_aim := {}                       ## bone -> its rotation before the aim was laid on, this frame
## First person (triage 57): the player's own body seen from its own eyes (Player, CameraRig). While
## it is on, the head and what is worn on it (FP_HEAD_SLOTS, the eyes) are drawn into the shadows
## only -- the camera is inside it, and its shadow still falls -- and the body carries the two
## things below. Off for everyone else.
var first_person := false:
	set(value):
		if first_person != value:
			first_person = value
			_apply_first_person_look()
## How much of aim_pitch the spine and chest follow without a bow up (0..1), eased over AIM_BLEND_S:
## in first person the upper body turns to the view, so a swing's arc and what the hands hold stay
## where the eyes look, up or down.
var view_follow := 0.0
## How much the arms are held in the carry (0..1, eased over CARRY_BLEND_S): in first person, a
## drawn weapon is held up before the body in Idle_Combat's guard over whatever the legs do, so the
## hands and the weapon are in the picture. Only while nothing else has the arms (no one-shot, no
## stance, not swimming).
var carry := 0.0
var _carry_w := 0.0
## How far the left arm is in the torch's hold now (0..1).
var _torch_w := 0.0
## Whether a long haft in the right hand is stood upright at rest (a foe's: EnemyDress sets it), and
## how far into that rest the arm is now.
var rests_poles := false
var _pole_w := 0.0
var _carry_t := 0.0
var _carry_tracks := {}                  ## bone -> its rotation track in CARRY_CLIP
## The view's pitch in first person (radians, up +: CameraRig.pitch), for placing the carry, and how
## far a swing's lift is in.
var view_pitch := 0.0
var _lift_w := 0.0
var _guard_w := 0.0
## The eyes' place in the Head bone's frame (eye_point), from the rig's own eyeballs at rest.
var _eye_in_head := Vector3.INF
## The bow in the left hand, worked: its string to the draw hand, its limbs bent, the arrow on it.
var bow_hands: BowHands = null
var _way := Way.AHEAD                    ## the way the legs are going (Way)
var _way_w := {"fb": 0.0, "lr": 1.0, "dir": 0.0}   ## the blends between the ways, eased
var _hips_turn := 0.0                    ## rad the hips are turned toward the way the body goes, eased
var _yaw_last := NAN                     ## the body's heading last frame, for its turn rate
var _yaw_rate := 0.0                     ## rad/s, + to the left, eased (TURN_SMOOTH_S)
var _turn := ""                          ## the TURN_CLIPS key being played, or ""
var _turn_w := 0.0                       ## the turn against the rest of the graph, eased
var _turn_quiet := 0.0                   ## seconds the body has turned slower than TURN_UNTIL
var _turn_age := 0.0                     ## seconds into the turn being played
var _gathered := 0.0                     ## rad turned since the body last stood square, + to the left
var _speed_last := 0.0                   ## the ground speed last frame, for braking
var _accel := 0.0                        ## m/s², eased (ACCEL_SMOOTH_S)
var _held_gait := -1.0                   ## the gait position held while braking, or -1
var _in_flight := false                  ## braking with both feet off the ground (see BRAKING_FROM)
var _flight_s := 0.0                     ## seconds the body has stood in the air
var _flight_pace := -1.0                 ## m/s the body went at when the flight began, or -1
var _gait_shown := -1.0                  ## the gait position the graph is set to
var _has_turns := false
var _handovers := {}                     ## "from>to" one-shot edges that hand over (_add_handovers)
var _handover_from: Array = []           ## each bone's [rotation, position] as the last clip left it
var _handover_t := -1.0                  ## seconds into a hand-over's blend, or -1
var _handover_len := ONE_SHOT_HANDOVER   ## how long this hand-over blends (s)
var _gait_points: Array = []             ## [[clip, ground speed m/s, point name], ...] ascending
var _clip_speed: Dictionary = {}         ## clip -> authored ground speed (sidecar `speed`)
var _clip_cycle: Dictionary = {}         ## clip -> seconds per stride cycle
var _part_cache: Dictionary = {}
## Which hair part is actually on the head, which is not always the record's: see COVERS_HEAD.
var hair_worn := ""
var _worn_signature := ""
var _colour_signature := ""
static var _meta_cache: Dictionary = {}
var _applying := false      ## guards the appearance_dict setter against re-entering
## How fast a one-shot plays. The AnimationDriver sets it so that the blow the body makes lands on
## the frame the game opens the hit window, whatever length the caller's timing gave the attack;
## 0 holds the pose, which is what a heavy being charged is. Locomotion always plays at 1.
var speed_scale: float = 1.0
var _holding := ""          ## a finished HOLD_LAST_POSE clip the body is lying in
## Holds the feet where they stand when the body stops and steps them into the stance, so a stop
## does not slide them along the ground (FootPlanter). Off, a stop cross-fades the gait into the
## idle as it did before (the review tool's before/after switch).
static var plant_feet := true
var _planter: FootPlanter = null
var _swimming := false                   ## in deep water: the Swim state is the one the body rests in
var _has_swim := false                   ## the rig has the swim clips
var _swim_w := 0.0                       ## the stroke against treading, eased over SWIM_BLEND_S

static var _clip_cache: Dictionary = {}


func _ready() -> void:
	if _rig_root == null:
		build()
	if not appearance_dict.is_empty():
		apply_appearance(appearance_dict)


## Takes the override materials off every mesh before the meshes go. Freed outright, a mesh's
## materials died with it while its render instance still named them, and the renderer said
## `Parameter "material" is null` once for every mesh on the body.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var meshes: Array = _default_eyes.duplicate()
	meshes.append_array(_default_meshes.values())
	for slot in _part_meshes:
		meshes.append_array(_part_meshes[slot])
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m == null or not is_instance_valid(m) or m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, null)


## Loads the rig and its clips. Safe to call once; `_ready` does it automatically.
func build() -> void:
	if _rig_root != null:
		return
	if _build_rig():
		_build_rest()


## `build` a piece at a time within the frame's budget (a person stood up while the world is drawn).
func _build_paced(slice: WorldPace.Slice) -> void:
	if _rig_root != null:
		return
	if _build_rig():
		await slice.pace("npc_rig")
		_build_rest()


## The rig's scene, kept: loaded again for every person stood up once the last had gone (a person's
## rig freed takes the scene's last reference), 20-30 ms of a frame here (TRIAGE item 36's second pass).
static var _rig_packed: PackedScene = null


func _build_rig() -> bool:
	var packed: PackedScene = _rig_packed
	if packed == null:
		packed = load(RIG_PATH)
		_rig_packed = packed
	if packed == null:
		push_error("HumanoidModel: cannot load %s" % RIG_PATH)
		return false
	_rig_root = packed.instantiate() as Node3D
	add_child(_rig_root)
	skeleton = _rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = _rig_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or anim_player == null:
		push_error("HumanoidModel: %s has no Skeleton3D/AnimationPlayer" % RIG_PATH)
		return false
	return true


func _build_rest() -> void:
	for mi in _rig_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var logical := _logical_name(m.name)
		if logical == "eyes":
			# two eyeballs share one logical name; keyed by it, the left one was lost
			_default_eyes.append(m)
			# And an eye's shadow falls inside the head's. Casting it is two more meshes in
			# every cascade of the sun for nothing: on Merrowby's street, twenty villagers in
			# view were 590 of 1328 draw calls, and their eyes about a hundred and thirty.
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_default_meshes[logical] = m
	_clip_data = _load_clip_data()
	_restore_contract_clip_names()
	_apply_loop_flags()
	_build_sockets()
	_build_animation_tree()
	_planter = FootPlanter.make(skeleton)
	arm_room = ArmRoom.new()
	arm_room.name = "ArmRoom"
	arm_room.hang = _idle_hang()
	skeleton.add_child(arm_room)
	# a skirt's bones posed from the thighs, after the clips, the planted feet and her carriage
	# (a rig built before them has none, and it does nothing)
	skirt_drive = SkirtDrive.new()
	skirt_drive.name = "SkirtDrive"
	skeleton.add_child(skirt_drive)


## How the upper arms and forearms hang in the Idle's first frame, bone index -> local rotation:
## what ArmRoom holds the arms in towards under a cloak.
func _idle_hang() -> Dictionary:
	var out := {}
	var idle := _find_animation("Idle")
	if idle == null:
		return out
	for i in idle.get_track_count():
		if idle.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name := idle.track_get_path(i).get_concatenated_subnames()
		if bone_name in ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]:
			var b := skeleton.find_bone(bone_name)
			if b >= 0:
				out[b] = idle.rotation_track_interpolate(i, 0.0)
	return out


## The rig GLB's meshes are named to avoid clashing with bone names (see the forge's
## `mesh_object_name`), so map them back to the slot they stand in for.
func _logical_name(n: String) -> String:
	var s := n.to_lower()
	if s.begins_with("body"):
		return "body"
	if s.begins_with("head"):
		return "head"
	if s.begins_with("eye"):
		return "eyes"
	return s


static func _load_clip_data() -> Dictionary:
	if _clip_cache.has(CLIPS_JSON):
		return _clip_cache[CLIPS_JSON]
	var out := {}
	if FileAccess.file_exists(CLIPS_JSON):
		var text := FileAccess.get_file_as_string(CLIPS_JSON)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
		else:
			push_warning("HumanoidModel: %s is not a JSON object" % CLIPS_JSON)
	else:
		push_warning("HumanoidModel: missing %s" % CLIPS_JSON)
	_clip_cache[CLIPS_JSON] = out
	return out


## Godot's glTF importer treats a "_Loop" (or "-loop", "_cycle", ...) suffix as a marker,
## strips it from the animation name and sets the loop mode — so `Jump_Loop` arrives as
## `Jump`. CONTRACTS.md §3 names are binding, so put them back; the sidecar says which
## names should exist.
func _restore_contract_clip_names() -> void:
	const SUFFIXES := ["_Loop", "-loop", "_loop", "_Cycle", "-cycle", "_cycle"]
	for wanted in _clip_data:
		var name := str(wanted)
		if _find_animation(name) != null:
			continue
		for suffix in SUFFIXES:
			if not name.ends_with(suffix):
				continue
			var stripped := name.substr(0, name.length() - suffix.length())
			for lib_name in anim_player.get_animation_library_list():
				var lib := anim_player.get_animation_library(lib_name)
				if lib.has_animation(stripped) and not lib.has_animation(name):
					lib.rename_animation(stripped, name)
					break
			break


## The sidecar is the source of truth for loop flags (CONTRACTS.md §3).
##
## A flag is written only when it is wrong, so in practice only by the first body built. The rig's
## Animations are one set of resources shared by every body built from it. Each write says
## `changed`, even of the same value, and every live AnimationTree answers `changed` by queueing
## a set-up of itself for later. Written on every build, one person stood up queued clips x bodies
## calls (82 x about 60). In a test that stood up the farms', mills' and caves' people, the message
## queue ran out of memory and the engine crashed. In the game it was a hitch on every spawn.
func _apply_loop_flags() -> void:
	for name in _clip_data:
		var anim := _find_animation(str(name))
		if anim == null:
			continue
		var want := Animation.LOOP_LINEAR if bool(_clip_data[name].get("loop", false)) else Animation.LOOP_NONE
		if anim.loop_mode != want:
			anim.loop_mode = want


func _find_animation(name: String) -> Animation:
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		if lib.has_animation(name):
			return lib.get_animation(name)
	return null


func has_clip(name: String) -> bool:
	return _find_animation(name) != null


func clip_names() -> PackedStringArray:
	return anim_player.get_animation_list()


func clip_length(name: String) -> float:
	var a := _find_animation(name)
	return a.length if a != null else 0.0


func clip_events(name: String) -> Array:
	var d: Variant = _clip_data.get(name, {})
	if typeof(d) != TYPE_DICTIONARY:
		return []
	return (d as Dictionary).get("events", [])


## A clip's own timeline, `{length, events}`: what the AnimationDriver keeps time by when its
## caller did not say. Empty when the rig has no such clip.
func clip_timing(name: String) -> Dictionary:
	if not has_clip(name):
		return {}
	var t := sidecar_timing(name)
	if t.is_empty() or float(t.get("length", 0.0)) <= 0.0:
		t = {"length": clip_length(name), "events": clip_events(name).duplicate(true)}
	return t


## The same, straight off the sidecar and without building a rig: a weapon measures its hit window
## against the clip it swings. Empty when the sidecar has no such clip.
static func sidecar_timing(name: String) -> Dictionary:
	var d: Variant = _load_clip_data().get(name, {})
	if typeof(d) != TYPE_DICTIONARY or (d as Dictionary).is_empty():
		return {}
	var data := d as Dictionary
	return {"length": float(data.get("length", 0.0)), "events": (data.get("events", []) as Array).duplicate(true)}


# ---------------------------------------------------------------------------------------
# sockets
# ---------------------------------------------------------------------------------------

func _build_sockets() -> void:
	for bone_name in SOCKETS:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			push_warning("HumanoidModel: rig has no socket bone %s" % bone_name)
			continue
		var att := BoneAttachment3D.new()
		att.name = "Socket%s" % SOCKETS[bone_name]
		att.bone_name = bone_name
		att.bone_idx = idx
		# Moved by the animation every frame, not by physics: interpolated between ticks it would
		# trail the hand (measured: a child moved per frame read 3.61 where it had been put at 4).
		# Off, it sits exactly on the bone of a body that is itself interpolated.
		att.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		skeleton.add_child(att)
		_sockets[bone_name] = att


## The BoneAttachment3D for a socket, by its contract name ("Socket.WeaponR") or short name
## ("WeaponR"). Returns null when the rig has no such socket.
func socket(name: String) -> BoneAttachment3D:
	if _sockets.has(name):
		return _sockets[name]
	var full := "Socket.%s" % name
	return _sockets.get(full, null)


func socket_names() -> Array:
	return _sockets.keys()


## Parents a node to a socket, replacing whatever was there.
func attach_to_socket(name: String, node: Node3D, clear_existing: bool = true) -> bool:
	var s := socket(name)
	if s == null:
		return false
	if clear_existing:
		for c in s.get_children():
			c.queue_free()
	s.add_child(node)
	return true


# ---------------------------------------------------------------------------------------
# appearance
# ---------------------------------------------------------------------------------------

## Given a `slice` (a person stood up while the world is drawn: NpcRegistry), the parts are put on
## a few at a time within the frame's budget (WorldPace), and it takes several frames: await it.
## Without one it is all done at once, as it always was.
func apply_appearance(d: Variant, slice: WorldPace.Slice = null) -> void:
	if _rig_root == null:
		if slice != null:
			# not in the frame the person is stood up in, when that frame's budget is spent
			await slice.pace("npc")
			await _build_paced(slice)
			await slice.pace("npc_rig")
		else:
			build()
	if skeleton == null:
		return
	appearance = d as CharacterAppearance if d is CharacterAppearance else CharacterAppearance.new(d as Dictionary)
	_applying = true
	appearance_dict = appearance.to_dict()
	_applying = false
	hair_worn = _hair_to_wear()
	# Parts are only torn down and put back when the parts change. A slider dragged across the
	# Naming used to rebuild every mesh on the body at every step of the drag.
	var signature := _parts_signature()
	if signature != _worn_signature:
		_clear_parts()
		var child := _child_body_ready()
		for slot in CharacterAppearance.SLOTS:
			var part_name := hair_worn if slot == "hair" else appearance.part(slot)
			if slot == "head":
				part_name = head_to_wear(part_name)
			part_name = over_skirt_cut(slot, part_name)
			if child:
				part_name = _child_cut(slot, part_name)
			if part_name.is_empty():
				continue
			if slice != null:
				# read on the loader's thread, the frames going on meanwhile, not in this frame
				var path := _part_path(slot, part_name)
				WorldStreamer.prefetch_paths([path])
				while WorldStreamer.still_reading(path):
					await WorldPace.next_frame()
					slice.t0 = Time.get_ticks_usec()
			_add_part(slot, part_name)
			if slice != null:
				await slice.pace("npc_part")
		_apply_morality_parts()
		if slice != null:
			await slice.pace("npc_part")
			# the body's part read on the loader's thread, as the others are
			await _read_ahead(slice, [_part_path("body", CHILD_BODY if appearance.body_variant() == CHILD_BODY else appearance.body_variant())])
		_apply_body_variant()
		if slice != null:
			await slice.pace("npc_body")
		# The head is always a part now, "default" included, and the rig's own head and eyes
		# stay hidden: the head parts carry the skull and the rig's copy is the old one. It
		# comes back only if the head part cannot be loaded at all.
		var own_head: bool = not _part_meshes.has("head")
		_show_default(_default_meshes.get("head"), own_head)
		for eye in _default_eyes:
			_show_default(eye, own_head)
		_worn_signature = signature
		_colour_signature = ""
	var colours := _colour_signature_now()
	if colours != _colour_signature:
		if slice != null:
			# a face's marks and zones read on the loader's thread; then a slot's colours a piece
			await _read_ahead(slice, _marks_paths())
			await _apply_colours(slice)
		else:
			await _apply_colours()
		_colour_signature = colours
	if slice != null:
		await _apply_jewellery(slice)
		await slice.pace("npc_jewellery")
	else:
		await _apply_jewellery()
	_apply_fits()
	_apply_proportions()
	if arm_room != null:
		arm_room.degrees = arm_room_for(appearance.part("torso"), body_variant_worn)
		# a child's head is sized by ChildProportions
		arm_room.head_scale = 1.0 if body_variant_worn == "child" else HEAD_SCALE
		# a grown woman's bearing: narrower shoulders, arms carried closer, a narrower stance and
		# her hips in the stride (ArmRoom.carriage)
		arm_room.carriage = 1.0 if appearance.is_woman() and appearance.body_variant() != CHILD_BODY else 0.0
		# the width of the shoulders, on the joints, so every sleeve and pauldron goes with them
		arm_room.shoulder_out = shoulders_out_for(appearance) if appearance.body_variant() != CHILD_BODY else 0.0
	_cloak_hold = arm_hold_for(appearance.part("back"))
	if first_person:
		_apply_first_person_look()
	appearance_changed.emit()


## Asks for `paths` on the loader's threads and waits, a frame at a time, until they are in.
func _read_ahead(slice: WorldPace.Slice, paths: Array) -> void:
	var wanted: Array = []
	for p in paths:
		if str(p) != "" and ResourceLoader.exists(str(p)):
			wanted.append(str(p))
	if wanted.is_empty():
		return
	WorldStreamer.prefetch_paths(wanted)
	for p in wanted:
		while WorldStreamer.still_reading(str(p)):
			await WorldPace.next_frame()
			slice.t0 = Time.get_ticks_usec()


## The face marks and zones the heads worn now are coloured with (`_face_marks`).
func _marks_paths() -> Array:
	var out: Array = []
	var heads: Array = []
	for mi in _part_meshes.get("head", []):
		if is_instance_valid(mi):
			heads.append(_part_path("head", str((mi as Node).get_meta("part", ""))).replace(".glb", "_marks.png"))
	heads.append(RIG_PATH.replace(".glb", "_head_marks.png"))
	for m in heads:
		if not out.has(m):
			out.append(m)
			out.append(str(m).replace("_marks.png", "_zones.png"))
	return out


## The skinned mesh a slot is worn as now ("head", "body", "hair"): the part's (its biggest mesh that
## is not an eye), or the rig's own head or body where no part stands in; null for none.
func worn_mesh(slot: String) -> MeshInstance3D:
	var best: MeshInstance3D = null
	for mi in _part_meshes.get(slot, []):
		var m := mi as MeshInstance3D
		if m == null or not is_instance_valid(m) or m.mesh == null or _is_eye(m):
			continue
		if best == null or _vertex_count(m) > _vertex_count(best):
			best = m
	if best == null and slot in ["head", "body"] and _default_meshes.has(slot):
		var own := _default_meshes[slot] as MeshInstance3D
		if own != null and own.visible:
			best = own
	return best


static func _vertex_count(mi: MeshInstance3D) -> int:
	return (mi.mesh as ArrayMesh).surface_get_array_len(0) if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0 else 0


## True when something covers the crown (a helm, a hood, a hood up): what is worn at the ears and in
## the hair is under it.
func head_covered() -> bool:
	for slot in COVERS_HEAD:
		if _covers_head(slot):
			return true
	return false


## Whether what is worn in `slot` covers the crown: a helm or a hood, or a part the forge says does
## (its meta's `covers_head`: a hat, a crown worn over a coif, a wimple).
func _covers_head(slot: String) -> bool:
	var worn := appearance.part(slot)
	if worn.is_empty():
		return false
	if worn in COVERS_HEAD.get(slot, []):
		return true
	return bool(_part_meta(slot, worn).get("covers_head", false))


## The jewellery (Adornment): one merged mesh of everything the record wears, built again when what
## it wears or what it is worn on changes. It is a part like any other (Adornment.SLOT), so the face's
## sliders and the grip reach its morph targets.
var _jewel_signature := ""


func _apply_jewellery(slice: WorldPace.Slice = null) -> void:
	var sig := "%s|%s|%s" % [_worn_signature, str(appearance.jewellery), body_variant_worn]
	if sig == _jewel_signature and (appearance.jewellery.is_empty() or _part_meshes.has(Adornment.SLOT)):
		return
	_jewel_signature = sig
	for mi in _part_meshes.get(Adornment.SLOT, []):
		if is_instance_valid(mi):
			mi.queue_free()
	_part_meshes.erase(Adornment.SLOT)
	var built: MeshInstance3D = await Adornment.build(self, slice)
	if built != null:
		_part_meshes[Adornment.SLOT] = [built]


## The head part a record wears for the face it chose: "default" for none, and a woman's cut of
## the face (`<face>_f`) on a woman when the forge has built it. The Naming offers one list of
## faces; the body chosen decides whose.
func head_to_wear(face: String) -> String:
	var chosen := face if not face.is_empty() else "default"
	if appearance.is_woman():
		var hers := chosen + CharacterAppearance.FEMININE_HEAD
		if ResourceLoader.exists(_part_path("head", hers)):
			return hers
	return chosen


## Everything that decides which meshes are on the body.
func _parts_signature() -> String:
	var bits: Array[String] = [hair_worn, appearance.body_variant(), str(appearance.is_woman()),
		"hollow%d" % int(appearance.hollow >= 0.66) + str(int(appearance.hollow >= 0.33)),
		"hearth%d" % int(appearance.hearth >= 0.66)]
	for slot in CharacterAppearance.SLOTS:
		bits.append("%s=%s" % [slot, appearance.part(slot)])
	return "|".join(bits)


## Everything that decides what colour those meshes are.
func _colour_signature_now() -> String:
	# a face's marks are laid on with the skin, so a record that only grows older is recoloured
	return "%s|%s|%s|%s|%s|%s|%s|%s|%.3f|%s|%.3f" % [appearance.skin, appearance.hair_colour, appearance.eye_colour,
		str(appearance.to_dict().get("palette", {})), str(face_marks_for(appearance)), appearance.brows,
		appearance.scar, appearance.paint, appearance.moles, str(appearance.is_woman()), appearance.hair_grey()] \
		+ str(appearance.tattoos)


## The hair the record chose, unless something is covering the crown.
func _hair_to_wear() -> String:
	var chosen := appearance.part("hair")
	if chosen.is_empty() or chosen in CharacterAppearance.CLOSE_HAIR:
		return chosen
	for slot in COVERS_HEAD:
		if _covers_head(slot):
			return UNDER_A_HOOD
	return chosen


## Freed at the end of the frame. A part put back in the same frame takes the same node names,
## and while the old meshes are still there the new ones are renamed `@MeshInstance3D@n` --
## which is why an eye is known by the `eye` meta `_add_part` gives it and not by its name: a
## head swapped for another used to lose the names its eyes were known by, and they were
## dressed in skin.
func _clear_parts() -> void:
	_worn_signature = ""
	for slot in _part_meshes:
		for mi in _part_meshes[slot]:
			if is_instance_valid(mi):
				mi.queue_free()
	_part_meshes.clear()


func _show_default(mi: MeshInstance3D, visible_now: bool) -> void:
	if mi != null:
		mi.visible = visible_now


## Morality visuals that are *parts* rather than colours (DESIGN.md §5.11).
func _apply_morality_parts() -> void:
	if appearance.hollow >= 0.66:
		_add_part("attachment", "horns_big")
	elif appearance.hollow >= 0.33:
		_add_part("attachment", "horns_small")
	if appearance.hearth >= 0.66:
		_add_part("attachment", "halo")


func _part_path(slot: String, part_name: String) -> String:
	var dir: String = SLOT_DIRS.get(slot, "clothing")
	var path := "%s%s/%s/%s.glb" % [PARTS_ROOT, dir, part_name, part_name]
	if dir == "attachments" and not ResourceLoader.exists(path):
		# a garment worn in the spare slot: a boss's plate over its tabard, a founder's apron over
		# his shirt (EnemyDress), from the clothing it is built as
		return "%sclothing/%s/%s.glb" % [PARTS_ROOT, part_name, part_name]
	return path


## The forge's meta for a part (what it is made of, its fits), read once per part.
func _part_meta(slot: String, part_name: String) -> Dictionary:
	var path := _part_path(slot, part_name).replace(".glb", ".meta.json")
	if _meta_cache.has(path):
		return _meta_cache[path]
	var out := {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
	_meta_cache[path] = out
	return out


func _add_part(slot: String, part_name: String) -> bool:
	var path := _part_path(slot, part_name)
	if not ResourceLoader.exists(path):
		push_warning("HumanoidModel: missing part %s (%s)" % [part_name, path])
		return false
	var packed: PackedScene = _part_cache.get(path, null)
	if packed == null:
		packed = WorldStreamer.load_asset(path, false) as PackedScene
		_part_cache[path] = packed
	if packed == null:
		return false
	var inst := packed.instantiate()
	var added: Array[MeshInstance3D] = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var src := mi as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.name = "%s_%s" % [slot, src.name]
		copy.mesh = src.mesh
		copy.skin = src.skin
		copy.transform = Transform3D.IDENTITY
		skeleton.add_child(copy)
		# every part is skinned to this same rig, so the shared Skeleton3D drives it
		copy.skeleton = copy.get_path_to(skeleton)
		copy.set_meta("slot", slot)
		copy.set_meta("part", part_name)
		copy.set_meta("eye", str(src.name).to_lower().contains("eye"))
		# a harness is several meshes of several materials (a coat under steel); the meta says
		# which mesh is which, and a single-mesh part falls back to its one material
		var meta := _part_meta(slot, part_name)
		var per_mesh: Dictionary = meta.get("materials", {})
		copy.set_meta("material", str(per_mesh.get(str(src.name), meta.get("material", ""))))
		# a cloth woven in its own colours (the clans' tartan) is lit as cloth but not tinted
		copy.set_meta("tint", str(meta.get("tint", "")))
		# the palette colour it is dressed in, when the forge says (a felt hat is the cloth's, not the
		# helm's metal its slot would give it)
		var keys: Dictionary = meta.get("colour_keys", {}) if meta.get("colour_keys") is Dictionary else {}
		copy.set_meta("colour_key", str(keys.get(str(src.name), meta.get("colour_key", ""))))
		_hair_lod(copy, meta)
		added.append(copy)
	inst.queue_free()
	if added.is_empty():
		return false
	if not _part_meshes.has(slot):
		_part_meshes[slot] = []
	_part_meshes[slot].append_array(added)
	return true


## A style with cards (triage 47) wears them close and its shell far: the cards to CARDS_RANGE, the
## shell from there on, with a metre of overlap either side so neither flickers at the line.
func _hair_lod(mi: MeshInstance3D, meta: Dictionary) -> void:
	var cards := str(meta.get("cards", ""))
	if cards.is_empty():
		return
	if str(mi.get_meta("material", "")) == "hair_cards":
		mi.visibility_range_end = CARDS_RANGE
		mi.visibility_range_end_margin = CARDS_RANGE_MARGIN
	elif str(mi.get_meta("material", "")) == "hair":
		mi.visibility_range_begin = CARDS_RANGE
		mi.visibility_range_begin_margin = CARDS_RANGE_MARGIN


## Every rig, head, hair shell and garment is baked once, in one colour: the record's skin,
## eyes and hair are tints relative to those bakes, and cloth takes the palette's colour for
## its role. Skin used to be applied only when a palette spelled out `skin_tint`, so the tone
## the record named was never seen on a body, and a head part fell through to the cloth
## palette's primary.
func _apply_colours(slice: WorldPace.Slice = null) -> void:
	var pal := appearance.palette
	var skin := appearance.skin_tint()
	for slot in _part_meshes:
		if slice != null:
			await slice.pace("npc_colours")
		for mi in _part_meshes[slot]:
			# A body variant is skin, not cloth. Without this it falls through to
			# `_colour_key_for`, which has no key for it, and a heavy villager keeps the
			# bake's own default tone while his face takes the record's.
			if slot == "body":
				_skin(mi, skin)
				Adornment.dress_body(mi, appearance, skeleton)
				continue
			if slot == Adornment.SLOT:
				# lit by what each piece is made of (Adornment), not dressed
				continue
			if slot == "head":
				if _is_eye(mi):
					_tint_iris(mi)
				else:
					_skin(mi, skin)
					_face_marks(mi, _part_path(slot, str(mi.get_meta("part", ""))).replace(".glb", "_marks.png"))
					_face_overlay(mi)
				continue
			var key := _colour_key_for(slot)
			var kind := str(mi.get_meta("material", ""))
			if slot == "hair" or slot == "beard":
				_dress(mi, appearance.hair_tint() if not pal.has("hair") else pal["hair"] as Color, "hair")
				if slot == "beard" and str(mi.get_meta("part", "")) == STUBBLE:
					_as_stubble(mi)
				elif slot == "hair" and str(mi.get_meta("part", "")) in CharacterAppearance.SHADOW_HAIR:
					# a shaven head is a shadow on the scalp, as stubble is on the jaw
					_as_stubble(mi, SHAVEN_ALPHA)
				continue
			if str(mi.get_meta("tint", "")) == "none":
				_dress(mi, Color.WHITE, kind, true)
				continue
			# Steel is the people's metal and leather their leather, whichever slot it is worn
			# in: a Vale cuirass was tinted the Vale's wool brown because it sat in `torso`.
			var colour_key := key
			var own_key := str(mi.get_meta("colour_key", ""))
			if kind == "iron" and pal.has("metal"):
				colour_key = "metal"
			elif not own_key.is_empty() and pal.has(own_key):
				colour_key = own_key
			elif kind == "leather" and pal.has("leather"):
				colour_key = "leather"
			if pal.has(colour_key):
				_dress(mi, pal[colour_key] as Color, kind)
	if slice != null:
		await slice.pace("npc_colours")
	for logical in ["body", "head"]:
		if _default_meshes.has(logical):
			_skin(_default_meshes[logical], skin)
	if _default_meshes.has("body"):
		Adornment.dress_body(_default_meshes["body"], appearance, skeleton)
	if _default_meshes.has("head"):
		_face_marks(_default_meshes["head"], RIG_PATH.replace(".glb", "_head_marks.png"))
	for eye in _default_eyes:
		_tint_iris(eye)


## Skin wears the skin shader, carrying the bake's own maps across and the record's tone as a
## tint against the bake.
func _skin(mi: MeshInstance3D, tint: Color) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	for i in count:
		var worn := mi.get_surface_override_material(i) as ShaderMaterial
		if worn != null and worn.shader == SKIN_SHADER:
			worn.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
			continue
		var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
		var m := ShaderMaterial.new()
		m.shader = SKIN_SHADER
		if base != null:
			m.set_shader_parameter("albedo_tex", base.albedo_texture)
			var orm: Texture2D = base.roughness_texture if base.roughness_texture != null else base.ao_texture
			m.set_shader_parameter("orm_tex", orm)
			m.set_shader_parameter("use_orm", orm != null)
			m.set_shader_parameter("normal_tex", base.normal_texture)
			m.set_shader_parameter("use_normal", base.normal_texture != null)
		m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		var detail := _detail(SKIN_DETAIL)
		m.set_shader_parameter("detail_normal", detail)
		m.set_shader_parameter("use_detail", detail != null)
		var is_body := str(mi.get_meta("slot", "")) == "body" or mi.name.to_lower().begins_with("body")
		m.set_shader_parameter("detail_scale", SKIN_DETAIL_SCALE_BODY if is_body else SKIN_DETAIL_SCALE_HEAD)
		mi.set_surface_override_material(i, m)


## Every head is baked young. Its lines of age come in with the years: none up to AGE_LINES_FROM,
## all of them at AGE_LINES_FULL (CharacterAppearance.age, 0 young .. 1 old).
const AGE_LINES_FROM := 0.30
const AGE_LINES_FULL := 0.85


static func age_lines_amount(age: float) -> float:
	return clampf((age - AGE_LINES_FROM) / (AGE_LINES_FULL - AGE_LINES_FROM), 0.0, 1.0)


## How much of each of a head's marks this person shows: the lines of age by their age, a
## ruddiness and a weathering of their own (from their seed, their people and their years) and
## their freckles. The values a face's marks_tex is read with (skin.gdshader).
const RUDDY_BY_CULTURE := {"clans": 0.25, "woodfolk": 0.12, "vale": 0.10, "lakefolk": 0.0,
	"reedfolk": -0.10, "ash_pilgrims": -0.15}


static func face_marks_for(a: CharacterAppearance) -> Dictionary:
	var h := absi(hash("%d|marks" % a.seed))
	var r1 := float(h % 1000) / 999.0
	var r2 := float(floori(h / 1000.0) % 1000) / 999.0
	return {
		"age": age_lines_amount(a.age),
		"ruddy": clampf(0.10 + 0.35 * r1 + float(RUDDY_BY_CULTURE.get(a.culture, 0.0)) + 0.15 * a.age, 0.0, 1.0),
		"freckles": clampf(a.freckles * 1.6, 0.0, 1.0),
		"weather": clampf(0.10 + 0.35 * r2 + 0.55 * a.age, 0.0, 1.0),
	}


## Which side of this person's face is a little higher, and by how much: a brow and a corner of
## the mouth (the head's morph targets, the forge's body.face_asymmetry), from their seed.
static func face_asymmetry_for(a: CharacterAppearance) -> Dictionary:
	var h := absi(hash("%d|asym" % a.seed))
	var brow := 0.30 + 0.70 * float(floori(h / 2.0) % 100) / 99.0
	var mouth := 0.20 + 0.60 * float(floori(h / 400.0) % 100) / 99.0
	var brow_left := h % 2 == 0
	var mouth_left := floori(h / 200.0) % 2 == 0
	return {
		"brow_up_L": brow if brow_left else 0.0, "brow_up_R": 0.0 if brow_left else brow,
		"mouth_up_L": mouth if mouth_left else 0.0, "mouth_up_R": 0.0 if mouth_left else mouth,
	}


func _face_marks(mi: MeshInstance3D, marks_path: String) -> void:
	var tex: Texture2D = WorldStreamer.load_asset(marks_path) as Texture2D if ResourceLoader.exists(marks_path) else null
	# and where its skin is warmer, cooler, oilier and thinner, beside the marks (paint.face_zones)
	var zones_path := marks_path.replace("_marks.png", "_zones.png")
	var zones: Texture2D = WorldStreamer.load_asset(zones_path) as Texture2D if ResourceLoader.exists(zones_path) else null
	var marks := face_marks_for(appearance)
	for i in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
		var m := mi.get_surface_override_material(i) as ShaderMaterial
		if m == null or m.shader != SKIN_SHADER:
			continue
		m.set_shader_parameter("marks_tex", tex)
		m.set_shader_parameter("zones_tex", zones)
		for key in marks:
			var param: String = "freckle_amount" if key == "freckles" else "%s_amount" % key
			m.set_shader_parameter(param, float(marks[key]) if tex != null else 0.0)


## The person's brows, scar, moles and face paint, drawn over the head (assets/shaders/face_marks):
## the head's material_overlay, in the face coordinates the forge wrote as its UV2. Only a head with
## one of them has it, so a plain face costs no second pass.
func _face_overlay(mi: MeshInstance3D) -> void:
	var a := appearance
	var params := face_overlay_params(a)
	if not bool(params["any"]):
		mi.material_overlay = null
		return
	var m := mi.material_overlay as ShaderMaterial
	if m == null or m.shader != FACE_MARKS_SHADER:
		m = ShaderMaterial.new()
		m.shader = FACE_MARKS_SHADER
		mi.material_overlay = m
	for key in params:
		if key != "any":
			m.set_shader_parameter(key, params[key])


## What the face overlay is drawn with for this record (the tests ask it too).
static func face_overlay_params(a: CharacterAppearance) -> Dictionary:
	var brow := CharacterAppearance.BROW_STYLES.find(a.brows)
	var scar := CharacterAppearance.SCARS.find(a.scar)
	var paint := CharacterAppearance.PAINTS.find(a.paint)
	var hair := a.hair_worn_colour()
	# brows are the hair's colour, a little darker, and grey more slowly than the head
	var brow_col := CharacterAppearance.hair_colour_value(a.hair_colour).lerp(hair, 0.6).darkened(0.18)
	var out := {
		"any": brow > 0 or scar > 0 or paint > 0 or a.moles > 0.01 or not a.face_tattoos().is_empty(),
		"brow_style": maxi(brow, 0), "brow_colour": brow_col, "brow_lift": 0.003 if a.is_woman() else 0.0,
		"scar": maxi(scar, 0), "skin_colour": CharacterAppearance.skin_colour(a.skin),
		"moles": a.moles, "mole_seed": float(absi(a.seed) % 997),
		"paint": maxi(paint, 0),
	}
	# and its tattoos (triage 48)
	out.merge(Adornment.face_tattoo_params(a), true)
	return out


## What a skin's tint is, from whichever material it is wearing (the tests and the probes ask).
static func skin_tint_of(mi: MeshInstance3D) -> Color:
	var m := mi.get_surface_override_material(0)
	if m is ShaderMaterial:
		var v: Variant = (m as ShaderMaterial).get_shader_parameter("tint")
		if v is Vector3:
			return Color(v.x, v.y, v.z)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color(-1, -1, -1)


## Cloth, leather, metal and hair are baked as value and grain; here each is also lit as what it
## is. Wool and linen catch a soft light along their edges, which is what reads as cloth at a
## distance; leather takes a tighter sheen; hair a brighter edge where the light comes through
## it. Metal needs nothing but its own metallic map and something to reflect.
##
## A mesh keeps the one material it was dressed in and only its colour changes after that. A
## look made in one frame (a preset, the lots, a probe) used to build a fresh material for every
## mesh at every step and drop the last one, and the Compatibility renderer was left holding
## materials that no longer existed: eyes stopped drawing, and the log filled with
## `Parameter "material" is null`.
## Stubble is a shell a millimetre and a half over the jaw, drawn in the hair colour: opaque,
## it was a full short beard. Seen through, it is a shadow on the skin, which is what stubble is.
const STUBBLE := "stubble"
const STUBBLE_ALPHA := 0.42
const SHAVEN_ALPHA := 0.55


func _as_stubble(mi: MeshInstance3D, alpha := STUBBLE_ALPHA) -> void:
	for i in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
		var m := mi.get_surface_override_material(i)
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("alpha", alpha)
		elif m is BaseMaterial3D:
			(m as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			(m as BaseMaterial3D).albedo_color.a = alpha
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _dress(mi: MeshInstance3D, c: Color, kind: String, woven := false) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	var garment := GARMENT_KINDS.has(kind) or kind == "" or woven
	for i in count:
		var worn := mi.get_surface_override_material(i)
		if worn != null and worn.has_meta("dressed"):
			_set_dress_colour(worn, c)
			continue
		var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if kind == "hair" and str(mi.get_meta("material", "")) == "hair_cards":
			mi.set_surface_override_material(i, _hair_cards_material(c))
			continue
		if kind == "hair":
			# a shaven head is drawn as stubble is: a shadow of hair on the skin (triage 39)
			var stubble := str(mi.get_meta("part", "")) == STUBBLE \
					or str(mi.get_meta("part", "")) in CharacterAppearance.SHADOW_HAIR
			mi.set_surface_override_material(i, _hair_material(base, c, STUBBLE_SHADER if stubble else HAIR_SHADER))
			continue
		if garment:
			var spec: Array = GARMENT_KINDS.get(kind, GARMENT_KINDS["cloth"])
			var sm := ShaderMaterial.new()
			sm.shader = GARMENT_SHADER
			sm.set_meta("dressed", true)
			if base != null:
				sm.set_shader_parameter("albedo_tex", base.albedo_texture)
				var orm: Texture2D = base.roughness_texture if base.roughness_texture != null else base.ao_texture
				sm.set_shader_parameter("orm_tex", orm)
				sm.set_shader_parameter("use_orm", orm != null)
			sm.set_shader_parameter("kind", 3 if woven else int(spec[0]))
			sm.set_shader_parameter("detail_normal", _detail(str(spec[1])))
			sm.set_shader_parameter("mottle_tex", _detail("mottle.png"))
			sm.set_shader_parameter("detail_scale", float(spec[2]))
			sm.set_shader_parameter("detail_depth", float(spec[3]))
			_set_dress_colour(sm, c)
			mi.set_surface_override_material(i, sm)
			continue
		var m := (base.duplicate() if base != null else StandardMaterial3D.new()) as BaseMaterial3D
		if m == null:
			continue
		m.set_meta("dressed", true)
		m.albedo_color = c
		if kind == "hair":
			m.rim_enabled = true
			m.rim = 0.45
			m.rim_tint = 0.40
			m.metallic_specular = 0.40
		mi.set_surface_override_material(i, m)


## Hair wears the hair shader, carrying the bake's maps across, and the style's flow map from
## beside its normal map when the style has one (a style built before them is lit without the
## strand direction, as hair falling down the head).
func _hair_material(base: BaseMaterial3D, c: Color, shader: Shader) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.set_meta("dressed", true)
	if base != null:
		sm.set_shader_parameter("albedo_tex", base.albedo_texture)
		var orm: Texture2D = base.roughness_texture if base.roughness_texture != null else base.ao_texture
		sm.set_shader_parameter("orm_tex", orm)
		sm.set_shader_parameter("use_orm", orm != null)
		sm.set_shader_parameter("normal_tex", base.normal_texture)
		sm.set_shader_parameter("use_normal", base.normal_texture != null)
		var flow: Texture2D = null
		if base.normal_texture != null:
			var flow_path := base.normal_texture.resource_path.replace("_normal.png", "_flow.png")
			if flow_path.ends_with("_flow.png") and ResourceLoader.exists(flow_path):
				flow = load(flow_path)
		sm.set_shader_parameter("flow_tex", flow)
		sm.set_shader_parameter("use_flow", flow != null)
	_set_dress_colour(sm, c)
	return sm


## The cards' material: the shared strand atlas and grain, and the person's colour as the shell's
## tint is (a ratio against the bake's brown).
func _hair_cards_material(c: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = HAIR_CARDS_SHADER
	sm.set_meta("dressed", true)
	sm.set_shader_parameter("strand_tex", _detail(HAIR_STRANDS))
	sm.set_shader_parameter("grain_tex", _detail(HAIR_GRAIN))
	_set_dress_colour(sm, c)
	return sm


func _set_dress_colour(m: Material, c: Color) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	elif m is BaseMaterial3D:
		(m as BaseMaterial3D).albedo_color = c


static func _detail(file: String) -> Texture2D:
	if not _detail_cache.has(file):
		_detail_cache[file] = load(DETAIL_DIR + file) if ResourceLoader.exists(DETAIL_DIR + file) else null
	return _detail_cache[file]


## The colour a dressed part is worn in, whichever material it wears (the tests ask).
static func dressed_colour_of(mi: MeshInstance3D) -> Color:
	var m := mi.get_surface_override_material(0)
	if m is ShaderMaterial:
		var v: Variant = (m as ShaderMaterial).get_shader_parameter("tint")
		var k: Variant = (m as ShaderMaterial).get_shader_parameter("kind")   # null when left at 0
		if k != null and int(k) == 3:
			return Color.WHITE
		if v is Vector3:
			return Color(v.x, v.y, v.z)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color(-1, -1, -1)


## Every garment is built on the default body and carries the other bodies it has been cut for
## as morph targets, fitted by the forge (FITTED_BODIES), so a heavy villager's tunic is cut for
## him and a woman's for her instead of the body standing through it. Beards carry one target per face, because a beard lies on a
## jaw and the faces' jaws are not one jaw.
func _apply_fits() -> void:
	var head := appearance.part("head")
	var asym := face_asymmetry_for(appearance)
	for slot in _part_meshes:
		for mi in _part_meshes[slot]:
			var m := mi as MeshInstance3D
			if m == null or m.mesh == null or not (m.mesh is ArrayMesh):
				continue
			# The importer's LODs were cut on the garment as built, on the default body. Fitted to
			# another, a coarse LOD no longer follows the fit: across a street a woman's tunic
			# dropped to one that lay flat over the chest, and her bust came through it in two
			# patches that the full mesh covers. A fitted garment keeps its detail further out.
			# The same holds on the body a garment was built on: a coarse LOD's flat facets cut in
			# across the curve of a chest or a thigh further than a close garment stands off it, and
			# a man's tunic showed skin at the waist across a street (triage 29). Measured on every
			# garment's LODs (the body's vertices a LOD leaves outside it), the torso's, the legs' and
			# the back's did it at 15-30 m, belts, boots, gloves and hoods not at all.
			m.lod_bias = FITTED_LOD_BIAS if (slot in FITTED_SLOTS and body_variant_worn in FITTED_BODIES) \
					or slot in CLOSE_LOD_SLOTS else 1.0
			if str(m.get_meta("material", "")) == "hair_cards":
				# the importer's decimated LODs of a card mesh are cards with their tips welded
				# together; the cards keep their detail and give way to the shell (_hair_lod)
				m.lod_bias = CARDS_LOD_BIAS
			var shapes := (m.mesh as ArrayMesh).get_blend_shape_count()
			for b in shapes:
				var shape := str((m.mesh as ArrayMesh).get_blend_shape_name(b))
				var on := false
				if shape.begins_with("grip_"):
					# the hands' own morphs, kept at what set_grip has them at
					m.set_blend_shape_value(b, float(_grip.get(shape.substr(5), 0.0)))
					continue
				if shape.begins_with(FACE_TARGET):
					# the face's sliders and its years, on the head, its eyes, and whatever lies over
					# the face (a beard, the hair's fringe, a hood's opening) so it goes with it
					m.set_blend_shape_value(b, appearance.face_weight(shape.substr(FACE_TARGET.length())))
					continue
				if shape in BUST_TARGETS:
					m.set_blend_shape_value(b, appearance.bust_weight()
							if body_variant_worn == CharacterAppearance.WOMAN_BODY else 0.0)
					continue
				if slot == "head":
					# a face's own asymmetry, by the person
					m.set_blend_shape_value(b, float(asym.get(shape, 0.0)))
					continue
				if slot == Adornment.SLOT and asym.has(shape):
					# a piece on the face goes with the face's own asymmetry, as its skin does
					m.set_blend_shape_value(b, float(asym[shape]))
					continue
				if shape in FITTED_BODIES:
					on = shape == body_variant_worn
				elif slot == "beard" or slot == "hair" or slot == Adornment.SLOT:
					on = shape == head
				m.set_blend_shape_value(b, 1.0 if on else 0.0)


## Close a hand round what it holds, or open it: `side` "L" or "R", `amount` 0 (open, the hand as
## it is modelled) to 1 (a fist round a haft on the socket's axis, Socket.WeaponR or WeaponL). The
## rig has no finger bones; the body, the variant bodies and the gloves carry the closed hand as
## the morph targets grip_L and grip_R, and this sets them, eased over GRIP_BLEND_S -- or at once
## with `now`, for a body that is not being processed. A part put on later gets the same value.
func set_grip(side: String, amount: float = 1.0, now: bool = false) -> void:
	if not _grip_to.has(side):
		push_warning("HumanoidModel.set_grip: no hand '%s'" % side)
		return
	_grip_to[side] = clampf(amount, 0.0, 1.0)
	if now:
		_grip[side] = _grip_to[side]
		_apply_grip()


## How closed a hand is now, 0..1 (see set_grip).
func grip(side: String) -> float:
	return float(_grip.get(side, 0.0))


const GRIP_BLEND_S := 0.1
## Where the closed hand holds a haft, from the weapon socket's origin in the socket's own frame
## (metres, on the default body; the rig's scale carries it for any height): the fist closes round
## a line through here along the socket's +Y. The socket sits in the palm's centre, and moved to
## here every grip-led clip, solved for where the socket goes, came out turned at the wrist; so the
## held thing is offset instead (forge `grip.grip_offset`).
const GRIP_OFFSET := {"R": Vector3(-0.0177, 0.0, -0.0018), "L": Vector3(0.0177, 0.0, -0.0018)}


## The position, under Socket.WeaponR or WeaponL, to put a held thing's grip centre at, so that
## the closed hand (set_grip) is round it.
static func grip_offset(side: String) -> Vector3:
	return GRIP_OFFSET.get(side, Vector3.ZERO)


func _ease_grip(delta: float) -> void:
	var moved := false
	for side in _grip:
		var to := float(_grip_to[side])
		if not is_equal_approx(float(_grip[side]), to):
			_grip[side] = move_toward(float(_grip[side]), to, delta / GRIP_BLEND_S)
			moved = true
	if moved:
		_apply_grip()


## Every mesh on the body that has the closed hands as morphs: the rig's own body and any part.
func _apply_grip() -> void:
	var meshes: Array = _default_meshes.values()
	for slot in _part_meshes:
		meshes.append_array(_part_meshes[slot])
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m == null or not is_instance_valid(m) or m.mesh == null:
			continue
		for side in _grip:
			var b := m.find_blend_shape_by_name(StringName("grip_" + str(side)))
			if b >= 0:
				m.set_blend_shape_value(b, float(_grip[side]))


func _is_eye(mi: MeshInstance3D) -> bool:
	if mi.has_meta("eye"):
		return bool(mi.get_meta("eye"))
	return mi.name.to_lower().contains("eye")


## The eyeball keeps its baked texture; only the iris band is recoloured.
func _tint_iris(mi: MeshInstance3D) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	var tint := appearance.iris_tint()
	for i in count:
		var worn := mi.get_surface_override_material(i) as ShaderMaterial
		if worn != null and worn.shader == IRIS_SHADER:
			worn.set_shader_parameter("iris_tint", Vector3(tint.r, tint.g, tint.b))
			continue
		var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
		var m := ShaderMaterial.new()
		m.shader = IRIS_SHADER
		if base != null and base.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", base.albedo_texture)
		m.set_shader_parameter("iris_tint", Vector3(tint.r, tint.g, tint.b))
		mi.set_surface_override_material(i, m)


func _colour_key_for(slot: String) -> String:
	match slot:
		"torso", "back":
			return "primary"
		"legs":
			return "secondary"
		"feet", "belt", "hands":
			return "leather"
		"headgear":
			return "metal"
		"hair", "beard":
			return "hair"
	return "primary"


## Body variants that may be worn on *this* rig, and the one that may not.
##
## `_add_part` re-skins a part's mesh onto the shared `Skeleton3D`, which is only honest
## when the part was built around the same bones. Measured against the default skeleton,
## the worst joint in `slight` moves 3.3 mm and in `heavy` 1.9 mm -- they are shape, not
## skeleton, and they wear straight onto this rig.
##
## `child` is a different skeleton: its hips sit at 0.646 m against 0.980, its upper arm is
## 192 mm against 292, and its worst joint is 476 mm from the adult's, 9.2 m summed over
## 29 bones. Draping that mesh on adult bones would stretch a child back into an adult, so it
## is not worn like the others: `_apply_child` re-proportions the rig itself (see
## ChildProportions) and the child body goes on that.
##
## `woman` is shape too, and less than either: the forge keeps a woman's body on the default
## joints exactly (character_forge MESH_ONLY), her hips, waist and bust in the mesh alone.
const WEARABLE_BODIES := ["slight", "heavy", "woman"]
## The morph targets on a garment that are a body's fit, named after the body.
const FITTED_BODIES := ["slight", "heavy", "woman"]
## How much longer a garment worn in its fit keeps its full detail (MeshInstance3D.lod_bias).
const FITTED_LOD_BIAS := 4.0
## Slots whose garments keep that detail on any body: the ones lying close over the trunk and the legs.
const CLOSE_LOD_SLOTS := ["torso", "legs", "back"]
const CHILD_BODY := "child"
## What a child wears in a slot whose garment has no child's cut: the plain garment of that
## slot. A slot missing here (hands, back) is left bare rather than draped in a grown cut.
const CHILD_STAND_INS := {"torso": "tunic", "legs": "trousers", "feet": "shoes", "belt": "belt"}
## A garment cut again to hang from the skirt's bones (SkirtDrive), worn in place of its plain cut
## when a long skirt that hangs from them is worn under it: weighted otherwise than the skirt, the
## skirt came through it in every gait, and hung from them over trousers a sprinting thigh came
## through its open front (PROGRESS "Skirts that swing from their own bones").
const OVER_SKIRT := {"coat": "coat_skirt"}
const SKIRT_BONE_LEGS := ["long_skirt", "wrap_skirt"]


## The part worn in `slot` for `part_name`, given what is worn under it (OVER_SKIRT).
func over_skirt_cut(slot: String, part_name: String) -> String:
	if slot != "torso" or not OVER_SKIRT.has(part_name) or appearance == null:
		return part_name
	if not (appearance.part("legs") in SKIRT_BONE_LEGS):
		return part_name
	var cut := str(OVER_SKIRT[part_name])
	return cut if ResourceLoader.exists(_part_path(slot, cut)) else part_name


## Slots whose parts are skinned to the body and so are cut per skeleton. Everything else
## (head, hair, beard, headgear, attachments) is rigid to the head and fits any skeleton.
const CUT_PER_SKELETON := ["torso", "legs", "feet", "hands", "belt", "back"]

var _child_mod: ChildProportions = null
var _child_height := 1.30
## Off, a child is the grown rig scaled down to a child's height, as before it had a skeleton
## of its own (the review tool's before/after switch).
static var child_rig := true


## The body this record wears, when it is not the default one.
##
## `CharacterAppearance.body_variant()` has always named the right one and nothing ever
## loaded it, because `bodies/child`, `heavy` and `slight` each held a 31-bone skeleton and
## no mesh at all: the forge built the geometry and the glTF exporter dropped it as invalid
## without failing the build.
##
## And only under clothes cut for it. The heavy body is wider than every garment built on the
## default one, so wearing it under them showed skin through the gambeson, the coat and the
## tunic at the heavy end of the Naming's build slider. A garment the forge has fitted carries
## the variant as a morph target and says so in its meta (`fits`); until every garment on the
## body does, the default body is worn and the rig's girth does the widening.
func _apply_body_variant() -> void:
	var variant := appearance.body_variant()
	if variant == CHILD_BODY and _child_body_ready() and _add_part("body", CHILD_BODY):
		body_variant_worn = CHILD_BODY
		_apply_child(true)
	else:
		_apply_child(false)
		var wearable: bool = WEARABLE_BODIES.has(variant) and _garments_fit(variant)
		body_variant_worn = variant if wearable and _add_part("body", variant) else ""
	_show_default(_default_meshes.get("body"), body_variant_worn.is_empty())


## True when this record is a child's and the forge has built the child's body and the
## clothes cut for it. Without the clothes the child body would stand in the street bare, and
## the grown rig scaled down is the better of the two.
func _child_body_ready() -> bool:
	return child_rig and appearance.body_variant() == CHILD_BODY \
			and ResourceLoader.exists(_part_path("body", CHILD_BODY)) \
			and ResourceLoader.exists(_part_path("torso", "%s_child" % CHILD_STAND_INS["torso"]))


## The part a child wears in `slot` for `part_name`: rigid parts as they are, a garment's
## child cut when the forge made one, otherwise the plain garment of the slot, otherwise none.
func _child_cut(slot: String, part_name: String) -> String:
	if part_name.is_empty() or not CUT_PER_SKELETON.has(slot):
		return part_name
	for candidate in [part_name, str(CHILD_STAND_INS.get(slot, ""))]:
		if candidate.is_empty():
			continue
		var cut := "%s_child" % candidate
		if ResourceLoader.exists(_part_path(slot, cut)):
			return cut
	return ""


## Puts the rig at the child's proportions (or back). The child's rest pose is read off the
## forge's child body, and its head scale off the proportions that body was built at: the
## heads are the grown ones and a child's is 0.86 of a grown head at 1.30 m.
func _apply_child(on: bool) -> void:
	if not on:
		if _child_mod != null:
			_child_mod.queue_free()
			_child_mod = null
		return
	if _child_mod != null:
		return
	var packed: PackedScene = _part_cache.get(_part_path("body", CHILD_BODY), null)
	if packed == null:
		packed = load(_part_path("body", CHILD_BODY))
	if packed == null:
		return
	var inst := packed.instantiate()
	var child_skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if child_skel == null:
		inst.free()
		return
	var props: Dictionary = _part_meta("body", CHILD_BODY).get("params", {}).get("proportions", {})
	_child_height = float(props.get("height", 1.30))
	var head_scale := float(props.get("head_size", 1.0)) * _child_height / 1.78
	_child_mod = ChildProportions.new()
	_child_mod.name = "ChildProportions"
	_child_mod.setup(skeleton, child_skel, head_scale)
	inst.free()
	skeleton.add_child(_child_mod)


## Slots whose garments take their weights from the body and so have to be cut for it.
const FITTED_SLOTS := ["torso", "legs", "feet", "hands", "belt", "back"]


func _garments_fit(variant: String) -> bool:
	if variant == CHILD_BODY:
		return true
	for slot in FITTED_SLOTS:
		var part_name := appearance.part(slot)
		if part_name.is_empty():
			continue
		var fits: Array = _part_meta(slot, part_name).get("fits", [])
		if not fits.has(variant):
			return false
	return true


## Runtime bone scaling would break clips authored on the default proportions
## (CONTRACTS.md §2), so overall size is a uniform scale.
##
## The widening is the fallback and only the fallback. With a real variant on, the shape is
## in the mesh -- baked at the proportions the forge was given -- and scaling the rig as
## well would count the same build twice and hand a heavy villager a second helping of
## width.
##
## The build slider used to do nothing at all across its middle third: the body variant only
## changes at 0.30 and 0.68, and with a variant on the rig was not widened. Now the girth the
## slider asks for is one continuous line from slight to broad, and the rig makes up the
## difference between it and the girth of whichever body is worn -- so each variant's own
## shape (narrow shoulders, a heavy middle) comes in at its end without the width jumping,
## and nothing is counted twice.
const VARIANT_GIRTH := {"": 1.0, "slight": 0.90, "heavy": 1.12, "woman": 1.0}


static func girth_for(build: float) -> float:
	return lerpf(0.88, 1.14, clampf(build, 0.0, 1.0))


## How far the arms are turned out from the clips' own pose, by what the body wears: the Idle
## hangs the wrists 5 cm outside the default body's hip, which a tunic or a shirt leaves room
## for and padding does not. Degrees at the shoulder, about half a metre above the hand, so each
## degree is nearly a centimetre there: the gambeson's 3 cm on the body and 3 cm on the sleeve
## want 7, the harness's coat, plate and tassets 8, and the heavy body's hips 3 more.
const ARM_ROOM := {"gambeson": 7.0, "plate_torso": 8.0, "brigandine": 7.0, "coat": 3.0}
const ARM_ROOM_HEAVY := 3.0
## A grown head worn this much larger than the forge made it (ArmRoom.head_scale): at 1.0 every head
## in a lineup read small on its shoulders, clothed ones most of all.
const HEAD_SCALE := 1.06


## Metres each shoulder joint stands out along the collarbone for the record's shoulder width:
## SHOULDER_SPAN at the ends of its range (0.86 .. 1.14), nothing at 1.
const SHOULDER_SPAN := 0.016


static func shoulders_out_for(a: CharacterAppearance) -> float:
	return clampf((a.shoulder_width - 1.0) / 0.14, -1.0, 1.0) * SHOULDER_SPAN


static func arm_room_for(torso: String, variant: String) -> float:
	return float(ARM_ROOM.get(torso, 0.0)) + (ARM_ROOM_HEAVY if variant == "heavy" else 0.0)


## How much of the arms' swing a cloak to the knee takes back while the body walks: the share
## of the clip's arm pose ArmRoom returns to the Idle's hang. The cloth lying on an arm goes with
## nearly all of its swing, and the whole Walk swing still brought the hand out through the front
## of the cloak at every step. A shoulder cape or a plaid leaves the arms free below it; a shawl
## lies over the tops of the arms to the elbow, and running they came up through its sides.
const ARM_HOLD := {"cloak": 0.7, "hooded_cloak": 0.7, "ragged_cloak": 0.7, "torn_cloak": 0.7, "shawl": 0.6}
## Running, nearly all of it: the Run pumps the arms 38 degrees with the elbows bent 80, and at
## the walk's hold the elbow behind still came out through the back of the cloak.
const ARM_HOLD_RUNNING := 0.95
## The hold comes and goes over this long, so a blow started mid-stride gets its whole arm at once.
const ARM_HOLD_BLEND_S := 0.1


static func arm_hold_for(back: String) -> float:
	return float(ARM_HOLD.get(back, 0.0))


## The hold for the cloak worn while `clip` plays on its own: the gaits', none for anything else
## (the Idle is the hang itself). What character_review shows when it holds a clip.
func arm_hold_in(clip: String) -> float:
	if _cloak_hold <= 0.0 or clip not in MOVE_CLIPS or clip == "Sneak_Walk":
		return 0.0
	return maxf(_cloak_hold, ARM_HOLD_RUNNING) if clip in ["Run", "Sprint"] else _cloak_hold


## While walking or running in a long cloak, and never through a one-shot, a held pose, a stance
## or a sneak, whose arms are posed for what they do.
func _arm_hold_now() -> float:
	if _cloak_hold <= 0.0 or not _one_shot.is_empty() or not _holding.is_empty() or _stance != "":
		return 0.0
	# from the walk's hold at a brisk walk to the run's at the Run's own pace
	var walk := float(_clip_speed.get("Walk", 1.8)) * BRISK_WALK
	var run := maxf(float(_clip_speed.get("Run", 5.0)), walk + 0.1)
	var running := smoothstep(walk, run, _loco_now.length())
	return lerpf(_cloak_hold, maxf(_cloak_hold, ARM_HOLD_RUNNING), running) * _move_w * (1.0 - _sneak_w)


func _apply_proportions() -> void:
	var s: float = appearance.height / (_child_height if _child_mod != null else 1.78)
	var wide: float = girth_for(appearance.build) / float(VARIANT_GIRTH.get(body_variant_worn, 1.0)) * breadth
	if _rig_root != null:
		_rig_root.scale = Vector3(s * wide, s, s * wide)


# ---------------------------------------------------------------------------------------
# animation
# ---------------------------------------------------------------------------------------

func _build_animation_tree() -> void:
	var sm := AnimationNodeStateMachine.new()
	# ROOT, not GROUPED: a grouped machine may only be driven through its parent's playback,
	# and this one is the tree root, so every travel() on it pushed an error.  A walking
	# actor did that once a frame.
	sm.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_ROOT
	sm.add_node(LOCOMOTION_STATE, _build_locomotion_tree(), Vector2(0, 0))
	var boot := _transition(0.0, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
	boot.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", LOCOMOTION_STATE, boot)
	var x := 260.0
	var y := -420.0
	_has_swim = SWIM_CLIPS.all(func(c: String) -> bool: return has_clip(c))
	if _has_swim:
		sm.add_node(SWIM_STATE, _build_swim_tree(), Vector2(0, 200))
		sm.add_transition(LOCOMOTION_STATE, SWIM_STATE,
				_transition(SWIM_IN_S, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE))
		sm.add_transition(SWIM_STATE, LOCOMOTION_STATE,
				_transition(SWIM_IN_S, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE))
	for name in anim_player.get_animation_list():
		if _is_locomotion_clip(name) or SWIM_CLIPS.has(name):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = name
		sm.add_node(name, node, Vector2(x, y))
		# travel() needs a path of real transitions or it teleports without a cross-fade. The edge
		# into a one-shot plays it from its start (_into_one_shot): without that, the clip went on
		# from wherever it was last left, which for anything played before was its last frame. A
		# heavy blow swung once, and every heavy after it stood in its follow-through with the
		# blade out in front for the whole of the swing; a roll rolled once each way, and after
		# that the body slid along in the roll's last pose, a dash (playtest 2026-09-27, 4 and 6).
		sm.add_transition(LOCOMOTION_STATE, name, _into_one_shot(name))
		sm.add_transition(name, LOCOMOTION_STATE,
				_transition(ONE_SHOT_BLEND_OUT, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE))
		if _has_swim:
			# a flinch or a flask in the water goes back to the swim, not through a walk
			sm.add_transition(SWIM_STATE, name, _into_one_shot(name))
			sm.add_transition(name, SWIM_STATE,
					_transition(ONE_SHOT_BLEND_OUT, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE))
		y += 46.0
		if y > 420.0:
			y = -420.0
			x += 200.0
	_add_handovers(sm)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = sm
	# Stepped by _process rather than by itself, so a one-shot can be played faster, slower or not
	# at all (speed_scale) -- an AnimationTree has no speed of its own to set.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# the node has to be in the tree before a NodePath to the player can resolve
	add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	anim_tree = tree
	_state_machine = tree.get("parameters/playback")
	_update_locomotion(0.0)


## The edges a fight hands over along, each played from the new clip's start. They switch at once:
## the blend across ONE_SHOT_HANDOVER is the model's own (_blend_handover).
func _add_handovers(sm: AnimationNodeStateMachine) -> void:
	_handovers.clear()
	var names := anim_player.get_animation_list()
	for from in names:
		if _is_locomotion_clip(from) or not _starts_with_any(from, HANDS_OVER):
			continue
		for to in names:
			if to == from or _is_locomotion_clip(to) or not _starts_with_any(to, TAKES_OVER):
				continue
			var t := _transition(0.0, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
			t.reset = true
			sm.add_transition(from, to, t)
			_handovers["%s>%s" % [from, to]] = true


static func _starts_with_any(clip: String, prefixes: Array) -> bool:
	for p in prefixes:
		if clip.begins_with(str(p)):
			return true
	return false


## The edge from the legs (or the swim) into a one-shot: cross-faded in, and played from the clip's
## start. The edges back out keep `reset` off, so the gait goes on in step from where it was. (Before
## this the clip also stood still for the first tenth of a second of its first play, the fade's,
## and the picture's blow landed that much after the timeline's.) A swing's edge switches at once and
## the model blends the legs' pose into the swing's itself, as a hand-over does (_blend_handover):
## the mixer's cross-fade from the idle carried a spear's butt 6-8 cm into the chest for two frames.
func _into_one_shot(clip: String) -> AnimationNodeStateMachineTransition:
	var fade := 0.0 if _starts_with_any(clip, HANDS_OVER) else ONE_SHOT_BLEND_IN
	var t := _transition(fade, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
	t.reset = true
	return t


## One transition resource per edge: they are cheap, and `travel` refuses to cross-fade
## between two states that are not connected.
func _transition(xfade: float, mode: int) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = mode
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	t.reset = false
	return t


## The locomotion graph (the Locomotion state):
##
##     Walk, Walk (fast), Run, Sprint -> gait (1D, by ground speed) -+
##                                             Sneak_Walk -> fwd ----+-> fb <- Walk_Back
##     Strafe_L, Strafe_R -> lr ------------------------------------> dir -> cycle -> move -> out
##     Idle, Sneak_Idle -> idle ------------------------------------------------------^
##
## Every moving clip is laid on the same one-second timeline, one stride cycle stretched to fit
## it, and every blend in the moving branch keeps its silent inputs running, so the gaits are
## always at the same phase: the forge puts the left foot down at 0 and the right at 0.5 in each
## (CONTRACTS §3). `cycle` then sets how many strides a second that shared timeline runs at:
## ground speed over the stride of whatever is being blended, which is what keeps a planted foot
## planted. The first graph was one 2D blend space fed velocity/6.5 with Sneak_Walk half way up
## its forward axis: the default gait was posed three-quarters of the way into a crouch, the
## sprint played Walk, and the feet slid at 76-79% of the ground speed.
func _build_locomotion_tree() -> AnimationNodeBlendTree:
	_read_gait_speeds()
	var bt := AnimationNodeBlendTree.new()
	var gait := AnimationNodeBlendSpace1D.new()
	gait.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	gait.min_space = 0.0
	gait.max_space = 20.0
	gait.sync = true
	for point in _gait_points:
		gait.add_blend_point(_cycle_node(str(point[0])), float(point[1]), -1, str(point[2]))
	bt.add_node("gait", gait, Vector2(0, 0))
	bt.add_node("sneak_walk", _cycle_node(_or_idle("Sneak_Walk")), Vector2(0, 160))
	bt.add_node("back", _cycle_node(_or_idle("Walk_Back")), Vector2(200, 260))
	bt.add_node("strafe_l", _cycle_node(_or_idle("Strafe_L")), Vector2(0, 360))
	bt.add_node("strafe_r", _cycle_node(_or_idle("Strafe_R")), Vector2(0, 460))
	for blend_name in ["fwd", "fb", "lr", "dir"]:
		var b := AnimationNodeBlend2.new()
		b.sync = true
		bt.add_node(blend_name, b, Vector2(400, 0))
	bt.connect_node("fwd", 0, "gait")
	bt.connect_node("fwd", 1, "sneak_walk")
	bt.connect_node("fb", 0, "fwd")
	bt.connect_node("fb", 1, "back")
	bt.connect_node("lr", 0, "strafe_l")
	bt.connect_node("lr", 1, "strafe_r")
	bt.connect_node("dir", 0, "fb")
	bt.connect_node("dir", 1, "lr")
	bt.add_node("cycle", AnimationNodeTimeScale.new(), Vector2(600, 0))
	bt.connect_node("cycle", 0, "dir")
	var idle := AnimationNodeAnimation.new()
	idle.animation = _or_idle("Idle")
	var sneak_idle := AnimationNodeAnimation.new()
	sneak_idle.animation = _or_idle("Sneak_Idle")
	bt.add_node("idle_stand", idle, Vector2(400, -200))
	bt.add_node("idle_sneak", sneak_idle, Vector2(400, -100))
	bt.add_node("idle", AnimationNodeBlend2.new(), Vector2(600, -150))
	bt.connect_node("idle", 0, "idle_stand")
	bt.connect_node("idle", 1, "idle_sneak")
	bt.add_node("move", AnimationNodeBlend2.new(), Vector2(800, 0))
	bt.connect_node("move", 0, "idle")
	bt.connect_node("move", 1, "cycle")
	bt.connect_node("output", 0, _add_stance_layer(bt, _add_turns(bt, "move")))
	return bt


## The turns on the spot over `below`: the quarter turns and the about-faces, left and right, on
## their own timeline, played at the rate the body turns (`turn_rate`) and started from the top at
## each new turn (`turn_seek`). Returns the node to take the output from.
func _add_turns(bt: AnimationNodeBlendTree, below: String) -> String:
	_has_turns = false
	for clip in TURN_CLIPS.values():
		if not has_clip(clip) or not _clip_data.get(clip, {}).has("turn"):
			return below
	bt.add_node("turn_left", _cycle_node(TURN_CLIPS["left"]), Vector2(400, 560))
	bt.add_node("turn_right", _cycle_node(TURN_CLIPS["right"]), Vector2(400, 640))
	bt.add_node("pivot_left", _cycle_node(TURN_CLIPS["pivot_left"]), Vector2(400, 720))
	bt.add_node("pivot_right", _cycle_node(TURN_CLIPS["pivot_right"]), Vector2(400, 800))
	for blend_name in ["turn_way", "pivot_way", "turn_kind", "turned"]:
		bt.add_node(blend_name, AnimationNodeBlend2.new(), Vector2(600, 600))
	bt.connect_node("turn_way", 0, "turn_left")
	bt.connect_node("turn_way", 1, "turn_right")
	bt.connect_node("pivot_way", 0, "pivot_left")
	bt.connect_node("pivot_way", 1, "pivot_right")
	bt.connect_node("turn_kind", 0, "turn_way")
	bt.connect_node("turn_kind", 1, "pivot_way")
	bt.add_node("turn_seek", AnimationNodeTimeSeek.new(), Vector2(800, 600))
	bt.connect_node("turn_seek", 0, "turn_kind")
	bt.add_node("turn_rate", AnimationNodeTimeScale.new(), Vector2(900, 600))
	bt.connect_node("turn_rate", 0, "turn_seek")
	bt.connect_node("turned", 0, below)
	bt.connect_node("turned", 1, "turn_rate")
	_has_turns = true
	return "turned"


## The upper body of a held stance (a raised guard) over `below`, filtered to UPPER_BODY so the
## hips and legs go on walking under it. Returns the node to take the output from.
func _add_stance_layer(bt: AnimationNodeBlendTree, below: String) -> String:
	_has_stance_layer = false
	if anim_player == null or not anim_player.has_animation(STANCE_CLIPS[0]):
		return below
	var pose := AnimationNodeAnimation.new()
	pose.animation = STANCE_CLIPS[0]
	_stance_node = pose
	bt.add_node("stance_pose", pose, Vector2(800, 200))
	# a stance played again starts from its first frame, at the pace it is given
	bt.add_node("stance_seek", AnimationNodeTimeSeek.new(), Vector2(900, 200))
	bt.connect_node("stance_seek", 0, "stance_pose")
	bt.add_node("stance_rate", AnimationNodeTimeScale.new(), Vector2(950, 200))
	bt.connect_node("stance_rate", 0, "stance_seek")
	var layer := AnimationNodeBlend2.new()
	layer.filter_enabled = true
	var clip := anim_player.get_animation(STANCE_CLIPS[0])
	for i in clip.get_track_count():
		var path := clip.track_get_path(i)
		if UPPER_BODY.has(str(path.get_concatenated_subnames())):
			layer.set_filter_path(path, true)
	bt.add_node("stance", layer, Vector2(1000, 0))
	bt.connect_node("stance", 0, below)
	bt.connect_node("stance", 1, "stance_rate")
	_has_stance_layer = true
	return "stance"


## One stride cycle of a clip, stretched onto the shared one-second timeline.
## Treading water blended into the stroke (`swim/blend_amount`), the stroke played at the pace
## the body swims (`stroke/scale`).
func _build_swim_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var tread := AnimationNodeAnimation.new()
	tread.animation = "Swim_Idle"
	bt.add_node("tread", tread, Vector2(0, 0))
	var stroke := AnimationNodeAnimation.new()
	stroke.animation = "Swim_Forward"
	bt.add_node("stroke_clip", stroke, Vector2(0, 160))
	var rate := AnimationNodeTimeScale.new()
	bt.add_node("stroke", rate, Vector2(200, 160))
	bt.connect_node("stroke", 0, "stroke_clip")
	var mix := AnimationNodeBlend2.new()
	bt.add_node("swim", mix, Vector2(400, 60))
	bt.connect_node("swim", 0, "tread")
	bt.connect_node("swim", 1, "stroke")
	bt.connect_node("output", 0, "swim")
	return bt


## In deep water or out of it. In it, the body rests in the swim (treading, or the stroke at its
## pace) rather than in a gait, and the feet are nobody's to plant.
func set_swimming(on: bool) -> void:
	if on == _swimming or not _has_swim:
		_swimming = on and _has_swim
		return
	_swimming = on
	_stance = ""
	if _planter != null and _planter.is_planted():
		_planter.release()
	if _state_machine != null and _one_shot.is_empty() and _holding.is_empty():
		_state_machine.travel(_rest_state())


func is_swimming() -> bool:
	return _swimming


## How much of the thighs' swing a skirt takes now (SkirtDrive.amount): none while swimming, prone
## with the legs trailing, nor in the saddle, the thighs round the barrel (a Ride clip, getting up or
## down, or the RideSeat laying the legs astride); all of it otherwise.
func skirt_amount_now() -> float:
	if _swimming:
		return 0.0
	if _one_shot.begins_with("Ride") or _one_shot in ["Mount_Horse", "Dismount_Horse"]:
		return 0.0
	if _state_machine != null and str(_state_machine.get_current_node()).begins_with("Ride"):
		return 0.0
	var seat := skeleton.get_node_or_null("RideSeat") if skeleton != null else null
	if seat != null and float(seat.get("amount")) > 0.01:
		return 0.0
	return 1.0


## Where the body goes back to when a one-shot ends: the swim in deep water, else Locomotion.
func _rest_state() -> String:
	return SWIM_STATE if _swimming else LOCOMOTION_STATE


func _update_swim(delta: float) -> void:
	var pace := _locomotion.length()
	_swim_w = move_toward(_swim_w, clampf(pace / SWIM_STROKE_FROM, 0.0, 1.0), delta / SWIM_BLEND_S)
	var speed := maxf(float((_clip_data.get("Swim_Forward", {}) as Dictionary).get("speed", 1.6)), 0.1)
	anim_tree.set("parameters/%s/swim/blend_amount" % SWIM_STATE, _swim_w)
	anim_tree.set("parameters/%s/stroke/scale" % SWIM_STATE, clampf(pace / speed, 0.6, 1.8))
	if _one_shot.is_empty() and _holding.is_empty() and str(_state_machine.get_current_node()) == LOCOMOTION_STATE:
		_state_machine.travel(SWIM_STATE)


func _cycle_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	n.use_custom_timeline = true
	n.timeline_length = 1.0
	n.stretch_time_scale = true
	n.loop_mode = Animation.LOOP_LINEAR
	return n


func _or_idle(clip: String) -> String:
	return clip if has_clip(clip) else "Idle"


## The ground speed each clip was authored at (the sidecar's `speed`, CONTRACTS §3) and the
## points of the gait blend: the walk twice (as authored, and a third faster before it breaks
## into a run, the way a person walks briskly before they jog), the run, and the sprint.
func _read_gait_speeds() -> void:
	_gait_points.clear()
	_clip_speed.clear()
	_clip_cycle.clear()
	for clip in MOVE_CLIPS:
		if has_clip(clip):
			_clip_speed[clip] = maxf(float((_clip_data.get(clip, {}) as Dictionary).get("speed", 1.0)), 0.1)
			_clip_cycle[clip] = maxf(clip_length(clip), 0.05)
	for clip in ["Walk", "Trot", "Run", "Sprint"]:
		if not _clip_speed.has(clip):
			continue
		_gait_points.append([clip, float(_clip_speed[clip]), clip.to_lower()])
		if clip == "Walk":
			_gait_points.append([clip, float(_clip_speed[clip]) * BRISK_WALK, "walk_brisk"])
	_gait_points.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))


## Ground speed (m/s) a gait clip plants its feet at, or 0 when the rig has no such clip.
func gait_speed(clip: String) -> float:
	return float(_clip_speed.get(clip, 0.0))


## Metres the body covers in one stride cycle of a clip played as authored.
func _stride(clip: String) -> float:
	return float(_clip_speed.get(clip, 1.0)) * float(_clip_cycle.get(clip, 1.0))


func _is_locomotion_clip(name: String) -> bool:
	return name in ["Idle", "Sneak_Idle"] or name in MOVE_CLIPS or name in TURN_CLIPS.values()


## Drive locomotion with the body's ground velocity in its own frame, in metres per second: x to
## its right, y ahead (behind is negative). The model picks the gait, the blend and the rate that
## keep a planted foot planted; `sneaking` crouches, cross-faded over a quarter of a second.
func set_locomotion(v: Vector2, sneaking: bool = false) -> void:
	_locomotion = v
	_sneaking = sneaking
	if anim_tree == null:
		return
	if _one_shot.is_empty() and _holding.is_empty() and _state_machine != null and _state_machine.get_current_node() != _rest_state():
		_state_machine.travel(_rest_state())


## What the Locomotion graph is set to for a ground velocity `v` (m/s, the body's frame) and a
## crouch weight 0..1, keyed by parameter path under the state. Pure, so tests can read it.
## `ground_speed` is the speed the stride has to match, when it is not `v`'s: the blend is
## driven by a smoothed velocity so that it does not shake, but a foot on the ground has to keep
## pace with the ground as it is this tick, not as it was a smoothing constant ago.
func locomotion_params(v: Vector2, sneak_w: float, ground_speed := -1.0, way := -1) -> Dictionary:
	var speed := v.length()
	if way < 0:
		way = way_for(v, Way.AHEAD if speed < 0.001 else -1)
	var w := way_blends(way)
	var gait_value := speed
	if not _gait_points.is_empty():
		gait_value = clampf(speed, float(_gait_points[0][1]), float(_gait_points[-1][1]))
	var pace := speed if ground_speed < 0.0 else ground_speed
	return {
		"gait/blend_position": gait_value,
		"fwd/blend_amount": sneak_w,
		"fb/blend_amount": w["fb"],
		"lr/blend_amount": w["lr"],
		"dir/blend_amount": w["dir"],
		"cycle/scale": _stride_rate(w, gait_value, sneak_w, pace),
		"idle/blend_amount": sneak_w,
		"move/blend_amount": smoothstep(MOVING_FROM, MOVING_FULL, speed),
	}


## The way (Way) the legs go for a ground velocity `v` (the body's frame, x to its right): the
## nearest of the four, where ahead and back each take the ways within SIDE_FROM of them. From
## `current` (a Way, or -1 for none) the body keeps going its way until SECTOR_HOLD past its edge.
static func way_for(v: Vector2, current := -1) -> int:
	if v.length() < 0.001:
		return Way.AHEAD if current < 0 else current
	var angle := atan2(v.x, v.y)          # 0 ahead, + to the right
	var off := absf(angle)
	var hold := SECTOR_HOLD if current >= 0 else 0.0
	match current:
		Way.AHEAD:
			if off <= SIDE_FROM + hold:
				return Way.AHEAD
		Way.BACK:
			if off >= PI - SIDE_FROM - hold:
				return Way.BACK
		Way.RIGHT:
			if angle > 0.0 and off > SIDE_FROM - hold and off < PI - SIDE_FROM + hold:
				return Way.RIGHT
		Way.LEFT:
			if angle < 0.0 and off > SIDE_FROM - hold and off < PI - SIDE_FROM + hold:
				return Way.LEFT
	if off <= SIDE_FROM:
		return Way.AHEAD
	if off >= PI - SIDE_FROM:
		return Way.BACK
	return Way.RIGHT if angle > 0.0 else Way.LEFT


## How far (rad, + to the right) the hips turn from the way the legs go (`way`) toward `v`.
static func hips_turn_for(v: Vector2, way: int) -> float:
	if v.length() < 0.001:
		return 0.0
	return wrapf(atan2(v.x, v.y) - float(WAY_ANGLE[way]), -PI, PI)


## The graph's blends for a way: "fb" back against ahead, "lr" right against left, "dir" the
## side-steps against ahead or back.
static func way_blends(way: int) -> Dictionary:
	match way:
		Way.BACK:
			return {"fb": 1.0, "lr": 1.0, "dir": 0.0}
		Way.RIGHT:
			return {"fb": 0.0, "lr": 1.0, "dir": 1.0}
		Way.LEFT:
			return {"fb": 0.0, "lr": 0.0, "dir": 1.0}
	return {"fb": 0.0, "lr": 1.0, "dir": 0.0}


## Stride cycles a second that keep a planted foot planted at `pace` m/s, for the blends `w`
## (way_blends, or eased between two of them) at gait position `gait_value` and crouch `sneak_w`.
## The legs go whichever way the hips are turned to, so the whole pace is along the stride.
func _stride_rate(w: Dictionary, gait_value: float, sneak_w: float, pace: float, braking := false,
		flying := false) -> float:
	var gait := _gait_blend(gait_value)
	var fwd_stride := lerpf(float(gait[0]), _stride("Sneak_Walk"), sneak_w)
	var fwd_rate := lerpf(float(gait[1]), 1.0 / float(_clip_cycle.get("Sneak_Walk", 1.0)), sneak_w)
	var fb := float(w["fb"])
	var lr := float(w["lr"])
	var side := float(w["dir"])
	var along := lerpf(fwd_stride, _stride("Walk_Back"), fb)
	var along_rate := lerpf(fwd_rate, 1.0 / float(_clip_cycle.get("Walk_Back", 1.0)), fb)
	var strafe := lerpf(_stride("Strafe_L"), _stride("Strafe_R"), lr)
	var strafe_rate := lerpf(1.0 / float(_clip_cycle.get("Strafe_L", 1.0)), 1.0 / float(_clip_cycle.get("Strafe_R", 1.0)), lr)
	var stride := lerpf(along, strafe, side)
	var natural := lerpf(along_rate, strafe_rate, side)
	var rate := pace / maxf(stride, 0.01)
	var floor_rate := 0.0 if braking else natural * RATE_MIN * smoothstep(MOVING_FROM, MOVING_FULL, pace)
	if braking and flying:
		floor_rate = natural
	return clampf(rate, floor_rate, natural * RATE_MAX)


## [stride m/cycle, cycles/s as authored] of the gait blend at a blend position, interpolated
## between the two points either side of it exactly as the 1D blend space weights them.
func _gait_blend(value: float) -> Array:
	if _gait_points.is_empty():
		return [1.0, 1.0]
	var lo: Array = _gait_points[0]
	var hi: Array = _gait_points[0]
	for p in _gait_points:
		if float(p[1]) <= value:
			lo = p
		if float(p[1]) >= value:
			hi = p
			break
	var w := 0.0
	if float(hi[1]) > float(lo[1]):
		w = (value - float(lo[1])) / (float(hi[1]) - float(lo[1]))
	var s_lo := _stride(str(lo[0]))
	var s_hi := _stride(str(hi[0]))
	var r_lo := 1.0 / float(_clip_cycle.get(str(lo[0]), 1.0))
	var r_hi := 1.0 / float(_clip_cycle.get(str(hi[0]), 1.0))
	return [lerpf(s_lo, s_hi, w), lerpf(r_lo, r_hi, w)]


func _update_locomotion(delta: float) -> void:
	if anim_tree == null:
		return
	if _swimming:
		_hips_turn = 0.0
		_update_swim(delta)
		return
	_loco_now = _loco_now.lerp(_locomotion, 1.0 - exp(-delta / SPEED_SMOOTH_S))
	_sneak_w = move_toward(_sneak_w, 1.0 if _sneaking else 0.0, delta / SNEAK_BLEND_S)
	# the way the legs go, held until the body is well past its edge, the blends eased across to it
	# and the hips turned the rest of the way
	if _locomotion.length() > MOVING_FROM:
		_way = way_for(_locomotion, _way)
	var want_w := way_blends(_way)
	# a branch that is not showing takes its new way at once: eased, a turn from ahead to a
	# side-step went through a side-step half left and half right
	if float(_way_w["dir"]) < 0.05:
		_way_w["lr"] = want_w["lr"]
	if float(_way_w["dir"]) > 0.95:
		_way_w["fb"] = want_w["fb"]
	for key in _way_w:
		_way_w[key] = move_toward(float(_way_w[key]), float(want_w[key]), delta / SECTOR_BLEND_S)
	var want_turn := hips_turn_for(_locomotion, _way) if _locomotion.length() > MOVING_FROM else 0.0
	_hips_turn = lerp_angle(_hips_turn, want_turn, 1.0 - exp(-delta / HIPS_TURN_S))
	# The gaits are read at the rig's own size: a body drawn half again as tall walks where a person
	# would trot, and its legs go round at a giant's cadence (a 2.8 m bell-bearer's legs went round at
	# a person's, and skated).
	var tall := _rig_root.scale.y if _rig_root != null and _rig_root.scale.y > 0.1 else 1.0
	var p := locomotion_params(_loco_now / tall, _sneak_w, _locomotion.length() / tall, _way)
	p["fb/blend_amount"] = _way_w["fb"]
	p["lr/blend_amount"] = _way_w["lr"]
	p["dir/blend_amount"] = _way_w["dir"]
	_update_braking(delta, p)
	var braking := _held_gait >= 0.0
	_in_flight = _flies(delta, braking)
	p["cycle/scale"] = _stride_rate(_way_w, float(p["gait/blend_position"]), _sneak_w, _locomotion.length() / tall,
			braking, _in_flight)
	var moving := smoothstep(MOVING_FROM, MOVING_FULL, _locomotion.length())
	if _plants_feet():
		# The gait keeps its pose until the body stands and its feet are held; only then does the
		# body settle into the idle over them while the feet step into it (_plant_feet). A
		# one-shot the body stands through goes back to the idle, not to a frozen stride.
		if _locomotion.length() >= FootPlanter.STANDS_BELOW:
			moving = 1.0
		elif _planter.is_planted() or not _one_shot.is_empty() or not _holding.is_empty():
			moving = 0.0
		else:
			moving = _move_w
	_move_w = move_toward(_move_w, moving, delta / MOVE_BLEND_S)
	p["move/blend_amount"] = _move_w
	if _has_stance_layer:
		_stance_w = move_toward(_stance_w, 1.0 if _stance != "" else 0.0, delta / STANCE_BLEND_S)
		p["stance/blend_amount"] = _stance_w
		p["stance_rate/scale"] = _stance_rate()
	if _has_turns:
		_update_turn(delta, p)
	for key in p:
		anim_tree.set("parameters/%s/%s" % [LOCOMOTION_STATE, key], p[key])


## Braking with both feet off the ground, as the last frame left them (see BRAKING_FROM): the
## stride goes on at the flight's own pace, standing or not, until a foot is down, or the body has
## stood in the air for FLIGHT_MOST_S.
func _flies(delta: float, braking: bool) -> bool:
	if not braking or not _plants_feet() or _planter.is_planted() or not _one_shot.is_empty() \
			or not _holding.is_empty() or _planter.feet_down() > 0:
		_flight_s = 0.0
		_flight_pace = -1.0
		return false
	if _flight_pace < 0.0:
		_flight_pace = _locomotion.length()
	if _flight_pace < FLIGHT_FROM:
		return false
	if _locomotion.length() < FootPlanter.STANDS_BELOW:
		_flight_s += delta
	return _flight_s < FLIGHT_MOST_S


## Braking, the gait position the body was at when it began to brake is held (see BRAKING_FROM),
## and let go when the body speeds up again or has settled into its stance.
func _update_braking(delta: float, p: Dictionary) -> void:
	var speed := _locomotion.length()
	if delta > 0.0:
		_accel = lerpf(_accel, (speed - _speed_last) / delta, 1.0 - exp(-delta / ACCEL_SMOOTH_S))
	_speed_last = speed
	var want := float(p["gait/blend_position"])
	if _held_gait < 0.0:
		if _accel < BRAKING_FROM and speed > MOVING_FROM:
			_held_gait = _gait_shown if _gait_shown >= 0.0 else want
	elif _accel > 1.0 or (_accel > -1.0 and speed > MOVING_FULL) or (speed < FootPlanter.STANDS_BELOW and _move_w < 0.01):
		# speeding up, going on at a steady pace, or settled: the gait follows the body again,
		# eased there from where it was held
		_held_gait = -1.0
	if _held_gait >= 0.0:
		_gait_shown = _held_gait
	elif _gait_shown < 0.0:
		_gait_shown = want
	else:
		_gait_shown = lerpf(_gait_shown, want, 1.0 - exp(-delta / SPEED_SMOOTH_S))
	p["gait/blend_position"] = _gait_shown


## A body turning on the spot plays the turn clips, at the rate it turns: a turn starts when a
## standing body turns faster than TURN_FROM, goes the way it turns, is an about-face if it began
## faster than PIVOT_FROM, and ends when the body has turned slower than TURN_UNTIL for a moment,
## moves off or plays a one-shot. Then the feet are planted where the turn left them and step into
## the stance, as after a stop.
func _update_turn(delta: float, p: Dictionary) -> void:
	var yaw := skeleton.global_transform.basis.get_euler().y if skeleton != null else 0.0
	var step := 0.0 if is_nan(_yaw_last) else wrapf(yaw - _yaw_last, -PI, PI)
	_yaw_last = yaw
	if absf(step) > SNAP_TURN or delta <= 0.0:
		step = 0.0
	var raw := step / delta if delta > 0.0 else 0.0
	if delta > 0.0:
		_yaw_rate = lerpf(_yaw_rate, raw, 1.0 - exp(-delta / TURN_SMOOTH_S))
	var free := _one_shot.is_empty() and _holding.is_empty() and _locomotion.length() < TURN_BELOW
	var rate := absf(_yaw_rate)
	# how fast the turn is going, for its kind: the eased rate lags the first frames of a flick
	var quick := maxf(rate, absf(raw))
	# the turn made while it was still too slow to call a turn, which the planted feet stood through
	if free and (not _turn.is_empty() or absf(raw) > TURN_UNTIL * 0.25):
		_gathered += step
	elif _turn.is_empty():
		_gathered = 0.0
	if not free:
		_turn = ""
	elif _turn.is_empty():
		if rate > TURN_FROM or absf(raw) > PIVOT_FROM:
			_start_turn(p, raw if absf(raw) > rate else _yaw_rate, quick > PIVOT_FROM)
	else:
		_turn_age += delta
		_turn_quiet = _turn_quiet + delta if rate < TURN_UNTIL else 0.0
		var reversed := (_yaw_rate > TURN_FROM and _turn.ends_with("right")) or (_yaw_rate < -TURN_FROM and _turn.ends_with("left"))
		if _turn_quiet > 0.08 or reversed:
			_turn = ""
		elif _turn_age < 0.1 and not _turn.begins_with("pivot_") and quick > PIVOT_FROM:
			# a flick that was still gathering speed: an about-face after all
			_start_turn(p, _yaw_rate, true)
	var target := 1.0 if not _turn.is_empty() else 0.0
	if _turn.is_empty() and _plants_feet() and not _planter.is_planted() and free and _turn_w > 0.0:
		target = _turn_w     # hold the turn's pose until the feet are held under it
	_turn_w = move_toward(_turn_w, target, delta / (TURN_IN_S if target > _turn_w else TURN_BLEND_S))
	p["turned/blend_amount"] = _turn_w
	var clip: String = TURN_CLIPS.get(_turn, "")
	if clip.is_empty():
		p["turn_rate/scale"] = 0.0
		return
	# the clip goes round exactly as far as the body did this frame (its own frame's turn, not the
	# eased rate), so a foot on the ground stays where it is; turned back the other way, it waits
	var per_cycle := deg_to_rad(absf(float(_clip_data[clip].get("turn", 90.0))))
	var natural := 1.0 / maxf(clip_length(clip), 0.05)
	var along := maxf(raw * (1.0 if _turn.ends_with("left") else -1.0), 0.0)
	p["turn_rate/scale"] = minf(along / per_cycle, natural * TURN_RATE_MAX)


## Starts a turn on the spot the way `rate` goes (+ to the left). It picks up as far round its clip
## as the body has already come since it last stood square, so its feet are where the planter holds
## them, and it takes them from the planter once it is all in (_plant_feet).
func _start_turn(p: Dictionary, rate: float, pivot: bool) -> void:
	_turn = ("pivot_" if pivot else "") + ("left" if rate > 0.0 else "right")
	_turn_quiet = 0.0
	_turn_age = 0.0
	var clip: String = TURN_CLIPS[_turn]
	var per_cycle := deg_to_rad(absf(float(_clip_data.get(clip, {}).get("turn", 90.0))))
	var along := absf(_gathered) if signf(_gathered) == signf(rate) else 0.0
	p["turn_seek/seek_request"] = clampf(along / per_cycle, 0.0, 0.04)
	p["turn_kind/blend_amount"] = 1.0 if pivot else 0.0
	p["turn_way/blend_amount"] = 0.0 if rate > 0.0 else 1.0
	p["pivot_way/blend_amount"] = 0.0 if rate > 0.0 else 1.0


## A body put down facing a new way (a teleport) has not turned on the spot, and its feet are
## planted where it lands.
func reset_heading() -> void:
	_yaw_last = NAN
	_yaw_rate = 0.0
	_turn = ""
	_turn_w = 0.0
	if _planter != null:
		_planter.release()


## The turn being played ("Turn_L90" and so on), or "" when the body is not turning on the spot.
func current_turn() -> String:
	return str(TURN_CLIPS.get(_turn, ""))


## The way the legs are going (Way) and how far (rad, + to the right) the hips are turned from it.
func current_way() -> int:
	return _way


func hips_turn() -> float:
	return _hips_turn


## Play a one-shot clip by name. Returns false if the rig has no such clip.
func play_intent(clip_name: String, blend: float = DEFAULT_BLEND) -> bool:
	if anim_tree == null or _state_machine == null:
		return false
	if not has_clip(clip_name):
		push_warning("HumanoidModel: no clip '%s'" % clip_name)
		return false
	_holding = ""
	if _has_stance_layer and STANCE_CLIPS.has(clip_name):
		# held over the legs in the Locomotion graph, not played as a state of its own
		var was := _stance
		_stance = clip_name
		_one_shot = ""
		if _state_machine.get_current_node() != LOCOMOTION_STATE:
			_state_machine.travel(LOCOMOTION_STATE)
		# from its first frame, every time (test_clips_play_again): a loose then a draw again, or a
		# draw let down and drawn again. One stance into another hands the pose over as a swing
		# into the next does (_begin_handover), the legs going on as they were.
		if was == clip_name and not STANCE_TIMED.has(clip_name):
			return true              # a held loop asked for again goes on
		if was != "" and _stance_w > 0.0 and was != clip_name:
			_begin_handover(ONE_SHOT_HANDOVER, LEGS)
			# the aim is laid on after the blend, every frame: blend from the pose without it
			for b in _pre_aim:
				if int(b) < _handover_from.size() and _handover_from[int(b)] != null:
					(_handover_from[int(b)] as Array)[0] = _pre_aim[b]
		if _stance_node != null and _stance_node.animation != StringName(clip_name):
			_stance_node.animation = clip_name
		anim_tree.set("parameters/%s/stance_seek/seek_request" % LOCOMOTION_STATE, 0.0)
		_stance_time = 0.0
		return true
	_stance = ""
	if _is_locomotion_clip(clip_name) or SWIM_CLIPS.has(clip_name):
		_one_shot = ""
		_state_machine.travel(_rest_state())
		return true
	# travel() cross-fades along the edge built for it: from locomotion, and from a swing to the
	# next swing, a roll or a flinch (_add_handovers). From any other one-shot there is no direct
	# edge, and routing through Locomotion would flash a walk, so that case restarts.
	var current := str(_state_machine.get_current_node())
	if current == LOCOMOTION_STATE or current == SWIM_STATE or _handovers.has("%s>%s" % [current, clip_name]):
		if current != LOCOMOTION_STATE and current != SWIM_STATE:
			_begin_handover(ONE_SHOT_HANDOVER)
		elif _starts_with_any(clip_name, HANDS_OVER):
			_begin_handover(ONE_SHOT_BLEND_IN, SWING_ARMS)
		_state_machine.travel(clip_name)
	else:
		_state_machine.start(clip_name, true)
	_one_shot = clip_name
	_one_shot_time = 0.0
	_one_shot_length = clip_length(clip_name)
	speed_scale = 1.0
	_fired.clear()
	return true


func stop_intent() -> void:
	_holding = ""
	_stance = ""
	if _one_shot.is_empty():
		return
	var finished := _one_shot
	_one_shot = ""
	if _state_machine != null:
		_state_machine.travel(_rest_state())
	clip_finished.emit(finished)


func current_intent() -> String:
	return _one_shot


## Holds the picture still for `seconds` where a blow lands (a hit-stop), then plays it up to
## HIT_STOP_CATCH_UP times as fast until it has caught the time up. The model is only a picture of
## the AnimationDriver's timeline (which keeps the hit windows, the cancels and every other §5.3
## timing on the physics clock), so a hit-stop delays nothing but the picture, by a few frames.
func hit_stop(seconds: float, replace := false) -> void:
	if seconds <= 0.0 and not replace:
		return
	var s := clampf(seconds, 0.0, HIT_STOP_MOST_S)
	_stop_left = s if replace else maxf(_stop_left, s)


## Seconds the picture is behind the timeline because of hit-stops, still to be caught up.
func hit_stop_owed() -> float:
	return _stop_owed + _stop_left


## How much of `delta` the picture plays this frame: none while held, more while catching up.
func _held_back(delta: float) -> float:
	if _stop_left > 0.0:
		var d := minf(_stop_left, delta)
		_stop_left -= d
		_stop_owed = minf(_stop_owed + d, HIT_STOP_OWED_MOST)
		return delta - d
	if _stop_owed > 0.0:
		var extra := minf(_stop_owed, delta * (HIT_STOP_CATCH_UP - 1.0))
		_stop_owed -= extra
		return delta + extra
	return delta


## The stance held over the legs (a raised guard), or "".
func current_stance() -> String:
	return _stance


## Past these distances from the eye a body's pose is worked out every second, and every fourth,
## frame (with the time of the frames between), staggered so each frame takes a share: forty people
## and foes posed in full every frame were most of what a film's frame cost the main thread, most of
## them a hundred metres off or more (TRIAGE item 36). A fight's swing or a flinch is always posed.
const POSE_HALF_M := 35.0
const POSE_QUARTER_M := 90.0
var _pose_owed := 0.0


func _process(delta: float) -> void:
	var every := _pose_every()
	if every > 1:
		_pose_owed += delta
		if (Engine.get_process_frames() + get_instance_id()) % every != 0:
			return
		delta = _pose_owed
		_pose_owed = 0.0
	elif _pose_owed > 0.0:
		delta += _pose_owed
		_pose_owed = 0.0
	_pose(delta)


## How often this body is posed: every frame near the eye, in a fight's move, or with no eye.
func _pose_every() -> int:
	if not _one_shot.is_empty() or not is_inside_tree():
		return 1
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1
	var d := cam.global_position.distance_squared_to(global_position)
	if d > POSE_QUARTER_M * POSE_QUARTER_M:
		return 4
	var every := 2 if d > POSE_HALF_M * POSE_HALF_M else 1
	if d > POSE_ALWAYS_M * POSE_ALWAYS_M and not _unseen_exempt() and not _seen_from(cam, sqrt(d)):
		return POSE_UNSEEN_EVERY
	return every


## A body neither the eye nor its shadow can be seen in -- behind the camera, off the side of the
## frame -- is posed every fourth frame, as a body past POSE_QUARTER_M is, with the time between
## (a village is most of a frame's scripts, and half of it is behind you). What makes it "seen" is
## generous: its sphere, grown with its distance so a quick turn cannot bring it into the frame
## before it is posed again, or any stretch of the shadow the sun or the moon throws from it. The
## player's own body, a torch-bearer (the torch's light moves with the hand) and anybody within
## POSE_ALWAYS_M are always posed.
const POSE_ALWAYS_M := 4.0
const POSE_UNSEEN_EVERY := 4
const UNSEEN_MARGIN_M := 1.5
const UNSEEN_MARGIN_PER_M := 0.12
## How tall a body's shadow is reckoned from, and the longest shadow reckoned with (a low sun).
const SHADOW_FROM_M := 2.4
const SHADOW_MOST_M := 60.0
const SHADOW_STEP_M := 3.0

## The eye's frustum and the shadow's way, worked out once a frame for every body.
static var _view_frame := -1
static var _view_planes: Array[Plane] = []
static var _view_cam: Camera3D = null
static var _shadow_way := Vector3.ZERO
## Indoors every lamp and hearth throws shadows from any side, so nobody is let off there; and a
## lantern or torch the player carries throws them round the player, as far as it reaches.
static var _indoors := false
static var _carried_at := Vector3.INF
static var _carried_reach := 0.0
var _exempt_checked := false
var _is_players := false


func _unseen_exempt() -> bool:
	if not _exempt_checked:
		_exempt_checked = true
		var n: Node = self
		while n != null:
			if n.is_in_group("player"):
				_is_players = true
				break
			n = n.get_parent()
	return _is_players or first_person or holds_torch()


func _seen_from(cam: Camera3D, dist: float) -> bool:
	var f := Engine.get_process_frames()
	if f != _view_frame or cam != _view_cam:
		_view_frame = f
		_view_cam = cam
		_view_planes = cam.get_frustum()
		_shadow_way = _shadow_way_now()
		_read_local_shadows()
	if _indoors:
		return true
	if _carried_at != Vector3.INF and global_position.distance_to(_carried_at) < _carried_reach:
		return true
	var r := UNSEEN_MARGIN_M + UNSEEN_MARGIN_PER_M * dist
	var at := global_position + Vector3(0.0, 1.0, 0.0)
	if _in_planes(at, r):
		return true
	if _shadow_way == Vector3.ZERO:
		return false
	# along the shadow, from the feet to where the top of the head's shadow lands
	var reach := minf(SHADOW_FROM_M / maxf(-_shadow_way.y, 0.04), SHADOW_MOST_M)
	var t := SHADOW_STEP_M
	var foot := global_position
	while t < reach + SHADOW_STEP_M:
		if _in_planes(foot + _shadow_way * minf(t, reach) + Vector3(0.0, 0.5, 0.0), r):
			return true
		t += SHADOW_STEP_M
	return false


static func _in_planes(p: Vector3, r: float) -> bool:
	for pl in _view_planes:
		if pl.distance_to(p) > r:
			return false
	return true


static func _read_local_shadows() -> void:
	_indoors = false
	_carried_at = Vector3.INF
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var atmos: Node = tree.get_first_node_in_group("atmosphere")
	if atmos != null and bool(atmos.get("interior")):
		_indoors = true
	var player := tree.get_first_node_in_group("player")
	if player != null:
		var carried := player.get("_lantern_light") as OmniLight3D
		if carried != null and is_instance_valid(carried) and carried.is_visible_in_tree():
			_carried_at = carried.global_position
			_carried_reach = carried.omni_range + 2.0


## The way a shadow falls from a body (the shadow-casting light's direction), or zero when no
## directional light casts one.
static func _shadow_way_now() -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	var atmos: Node = tree.get_first_node_in_group("atmosphere") if tree != null else null
	if atmos == null:
		return Vector3.ZERO
	for key in ["sun", "moon"]:
		var light := atmos.get(key) as DirectionalLight3D
		if light != null and light.is_visible_in_tree() and light.shadow_enabled:
			var way := -light.global_transform.basis.z
			if way.y < 0.0:
				return way.normalized()
	return Vector3.ZERO


func _pose(delta: float) -> void:
	_update_locomotion(delta)
	_ease_grip(delta)
	if arm_room != null:
		arm_room.hold = move_toward(arm_room.hold, _arm_hold_now(), delta / ARM_HOLD_BLEND_S)
	if skirt_drive != null:
		skirt_drive.amount = move_toward(skirt_drive.amount, skirt_amount_now(), delta / SKIRT_BLEND_S)
	var step := _held_back(delta) * (maxf(speed_scale, 0.0) if not _one_shot.is_empty() else 1.0)
	if anim_tree != null:
		anim_tree.advance(step)
		if _handover_t >= 0.0:
			_blend_handover(step)
	if not _one_shot.is_empty():
		_advance_one_shot(step)
	_advance_stance(step)
	_turn_the_hips()
	_lay_carry(delta)
	_aim_the_body(delta)
	_hold_in_view(delta)
	_hold_the_torch(delta)
	_rest_the_pole(delta)
	_plant_feet(delta)
	if bow_hands != null:
		bow_hands.update(self, delta)


## The stance's clip plays on (at _stance_rate); one of STANCE_ENDS that has played through lets the
## upper body go back to the legs' over STANCE_BLEND_S.
func _advance_stance(step: float) -> void:
	if _stance.is_empty():
		return
	_stance_time += step * _stance_rate()
	if STANCE_ENDS.has(_stance) and _stance_time >= clip_length(_stance):
		_stance = ""


## How fast the stance's clip plays: a timed one (a draw, a loose) at the AnimationDriver's pace for
## it, as a one-shot is (speed_scale); a held one (a guard, a bow held drawn) at its own.
func _stance_rate() -> float:
	return maxf(speed_scale, 0.0) if STANCE_TIMED.has(_stance) else 1.0


## Seconds into the stance's clip (its own time), and the stance's own event times from the sidecar.
func stance_time() -> float:
	return _stance_time


func stance_event(event_name: String, fallback := -1.0) -> float:
	for e in clip_events(_stance):
		if str(e.get("name", "")) == event_name:
			return float(e.get("t", fallback))
	return fallback


## How much the body is turned to its aim now (0..1): the bow up from the moment it is raised
## until the loose's follow-through is done.
func aim_weight() -> float:
	return _aim_w


func _aim_wanted() -> float:
	match _stance:
		"Bow_Draw":
			var from := stance_event("nocked", 0.3)
			var full := stance_event("bow_raised", 0.56)
			return clampf((_stance_time - from) / maxf(full - from, 0.01), 0.0, 1.0)
		"Bow_Aim":
			return 1.0
		"Bow_Release":
			var hold := stance_event("cancel_ok", 0.3)
			var length := maxf(clip_length("Bow_Release"), hold + 0.01)
			return 1.0 - clampf((_stance_time - hold) / (length - hold), 0.0, 1.0)
	return 0.0


## The spine and chest turned up or down and round to the aim (aim_pitch, aim_yaw) over whatever the
## clips have set, with a held draw's tremble on top: the bow's clips are drawn level and straight
## ahead, and the body bends to where the arrow will go. Only while a bow is up (_aim_wanted).
func _aim_the_body(delta: float) -> void:
	_aim_w = move_toward(_aim_w, maxf(_aim_wanted() * _stance_w, clampf(view_follow, 0.0, 1.0)), delta / AIM_BLEND_S)
	_pre_aim.clear()
	if skeleton == null or _aim_w <= 0.001:
		return
	_tremble_t += delta
	var shake := Vector2(sin(_tremble_t * 23.0) + 0.6 * sin(_tremble_t * 37.0 + 1.3),
			sin(_tremble_t * 29.0 + 0.7) + 0.5 * sin(_tremble_t * 41.0)) * (aim_tremble / 1.6)
	var pitch := clampf(aim_pitch + shake.y, -AIM_MOST, AIM_MOST) * _aim_w
	var yaw := clampf(aim_yaw + shake.x, -AIM_MOST, AIM_MOST) * _aim_w
	# the rig faces +Z, so its right is -X: up is a turn about +X the other way
	for pair in [["Spine", AIM_SPINE], ["Chest", AIM_CHEST]]:
		var b := skeleton.find_bone(str(pair[0]))
		if b < 0:
			continue
		var share := float(pair[1])
		_pre_aim[b] = skeleton.get_bone_pose_rotation(b)
		var turn := Quaternion(Vector3.UP, yaw * share) * Quaternion(Vector3.RIGHT, -pitch * share)
		_set_bone_global_rotation(b, turn * skeleton.get_bone_global_pose(b).basis.get_rotation_quaternion())


# --- first person (triage 57) ------------------------------------------------------------------

## The arms held in the carry (see `carry`), as far as it has eased in: each arm bone turned from
## the pose the clips set towards Idle_Combat's, played on at its own pace so the guard breathes.
## Only the arms: the chest, the head and the legs go on with the walk, the run or the idle, so the
## hands ride the stride as they would.
func _lay_carry(delta: float) -> void:
	var wanted := carry if first_person and _one_shot.is_empty() and _stance.is_empty() and not _swimming \
			and _holding.is_empty() else 0.0
	_carry_w = move_toward(_carry_w, clampf(wanted, 0.0, 1.0), delta / CARRY_BLEND_S)
	if skeleton == null or _carry_w <= 0.001:
		return
	var clip := _find_animation(CARRY_CLIP)
	if clip == null:
		return
	if _carry_tracks.is_empty():
		for i in clip.get_track_count():
			if clip.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var bone_name := str(clip.track_get_path(i).get_concatenated_subnames())
			if CARRY_BONES.has(bone_name):
				var b := skeleton.find_bone(bone_name)
				if b >= 0:
					_carry_tracks[b] = i
	_carry_t = fmod(_carry_t + delta, maxf(clip.length, 0.01))
	var w := smoothstep(0.0, 1.0, _carry_w)
	for b in _carry_tracks:
		var held := clip.rotation_track_interpolate(int(_carry_tracks[b]), _carry_t)
		skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b).slerp(held, w))


## The arms placed for the eyes in first person, over whatever posed them this frame:
##   * in the carry (`carry`, as far as it has eased in) each hand is reached to its place in the view
##     (FP_HOLD_*: across, up and ahead of the eyes, the view's own axes) by turning its upper arm and
##     forearm, the elbow down and out; a weapon in the right hand is turned so its blade points up,
##     ahead and across the view (FP_BLADE), and a free left hand keeps its grip on the weapon where
##     the guard put it (a two-handed hilt, the pommel); a shield or a bow in the left has a place of
##     its own. Idle_Combat's guard, laid on first, held its sword upright 20 cm before the eyes:
##     a black bar across half the picture;
##   * a raised guard (Block_Idle, and a blow taken on it) is held the same way at FP_GUARD_*: the
##     blade across the view, or the shield before its left. Laid on as the clip has it, the guard
##     was a black crossguard and an open hand filling the picture a hand's breadth from the eyes;
##   * in a swing, a saying, a parry, or a reach to use or take something (FP_LIFTS) both arms are
##     turned up together about the line of the shoulders by FP_LIFT_DEG, and each hand is kept inside
##     the view (_keep_hands_in_view), so an arc the clip draws wide and low at the chest is drawn
##     where the eyes see it. Not a bow, whose clips are already drawn at the eye and aimed.
func _hold_in_view(delta: float) -> void:
	var lift_to := 1.0 if first_person and _starts_with_any(_one_shot, FP_LIFTS) else 0.0
	_lift_w = move_toward(_lift_w, lift_to, delta / FP_LIFT_S)
	var guard_to := 1.0 if first_person and (_stance == "Block_Idle" or _one_shot == "Block_Hit") else 0.0
	_guard_w = move_toward(_guard_w, guard_to, delta / CARRY_BLEND_S)
	if skeleton == null or not first_person:
		return
	if _lift_w > 0.001:
		var lw := smoothstep(0.0, 1.0, _lift_w)
		_lift_arms(deg_to_rad(FP_LIFT_DEG) * lw)
		_keep_hands_in_view(lw)
	if _carry_w > 0.001:
		_reach_for_view(smoothstep(0.0, 1.0, _carry_w), false)
	if _guard_w > 0.001:
		_reach_for_view(smoothstep(0.0, 1.0, _guard_w), true)


## Both arms turned up by `angle` (rad) about the line of the shoulders, as one: every Shoulder bone
## turned about its own joint, which is on that line.
func _lift_arms(angle: float) -> void:
	var left := skeleton.find_bone("Shoulder.L")
	var right := skeleton.find_bone("Shoulder.R")
	if left < 0 or right < 0:
		return
	var axis := (skeleton.get_bone_global_pose(left).origin - skeleton.get_bone_global_pose(right).origin)
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	# the rig faces +Z and +X is its left: a turn about +X takes its forward (+Z) down, so up is -angle
	var q := Quaternion(axis.normalized(), -angle)
	for b in [left, right]:
		_set_bone_global_rotation(b, q * skeleton.get_bone_global_pose(b).basis.get_rotation_quaternion())


## Each hand drawn into the view in a swing (see FP_ACROSS), its arm reaching for the place and the
## hand keeping the turn the clip gave it, so the blade still points where the clip points it. A
## left hand gripping the right hand's weapon keeps its grip; a free one is drawn in only for a saying.
func _keep_hands_in_view(w: float) -> void:
	var names := ["UpperArm.R", "LowerArm.R", "Hand.R", "UpperArm.L", "LowerArm.L", "Hand.L"]
	var bones: Array[int] = []
	for n in names:
		var b := skeleton.find_bone(n)
		if b < 0:
			return
		bones.append(b)
	var socket_r := skeleton.find_bone("Socket.WeaponR")
	var was: Array[Quaternion] = []
	for b in bones:
		was.append(skeleton.get_bone_pose_rotation(b))
	var head := skeleton.find_bone("Head")
	var eye := skeleton.get_bone_global_pose(head) * (_eye_in_head if _eye_in_head != Vector3.INF else EYE_IN_HEAD)
	var turn := _view_turn()
	var grip_l := Transform3D.IDENTITY
	var gripping := false
	if socket_r >= 0 and _holds("WeaponR"):
		grip_l = skeleton.get_bone_global_pose(socket_r).affine_inverse() * skeleton.get_bone_global_pose(bones[5])
		gripping = grip_l.origin.length() < FP_TWO_HANDS_M
	_hand_into_view(bones[0], bones[1], bones[2], eye, turn, Vector3(-0.8, -0.7, -0.3))
	if gripping:
		var want := skeleton.get_bone_global_pose(socket_r) * grip_l
		_reach(bones[3], bones[4], bones[5], want.origin, turn * Vector3(0.8, -0.7, -0.3))
		_set_bone_global_rotation(bones[5], want.basis.get_rotation_quaternion())
	elif _one_shot.begins_with("Cast_"):
		# the hand a saying is said with; a free hand in a swing goes where the swing has it
		_hand_into_view(bones[3], bones[4], bones[5], eye, turn, Vector3(0.8, -0.7, -0.3))
	if w < 0.999:
		for i in bones.size():
			skeleton.set_bone_pose_rotation(bones[i], was[i].slerp(skeleton.get_bone_pose_rotation(bones[i]), w))


func _hand_into_view(upper: int, lower: int, hand: int, eye: Vector3, turn: Quaternion, pole: Vector3) -> void:
	var at := skeleton.get_bone_global_pose(hand).origin
	var local := turn.inverse() * (at - eye)
	var v := Vector3(-local.x, local.y, local.z)          # across to the right, up, ahead
	var z := maxf(v.z, FP_NEAREST)
	var put := Vector3(clampf(v.x, -FP_ACROSS * z, FP_ACROSS * z), clampf(v.y, -FP_BELOW * z, FP_ABOVE * z), z)
	if put.distance_to(v) < 0.005:
		return
	var keep := skeleton.get_bone_global_pose(hand).basis.get_rotation_quaternion()
	_reach(upper, lower, hand, _in_view(eye, put), turn * pole)
	_set_bone_global_rotation(hand, keep)


## A place in the view (x across to the right, y up, z ahead of the eyes, metres) in the skeleton's
## space: the view looks along the body's way, pitched by view_pitch.
func _in_view(eye: Vector3, v: Vector3) -> Vector3:
	return eye + _view_turn() * Vector3(-v.x, v.y, v.z)


func _view_turn() -> Quaternion:
	return Quaternion(Vector3.RIGHT, -clampf(view_pitch, -1.5, 1.5))


## The carry's reach, or the guard's (see _hold_in_view), at `w` of the way from the pose the
## clips set.
func _reach_for_view(w: float, guard: bool) -> void:
	var names := ["UpperArm.R", "LowerArm.R", "Hand.R", "UpperArm.L", "LowerArm.L", "Hand.L"]
	var bones: Array[int] = []
	for n in names:
		var b := skeleton.find_bone(n)
		if b < 0:
			return
		bones.append(b)
	var was: Array[Quaternion] = []
	for b in bones:
		was.append(skeleton.get_bone_pose_rotation(b))
	var head := skeleton.find_bone("Head")
	var eye := skeleton.get_bone_global_pose(head) * (_eye_in_head if _eye_in_head != Vector3.INF else EYE_IN_HEAD)
	var right_holds := _holds("WeaponR")
	var torch := holds_torch()
	var bow := _holds("WeaponL") and not torch
	var left_holds := bow or torch or _holds("ShieldL")
	var socket_r := skeleton.find_bone("Socket.WeaponR")
	# the left hand's grip on what the right holds, as the guard has it
	var grip_l := Transform3D.IDENTITY
	if right_holds and not left_holds and socket_r >= 0:
		grip_l = skeleton.get_bone_global_pose(socket_r).affine_inverse() * skeleton.get_bone_global_pose(bones[5])
	# a guard holds a two-handed weapon in both hands; a one-handed blade's is the right hand's alone
	var two_hands := right_holds and not left_holds and grip_l.origin.length() < FP_TWO_HANDS_M
	var turn := _view_turn()
	if bow:
		_reach(bones[3], bones[4], bones[5], _in_view(eye, FP_HOLD_BOW), turn * Vector3(0.9, -0.5, 0.2))
		_turn_held(bones[5], skeleton.find_bone("Socket.WeaponL"), turn * _flip(FP_BOW_AXIS))
		_reach(bones[0], bones[1], bones[2], _in_view(eye, FP_HOLD_FREE_R), turn * Vector3(-0.9, -0.6, -0.2))
	elif right_holds:
		_reach(bones[0], bones[1], bones[2], _in_view(eye, FP_GUARD_R if guard else FP_HOLD_R), turn * Vector3(-0.8, -0.7, -0.3))
		_turn_held(bones[2], socket_r, turn * _flip(FP_GUARD_BLADE if guard else FP_BLADE))
		if left_holds or (guard and not two_hands):
			_reach(bones[3], bones[4], bones[5], _in_view(eye, FP_GUARD_L if guard and left_holds else FP_HOLD_L),
					turn * Vector3(0.8, -0.7, -0.3))
		else:
			var want := skeleton.get_bone_global_pose(socket_r) * grip_l
			_reach(bones[3], bones[4], bones[5], want.origin, turn * Vector3(0.8, -0.7, -0.3))
			_set_bone_global_rotation(bones[5], want.basis.get_rotation_quaternion())
	else:
		_reach(bones[0], bones[1], bones[2], _in_view(eye, FP_HOLD_FREE_R), turn * Vector3(-0.8, -0.7, -0.3))
		_reach(bones[3], bones[4], bones[5], _in_view(eye, _mirror(FP_HOLD_FREE_R) if not left_holds else FP_HOLD_L),
				turn * Vector3(0.8, -0.7, -0.3))
	if w < 0.999:
		for i in bones.size():
			skeleton.set_bone_pose_rotation(bones[i], was[i].slerp(skeleton.get_bone_pose_rotation(bones[i]), w))


## A view direction (x right, y up, z ahead) in the rig's axes, where +X is the body's left.
static func _flip(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z).normalized()


static func _mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## Whether the left hand holds a torch (HeldTorch).
func holds_torch() -> bool:
	var s := socket("WeaponL")
	if s == null:
		return false
	for c in s.get_children():
		if c is HeldTorch and not c.is_queued_for_deletion():
			return true
	return false


## The left arm raised to hold a torch up (TORCH_HOLD_*), over whatever posed it: through walks,
## runs, swings and sayings, not in a roll, a stagger, a fall, a climb, the saddle or the water,
## where the clips' own arms are kept.
func _hold_the_torch(delta: float) -> void:
	var want := 1.0 if holds_torch() and (_one_shot.is_empty() or _starts_with_any(_one_shot, FP_LIFTS)) \
			and _stance.is_empty() and not _swimming and _holding.is_empty() else 0.0
	_torch_w = move_toward(_torch_w, want, delta / CARRY_BLEND_S)
	if skeleton == null or _torch_w <= 0.001:
		return
	var bones: Array[int] = []
	for n in ["UpperArm.L", "LowerArm.L", "Hand.L"]:
		var b := skeleton.find_bone(n)
		if b < 0:
			return
		bones.append(b)
	var socket_l := skeleton.find_bone("Socket.WeaponL")
	var was: Array[Quaternion] = []
	for b in bones:
		was.append(skeleton.get_bone_pose_rotation(b))
	if first_person:
		var head := skeleton.find_bone("Head")
		var eye := skeleton.get_bone_global_pose(head) * (_eye_in_head if _eye_in_head != Vector3.INF else EYE_IN_HEAD)
		var turn := _view_turn()
		_reach(bones[0], bones[1], bones[2], _in_view(eye, TORCH_HOLD_FP), turn * Vector3(0.8, -0.7, -0.3))
		_turn_held(bones[2], socket_l, turn * _flip(TORCH_UP_FP))
	else:
		var chest := skeleton.find_bone("Chest")
		if chest < 0:
			return
		var at := skeleton.get_bone_global_pose(chest).origin + TORCH_HOLD_3P
		_reach(bones[0], bones[1], bones[2], at, Vector3(0.8, -0.7, -0.3))
		_turn_held(bones[2], socket_l, TORCH_UP_3P.normalized())
	var w := smoothstep(0.0, 1.0, _torch_w)
	if w < 0.999:
		for i in bones.size():
			skeleton.set_bone_pose_rotation(bones[i], was[i].slerp(skeleton.get_bone_pose_rotation(bones[i]), w))


## A long haft at rest stood upright at the right side (POLE_*), out of a swing, a flinch, a
## stance or the water; the swing takes it from wherever the clip's own arm has it.
func _rest_the_pole(delta: float) -> void:
	var want := 1.0 if rests_poles and not first_person and _one_shot.is_empty() and _stance.is_empty() \
			and not _swimming and _holding.is_empty() and held_length("WeaponR") >= POLE_FROM_M else 0.0
	_pole_w = move_toward(_pole_w, want, delta / CARRY_BLEND_S)
	if skeleton == null or _pole_w <= 0.001:
		return
	var bones: Array[int] = []
	for n in ["UpperArm.R", "LowerArm.R", "Hand.R", "Chest"]:
		var b := skeleton.find_bone(n)
		if b < 0:
			return
		bones.append(b)
	var was: Array[Quaternion] = []
	for i in 3:
		was.append(skeleton.get_bone_pose_rotation(bones[i]))
	var at := skeleton.get_bone_global_pose(bones[3]).origin + POLE_HOLD_3P
	_reach(bones[0], bones[1], bones[2], at, Vector3(-0.8, -0.7, -0.3))
	_turn_held(bones[2], skeleton.find_bone("Socket.WeaponR"), POLE_UP_3P.normalized())
	var w := smoothstep(0.0, 1.0, _pole_w)
	if w < 0.999:
		for i in 3:
			skeleton.set_bone_pose_rotation(bones[i], was[i].slerp(skeleton.get_bone_pose_rotation(bones[i]), w))


## How long what a socket holds is, end to end along the socket's +Y, in the rig's metres (0 for
## nothing): read off its meshes once and kept on it.
func held_length(socket_name: String) -> float:
	var s := socket(socket_name)
	if s == null:
		return 0.0
	for c in s.get_children():
		if not c.has_meta(HeldItems.TAG) or c.is_queued_for_deletion() or not (c is Node3D):
			continue
		if c.has_meta("held_length"):
			return float(c.get_meta("held_length"))
		var lo := INF
		var hi := -INF
		for mi in (c as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			# in the socket's own frame (the rig's metres, the haft along +Y)
			var box := s.global_transform.affine_inverse() * m.global_transform * m.mesh.get_aabb()
			lo = minf(lo, box.position.y)
			hi = maxf(hi, box.end.y)
		var length := hi - lo if hi > lo else 0.0
		c.set_meta("held_length", length)
		return length
	return 0.0


## Whether something is held in this socket (a HeldItems model).
func _holds(socket_name: String) -> bool:
	var s := socket(socket_name)
	if s == null:
		return false
	for c in s.get_children():
		if c.has_meta(HeldItems.TAG) and not c.is_queued_for_deletion():
			return true
	return false


## A two-bone reach: the upper arm and forearm turned so the hand's joint is at `target` (skeleton
## space), the elbow bent toward `pole`. Out of reach, the arm points at it, straight.
func _reach(upper: int, lower: int, hand: int, target: Vector3, pole: Vector3) -> void:
	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(lower).origin
	var c := skeleton.get_bone_global_pose(hand).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to := target - a
	if l1 < 0.01 or l2 < 0.01 or to.length() < 0.01:
		return
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var side := pole - dir * pole.dot(dir)
	if side.length() < 0.001:
		side = Vector3.DOWN - dir * dir.y
	var elbow := a + dir * (l1 * cos_a) + side.normalized() * (l1 * sqrt(1.0 - cos_a * cos_a))
	_turn_bone_toward(upper, b - a, elbow - a)
	b = skeleton.get_bone_global_pose(lower).origin
	c = skeleton.get_bone_global_pose(hand).origin
	_turn_bone_toward(lower, c - b, a + dir * d - b)


## Turns a bone about its own joint so `from` (a direction it carries, skeleton space) points along `to`.
func _turn_bone_toward(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length() < 0.0001 or to.length() < 0.0001:
		return
	var f := from.normalized()
	var t := to.normalized()
	if f.dot(t) > 0.99999:
		return
	var q := Quaternion(f, t) if f.dot(t) > -0.9999 else Quaternion(f.cross(Vector3.UP).normalized(), PI)
	_set_bone_global_rotation(bone, q * skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())


## Turns the hand so what its socket holds points along `way` (skeleton space; the held model's +Y).
func _turn_held(hand: int, socket_bone: int, way: Vector3) -> void:
	if socket_bone < 0:
		return
	_turn_bone_toward(hand, skeleton.get_bone_global_pose(socket_bone).basis.y, way)


## How far the arms are in the carry now (0..1).
func carry_weight() -> float:
	return _carry_w


## The meshes first person draws into the shadows only: the head and everything on it.
func first_person_hidden() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for slot in FP_HEAD_SLOTS:
		for mi in _part_meshes.get(slot, []):
			if mi is MeshInstance3D and is_instance_valid(mi):
				out.append(mi)
	var own := _default_meshes.get("head") as MeshInstance3D
	if own != null:
		out.append(own)
	for eye in _default_eyes:
		out.append(eye)
	return out


## Puts the head into the shadows only, or back, as `first_person` says. Each mesh keeps the shadow
## setting it had (an eye casts none) under the meta "fp_cast" while it is hidden.
func _apply_first_person_look() -> void:
	for mi in first_person_hidden():
		if first_person:
			if not mi.has_meta("fp_cast"):
				mi.set_meta("fp_cast", mi.cast_shadow)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif mi.has_meta("fp_cast"):
			mi.cast_shadow = int(mi.get_meta("fp_cast")) as GeometryInstance3D.ShadowCastingSetting
			mi.remove_meta("fp_cast")


## Where the eyes are now, in world space: between the eyeballs, carried by the Head bone as the
## clips and the aim pose it (the first-person camera's place).
func eye_point() -> Vector3:
	if skeleton == null:
		return global_position + Vector3.UP * 1.62
	var head := skeleton.find_bone("Head")
	if head < 0:
		return global_position + Vector3.UP * 1.62
	if _eye_in_head == Vector3.INF:
		_eye_in_head = _measure_eye_in_head(head)
	return skeleton.global_transform * (skeleton.get_bone_global_pose(head) * _eye_in_head)


## The eyes' middle in the Head bone's rest frame, from the rig's eyeballs (their bind-pose boxes).
func _measure_eye_in_head(head: int) -> Vector3:
	if _default_eyes.is_empty():
		return EYE_IN_HEAD + Vector3(0.0, 0.0, EYE_AHEAD)
	var mid := Vector3.ZERO
	for eye in _default_eyes:
		var in_skeleton := skeleton.global_transform.affine_inverse() * eye.global_transform
		mid += in_skeleton * eye.get_aabb().get_center()
	mid /= float(_default_eyes.size())
	return skeleton.get_bone_global_rest(head).affine_inverse() * mid + Vector3(0.0, 0.0, EYE_AHEAD)


## A fight's hand-over (a swing into the next, a roll, a flinch) is the pose the last clip left
## blended into the new clip's, bone by bone, over ONE_SHOT_HANDOVER: each rotation slerped and each
## position lerped, eased in and out so the hands neither start nor stop with a jolt. The mixer's own
## cross-fade is not the pose in between: it takes each clip's turn of a bone from the bone's rest,
## weighted, and composes one over the other, and between two poses far apart that goes where
## neither does. From the two-handed chop's follow-through into the sweep after it, it put a
## spear's butt 9 cm through the chest (test_attack_motion).
##
## A swing from the legs blends the body so, but not the arms and what they hold (`free`): they take
## the swing's own pose from its first frame. Between the idle's hang and a swing's wind-up there is
## no arc of the arms that keeps a long weapon out of the body: the mixer's cross-fade put a spear's
## butt 6-8 cm into the chest for two frames, and a bone-by-bone blend 11 cm (test_attack_motion).
func _begin_handover(across: float, free: Array[String] = []) -> void:
	if skeleton == null:
		return
	_handover_len = across
	var n := skeleton.get_bone_count()
	_handover_from.resize(n)
	for i in n:
		_handover_from[i] = [skeleton.get_bone_pose_rotation(i), skeleton.get_bone_pose_position(i)]
	for bone_name in free:
		var b := skeleton.find_bone(bone_name)
		if b >= 0:
			_handover_from[b] = null
	_handover_t = 0.0


## Called after the tree has set this frame's pose (see _begin_handover).
func _blend_handover(step: float) -> void:
	_handover_t += step
	var w := _handover_t / _handover_len
	if w >= 1.0 or skeleton == null:
		_handover_t = -1.0
		return
	w = w * w * (3.0 - 2.0 * w)
	for i in mini(_handover_from.size(), skeleton.get_bone_count()):
		if _handover_from[i] == null:
			continue
		var was: Array = _handover_from[i]
		skeleton.set_bone_pose_rotation(i, (was[0] as Quaternion).slerp(skeleton.get_bone_pose_rotation(i), w))
		skeleton.set_bone_pose_position(i, (was[1] as Vector3).lerp(skeleton.get_bone_pose_position(i), w))


## Turns the hips (and the legs under them) toward the way the body goes, and the chest back most of
## the way to face ahead: the legs play the nearest of the four ways, and this is the rest of it.
func _turn_the_hips() -> void:
	if skeleton == null or absf(_hips_turn) < 0.001 or not _one_shot.is_empty() or not _holding.is_empty():
		return
	var hips := skeleton.find_bone("Hips")
	var spine := skeleton.find_bone("Spine")
	if hips < 0 or spine < 0:
		return
	# + to the right; the rig faces +Z, so its right is -X, a turn the other way about +Y
	var turn := Quaternion(Vector3.UP, -_hips_turn)
	var spine_was := skeleton.get_bone_global_pose(spine).basis.get_rotation_quaternion()
	_set_bone_global_rotation(hips, turn * skeleton.get_bone_global_pose(hips).basis.get_rotation_quaternion())
	var back := Quaternion(Vector3.UP, _hips_turn * CHEST_BACK)
	_set_bone_global_rotation(spine, back * turn * spine_was)


func _set_bone_global_rotation(bone: int, q: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var p := Quaternion.IDENTITY
	if parent >= 0:
		p = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (p.inverse() * q).normalized())


## The feet held where they stand when the body stops, and stepped into the stance, on the pose
## the clips have just set (FootPlanter). Not on a child's rig: its legs are re-proportioned after
## this, by ChildProportions, and a solve on the grown legs would miss its feet.
func _plant_feet(delta: float) -> void:
	if _plants_feet():
		# a turn on the spot has the feet once it is all in; until then the planter holds them where
		# they stand, which is where the turn's first frame puts them
		var turning := not _turn.is_empty()
		if turning and _turn_w >= 0.999 and _planter.is_planted():
			# at once: the turn's feet are where the planter holds them, and eased from one to the
			# other a held ankle and a foot pivoting on its ball pull the ball two ways
			_planter.release()
		var busy := not _one_shot.is_empty() or not _holding.is_empty() or (turning and _turn_w >= 0.999) \
				or _in_flight
		_planter.update(delta, _locomotion.length(), busy, turning)
	elif _planter != null and _planter.is_planted():
		_planter.release()


func _plants_feet() -> bool:
	return plant_feet and _planter != null and _child_mod == null and anim_tree != null and not _swimming


## The feet the planter holds, for tests and the motion studio (null on a rig without legs).
func foot_planter() -> FootPlanter:
	return _planter


func _advance_one_shot(step: float) -> void:
	var prev := _one_shot_time
	_one_shot_time += step
	_fire_events(prev, _one_shot_time)
	if _one_shot_time >= _one_shot_length and _loops_until_stopped(_one_shot):
		# a looping clip played as an intent (a rider's seat, a jump's hang, a held cast) goes round
		# until something else is played or it is stopped: it went back to the idle after one turn,
		# and a rider stood up in the saddle 2.4 s after sitting down
		_one_shot_time = fmod(_one_shot_time, maxf(_one_shot_length, 0.001))
		_fired.clear()
		return
	if _one_shot_time >= _one_shot_length:
		var finished := _one_shot
		_one_shot = ""
		if HOLD_LAST_POSE.has(finished):
			_holding = finished
		elif _state_machine != null:
			_state_machine.travel(_rest_state())
		clip_finished.emit(finished)


## A clip the sidecar marks as a loop, played as an intent, and not one whose last pose is held.
func _loops_until_stopped(clip: String) -> bool:
	return not HOLD_LAST_POSE.has(clip) and bool((_clip_data.get(clip, {}) as Dictionary).get("loop", false))


## The pose a finished one-shot left the body lying in, or "" when it went back to its feet.
func holding_pose() -> String:
	return _holding


## Events come from the clips.json sidecar: everything in [prev, now) fires once.
func _fire_events(prev: float, now: float) -> void:
	var events := clip_events(_one_shot)
	for i in events.size():
		if _fired.has(i):
			continue
		var e: Dictionary = events[i]
		var t := float(e.get("t", 0.0))
		if t >= prev and t < now:
			_fired[i] = true
			clip_event.emit(str(e.get("name", "")))
