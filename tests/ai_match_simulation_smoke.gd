extends SceneTree

const FailureReporter := preload("res://systems/simulation/seed_failure_reporter.gd")

const MISSION_KINDS: Array[MissionObjectiveDefinition.Kind] = [
	MissionObjectiveDefinition.Kind.ELIMINATE,
	MissionObjectiveDefinition.Kind.PROTECT,
	MissionObjectiveDefinition.Kind.RESCUE,
	MissionObjectiveDefinition.Kind.REACH,
	MissionObjectiveDefinition.Kind.SURVIVE,
	MissionObjectiveDefinition.Kind.EXTRACT,
	MissionObjectiveDefinition.Kind.ENEMY_EVACUATION,
	MissionObjectiveDefinition.Kind.INTERACT_TERMINAL,
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var first_seed := _positive_argument(arguments, 0, 23001)
	var match_count := _positive_argument(arguments, 1, MISSION_KINDS.size())
	var mission_offset := _non_negative_argument(arguments, 2, 0) % MISSION_KINDS.size()
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 12.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var batch := AIMatchSimulationBatch.new()
	for index in match_count:
		var mission_kind := MISSION_KINDS[(mission_offset + index) % MISSION_KINDS.size()]
		batch.add(await simulator.run_match({
			"seed": first_seed + index,
			"mission_kind": mission_kind,
			"player_count": 2,
			"enemy_count": 2,
			"ally_count": 1 if mission_kind in [MissionObjectiveDefinition.Kind.PROTECT, MissionObjectiveDefinition.Kind.RESCUE] else 0,
			"include_vip": mission_kind == MissionObjectiveDefinition.Kind.PROTECT,
			"battlefield_id": BattlefieldCatalog.SERVICE_DEPOT,
			"map_size": Generation2.DEPOT_SIZE,
			"maximum_rounds": 20,
			"stall_seconds": 4.0,
			"timeout_seconds": 20.0,
		}))
	Engine.time_scale = previous_time_scale
	print("[AISim] BATCH — %s" % batch.summary())
	for result in batch.results:
		if not result.completed():
			print("[AISim] ISSUE — %s" % result.summary())
			var report_path := FailureReporter.save(result)
			if not report_path.is_empty():
				print("[AISim] FAILURE REPORT — %s" % report_path)
	quit(1 if batch.issue_count() else 0)

func _positive_argument(arguments: PackedStringArray, index: int, fallback: int) -> int:
	if index >= arguments.size() or not arguments[index].is_valid_int():
		return fallback
	return maxi(1, arguments[index].to_int())

func _non_negative_argument(arguments: PackedStringArray, index: int, fallback: int) -> int:
	if index >= arguments.size() or not arguments[index].is_valid_int():
		return fallback
	return maxi(0, arguments[index].to_int())
