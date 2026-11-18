@tool
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
## Render-only destination context. Normal units leave this unset.
var preview_cell := Vector3i(-1, -1, -1)
var preview_carrying := false
## Read-only world-space hints for hybrid pose fitting. Never applied as a root offset.
var last_cover_contact: Dictionary = {}
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
	return preview_carrying or (is_instance_valid(tactical_unit) and tactical_unit.is_carrying_unit())
const POSE_CONTEXT := preload("res://presentation/characters/runtime/tactical_pose_context.gd")
const TRAVERSAL_STATES := [&"vault", &"climb", &"descend"]
## States in which the sights are up.
const AIM_POSE_STATES: Array[StringName] = [&"aim", &"shoot", &"shoot_left", &"shoot_right"]
## Quiet states a held Aim may change. A shot, hit, defeat, move or traversal is never interrupted.
const AIM_SETTLE_STATES: Array[StringName] = [&"aim", &"rifle_idle", &"cover_low", &"cover_high"]
## After the committed Aim ends, the sights stay up this long so the rifle does not dip while the
## attack camera moves in before the shot. A shot or any other action takes over sooner.
const AIM_RELEASE_GRACE := 1.0
## Presentation-only mirror of the committed Aim: true while the sights should be up.
var _aim_held := false
var _aim_release_left := 0.0
var _return_generation := 0
var _team_accent: MeshInstance3D

func _ready() -> void:
	_build_character()
	_build_weapon_attachment()
	_build_arm_ik()
	_build_animation_controller()
	_build_team_accent()
	_apply_class_marker()
	skeleton.skeleton_updated.connect(_align_weapon_to_aim)
	animation_controller.state_changed.connect(_forward_state_change)
	await get_tree().process_frame
	if not is_inside_tree(): return
	await get_tree().process_frame
	if not is_inside_tree(): return
	_align_weapon_to_aim()

func setup(unit: TacticalUnit) -> void:
	tactical_unit = unit
	if is_node_ready():
		_apply_team_accent()
		_apply_class_marker()

## Chest band: a thin ring around the torso, riding the chest bone so it follows every pose.
const CLASS_MARKER_NAME := "ClassMarkerStripe"
const CLASS_MARKER_RADIUS := 0.165
const CLASS_MARKER_HEIGHT := 0.06
## Squeezes the round band to the torso's oval: narrower side to side, a little shallower front to back.
const CLASS_MARKER_FIT := Vector3(1.0, 1.0, 0.95)

## Paints (or removes) the class stripe from the unit's archetype. Presentation only.
func _apply_class_marker() -> void:
	var color := Color(0.0, 0.0, 0.0, 0.0)
	if is_instance_valid(tactical_unit):
		var definition := TacticalArchetypeCatalog.get_definition(tactical_unit.archetype_id)
		if definition:
			color = definition.marker_color
	set_class_marker(color)

func set_class_marker(color: Color) -> void:
	if not is_instance_valid(skeleton):
		return
	var existing := skeleton.get_node_or_null(CLASS_MARKER_NAME)
	if existing:
		existing.queue_free()
	if color.a <= 0.0:
		return
	var bone_name := &"mixamorig_Spine2" if skeleton.find_bone(&"mixamorig_Hips") >= 0 else &"J_Bip_C_Chest"
	if skeleton.find_bone(bone_name) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = CLASS_MARKER_NAME
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	var band := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = CLASS_MARKER_RADIUS
	tube.bottom_radius = CLASS_MARKER_RADIUS
	tube.height = CLASS_MARKER_HEIGHT
	tube.cap_top = false
	tube.cap_bottom = false
	band.mesh = tube
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = material
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attachment.add_child(band)
	# The skeleton sits under a scaled model: counter that scale so the band keeps its size in metres.
	# The chest bone's own axes are not "up", so once the pose has settled, stand the band upright and at
	# true size in the character's frame. It still rides the bone through every later pose.
	await get_tree().process_frame
	if is_instance_valid(band) and band.is_inside_tree() and is_inside_tree():
		band.global_basis = character_root.global_basis * Basis.from_scale(CLASS_MARKER_FIT)

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
	var cell := preview_cell if preview_cell != Vector3i(-1, -1, -1) else tactical_unit.grid_position if is_instance_valid(tactical_unit) else Vector3i(-1, -1, -1)
	if is_instance_valid(presentation_grid) and cell != Vector3i(-1, -1, -1):
		last_cover_contact = POSE_CONTEXT.cover_at(presentation_grid, cell, global_basis.z)
	else:
		last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	return last_cover_contact

## The Aim action committed: bring the sights up now. The pose then follows the committed
## is_aiming flag (see _sync_aim_hold), so replays and AI units behave the same.
func present_aim() -> void:
	if _carrying(): return
	_aim_held = true
	_aim_release_left = AIM_RELEASE_GRACE
	present_idle()

## Reads committed state only; never writes it.
func _aim_should_hold() -> bool:
	return is_instance_valid(tactical_unit) and tactical_unit.tactical_state != null and tactical_unit.tactical_state.is_aiming \
		and not tactical_unit.is_moving and not _carrying()

func _aim_target(state_name: StringName) -> float:
	return 1.0 if state_name in AIM_POSE_STATES or _aim_held else 0.0

func _retarget_aim_blend() -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(self, "aim_blend", _aim_target(get_presentation_state()), 0.28)

