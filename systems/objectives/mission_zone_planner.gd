class_name MissionZonePlanner
extends RefCounted

const ZONE_SIZE := 4
const CARDINALS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
const DEFAULT_ZONE_IDS: Array[StringName] = [&"reach", &"extract", &"enemy_extract", &"rescue_spawn", &"terminal"]

static func has_complete_defaults(map_data: MapData) -> bool:
	for zone_id in DEFAULT_ZONE_IDS:
		if map_data.get_objective_zone(zone_id).is_empty():
			return false
	return true

static func populate_defaults(map_data: MapData, pathfinder: Pathfinder) -> void:
	var evaluator := MissionPlacementEvaluator.new(map_data, pathfinder)
	var candidates := evaluator.legal_candidates()
	var reach := _place_zone(candidates, evaluator, Callable(evaluator, "score_reach"), Callable(evaluator, "is_reach_candidate"))
	map_data.set_objective_zone(&"reach", reach)
	evaluator.reserve(reach)
	var extraction := _place_zone(candidates, evaluator, Callable(evaluator, "score_friendly_extract"), Callable(evaluator, "is_friendly_extract_candidate"))
	map_data.set_objective_zone(&"extract", extraction)
	evaluator.reserve(extraction)
	var enemy_extraction := _place_zone(candidates, evaluator, Callable(evaluator, "score_enemy_extract"), Callable(evaluator, "is_enemy_extract_candidate"))
	map_data.set_objective_zone(&"enemy_extract", enemy_extraction)
	evaluator.reserve(enemy_extraction)
	var rescue := _best_available(candidates, evaluator, Callable(evaluator, "score_rescue"))
	var rescue_zone: Array[Vector3i] = []
	if rescue.x >= 0:
		rescue_zone.append(rescue)
	map_data.set_objective_zone(&"rescue_spawn", rescue_zone)
	evaluator.reserve(rescue_zone)
	# Terminal planning comes last so this optional objective cannot shift the
	# established layouts of missions that do not use a terminal.
	var terminal := _best_eligible(candidates, evaluator, Callable(evaluator, "score_terminal"), Callable(evaluator, "is_terminal_candidate"))
	var terminal_zone: Array[Vector3i] = []
	if terminal.x >= 0:
		terminal_zone.append(terminal)
	map_data.set_objective_zone(&"terminal", terminal_zone)

static func find_rescue_cell(map_data: MapData) -> Vector3i:
	var cells := map_data.get_objective_zone(&"rescue_spawn")
	return cells[0] if not cells.is_empty() else Vector3i(-1, -1, -1)

static func _place_zone(candidates: Array[Vector3i], evaluator: MissionPlacementEvaluator, scorer: Callable, eligibility: Callable) -> Array[Vector3i]:
	var best_zone: Array[Vector3i] = []
	var best_score := -INF
	for anchor in candidates:
		if evaluator.blocked.has(anchor) or not eligibility.call(anchor):
			continue
		var zone := _grow_zone(anchor, candidates, evaluator)
		if zone.size() != ZONE_SIZE:
			continue
		var score: float = scorer.call(anchor)
		if score > best_score or (is_equal_approx(score, best_score) and _comes_first(anchor, best_zone[0] if not best_zone.is_empty() else Vector3i(-1, -1, -1))):
			best_zone = zone
			best_score = score
	return best_zone

static func _grow_zone(anchor: Vector3i, candidates: Array[Vector3i], evaluator: MissionPlacementEvaluator) -> Array[Vector3i]:
	var zone: Array[Vector3i] = [anchor]
	var frontier: Array[Vector3i] = [anchor]
	var head := 0
	while head < frontier.size() and zone.size() < ZONE_SIZE:
		var current: Vector3i = frontier[head]
		head += 1
		for direction in CARDINALS:
			var neighbor: Vector3i = current + direction
			if neighbor.y == anchor.y and candidates.has(neighbor) and not evaluator.blocked.has(neighbor) and not zone.has(neighbor):
				zone.append(neighbor)
				frontier.append(neighbor)
				if zone.size() == ZONE_SIZE:
					break
	return zone

static func _best_available(candidates: Array[Vector3i], evaluator: MissionPlacementEvaluator, scorer: Callable) -> Vector3i:
	return _best_eligible(candidates, evaluator, scorer, Callable())

static func _best_eligible(candidates: Array[Vector3i], evaluator: MissionPlacementEvaluator, scorer: Callable, eligibility: Callable) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_score := -INF
	for position in candidates:
		if evaluator.blocked.has(position) or (eligibility.is_valid() and not eligibility.call(position)):
			continue
		var score: float = scorer.call(position)
		if score > best_score or (is_equal_approx(score, best_score) and _comes_first(position, best)):
			best = position
			best_score = score
	return best

static func _comes_first(candidate: Vector3i, current: Vector3i) -> bool:
	if current.x < 0:
		return true
	if candidate.y != current.y:
		return candidate.y < current.y
	if candidate.x != current.x:
		return candidate.x < current.x
	return candidate.z < current.z
