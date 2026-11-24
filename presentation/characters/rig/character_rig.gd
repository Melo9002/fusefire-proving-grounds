@tool
class_name CharacterRig
extends Node3D

const RigResolver := preload("res://presentation/characters/rig_profile/rig_resolver.gd")
const ANIMATION_CONTROLLER_FALLBACK := preload("res://presentation/characters/rig/character_animation_controller.gd")

@export_group("Model Assets")
## Character model to assemble. It must contain a Skeleton3D.
## Character model instantiated by this presentation rig. MIRA Zero is the supported default.
@export var character_scene: PackedScene = preload("res://art/characters/mira_0/models/mira_0_prototype.glb")
## Optional rig profile (anatomy, joint limits, sockets) describing `character_scene`'s skeleton. PASSIVE in Task 07's first package: it is resolved and validated once when the character is built
## and the result is exposed as `resolved_rig`; nothing in the rig reads it to pose the character yet, so assigning or clearing it changes no behaviour.
@export var rig_profile: Resource
## Uniform correction applied to imported models whose source units are not metres.
@export_range(0.1, 4.0, 0.01) var character_scale := 1.0
## The weapon this character carries (a model with SupportHandTarget and MuzzleSocket nodes), or null for an unarmed character. Equipment is chosen by the scene or the context: the rig requires none.
@export var weapon_scene: PackedScene

## The skeleton configuration the whole stack runs on: which bone plays which anatomical role, derived from `rig_profile` (see RigBones). No code in the stack names a bone.
var bones: RigBones
## Upper arm, forearm and hand of the firing-hand and the support-hand IK chains: read-only views of `bones`.
var right_arm_bones: Array[StringName]:
	get: return bones.right_arm if bones != null else []
var left_arm_bones: Array[StringName]:
	get: return bones.left_arm if bones != null else []

@onready var character_root: Node3D = $Character
@onready var right_hand_target: Marker3D = $Character/IKTargets/RightHandTarget
@onready var right_elbow_pole: Marker3D = $Character/IKTargets/RightElbowPole
@onready var left_elbow_pole: Marker3D = $Character/IKTargets/LeftElbowPole

var skeleton: Skeleton3D
var arm_ik: TwoBoneIK3D
## Environmental traversal (see TraversalSolver / TraversalPoseModifier). `ladder` is null when none; while a ladder is climbed it is the climb (LadderClimb) and `ladder.pose` the typed pose solved for its
## progress (LadderPose). Legs go through `leg_ik` to `foot_targets`, knees toward `knee_poles`.
@export var traversal_profile: TraversalProfile = TraversalProfile.new()
var ladder: LadderClimb
## Stair walking (see StairModel / StairFootPlanner / StairProfile): `stairs` is null when none; while on a stair it is the walk (StairWalk) and `stairs.pose` the typed feet and pelvis solved for the current place (StairPose).
@export var stair_profile: StairProfile = StairProfile.new()
var stairs: StairWalk
var traversal_modifier: TraversalPoseModifier
var foot_modifier: TraversalFootModifier
var leg_ik: TwoBoneIK3D
var foot_targets: Array[Marker3D] = []
var knee_poles: Array[Marker3D] = []
var crouch_modifier: CoverCrouchModifier
## The shared presentation state of this character (time, reported velocity, facing, the moving decision, posture requests). Every host of a rig (the tactical adapter, the workbench)
## ticks it once per frame from its own `_process`; while hosts inherit the rig it is a bound component, afterwards it becomes the node that ticks.
var presenter := CharacterPresenter.new(self)
## The posture the body has actually reached (the ramps below), so a posture request is followed over time and never snaps. Owned here because the rig applies poses; the REQUEST is the
## presenter's (PostureArbiter). `_cover_yaw` is the visual root's yaw, which is the posture's yaw offset once reached.
var _crouch_depth := 0.0
var _kneel := 0.0
var _cover_yaw: float:
	get: return character_root.rotation.y if is_instance_valid(character_root) else 0.0
	set(value):
		if is_instance_valid(character_root):
			character_root.rotation.y = value
## Width of the depth range over which the crouch gives way to kneeling (metres past the deepest natural crouch).
const KNEEL_BLEND_RANGE := 0.08
## Places the weapon's hand targets from the shoulder of the current skeleton pass (see WeaponPoseModifier).
var weapon_pose_modifier: WeaponPoseModifier
## False places the hand targets from the shoulder as the animation leaves it, before the skeleton's modifiers (`update_weapon_pose`), by the same formulas (`apply_weapon_targets`). It is the EDITOR-PREVIEW path
## (the modifier does not run in the editor) and the comparison the weapon-pose tests make; the game always runs the modifier.
var weapon_pose_modifier_enabled := true:
	set(value):
		weapon_pose_modifier_enabled = value
		if is_instance_valid(weapon_pose_modifier):
			weapon_pose_modifier.active = value
var grip_modifier: HandGripModifier
## Forward lean into the rifle while aiming, degrees. Brings the shoulders, and so the support hand,
## toward the front handle.
const AIM_LEAN_DEGREES := 5.0
## Support-side shoulder reach while the rifle is up, degrees.
const SUPPORT_REACH_DEGREES := 14.0
## Finger closure on the rifle: around the front handle, and on the pistol grip.
const SUPPORT_GRIP_CURL := 0.8
const TRIGGER_HAND_CURL := 0.75
var trigger_pull := 0.0
var _trigger_tween: Tween
var _standing_shoulder := Vector3.ZERO
var _standing_shoulder_known := false
## The low-ready grip before any body offset (carry grip plus the walking sway), refreshed each frame.
var _ready_grip_base := Vector3.ZERO
var weapon_attachment: BoneAttachment3D
var weapon: Node3D
var support_hand_target: Node3D
var muzzle_socket: Node3D
var muzzle_flash: MeshInstance3D
var ik_enabled := true
@onready var animation_controller: Node = get_node_or_null("VerticalSliceController")
var _shot_feedback_generation := 0
var aim_blend := 0.0
## The aimed weapon's orientation as an offset from the character root, in the root's frame: identity while the torso
## is settled, the chest's turn since it settled while it kicks. Written in the WeaponPose pass (update_torso_frame).
var torso_frame := Basis.IDENTITY
var _torso_reference := Basis.IDENTITY
var _torso_reference_known := false
var _torso_offset := Quaternion.IDENTITY
## Animation states in which the chest kicks and the weapon should turn with it: a shot. Hit reactions are left out on
## purpose: their chest swing is up to ~40 degrees, which would whip the weapon without improving hand contact (measured in
## tests/unit_visual_torso_weapon_frame_test.gd); they keep the root-frame weapon until hit reactions are designed.
const TORSO_KICK_STATES: Array[StringName] = [&"shoot", &"shoot_left", &"shoot_right"]
## After a kick the weapon's offset eases back to the settled frame over about this long, so nothing snaps.
const TORSO_FRAME_RELEASE_SECONDS := 0.06
## Requests for weapon readiness by source (see WeaponReadiness). aim_blend follows the highest.
var readiness := WeaponReadiness.new()
var recoil := 0.0
var _pose_tween: Tween
var _recoil_tween: Tween
@export_group("Animation Clips")
## Edit this shared library through animations/animation_workbench.tscn. Missing clips use generated defaults.
## Optional authored clips. When empty, the controller builds the tested prototype fallbacks.
@export var clip_library: AnimationLibrary
@export_group("Weapon Contact")
## Where the weapon is held: scale, stock, grips and hand posture. See WeaponHandlingProfile.
@export var handling: WeaponHandlingProfile = WeaponHandlingProfile.new()
## Right-upper-arm-local metres: where the butt plate rests relative to the shoulder joint. A little
## in front of the joint, so the stock sits in the pocket instead of passing through the shoulder.
@export var shoulder_contact_offset := Vector3(0.035, 0.015, 0.02)
## Derived from `handling` and the hand size (see _place_hands_on_weapon): the weapon origin relative
## to the firing wrist, the stock point and the support wrist, all in character metres.
var grip_offset := Vector3.ZERO
var stock_contact_offset := Vector3.ZERO
var support_wrist := Vector3.ZERO
var stock_marker: Marker3D
var shoulder_marker: Marker3D
var sight_marker: Marker3D
var support_ik_target: Marker3D
@export_group("Arm IK")
## Elbow guide positions in Character-local metres.
@export var right_elbow_ready := Vector3(-0.26, 0.93, -0.04)
@export var right_elbow_aim := Vector3(-0.42, 1.18, -0.08)
@export var left_elbow_ready := Vector3(0.27, 0.94, 0.10)
@export var left_elbow_aim := Vector3(0.38, 1.03, 0.08)
@export_group("Weapon Pose")
## The support arm's live limits, shared by reference with WeaponPoseModifier (see WeaponPoseSettings). The properties below read and write this one object.
var weapon_pose_settings := WeaponPoseSettings.new()
## Most the support shoulder may be protracted in total (base reach plus what a target needs), degrees. The base is
## SUPPORT_REACH_DEGREES. Conservative: about half of the sternoclavicular joint's ~35 degree protraction-retraction
## range (StatPearls, Kenhub, GPnotebook). Set per character; see WeaponPoseModifier.
@export_range(0.0, 45.0, 0.5, "suffix:°") var support_protraction_limit_degrees: float = 18.0:
	get: return weapon_pose_settings.protraction_limit_degrees
	set(value): weapon_pose_settings.protraction_limit_degrees = value
## Elbow bend (interior angle, degrees) the support arm is eased toward when its target is nearly out of reach.
## 180 is a locked elbow.
@export_range(120.0, 180.0, 1.0, "suffix:°") var support_elbow_comfort_degrees: float = 165.0:
	get: return weapon_pose_settings.elbow_comfort_degrees
	set(value): weapon_pose_settings.elbow_comfort_degrees = value
@export_range(2, 16, 1) var support_solve_iterations: int = 8:
	get: return weapon_pose_settings.solve_iterations
	set(value): weapon_pose_settings.solve_iterations = value
## Torso-relative weapon frame. While the chest kicks (a shot) the aimed weapon turns with the chest, about the
## stock, instead of keeping the character root's orientation: the weapon and both shoulders then move as one body and
## the support hand keeps its grip. Off restores the root-frame weapon (used for before/after comparisons).
@export var torso_frame_enabled := true
## Bone whose orientation defines the torso (the chest), and the bone the carried passenger is measured from (the base of the neck): read-only views of `bones`.
var torso_bone_name: StringName:
	get: return bones.torso if bones != null else &""
var neck_bone_name: StringName:
	get: return bones.neck if bones != null else &""
