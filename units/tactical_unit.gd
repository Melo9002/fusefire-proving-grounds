extends CharacterBody3D
class_name TacticalUnit

enum Faction { PLAYER, ENEMY, ALLY, NEUTRAL }

signal movement_finished
signal defeated(unit: TacticalUnit)
signal attack_presented(target_world_position: Vector3)

@export_group("Gameplay")
## Presentation speed in world metres per second. Movement range is UnitStats.speed.
@export_range(0.1, 30.0, 0.1, "suffix:m/s") var movement_speed: float = 5.0
## Feet-to-origin offset used when placing the unit on a grid cell.
@export_range(0.0, 5.0, 0.01, "suffix:m") var standing_height: float = 1.0
## Presentation of the walk between authorized cells (never legality): smoothing corners within the body clearance (off by default, experimental) and stairs followed on
## their physical treads (stair links the authored scene declares). See PathRefiner and StairModel.
@export var path_presentation: PathPresentationProfile = PathPresentationProfile.new()
@export var stair_profile: StairProfile = StairProfile.new()
## Maximum grid distance for the equipped Prototype 1 weapon.
@export_range(1, 30, 1, "suffix:cells") var attack_range: int = 3
## Scales the damage of every hit this unit's weapon deals (1.0 = the combat tuning's damage).
@export_range(0.1, 3.0, 0.05) var weapon_damage_multiplier: float = 1.0
@export_group("Identity")
@export var faction: Faction = Faction.PLAYER
## Stable battle-local identity used by actions and replay. Display/node names may change.
@export var tactical_id: StringName
## Short name shown to the player (cards, selection, combat messages). Presentation only: actions,
## replay and the AI use tactical_id. Empty falls back to the node name.
@export var display_name := ""
## Starting preset selected by Match Setup. Mechanics query capabilities, not this ID.
@export var archetype_id: StringName = &"generic"
## Prepared for 01.11.4; grants no defensive benefit by itself.
@export var shield_capability: ShieldCapability
@export_flags("Biological", "Mechanical Fluid", "Electronic") var condition_susceptibilities := ConditionDefinition.Susceptibility.MECHANICAL_FLUID | ConditionDefinition.Susceptibility.ELECTRONIC
@export var condition_immunities: Array[StringName] = []
@export_range(0, 9, 1) var emergency_seal_charges := 1
## Optional weapon/test-fixture condition. Ordinary attacks leave this empty.
@export var attack_condition: ConditionDefinition
@export_group("Components")
@export var stats: UnitStats
@export var mission_actor: MissionActor
@export var tactical_state: TacticalState
@export var conditions: ConditionComponent
@export_group("Presentation")
## Disable for isolated presentation tools or fixtures that intentionally have no battle UI layer.
@export var show_world_hud := true
@export var unit_hud_scene: PackedScene = preload("res://ui/unit_world_bar.tscn")
@export var visual_adapter: UnitVisualAdapter
## Show the original Prototype 1 Bean instead of the current character rig.
## Kept as a debug fallback and a tiny piece of FuseFire archaeology.
@export var use_legacy_bean := false
@export_group("")

var current_path: PackedVector3Array = PackedVector3Array()
var grid_position: Vector3i = Vector3i.ZERO
var current_waypoint_idx: int = 0
var is_moving: bool = false
## Suppresses automatic poses while an action service commits authoritative stats.
var defer_stat_presentation := false
## The presented route of the current move (poses, leg kinds, stair runs, the refinement's report), built by TacticalRouteBuilder from the authorised waypoints. This unit EXECUTES the walk (`current_path`
## is what it moves along); the route says how each leg is shown.
var route := TacticalRouteBuilder.Route.new()
var _segment_speed := 0.0
const DEFAULT_MOVEMENT_SPEED := 5.0
var _visual_waypoint := -1
var carried_unit: TacticalUnit
## True while this unit is a rescue target awaiting a carrier. DERIVED from the rescue objective by ObjectiveManager (it is not a new tactical
## state and changes no rule); it only tells the presentation to show the unit incapacitated, on the ground.
var awaiting_rescue := false
var _movement_speed_before_carry := -1
var _leak_particles: CPUParticles3D

