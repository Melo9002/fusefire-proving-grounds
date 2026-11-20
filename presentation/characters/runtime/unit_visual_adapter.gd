@tool
extends "res://presentation/characters/runtime/character_rig.gd"
class_name UnitVisualAdapter

signal presentation_state_changed(state_name: StringName)
## The shot is shown: muzzle flash and recoil begin together. `timeline` is the attack's record (attack_timeline).
signal shot_fired(timeline: Dictionary)
## The attack presentation is over. fired is false when it was cancelled by a higher-priority presentation.
signal attack_sequence_ended(fired: bool)

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
@export_group("Action Timing")
## Delay before pickup returns to the appropriate idle pose.
@export_range(0.0, 3.0, 0.01, "suffix:s") var pickup_return_seconds := 0.6
## Delay before traversal landing returns to locomotion or idle.
@export_range(0.0, 3.0, 0.01, "suffix:s") var landing_return_seconds := 0.3
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
var _locomotion_speed := 0.0
var _locomotion_heading_rate := 0.0
var _locomotion_age := 1.0
## Where the rescued actor lies, while the carrier is still walking to it (see present_pickup); INF when no pickup is waiting.
var _pending_pickup_world := Vector3.INF
var _pending_lying_basis = null
var _lying_body: Node3D
## The way an incapacitated unit lies, degrees about the vertical from the way it faces (across its facing, head to its right).
const INCAPACITATED_YAW_DEGREES := 90.0
var presentation_grid: GridManager
## Render-only destination context. Normal units leave this unset.
var preview_cell := Vector3i(-1, -1, -1)
var preview_carrying := false
## Read-only world-space hints for hybrid pose fitting. Never applied as a root offset.
var last_cover_contact: Dictionary = {}
var _segment_state: StringName = &"move"

## The carrier has just taken `passenger_world` (the rescued actor's place, which the tactical layer has hidden the actor at).
## The carrier faces it and the shared timeline (RescueInteraction) lifts a visual passenger from there into the carry. Without a
## place there is nothing to lift from: the passenger appears across the shoulders as before.
func present_pickup(passenger_world := Vector3.INF, lying_orientation = null) -> void:
	_cancel_attack_sequence()
	_return_generation += 1
	if not rescue_interaction_finished.is_connected(_on_rescue_interaction_finished):
		rescue_interaction_finished.connect(_on_rescue_interaction_finished)
	if passenger_world.is_finite() and is_instance_valid(tactical_unit) and (tactical_unit.is_moving or _flat_distance_to(passenger_world) > rescue_interaction.max_step + rescue_interaction.stand_off + 0.3):
		# The tactical layer decides the rescue when the move is COMMITTED, before the carrier's body has walked there (the move's presentation
		# starts after). The lift is shown on arrival (present_movement_end); until then it is an ordinary walk with the rifle in hand and nobody on
		# its shoulders. Otherwise the passenger would "fly" to a carrier still metres away.
		_pending_pickup_world = passenger_world
		_pending_lying_basis = lying_orientation
		return
	if passenger_world.is_finite():
		face_world_position(passenger_world)
		begin_pickup(passenger_world, lying_orientation)
		return
	begin_carry()
	_play(&"pickup")
	_return_to_idle_after(pickup_return_seconds)

## A pickup or release has run out: carry on in whichever loaded state the unit is in.
func _on_rescue_interaction_finished(kind: int) -> void:
	if kind == RescueInteraction.Kind.PICKUP:
		if is_instance_valid(tactical_unit) and tactical_unit.is_moving:
			_play(&"carry_move")
		else:
			present_idle()

## The tactical layer has put the passenger down (the carrier fell): drop the visual one at once, take the rifle back and leave
## the rest to the revealed actor. Safe in any phase of a pickup or release.
func present_carry_released() -> void:
	_pending_pickup_world = Vector3.INF
	_return_generation += 1
	end_carry()
	if is_instance_valid(animation_controller) and animation_controller.current_state in [&"pickup", &"carry_idle", &"carry_move", &"boarding"]:
		present_idle()