var _stow_anchor: ChestAnchor
var _carry_lean := 0.0
## Swivel-preserving elbow guidance (animation improvement 05B). While aiming, each elbow pole is built every pass from
## the shoulder, the wrist target and the chest's "down", keeping the bend-plane swivel the elbow has in the standing aim
## (the `right_elbow_aim` / `left_elbow_aim` guides). The guides themselves are fixed in standing character space, which
## is what lifted and flared the elbows when the body dropped. Off restores the fixed guides (before/after comparisons).
@export var elbow_guidance_enabled := true
## How far from the arm's midpoint the guidance places a pole. Only the direction matters to the solver.
const ELBOW_POLE_DISTANCE := 0.35
## Below this length (of the chest-down component perpendicular to the arm axis) the reference direction is unstable
## (arm axis nearly vertical) and the guide pole is kept for that arm.
const ELBOW_REFERENCE_MIN := 0.2
var _elbow_swivel: Array[float] = [0.0, 0.0]
var _elbow_swivel_latched := false
var _pole_ready: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _pole_body_offset := Vector3.ZERO
@export_group("Cover")
## How the body behaves behind cover (facing offsets, crouch, edge selection). See CoverPostureProfile. Used by the game's adapter and by the workbench.
@export var cover_profile: CoverPostureProfile = CoverPostureProfile.new()
@export_group("Locomotion")
## Gaits, speed thresholds, cadence, turning and start/stop behaviour for this character. See LocomotionProfile.
@export var locomotion_profile: LocomotionProfile = LocomotionProfile.new()
## Direction of travel in the character's own frame (x toward its left, y forward). Tactical movement is always forward; the workbench sets the others.
var locomotion_direction := Vector2(0.0, 1.0)
## What the presentation is currently doing, for tests and the workbench: the speed the legs follow, the gait blend values, the cadence.
var locomotion_report := {"speed": 0.0, "gait": 0.0, "loaded": 0.0, "cadence": 0.0, "accel": 0.0, "bank": 0.0}
var _visual_speed := 0.0
var _gait_blend := 0.0
var _loaded_blend := 0.0
var _speed_accel := 0.0
var _bank_target := 0.0
var _heading_rate := 0.0
var _locomotion_fed_frame := -1
var locomotion_modifier: LocomotionPoseModifier
var _twist := 0.0
var _twist_start := 0.0
@export_group("Rescue Carry")
## Positions are in Character-local metres; stowed angles are degrees. `passenger_anchor_from_neck` is where the
## carried passenger's abdomen rests, measured from the neck bone in the carrier's rest pose, in character space
@export var passenger_anchor_from_neck := Vector3(0.12, -0.03, -0.10)
## Turn of the passenger's body about the vertical, degrees: 0 lays it exactly across the shoulders (head to the carrier's
## right, legs to its left); negative swings the head end back and the legs forward.
@export var passenger_yaw_degrees := -8.0
## Overrides for PassivePassengerPose.DEFAULTS (spine fold, leg angles, the arms). Empty uses the defaults.
@export var passenger_pose_overrides := {}
## Carry contacts: while carrying, the wrists are placed on the passenger's body (CARRY_CONTACTS) by the WeaponPose modifier,
## through the same arm IK and elbow guidance the weapon uses. Off keeps the fixed carry clip's arms (the arm IK stays off).
@export var carry_contacts_enabled := true
## Elbow bend-plane swivel while carrying, degrees (right arm, left arm), measured as in apply_elbow_guidance: the elbow hangs
## below the shoulder-wrist line and out to the side. These are the carrying posture's own values (the weapon aim latches its own).
@export var carry_elbow_swivel_degrees := Vector2(-60.0, 60.0)
## The pickup/release timeline and the carrier's and passenger's key values for it (see RescueInteraction).
@export var rescue_interaction: RescueInteraction = RescueInteraction.new()
@export_subgroup("Passenger secondary motion")
## Off gives the rigid carry. Amplitude (m), tilt (degrees), response time (s) and swing (degrees) are the limits of the
## restrained body lag (RescuePassenger._update_motion); all are filters of the carrier's own chest motion.
@export var passenger_motion_enabled := true
@export_range(0.0, 0.05, 0.001, "suffix:m") var passenger_motion_amplitude := 0.02
@export_range(0.0, 5.0, 0.1, "suffix:°") var passenger_motion_tilt_degrees := 1.5
@export_range(0.0, 0.5, 0.01, "suffix:s") var passenger_motion_response := 0.12
@export_range(0.0, 10.0, 0.1, "suffix:°") var passenger_motion_swing_degrees := 4.0
@export_subgroup("")
## Leave the passenger lying where a release set it down (workbench), instead of freeing it when the release ends.
var keep_released_passenger := false
## The presentation handle of the rescue operation in progress (a pickup or a release), or null. It describes the VISUAL operation only: it settles COMPLETED when the timeline runs out, SKIPPED when it is
## run to its end at once, INTERRUPTED when something ends the carry under it (the carrier falls, is defeated or is freed) and CANCELLED when the requester withdraws it. The gameplay outcome of a rescue is
## decided elsewhere and never depends on it.
var _rescue_handle: ActionHandle
## The posture source a rescue lift requests under (an ACTION-priority request: it wins over the cover policy for its duration and the cover request is untouched underneath).
const RESCUE_POSTURE_SOURCE := &"presentation/rescue"
var _interaction_sample := {}
var _reach_hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _reach_poles: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _reach_curl := 0.0
var _carry_reach := 1.0
var _step_vector := Vector3.ZERO
## The carrier's own place (this node's position) before a pickup or release; the step toward the passenger is made from it
## and undone to it. The step moves THIS node, not the character root, because the animation controller tweens the root's
## position back to zero at every state change.
var _root_rest_position := Vector3.ZERO
var _weapon_hand_local := Transform3D.IDENTITY
var _stow_blend := 1.0
## Which carrier hand holds which passenger contact: [hand, contact]. The right hand takes the wrist and the left the
## thigh: the passenger's torso, head and arms hang behind the carrier's right shoulder and its legs at the left.
## The optional third value is the direction (carrier frame) the hand comes from; without it the hand comes from its shoulder's side.
## The thigh is taken from the front so the hand is not sandwiched between the passenger's leg and the carrier's own hip.
const CARRY_CONTACTS := [[&"right", &"wrist"], [&"left", &"thigh", Vector3(0.4, 0.0, 1.0)]]
## Fingers' grip tightness on the contacts (0 open, 1 fist).
const CARRY_GRIP_CURL := 0.75
const RESCUE_PASSENGER := preload("res://presentation/characters/rig/rescue_passenger.gd")
## The carried passenger while carrying, else null. Created by begin_carry, freed by end_carry.
var carry_passenger: Node3D
## What the contacts asked of each hand in the last pass: [dominant (right), support (left)] dictionaries with the passenger's
## contact point, the intended palm centre and the intended finger and palm directions (world). Read by diagnostics.
var carry_contact_report: Array = []
@export_group("")
var carry_motion_blend := 0.0
var _carry_phase := 0.0
var _pose_delta := 0.0
var _pose_delta_frame := -1
var _passenger_delta_frame := -1

## How shouldered the rifle is. The rifle stays in its relaxed carry, in cover or not, and comes up
## only to aim or shoot. While crouched the carry simply travels with the chest (see body_offset).
func weapon_blend() -> float:
	return aim_blend


func _rifle_local_basis() -> Basis:
	var carry_rotation := Quaternion.from_euler(handling.lowered_angles_degrees * (PI / 180.0))
	return Basis(carry_rotation.slerp(torso_frame.get_rotation_quaternion(), weapon_blend()))


## Builds the character: the model, the weapon (if any), the arm IK and the animation controller. A host (the tactical adapter, the workbench, a tool) adds this node and drives it: the presenter's tick
## and `update_weapon_pose` once per frame. The rig has no frame callback of its own, so a character is advanced exactly once per frame by whoever hosts it.
## Tuning for this character, in a `tuning/` folder beside its rig profile (art/characters/<id>/tuning/). A `<property>.tres` there replaces the profile the scene gives and `clips.tres` adds hand-edited
## clips: that is what the GAME uses (written only by the Workbench's explicit "Apply to game"). `tuning/drafts/` holds the Workbench's experiments; only a host that sets `use_drafts` (the Workbench) reads
## them, so an experiment never changes the game. No folder, no change. Never read in the editor (the scene file is not rewritten).
const TUNED_PROFILES: Array[StringName] = [&"cover_profile", &"locomotion_profile", &"traversal_profile", &"stair_profile", &"handling"]
const DRAFTS := "drafts"
## Tests point this at a scratch folder so they never read or write the character's real tuning.
static var tuning_folder_override := ""
## Set by the Workbench before it builds its rig: read the drafts over the game's tuning. The game never sets it.
static var use_drafts := false
## The stair profile as authored or tuned, before `_measure_stair_anatomy` copies it and fills in this body's measurements (the Tune tab edits this one).
var stair_profile_source: StairProfile
## What the GAME would use, per tuned property: a copy taken before any draft was applied (the Tune tab compares against it and "Apply to game" writes over it).
var tuning_game := {}
## Where "Apply to game" writes each property: the tuning file, or the profile's own .tres when the scene already gives one and there is no tuning file.
var tuning_game_file := {}

## The folder this rig's tuning lives in ("" when the rig has no rig profile file to place it beside).
func tuning_folder() -> String:
	if tuning_folder_override != "":
		return tuning_folder_override
	if rig_profile == null or rig_profile.resource_path == "" or rig_profile.resource_path.contains("::"):
		return ""
	return rig_profile.resource_path.get_base_dir().path_join("tuning")

func _load_tuning() -> void:
	var folder := tuning_folder()
	if folder == "":
		return
	for property in TUNED_PROFILES:
		var current: Resource = get(property)
		var own := current.resource_path if current != null and current.resource_path.ends_with(".tres") and not current.resource_path.contains("::") else ""
		var game_file := folder.path_join("%s.tres" % property)
		if _take(property, game_file):
			tuning_game_file[property] = game_file
		else:
			tuning_game_file[property] = own if own != "" else game_file
		if get(property) != null:
			tuning_game[property] = (get(property) as Resource).duplicate(true)
		if use_drafts:
			_take(property, folder.path_join(DRAFTS).path_join("%s.tres" % property))
	# Hand-edited clips (the Workbench's "Edit this clip in Godot"): a saved clip replaces the generated one of the same name (CharacterAnimationController checks each one).
	for clips in ([folder.path_join(DRAFTS).path_join("clips.tres")] if use_drafts else []) + [folder.path_join("clips.tres")]:
		if ResourceLoader.exists(clips):
			var library := ResourceLoader.load(clips, "", ResourceLoader.CACHE_MODE_IGNORE)
			if library is AnimationLibrary:
				clip_library = library
				break

## Replaces `property` with the profile in `path` when it exists and is of the same kind (a file of the wrong kind is ignored, never half-applied). Each rig gets its own copy.
func _take(property: StringName, path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var tuned := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var current: Resource = get(property)
	if tuned is Resource and (current == null or tuned.get_script() == current.get_script()):
		set(property, tuned)
		return true
	return false

## Puts the authored stair numbers back and measures this body again (after the Tune tab changed `stair_profile_source`).
func reapply_stair_profile() -> void:
	if stair_profile_source != null:
		stair_profile = stair_profile_source
		_measure_stair_anatomy()

func _ready() -> void:
	if not Engine.is_editor_hint():
		_load_tuning()
	_build_character()
	_build_weapon_attachment()
	_build_arm_ik()
	_measure_stair_anatomy()
	if Engine.is_editor_hint():
		await get_tree().process_frame
		await get_tree().process_frame
		_align_weapon_to_aim()
		update_weapon_pose()
		return
	_build_animation_controller()
	skeleton.skeleton_updated.connect(_align_weapon_to_aim)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_align_weapon_to_aim()


## The stair planner's anatomy, measured from THIS rig's skeleton in its rest pose through the typed bone roles (no bone names, no assumed proportions): the leg's straight length (thigh plus shin), how high
## the ankle sits above the sole, where the hip joint is relative to the pelvis origin, and the foot's extent (from the ankle-to-ball distance). The profile is copied first so a shared resource is not
## changed. A role the skeleton lacks keeps the profile's value.
func _measure_stair_anatomy() -> void:
	if stair_profile == null or not is_instance_valid(skeleton):
		return
	if stair_profile_source == null:
		stair_profile_source = stair_profile
	stair_profile = stair_profile.duplicate() as StairProfile
	# The profile's lengths in metres (stance roll, heel lift, swing lift, margins, step rise, stance width, standing pelvis height) are authored for the reference body (RigBones.REFERENCE_HIP_TO_ANKLE);
	# a body with a different leg takes its share. The anatomy below is measured, never scaled.
	var ratio := body_ratio()
	if absf(ratio - 1.0) > 0.0005:
		for property in [&"tread_margin", &"max_step_rise", &"swing_lift", &"ankle_setback", &"foot_half_spread", &"stance_roll", &"heel_lift", &"placement_variation", &"pelvis_sway", &"pelvis_standing_height"]:
			stair_profile.set(property, float(stair_profile.get(property)) * ratio)
	var frame := character_root.global_transform.affine_inverse() * skeleton.global_transform
	var rest := func(bone_name: StringName) -> Vector3:
		var index := skeleton.find_bone(bone_name)
		return (frame * skeleton.get_bone_global_rest(index).origin) if index >= 0 else Vector3(NAN, NAN, NAN)
	var hips: Vector3 = rest.call(bones.hips)
	var joint: Vector3 = rest.call(bones.left_leg[0])
	var knee: Vector3 = rest.call(bones.left_leg[1])
	var ankle: Vector3 = rest.call(bones.left_leg[2])
	if is_nan(hips.x) or is_nan(joint.x) or is_nan(knee.x) or is_nan(ankle.x):
		return
	stair_profile.leg_length = joint.distance_to(knee) + knee.distance_to(ankle)
	stair_profile.ankle_height = ankle.y
	stair_profile.hip_joint_offset = Vector3(absf(joint.x - hips.x), hips.y - joint.y, joint.z - hips.z)
	var toe: Vector3 = rest.call(bones.left_toes) if bones.left_toes != &"" else Vector3(NAN, NAN, NAN)
	if not is_nan(toe.x):
		var ball := Vector2(toe.x - ankle.x, toe.z - ankle.z).length()
		if ball > 0.02:
			stair_profile.foot_front = ball * 1.6
			stair_profile.foot_back = ball * 0.55
			stair_profile.foot_half_width = ball * 0.4


func _build_character() -> void:
	assert(character_scene != null, "Character scene is required")
	var model := character_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * character_scale
	character_root.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null, "Character model must contain Skeleton3D")
	assert(rig_profile != null, "A character needs a rig profile: it names the skeleton's bones (see RigBones)")
	_resolve_rig_profile()
	bones = RigBones.from_profile(rig_profile, skeleton)
	assert(not right_arm_bones.has(&"") and not left_arm_bones.has(&""), "The rig profile must map both arms (upper arm, lower arm, hand) to bones of this skeleton")


## The profile resolved against this character's skeleton (a RigResolver.Resolved), or null without a profile. Read-only information: roles, measurements, capabilities, diagnostics.
var resolved_rig: RefCounted

func _resolve_rig_profile() -> void:
	resolved_rig = null
	if rig_profile != null:
		resolved_rig = RigResolver.resolve(rig_profile, skeleton)


## Whether this character carries a weapon at all. Every weapon-specific pose, readiness and IK assumption is conditional on it.
func has_weapon() -> bool:
	return is_instance_valid(weapon)


