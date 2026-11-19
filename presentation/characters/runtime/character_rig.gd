@tool
extends Node3D

const ANIMATION_CONTROLLER_FALLBACK := preload("res://presentation/characters/runtime/character_animation_controller.gd")

@export_group("Model Assets")
## Character model to assemble. It must contain a Skeleton3D.
## Character model instantiated by this presentation rig. MIRA Zero is the supported default.
@export var character_scene: PackedScene = preload("res://art/characters/mira_0/models/mira_0_prototype.glb")
## Uniform correction applied to imported models whose source units are not metres.
@export_range(0.1, 4.0, 0.01) var character_scale := 1.0
## Weapon model to attach. It must contain SupportHandTarget and MuzzleSocket nodes.
@export var weapon_scene: PackedScene = preload("res://art/weapons/aug/models/aug_runtime_socketed.glb")

@export_group("Skeleton Bone Map")
## Upper arm, forearm, and hand used by the firing-hand IK chain.
@export var right_arm_bones: Array[StringName] = [&"J_Bip_R_UpperArm", &"J_Bip_R_LowerArm", &"J_Bip_R_Hand"]
## Upper arm, forearm, and hand used by the support-hand IK chain.
@export var left_arm_bones: Array[StringName] = [&"J_Bip_L_UpperArm", &"J_Bip_L_LowerArm", &"J_Bip_L_Hand"]

@onready var character_root: Node3D = $Character
@onready var right_hand_target: Marker3D = $Character/IKTargets/RightHandTarget
@onready var right_elbow_pole: Marker3D = $Character/IKTargets/RightElbowPole
@onready var left_elbow_pole: Marker3D = $Character/IKTargets/LeftElbowPole

var skeleton: Skeleton3D
var arm_ik: TwoBoneIK3D
var crouch_modifier: CoverCrouchModifier
## Places the weapon's hand targets from the shoulder of the current skeleton pass (see WeaponPoseModifier).
var weapon_pose_modifier: WeaponPoseModifier
## False falls back to the legacy path: targets computed in `_process` from the shoulder as the animation leaves it,
## before the skeleton's modifiers. Kept for the editor preview, for comparison, and as a switch back.
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
const GRIP_OFFSET := Vector3(0.0, -0.035, 0.025)
# Approximate center of the AUG optic in weapon coordinates, checked in the demo.
const SIGHT_OFFSET := Vector3(0.0, 0.13, -0.10)
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
var sight_offset := SIGHT_OFFSET
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
## Most the support shoulder may be protracted in total (base reach plus what a target needs), degrees. The base is
## SUPPORT_REACH_DEGREES. Conservative: about half of the sternoclavicular joint's ~35 degree protraction-retraction
## range (StatPearls, Kenhub, GPnotebook). Set per character; see WeaponPoseModifier.
@export_range(0.0, 45.0, 0.5, "suffix:°") var support_protraction_limit_degrees := 18.0
## Elbow bend (interior angle, degrees) the support arm is eased toward when its target is nearly out of reach.
## 180 is a locked elbow.
@export_range(120.0, 180.0, 1.0, "suffix:°") var support_elbow_comfort_degrees := 165.0
@export_range(2, 16, 1) var support_solve_iterations := 8
## Torso-relative weapon frame. While the chest kicks (a shot) the aimed weapon turns with the chest, about the
## stock, instead of keeping the character root's orientation: the weapon and both shoulders then move as one body and
## the support hand keeps its grip. Off restores the root-frame weapon (used for before/after comparisons).
@export var torso_frame_enabled := true
## Bone whose orientation defines the torso (the chest). Set automatically for known skeletons.
var torso_bone_name := &""
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
@export_group("Rescue Carry")
## Positions are in Character-local metres; stowed angles are degrees.
@export var passenger_position := Vector3(0, 1.38, -0.16)
@export var stowed_weapon_position := Vector3(0.26, 0.8, -0.24)
@export var stowed_weapon_angles_degrees := Vector3(0, 0, rad_to_deg(-0.65))
@export_group("")
var carry_motion_blend := 0.0
var _carry_phase := 0.0