func present_boarding() -> void:
	_pending_pickup_world = Vector3.INF
	_cancel_attack_sequence()
	finish_interaction_now()
	_return_generation += 1
	_play(&"boarding")
	if is_instance_valid(carry_passenger):
		var tween := create_tween()
		tween.tween_property(carry_passenger, "presence", 0.01, 0.55)

func _flat_distance_to(world: Vector3) -> float:
	return Vector2(world.x - global_position.x, world.z - global_position.z).length()

## INCAPACITATED PRESENTATION. A unit that is awaiting rescue (TacticalUnit.awaiting_rescue, set by the ObjectiveManager from the rescue objective)
## is shown lying on its back where it is: its standing rig and rifle are hidden and a passive body in the pickup's own lying pose takes their place.
## No idle, no weapon, no locomotion. The state is the tactical flag's, so it lasts until the objective changes it (a carrier lifts it, or it is
## recovered after the carrier fell). Presentation only: the actor stays one actor.
func present_incapacitated(on: bool) -> void:
	if on == is_instance_valid(_lying_body):
		return
	if on:
		_cancel_attack_sequence()
		_return_generation += 1
		_pending_pickup_world = Vector3.INF
		character_root.visible = false
		_lying_body = RESCUE_PASSENGER.new()
		_lying_body.name = "IncapacitatedBody"
		add_child(_lying_body)
		_lying_body.build(character_scene, character_scale)
		_lying_body.lie_on_ground(Vector3(0.0, _lying_ground_height(), 0.0), deg_to_rad(INCAPACITATED_YAW_DEGREES))
	else:
		remove_child(_lying_body)
		_lying_body.free()
		_lying_body = null
		character_root.visible = true
		present_idle()

func is_incapacitated() -> bool:
	return is_instance_valid(_lying_body)

## The world orientation the body lies in, for the pickup to start from; null when this unit is not lying.
func lying_basis() -> Variant:
	if not is_instance_valid(_lying_body):
		return null
	return _lying_body.global_basis.orthonormalized()

func _lying_ground_height() -> float:
	return rescue_interaction.ground_height

func _moving_now() -> bool:
	return is_instance_valid(tactical_unit) and tactical_unit.is_moving

func pickup_pending() -> bool:
	return _pending_pickup_world.is_finite()

func _carrying() -> bool:
	return preview_carrying or (is_instance_valid(tactical_unit) and tactical_unit.is_carrying_unit() and not pickup_pending())
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

## Attack presentation: Raise -> Align -> Fire -> Recover -> Release. The tactical attack is already resolved
## when this runs; it only stages that outcome. Time is the sum of frame deltas, never wall time, so the
## sequence depends on what was presented, not on how fast the machine ran.
enum AttackPhase { NONE, RAISE, ALIGN, FIRE, RECOVER, RELEASE }
const ATTACK_SOURCE := &"attack"
var attack_phase := AttackPhase.NONE
## Record of the latest attack: times (presentation seconds), phases, aim blend and muzzle error at the shot.
var attack_timeline: Dictionary = {}
var _presentation_clock := 0.0
var _attack_shot_state := &"shoot"
var _recover_left := 0.0
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
	finish_interaction_now()
	_cancel_attack_sequence()
	_return_generation += 1
	_segment_state = &"move"
	_play(&"carry_move" if _carrying() else &"move")

func present_path_segment(state_name: StringName) -> void:
	finish_interaction_now()
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
	if pickup_pending():
		var world := _pending_pickup_world
		_pending_pickup_world = Vector3.INF
		present_pickup(world, _pending_lying_basis)
		return
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
	return WeaponReadiness.blend_for(requested_readiness(state_name), handling)

## The level the unit is asking for: the highest of any request (an attack, later a Guard), the aim
## stance, and a held Aim. A carrier holds nothing.
func requested_readiness(state_name: StringName = &"") -> WeaponReadiness.Level:
	if _carrying():
		return WeaponReadiness.Level.STOWED
	if state_name == &"":
		state_name = get_presentation_state()
	var level := readiness.requested()
	if state_name in AIM_POSE_STATES or _aim_held:
		level = WeaponReadiness.Level.AIMED
	return level