## What the body physically holds: NONE (no weapon), HELD (in the hands) or SLUNG (carried, not held). It is what is true, not an inference from the weapon pose.
func equipment_state() -> PresentationTypes.EquipmentState:
	if not has_weapon():
		return PresentationTypes.EquipmentState.NONE
	return PresentationTypes.EquipmentState.SLUNG if is_weapon_stowed() else PresentationTypes.EquipmentState.HELD


func _build_weapon_attachment() -> void:
	if weapon_scene == null:
		return   # unarmed: no weapon, no socket, no markers and no muzzle flash. The arms hang relaxed (apply_relaxed_hand_targets) and nothing here assumes a rifle.
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "RightHandWeaponSocket"
	weapon_attachment.bone_name = right_arm_bones[2]
	skeleton.add_child(weapon_attachment)

	weapon = weapon_scene.instantiate() as Node3D
	weapon.name = "AUG"
	weapon.scale = Vector3.ONE * handling.scale
	_place_hands_on_weapon()
	# The source WeaponOrigin is centered on the firing-hand grip. This small
	# offset nests it into the palm while its +Z axis remains the firing axis.
	weapon.position = grip_offset
	weapon_attachment.add_child(weapon)
	support_hand_target = weapon.find_child("SupportHandTarget", true, false) as Node3D
	assert(support_hand_target != null, "AUG must expose SupportHandTarget")
	muzzle_socket = weapon.find_child("MuzzleSocket", true, false) as Node3D
	assert(muzzle_socket != null, "AUG must expose MuzzleSocket")
	sight_marker = Marker3D.new()
	sight_marker.name = "SightReference"
	sight_marker.position = handling.sight
	weapon.add_child(sight_marker)
	stock_marker = Marker3D.new()
	stock_marker.name = "ButtstockContact"
	stock_marker.position = handling.stock_rear
	weapon.add_child(stock_marker)
	shoulder_marker = Marker3D.new()
	shoulder_marker.name = "ShoulderContact"
	character_root.add_child(shoulder_marker)
	_build_muzzle_flash()


func _build_muzzle_flash() -> void:
	muzzle_flash = MeshInstance3D.new()
	muzzle_flash.name = "MuzzleFlash"
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.035
	flash_mesh.height = 0.15
	muzzle_flash.mesh = flash_mesh
	muzzle_flash.scale = Vector3(0.7, 0.7, 2.0)
	muzzle_flash.position = Vector3(0.0, 0.0, 0.055)
	var flash_material := StandardMaterial3D.new()
	flash_material.albedo_color = Color(1.0, 0.62, 0.12)
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.24, 0.025)
	flash_material.emission_energy_multiplier = 5.0
	muzzle_flash.material_override = flash_material
	muzzle_flash.visible = false
	muzzle_socket.add_child(muzzle_flash)


func _build_arm_ik() -> void:
	arm_ik = TwoBoneIK3D.new()
	arm_ik.name = "WeaponArmIK"
	arm_ik.setting_count = 2
	skeleton.add_child(arm_ik)

	support_ik_target = Marker3D.new()
	support_ik_target.name = "SupportIKTarget"
	character_root.add_child(support_ik_target)
	_configure_chain(0, right_arm_bones, right_hand_target, right_elbow_pole)
	_configure_chain(1, left_arm_bones, support_ik_target, left_elbow_pole)
	arm_ik.active = true


func _build_animation_controller() -> void:
	# Runtime and demo scenes expose this stable component in the editor. Keep a
	# fallback for older external scenes that extend CharacterRig directly.
	if not is_instance_valid(animation_controller):
		animation_controller = ANIMATION_CONTROLLER_FALLBACK.new()
		animation_controller.name = "VerticalSliceController"
		add_child(animation_controller)
	animation_controller.clip_library = clip_library
	animation_controller.locomotion_profile = locomotion_profile
	animation_controller.state_changed.connect(_on_animation_state_changed)
	animation_controller.setup(skeleton, character_root, bones)
	_build_crouch_modifier()
	_build_traversal_modifier()
	_build_weapon_pose_modifier()
	_build_grip_modifier()
	_build_locomotion_modifier()


## Procedural crouch layer: runs after the animation and before the arm IK, so the arms and
## the weapon follow the lowered body.
func _build_grip_modifier() -> void:
	grip_modifier = HandGripModifier.new()
	grip_modifier.name = "HandGrip"
	if not grip_modifier.setup(skeleton, bones):
		grip_modifier.free()
		grip_modifier = null
		bones.degrade("HandGrip", bones.missing_of([&"LeftHand", &"RightHand", &"LeftMiddleProximal", &"RightMiddleProximal"]))
		return
	skeleton.add_child(grip_modifier)
	if not grip_modifier.missing_digits.is_empty():
		bones.degraded.append("HandGrip keeps wrist alignment (missing digit chains: %s)" % ", ".join(grip_modifier.missing_digits))
	if has_weapon():
		_place_hands_on_weapon()


## Derives the weapon placement from the handling profile and the real hand size: the palm centre
## lies half a palm length ahead of the wrist along the hand's forward direction, so each wrist is
## put that far behind its grip.
func _place_hands_on_weapon() -> void:
	var scale_value := handling.scale
	var hand_forward := handling.hand_forward()
	var firing_wrist := handling.firing_palm() * scale_value - hand_forward * _half_palm_length(HandContact.Hand.RIGHT)
	grip_offset = -firing_wrist
	# Existing weapon profiles were calibrated against the firing hand's
	# reference length for both offsets. Keep that fit until the support
	# geometry is calibrated per hand. Surface contacts use the actual hand.
	support_wrist = handling.support_palm() * scale_value - hand_forward * _half_palm_length(HandContact.Hand.RIGHT)
	stock_contact_offset = handling.stock_rear * scale_value
	if grip_modifier != null:
		grip_modifier.hand_forward = handling.hand_forward()


func _half_palm_length(hand: HandContact.Hand) -> float:
	return float(grip_modifier.palm_lengths[int(hand)]) * 0.5 if grip_modifier != null else 0.045


## Runs after the crouch layer and before the arm IK, so the targets are placed from the final procedural shoulder.
## The rig's side of the PoseTargetPlacer contract: the weapon-pose modifier asks, the rig places its own targets with its own formulas. KEPT in Task 07 package 9 as the typed boundary for same-pass skeletal
## operations: it is not about weapons (place_weapon_targets places the rifle's hands for an armed character and the relaxed hanging hands for an unarmed one, decided inside the rig), and removing it would put
## the rig back inside the modifier. The modifier decides WHEN; every formula stays here.
class RigPoseTargets extends PoseTargetPlacer:
	var _rig: CharacterRig
	func _init(owner_rig: CharacterRig) -> void:
		_rig = owner_rig
	func carrying() -> bool:
		return _rig.carry_contacts_active()
	func holding_traversal() -> bool:
		return _rig.traversal_contacts_active()
	func place_carry_targets(right_shoulder: Vector3, left_shoulder: Vector3) -> void:
		_rig.apply_carry_targets([right_shoulder, left_shoulder], _rig.carry_passenger.anchor_world())
	func observe_torso_frame(chest_in_root: Basis, delta: float) -> void:
		_rig.update_torso_frame(chest_in_root, delta)
	func place_weapon_targets(right_shoulder: Vector3) -> void:
		_rig.apply_weapon_targets(right_shoulder)
	func place_traversal_hand_targets() -> void:
		_rig.apply_traversal_hand_targets()
	func guide_elbows(right_shoulder: Vector3, left_shoulder: Vector3, chest_world: Basis, carrying_now: bool) -> void:
		_rig.apply_elbow_guidance([right_shoulder, left_shoulder], chest_world, carrying_now)


func _build_weapon_pose_modifier() -> void:
	var modifier := WeaponPoseModifier.new()
	modifier.name = "WeaponPose"
	var binding := WeaponPoseBinding.new()
	binding.skeleton = skeleton
	binding.right_shoulder_bone = bones.right_arm[0]
	binding.left_arm_bones.assign(bones.left_arm)
	binding.chest_bone = bones.torso
	binding.character_root = character_root
	binding.arm_ik = arm_ik
	binding.support_target = support_ik_target
	binding.crouch = crouch_modifier
	binding.settings = weapon_pose_settings
	binding.placer = RigPoseTargets.new(self)
	if not modifier.setup(binding):
		return
	skeleton.add_child(modifier)
	if is_instance_valid(arm_ik):
		skeleton.move_child(modifier, arm_ik.get_index())
	weapon_pose_modifier = modifier
	weapon_pose_modifier.active = weapon_pose_modifier_enabled


## The situational body adjustments (turn twist, lean into turns, start/stop pitch). First in the modifier order: see LocomotionPoseModifier.
func _build_locomotion_modifier() -> void:
	locomotion_modifier = LocomotionPoseModifier.new()
	locomotion_modifier.name = "Locomotion"
	if not locomotion_modifier.setup(skeleton, bones, animation_controller.locomotion_axes()):
		locomotion_modifier = null
		bones.degrade("Locomotion", bones.missing_of([&"Hips", &"Spine", &"LeftUpperLeg", &"RightUpperLeg"]))
		return
	skeleton.add_child(locomotion_modifier)
	for child in skeleton.get_children():
		if child is SkeletonModifier3D and child != locomotion_modifier:
			skeleton.move_child(locomotion_modifier, child.get_index())
			break


