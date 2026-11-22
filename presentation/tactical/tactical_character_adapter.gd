@tool
extends Node3D
class_name TacticalCharacterAdapter

signal presentation_state_changed(state_name: StringName)

## The skeletal character this host drives (a child CharacterRig: the model, the modifiers, the IK and the poses), and its presenter (the character's presentation time, intent and action lifecycles). This node is
## the TACTICAL CONTEXT HOST: it reads the tactical unit, chooses what to present and asks the presenter and the rig for it. It holds no skeleton and applies no pose.
## Where this host's CharacterRig child is (the scene's "Rig" node by default).
@export var rig_path := NodePath("Rig")
## The CharacterRig this host drives and the presenter it owns: plain variables (resolved as soon as the scene is instantiated, before it enters the tree), because a host reads them every frame.
var rig: CharacterRig
var presenter: CharacterPresenter

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		_resolve_rig()

func _resolve_rig() -> void:
	if rig == null:
		rig = get_node_or_null(rig_path) as CharacterRig
		if rig != null:
			presenter = rig.presenter
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
## same handle is the one the lift settles later; a pickup without a place has no lift to run (the passenger just appears across the shoulders): its handle is the pickup clip's hold, which settles when the
## unit returns to idle.
func present_pickup(passenger_world := Vector3.INF, lying_orientation = null) -> ActionHandle:
	if presenter.is_defeated():
		return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)   # a defeated carrier lifts nobody
	presenter.attack.cancel()
	presenter.cancel_hold()
	if passenger_world.is_finite() and is_instance_valid(tactical_unit) and (tactical_unit.is_moving or _flat_distance_to(passenger_world) > rig.rescue_interaction.max_step + rig.rescue_interaction.stand_off + 0.3):
		# The tactical layer decides the rescue when the move is COMMITTED, before the carrier's body has walked there (the move's presentation
		# starts after). The lift is shown on arrival (present_movement_end); until then it is an ordinary walk with the rifle in hand and nobody on
		# its shoulders. Otherwise the passenger would "fly" to a carrier still metres away.
		return presenter.hold_pickup(passenger_world, lying_orientation)   # the presenter holds it (and its reserved handle) until the carrier arrives
	if passenger_world.is_finite():
		presenter.arrive_pickup(func(_world: Vector3, _basis: Variant) -> void: pass)   # a lift starting now takes over any held request and its reserved handle
		face_world_position(passenger_world)
		var handle := rig.begin_pickup(passenger_world, lying_orientation)
		if not handle.finished.is_connected(_on_pickup_presented):
			handle.finished.connect(_on_pickup_presented, CONNECT_ONE_SHOT)
		return handle
	rig.begin_carry()
	_play(&"pickup")
	return presenter.begin_hold(pickup_return_seconds, _return_from_hold)

## A pickup's lift has run out (or was run to its end at once): carry on in whichever loaded state the unit is in. An interrupted or cancelled lift is not carried on from: whoever ended it owns what follows.
func _on_pickup_presented(outcome: PresentationTypes.Outcome) -> void:
	if outcome == PresentationTypes.Outcome.COMPLETED or outcome == PresentationTypes.Outcome.SKIPPED:
		if is_instance_valid(tactical_unit) and tactical_unit.is_moving:
			_play(&"carry_move")
		else:
			present_idle()

## The tactical layer has put the passenger down (the carrier fell): drop the visual one at once, take the rifle back and leave
## the rest to the revealed actor. Safe in any phase of a pickup or release.
func present_carry_released() -> void:
	presenter.cancel_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
	presenter.cancel_hold()
	rig.end_carry()
	if is_instance_valid(rig.animation_controller) and rig.animation_controller.current_state in [&"pickup", &"carry_idle", &"carry_move", &"boarding"]:
		present_idle()