func set_awaiting_rescue(value: bool) -> void:
	awaiting_rescue = value
	if visual_adapter:
		visual_adapter.present_incapacitated(value)

func carry_unit(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit) or carried_unit != null:
		return
	carried_unit = unit
	var lying_basis_of = unit.visual_adapter.lying_basis() if is_instance_valid(unit.visual_adapter) else null
	_movement_speed_before_carry = stats.speed
	stats.speed = maxi(2, stats.speed - 2)
	unit.visible = false
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	if visual_adapter:
		# The pickup starts from where and how the rescued unit actually lies.
		visual_adapter.present_pickup(unit.global_position, lying_basis_of)

func get_display_name() -> String:
	return display_name if not display_name.is_empty() else String(name)

## The player-facing name with the stable ID, for logs and debug text: "Alpha (PlayerUnit1)".
func get_log_name() -> String:
	return "%s (%s)" % [display_name, name] if not display_name.is_empty() else String(name)

func is_carrying_unit() -> bool:
	return is_instance_valid(carried_unit)

## Puts the passenger down: it becomes visible and active again and this unit moves at its normal
## speed. Placing it on the grid is the caller's job. Returns the passenger, or null if there was none.
func release_carried_unit() -> TacticalUnit:
	var passenger := carried_unit
	carried_unit = null
	if _movement_speed_before_carry >= 0 and stats:
		stats.speed = _movement_speed_before_carry
	_movement_speed_before_carry = -1
	if is_instance_valid(passenger):
		passenger.visible = true
		passenger.process_mode = Node.PROCESS_MODE_INHERIT
	# The visual passenger the carrier showed is gone with it; the revealed actor is the one that remains.
	if visual_adapter:
		visual_adapter.present_carry_released()
	return passenger if is_instance_valid(passenger) else null

func get_mission_id() -> StringName:
	return mission_actor.mission_id if mission_actor else StringName(name)

func get_mission_actor_kind() -> MissionActor.Kind:
	return mission_actor.kind if mission_actor else MissionActor.Kind.COMBATANT

func can_extract_others() -> bool:
	return mission_actor != null and mission_actor.can_extract_others()

func _ready() -> void:
	_apply_character_presentation()
	if stats:
		stats.defeated.connect(_on_stats_defeated)
		stats.hp_changed.connect(_on_hp_changed)
	if visual_adapter and not use_legacy_bean:
		visual_adapter.setup(self)
	if show_world_hud:
		_spawn_world_hud()
	if conditions and not conditions.changed.is_connected(_refresh_condition_presentation):
		conditions.changed.connect(_refresh_condition_presentation)
	_refresh_condition_presentation()

func can_receive_condition(definition: ConditionDefinition) -> bool:
	if definition == null or condition_immunities.has(definition.condition_id): return false
	if definition.required_susceptibility == 0: return true
	return (condition_susceptibilities & definition.required_susceptibility) == definition.required_susceptibility

## Narrow equipment-resistance hook. Equipment can supply IDs later without a registry.
func is_condition_resisted(condition_id: StringName) -> bool:
	return condition_immunities.has(condition_id)

func _refresh_condition_presentation() -> void:
	var leaking := conditions != null and conditions.has(&"leaking") and stats and not stats.is_defeated
	if leaking and not is_instance_valid(_leak_particles):
		_leak_particles = CPUParticles3D.new()
		_leak_particles.name = "LeakingDroplets"
		_leak_particles.position = Vector3(0, 1.0, 0)
		_leak_particles.amount = 8
		_leak_particles.lifetime = 1.1
		_leak_particles.direction = Vector3.DOWN
		_leak_particles.spread = 18.0
		_leak_particles.initial_velocity_min = 0.25
		_leak_particles.initial_velocity_max = 0.7
		_leak_particles.gravity = Vector3(0, -1.8, 0)
		var droplet := SphereMesh.new()
		droplet.radius = 0.025
		droplet.height = 0.08
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.65, 1.0, 0.85)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		droplet.material = material
		_leak_particles.mesh = droplet
		add_child(_leak_particles)
	if is_instance_valid(_leak_particles):
		_leak_particles.emitting = leaking

