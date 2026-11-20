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
var _visual_segments: Array[StringName] = []
var _segment_speed := 0.0
## Stair walking in the current route: for each waypoint the index of its stair run (or -1) and the runs {model, ascending}.
var _stair_ids: Array[int] = []
var _stair_runs: Array[Dictionary] = []
var last_path_report := {}
## For each waypoint of the current route, what kind of link the leg ending there crosses (TraversalLinkData.UNSPECIFIED/RAMP/STAIRS/LADDER, or VAULT for a low-cover transit).
var _leg_kinds: Array[int] = []
const VAULT_KIND := 10
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
			var segment_state: StringName = _visual_segments[current_waypoint_idx] if current_waypoint_idx < _visual_segments.size() else &"move"
			_segment_speed = visual_adapter.note_segment(global_position, target_waypoint, segment_state, _ladder_toward_deck(current_waypoint_idx), _leg_kind(current_waypoint_idx))
			var stair_id := _stair_ids[current_waypoint_idx] if current_waypoint_idx < _stair_ids.size() else -1
			if stair_id >= 0:
				var run: Dictionary = _stair_runs[stair_id]
				visual_adapter.note_stairs(run.model, run.ascending, run.enter, run.exit)
				_segment_speed = stair_profile.speed if stair_profile.slow_stairs_enabled else 0.0
			else:
				visual_adapter.end_stairs()
			visual_adapter.present_path_segment(segment_state)
		visual_adapter.update_locomotion(global_position.direction_to(target_waypoint) * movement_speed, delta)

	global_position = global_position.move_toward(target_waypoint, _presented_speed() * delta)

	if global_position.distance_to(target_waypoint) < 0.01:
		global_position = target_waypoint
		current_waypoint_idx += 1

## The speed at which the current route segment is PRESENTED. The tactical route is walked at `movement_speed` (5 m/s by default), which would take a 4 m ladder 0.8 s; a
## ladder segment is slower (TraversalProfile.climb_speed / descend_speed), scaled by how far movement_speed is from its default so replay playback speeds still apply.
## Only the time the move takes to show changes: cells, AP, positions and the replay record are untouched.
func _presented_speed() -> float:
	if _segment_speed <= 0.0:
		return movement_speed
	return minf(movement_speed, _segment_speed * movement_speed / DEFAULT_MOVEMENT_SPEED)

## How long the rest of the current route will take to PRESENT, in seconds, at the speeds the walk will use (route speed, stair speed, ladder speeds; all scaled by movement_speed as
## in _presented_speed). The action presenter uses it so a slow traversal is never mistaken for a stuck one.
func estimated_move_seconds() -> float:
	var total := 0.0
	var from := global_position
	for index in range(current_waypoint_idx, current_path.size()):
		var to: Vector3 = current_path[index]
		var speed := movement_speed
		var speed_scale := movement_speed / DEFAULT_MOVEMENT_SPEED
		if index < _stair_ids.size() and _stair_ids[index] >= 0 and stair_profile.slow_stairs_enabled:
			speed = minf(movement_speed, stair_profile.speed * speed_scale)
		elif _leg_kind(index) == TraversalLinkData.LADDER and absf(to.y - from.y) > 0.05 and visual_adapter != null and visual_adapter.traversal_profile != null and visual_adapter.traversal_profile.slow_ladder_enabled:
			var ladder_speed: float = visual_adapter.traversal_profile.climb_speed if to.y > from.y else visual_adapter.traversal_profile.descend_speed
			speed = minf(movement_speed, ladder_speed * speed_scale)
		total += from.distance_to(to) / maxf(speed, 0.01)
		from = to
	return total

func _leg_kind(index: int) -> int:
	return _leg_kinds[index] if index >= 0 and index < _leg_kinds.size() else 0

## For a vertical ladder segment, the horizontal direction from the ladder toward its top deck: the next waypoint after a climb (the step onto the deck) or the previous one
## before a descent (the step off it). ZERO when the segment is not part of such a route.
func _ladder_toward_deck(index: int) -> Vector3:
	if index < 0 or index >= current_path.size():
		return Vector3.ZERO
	var here: Vector3 = current_path[index]
	var before: Vector3 = current_path[index - 1] if index > 0 else here
	var rising := here.y > before.y
	if rising and index + 1 < current_path.size():
		return current_path[index + 1] - here
	if not rising and index > 0 and index - 1 > 0:
		return current_path[index - 2] - before
	return Vector3.ZERO