func present_boarding() -> void:
	presenter.cancel_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
	presenter.attack.cancel()
	rig.finish_interaction_now()
	presenter.cancel_hold()
	_play(&"boarding")
	if is_instance_valid(rig.carry_passenger):
		var tween := create_tween()
		tween.tween_property(rig.carry_passenger, "presence", 0.01, 0.55)

func _flat_distance_to(world: Vector3) -> float:
	return Vector2(world.x - rig.global_position.x, world.z - rig.global_position.z).length()

## INCAPACITATED PRESENTATION. A unit that is awaiting rescue (TacticalUnit.awaiting_rescue, set by the ObjectiveManager from the rescue objective)
## is shown lying on its back where it is: its standing rig and rifle are hidden and a passive body in the pickup's own lying pose takes their place.
## No idle, no weapon, no locomotion. The state is the tactical flag's, so it lasts until the objective changes it (a carrier lifts it, or it is
## recovered after the carrier fell). Presentation only: the actor stays one actor.
func present_incapacitated(on: bool) -> void:
	if on == is_instance_valid(_lying_body):
		return
	if on:
		presenter.attack.cancel()
		presenter.cancel_hold()
		presenter.cancel_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
		rig.character_root.visible = false
		_lying_body = rig.RESCUE_PASSENGER.new()
		_lying_body.name = "IncapacitatedBody"
		rig.add_child(_lying_body)
		_lying_body.build(rig.character_scene, rig.character_scale, rig.rig_profile)
		_lying_body.lie_on_ground(Vector3(0.0, _lying_ground_height(), 0.0), deg_to_rad(INCAPACITATED_YAW_DEGREES))
	else:
		rig.remove_child(_lying_body)
		_lying_body.free()
		_lying_body = null
		rig.character_root.visible = true
		present_idle()

func is_incapacitated() -> bool:
	return is_instance_valid(_lying_body)

## The world orientation the body lies in, for the pickup to start from; null when this unit is not lying.
func lying_basis() -> Variant:
	if not is_instance_valid(_lying_body):
		return null
	return _lying_body.global_basis.orthonormalized()

func _lying_ground_height() -> float:
	return rig.rescue_interaction.ground_height

func _moving_now() -> bool:
	return is_instance_valid(tactical_unit) and tactical_unit.is_moving

## A pickup is waiting for this carrier to arrive (held by the presenter).
func pickup_pending() -> bool:
	return presenter.has_pending_pickup()

func _carrying() -> bool:
	return preview_carrying or (is_instance_valid(tactical_unit) and tactical_unit.is_carrying_unit() and not pickup_pending())
const POSE_CONTEXT := preload("res://presentation/tactical/tactical_pose_context.gd")
const TRAVERSAL_STATES := [&"vault", &"climb", &"descend"]
## States in which the sights are up.
const AIM_POSE_STATES: Array[StringName] = [&"aim", &"shoot", &"shoot_left", &"shoot_right"]
## Quiet states a held Aim may change. A shot, hit, defeat, move or traversal is never interrupted.
const AIM_SETTLE_STATES: Array[StringName] = [&"aim", &"rifle_idle", &"cover_low", &"cover_high"]
## The committed Aim's persistent mirror and its release grace are the presenter's (`presenter.aim`, AimHold); this keeps the policy: when the Aim still counts as held and what a transition does to the pose.

## Attack presentation (Raise -> Align -> Fire -> Recover -> Release) is `presenter.attack` (AttackSequence); its clock is the presenter's. This adapter only supplies the body: AdapterAttackHost.
var _attack_host := AdapterAttackHost.new(self)
var _team_accent: MeshInstance3D