## Sustained readiness: a source (a future Guard, say) asks for a level and holds it until it releases the
## request. Attacks use the same model. Quiet poses settle to match; shots, hits and movement are not interrupted.
func request_readiness(source: StringName, level: WeaponReadiness.Level) -> void:
	readiness.request(source, level)
	_settle_readiness_pose()

func release_readiness(source: StringName) -> void:
	readiness.release(source)
	_settle_readiness_pose()

func _settle_readiness_pose() -> void:
	var state := get_presentation_state()
	if attack_phase == AttackPhase.NONE and state in AIM_SETTLE_STATES and not _carrying():
		_settle_aim_pose(state)

## The level the weapon is actually at (derived from the aim blend it has reached).
func readiness_level() -> WeaponReadiness.Level:
	if _carrying():
		return WeaponReadiness.Level.STOWED
	return WeaponReadiness.level_for_blend(aim_blend, handling)

## The blend follows its target every frame: up over the profile's raise time, down over its lower time.
## Nothing needs to retarget it; callers that still do so (see _retarget_aim_blend) change nothing.
func _advance_readiness(delta: float) -> void:
	var target := _aim_target(get_presentation_state())
	var seconds := handling.raise_seconds if target > aim_blend else handling.lower_seconds
	aim_blend = move_toward(aim_blend, target, delta / maxf(seconds, 0.001))

func _retarget_aim_blend() -> void:
	pass

## Angle between the muzzle and the firing direction (the character's forward, which the weapon is
## rotated onto at full aim). 0 when the weapon is in its firing configuration.
func weapon_alignment_error_degrees() -> float:
	if not is_instance_valid(muzzle_socket) or not muzzle_socket.is_inside_tree():
		return 0.0
	var muzzle := muzzle_socket.global_basis.z.normalized()
	var forward := (character_root.global_basis * torso_frame).z.normalized()
	return rad_to_deg(acos(clampf(muzzle.dot(forward), -1.0, 1.0)))

## The firing configuration is reached: the weapon is within tolerance of the firing pose, and in
## cover the body has finished turning into its aiming stance.
func weapon_aligned() -> bool:
	if weapon_alignment_error_degrees() > handling.alignment_tolerance_degrees:
		return false
	return absf(angle_difference(_cover_yaw, _cover_yaw_target(1.0))) <= deg_to_rad(handling.alignment_tolerance_degrees)

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
## All cover numbers (crouch depths, clearances, turn rate, peek and protected yaw, edge selection) are CoverPostureProfile's (`cover_profile`).
const CROUCH_SPEED := 1.1
const KNEEL_BLEND_RANGE := 0.08
const KNEEL_SPEED := 2.5
var _crouch_depth := 0.0
var _kneel := 0.0
var _cover_yaw := 0.0
## Which wall edge the unit would peek around (CoverEdgeSelector.Side), kept stable by hysteresis; NONE when there is no usable edge or no cover.
var cover_side := 0
var _cover_side_key := Vector3i(-999, 0, -999)
## The last edge analysis (distances, usability, normal, tangent), for diagnostics and tests. Presentation only.
var cover_edges := {}
## The cover kind held through a hit reaction, so the pose does not pop out of cover while the hit clip plays.
var _held_cover_kind := MapCellData.CoverType.NONE

## Which cover the pose is in right now: LOW or FULL, or NONE when no cover pose applies.
func _cover_kind() -> MapCellData.CoverType:
	var type: int = last_cover_contact.get("type", MapCellData.CoverType.NONE)
	var held := _compute_cover_kind(type)
	# A hit reaction keeps the cover pose it interrupted (the hit clip owns the arms; cover keeps owning the legs and yaw).
	if get_presentation_state() == &"hit" and type != MapCellData.CoverType.NONE and _held_cover_kind != MapCellData.CoverType.NONE:
		return _held_cover_kind
	_held_cover_kind = held
	return held