func move_along_path(path: PackedVector3Array, visual_segments: Array[StringName] = []) -> void:
	if path.size() == 0:
		return
	_stair_ids = []
	_stair_runs = []
	_leg_kinds = []
	last_path_report = {}
	if visual_adapter and is_instance_valid(visual_adapter.presentation_grid) and visual_adapter.presentation_grid.map_data.surface_placement_enabled:
		var data := visual_adapter.presentation_grid.map_data
		var up := Vector3.UP * standing_height
		var expanded := PackedVector3Array([path[0]])
		var poses: Array[StringName] = [visual_segments[0] if not visual_segments.is_empty() else &"move"]
		var stair_ids: Array[int] = [-1]
		var kinds: Array[int] = [0]
		var index := 1
		while index < path.size():
			# A run of authored stair links in one direction is walked ON its treads (StairModel), not as vertical-then-level legs.
			var run_end := _stair_run_end(data, path, index)
			if run_end >= index:
				var model := _stair_model(data, path, index, run_end)
				if model != null:
					var ascending := path[run_end].y > path[index - 1].y
					var points := model.path_points(ascending, stair_profile.riser_ramp, stair_profile.landing_tail)
					for point_index in range(1, points.size()):
						expanded.append(points[point_index] + up)
						poses.append(&"move")
						stair_ids.append(_stair_runs.size())
						kinds.append(TraversalLinkData.STAIRS)
					_stair_runs.append({"model": model, "ascending": ascending, "enter": model.progress_of(path[index - 1] - up), "exit": model.progress_of(path[run_end] - up)})
					index = run_end + 1
					continue
			var from_floor := path[index - 1] - up
			var to_floor := path[index] - up
			var link := SurfaceNavigation.link_between(data, from_floor, to_floor)
			if link != null and link.surface_kind == TraversalLinkData.RAMP:
				# A ramp is a continuous incline: the walk follows the slope, never a vertical pop; it is walked, not climbed. Where the physical ramp ends at the cell boundary
				# (the link's `step_at_to`: a step up onto the deck) the slope runs to that boundary and the step is made there, so the body never goes below the deck.
				var step_up := link.step_at_to
				var toward_to := data.get_cell(link.to_cell).world_position.is_equal_approx(to_floor)   # walking in the link's own direction (entry -> exit)
				var points: Array[Vector3] = []
				if step_up:
					var middle := (from_floor + to_floor) * 0.5
					var upper := to_floor if toward_to else from_floor
					var lower_y := from_floor.y if toward_to else to_floor.y
					var slope_end := Vector3(middle.x, (from_floor.y + to_floor.y) * 0.5, middle.z)
					var lip_top := Vector3(middle.x, upper.y, middle.z)
					if toward_to:
						points = [slope_end, lip_top, to_floor]
					else:
						points = [lip_top, slope_end, to_floor]
					if lower_y > upper.y:
						points = [to_floor]   # defensive: malformed data keeps the plain slope
				else:
					points = [to_floor]
				for point in points:
					expanded.append(point + up)
					poses.append(&"move")
					stair_ids.append(-1)
					kinds.append(TraversalLinkData.RAMP)
				index += 1
				continue
			var route := SurfaceNavigation.traversal_route(data, from_floor, to_floor)
			var kind: int = link.surface_kind if link != null else 0
			if route.size() == 4:
				kind = VAULT_KIND
			for waypoint in range(1, route.size()):
				expanded.append(route[waypoint] + up)
				var pose: StringName = visual_segments[index] if index < visual_segments.size() else &"move"
				if route.size() == 4: pose = &"vault"
				poses.append(pose)
				stair_ids.append(-1)
				kinds.append(kind)
			index += 1
		if path_presentation != null and path_presentation.enabled:
			var refined := _refine_flat_runs(data, expanded, poses, stair_ids, kinds)
			expanded = refined.points
			poses = refined.poses
			stair_ids = refined.stair_ids
			kinds = refined.kinds
		path = expanded
		visual_segments = poses
		_stair_ids = stair_ids
		_leg_kinds = kinds
	current_path = path
	_visual_segments = visual_segments
	_visual_waypoint = -1
	current_waypoint_idx = 0
	is_moving = true
	if visual_adapter:
		visual_adapter.present_move()