## What the attack sequence asks of this body (see AttackHost): the firing configuration, the clips, the readiness request and the cover plan.
class AdapterAttackHost extends AttackHost:
	var adapter: TacticalCharacterAdapter
	func _init(owner_adapter: TacticalCharacterAdapter) -> void:
		adapter = owner_adapter
	func sequence_available() -> bool:
		return not adapter._carrying() and adapter.can_process() and is_instance_valid(adapter.rig.muzzle_socket)
	func immediate_release() -> bool:
		return adapter._carrying() or not adapter.can_process()
	func weapon_aligned() -> bool:
		return adapter.weapon_aligned()
	func alignment_error_degrees() -> float:
		return adapter.weapon_alignment_error_degrees()
	func aim_blend() -> float:
		return adapter.rig.aim_blend
	func aim_target() -> float:
		return adapter._aim_target(adapter.get_presentation_state())
	func max_raise_wait_seconds() -> float:
		return adapter.rig.handling.max_raise_wait_seconds
	func recover_seconds() -> float:
		return adapter.rig.handling.shot_recover_seconds
	func begin_raise() -> void:
		adapter.rig.readiness.request(AttackSequence.SOURCE, WeaponReadiness.Level.AIMED)
		if adapter._cover_context().type == MapCellData.CoverType.NONE and adapter.get_presentation_state() not in adapter.AIM_POSE_STATES:
			adapter._play(&"aim")
	func release_aimed() -> void:
		adapter.rig.readiness.release(AttackSequence.SOURCE)
	func play_shot(state: StringName) -> void:
		adapter._play(state)
	func resume_after_shot() -> void:
		if is_instance_valid(adapter.tactical_unit) and adapter.tactical_unit.is_moving:
			adapter._play(&"carry_move" if adapter._segment_state == &"move" and adapter._carrying() else adapter._segment_state)
		else:
			adapter.present_idle()
	func attack_ended() -> void:
		adapter.attack_plan = {}

## The rig is configured for this host before it builds (a parent enters the tree before its children are ready): the tactical carry state says when the character is a loaded carrier, and the readiness
## stage (not the playing clip) drives the sights.
func _enter_tree() -> void:
	_resolve_rig()
	rig.loaded_query = _carrying
	rig.aim_blend_follows_clips = false

func _ready() -> void:
	# The rig built the character in its own _ready (a child is ready first); this host configures the tactical context around it.
	_build_team_accent()
	_apply_class_marker()
	presenter.aim_settling_states = AIM_SETTLE_STATES
	presenter.aim_hold_changed.connect(_on_aim_hold_changed)
	rig.animation_controller.state_changed.connect(_forward_state_change)
	await get_tree().process_frame
	if not is_inside_tree(): return
	await get_tree().process_frame
	if not is_inside_tree(): return
	for problem in presenter.foot_point_problems():
		push_error("[TacticalCharacterAdapter] %s" % problem)

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
	if not is_instance_valid(rig.skeleton):
		return
	var existing := rig.skeleton.get_node_or_null(CLASS_MARKER_NAME)
	if existing:
		existing.queue_free()
	if color.a <= 0.0:
		return
	var bone_name := rig.bones.torso
	if rig.skeleton.find_bone(bone_name) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = CLASS_MARKER_NAME
	attachment.bone_name = bone_name
	rig.skeleton.add_child(attachment)
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
		band.global_basis = rig.character_root.global_basis * Basis.from_scale(CLASS_MARKER_FIT)

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
	rig.add_child(_team_accent)
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

func present_move() -> void:
	rig.finish_interaction_now()
	_end_ladder()
	rig.end_stairs()
	presenter.attack.cancel()
	presenter.cancel_hold()
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
	var profile: TraversalProfile = rig.traversal_profile
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
		"yaw": atan2(facing.x, facing.z) if facing.length() > 0.01 else rig.rotation.y}
	if profile == null or not profile.slow_ladder_enabled:
		return 0.0
	return profile.climb_speed if int(_ladder.direction) > 0 else profile.descend_speed


func note_stairs(model: StairModel, ascending: bool, enter: float, exit: float) -> void:
	if rig.stairs != null and rig.stairs.model == model:
		return
	rig.end_stairs()
	rig.begin_stairs(model, ascending, enter, exit)


func is_ladder_active() -> bool:
	return not _ladder.is_empty()