## How shouldered the rifle is. The rifle stays in its relaxed carry, in cover or not, and comes up
## only to aim or shoot. While crouched the carry simply travels with the chest (see body_offset).
func weapon_blend() -> float:
	return aim_blend


func _rifle_local_basis() -> Basis:
	var carry_rotation := Quaternion.from_euler(handling.lowered_angles_degrees * (PI / 180.0))
	return Basis(carry_rotation.slerp(torso_frame.get_rotation_quaternion(), weapon_blend()))


func _build_character() -> void:
	assert(character_scene != null, "Character scene is required")
	var model := character_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * character_scale
	character_root.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null, "Character model must contain Skeleton3D")
	assert(right_arm_bones.size() == 3 and left_arm_bones.size() == 3, "Arm bone maps require upper arm, forearm, and hand")


func _build_weapon_attachment() -> void:
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "RightHandWeaponSocket"
	weapon_attachment.bone_name = right_arm_bones[2]
	skeleton.add_child(weapon_attachment)

	assert(weapon_scene != null, "Weapon scene is required")
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
	animation_controller.state_changed.connect(_on_animation_state_changed)
	animation_controller.setup(skeleton, character_root)
	_build_crouch_modifier()
	_build_weapon_pose_modifier()
	_build_grip_modifier()


## Procedural crouch layer: runs after the animation and before the arm IK, so the arms and
## the weapon follow the lowered body.
func _build_grip_modifier() -> void:
	var prefix := "mixamorig_" if skeleton.find_bone(&"mixamorig_Hips") >= 0 else ""
	if prefix.is_empty():
		return
	grip_modifier = HandGripModifier.new()
	grip_modifier.name = "HandGrip"
	if not grip_modifier.setup(skeleton, prefix):
		grip_modifier = null
		return
	skeleton.add_child(grip_modifier)
	_place_hands_on_weapon()


## Derives the weapon placement from the handling profile and the real hand size: the palm centre
## lies half a palm length ahead of the wrist along the hand's forward direction, so each wrist is
## put that far behind its grip.
func _place_hands_on_weapon() -> void:
	var scale_value := handling.scale
	var palm := grip_modifier.palm_length if grip_modifier != null else 0.09
	var half_palm := handling.hand_forward() * palm * 0.5
	var firing_wrist := handling.firing_palm() * scale_value - half_palm
	grip_offset = -firing_wrist
	support_wrist = handling.support_palm() * scale_value - half_palm
	stock_contact_offset = handling.stock_rear * scale_value
	if grip_modifier != null:
		grip_modifier.hand_forward = handling.hand_forward()


## Runs after the crouch layer and before the arm IK, so the targets are placed from the final procedural shoulder.
func _build_weapon_pose_modifier() -> void:
	var modifier := WeaponPoseModifier.new()
	modifier.name = "WeaponPose"
	torso_bone_name = &"mixamorig_Spine2" if skeleton.find_bone(&"mixamorig_Hips") >= 0 else &"J_Bip_C_Chest"
	if not modifier.setup(self):
		return
	skeleton.add_child(modifier)
	if is_instance_valid(arm_ik):
		skeleton.move_child(modifier, arm_ik.get_index())
	weapon_pose_modifier = modifier
	weapon_pose_modifier.active = weapon_pose_modifier_enabled