func _build_crouch_modifier() -> void:
	crouch_modifier = CoverCrouchModifier.new()
	crouch_modifier.name = "CoverCrouch"
	if not crouch_modifier.setup(skeleton, bones, character_root.global_basis.z):
		crouch_modifier = null
		bones.degrade("CoverCrouch", bones.missing_of([&"Hips", &"Spine", &"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]))
		return
	skeleton.add_child(crouch_modifier)
	if is_instance_valid(arm_ik):
		skeleton.move_child(crouch_modifier, arm_ik.get_index())


## The body layer for ladders and obstacles: a pelvis/trunk pose and a two-bone leg IK, after Locomotion and CoverCrouch and before WeaponPose (see TraversalPoseModifier).
func _build_traversal_modifier() -> void:
	var legs := [bones.left_leg, bones.right_leg]
	traversal_modifier = TraversalPoseModifier.new()
	traversal_modifier.name = "Traversal"
	if not traversal_modifier.setup(skeleton, bones.hips, character_root):
		traversal_modifier = null
		bones.degrade("Traversal", bones.missing_of([&"Hips"]))
		return
	leg_ik = TwoBoneIK3D.new()
	leg_ik.name = "TraversalLegIK"
	leg_ik.setting_count = 2
	skeleton.add_child(traversal_modifier)
	skeleton.add_child(leg_ik)
	for side in 2:
		var foot := Marker3D.new()
		foot.name = "TraversalFootTarget%d" % side
		character_root.add_child(foot)
		var knee := Marker3D.new()
		knee.name = "TraversalKneePole%d" % side
		character_root.add_child(knee)
		foot_targets.append(foot)
		knee_poles.append(knee)
		leg_ik.set_root_bone_name(side, legs[side][0])
		leg_ik.set_middle_bone_name(side, legs[side][1])
		leg_ik.set_end_bone_name(side, legs[side][2])
		leg_ik.set_target_node(side, leg_ik.get_path_to(foot))
		leg_ik.set_pole_node(side, leg_ik.get_path_to(knee))
	leg_ik.active = false
	traversal_modifier.bind_legs(leg_ik, foot_targets, knee_poles)
	# The feet's orientation, right after the leg IK (which places the ankles but not the feet's rotation).
	foot_modifier = TraversalFootModifier.new()
	foot_modifier.name = "TraversalFoot"
	var foot_bones: Array[StringName] = [bones.left_leg[2], bones.right_leg[2]]
	var ball := 0.113
	if bones.left_toes != &"" and skeleton.find_bone(bones.left_toes) >= 0:
		var ankle_rest := skeleton.get_bone_global_rest(skeleton.find_bone(bones.left_leg[2])).origin
		var toe_rest := skeleton.get_bone_global_rest(skeleton.find_bone(bones.left_toes)).origin
		ball = Vector2(toe_rest.x - ankle_rest.x, toe_rest.z - ankle_rest.z).length() * skeleton.global_basis.get_scale().y
	if foot_modifier.setup(skeleton, foot_bones, character_root, ball):
		foot_modifier.input = traversal_modifier.input
		skeleton.add_child(foot_modifier)
	else:
		foot_modifier = null
		bones.degrade("TraversalFoot", [])
	# Just before the arm IK, after whatever was built before (Locomotion, CoverCrouch).
	if is_instance_valid(arm_ik):
		skeleton.move_child(traversal_modifier, arm_ik.get_index())
		skeleton.move_child(leg_ik, arm_ik.get_index())
		if foot_modifier != null:
			skeleton.move_child(foot_modifier, arm_ik.get_index())


## Translates the traversal and stair state into the typed pose the Traversal modifier applies (TraversalPoseInput). Called wherever that state changes, so the modifier always has the current pose and
## reads nothing of the rig. A ladder takes precedence over stairs, exactly as before. `ladder` and `stairs` are the rig's own typed state (read by tests and tools).
func _publish_traversal_input() -> void:
	if traversal_modifier == null:
		return
	var input := traversal_modifier.input
	if ladder != null:
		input.mode = TraversalPoseInput.Mode.LADDER
		input.solved = ladder.pose != null
		if input.solved:
			input.weight = ladder.pose.weight
			input.hips_local = ladder.pose.hips
			input.feet_local = [ladder.pose.feet[0], ladder.pose.feet[1]]
			input.ladder_geometry = ladder.geometry
			input.ladder_body = ladder.body
			input.floor_level = ladder.climbed
			input.landing = ladder.landing
			input.deck_planted = [ladder.landing != null and ladder.pose.foot_rung[0] < 0, ladder.landing != null and ladder.pose.foot_rung[1] < 0]
			# A foot planted on a rung is turned flat to it (the sole on the bar), as it is on a tread or the deck; a swinging foot is levelled less. Without this the foot keeps the pitch the shin gives it
			# and its sole sinks into the rung (measured on the mesh, up to 17 mm).
			var levelled: Array[float] = []
			for side_index in 2:
				levelled.append(maxf(ladder.pose.foot_deck[side_index], 1.0 - ladder.pose.foot_swing[side_index]))
			input.deck_levelling = levelled
	elif stairs != null and stairs.pose != null:
		input.mode = TraversalPoseInput.Mode.STAIRS
		input.solved = true
		input.weight = stairs.pose.weight
		input.pelvis_height = stairs.pose.pelvis_height
		input.pelvis_offset = stairs.pose.pelvis_offset
		input.smooth_floor = stairs.pose.smooth_floor
		input.ankles_world = [stairs.pose.feet[0].position, stairs.pose.feet[1].position]
		input.planted = [stairs.pose.feet[0].planted, stairs.pose.feet[1].planted]
		input.foot_lift = [maxf(stairs.pose.feet[0].position.y - stairs.pose.feet[0].tread_top - stair_profile.ankle_height, 0.0), maxf(stairs.pose.feet[1].position.y - stairs.pose.feet[1].tread_top - stair_profile.ankle_height, 0.0)]
		input.stair_profile = stair_profile
	else:
		input.clear()


## Starts a ladder traversal (kind &"ladder"): `length` is the ladder's rise, `direction` +1 climbing / -1 descending. The pose follows set_traversal_progress.
## `landing` is the supported landing the HOST verified at the top (see LadderLanding); null keeps the ordinary height-only climb-out. A landing this body cannot use (the deck too far, too small, or
## nothing to hold) is refused here with the reason in `ladder.landing_status`, never half-used.
func begin_traversal(kind: StringName, length: float, direction: int, landing: LadderLanding = null) -> void:
	ladder = LadderClimb.new(kind, length, direction)
	ladder.body = ladder_body()
	if landing != null:
		var reason := landing.unsupported_reason(ladder.geometry, ladder.body)
		if reason.is_empty():
			ladder.landing = landing
			ladder.landing_status = "supported (%s)" % landing.source
		else:
			ladder.landing_status = "fallback: %s" % reason
	_publish_traversal_input()


## The height of the character's floor level above the ladder's bottom floor. Solves the pose now (pure function of this height), asks the trunk to lean, and sets
## how far the rifle is slung (the weapon travels to the sling as the climber mounts and back as they leave; the pose is released again at the ends).
func set_traversal_progress(climbed: float, rung_plane := NAN, across_deck := 0.0) -> void:
	if ladder == null:
		return
	if not is_nan(rung_plane):
		ladder.geometry.plane_ahead = rung_plane
	ladder.climbed = climbed
	var result: Dictionary
	if ladder.landing != null and climbed >= TraversalSolver.landing_start(ladder.geometry, ladder.body):
		result = TraversalSolver.ladder_landing_pose(traversal_profile, ladder.geometry, ladder.body, climbed, ladder.direction, ladder.landing, across_deck)
	else:
		result = TraversalSolver.ladder_pose(traversal_profile, ladder.geometry, ladder.body, climbed, ladder.direction)
	ladder.pose = LadderPose.from_solver(result)
	_publish_traversal_input()
	var weight: float = ladder.pose.weight
	if crouch_modifier != null:
		crouch_modifier.aim_lean_degrees = ladder.pose.lean_degrees * weight
	if weight > 0.001:
		if not is_weapon_stowed():
			stow_weapon()
		_stow_blend = weight
	elif is_weapon_stowed():
		unstow_weapon()
		_stow_blend = 1.0


## Starts stair walking on `model` (the unit walks it up or down). Not used while carrying a passenger (that keeps the existing loaded gait).
func begin_stairs(model: StairModel, ascending: bool, enter := 0.0, exit := -1.0) -> void:
	if model == null or not stair_profile.enabled or is_instance_valid(carry_passenger):
		return
	stairs = StairWalk.new(model, ascending, enter, exit if exit >= 0.0 else model.riser_s(model.count))
	_publish_traversal_input()


## The body's place along the stair (distance from the lower cell centre) and its speed: plans the feet and the pelvis now (a pure function of these two numbers).
func set_stair_progress(s: float, unit_speed: float, lateral_speed := 0.0, allow_crouch := false) -> void:
	if stairs == null:
		return
	var model := stairs.model
	var ascending := stairs.ascending
	var step := stair_profile.step_treads(unit_speed, false, model.tread_rise)
	if step != stairs.step:
		stairs.step = step
		stairs.holds = StairFootPlanner.holds(model, ascending, step)
	var holds: Array = stairs.holds
	var body_root := character_root.global_position
	var facing := character_root.global_basis.orthonormalized().z
	var feet: Array = []
	var lateral_blend := smoothstep(0.10, 0.40, absf(lateral_speed) - unit_speed * 0.6)
	for foot in 2:
		var contact := StairFootPlanner.contact_foot(model, stair_profile, holds, ascending, s, foot, body_root, facing, unit_speed)
		if lateral_blend > 0.0:
			var side_step := StairFootPlanner.side_step_foot(model, stair_profile, foot, body_root, facing)
			contact.position = (contact.position as Vector3).lerp(side_step.position, lateral_blend)
			contact.tread_top = lerpf(contact.tread_top, side_step.tread_top, lateral_blend)
			contact.planted = contact.planted and side_step.planted
		feet.append(contact)
	var shift := StairFootPlanner.sway_at(model, stair_profile, holds, ascending, s) * (1.0 - StairFootPlanner.settle_weight(stair_profile, unit_speed))
	var body := body_root + shift   # the legs are solved for the pelvis where it will actually be
	var solved := StairFootPlanner.pelvis_smoothed(model, stair_profile, holds, ascending, s, body, feet, facing)
	stairs.pose = StairPose.from_planner(feet, solved, StairFootPlanner.weight_at(s, stairs.enter_s, stairs.exit_s, model.tread_depth * 1.5), s, step, shift, StairFootPlanner.floor_reference(model, stair_profile, s))
	_publish_traversal_input()
	if traversal_modifier != null:
		traversal_modifier.input.stair_crouch = crouch_modifier.depth if allow_crouch and crouch_modifier != null else 0.0


func end_stairs() -> void:
	if stairs == null:
		return
	stairs = null
	_publish_traversal_input()
	if is_instance_valid(leg_ik) and ladder == null:
		leg_ik.active = false


## Ends the traversal and leaves nothing of it: the legs, lean, hands and rifle go back to the ordinary pose layers.
func end_traversal() -> void:
	if ladder == null:
		return
	ladder = null
	_publish_traversal_input()
	if crouch_modifier != null:
		crouch_modifier.aim_lean_degrees = 0.0
	if is_instance_valid(leg_ik):
		leg_ik.active = false
	release_hand_contacts()
	if is_weapon_stowed() and not carry_contacts_active():
		unstow_weapon()
	_stow_blend = 1.0


func traversal_contacts_active() -> bool:
	return ladder != null and ladder.pose != null and (ladder.pose.hand_weight[0] > 0.001 or ladder.pose.hand_weight[1] > 0.001)


## Puts the hands on the rungs (or the deck edge), by the traversal's weight, over wherever the weapon pose placed them. Runs inside the WeaponPose pass, after the weapon
## targets, so ladder contacts take priority over the rifle grip for as long as they hold (the rifle is slung, so nothing competes for the hands).
func apply_traversal_hand_targets() -> void:
	var up := Vector3.UP
	var toward := character_root.global_basis.orthonormalized().z
	for side in 2:   # the ladder's own order: 0 left, 1 right
		var hand := HandContact.Hand.LEFT if side == 0 else HandContact.Hand.RIGHT
		var node: Node3D = support_ik_target if side == 0 else right_hand_target
		var hold: float = ladder.pose.hand_weight[side]
		var deck := ladder.pose.hand_deck[side] if ladder.landing != null else 0.0
		var target := character_root.to_global(ladder.pose.hands[side])
		if deck > 0.0:
			# The final arm solver sees the posed shoulder, not the rest estimate.
			var arm := left_arm_bones if side == 0 else right_arm_bones
			var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(arm[0])).origin
			var arm_length := _arm_length(1 - side)
			hold *= 1.0 - smoothstep(arm_length * 0.98, arm_length * 1.09, target.distance_to(shoulder))
		var point := node.global_position.lerp(target, hold)
		var on_post := ladder.landing != null and ladder.landing.has_grips()
		var fingers := up.lerp(toward, deck).normalized()
		var post_side := character_root.global_basis.orthonormalized().x * (1.0 if side == 0 else -1.0)
		var palm_normal := toward.lerp(post_side if on_post else Vector3.DOWN, deck).normalized()
		claim_hand_contact(HandContact.make(hand, point, fingers, palm_normal, hold, lerpf(0.6, 0.65 if on_post else 0.1, deck) * hold))


## The ONE writer of a hand contact (HandContact): the wrist target goes to its point and the grip modifier takes its orientation, weight and closure, converted to skeleton space here and nowhere else. Every
## producer (a ladder's rungs, the carried body, the relaxed hang) plans in world space and claims through this; none of them touches the grip modifier's contact slots.
func claim_hand_contact(contact: HandContact) -> void:
	var node: Node3D = right_hand_target if contact.hand == HandContact.Hand.RIGHT else support_ik_target
	node.global_position = contact.point
	if grip_modifier == null:
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	var index := int(contact.hand)
	grip_modifier.orient_weight = 0.0
	grip_modifier.contact_weight[index] = contact.weight
	grip_modifier.contact_forward[index] = to_skeleton * contact.finger_direction
	grip_modifier.contact_normal[index] = to_skeleton * contact.palm_normal
	if contact.curl != HandContact.NO_CURL:
		grip_modifier.curl[index] = contact.curl


## Lets go of every hand contact. Run at the start of each pass that places the hands (a hand nobody claims this pass is the weapon's or the animation's again) and when a traversal or a carry ends, so a
## contact's weight can never outlive the producer that set it.
func release_hand_contacts() -> void:
	if grip_modifier != null:
		grip_modifier.contact_weight = [0.0, 0.0]


func _configure_chain(
	index: int,
	chain: Array,
	target: Node3D,
	pole: Node3D,
) -> void:
	arm_ik.set_root_bone_name(index, chain[0])
	arm_ik.set_middle_bone_name(index, chain[1])
	arm_ik.set_end_bone_name(index, chain[2])
	arm_ik.set_target_node(index, arm_ik.get_path_to(target))
	arm_ik.set_pole_node(index, arm_ik.get_path_to(pole))


func _align_weapon_to_aim() -> void:
	# Runtime animations will provide this aiming basis. For the static proof,
	# keep +Z as the muzzle direction and +Y as weapon-up while the attachment
	# continues to inherit the right wrist's position.
	if is_loaded():
		return   # a carrier's weapon is slung: the stow follows the body instead
	if not is_inside_tree() \
		or not is_instance_valid(character_root) or not character_root.is_inside_tree() \
		or not is_instance_valid(weapon_attachment) or not weapon_attachment.is_inside_tree() \
		or not is_instance_valid(weapon) or not weapon.is_inside_tree():
		return
	var desired_global_basis := character_root.global_basis * _rifle_local_basis()
	# The basis is rewritten every frame, so the presentation scale must be re-applied with it.
	weapon.basis = (weapon_attachment.global_basis.inverse() * desired_global_basis) * Basis.from_scale(Vector3.ONE * handling.scale)
	weapon.position = weapon_attachment.global_basis.inverse() * (desired_global_basis * grip_offset)


## Once per frame, after the presenter has advanced: the arms, hands and weapon for this frame (a loaded carrier's carry posture, else the weapon or relaxed-arm inputs).
func update_weapon_pose(delta := 0.0) -> void:
	if not is_instance_valid(skeleton):
		return
	_pose_delta = delta
	_pose_delta_frame = Engine.get_process_frames()
	if is_loaded():
		_apply_carry_posture(delta)
		return
	_carry_lean = 0.0
	_update_weapon_pose_inputs(delta)
	if weapon_pose_modifier_controls_targets():
		return   # the WeaponPose modifier places the targets in the skeleton pass, from the real shoulder
	# Editor-preview path (or the modifier switched off): the shoulder as the animation leaves it, which
	# does not include what the skeleton's modifiers do to it.
	var shoulder_index := skeleton.find_bone(right_arm_bones[0])
	apply_weapon_targets(skeleton.global_transform * skeleton.get_bone_global_pose(shoulder_index).origin)


func weapon_pose_modifier_controls_targets() -> bool:
	return weapon_pose_modifier != null and weapon_pose_modifier_enabled and not Engine.is_editor_hint()


## Everything the weapon pose needs that does not depend on where the shoulder is: the carry sway, and what the
## crouch and grip layers are told about the weapon.
func _update_weapon_pose_inputs(delta: float) -> void:
	if not has_weapon():
		_update_unarmed_pose_inputs()
		return
	stock_marker.position = handling.stock_rear
	var moving := false
	# Non-tool animation controllers intentionally do not expose runtime state
	# while this rig is drawing its editor preview.
	if not Engine.is_editor_hint() and is_instance_valid(animation_controller):
		moving = animation_controller.current_state in [&"move", &"carry_move"]
	carry_motion_blend = move_toward(carry_motion_blend, 1.0 if moving else 0.0, delta * 5.0)
	_carry_phase += delta * TAU * 2.0
	# Moving with the rifle held: the butt is carried in front of the shoulder (clearance), a little higher. Standing still is the authored lowered carry.
	var ready_grip := handling.lowered_grip + (handling.ready_clearance + Vector3(0, 0.02, 0.0)) * carry_motion_blend
	ready_grip.y += sin(_carry_phase) * 0.008 * carry_motion_blend
	_ready_grip_base = ready_grip
	if crouch_modifier != null:
		crouch_modifier.aim_lean_degrees = AIM_LEAN_DEGREES * weapon_blend()
		crouch_modifier.support_reach_degrees = SUPPORT_REACH_DEGREES * weapon_blend()
		if ladder != null and ladder.pose != null:
			# A ladder climbed: the trunk leans into it by the traversal's weight (set_traversal_progress), not into the rifle.
			crouch_modifier.aim_lean_degrees = lerpf(crouch_modifier.aim_lean_degrees, ladder.pose.lean_degrees, ladder.pose.weight)
	if grip_modifier != null:
		var holding: bool = not (is_instance_valid(animation_controller) and animation_controller.current_state in [&"pickup", &"boarding", &"carry_idle", &"carry_move"])
		grip_modifier.curl = [SUPPORT_GRIP_CURL if holding else 0.0, TRIGGER_HAND_CURL if holding else 0.0]
		grip_modifier.grasp[1] = HandGripModifier.Grasp.INDEXED_FIREARM if holding and ladder == null else HandGripModifier.Grasp.WRAP
		grip_modifier.orient_weight = 1.0 if holding else 0.0
		grip_modifier.weapon_basis = skeleton.global_basis.orthonormalized().inverse() * weapon.global_basis.orthonormalized()
		grip_modifier.trigger_pull = trigger_pull


## The shoulder-dependent half of the weapon pose: the stock pocket, both hand targets and the elbow poles, given
## the right shoulder's world position. One place for the formulas; the WeaponPose modifier calls it with the
## shoulder of the current skeleton pass, the editor-preview path with the animation-only shoulder.
## `chest_in_root` is the chest bone's orientation in the character-root frame, in THIS skeleton pass. The settled
## reference follows the chest every pass except while the chest kicks, when it is held: the weapon then turns by the
## chest's rotation since it settled. Standing, crouching and kneeling all share this; cover yaw and facing turn the
## root, so they never appear in it.
func update_torso_frame(chest_in_root: Basis, delta: float) -> void:
	if not has_weapon() or not torso_frame_enabled or Engine.is_editor_hint():
		torso_frame = Basis.IDENTITY
		_torso_offset = Quaternion.IDENTITY
		return
	var chest := chest_in_root.orthonormalized()
	var kicking: bool = is_instance_valid(animation_controller) and animation_controller.current_state in TORSO_KICK_STATES
	if not kicking or not _torso_reference_known:
		_torso_reference = chest
		_torso_reference_known = true
	if kicking:
		_torso_offset = (chest * _torso_reference.inverse()).get_rotation_quaternion()
	else:
		var ease_in := 1.0 if delta <= 0.0 else 1.0 - exp(-delta / TORSO_FRAME_RELEASE_SECONDS)
		_torso_offset = _torso_offset.slerp(Quaternion.IDENTITY, ease_in)
	torso_frame = Basis(_torso_offset)


func apply_weapon_targets(shoulder_world: Vector3) -> void:
	release_hand_contacts()   # a new pass: only a contact claimed again below still owns a hand
	if not has_weapon():
		apply_relaxed_hand_targets(shoulder_world)
		return
	shoulder_marker.position = character_root.to_local(shoulder_world) + shoulder_contact_offset
	var aimed_grip := shoulder_marker.position - torso_frame * (stock_contact_offset + grip_offset)
	# While crouched, the low-ready grip and the elbows travel with the chest: the shoulder moved
	# from where it stands when upright.
	if not _standing_shoulder_known:
		_standing_shoulder = shoulder_marker.position
		_standing_shoulder_known = true
	# The held rifle follows the shoulder wherever the body puts it (crouch, a running lean, the step's bob), so its stock keeps its place in front of it.
	var landing := ladder != null and ladder.pose != null and ladder.pose.landing_phase >= 0.0
	var landing_follow := 0.0
	if landing:
		var phase := ladder.pose.landing_phase
		landing_follow = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.95, 1.0, phase))
	var follow := 1.0 if (crouch_modifier != null and crouch_modifier.depth > 0.002) else maxf(carry_motion_blend, landing_follow)
	var body_offset := (shoulder_marker.position - _standing_shoulder) * follow
	var ready_grip := _ready_grip_base + body_offset
	right_hand_target.position = ready_grip.lerp(aimed_grip, weapon_blend()) + Vector3(0, 0, -recoil * 0.08)
	_pole_body_offset = body_offset
	_pole_ready = [right_elbow_ready + body_offset, left_elbow_ready + body_offset]
	right_elbow_pole.position = _pole_ready[0].lerp(right_elbow_aim, weapon_blend())
	left_elbow_pole.position = _pole_ready[1].lerp(left_elbow_aim, weapon_blend())
	# Predict the support marker in the current pose before solving either arm.
	# Reading the attached weapon here would use last frame's wrist transform.
	if is_instance_valid(support_ik_target):
		support_ik_target.position = right_hand_target.position + _rifle_local_basis() * (grip_offset + support_wrist)