## Once per frame: while a ladder segment is walked, the character faces the ladder and the pose follows the unit's height up it.
func _tick_traversal(delta: float) -> void:
	if rig.stairs != null and is_instance_valid(tactical_unit):
		var floor_position := tactical_unit.global_position - Vector3.UP * tactical_unit.standing_height
		rig.set_stair_progress(rig.stairs.model.progress_of(floor_position), presenter.speed)
	if _ladder.is_empty() or not is_instance_valid(tactical_unit):
		return
	var climbed := clampf(tactical_unit.global_position.y - float(_ladder.low_y), 0.0, float(_ladder.length))
	if get_presentation_state() != &"rifle_idle" and get_presentation_state() != &"aim":
		_play(&"rifle_idle")
	presenter.turn_toward_yaw(float(_ladder.yaw), turn_speed_degrees, delta)
	if rig.ladder == null:
		rig.begin_traversal(&"ladder", float(_ladder.length), int(_ladder.direction))
	rig.set_traversal_progress(climbed)


func _end_ladder() -> void:
	if _ladder.is_empty() and rig.ladder == null:
		return
	_ladder = {}
	rig.end_traversal()


func present_path_segment(state_name: StringName) -> void:
	rig.finish_interaction_now()
	if not _ladder.is_empty():
		# Climbing or descending a ladder: no clip of its own, the contacts do it (see _tick_traversal). The leg that steps on or off the deck is ordinary walking.
		_segment_state = &"ladder"
		presenter.cancel_hold()
		_play(&"rifle_idle")
		return
	if _ladder_step:
		state_name = &"move"   # the horizontal step to or from a ladder's top: walking
	if state_name == _segment_state:
		return
	var was_traversing := _segment_state in TRAVERSAL_STATES
	_segment_state = state_name
	presenter.cancel_hold()
	if was_traversing and state_name == &"move":
		_play(&"land")
		presenter.begin_hold(landing_return_seconds, _return_from_hold)
	else:
		_play(&"carry_move" if state_name == &"move" and _carrying() else state_name)

func present_movement_end() -> void:
	_end_ladder()
	rig.end_stairs()
	if presenter.arrive_pickup(func(world: Vector3, lying: Variant) -> void: present_pickup(world, lying)):
		return   # the carrier arrived: the lift starts and takes over the reserved handle
	if _segment_state in TRAVERSAL_STATES:
		_play(&"land")
		presenter.begin_hold(landing_return_seconds, _return_from_hold)
	else:
		present_idle()

func _cover_context() -> Dictionary:
	var cell := preview_cell if preview_cell != Vector3i(-1, -1, -1) else tactical_unit.grid_position if is_instance_valid(tactical_unit) else Vector3i(-1, -1, -1)
	if is_instance_valid(presentation_grid) and cell != Vector3i(-1, -1, -1):
		last_cover_contact = POSE_CONTEXT.cover_at(presentation_grid, cell, rig.global_basis.z)
	else:
		last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	return last_cover_contact

## The Aim action committed: bring the sights up now. The pose then follows the committed
## is_aiming flag (see _process and CharacterPresenter.aim_committed), so replays and AI units behave the same.
func present_aim() -> void:
	if _carrying() or not rig.has_weapon(): return   # nothing to raise
	presenter.aim.engage()
	present_idle()

## Reads committed state only; never writes it.
func _aim_should_hold() -> bool:
	return is_instance_valid(tactical_unit) and tactical_unit.tactical_state != null and tactical_unit.tactical_state.is_aiming \
		and not tactical_unit.is_moving and not _carrying()

func _aim_target(state_name: StringName) -> float:
	return WeaponReadiness.blend_for(requested_readiness(state_name), rig.handling)