func _compute_cover_kind(type: int) -> MapCellData.CoverType:
	var state := get_presentation_state()
	# A shot fired from cover keeps the cover pose: the shot only changes what the arms and weapon do.
	if state in [&"cover_low", &"shoot"] and type == MapCellData.CoverType.LOW:
		return MapCellData.CoverType.LOW
	if state in [&"cover_high", &"shoot_left", &"shoot_right"] and type == MapCellData.CoverType.FULL:
		return MapCellData.CoverType.FULL
	return MapCellData.CoverType.NONE

## Depth the cover asks for, before the human limit. 0 when not behind cover.
func _cover_crouch_request() -> float:
	if crouch_modifier == null:
		return 0.0
	var kind := _cover_kind()
	if kind == MapCellData.CoverType.NONE:
		return 0.0
	return cover_profile.crouch_request(kind == MapCellData.CoverType.FULL, float(last_cover_contact.get("height", 0.0)), aim_blend, crouch_modifier.standing_head_height)

func _cover_crouch_target() -> float:
	return crouch_modifier.clamp_depth(_cover_crouch_request()) if crouch_modifier != null else 0.0

func _sync_cover_crouch(delta: float) -> void:
	if crouch_modifier == null:
		return
	_update_cover_side()
	_crouch_depth = move_toward(_crouch_depth, _cover_crouch_target(), cover_profile.crouch_speed * delta)
	crouch_modifier.depth = _crouch_depth
	# Cover lower than the deepest natural crouch can hide behind: go down on one knee.
	var kneel_target := clampf((_cover_crouch_request() - crouch_modifier.max_depth) / KNEEL_BLEND_RANGE, 0.0, 1.0)
	_kneel = move_toward(_kneel, kneel_target, cover_profile.kneel_speed * delta)
	crouch_modifier.kneel = _kneel
	# Shortest way round, always: the offset is an angle, and a plain linear chase could sweep the long way through a full turn.
	var step := deg_to_rad(cover_profile.turn_degrees_per_second) * delta
	_cover_yaw = wrapf(_cover_yaw + clampf(angle_difference(_cover_yaw, _cover_yaw_target(aim_blend)), -step, step), -PI, PI)
	character_root.rotation.y = _cover_yaw

## Body yaw OFFSET (relative to the unit's tactical facing) the cover pose asks for at a given weapon blend (see CoverPostureProfile, "facing contract"):
## protected, the body turns toward the chosen peek edge; aiming over low cover it faces the target squarely; aiming around full cover it turns slightly
## toward the edge. With no usable edge it stays square to the facing. Never the back to the wall.
func _cover_yaw_target(blend: float) -> float:
	var kind := _cover_kind()
	if kind == MapCellData.CoverType.NONE:
		return 0.0
	return cover_profile.yaw_offset(kind == MapCellData.CoverType.FULL, cover_side, blend)

## Re-evaluates which wall edge the unit would peek around while it is in cover (stable by hysteresis); clears it otherwise.
func _update_cover_side() -> void:
	if _cover_kind() == MapCellData.CoverType.NONE or not is_instance_valid(presentation_grid):
		cover_side = CoverEdgeSelector.Side.NONE
		_cover_side_key = Vector3i(-999, 0, -999)
		cover_edges = {}
		return
	var cell := presentation_grid.world_to_grid(global_position)
	if cell != _cover_side_key:
		_cover_side_key = cell
		cover_side = CoverEdgeSelector.Side.NONE   # a new place: choose afresh (hysteresis only holds within one cell's cover)
	cover_edges = CoverEdgeSelector.edges(presentation_grid, global_position, last_cover_contact, cover_profile)
	cover_side = CoverEdgeSelector.choose(cover_edges, cover_side, cover_profile)

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
		_play(&"aim" if (_aim_held or _aim_should_hold() or readiness.requested() == WeaponReadiness.Level.AIMED) else &"rifle_idle")
	else:
		face_world_position(global_position + cover.direction)
		_play(&"cover_low" if cover.type == MapCellData.CoverType.LOW else &"cover_high")

