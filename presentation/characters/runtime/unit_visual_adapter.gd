@tool
extends CharacterRig
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
## Where the rescued actor lies, while the carrier is still walking to it (see present_pickup); INF when no pickup is waiting.
var _pending_pickup_world := Vector3.INF
var _pending_lying_basis = null
## The rescue handle reserved while that pickup waits for its carrier to arrive (the rig settles it once the lift runs; see present_pickup).
var _pending_handle: ActionHandle
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
## Ladder traversal (a climb/descend route segment that is vertical): the unit's tactical HEIGHT up the ladder drives the whole pose (TraversalSolver is a pure function of it),
## so the presentation is the same at any playback speed and from any replay position. `_ladder` is {} when none.
var _ladder := {}
var _segment_from := Vector3.ZERO
var _ladder_step := false
var _segment_to := Vector3.ZERO

## The carrier has just taken `passenger_world` (the rescued actor's place, which the tactical layer has hidden the actor at).
## The carrier faces it and the shared timeline (RescueInteraction) lifts a visual passenger from there into the carry. Without a
## place there is nothing to lift from: the passenger appears across the shoulders as before.
## Returns the handle of the visual lift: it settles when the lift ends (see CharacterRig.rescue_presentation). A pickup that has to wait for the carrier to arrive returns the reserved handle at once and the
## same handle is the one the lift settles later; a pickup without a place has no timeline to run (the passenger just appears across the shoulders), so nothing was presented and it is SKIPPED.
func present_pickup(passenger_world := Vector3.INF, lying_orientation = null) -> ActionHandle:
	_cancel_attack_sequence()
	_return_generation += 1
	if passenger_world.is_finite() and is_instance_valid(tactical_unit) and (tactical_unit.is_moving or _flat_distance_to(passenger_world) > rescue_interaction.max_step + rescue_interaction.stand_off + 0.3):
		# The tactical layer decides the rescue when the move is COMMITTED, before the carrier's body has walked there (the move's presentation
		# starts after). The lift is shown on arrival (present_movement_end); until then it is an ordinary walk with the rifle in hand and nobody on
		# its shoulders. Otherwise the passenger would "fly" to a carrier still metres away.
		_pending_pickup_world = passenger_world
		_pending_lying_basis = lying_orientation
		if _pending_handle == null or _pending_handle.is_done():
			_pending_handle = reserve_rescue_handle()
			_pending_handle.finished.connect(_on_pending_pickup_settled.bind(_pending_handle), CONNECT_ONE_SHOT)
		return _pending_handle
	if passenger_world.is_finite():
		_pending_handle = null   # the lift takes the reserved handle over from here
		face_world_position(passenger_world)
		var handle := begin_pickup(passenger_world, lying_orientation)
		if not handle.finished.is_connected(_on_pickup_presented):
			handle.finished.connect(_on_pickup_presented, CONNECT_ONE_SHOT)
		return handle
	begin_carry()
	_play(&"pickup")
	_return_to_idle_after(pickup_return_seconds)
	return ActionHandle.settled(PresentationTypes.Outcome.SKIPPED)

## A pickup's lift has run out (or was run to its end at once): carry on in whichever loaded state the unit is in. An interrupted or cancelled lift is not carried on from: whoever ended it owns what follows.
func _on_pickup_presented(outcome: PresentationTypes.Outcome) -> void:
	if outcome == PresentationTypes.Outcome.COMPLETED or outcome == PresentationTypes.Outcome.SKIPPED:
		if is_instance_valid(tactical_unit) and tactical_unit.is_moving:
			_play(&"carry_move")
		else:
			present_idle()

## The requester cancelled a pickup that was still waiting for its carrier: it is not started on arrival. (Settlements made by the rig itself have already cleared the pending state.)
func _on_pending_pickup_settled(outcome: PresentationTypes.Outcome, handle: ActionHandle) -> void:
	if handle == _pending_handle and outcome == PresentationTypes.Outcome.CANCELLED:
		_pending_pickup_world = Vector3.INF
		_pending_lying_basis = null
		_pending_handle = null

## A pickup that was still waiting for its carrier is withdrawn: nothing is pending and whoever waits on the reserved handle is told the presentation will not happen.
func _clear_pending_pickup(outcome: PresentationTypes.Outcome) -> void:
	_pending_pickup_world = Vector3.INF
	_pending_lying_basis = null
	var handle := _pending_handle
	_pending_handle = null
	if handle != null and not handle.is_done() and not interaction_active():
		_settle_rescue(outcome)