## The level the unit is asking for: the highest of any request (an attack, later a Guard), the aim
## stance, and a held Aim. A carrier holds nothing.
func requested_readiness(state_name: StringName = &"") -> WeaponReadiness.Level:
	if _carrying() or not rig.has_weapon():
		return WeaponReadiness.Level.STOWED   # a carrier holds nothing, and neither does a character with no weapon
	if state_name == &"":
		state_name = get_presentation_state()
	var level := rig.readiness.requested()
	if state_name in AIM_POSE_STATES or presenter.aim.held:
		level = WeaponReadiness.Level.AIMED
	return level

## Sustained readiness: a source (a future Guard, say) asks for a level and holds it until it releases the
## request. Attacks use the same model. Quiet poses settle to match; shots, hits and movement are not interrupted.
func request_readiness(source: StringName, level: WeaponReadiness.Level) -> void:
	rig.readiness.request(source, level)
	_settle_readiness_pose()

func release_readiness(source: StringName) -> void:
	rig.readiness.release(source)
	_settle_readiness_pose()

func _settle_readiness_pose() -> void:
	var state := get_presentation_state()
	if not presenter.attack.is_active() and state in AIM_SETTLE_STATES and not _carrying():
		_settle_aim_pose(state)

## The level the weapon is actually at (derived from the aim blend it has reached).
func readiness_level() -> WeaponReadiness.Level:
	if _carrying() or not rig.has_weapon():
		return WeaponReadiness.Level.STOWED
	return WeaponReadiness.level_for_blend(rig.aim_blend, rig.handling)

## The blend follows its target every frame: up over the profile's raise time, down over its lower time.
func _advance_readiness(delta: float) -> void:
	var target := _aim_target(get_presentation_state())
	var seconds := rig.handling.raise_seconds if target > rig.aim_blend else rig.handling.lower_seconds
	rig.aim_blend = move_toward(rig.aim_blend, target, delta / maxf(seconds, 0.001))

## Angle between the muzzle and the firing direction (the character's forward, which the weapon is
## rotated onto at full aim). 0 when the weapon is in its firing configuration.
func weapon_alignment_error_degrees() -> float:
	if not is_instance_valid(rig.muzzle_socket) or not rig.muzzle_socket.is_inside_tree():
		return 0.0
	var muzzle := rig.muzzle_socket.global_basis.z.normalized()
	var forward := (rig.character_root.global_basis * rig.torso_frame).z.normalized()
	return rad_to_deg(acos(clampf(muzzle.dot(forward), -1.0, 1.0)))

## The firing configuration is reached: the weapon is within tolerance of the firing pose, and in
## cover the body has finished turning into its aiming stance.
func weapon_aligned() -> bool:
	if weapon_alignment_error_degrees() > rig.handling.alignment_tolerance_degrees:
		return false
	return absf(angle_difference(rig.cover_yaw(), _cover_yaw_target(1.0))) <= deg_to_rad(rig.handling.alignment_tolerance_degrees)

## The held Aim engaged or ended (the presenter progresses it from the committed-aim input): a quiet pose is re-settled so the weapon comes up or goes down. A shot, hit, defeat, move or traversal is never interrupted.
func _on_aim_hold_changed(_transition: AimHold.Transition, settling: bool) -> void:
	if settling:
		_settle_aim_pose(get_presentation_state())

## Low cover: crouch only as deep as the cover is tall (never beyond what a person can), turned
## with the back to the wall while hiding, and facing the wall, eyes just over the top, to aim.
## High cover (standing behind a full wall): a slight wary bend of the knees with the back to the
## wall, turning side-on to peek along it when aiming. In both, the rifle stays in its relaxed carry
## until she aims or shoots. Presentation only.
## The body's cover numbers (crouch depths, clearances, turn rate, peek and protected yaw) are CoverPostureProfile's (`rig.cover_profile`); this host's own edge-selection policy is `cover_policy` (CoverEdgePolicy).
@export var cover_policy: CoverEdgePolicy = CoverEdgePolicy.new()
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
	if rig.crouch_modifier == null:
		return 0.0
	var kind := _cover_kind()
	if kind == MapCellData.CoverType.NONE:
		return 0.0
	return rig.cover_profile.crouch_request(kind == MapCellData.CoverType.FULL, float(last_cover_contact.get("height", 0.0)), rig.aim_blend, rig.crouch_modifier.standing_head_height, rig.crouch_modifier.body_ratio())