## Swivel of `elbow` around the shoulder-to-wrist axis, degrees, measured from the chest's down direction projected
## onto the plane perpendicular to that axis. Returns INF when the reference is unstable.
static func elbow_swivel_degrees(shoulder: Vector3, elbow: Vector3, wrist: Vector3, down: Vector3) -> float:
	var axis := (wrist - shoulder).normalized()
	var reference := down - axis * down.dot(axis)
	var bend := (elbow - shoulder) - axis * (elbow - shoulder).dot(axis)
	if reference.length() < ELBOW_REFERENCE_MIN or bend.length() < 0.0001:
		return INF
	return rad_to_deg(reference.normalized().signed_angle_to(bend.normalized(), axis))


## The elbow poles for this skeleton pass, after the hand targets and the support reach are final. `shoulders` are the
## world positions of the right and left upper-arm joints, `chest_world` the chest's world orientation (the root frame
## turned by the chest's change from its rest pose). The pole sits on the side of the shoulder-wrist axis that the
## standing aim's elbow does, measured from the chest's down, so a lowered or leaning torso carries the bend plane with it.
## The swivel is read from the guides until the aim has fully raised and then held; relaxed handling is not touched.
func apply_elbow_guidance(shoulders: Array, chest_world: Basis, carrying := false) -> void:
	if not elbow_guidance_enabled or Engine.is_editor_hint():
		return
	var blend := 1.0 if carrying else weapon_blend()
	if blend <= 0.0:
		return
	var poles: Array[Node3D] = [right_elbow_pole, left_elbow_pole]
	var guides: Array[Vector3] = [right_elbow_aim, left_elbow_aim]
	var wrists: Array[Vector3] = [right_hand_target.global_position, support_ik_target.global_position]
	var down := -chest_world.orthonormalized().y
	var swivels: Array[float] = [_elbow_swivel[0], _elbow_swivel[1]]
	if carrying:
		swivels = [carry_elbow_swivel_degrees.x, carry_elbow_swivel_degrees.y]
	elif not _elbow_swivel_latched:
		var measured := true
		for i in 2:
			var parent := poles[i].get_parent() as Node3D
			var guide_world := parent.to_global(guides[i] + _pole_body_offset)
			swivels[i] = elbow_swivel_degrees(shoulders[i], guide_world, wrists[i], down)
			measured = measured and is_finite(swivels[i])
		if not measured:
			return
		if blend >= 0.99:
			_elbow_swivel = swivels.duplicate()
			_elbow_swivel_latched = true
	for i in 2:
		var axis_vector: Vector3 = wrists[i] - shoulders[i]
		if axis_vector.length() < 0.05:
			continue
		var axis := axis_vector.normalized()
		var reference := down - axis * down.dot(axis)
		if reference.length() < ELBOW_REFERENCE_MIN:
			continue
		var direction := reference.normalized().rotated(axis, deg_to_rad(swivels[i]))
		var aimed_world: Vector3 = (shoulders[i] + wrists[i]) * 0.5 + direction * ELBOW_POLE_DISTANCE
		var parent := poles[i].get_parent() as Node3D
		if carrying:
			poles[i].position = parent.to_local(character_root.to_global(_reach_poles[i]).lerp(aimed_world, _carry_reach) if _carry_reach < 1.0 else aimed_world)
		else:
			poles[i].position = _pole_ready[i].lerp(parent.to_local(aimed_world), blend)


## The unarmed character's per-frame inputs: no rifle sway, no aim lean, no support reach; the hands rest open (and close on a ladder's rungs as it is climbed).
const UNARMED_HAND_CURL := 0.25
## How much of its length the hanging arm keeps (a slight bend at the elbow).
const RELAXED_ARM_BEND := 0.93

func _update_unarmed_pose_inputs() -> void:
	carry_motion_blend = 0.0
	var climbing := ladder != null and ladder.pose != null
	if crouch_modifier != null:
		crouch_modifier.aim_lean_degrees = lerpf(0.0, ladder.pose.lean_degrees, ladder.pose.weight) if climbing else 0.0
		crouch_modifier.support_reach_degrees = 0.0
	if grip_modifier != null:
		var grip := lerpf(UNARMED_HAND_CURL, CARRY_GRIP_CURL, ladder.pose.weight) if climbing else UNARMED_HAND_CURL
		grip_modifier.curl = [grip, grip]
		grip_modifier.grasp[1] = HandGripModifier.Grasp.WRAP
		grip_modifier.orient_weight = 0.0
		grip_modifier.trigger_pull = 0.0


## The unarmed hands: each hangs under its shoulder at the arm's own length (slightly bent), the elbow pole behind and outward. Runs where the weapon targets would, from the same-pass shoulder, so a crouch,
## a kneel or a lean carries the arms with the body. A ladder or a carried passenger then takes the hands from here, exactly as it takes them from the weapon's.
func apply_relaxed_hand_targets(right_shoulder_world: Vector3) -> void:
	var left_shoulder_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bones.left_arm[0])).origin
	var frame := character_root.global_basis.orthonormalized()
	var shoulders: Array[Vector3] = [right_shoulder_world, left_shoulder_world]
	var targets: Array[Node3D] = [right_hand_target, support_ik_target]
	var poles: Array[Node3D] = [right_elbow_pole, left_elbow_pole]
	for side in 2:
		var hang: Vector3 = shoulders[side] + frame * Vector3(0.0, -_arm_length(side) * RELAXED_ARM_BEND, 0.03)
		hang += _arm_swing(side, frame, _arm_length(side))
		hang = _clear_of_thigh(hang, side, frame, _arm_length(side))
		if side == 0 and presenter != null:
			hang = _raised_by_gesture(hang, shoulders[side], frame)
		var palm_toward_body: Vector3 = frame * Vector3(1.0 if side == 0 else -1.0, 0.0, 0.0)
		claim_hand_contact(HandContact.make(HandContact.Hand.RIGHT if side == 0 else HandContact.Hand.LEFT, hang, (hang - shoulders[side]).normalized(), palm_toward_body, HANGING_HAND_WEIGHT))
		var outward := -1.0 if side == 0 else 1.0   # the character's right hand is on -X
		poles[side].global_position = (shoulders[side] + hang) * 0.5 + frame * Vector3(outward * 0.30, 0.0, -0.30)


## The walking arm swing of a hanging (unarmed) arm: the hand goes forward while the foot on the SAME side goes back, as a walker's arms counter the legs, by a share of how far that ankle is
## ahead of or behind its hip, faded in with the walking speed (none when standing). It follows the legs' own phase, whatever gait or body: the hang point used to stay fixed under the shoulder, so the
## IK held the arms rigid while the legs walked.
const ARM_SWING_PER_STRIDE := 0.55
## The most a hand swings fore or aft, as a share of the arm's length.
const ARM_SWING_MAX := 0.22
## The walking speed (m/s) at which the swing is full.
const ARM_SWING_FULL_SPEED := 0.9