## The tactical layer has put the passenger down (the carrier fell): drop the visual one at once, take the rifle back and leave
## the rest to the revealed actor. Safe in any phase of a pickup or release.
func present_carry_released() -> void:
	_clear_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
	_return_generation += 1
	end_carry()
	if is_instance_valid(animation_controller) and animation_controller.current_state in [&"pickup", &"carry_idle", &"carry_move", &"boarding"]:
		present_idle()

func present_boarding() -> void:
	_clear_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
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
		_clear_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
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
## Presentation seconds: owned by the presenter; this accessor keeps existing readers (attack timelines, tests) working.
var _presentation_clock: float:
	get: return presenter.time
	set(value): presenter.time = value
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
	super()   # the rig releases the presenter (no posture request outlives the character)
	# Skeleton modifiers can emit once more while their hierarchy is being
	# removed. Disconnect before descendants lose legal global transforms.
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_align_weapon_to_aim):
		skeleton.skeleton_updated.disconnect(_align_weapon_to_aim)

func present_move() -> void:
	finish_interaction_now()
	_end_ladder()
	end_stairs()
	_cancel_attack_sequence()
	_return_generation += 1
	_segment_state = &"move"
	_play(&"carry_move" if _carrying() else &"move")

## The route segment the tactical unit is about to walk (its start and end, in the tactical node's own coordinates), with the horizontal direction of the ladder's top
## (`toward_deck`, the way the ladder leans/faces; Vector3.ZERO if unknown). A vertical climb/descend segment is a ladder: the body then climbs by the unit's height. Returns the
## speed this segment should be presented at (<= 0: the route speed, unchanged); see TraversalProfile.slow_ladder_enabled.
func note_segment(from_world: Vector3, to_world: Vector3, state_name: StringName, toward_deck: Vector3, link_kind := 0) -> float:
	_segment_from = from_world
	_segment_to = to_world
	# The level step to or from a ladder's top (the horizontal leg of a LADDER link's route) is ordinary walking, not a climb clip.
	_ladder_step = absf(to_world.y - from_world.y) < 0.05 and state_name in [&"climb", &"descend"] and link_kind == TraversalLinkData.LADDER
	var vertical := absf(to_world.y - from_world.y) > 0.05 and Vector2(to_world.x - from_world.x, to_world.z - from_world.z).length() < 0.02
	var profile: TraversalProfile = traversal_profile
	if _carrying():
		# A loaded carrier on a ladder is an unsupported combination (the passenger's contacts and the rungs would compete for the hands): the placeholder clips, as before.
		_ladder_step = false
		_end_ladder()
		return 0.0
	# Only a link DECLARED a ladder gets the rung contacts; a generic or undeclared vertical link keeps the placeholder clips (no guessing from its height).
	if not (vertical and link_kind == TraversalLinkData.LADDER):
		_end_ladder()
		return 0.0
	var facing := Vector3(toward_deck.x, 0.0, toward_deck.z)
	_ladder = {"low_y": minf(from_world.y, to_world.y), "length": absf(to_world.y - from_world.y), "direction": 1 if to_world.y > from_world.y else -1,
		"yaw": atan2(facing.x, facing.z) if facing.length() > 0.01 else rotation.y}
	if profile == null or not profile.slow_ladder_enabled:
		return 0.0
	return profile.climb_speed if int(_ladder.direction) > 0 else profile.descend_speed


func note_stairs(model: StairModel, ascending: bool, enter: float, exit: float) -> void:
	if not stair_state.is_empty() and stair_state.model == model:
		return
	end_stairs()
	begin_stairs(model, ascending, enter, exit)


func is_ladder_active() -> bool:
	return not _ladder.is_empty()