func _build_crouch_modifier() -> void:
	var mixamo := skeleton.find_bone(&"mixamorig_Hips") >= 0
	var bones := {
		"hips": &"mixamorig_Hips" if mixamo else &"J_Bip_C_Hips",
		"left_upper": &"mixamorig_LeftUpLeg" if mixamo else &"J_Bip_L_UpperLeg",
		"left_lower": &"mixamorig_LeftLeg" if mixamo else &"J_Bip_L_LowerLeg",
		"left_foot": &"mixamorig_LeftFoot" if mixamo else &"J_Bip_L_Foot",
		"right_upper": &"mixamorig_RightUpLeg" if mixamo else &"J_Bip_R_UpperLeg",
		"right_lower": &"mixamorig_RightLeg" if mixamo else &"J_Bip_R_LowerLeg",
		"right_foot": &"mixamorig_RightFoot" if mixamo else &"J_Bip_R_Foot",
		"spine": [&"mixamorig_Spine", &"mixamorig_Spine1"] if mixamo else [&"J_Bip_C_Spine", &"J_Bip_C_Chest"],
		"head_top": &"mixamorig_HeadTop_End" if mixamo else &"J_Bip_C_Head",
		"support_clavicle": &"mixamorig_LeftShoulder" if mixamo else &"J_Bip_L_Shoulder",
		"support_arm": &"mixamorig_LeftArm" if mixamo else &"J_Bip_L_UpperArm",
	}
	crouch_modifier = CoverCrouchModifier.new()
	crouch_modifier.name = "CoverCrouch"
	if not crouch_modifier.setup(skeleton, bones, character_root.global_basis.z):
		crouch_modifier = null
		return
	skeleton.add_child(crouch_modifier)
	if is_instance_valid(arm_ik):
		skeleton.move_child(crouch_modifier, arm_ik.get_index())


func _configure_chain(
	index: int,
	bones: Array,
	target: Node3D,
	pole: Node3D,
) -> void:
	arm_ik.set_root_bone_name(index, bones[0])
	arm_ik.set_middle_bone_name(index, bones[1])
	arm_ik.set_end_bone_name(index, bones[2])
	arm_ik.set_target_node(index, arm_ik.get_path_to(target))
	arm_ik.set_pole_node(index, arm_ik.get_path_to(pole))


func _align_weapon_to_aim() -> void:
	# Runtime animations will provide this aiming basis. For the static proof,
	# keep +Z as the muzzle direction and +Y as weapon-up while the attachment
	# continues to inherit the right wrist's position.
	if not is_inside_tree() \
		or not is_instance_valid(character_root) or not character_root.is_inside_tree() \
		or not is_instance_valid(weapon_attachment) or not weapon_attachment.is_inside_tree() \
		or not is_instance_valid(weapon) or not weapon.is_inside_tree():
		return
	var desired_global_basis := character_root.global_basis * _rifle_local_basis()
	# The basis is rewritten every frame, so the presentation scale must be re-applied with it.
	weapon.basis = (weapon_attachment.global_basis.inverse() * desired_global_basis) * Basis.from_scale(Vector3.ONE * handling.scale)
	weapon.position = weapon_attachment.global_basis.inverse() * (desired_global_basis * grip_offset)


func _update_weapon_pose() -> void:
	if not is_instance_valid(skeleton):
		return
	_update_weapon_pose_inputs()
	if weapon_pose_modifier_controls_targets():
		return   # the WeaponPose modifier places the targets in the skeleton pass, from the real shoulder
	# Legacy path (editor preview, or the modifier switched off): the shoulder as the animation leaves it, which
	# does not include what the skeleton's modifiers do to it.
	var shoulder_index := skeleton.find_bone(right_arm_bones[0])
	apply_weapon_targets(skeleton.global_transform * skeleton.get_bone_global_pose(shoulder_index).origin)


func weapon_pose_modifier_controls_targets() -> bool:
	return weapon_pose_modifier != null and weapon_pose_modifier_enabled and not Engine.is_editor_hint()


