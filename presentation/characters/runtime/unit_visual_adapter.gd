extends "res://presentation/characters/runtime/character_rig.gd"
class_name UnitVisualAdapter

signal presentation_state_changed(state_name: StringName)

const TeamPaletteData := preload("res://presentation/team_presentation_palette.gd")

@export_group("Team Presentation")
## Shared faction colors and ground-ring appearance.
@export var team_palette: TeamPaletteData = preload("res://presentation/team_presentation_palette.tres")

@export_group("Camera Anchors")
@export var camera_focus_anchor := Vector3(0.0, 1.05, 0.0)
@export var camera_eye_anchor := Vector3(0.0, 1.5, 0.0)
@export var camera_body_height := 1.6
@export_group("Locomotion")
## Degrees per second when following a path. Attacks still face their target immediately.
@export_range(90.0, 1080.0) var turn_speed_degrees := 360.0
## Metres travelled per full left/right step cycle. Tune alongside the move clip.
@export_range(0.5, 4.0) var stride_length := 1.6
@export_group("Action Timing")
## Delay before pickup returns to the appropriate idle pose.
@export_range(0.0, 3.0, 0.01, "suffix:s") var pickup_return_seconds := 0.6
## Delay before traversal landing returns to locomotion or idle.
@export_range(0.0, 3.0, 0.01, "suffix:s") var landing_return_seconds := 0.3
## Delay before a shot returns to the appropriate ready pose.
@export_range(0.0, 3.0, 0.01, "suffix:s") var shoot_return_seconds := 0.34
## Delay before hit reaction returns to the appropriate ready pose.
@export_range(0.0, 3.0, 0.01, "suffix:s") var hit_return_seconds := 0.58
@export_group("")

func get_camera_focus() -> Vector3:
	return to_global(camera_focus_anchor)

func get_camera_eye() -> Vector3:
	return to_global(camera_eye_anchor)

func get_camera_height() -> float:
	return maxf(0.2, camera_body_height * global_basis.y.length())

var tactical_unit: TacticalUnit
var presentation_grid: GridManager
var _segment_state: StringName = &"move"
var _passenger: Node3D

func present_pickup() -> void:
	arm_ik.active = false
	weapon.reparent(character_root)
	weapon.position = stowed_weapon_position
	weapon.rotation_degrees = stowed_weapon_angles_degrees
	if not is_instance_valid(_passenger):
		_passenger = preload("res://presentation/characters/runtime/rescue_passenger.gd").new()
		_passenger.name = "RescuePassenger"
		character_root.add_child(_passenger)
		_passenger.position = passenger_position
	_play(&"pickup")
	_return_to_idle_after(pickup_return_seconds)

func present_boarding() -> void:
	_return_generation += 1
	_play(&"boarding")
	if is_instance_valid(_passenger):
		var tween := create_tween()
		tween.tween_property(_passenger, "scale", Vector3.ONE * 0.01, 0.55)

func _carrying() -> bool:
	return is_instance_valid(tactical_unit) and tactical_unit.is_carrying_unit()
const POSE_CONTEXT := preload("res://presentation/characters/runtime/tactical_pose_context.gd")
const TRAVERSAL_STATES := [&"vault", &"climb", &"descend"]
var _return_generation := 0
var _team_accent: MeshInstance3D

func _ready() -> void:
	_build_character()
	_build_weapon_attachment()
	_build_arm_ik()
	_build_animation_controller()
	_build_team_accent()
	skeleton.skeleton_updated.connect(_align_weapon_to_aim)
	animation_controller.state_changed.connect(_forward_state_change)
	await get_tree().process_frame
	await get_tree().process_frame
	_align_weapon_to_aim()

func setup(unit: TacticalUnit) -> void:
	tactical_unit = unit
	if is_node_ready():
		_apply_team_accent()

func _build_team_accent() -> void:
	_team_accent = MeshInstance3D.new()
	_team_accent.name = "TeamAccentRing"
	var ring := TorusMesh.new()
	ring.inner_radius = team_palette.inner_radius
	ring.outer_radius = team_palette.outer_radius
	ring.rings = team_palette.radial_segments
	ring.ring_segments = team_palette.ring_segments
	_team_accent.mesh = ring
	_team_accent.position = Vector3(0.0, team_palette.height, 0.0)
	_team_accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_team_accent)
	_apply_team_accent()