## Once per frame: while a ladder segment is walked, the character faces the ladder and the pose follows the unit's height up it.
func _tick_traversal(delta: float) -> void:
	if not stair_state.is_empty() and is_instance_valid(tactical_unit):
		var floor_position := tactical_unit.global_position - Vector3.UP * tactical_unit.standing_height
		set_stair_progress((stair_state.model as StairModel).progress_of(floor_position), presenter.speed)
	if _ladder.is_empty() or not is_instance_valid(tactical_unit):
		return
	var climbed := clampf(tactical_unit.global_position.y - float(_ladder.low_y), 0.0, float(_ladder.length))
	if get_presentation_state() != &"rifle_idle" and get_presentation_state() != &"aim":
		_play(&"rifle_idle")
	rotation.y = rotate_toward(rotation.y, float(_ladder.yaw), deg_to_rad(turn_speed_degrees) * delta)
	if traversal.is_empty():
		begin_traversal(&"ladder", float(_ladder.length), int(_ladder.direction))
	set_traversal_progress(climbed)


func _end_ladder() -> void:
	if _ladder.is_empty() and traversal.is_empty():
		return
	_ladder = {}
	end_traversal()


func present_path_segment(state_name: StringName) -> void:
	finish_interaction_now()
	if not _ladder.is_empty():
		# Climbing or descending a ladder: no clip of its own, the contacts do it (see _tick_traversal). The leg that steps on or off the deck is ordinary walking.
		_segment_state = &"ladder"
		_return_generation += 1
		_play(&"rifle_idle")
		return
	if _ladder_step:
		state_name = &"move"   # the horizontal step to or from a ladder's top: walking
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
	_end_ladder()
	end_stairs()
	if pickup_pending():
		var world := _pending_pickup_world
		_pending_pickup_world = Vector3.INF
		present_pickup(world, _pending_lying_basis)   # the reserved handle is taken over by the lift it starts
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
## The posture source this unit's cover policy requests under (see CharacterPresenter.postures); the applied ramps (`_crouch_depth`, `_kneel`, `_cover_yaw`) live in the rig.
const COVER_POSTURE_SOURCE := &"tactical/cover"
## Which wall edge the unit would peek around (CoverEdgeSelector.Side), kept stable by hysteresis; NONE when there is no usable edge or no cover.
var cover_side := 0
## The plan for the attack being presented (CoverEdgeSelector.plan_attack): {} when none. Built from the authorized attack's target position only, held until the
## attack sequence ends so the posture cannot flip mid-attack; `cover_side` stays the PASSIVE choice (what the unit returns to).
var attack_plan := {}
## Recent plans (newest last, capped) for diagnostics and tests; mismatches between the tactical shot and a plausible pose are recorded here.
var attack_plan_log: Array[Dictionary] = []
var _last_attack_side := 0
const ATTACK_PLAN_LOG_LIMIT := 24
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
	if (state in [&"cover_high", &"shoot_left", &"shoot_right"] or (state == &"shoot" and not attack_plan.is_empty())) and type == MapCellData.CoverType.FULL:
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

## Cover POLICY, once per frame: what the cover the unit is in asks of the body, handed to the presenter as a persistent posture request (released when there is no cover pose), and then
## the presenter resolves and the rig applies it. Nothing here writes the crouch, kneel or body yaw any more.
func _sync_cover_crouch(delta: float) -> void:
	if crouch_modifier == null:
		return
	_update_cover_side()
	var request := _cover_crouch_request()
	if _cover_kind() == MapCellData.CoverType.NONE:
		presenter.postures.release(COVER_POSTURE_SOURCE)
	else:
		# The posture KIND is the classification (a kneel once the kneel blend is past halfway); the rig derives the continuous blend from the depth itself.
		var posture := PresentationTypes.Posture.KNEEL if request > crouch_modifier.max_depth + KNEEL_BLEND_RANGE * 0.5 else PresentationTypes.Posture.CROUCH
		presenter.postures.set_posture(COVER_POSTURE_SOURCE, posture, PresentationTypes.PRIORITY_CONTEXT, _cover_yaw_target(aim_blend), request)
	presenter.apply_posture(delta, cover_profile)

## Body yaw OFFSET (relative to the unit's tactical facing) the cover pose asks for at a given weapon blend (see CoverPostureProfile, "facing contract"):
## protected, the body turns toward the chosen peek edge; aiming over low cover it faces the target squarely; aiming around full cover it turns slightly
## toward the edge. With no usable edge it stays square to the facing. Never the back to the wall.
func _cover_yaw_target(blend: float) -> float:
	var kind := _cover_kind()
	if kind == MapCellData.CoverType.NONE:
		return 0.0
	if not attack_plan.is_empty():
		return cover_profile.attack_yaw_offset(cover_side, int(attack_plan.side), blend)
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
		_last_attack_side = CoverEdgeSelector.Side.NONE
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
	# The tactical layer owns speed and heading. This only reports them: the presenter turns the body toward the velocity and the presentation derives its gait, cadence and lean from them every frame.
	presenter.report_velocity(world_velocity, delta, turn_speed_degrees)
	# Tactical paths mean "turn and advance": the clip family is always the forward one (see the movement coordinate contract in the
	# animation builder); the speed decides walk, jog or run.