## Cover POLICY, once per frame: what the cover the unit is in asks of the body, handed to the presenter as a persistent posture request (released when there is no cover pose), and then
## the presenter resolves and the rig applies it. Nothing here writes the crouch, kneel or body yaw any more.
func _sync_cover_crouch(delta: float) -> void:
	if rig.crouch_modifier == null:
		return
	_update_cover_side()
	var request := _cover_crouch_request()
	if _cover_kind() == MapCellData.CoverType.NONE:
		presenter.postures.release(COVER_POSTURE_SOURCE)
	else:
		# The posture KIND is the classification (a kneel once the kneel blend is past halfway); the rig derives the continuous blend from the depth itself.
		var posture := PresentationTypes.Posture.KNEEL if request > rig.crouch_modifier.max_depth + rig.KNEEL_BLEND_RANGE * 0.5 else PresentationTypes.Posture.CROUCH
		presenter.postures.set_posture(COVER_POSTURE_SOURCE, posture, PresentationTypes.PRIORITY_CONTEXT, _cover_yaw_target(rig.aim_blend), request)
	presenter.apply_posture(delta, rig.cover_profile)

## Body yaw OFFSET (relative to the unit's tactical facing) the cover pose asks for at a given weapon blend (see CoverPostureProfile, "facing contract"):
## protected, the body turns toward the chosen peek edge; aiming over low cover it faces the target squarely; aiming around full cover it turns slightly
## toward the edge. With no usable edge it stays square to the facing. Never the back to the wall.
func _cover_yaw_target(blend: float) -> float:
	var kind := _cover_kind()
	if kind == MapCellData.CoverType.NONE:
		return 0.0
	if not attack_plan.is_empty():
		return rig.cover_profile.attack_yaw_offset(cover_side, int(attack_plan.side), blend)
	return rig.cover_profile.yaw_offset(kind == MapCellData.CoverType.FULL, cover_side, blend)

## Re-evaluates which wall edge the unit would peek around while it is in cover (stable by hysteresis); clears it otherwise.
func _update_cover_side() -> void:
	if _cover_kind() == MapCellData.CoverType.NONE or not is_instance_valid(presentation_grid):
		cover_side = CoverEdgeSelector.Side.NONE
		_cover_side_key = Vector3i(-999, 0, -999)
		cover_edges = {}
		return
	var cell := presentation_grid.world_to_grid(rig.global_position)
	if cell != _cover_side_key:
		_cover_side_key = cell
		_last_attack_side = CoverEdgeSelector.Side.NONE
		cover_side = CoverEdgeSelector.Side.NONE   # a new place: choose afresh (hysteresis only holds within one cell's cover)
	cover_edges = CoverEdgeSelector.edges(presentation_grid, rig.global_position, last_cover_contact, cover_policy)
	cover_side = CoverEdgeSelector.choose(cover_edges, cover_side, cover_policy)

func _settle_aim_pose(state: StringName) -> void:
	if state in [&"cover_low", &"cover_high"]:
		pass   # keep the cover pose; the weapon blend follows its target on its own
	else:
		present_idle()

func present_idle() -> void:
	presenter.cancel_hold()
	if _carrying():
		_play(&"carry_idle")
		return
	var cover := _cover_context()
	if cover.type == MapCellData.CoverType.NONE:
		_play(&"aim" if (rig.has_weapon() and (presenter.aim.held or _aim_should_hold() or rig.readiness.requested() == WeaponReadiness.Level.AIMED)) else &"rifle_idle")
	else:
		face_world_position(rig.global_position + cover.direction)
		_play(&"cover_low" if cover.type == MapCellData.CoverType.LOW else &"cover_high")