## The last path index of the run of consecutive stair links starting at `index` (the leg path[index-1] -> path[index]), or index - 1 when that leg is not a stair link.
func _stair_run_end(data: MapData, path: PackedVector3Array, index: int) -> int:
	if stair_profile == null or not stair_profile.enabled:
		return index - 1
	var up := Vector3.UP * standing_height
	var first := SurfaceNavigation.stair_link(data, path[index - 1] - up, path[index] - up)
	if first == null:
		return index - 1
	var direction := (path[index] - path[index - 1])
	var end := index
	while end + 1 < path.size():
		var next := SurfaceNavigation.stair_link(data, path[end] - up, path[end + 1] - up)
		if next == null or next.treads_per_step != first.treads_per_step:
			break
		var step := path[end + 1] - path[end]
		if not is_equal_approx(step.y, direction.y) or not Vector2(step.x, step.z).is_equal_approx(Vector2(direction.x, direction.z)):
			break   # a turn or a different rise: a separate run (or the ordinary route)
		end += 1
	return end

func _stair_model(data: MapData, path: PackedVector3Array, first: int, last: int) -> StairModel:
	var up := Vector3.UP * standing_height
	var from_floor := path[first - 1] - up
	var to_floor := path[last] - up
	var link := SurfaceNavigation.stair_link(data, path[first - 1] - up, path[first] - up)
	var links := last - first + 1
	var leg := path[first] - path[first - 1]
	var run := Vector2(leg.x, leg.z).length()
	var low := from_floor if from_floor.y < to_floor.y else to_floor
	var high := to_floor if from_floor.y < to_floor.y else from_floor
	return StairModel.from_links(low, high, run, absf(leg.y), link.treads_per_step, links)

## Smooths the corners of each horizontal run of the route within the body clearance (PathRefiner). Points inherit the pose and stair id of the original point they replace; a route
## the physical geometry does not support is reported in `last_path_report` and left exactly as it was.
func _refine_flat_runs(data: MapData, points: PackedVector3Array, poses: Array[StringName], stair_ids: Array[int], kinds: Array[int]) -> Dictionary:
	var up := Vector3.UP * standing_height
	var radius := data.body_radius + data.body_clearance - data.surface_unit / 10000.0
	var out := PackedVector3Array([points[0]])
	var out_poses: Array[StringName] = [poses[0]]
	var out_ids: Array[int] = [stair_ids[0]]
	var out_kinds: Array[int] = [kinds[0]]
	var mismatches: Array[String] = []
	var rounded := 0
	var i := 0
	var count := points.size()
	while i < count - 1:
		var j := i + 1
		if absf(points[i + 1].y - points[i].y) <= PathRefiner.FLAT:
			while j + 1 < count and absf(points[j + 1].y - points[i].y) <= PathRefiner.FLAT:
				j += 1
		if j - i >= 2:
			var run := PackedVector3Array()
			for k in range(i, j + 1):
				run.append(points[k] - up)
			var result := PathRefiner.refine(run, data.movement_parts, radius, data.body_height, path_presentation)
			mismatches.append_array(result.mismatches)
			rounded += int(result.rounded)
			for k in range(1, result.path.size()):
				var original := i + int(result.sources[k])
				out.append(result.path[k] + up)
				out_poses.append(poses[original])
				out_ids.append(stair_ids[original])
				out_kinds.append(kinds[original])
		else:
			out.append(points[j])
			out_poses.append(poses[j])
			out_ids.append(stair_ids[j])
			out_kinds.append(kinds[j])
		i = j
	last_path_report = {"mismatches": mismatches, "rounded": rounded}
	if not mismatches.is_empty():
		return {"points": points, "poses": poses, "stair_ids": stair_ids, "kinds": kinds}
	return {"points": out, "poses": out_poses, "stair_ids": out_ids, "kinds": out_kinds}

func present_attack(target_world_position: Vector3) -> void:
	if visual_adapter:
		visual_adapter.present_attack(target_world_position)
	attack_presented.emit(target_world_position)

## True while the visual attack is still raising the weapon, before the shot is shown.
func is_attack_pending() -> bool:
	return visual_adapter != null and is_instance_valid(visual_adapter) and visual_adapter.is_attack_pending()

func present_aim() -> void:
	if visual_adapter:
		visual_adapter.present_aim()

func face_world_position(target_world_position: Vector3) -> void:
	if visual_adapter:
		visual_adapter.face_world_position(target_world_position)

func finish_defeat_presentation() -> void:
	# Tactical removal has already happened. Leave only the harmless visual body
	# long enough for its one-shot defeat pose to be readable.
	collision_layer = 0
	collision_mask = 0
	await get_tree().create_timer(1.25, false).timeout
	if is_instance_valid(self):
		queue_free()

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