func _apply_team_accent() -> void:
	if not is_instance_valid(_team_accent):
		return
	var accent: Color = team_palette.neutral
	if is_instance_valid(tactical_unit):
		match tactical_unit.faction:
			TacticalUnit.Faction.PLAYER: accent = team_palette.player
			TacticalUnit.Faction.ALLY: accent = team_palette.ally
			TacticalUnit.Faction.ENEMY: accent = team_palette.enemy
	var material := StandardMaterial3D.new()
	material.albedo_color = accent
	material.emission_enabled = true
	material.emission = accent
	material.emission_energy_multiplier = team_palette.emission_energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_team_accent.material_override = material

func _exit_tree() -> void:
	# Skeleton modifiers can emit once more while their hierarchy is being
	# removed. Disconnect before descendants lose legal global transforms.
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_align_weapon_to_aim):
		skeleton.skeleton_updated.disconnect(_align_weapon_to_aim)

func present_move() -> void:
	_return_generation += 1
	_segment_state = &"move"
	_play(&"carry_move" if _carrying() else &"move")

func present_path_segment(state_name: StringName) -> void:
	if state_name == _segment_state:
		return
	var was_traversing := _segment_state in TRAVERSAL_STATES
	_segment_state = state_name
	_return_generation += 1
	if was_traversing and state_name == &"move":
		_play(&"land")
		_return_to_idle_after(landing_return_seconds)
	else:
		_play(&"carry_move" if state_name == &"move" and _carrying() else state_name)

func present_movement_end() -> void:
	if _segment_state in TRAVERSAL_STATES:
		_play(&"land")
		_return_to_idle_after(landing_return_seconds)
	else:
		present_idle()

func _cover_context() -> Dictionary:
	if is_instance_valid(presentation_grid) and is_instance_valid(tactical_unit):
		return POSE_CONTEXT.cover_at(presentation_grid, tactical_unit.grid_position, global_basis.z)
	return {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}

func present_idle() -> void:
	_return_generation += 1
	if _carrying():
		_play(&"carry_idle")
		return
	var cover := _cover_context()
	if cover.type == MapCellData.CoverType.NONE:
		_play(&"rifle_idle")
	else:
		face_world_position(global_position + cover.direction)
		_play(&"cover_low" if cover.type == MapCellData.CoverType.LOW else &"cover_high")

func update_locomotion(world_velocity: Vector3, delta: float) -> void:
	var flat := Vector3(world_velocity.x, 0.0, world_velocity.z)
	if flat.length_squared() < 0.000001:
		return
	var desired_yaw := atan2(flat.x, flat.z)
	global_rotation.y = rotate_toward(global_rotation.y, desired_yaw, deg_to_rad(turn_speed_degrees) * delta)
	# Tactical paths currently mean "turn and advance." Choosing a clip from the
	# partially rotated local basis made an ordinary forward run briefly select a
	# strafe clip during turns. Keep directional clips available for explicit
	# future movement styles and the workbench; path-following intent is forward.
	animation_controller.set_locomotion(Vector2(0.0, 1.0), flat.length() / stride_length)

func present_attack(target_world_position: Vector3) -> void:
	var cover := _cover_context()
	face_world_position(target_world_position)
	var shot := &"shoot"
	if cover.type == MapCellData.CoverType.FULL:
		# Visual lean only; the combat evaluator has already resolved the shot.
		shot = &"shoot_left" if global_basis.x.dot(cover.direction) >= 0.0 else &"shoot_right"
	_play(shot)
	_return_to_idle_after(shoot_return_seconds)

func present_hit() -> void:
	_play(&"hit")
	_return_to_idle_after(hit_return_seconds)

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
	# Facing and cadence are supplied by TacticalUnit before each movement step.

func _update_weapon_pose() -> void:
	if _carrying(): return
	super._update_weapon_pose()

func _align_weapon_to_aim() -> void:
	if _carrying(): return
	super._align_weapon_to_aim()

func _play(state_name: StringName) -> void:
	if is_instance_valid(animation_controller):
		animation_controller.play(state_name)

func _return_to_idle_after(seconds: float) -> void:
	_return_generation += 1
	var generation := _return_generation
	await get_tree().create_timer(seconds, false).timeout
	if generation != _return_generation:
		return
	if is_instance_valid(tactical_unit) and tactical_unit.is_moving:
		_play(&"carry_move" if _segment_state == &"move" and _carrying() else _segment_state)
	else:
		present_idle()

func _forward_state_change(state_name: StringName) -> void:
	presentation_state_changed.emit(state_name)

func _on_animation_state_changed(state_name: StringName) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(self, "aim_blend", 1.0 if state_name in [&"aim", &"shoot", &"shoot_left", &"shoot_right"] else 0.0, 0.28)
	if state_name in [&"shoot", &"shoot_left", &"shoot_right"]:
		_play_shot_feedback()