func update_locomotion(world_velocity: Vector3, delta: float) -> void:
	var flat := Vector3(world_velocity.x, 0.0, world_velocity.z)
	if flat.length_squared() < 0.000001:
		return
	var desired_yaw := atan2(flat.x, flat.z)
	var yaw_before := global_rotation.y
	global_rotation.y = rotate_toward(global_rotation.y, desired_yaw, deg_to_rad(turn_speed_degrees) * delta)
	# The tactical layer owns speed and heading. This only reports them: the presentation derives its gait, cadence and lean from them every frame.
	_locomotion_speed = flat.length()
	_locomotion_age = 0.0
	_locomotion_heading_rate = angle_difference(yaw_before, global_rotation.y) / maxf(delta, 0.0001)
	# Tactical paths mean "turn and advance": the clip family is always the forward one (see the movement coordinate contract in the
	# animation builder); the speed decides walk, jog or run.

## Stages an attack that is already resolved: raise the weapon to its firing configuration, fire, recover,
## release. From an already aimed pose there is no raise: the shot is shown at once. A unit that cannot
## sequence (carrying, no processing) shows the shot immediately, as before.
func present_attack(target_world_position: Vector3) -> void:
	var cover := _cover_context()
	face_world_position(target_world_position)
	var shot := &"shoot"
	if cover.type == MapCellData.CoverType.FULL:
		# Visual lean only; the combat evaluator has already resolved the shot.
		shot = &"shoot_left" if cover_side < 0 else &"shoot_right"   # lean toward the chosen edge (right when there is none or it is a tie)
	_cancel_attack_sequence()
	_return_generation += 1
	_attack_shot_state = shot
	attack_timeline = {"start": _presentation_clock, "from_state": get_presentation_state(), "from_blend": aim_blend,
		"phases": [], "forced": false, "fired": false, "shot_state": shot}
	if _carrying() or not can_process() or not is_instance_valid(muzzle_socket):
		attack_timeline["forced"] = true
		_fire_shot()
		return
	attack_phase = AttackPhase.RAISE
	_note_attack_phase(AttackPhase.RAISE)
	readiness.request(ATTACK_SOURCE, WeaponReadiness.Level.AIMED)
	if cover.type == MapCellData.CoverType.NONE and get_presentation_state() not in AIM_POSE_STATES:
		_play(&"aim")
	_advance_attack(0.0)

## True from the attack request until its shot is shown (or it is cancelled). The action presenter
## waits on this before showing the target's reaction.
func is_attack_pending() -> bool:
	return attack_phase == AttackPhase.RAISE or attack_phase == AttackPhase.ALIGN

func _note_attack_phase(phase: AttackPhase) -> void:
	var phases: Array = attack_timeline.get("phases", [])
	phases.append({"phase": phase, "t": _presentation_clock - float(attack_timeline.get("start", 0.0)), "blend": aim_blend,
		"muzzle_error_degrees": weapon_alignment_error_degrees()})

func _advance_attack(delta: float) -> void:
	match attack_phase:
		AttackPhase.RAISE:
			var waited := _presentation_clock - float(attack_timeline.get("start", 0.0))
			var aligned := weapon_aligned()
			if not aligned and waited < handling.max_raise_wait_seconds:
				return
			attack_phase = AttackPhase.ALIGN
			_note_attack_phase(AttackPhase.ALIGN)
			attack_timeline["forced"] = not aligned
			_fire_shot()
		AttackPhase.RECOVER:
			_recover_left -= delta
			if _recover_left <= 0.0:
				_release_attack()
		AttackPhase.RELEASE:
			if is_equal_approx(aim_blend, _aim_target(get_presentation_state())):
				_finish_attack_sequence(true)

## Muzzle flash, recoil and trigger together: the shot state starts them (see _on_animation_state_changed).
func _fire_shot() -> void:
	var start := float(attack_timeline.get("start", _presentation_clock))
	attack_timeline["fired"] = true
	attack_timeline["fire_t"] = _presentation_clock - start
	attack_timeline["fire_blend"] = aim_blend
	attack_timeline["fire_muzzle_error_degrees"] = weapon_alignment_error_degrees()
	attack_phase = AttackPhase.FIRE
	_note_attack_phase(AttackPhase.FIRE)
	_play(_attack_shot_state)
	attack_phase = AttackPhase.RECOVER
	_recover_left = handling.shot_recover_seconds
	_note_attack_phase(AttackPhase.RECOVER)
	shot_fired.emit(attack_timeline)
	if _carrying() or not can_process():
		_release_attack()