## Keeps the sights up for as long as the committed Aim lasts: until its attack, an action that
## cancels it, or the next activation. Never interrupts a shot, hit, defeat, move or traversal.
func _sync_aim_hold(delta: float) -> void:
	var state := get_presentation_state()
	if _aim_should_hold():
		_aim_release_left = AIM_RELEASE_GRACE
		if not _aim_held:
			_aim_held = true
			if state in AIM_SETTLE_STATES: _settle_aim_pose(state)
		return
	if not _aim_held:
		return
	_aim_release_left -= delta
	# Once the unit has moved on to a shot or any other action, the hold is simply over.
	if _aim_release_left <= 0.0 or state not in AIM_SETTLE_STATES:
		_aim_held = false
		if state in AIM_SETTLE_STATES: _settle_aim_pose(state)
		else: _retarget_aim_blend()

## Low cover: crouch only as deep as the cover is tall (never beyond what a person can), turned
## with the back to the wall while hiding, and facing the wall, eyes just over the top, to aim.
## High cover (standing behind a full wall): a slight wary bend of the knees with the back to the
## wall, turning side-on to peek along it when aiming. In both, the rifle stays in its relaxed carry
## until she aims or shoots. Presentation only.
const COVER_HEAD_CLEARANCE := 0.05
const COVER_EYE_CLEARANCE := 0.05
const EYE_BELOW_HEAD_TOP := 0.12
const CROUCH_SPEED := 1.1
const HIDE_YAW_DEGREES := -150.0
## Standing behind full cover: how far the knees bend, and how side-on she turns to peek.
const HIGH_COVER_CROUCH_DEPTH := 0.12
const HIGH_COVER_AIM_CROUCH_DEPTH := 0.04
const HIGH_COVER_AIM_YAW_DEGREES := -90.0
const COVER_TURN_DEGREES_PER_SECOND := 320.0
const KNEEL_BLEND_RANGE := 0.08
const KNEEL_SPEED := 2.5
var _crouch_depth := 0.0
var _kneel := 0.0
var _cover_yaw := 0.0

## Which cover the pose is in right now: LOW or FULL, or NONE when no cover pose applies.
func _cover_kind() -> MapCellData.CoverType:
	var type: int = last_cover_contact.get("type", MapCellData.CoverType.NONE)
	var state := get_presentation_state()
	if state == &"cover_low" and type == MapCellData.CoverType.LOW:
		return MapCellData.CoverType.LOW
	if state == &"cover_high" and type == MapCellData.CoverType.FULL:
		return MapCellData.CoverType.FULL
	return MapCellData.CoverType.NONE

## Depth the cover asks for, before the human limit. 0 when not behind cover.
func _cover_crouch_request() -> float:
	if crouch_modifier == null:
		return 0.0
	var kind := _cover_kind()
	if kind == MapCellData.CoverType.FULL:
		return lerpf(HIGH_COVER_CROUCH_DEPTH, HIGH_COVER_AIM_CROUCH_DEPTH, aim_blend)
	if kind != MapCellData.CoverType.LOW:
		return 0.0
	var cover_height: float = last_cover_contact.get("height", 0.0)
	var hide := crouch_modifier.standing_head_height - (cover_height - COVER_HEAD_CLEARANCE)
	var peek := crouch_modifier.standing_head_height - EYE_BELOW_HEAD_TOP - (cover_height + COVER_EYE_CLEARANCE)
	return maxf(lerpf(hide, peek, aim_blend), 0.0)

func _cover_crouch_target() -> float:
	return crouch_modifier.clamp_depth(_cover_crouch_request()) if crouch_modifier != null else 0.0

func _sync_cover_crouch(delta: float) -> void:
	if crouch_modifier == null:
		return
	var kind := _cover_kind()
	_crouch_depth = move_toward(_crouch_depth, _cover_crouch_target(), CROUCH_SPEED * delta)
	crouch_modifier.depth = _crouch_depth
	# Cover lower than the deepest natural crouch can hide behind: go down on one knee.
	var kneel_target := clampf((_cover_crouch_request() - crouch_modifier.max_depth) / KNEEL_BLEND_RANGE, 0.0, 1.0)
	_kneel = move_toward(_kneel, kneel_target, KNEEL_SPEED * delta)
	crouch_modifier.kneel = _kneel
	var yaw_target := 0.0
	if kind == MapCellData.CoverType.LOW:
		yaw_target = deg_to_rad(HIDE_YAW_DEGREES) * (1.0 - aim_blend)
	elif kind == MapCellData.CoverType.FULL:
		yaw_target = lerpf(deg_to_rad(HIDE_YAW_DEGREES), deg_to_rad(HIGH_COVER_AIM_YAW_DEGREES), aim_blend)
	_cover_yaw = rotate_toward(_cover_yaw, yaw_target, deg_to_rad(COVER_TURN_DEGREES_PER_SECOND) * delta)
	character_root.rotation.y = _cover_yaw

func _settle_aim_pose(state: StringName) -> void:
	if state in [&"cover_low", &"cover_high"]:
		# Keep the cover pose; only the weapon comes up or goes down.
		_retarget_aim_blend()
	else:
		present_idle()

func present_idle() -> void:
	_return_generation += 1
	if _carrying():
		_play(&"carry_idle")
		return
	var cover := _cover_context()
	if cover.type == MapCellData.CoverType.NONE:
		_play(&"aim" if (_aim_held or _aim_should_hold()) else &"rifle_idle")
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

func _process(delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree():
		return
	_sync_aim_hold(delta)
	_sync_cover_crouch(delta)
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
	_pose_tween.tween_property(self, "aim_blend", _aim_target(state_name), 0.28)
	if state_name in [&"shoot", &"shoot_left", &"shoot_right"]:
		_play_shot_feedback()