func _arm_swing(side: int, frame: Basis, arm_length: float) -> Vector3:
	var speed_share := clampf(float(locomotion_report.get("speed", 0.0)) / ARM_SWING_FULL_SPEED, 0.0, 1.0)
	if speed_share <= 0.001 or ladder != null or is_instance_valid(carry_passenger):
		return Vector3.ZERO
	var leg: Array[StringName] = bones.right_leg if side == 0 else bones.left_leg
	var hip := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(leg[0])).origin
	var ankle := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(leg[2])).origin
	var ahead := (ankle - hip).dot(frame.z)
	var swing := clampf(-ahead * ARM_SWING_PER_STRIDE, -arm_length * ARM_SWING_MAX, arm_length * ARM_SWING_MAX) * speed_share
	return frame.z * swing + frame.y * (absf(swing) * 0.3)   # the hand rises a little at either end of its arc

## The right hand while a gesture asks for it (CharacterPresenter.gesture_hand): raised out beside the head at the arm's own length, with a small wave, blended from where it hangs. The point is in the body's own
## frame and scales with the arm, so it fits any humanoid.
func _raised_by_gesture(hang: Vector3, shoulder: Vector3, frame: Basis) -> Vector3:
	var hand := presenter.gesture_hand()
	if hand.x <= 0.0:
		return hang
	var length := _arm_length(0)
	var raised := shoulder + frame * Vector3(-0.36 * length + 0.12 * length * hand.y, 0.50 * length, 0.34 * length)   # the character's right is -X
	return hang.lerp(raised, hand.x)


## How far a resting hand keeps from the thigh's axis, as a fraction of the thigh's length: the thigh's own thickness plus the hand's. Body-relative, so it scales with the character and needs no rig-specific number.
## How fully the hanging hand takes the neutral-wrist orientation over the animation's rotation.
const HANGING_HAND_WEIGHT := 1.0
const HAND_THIGH_CLEARANCE := 0.30
## The most a resting hand may be pushed out from straight under its shoulder, as a fraction of the arm's length: enough to clear the hip, never a held-out arm.
const MAX_HAND_ABDUCTION := 0.28

## A resting hand's wrist is neutral: the fingers continue the arm's line and the palm faces the thigh (claimed as a HandContact above). Without it the hand keeps the animation's rest rotation, which points it
## inward across the leg (the rest pose is a T-pose with the palms down). A ladder or a carried body claims the hand after this, in the same pass, and takes it over.

## The hand's resting point moved outward (never inward) until it clears this side's thigh (hip to knee, as posed this pass), so a hand hangs beside the leg instead of in it. Not a collision system: one segment, one direction.
func _clear_of_thigh(hand: Vector3, side: int, frame: Basis, arm_length: float) -> Vector3:
	var leg: Array[StringName] = bones.right_leg if side == 0 else bones.left_leg
	var hip := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(leg[0])).origin
	var knee := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(leg[1])).origin
	var thigh := knee - hip
	if thigh.length_squared() < 0.000001:
		return hand
	var clearance := thigh.length() * HAND_THIGH_CLEARANCE
	var outward: Vector3 = frame.x * (-1.0 if side == 0 else 1.0)   # the character's right side is -X
	var origin := hand
	for step in 4:   # the thigh's closest point moves with the hand: a few passes settle it
		var t := clampf((hand - hip).dot(thigh) / thigh.length_squared(), 0.0, 1.0)
		var away := hand - (hip + thigh * t)
		var lateral := away.dot(outward)
		var gap := away.length()
		if gap >= clearance:
			break
		# push along the outward axis by what the remaining clearance needs (solved on the lateral part of the gap)
		var vertical_part := maxf(gap * gap - lateral * lateral, 0.0)
		var needed := sqrt(maxf(clearance * clearance - vertical_part, 0.0)) - lateral
		hand += outward * maxf(needed, 0.0)
	var shift := (hand - origin).dot(outward)
	if shift > arm_length * MAX_HAND_ABDUCTION:
		hand = origin + outward * arm_length * MAX_HAND_ABDUCTION
	return hand


## The length of an arm (upper arm plus forearm) as the character is scaled, from the rest pose.
func _arm_length(side: int) -> float:
	var chain: Array[StringName] = bones.right_arm if side == 0 else bones.left_arm
	var shoulder := skeleton.get_bone_global_rest(skeleton.find_bone(chain[0])).origin
	var elbow := skeleton.get_bone_global_rest(skeleton.find_bone(chain[1])).origin
	var wrist := skeleton.get_bone_global_rest(skeleton.find_bone(chain[2])).origin
	return (shoulder.distance_to(elbow) + elbow.distance_to(wrist)) * skeleton.global_basis.get_scale().y


## Where the hands and elbows rest, in the character's frame, when no rifle holds them (right, left): the release lets go to
## these, and a pickup that has no better record of where they were starts from them.
const RELAXED_HANDS: Array[Vector3] = [Vector3(-0.22, 0.92, 0.30), Vector3(0.22, 0.92, 0.30)]
const RELAXED_POLES: Array[Vector3] = [Vector3(-0.50, 0.85, 0.05), Vector3(0.50, 0.85, 0.05)]
## Nearest the carrier walks into the passenger when setting it down (metres, in front of its root).
const RELEASE_STEP := 0.45


## What the context host may tell this rig about the character it carries. `loaded_query` is a `func() -> bool`: when set, it says whether the character is a loaded carrier (the tactical host answers from
## its unit's carry state, which leads the visual passenger); unset, a character is loaded when its visual passenger exists (the workbench and tools).
var loaded_query: Callable

## Whether the loaded gaits and the carry pose apply.
func is_loaded() -> bool:
	return loaded_query.call() if loaded_query.is_valid() else is_instance_valid(carry_passenger)


## Once per frame: the speed the character is ACTUALLY moving at (the tactical layer's, or the workbench's preview) and how fast its heading is changing,
## in, the legs' cadence, gait blend and the body's lean out. The speed the legs respond to follows the real speed with the profile's rise and fall
## limits; it never drives movement. Idle is a speed of zero: this is also what settles the gait to a stop.
func _exit_tree() -> void:
	# Skeleton modifiers can emit once more while their hierarchy is being removed. Disconnect before descendants lose legal global transforms.
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_align_weapon_to_aim):
		skeleton.skeleton_updated.disconnect(_align_weapon_to_aim)
	presenter.teardown()
	if _rescue_handle != null:
		# Nothing waits on a character that is gone: the timeline stops and whoever observes the handle is told it was interrupted.
		rescue_interaction.stop()
		_settle_rescue(PresentationTypes.Outcome.INTERRUPTED)


## Follows the resolved posture request one frame: the crouch depth and the kneel blend ease toward what the request needs (profile speeds; an `exact` request is followed as given), and when `drive_yaw` the body yaw eases to the
## requested offset by the shortest way. This is the ONLY writer of the posture ramps. `depth_request` is the unclamped lowering the request asks for: up to the deepest natural crouch it is a
## crouch, beyond it the character goes down on one knee.
func apply_posture_target(depth_request: float, yaw_goal: float, delta: float, profile: CoverPostureProfile, drive_yaw := true, kneel_request := -1.0, exact := false) -> void:
	if crouch_modifier == null:
		return
	var depth_target := crouch_modifier.clamp_depth(depth_request)
	var kneel_target := kneel_request if kneel_request >= 0.0 else clampf((depth_request - crouch_modifier.max_depth) / KNEEL_BLEND_RANGE, 0.0, 1.0)
	if exact:
		# An authored timeline (the rescue lift) already shapes the motion: follow it as it is, and keep the ramps where it left them so the next ordinary request eases from there.
		_crouch_depth = depth_target
		_kneel = clampf(kneel_target, 0.0, 1.0)
	else:
		_crouch_depth = move_toward(_crouch_depth, depth_target, profile.crouch_speed * delta)
		_kneel = move_toward(_kneel, kneel_target, profile.kneel_speed * delta)
	crouch_modifier.depth = _crouch_depth
	crouch_modifier.kneel = _kneel
	if drive_yaw:
		# Shortest way round, always: the offset is an angle, and a plain linear chase could sweep the long way through a full turn.
		var step := deg_to_rad(profile.turn_degrees_per_second) * delta
		_cover_yaw = wrapf(_cover_yaw + clampf(angle_difference(_cover_yaw, yaw_goal), -step, step), -PI, PI)


## True when the locomotion presentation was already fed on this engine frame (a tool or test drove it directly), so a second feed would advance the smoothing twice.
func locomotion_fed_this_frame() -> bool:
	return _locomotion_fed_frame == Engine.get_process_frames()


## This body's leg over the reference body's (RigBones.body_ratio), measured once.
func body_ratio() -> float:
	if _body_ratio < 0.0:
		_body_ratio = bones.body_ratio(skeleton) if bones != null and is_instance_valid(skeleton) else 1.0
	return _body_ratio


var _body_ratio := -1.0
var _ladder_body: LadderBody


## The limb lengths and joint offsets the ladder planner works from, measured once from the skeleton at rest as the character is shown (see LadderBody). Falls back to the reference proportions when
## the bones are not mapped.
func ladder_body() -> LadderBody:
	if _ladder_body != null:
		return _ladder_body
	_ladder_body = LadderBody.new()
	_ladder_body.ratio = body_ratio()
	if bones == null or not is_instance_valid(skeleton) or not skeleton.is_inside_tree() or bones.left_leg.size() < 3 or bones.left_arm.size() < 3 or bones.hips == &"":
		return _ladder_body
	var to_local := character_root.global_basis.orthonormalized().inverse()
	var rest := func(bone: StringName) -> Vector3:
		return skeleton.global_basis * skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin
	var hips: Vector3 = rest.call(bones.hips)
	var hip: Vector3 = rest.call(bones.left_leg[0])
	var knee: Vector3 = rest.call(bones.left_leg[1])
	var ankle: Vector3 = rest.call(bones.left_leg[2])
	var shoulder: Vector3 = rest.call(bones.left_arm[0])
	var elbow: Vector3 = rest.call(bones.left_arm[1])
	var wrist: Vector3 = rest.call(bones.left_arm[2])
	_ladder_body.thigh = hip.distance_to(knee)
	_ladder_body.shin = knee.distance_to(ankle)
	_ladder_body.upper_arm = shoulder.distance_to(elbow)
	_ladder_body.forearm = elbow.distance_to(wrist)
	_ladder_body.hip_offset = to_local * (hip - hips)
	_ladder_body.shoulder_offset = to_local * (shoulder - hips)
	# The skeleton's origin is on the floor at rest, so the ankle's height above it is its height above the sole.
	_ladder_body.ankle_height = maxf((to_local * ankle).y, 0.0)
	if bones.left_toes != &"" and skeleton.find_bone(bones.left_toes) >= 0:
		var toe: Vector3 = to_local * (rest.call(bones.left_toes) - ankle)
		_ladder_body.ball_length = Vector2(toe.x, toe.z).length()
		_ladder_body.toe_height = maxf((to_local * rest.call(bones.left_toes)).y, 0.0)
	# The limb volumes as this body's own mesh has them (armor included), not as the reference body would: measured once from the skinned vertices at rest.
	var legs: Array[StringName] = [bones.left_leg[0], bones.left_leg[1], bones.left_leg[2]]
	var foot_bones: Array[StringName] = [bones.left_leg[2]]
	if bones.left_toes != &"" and skeleton.find_bone(bones.left_toes) >= 0:
		legs.append(bones.left_toes)
		foot_bones.append(bones.left_toes)
	var surface := SkinnedSurface.create(skeleton, legs)
	if surface.size() > 100:
		_ladder_body.measured_thigh = surface.measured_radius([bones.left_leg[0]], bones.left_leg[0], bones.left_leg[1])
		_ladder_body.measured_shin = surface.measured_radius([bones.left_leg[1]], bones.left_leg[1], bones.left_leg[2])
		_ladder_body.measured_knee = surface.measured_radius([bones.left_leg[0], bones.left_leg[1]], bones.left_leg[1], bones.left_leg[1], 0.9, true)
		# The boot's reach ahead of the ankle, along the character's own forward (in the skeleton frame).
		var forward := (skeleton.global_basis.inverse() * character_root.global_basis.z).normalized()
		_ladder_body.foot_forward = surface.reach_along(foot_bones, bones.left_leg[2], forward, 1.0)
		# The boot's sole thickness: how far below the ankle bone its lowest vertex is (down = the character's own down in the skeleton frame).
		var down := (skeleton.global_basis.inverse() * -character_root.global_basis.y).normalized()
		_ladder_body.sole_below_ankle = maxf(surface.reach_along(foot_bones, bones.left_leg[2], down, 1.0), _ladder_body.ankle_height * 0.5)
	return _ladder_body