func update_locomotion(world_velocity: Vector3, delta: float) -> void:
	# The tactical layer owns speed and heading. This only reports them: the presenter turns the body toward the velocity and the presentation derives its gait, cadence and lean from them every frame.
	presenter.report_velocity(world_velocity, delta, turn_speed_degrees)
	# Tactical paths mean "turn and advance": the clip family is always the forward one (see the movement coordinate contract in the
	# animation builder); the speed decides walk, jog or run.

## Stages an attack that is already resolved: raise the weapon to its firing configuration, fire, recover,
## release. From an already aimed pose there is no raise: the shot is shown at once. A unit that cannot
## sequence (carrying, no processing) shows the shot immediately, as before.
## Returns the attack's handle: `handle.shot` settles when the shot is shown (what the tactical layer waits on before the target reacts), the handle itself when the release is over (see AttackHandle).
func present_attack(target_world_position: Vector3) -> AttackHandle:
	if presenter.is_defeated():
		var refused := AttackHandle.new()   # defeat is terminal: a defeated character shows no shot
		refused.shot.settle(PresentationTypes.Outcome.CANCELLED)
		refused.settle(PresentationTypes.Outcome.CANCELLED)
		return refused
	if not rig.has_weapon():
		var unarmed := AttackHandle.new()   # no weapon, no shot to show: nothing was presented (the attack's result is gameplay's)
		unarmed.shot.settle(PresentationTypes.Outcome.SKIPPED)
		unarmed.settle(PresentationTypes.Outcome.SKIPPED)
		return unarmed
	var cover := _cover_context()
	# The firing posture comes from the authorized shot's direction and the wall geometry only (CoverEdgeSelector.plan_attack); a visual pose never creates a shot.
	var plan := _plan_attack_posture(cover, target_world_position)
	face_world_position(target_world_position)
	var shot := CoverEdgeSelector.shot_state(cover.type == MapCellData.CoverType.FULL, plan, cover_side)   # visual lean only; the combat evaluator has already resolved the shot
	presenter.attack.cancel()   # a newer attack ends the running one first (its cover plan is dropped before this one's is set)
	attack_plan = plan
	presenter.cancel_hold()
	return presenter.attack.begin(_attack_host, presenter.time, shot, get_presentation_state(), rig.aim_blend)

## The target-aware posture for an authorized attack from the unit's current cover; {} outside cover. Records the plan (and any mismatch) in `attack_plan_log`.
func _plan_attack_posture(cover: Dictionary, target_world_position: Vector3) -> Dictionary:
	if int(cover.type) == MapCellData.CoverType.NONE or not is_instance_valid(presentation_grid):
		return {}
	var edges := CoverEdgeSelector.edges(presentation_grid, rig.global_position, cover, cover_policy)
	var face_distance := float(cover.get("distance", presentation_grid.cell_size * 0.5))
	var plan := CoverEdgeSelector.plan_attack(edges, int(cover.type) == MapCellData.CoverType.FULL, target_world_position - rig.global_position, _last_attack_side, cover_side, face_distance, cover_policy)
	if int(plan.mode) in [CoverEdgeSelector.FiringMode.AROUND_LEFT, CoverEdgeSelector.FiringMode.AROUND_RIGHT]:
		_last_attack_side = int(plan.side)
	attack_plan_log.append(plan)
	if attack_plan_log.size() > ATTACK_PLAN_LOG_LIMIT:
		attack_plan_log.pop_front()
	return plan

## A hit reaction: the hit clip, held for `hit_return_seconds` of presentation time, then back to idle (or on with the walk). It ends a running attack and is itself ended by anything newer. The handle
## settles COMPLETED at the return, INTERRUPTED if something took over, SKIPPED when a ladder shows no reaction.
func present_hit() -> ActionHandle:
	if presenter.is_defeated():
		return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)   # defeat is terminal: nothing outranks it, a hit after it shows nothing
	if rig.interaction_active():
		return ActionHandle.settled(PresentationTypes.Outcome.SKIPPED)   # a rescue lift owns the body and was already committed; a cosmetic reaction does not cut it short
	presenter.attack.cancel()
	if is_ladder_active():
		return ActionHandle.settled(PresentationTypes.Outcome.SKIPPED)   # a reaction shot that hits a unit on a ladder: it keeps climbing (no hit clip over the rungs; a hit-on-ladder reaction is not designed yet)
	_play(&"hit")
	return presenter.begin_hold(hit_return_seconds, _return_from_hold)