## Everything the weapon pose needs that does not depend on where the shoulder is: the carry sway, and what the
## crouch and grip layers are told about the weapon.
func _update_weapon_pose_inputs() -> void:
	stock_marker.position = handling.stock_rear
	var moving := false
	# Non-tool animation controllers intentionally do not expose runtime state
	# while this rig is drawing its editor preview.
	if not Engine.is_editor_hint() and is_instance_valid(animation_controller):
		moving = animation_controller.current_state in [&"move", &"carry_move"]
	carry_motion_blend = move_toward(carry_motion_blend, 1.0 if moving else 0.0, get_process_delta_time() * 5.0)
	_carry_phase += get_process_delta_time() * TAU * 2.0
	var ready_grip := handling.lowered_grip + Vector3(0, 0.035, -0.02) * carry_motion_blend
	ready_grip.y += sin(_carry_phase) * 0.008 * carry_motion_blend
	_ready_grip_base = ready_grip
	if crouch_modifier != null:
		crouch_modifier.aim_lean_degrees = AIM_LEAN_DEGREES * weapon_blend()
		crouch_modifier.support_reach_degrees = SUPPORT_REACH_DEGREES * weapon_blend()
	if grip_modifier != null:
		var holding: bool = not (is_instance_valid(animation_controller) and animation_controller.current_state in [&"pickup", &"boarding", &"carry_idle", &"carry_move"])
		grip_modifier.curl = [SUPPORT_GRIP_CURL if holding else 0.0, TRIGGER_HAND_CURL if holding else 0.0]
		grip_modifier.orient_weight = 1.0 if holding else 0.0
		grip_modifier.weapon_basis = skeleton.global_basis.orthonormalized().inverse() * weapon.global_basis.orthonormalized()
		grip_modifier.trigger_pull = trigger_pull


## The shoulder-dependent half of the weapon pose: the stock pocket, both hand targets and the elbow poles, given
## the right shoulder's world position. One place for the formulas; the WeaponPose modifier calls it with the
## shoulder of the current skeleton pass, the legacy path with the animation-only shoulder.
## `chest_in_root` is the chest bone's orientation in the character-root frame, in THIS skeleton pass. The settled
## reference follows the chest every pass except while the chest kicks, when it is held: the weapon then turns by the
## chest's rotation since it settled. Standing, crouching and kneeling all share this; cover yaw and facing turn the
## root, so they never appear in it.
func update_torso_frame(chest_in_root: Basis, delta: float) -> void:
	if not torso_frame_enabled or Engine.is_editor_hint():
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
	shoulder_marker.position = character_root.to_local(shoulder_world) + shoulder_contact_offset
	var aimed_grip := shoulder_marker.position - torso_frame * (stock_contact_offset + grip_offset)
	# While crouched, the low-ready grip and the elbows travel with the chest: the shoulder moved
	# from where it stands when upright.
	if not _standing_shoulder_known:
		_standing_shoulder = shoulder_marker.position
		_standing_shoulder_known = true
	var body_offset := shoulder_marker.position - _standing_shoulder if crouch_modifier != null and crouch_modifier.depth > 0.002 else Vector3.ZERO
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
func apply_elbow_guidance(shoulders: Array, chest_world: Basis) -> void:
	if not elbow_guidance_enabled or Engine.is_editor_hint():
		return
	var blend := weapon_blend()
	if blend <= 0.0:
		return
	var poles: Array[Node3D] = [right_elbow_pole, left_elbow_pole]
	var guides: Array[Vector3] = [right_elbow_aim, left_elbow_aim]
	var wrists: Array[Vector3] = [right_hand_target.global_position, support_ik_target.global_position]
	var down := -chest_world.orthonormalized().y
	var swivels: Array[float] = [_elbow_swivel[0], _elbow_swivel[1]]
	if not _elbow_swivel_latched:
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
		poles[i].position = _pole_ready[i].lerp(parent.to_local(aimed_world), blend)


func _play_shot_feedback() -> void:
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
func _on_animation_state_changed(state_name: StringName) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(self, "aim_blend", 1.0 if state_name in [&"aim", &"shoot", &"shoot_left", &"shoot_right"] else 0.0, 0.28)
	if state_name in [&"shoot", &"shoot_left", &"shoot_right"]:
		_play_shot_feedback()