func update_locomotion_presentation(speed: float, heading_rate: float, delta: float) -> void:
	if not is_instance_valid(animation_controller) or not is_instance_valid(animation_controller.animation_tree) or delta <= 0.0:
		return
	_locomotion_fed_frame = Engine.get_process_frames()
	var p := locomotion_profile
	var previous := _visual_speed
	_visual_speed = move_toward(_visual_speed, speed, (p.speed_rise if speed > _visual_speed else p.speed_fall) * delta)
	_speed_accel = lerpf(_speed_accel, (_visual_speed - previous) / delta, 1.0 - exp(-delta / 0.08))
	var k := 1.0 if p.gait_smoothing <= 0.0 else 1.0 - exp(-delta / p.gait_smoothing)
	_gait_blend = lerpf(_gait_blend, p.gait_blend(_visual_speed), k)
	_loaded_blend = lerpf(_loaded_blend, p.loaded_blend(_visual_speed), k)
	var stride := p.loaded_stride_at(_loaded_blend) if is_loaded() else p.stride_at(_gait_blend)
	stride *= body_ratio()   # a stride is authored in metres for the reference body; a shorter leg takes a shorter step at the same speed (more steps per second)
	var cadence := p.cadence_for(_visual_speed, stride)
	animation_controller.set_locomotion(locomotion_direction, cadence)
	animation_controller.set_gait(_gait_blend, _loaded_blend)
	_heading_rate = lerpf(_heading_rate, heading_rate, 1.0 - exp(-delta / 0.06))
	_bank_target = clampf(_heading_rate * _visual_speed * p.bank_gain, -p.bank_max, p.bank_max)
	if is_loaded():
		_bank_target = 0.0   # a carrier keeps the trunk square: the passenger and the hand contacts ride on the chest
	_update_body_adjustments(delta)
	locomotion_report = {"speed": _visual_speed, "gait": _gait_blend, "loaded": _loaded_blend, "cadence": cadence, "accel": _speed_accel, "bank": _bank_target}


## The presenter's facing, applied: the node's yaw, the visual root's yaw, and the absorption of a facing change into the cover yaw. These are the only writers of facing in a rig; the DECISIONS (toward which
## point, whether a cover pose absorbs the change, how fast to turn) are CharacterPresenter's.
func apply_facing_yaw(yaw: float) -> void:
	rotation.y = yaw


func apply_root_yaw(yaw: float) -> void:
	if is_instance_valid(character_root):
		character_root.rotation.y = yaw


## A facing change of `change` radians arrived while a cover pose holds the body: the body (and the rifle on it) does not snap, its offset takes the change up and eases to the new pose.
func absorb_facing_change(change: float) -> void:
	_cover_yaw = wrapf(_cover_yaw - change, -PI, PI)


## A facing change that arrived at once (the unit now faces `delta_yaw` radians further round): the chest and weapon already face the new way; the
## hips are shown catching up (LocomotionPoseModifier). Presentation only.
func begin_turn(delta_yaw: float) -> void:
	if locomotion_modifier == null or is_loaded() or locomotion_profile.turn_twist_limit <= 0.0:
		return
	var limit := locomotion_profile.turn_twist_limit
	_twist = clampf(_twist + rad_to_deg(delta_yaw), -limit, limit)
	_twist_start = _twist


func _update_body_adjustments(delta: float) -> void:
	if locomotion_modifier == null:
		return
	var p := locomotion_profile
	var moving := _visual_speed > p.idle_below
	_twist = move_toward(_twist, 0.0, p.turn_unwind_rate * (3.0 if moving else 1.0) * delta)
	var steps := [0.0, 0.0]
	if not moving and absf(_twist_start) > 25.0 and absf(_twist) > 0.0:
		# Two repositioning steps, the foot on the side being turned toward first.
		var progress := 1.0 - absf(_twist) / absf(_twist_start)
		var first := 0 if _twist_start > 0.0 else 1
		steps[first] = p.turn_step_lift * sin(PI * clampf(progress / 0.55, 0.0, 1.0))
		steps[1 - first] = p.turn_step_lift * sin(PI * clampf((progress - 0.45) / 0.55, 0.0, 1.0))
	if absf(_twist) < 0.01:
		_twist_start = 0.0
	var input := RigInput.new()
	input.twist_degrees = _twist
	input.step_lift_left = steps[0]
	input.step_lift_right = steps[1]
	input.bank_degrees = _bank_target
	var pitch := 0.0 if is_loaded() else clampf(_speed_accel * p.accel_lean_gain, -p.accel_lean_max, p.accel_lean_max)
	input.pitch_degrees = pitch
	locomotion_modifier.apply_input(input)


## Starts the STEADY carry presentation at once (no lift): the passenger across the shoulders, the weapon slung and the wrists on
## the carry contacts. A pickup is `begin_pickup`; this is the loaded state both end in, and what tools and tests start from.
func begin_carry() -> void:
	if rescue_interaction.active():
		return
	_ensure_passenger(1.0, 1.0)
	stow_weapon()
	_stow_blend = 1.0
	_hands_to_contacts()


## The pickup: the passenger lies on the floor at `passenger_world` (where the rescued actor was) and the shared timeline lifts
## it into the carry while the carrier turns, steps in, kneels, takes hold, rises and steps back. Facing the passenger is the
## caller's business (the adapter turns the carrier first); the lift is built in the carrier's own frame.
func begin_pickup(passenger_world: Vector3, lying_basis = null) -> ActionHandle:
	if rescue_interaction.kind == RescueInteraction.Kind.PICKUP:
		return _rescue_handle   # already lifting: a repeated request is the same operation, not a second pickup
	if rescue_interaction.kind == RescueInteraction.Kind.RELEASE:
		_halt_interaction(PresentationTypes.Outcome.INTERRUPTED, false)   # a new pickup supersedes a release still running
	_discard_passenger()
	var handle := reserve_rescue_handle()
	var interaction := rescue_interaction
	interaction.start(RescueInteraction.Kind.PICKUP)
	_root_rest_position = position
	var to_passenger := passenger_world - character_root.global_position
	to_passenger.y = 0.0
	var gap := to_passenger.length()
	var local_direction := Vector3.BACK if gap < 0.01 else (character_root.global_basis.orthonormalized().inverse() * to_passenger / gap)
	local_direction.y = 0.0
	local_direction = local_direction.normalized() if local_direction.length() > 0.01 else Vector3.BACK
	_step_vector = local_direction * clampf(gap - interaction.stand_off, 0.0, interaction.max_step)
	_reach_hands = [character_root.to_local(right_hand_target.global_position), character_root.to_local(support_ik_target.global_position)]
	_reach_poles = [character_root.to_local(right_elbow_pole.global_position), character_root.to_local(left_elbow_pole.global_position)]
	_reach_curl = grip_modifier.curl[0] if grip_modifier != null else 0.0
	_ensure_passenger(0.0, 0.0)
	carry_passenger.ground_origin = Vector3(passenger_world.x, character_root.global_position.y + interaction.ground_height, passenger_world.z)
	if lying_basis is Basis:
		carry_passenger.ground_basis = lying_basis
		carry_passenger.has_ground_basis = true
	stow_weapon()
	_stow_blend = 0.0
	_hands_to_contacts()
	carry_passenger.refresh()
	_interaction_sample = interaction.sample()
	return handle


## The release: the carrier steps in, kneels, lowers the passenger to the floor in front of it, lets go and rises, taking the
## rifle back. The passenger is freed when it ends (or left lying: `keep_released_passenger`). Needs a carried passenger.
func begin_release() -> ActionHandle:
	if rescue_interaction.kind == RescueInteraction.Kind.RELEASE:
		return _rescue_handle   # already lowering: the same operation
	if not is_instance_valid(carry_passenger) or rescue_interaction.active():
		return ActionHandle.settled(PresentationTypes.Outcome.SKIPPED)   # nobody to put down, or a pickup still running: nothing was presented
	var handle := reserve_rescue_handle()
	var interaction := rescue_interaction
	interaction.start(RescueInteraction.Kind.RELEASE)
	_root_rest_position = position
	var step := minf(interaction.max_step, RELEASE_STEP)
	_step_vector = Vector3(0.0, 0.0, step)
	_reach_hands = RELAXED_HANDS.duplicate()
	_reach_poles = RELAXED_POLES.duplicate()
	_reach_curl = 0.2
	var forward := character_root.global_basis.orthonormalized().z
	var ahead := character_root.global_position + forward * (step + interaction.stand_off)
	carry_passenger.ground_origin = Vector3(ahead.x, character_root.global_position.y + interaction.ground_height, ahead.z)
	carry_passenger.waypoint_local = interaction.lift_waypoint
	_interaction_sample = interaction.sample()
	return handle


## The handle of the rescue operation that is RUNNING now (its timeline is advancing), else null. A pickup still waiting for its carrier to arrive is not running.
func rescue_presentation() -> ActionHandle:
	return _rescue_handle if _rescue_handle != null and not _rescue_handle.is_done() and rescue_interaction.active() else null


## The handle for the rescue operation about to start (or already pending/running): one operation, one handle. A host that has to hold a pickup back until the carrier arrives reserves it early so
## whoever observes the rescue has something to wait on; the rig settles it.
func reserve_rescue_handle() -> ActionHandle:
	if _rescue_handle != null and not _rescue_handle.is_done():
		return _rescue_handle
	_rescue_handle = ActionHandle.new()
	_rescue_handle.finished.connect(_on_rescue_handle_settled.bind(_rescue_handle))
	return _rescue_handle


## Settles the current rescue handle with `outcome` and forgets it. The slot is cleared BEFORE observers run, so one that starts or ends a rescue in its callback finds a clean rig.
func _settle_rescue(outcome: PresentationTypes.Outcome) -> void:
	var handle := _rescue_handle
	_rescue_handle = null
	if handle != null:
		handle.settle(outcome)


## The requester withdrew the operation (handle.cancel()). Only a cancel of the CURRENT handle acts; every other settlement was made by this rig and has already cleaned up.
func _on_rescue_handle_settled(outcome: PresentationTypes.Outcome, handle: ActionHandle) -> void:
	if handle != _rescue_handle or outcome != PresentationTypes.Outcome.CANCELLED:
		return
	_rescue_handle = null
	if rescue_interaction.kind == RescueInteraction.Kind.PICKUP:
		end_carry()   # a pickup that never finished leaves nothing of the lift: no passenger, the rifle back in hand
	elif rescue_interaction.kind == RescueInteraction.Kind.RELEASE:
		_halt_interaction(PresentationTypes.Outcome.CANCELLED, true)   # a release withdrawn midway leaves the passenger carried, as before it began


## The yaw the visual root currently shows (the posture's yaw offset once reached): a read-only view for hosts, so none reaches for the private property.
func cover_yaw() -> float:
	return _cover_yaw

## A host ends the running rescue interaction (a carrier defeated mid-lift): the public face of `_halt_interaction`.
func halt_interaction(outcome: PresentationTypes.Outcome, restore_carry := false) -> void:
	_halt_interaction(outcome, restore_carry)

## Stops the running timeline where it is and puts back what it moved (the step toward the passenger, the posture request); the passenger stays, steady across the shoulders when `restore_carry`.
func _halt_interaction(outcome: PresentationTypes.Outcome, restore_carry: bool) -> void:
	rescue_interaction.stop()
	position = _root_rest_position
	_step_vector = Vector3.ZERO
	_carry_reach = 1.0
	_interaction_sample = rescue_interaction.sample()
	_release_rescue_posture()
	_snap_posture_to_requests()
	if restore_carry and is_instance_valid(carry_passenger):
		carry_passenger.lift = 1.0
		carry_passenger.pose_blend = 1.0
		carry_passenger.refresh()
	_settle_rescue(outcome)


## True from the start of a pickup or release until it runs out.
func interaction_active() -> bool:
	return rescue_interaction.active()


## Runs the timeline to its end now: the final state, with no animation in between. For a conflicting presentation (the carrier
## starts walking, boards, falls) and for tools.
func finish_interaction_now() -> void:
	if not rescue_interaction.active():
		return
	rescue_interaction.scrub(rescue_interaction.duration())
	_interaction_sample = rescue_interaction.sample()
	_complete_interaction(PresentationTypes.Outcome.SKIPPED)


## Ends it: the passenger is freed (or, with `leave_passenger`, left lying where it is), the weapon returns to the hand, and
## nothing of the carry is left on the arms (the weapon pose writes the targets, poles and grip again on the next update).
## Also the safe answer to an interrupted rescue (the carrier is hit and the tactical layer puts the passenger down).
func end_carry(leave_passenger := false) -> void:
	rescue_interaction.stop()
	position = _root_rest_position
	_step_vector = Vector3.ZERO
	_carry_reach = 1.0
	_interaction_sample = {}
	if is_instance_valid(carry_passenger):
		if leave_passenger:
			carry_passenger.detach_to(_beside_host())
		else:
			carry_passenger.get_parent().remove_child(carry_passenger)
			carry_passenger.free()
	carry_passenger = null
	carry_contact_report = []
	_carry_lean = 0.0
	_release_rescue_posture()   # the posture is the arbiter's: whatever else is requested (cover) takes the body back
	_snap_posture_to_requests()   # a carry that ends under the carrier (hit, freed, cancelled) does not ease out of its lift pose: the body is where the remaining requests put it
	if crouch_modifier != null:
		crouch_modifier.aim_lean_degrees = 0.0
	release_hand_contacts()
	if grip_modifier != null:
		grip_modifier.curl = [0.0, 0.0]
	unstow_weapon()
	arm_ik.active = true
	_settle_rescue(PresentationTypes.Outcome.INTERRUPTED)   # last, once the rig is clean; a no-op when the operation had already settled


func carry_contacts_active() -> bool:
	return carry_contacts_enabled and is_instance_valid(carry_passenger)