func _apply_character_presentation() -> void:
	var bean := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if bean:
		bean.visible = use_legacy_bean
	if visual_adapter:
		visual_adapter.visible = not use_legacy_bean
		visual_adapter.process_mode = Node.PROCESS_MODE_DISABLED if use_legacy_bean else Node.PROCESS_MODE_INHERIT

func _on_stats_defeated() -> void:
	if tactical_state:
		tactical_state.reset()
	if conditions:
		conditions.clear()
	_refresh_condition_presentation()
	if visual_adapter and not defer_stat_presentation:
		visual_adapter.present_defeat()
	defeated.emit(self)

func _on_hp_changed(_current: int, _maximum: int) -> void:
	if visual_adapter and stats and not stats.is_defeated and not defer_stat_presentation:
		visual_adapter.present_hit()

func present_attack_impact(defeated_by_attack: bool) -> void:
	if not visual_adapter:
		return
	if defeated_by_attack:
		visual_adapter.present_defeat()
	else:
		visual_adapter.present_hit()

func _process(delta: float) -> void:
	if not is_moving:
		return

	if current_waypoint_idx >= current_path.size():
		is_moving = false
		if visual_adapter:
			visual_adapter.present_movement_end()
		movement_finished.emit()
		return

	var target_waypoint = current_path[current_waypoint_idx]
	if visual_adapter:
		if _visual_waypoint != current_waypoint_idx:
			_visual_waypoint = current_waypoint_idx
			var segment_state := route.pose_at(current_waypoint_idx)
			_segment_speed = visual_adapter.note_segment(global_position, target_waypoint, segment_state, TacticalRouteBuilder.ladder_toward_deck(current_path, current_waypoint_idx), route.kind_at(current_waypoint_idx))
			var stair_id := route.stair_id_at(current_waypoint_idx)
			if stair_id >= 0:
				var run := route.stair_runs[stair_id]
				visual_adapter.note_stairs(run.model, run.ascending, run.enter, run.exit)
				_segment_speed = TacticalRouteBuilder.stair_segment_speed(stair_profile)
			else:
				visual_adapter.end_stairs()
			visual_adapter.present_path_segment(segment_state)
		visual_adapter.update_locomotion(global_position.direction_to(target_waypoint) * movement_speed, delta)

	global_position = global_position.move_toward(target_waypoint, _presented_speed() * delta)

	if global_position.distance_to(target_waypoint) < 0.01:
		global_position = target_waypoint
		current_waypoint_idx += 1

## The speed at which the current route segment is PRESENTED (see TacticalRouteBuilder.presented_speed): only the time the move takes to show changes; cells, AP, positions and the replay record are untouched.
func _presented_speed() -> float:
	return TacticalRouteBuilder.presented_speed(_segment_speed, movement_speed, DEFAULT_MOVEMENT_SPEED)

## How long the rest of the current route will take to PRESENT, in seconds, at the speeds the walk will use (see TacticalRouteBuilder.estimated_seconds). The action presenter uses it so a slow traversal is
## never mistaken for a stuck one.
func estimated_move_seconds() -> float:
	var traversal_profile: TraversalProfile = visual_adapter.traversal_profile if visual_adapter != null and is_instance_valid(visual_adapter) else null
	return TacticalRouteBuilder.estimated_seconds(route, current_waypoint_idx, global_position, movement_speed, DEFAULT_MOVEMENT_SPEED, stair_profile, traversal_profile)