## Back to the readiness the unit is otherwise holding: relaxed unless a committed Aim (or another
## request) keeps the weapon up.
func _release_attack() -> void:
	readiness.release(ATTACK_SOURCE)
	attack_phase = AttackPhase.RELEASE
	_note_attack_phase(AttackPhase.RELEASE)
	if is_instance_valid(tactical_unit) and tactical_unit.is_moving:
		_play(&"carry_move" if _segment_state == &"move" and _carrying() else _segment_state)
	else:
		present_idle()
	if is_equal_approx(aim_blend, _aim_target(get_presentation_state())):
		_finish_attack_sequence(true)

func _finish_attack_sequence(fired: bool) -> void:
	readiness.release(ATTACK_SOURCE)
	if attack_phase != AttackPhase.NONE:
		attack_phase = AttackPhase.NONE
		attack_timeline["end_t"] = _presentation_clock - float(attack_timeline.get("start", 0.0))
		attack_sequence_ended.emit(fired)

## A higher-priority or newer presentation took over: drop the attack's readiness request so the weapon
## goes back to whatever the new state wants, and let anyone waiting on the attack continue.
func _cancel_attack_sequence() -> void:
	if attack_phase != AttackPhase.NONE:
		attack_timeline["cancelled"] = true
		_finish_attack_sequence(bool(attack_timeline.get("fired", false)))
	else:
		readiness.release(ATTACK_SOURCE)

func present_hit() -> void:
	_cancel_attack_sequence()
	_play(&"hit")
	_return_to_idle_after(hit_return_seconds)

func present_defeat() -> void:
	_cancel_attack_sequence()
	readiness.clear()
	_return_generation += 1
	_play(&"defeat")

func face_world_position(world_position: Vector3) -> void:
	var flat_direction := world_position - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.0001:
		# This imported rig and its rifle are authored facing +Z.
		var before := rotation.y
		rotation.y = atan2(flat_direction.x, flat_direction.z)
		var change := angle_difference(before, rotation.y)
		if _held_cover_kind != MapCellData.CoverType.NONE and not _moving_now():
			# In cover the facing change is absorbed into the body's offset, so the body (and the rifle on it) does not snap: it eases to the new pose.
			_cover_yaw = wrapf(_cover_yaw - change, -PI, PI)
			character_root.rotation.y = _cover_yaw
		elif absf(change) > deg_to_rad(1.0):
			begin_turn(change)

func get_presentation_state() -> StringName:
	return animation_controller.current_state if is_instance_valid(animation_controller) else &"setup"

func _process(delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree():
		return
	_presentation_clock += delta
	_tick_locomotion(delta)
	_sync_aim_hold(delta)
	_advance_readiness(delta)
	_sync_cover_crouch(delta)
	_advance_attack(delta)
	_update_weapon_pose()
	# Facing and cadence are supplied by TacticalUnit before each movement step.

## The speed and heading rate the tactical unit reports while it moves; zero otherwise (which is what settles the gait to a stop).
func _tick_locomotion(delta: float) -> void:
	if _locomotion_fed_frame == Engine.get_process_frames():
		return   # a tool or test already fed this frame's speed directly
	_locomotion_age += delta
	# A tactical unit says when it is moving; a rig with no tactical unit (tools, tests) is moving while it is being fed velocities.
	var moving := tactical_unit.is_moving if is_instance_valid(tactical_unit) else _locomotion_age < 0.15
	var speed := _locomotion_speed if moving else 0.0
	update_locomotion_presentation(speed, _locomotion_heading_rate if moving else 0.0, delta)
	if not moving:
		_locomotion_speed = 0.0
		_locomotion_heading_rate = 0.0

func _loaded_locomotion() -> bool:
	return _carrying()

func _update_weapon_pose() -> void:
	if _carrying():
		_apply_carry_posture()
		return
	_carry_lean = 0.0
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
	if state_name in [&"shoot", &"shoot_left", &"shoot_right"]:
		_play_shot_feedback()