## The timed state ran out (a hit, a landing, a pickup clip): walk on or go to the idle that fits.
func _return_from_hold() -> void:
	if is_instance_valid(tactical_unit) and tactical_unit.is_moving:
		_play(&"carry_move" if _segment_state == &"move" and _carrying() else _segment_state)
	else:
		present_idle()

## Defeat ends everything else this character was presenting (the rescue, a traversal, the attack, the held aim, a pending hit return) and plays the one-shot defeat clip. A repeat while the clip is still
## running is the same defeat. The handle settles COMPLETED when the clip has run its length, INTERRUPTED if the character is removed first.
func present_defeat() -> ActionHandle:
	if presenter.is_defeated():
		return presenter.begin_defeat(0.0)   # the same defeat, running or finished: it is never restarted
	presenter.aim.clear()
	# A rescue under way cannot continue on a defeated carrier: its visual operation is interrupted here (the tactical layer puts the passenger down, which frees the carried body).
	presenter.cancel_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
	if rig.interaction_active():
		rig.halt_interaction(PresentationTypes.Outcome.INTERRUPTED, false)
	_end_ladder()
	rig.end_stairs()
	presenter.attack.cancel()
	rig.readiness.clear()
	presenter.cancel_hold()
	_play(&"defeat")
	return presenter.begin_defeat(rig.animation_controller.state_length(&"defeat") if is_instance_valid(rig.animation_controller) else 0.0)

func face_world_position(world_position: Vector3) -> void:
	# This imported rig and its rifle are authored facing +Z. The presenter decides and the rig applies; this only says whether the cover pose holds the body (the tactical cover kind and movement).
	presenter.face_point(world_position, _facing_absorbed_by_cover())

## A direction gameplay authority committed (a world X/Z vector, as TacticalState.shield_facing is): shown exactly, and reported as authoritative by the presenter.
func face_committed_direction(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	presenter.face_authoritative(atan2(direction.x, direction.y), _facing_absorbed_by_cover())

## In cover a facing change is absorbed into the body's offset so the body (and the rifle on it) does not snap: it eases to the new pose.
func _facing_absorbed_by_cover() -> bool:
	return _held_cover_kind != MapCellData.CoverType.NONE and not _moving_now()

func get_presentation_state() -> StringName:
	return rig.animation_controller.current_state if is_instance_valid(rig.animation_controller) else &"setup"

func _process(delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(rig.skeleton) or not rig.skeleton.is_inside_tree():
		return
	_sync_movement_authority()
	presenter.aim_committed = _aim_should_hold()   # a tactical fact translated into the presenter's typed input; the presenter does the rest
	presenter.tick(delta)
	_advance_readiness(delta)
	_sync_cover_crouch(delta)
	presenter.advance_actions(delta)
	_tick_traversal(delta)
	rig.update_weapon_pose()
	# Facing and cadence are supplied by TacticalUnit before each movement step.

## A tactical unit says when it is moving; a rig with no tactical unit (tools, tests) is moving while it is being fed velocities (the presenter infers that).
func _sync_movement_authority() -> void:
	if is_instance_valid(tactical_unit):
		presenter.set_movement_authority(tactical_unit.is_moving)
	else:
		presenter.clear_movement_authority()

func _play(state_name: StringName) -> void:
	if is_instance_valid(rig.animation_controller):
		rig.animation_controller.play(state_name)

func _forward_state_change(state_name: StringName) -> void:
	presentation_state_changed.emit(state_name)