func _ensure_passenger(lift: float, pose: float) -> void:
	if is_instance_valid(carry_passenger):
		return
	carry_passenger = RESCUE_PASSENGER.new()
	carry_passenger.name = "RescuePassenger"
	character_root.add_child(carry_passenger)
	carry_passenger.carry_yaw_degrees = passenger_yaw_degrees
	carry_passenger.pose_params = passenger_pose_overrides
	carry_passenger.carrier_root = character_root
	carry_passenger.waypoint_local = rescue_interaction.lift_waypoint
	carry_passenger.lift = lift
	carry_passenger.pose_blend = pose
	carry_passenger.build(character_scene, character_scale, rig_profile)
	carry_passenger.update_presentation(lift, pose, carry_passenger.global_transform, 0.0)
	carry_passenger.attach_to_carrier(skeleton, character_root, torso_bone_name, neck_bone_name, passenger_anchor_from_neck)


## Where a passenger left lying (the workbench's keep_released_passenger) is put: beside this rig's host, in the host's own container, so it is no longer part of the carrier.
func _beside_host() -> Node:
	var host := get_parent()
	return host.get_parent() if host != null and host.get_parent() != null else host


func _discard_passenger() -> void:
	if is_instance_valid(carry_passenger):
		carry_passenger.get_parent().remove_child(carry_passenger)
		carry_passenger.free()
	carry_passenger = null


func _hands_to_contacts() -> void:
	arm_ik.active = carry_contacts_enabled
	if grip_modifier != null:
		grip_modifier.grasp[1] = HandGripModifier.Grasp.WRAP
		grip_modifier.orient_weight = 0.0
		grip_modifier.trigger_pull = 0.0


## Forward lean of a carrier's trunk under the load, degrees, through the crouch modifier's measured forward axis (the same
## `aim_lean_degrees` the rifle uses; the rifle is slung while carrying). Eased in and out over CARRY_LEAN_SECONDS.
const CARRY_LEAN_DEGREES := 20.0
const CARRY_LEAN_SECONDS := 0.4

## The rescue clock moves on one frame. Called by the presenter's action stage, once per frame, for every host: the presenter owns WHEN the lift progresses, this rig owns what it looks like. A character that is
## not a loaded carrier (see is_loaded) does not advance it, exactly as it never applied it.
func advance_rescue_clock(delta: float) -> void:
	if rescue_interaction.active() and is_loaded():
		rescue_interaction.advance(delta)


## Once per frame while carrying (before the skeleton's modifiers, after the presenter has advanced the clock): sets the carrier's body from
## its sample (bend, kneel, lean, step toward the passenger, base clip, weapon position).
func _apply_carry_posture(delta: float) -> void:
	_interaction_sample = rescue_interaction.sample()
	var sample := _interaction_sample
	var interacting := rescue_interaction.active()
	if interacting:
		if is_instance_valid(animation_controller) and animation_controller.current_state != sample.clip:
			animation_controller.play(sample.clip)
		_stow_blend = float(sample.stow)
		if rescue_interaction.time >= rescue_interaction.duration() - 0.00001:
			_complete_interaction()
			interacting = false
	if crouch_modifier != null:
		if interacting:
			_carry_lean = float(sample.carry)
			_request_rescue_posture(sample)
			crouch_modifier.aim_lean_degrees = CARRY_LEAN_DEGREES * _carry_lean
			var parent_node := get_parent_node_3d()
			var parent_basis := parent_node.global_basis.orthonormalized() if parent_node != null else Basis.IDENTITY
			position = _root_rest_position + parent_basis.inverse() * (character_root.global_basis.orthonormalized() * _step_vector) * float(sample.step)
		else:
			_release_rescue_posture()
			var loaded: bool = is_instance_valid(animation_controller) and animation_controller.current_state in [&"carry_idle", &"carry_move"]
			_carry_lean = move_toward(_carry_lean, 1.0 if loaded else 0.0, delta / CARRY_LEAN_SECONDS)
			crouch_modifier.aim_lean_degrees = CARRY_LEAN_DEGREES * _carry_lean
		crouch_modifier.support_reach_degrees = 0.0


## The timeline has run out: pickup leaves the steady carry (the sample at its end IS the steady carry), release gives the
## passenger up. `rescue_interaction_finished` is emitted first, so a listener can show the real actor where it was set down.
func _complete_interaction(outcome := PresentationTypes.Outcome.COMPLETED) -> void:
	var kind := rescue_interaction.kind
	var handle := _rescue_handle
	_rescue_handle = null   # settled below, after the carry is cleaned up; end_carry must not settle it as interrupted first
	rescue_interaction.stop()
	_release_rescue_posture()
	position = _root_rest_position
	_step_vector = Vector3.ZERO
	_carry_reach = 1.0
	_interaction_sample = rescue_interaction.sample()
	if kind == RescueInteraction.Kind.PICKUP and is_instance_valid(carry_passenger):
		carry_passenger.lift = 1.0   # the steady carry, without waiting for the next skeleton pass to say so
		carry_passenger.pose_blend = 1.0
		carry_passenger.refresh()
	if kind == RescueInteraction.Kind.RELEASE:
		end_carry(keep_released_passenger)
		if is_instance_valid(animation_controller):
			animation_controller.play(&"rifle_idle")
	if handle != null:
		handle.settle(outcome)   # observers see the finished state (a released passenger is already gone)


## The rescue lift's posture: an ACTION-priority request (the cover request beneath it is untouched and takes the body back when this is released). The timeline already shapes the motion, so the
## request is `exact`; the depth and the half-kneel blend are the timeline's own, as they always were. Applied at once (delta 0 moves no ramp), so the pose this frame is this frame's sample.
func _request_rescue_posture(sample: Dictionary) -> void:
	var kneel_blend := float(sample.kneel)
	var posture := PresentationTypes.Posture.KNEEL if kneel_blend > 0.5 else PresentationTypes.Posture.CROUCH
	presenter.postures.set_posture(RESCUE_POSTURE_SOURCE, posture, PresentationTypes.PRIORITY_ACTION, 0.0, float(sample.crouch) * rescue_interaction.crouch_depth, kneel_blend, true)
	presenter.apply_posture(0.0, cover_profile, false)


## Puts the applied posture where the requests that remain resolve to, at once (the rig applies; the arbiter still decides). For the hard end of a rescue, not for ordinary changes.
func _snap_posture_to_requests() -> void:
	var requests := presenter.postures
	apply_posture_target(requests.resolved_depth(), requests.resolved_yaw_offset(), 0.0, cover_profile, false, requests.resolved_kneel(), true)


func _release_rescue_posture() -> void:
	presenter.postures.release(RESCUE_POSTURE_SOURCE)


## Places both wrists on the passenger's contacts for this skeleton pass (called by the WeaponPose modifier, with the carrier's
## shoulders and the passenger's anchor as they are in this pass). The hand is put on the limb from the shoulder's side, the
## fingers wrap across it, and the palm faces it; the wrist is the palm centre set back half a palm along the fingers.
func apply_carry_targets(shoulders: Array, anchor: Transform3D) -> void:
	var sample := _interaction_sample if not _interaction_sample.is_empty() else rescue_interaction.sample()
	var reach := float(sample.contact)
	_carry_reach = reach
	carry_passenger.motion_enabled = passenger_motion_enabled
	carry_passenger.motion_amplitude = passenger_motion_amplitude
	carry_passenger.motion_tilt_degrees = passenger_motion_tilt_degrees
	carry_passenger.motion_response = passenger_motion_response
	carry_passenger.motion_swing_degrees = passenger_motion_swing_degrees
	# The skeleton may still evaluate while the workbench is paused. Follow the
	# anchor each pass, but integrate secondary motion once per supplied step.
	var frame_id := Engine.get_process_frames()
	var delta := _pose_delta if _pose_delta_frame == frame_id and _passenger_delta_frame != frame_id else 0.0
	_passenger_delta_frame = frame_id
	carry_passenger.update_presentation(float(sample.lift), float(sample.pose), anchor, delta)
	var shoulder_of := {&"right": 0, &"left": 1}   # the index into `shoulders`
	var report: Array = [{}, {}]
	var curl := lerpf(_reach_curl, CARRY_GRIP_CURL, reach)
	for assignment in CARRY_CONTACTS:
		var approach := Vector3.ZERO
		if assignment.size() > 2:
			# Lying, a hand takes the limb from above; as the passenger comes up it moves round to the carry's own side.
			var carried_side := character_root.global_basis.orthonormalized() * (assignment[2] as Vector3).normalized()
			approach = Vector3.UP.lerp(carried_side, clampf(float(sample.lift) * 1.2, 0.0, 1.0)).normalized()
		var frame: Dictionary = carry_passenger.contact_frame(assignment[1], anchor, shoulders[shoulder_of[assignment[0]]], approach)
		var wrap_direction: Vector3 = (frame.axis as Vector3).cross(frame.side).normalized()
		var fingers: Vector3 = wrap_direction * (1.0 if assignment[0] == &"left" else -1.0)
		var normal: Vector3 = -(frame.side as Vector3)
		var palm: Vector3 = (frame.point as Vector3) + (frame.side as Vector3) * float(frame.radius)
		var half_palm := _half_palm_length(HandContact.Hand.RIGHT if assignment[0] == &"right" else HandContact.Hand.LEFT)
		var on_contact := palm - fingers * half_palm
		var side_index := 0 if assignment[0] == &"right" else 1
		# Before the hands have reached, they are where they were (carried with the body); `reach` brings them onto the contact.
		var point: Vector3 = character_root.to_global(_reach_hands[side_index]).lerp(on_contact, reach) if reach < 1.0 else on_contact
		claim_hand_contact(HandContact.make(HandContact.Hand.RIGHT if assignment[0] == &"right" else HandContact.Hand.LEFT, point, fingers, normal, reach, curl))
		report[side_index] = {"contact": assignment[1], "point": frame.point, "intended_palm": palm, "intended_finger_direction": fingers, "intended_palm_normal": normal, "reach": reach}
	carry_contact_report = report


## Hangs the weapon on the carrier's chest at the handling profile's stowage place (a provisional sling carry, nothing drawn):
## it follows the torso from then on. Presentation only; readiness and aim code are not involved while it is stowed.
func stow_weapon() -> void:
	if not has_weapon():
		return   # nothing to sling
	if weapon.get_parent() != character_root:
		_weapon_hand_local = weapon_attachment.global_transform.affine_inverse() * weapon.global_transform
		weapon.reparent(character_root)
	_stow_anchor = ChestAnchor.create(skeleton, character_root, torso_bone_name, neck_bone_name, handling.stowed_offset_from_neck, Basis.from_euler(handling.stowed_angles_degrees * (PI / 180.0)))
	if _stow_anchor == null:
		return
	if not skeleton.skeleton_updated.is_connected(_follow_stowed_weapon):
		skeleton.skeleton_updated.connect(_follow_stowed_weapon)
	_follow_stowed_weapon()


## Takes the weapon off the chest and back to the right hand's socket.
func unstow_weapon() -> void:
	_stow_anchor = null
	if has_weapon():
		weapon.reparent(weapon_attachment)


func is_weapon_stowed() -> bool:
	return _stow_anchor != null


func _follow_stowed_weapon() -> void:
	if _stow_anchor == null or not is_instance_valid(weapon):
		return
	var world := _stow_anchor.world_transform()
	var slung := Transform3D(world.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * handling.scale), world.origin)
	if _stow_blend >= 0.9999:
		weapon.global_transform = slung
		return
	# Between the hand and the sling (a pickup or release in progress): the rifle travels, it does not jump.
	var held := weapon_attachment.global_transform * _weapon_hand_local
	var t := smoothstep(0.0, 1.0, _stow_blend)
	weapon.global_transform = Transform3D(Basis(held.basis.get_rotation_quaternion().slerp(slung.basis.get_rotation_quaternion(), t)).scaled(slung.basis.get_scale()), held.origin.lerp(slung.origin, t))


func _play_shot_feedback() -> void:
	if muzzle_flash == null:
		return   # unarmed: there is no shot to show
	_shot_feedback_generation += 1
	var generation := _shot_feedback_generation
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	recoil = 0.065
	if _trigger_tween != null and _trigger_tween.is_valid():
		_trigger_tween.kill()
	trigger_pull = 1.0
	_trigger_tween = create_tween()
	_trigger_tween.tween_property(self, "trigger_pull", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(self, "recoil", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	muzzle_flash.visible = true
	await get_tree().create_timer(0.075, false).timeout
	if generation == _shot_feedback_generation:
		muzzle_flash.visible = false
## Whether the sights follow the playing clip (a standalone rig: the workbench and tools). A host with its own readiness (the tactical adapter) turns this off and drives `aim_blend` from it.
var aim_blend_follows_clips := true

func _on_animation_state_changed(state_name: StringName) -> void:
	if aim_blend_follows_clips:
		if _pose_tween != null and _pose_tween.is_valid():
			_pose_tween.kill()
		_pose_tween = create_tween()
		_pose_tween.tween_property(self, "aim_blend", 1.0 if state_name in [&"aim", &"shoot", &"shoot_left", &"shoot_right"] else 0.0, 0.28)
	if state_name in [&"shoot", &"shoot_left", &"shoot_right"]:
		_play_shot_feedback()