func move_along_path(path: PackedVector3Array, visual_segments: Array[StringName] = []) -> void:
	if path.size() == 0:
		return
	# The authorised waypoints become the presented route: over the map's surfaces when the map has them (stairs, ramps, ladders, vaults, the corner refinement), exactly as authorised otherwise.
	if visual_adapter and is_instance_valid(visual_adapter.presentation_grid) and visual_adapter.presentation_grid.map_data.surface_placement_enabled:
		route = TacticalRouteBuilder.expand(visual_adapter.presentation_grid.map_data, path, visual_segments, standing_height, stair_profile, path_presentation)
	else:
		route = TacticalRouteBuilder.passthrough(path, visual_segments)
	current_path = route.points
	_visual_waypoint = -1
	current_waypoint_idx = 0
	is_moving = true
	if visual_adapter:
		visual_adapter.present_move()

## Shows an attack that is already resolved. The handle's `shot` settles when the shot is visible (the tactical layer waits on it before the target reacts); it never decides the attack's result.
func present_attack(target_world_position: Vector3) -> AttackHandle:
	var handle: AttackHandle = visual_adapter.present_attack(target_world_position) if visual_adapter else null
	attack_presented.emit(target_world_position)
	if handle == null:
		handle = AttackHandle.new()
		handle.shot.settle(PresentationTypes.Outcome.SKIPPED)
		handle.settle(PresentationTypes.Outcome.SKIPPED)
	return handle

func present_aim() -> void:
	if visual_adapter:
		visual_adapter.present_aim()

func face_world_position(target_world_position: Vector3) -> void:
	if visual_adapter:
		visual_adapter.face_world_position(target_world_position)

## How long a defeated unit's body stays so its one-shot defeat pose is readable (the tactical cleanup floor).
const DEFEAT_REMOVAL_SECONDS := 1.25
## A defeat that never settles (a character that no longer processes) must not keep the body for ever.
const DEFEAT_REMOVAL_DEADLINE_MS := 6000

func finish_defeat_presentation() -> void:
	# Tactical removal has already happened. Leave only the harmless visual body
	# long enough for its one-shot defeat pose to be readable: the presenter's removal handle settles when the
	# defeat has finished and DEFEAT_REMOVAL_SECONDS of presentation time have passed, or when the character is
	# removed. A unit with no processing visual has no lifecycle to observe and keeps the plain floor.
	collision_layer = 0
	collision_mask = 0
	var removal: ActionHandle = null
	if visual_adapter != null and is_instance_valid(visual_adapter) and visual_adapter.can_process():
		removal = visual_adapter.presenter.removal_handle(DEFEAT_REMOVAL_SECONDS)
	if removal != null:
		var deadline := Time.get_ticks_msec() + DEFEAT_REMOVAL_DEADLINE_MS
		while is_inside_tree() and not removal.is_done() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	elif is_inside_tree():
		await get_tree().create_timer(DEFEAT_REMOVAL_SECONDS, false).timeout
	if is_instance_valid(self):
		queue_free()

## The direction this unit's visual faces, horizontal and unit length: a read-only presentation hint (a replay camera's focus), never an input to any rule.
func get_presentation_facing() -> Vector3:
	if visual_adapter != null and is_instance_valid(visual_adapter):
		return visual_adapter.presenter.facing_direction()
	return Vector3.FORWARD

## Shows a direction gameplay authority committed (the Shield stance's facing) exactly as supplied.
func face_committed_direction(direction: Vector2) -> void:
	if visual_adapter:
		visual_adapter.face_committed_direction(direction)

func _spawn_world_hud() -> void:
	if not unit_hud_scene:
		push_warning("[TacticalUnit] %s: unit_hud_scene is missing!" % name)
		return
	if not stats:
		push_warning("[TacticalUnit] %s: stats component reference is missing!" % name)
		return

	var ui_layer: Node = get_tree().get_first_node_in_group("UI_LAYER")
	if not ui_layer:
		push_error("[TacticalUnit] %s: No CanvasLayer found in 'UI_LAYER' group!" % name)
		return

	var hud_instance: UnitWorldBar = unit_hud_scene.instantiate() as UnitWorldBar
	if hud_instance:
		ui_layer.add_child(hud_instance)
		hud_instance.setup(self, stats, faction)
