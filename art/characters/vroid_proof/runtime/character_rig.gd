extends Node3D

const CHARACTER_SCENE := preload("res://art/characters/vroid_proof/models/vroid_test_runtime.glb")
const WEAPON_SCENE := preload("res://art/weapons/aug/models/aug_runtime_socketed.glb")
const ANIMATION_CONTROLLER := preload("res://art/characters/vroid_proof/runtime/character_animation_controller.gd")

const RIGHT_ARM := [&"J_Bip_R_UpperArm", &"J_Bip_R_LowerArm", &"J_Bip_R_Hand"]
const LEFT_ARM := [&"J_Bip_L_UpperArm", &"J_Bip_L_LowerArm", &"J_Bip_L_Hand"]

@onready var character_root: Node3D = $Character
@onready var right_hand_target: Marker3D = $Character/IKTargets/RightHandTarget
@onready var right_elbow_pole: Marker3D = $Character/IKTargets/RightElbowPole
@onready var left_elbow_pole: Marker3D = $Character/IKTargets/LeftElbowPole

var skeleton: Skeleton3D
var arm_ik: TwoBoneIK3D
var weapon_attachment: BoneAttachment3D
var weapon: Node3D
var support_hand_target: Node3D
var muzzle_socket: Node3D
var muzzle_flash: MeshInstance3D
var ik_enabled := true
var animation_controller: Node
var _shot_feedback_generation := 0
var aim_blend := 0.0
var recoil := 0.0
var _pose_tween: Tween
var _recoil_tween: Tween
const GRIP_OFFSET := Vector3(0.0, -0.035, 0.025)
# Approximate center of the AUG optic in weapon coordinates, checked in the demo.
const SIGHT_OFFSET := Vector3(0.0, 0.13, -0.10)
@export_group("Animation Clips")
## Edit this shared library through animations/animation_workbench.tscn. Missing clips use generated defaults.
@export var clip_library: AnimationLibrary = preload("res://art/characters/vroid_proof/animations/prototype_clips.tres")
@export_group("Weapon Contact")
## Metres in weapon-local coordinates; moves the rifle relative to the firing wrist.
@export var grip_offset := GRIP_OFFSET
@export var sight_offset := SIGHT_OFFSET
# Editable contact points, in rifle-local and right-upper-arm-local metres.
@export var stock_contact_offset := Vector3(0.0, 0.065, -0.28)
@export var shoulder_contact_offset := Vector3(0.035, 0.015, 0.055)
var stock_marker: Marker3D
var shoulder_marker: Marker3D
var sight_marker: Marker3D
var support_ik_target: Marker3D
@export_group("Low Ready")
@export var carry_angles_degrees := Vector3(35, 40, -8)
@export var carry_grip_position := Vector3(-0.08, 1.16, 0.15)
@export_group("Rescue Carry")
## Positions are in Character-local metres; stowed angles are degrees.
@export var passenger_position := Vector3(0, 1.38, -0.16)
@export var stowed_weapon_position := Vector3(0.26, 0.8, -0.24)
@export var stowed_weapon_angles_degrees := Vector3(0, 0, rad_to_deg(-0.65))
@export_group("")
var carry_motion_blend := 0.0
var _carry_phase := 0.0

func _rifle_local_basis() -> Basis:
	var carry_rotation := Quaternion.from_euler(carry_angles_degrees * (PI / 180.0))
	return Basis(carry_rotation.slerp(Quaternion.IDENTITY, aim_blend))


func _build_character() -> void:
	var model := CHARACTER_SCENE.instantiate() as Node3D
	character_root.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null, "VRoid runtime model must contain Skeleton3D")


func _build_weapon_attachment() -> void:
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "RightHandWeaponSocket"
	weapon_attachment.bone_name = RIGHT_ARM[2]
	skeleton.add_child(weapon_attachment)

	weapon = WEAPON_SCENE.instantiate() as Node3D
	weapon.name = "AUG"
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
	sight_marker.position = sight_offset
	weapon.add_child(sight_marker)
	stock_marker = Marker3D.new()
	stock_marker.name = "ButtstockContact"
	stock_marker.position = stock_contact_offset
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
	_configure_chain(0, RIGHT_ARM, right_hand_target, right_elbow_pole)
	_configure_chain(1, LEFT_ARM, support_ik_target, left_elbow_pole)
	arm_ik.active = true


func _build_animation_controller() -> void:
	animation_controller = ANIMATION_CONTROLLER.new()
	animation_controller.name = "VerticalSliceController"
	animation_controller.clip_library = clip_library
	add_child(animation_controller)
	animation_controller.state_changed.connect(_on_animation_state_changed)
	animation_controller.setup(skeleton, character_root)


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
	weapon.basis = weapon_attachment.global_basis.inverse() * desired_global_basis
	weapon.position = weapon_attachment.global_basis.inverse() * (desired_global_basis * grip_offset)


func _update_weapon_pose() -> void:
	if not is_instance_valid(skeleton):
		return
	# Use the animated shoulder origin (unaffected by the arm IK rotations).
	# The chest's shot animation therefore carries the rifle through recoil.
	var shoulder_index := skeleton.find_bone(RIGHT_ARM[0])
	var shoulder_world := skeleton.global_transform * skeleton.get_bone_global_pose(shoulder_index).origin
	shoulder_marker.position = character_root.to_local(shoulder_world) + shoulder_contact_offset
	stock_marker.position = stock_contact_offset
	var aimed_grip := shoulder_marker.position - stock_contact_offset - grip_offset
	var moving: bool = is_instance_valid(animation_controller) and animation_controller.current_state in [&"move", &"carry_move"]
	carry_motion_blend = move_toward(carry_motion_blend, 1.0 if moving else 0.0, get_process_delta_time() * 5.0)
	_carry_phase += get_process_delta_time() * TAU * 2.0
	var ready_grip := carry_grip_position + Vector3(0, 0.035, -0.02) * carry_motion_blend
	ready_grip.y += sin(_carry_phase) * 0.008 * carry_motion_blend
	# Only a few millimetres of stock compression; avoid the old 6.5 cm slide
	# through the shoulder. Upper-body animation supplies the visible kick.
	right_hand_target.position = ready_grip.lerp(aimed_grip, aim_blend) + Vector3(0, 0, -recoil * 0.08)
	right_elbow_pole.position = Vector3(-0.26, 0.93, -0.04).lerp(Vector3(-0.42, 1.18, -0.08), aim_blend)
	left_elbow_pole.position = Vector3(0.27, 0.94, 0.10).lerp(Vector3(0.38, 1.03, 0.08), aim_blend)
	# Predict the support marker in the current pose before solving either arm.
	# Reading the attached weapon here would use last frame's wrist transform.
	if is_instance_valid(support_ik_target):
		var support_offset := weapon.to_local(support_hand_target.global_position)
		support_ik_target.position = right_hand_target.position + _rifle_local_basis() * (grip_offset + support_offset)


func _play_shot_feedback() -> void:
	_shot_feedback_generation += 1
	var generation := _shot_feedback_generation
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	recoil = 0.065
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(self, "recoil", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	muzzle_flash.visible = true
	await get_tree().create_timer(0.075).timeout
	if generation == _shot_feedback_generation:
		muzzle_flash.visible = false
func _on_animation_state_changed(state_name: StringName) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(self, "aim_blend", 1.0 if state_name in [&"aim", &"shoot", &"shoot_left", &"shoot_right"] else 0.0, 0.28)
	if state_name in [&"shoot", &"shoot_left", &"shoot_right"]:
		_play_shot_feedback()


