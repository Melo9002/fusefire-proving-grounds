extends "res://art/characters/vroid_proof/demo/vroid_weapon_ik_demo.gd"
class_name UnitVisualAdapter

signal presentation_state_changed(state_name: StringName)

@export var camera_focus_anchor := Vector3(0.0, 1.05, 0.0)
@export var camera_eye_anchor := Vector3(0.0, 1.5, 0.0)
@export var camera_body_height := 1.6

func get_camera_focus() -> Vector3:
	return to_global(camera_focus_anchor)

func get_camera_eye() -> Vector3:
	return to_global(camera_eye_anchor)

func get_camera_height() -> float:
	return maxf(0.2, camera_body_height * global_basis.y.length())

var tactical_unit: TacticalUnit
var _last_parent_position := Vector3.ZERO
var _return_generation := 0
var _team_accent: MeshInstance3D

const PLAYER_ACCENT := Color(0.05, 0.65, 1.0, 1.0)
const ALLY_ACCENT := Color(0.2, 1.0, 0.35, 1.0)
const ENEMY_ACCENT := Color(1.0, 0.12, 0.08, 1.0)
const NEUTRAL_ACCENT := Color(0.85, 0.85, 0.85, 1.0)

func _ready() -> void:
	_build_character()
	_build_weapon_attachment()
	_build_arm_ik()
	_build_animation_controller()
	_build_team_accent()
	skeleton.skeleton_updated.connect(_align_weapon_to_demo_aim)
	animation_controller.state_changed.connect(_forward_state_change)
	_last_parent_position = get_parent_node_3d().global_position
	await get_tree().process_frame
	await get_tree().process_frame
	_align_weapon_to_demo_aim()

func setup(unit: TacticalUnit) -> void:
	tactical_unit = unit
	if is_node_ready():
		_apply_team_accent()

func _build_team_accent() -> void:
	_team_accent = MeshInstance3D.new()
	_team_accent.name = "TeamAccentRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.31
	ring.outer_radius = 0.37
	ring.rings = 12
	ring.ring_segments = 24
	_team_accent.mesh = ring
	_team_accent.position = Vector3(0.0, 0.025, 0.0)
	_team_accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_team_accent)
	_apply_team_accent()

func _apply_team_accent() -> void:
	if not is_instance_valid(_team_accent):
		return
	var accent := NEUTRAL_ACCENT
	if is_instance_valid(tactical_unit):
		match tactical_unit.faction:
			TacticalUnit.Faction.PLAYER: accent = PLAYER_ACCENT
			TacticalUnit.Faction.ALLY: accent = ALLY_ACCENT
			TacticalUnit.Faction.ENEMY: accent = ENEMY_ACCENT
	var material := StandardMaterial3D.new()
	material.albedo_color = accent
	material.emission_enabled = true
	material.emission = accent
	material.emission_energy_multiplier = 2.2
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_team_accent.material_override = material

func _exit_tree() -> void:
	# Skeleton modifiers can emit once more while their hierarchy is being
	# removed. Disconnect before descendants lose legal global transforms.
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_align_weapon_to_demo_aim):
		skeleton.skeleton_updated.disconnect(_align_weapon_to_demo_aim)

func present_move() -> void:
	_play(&"move")

func present_idle() -> void:
	_play(&"rifle_idle")

func present_attack(target_world_position: Vector3) -> void:
	face_world_position(target_world_position)
	_play(&"shoot")
	_return_to_idle_after(0.34)

func present_hit() -> void:
	_play(&"hit")
	_return_to_idle_after(0.58)

func present_defeat() -> void:
	_return_generation += 1
	_play(&"defeat")

func face_world_position(world_position: Vector3) -> void:
	var flat_direction := world_position - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.0001:
		# This imported rig and its rifle are authored facing +Z.
		rotation.y = atan2(flat_direction.x, flat_direction.z)

func get_presentation_state() -> StringName:
	return animation_controller.current_state if is_instance_valid(animation_controller) else &"setup"

func _process(_delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree():
		return
	_update_weapon_pose()
	var parent_position := get_parent_node_3d().global_position
	var travel := parent_position - _last_parent_position
	travel.y = 0.0
	# Placement and debug teleportation are not walking. In particular, spawn
	# placement happens after _ready and must not overwrite initial facing.
	if is_instance_valid(tactical_unit) and tactical_unit.is_moving and travel.length_squared() > 0.000001:
		face_world_position(parent_position + travel)
	_last_parent_position = parent_position

func _update_weapon_pose() -> void:
	super._update_weapon_pose()

func _play(state_name: StringName) -> void:
	if is_instance_valid(animation_controller):
		animation_controller.play(state_name)

func _return_to_idle_after(seconds: float) -> void:
	_return_generation += 1
	var generation := _return_generation
	await get_tree().create_timer(seconds).timeout
	if generation != _return_generation:
		return
	if is_instance_valid(tactical_unit) and tactical_unit.is_moving:
		_play(&"move")
	else:
		_play(&"rifle_idle")

func _forward_state_change(state_name: StringName) -> void:
	presentation_state_changed.emit(state_name)

func _on_animation_state_changed(state_name: StringName) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(self, "aim_blend", 1.0 if state_name in [&"aim", &"shoot"] else 0.0, 0.28)
	if state_name == &"shoot":
		_play_shot_feedback()