## Stages an attack that is already resolved: raise the weapon to its firing configuration, fire, recover,
## release. From an already aimed pose there is no raise: the shot is shown at once. A unit that cannot
## sequence (carrying, no processing) shows the shot immediately, as before.
func present_attack(target_world_position: Vector3) -> void:
	var cover := _cover_context()
	# The firing posture comes from the authorized shot's direction and the wall geometry only (CoverEdgeSelector.plan_attack); a visual pose never creates a shot.
	var plan := _plan_attack_posture(cover, target_world_position)
	face_world_position(target_world_position)
	var shot := &"shoot"
	if cover.type == MapCellData.CoverType.FULL:
		# Visual lean only; the combat evaluator has already resolved the shot.
		match int(plan.get("mode", CoverEdgeSelector.FiringMode.PROTECTED)):
			CoverEdgeSelector.FiringMode.AROUND_LEFT: shot = &"shoot_left"
			CoverEdgeSelector.FiringMode.AROUND_RIGHT: shot = &"shoot_right"
			CoverEdgeSelector.FiringMode.ORDINARY: shot = &"shoot"
			_: shot = &"shoot_left" if cover_side < 0 else &"shoot_right"   # no honest peek: the passive lean side (right on a tie or none)
	_cancel_attack_sequence()
	attack_plan = plan
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

## The target-aware posture for an authorized attack from the unit's current cover; {} outside cover. Records the plan (and any mismatch) in `attack_plan_log`.
func _plan_attack_posture(cover: Dictionary, target_world_position: Vector3) -> Dictionary:
	if int(cover.type) == MapCellData.CoverType.NONE or not is_instance_valid(presentation_grid):
		return {}
	var edges := CoverEdgeSelector.edges(presentation_grid, global_position, cover, cover_profile)
	var face_distance := float(cover.get("distance", presentation_grid.cell_size * 0.5))
	var plan := CoverEdgeSelector.plan_attack(edges, int(cover.type) == MapCellData.CoverType.FULL, target_world_position - global_position, _last_attack_side, cover_side, face_distance, cover_profile)
	if int(plan.mode) in [CoverEdgeSelector.FiringMode.AROUND_LEFT, CoverEdgeSelector.FiringMode.AROUND_RIGHT]:
		_last_attack_side = int(plan.side)
	attack_plan_log.append(plan)
	if attack_plan_log.size() > ATTACK_PLAN_LOG_LIMIT:
		attack_plan_log.pop_front()
	return plan

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
	attack_plan = {}   # back to the passive cover posture
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
	if is_ladder_active():
		return   # a reaction shot that hits a unit on a ladder: it keeps climbing (no hit clip over the rungs; a hit-on-ladder reaction is not designed yet)
	_play(&"hit")
	_return_to_idle_after(hit_return_seconds)

func present_defeat() -> void:
	# A rescue under way cannot continue on a defeated carrier: its visual operation is interrupted here (the tactical layer puts the passenger down, which frees the carried body).
	_clear_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
	if interaction_active():
		_halt_interaction(PresentationTypes.Outcome.INTERRUPTED, false)
	_end_ladder()
	end_stairs()
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
	_sync_movement_authority()
	presenter.tick(delta)
	_sync_aim_hold(delta)
	_advance_readiness(delta)
	_sync_cover_crouch(delta)
	_advance_attack(delta)
	_tick_traversal(delta)
	_update_weapon_pose()
	# Facing and cadence are supplied by TacticalUnit before each movement step.

## A tactical unit says when it is moving; a rig with no tactical unit (tools, tests) is moving while it is being fed velocities (the presenter infers that).
func _sync_movement_authority() -> void:
	if is_instance_valid(tactical_unit):
		presenter.set_movement_authority(tactical_unit.is_moving)
	else:
		presenter.clear_movement_authority()

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
