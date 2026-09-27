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
]

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var batch := AIMatchSimulationBatch.new()
	var sources: Dictionary[String, int] = {}
	var sizes: Dictionary[Vector2i, int] = {}
	var elevated_matches := 0
	var traversal_matches := 0
	for pass_index in 2:
		for mission_index in MISSION_KINDS.size():
			var mission_kind := MISSION_KINDS[mission_index]
			var refinery := pass_index == 1 and mission_index % 2 == 0
			var dimensions := Vector2i(40, 30) if refinery else FlatMapGenerator.MAP_SIZES[(pass_index + mission_index) % FlatMapGenerator.MAP_SIZES.size()]
			var uses_allied_faction := mission_kind in [MissionObjectiveDefinition.Kind.PROTECT, MissionObjectiveDefinition.Kind.RESCUE]
			var result := await simulator.run_match({
				"seed": 25000 + pass_index * 100 + mission_index,
				"mission_kind": mission_kind,
				"player_count": 4 if uses_allied_faction else 5,
				"ally_count": 1 if uses_allied_faction else 0,
				"enemy_count": 5,
				"include_vip": mission_kind == MissionObjectiveDefinition.Kind.PROTECT,
				"map_size": dimensions,
				"refinery": refinery,
				"difficulty": AIDifficultyPolicy.Tier.NORMAL,
				"maximum_rounds": 30,
				"stall_seconds": 6.0,
				"timeout_seconds": 35.0,
			})
			batch.add(result)
			_record_coverage(result, sources, sizes)
			elevated_matches += int(result.elevated_cell_count > 0)
			traversal_matches += int(result.traversal_link_count > 0)
	var authored := await simulator.run_match({
		"seed": 25200,
		"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE,
		"player_count": 5,
		"ally_count": 0,
		"enemy_count": 5,
		"generated_map": false,
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 30,
		"stall_seconds": 6.0,
		"timeout_seconds": 35.0,
	})
	batch.add(authored)
	_record_coverage(authored, sources, sizes)
	elevated_matches += int(authored.elevated_cell_count > 0)
	traversal_matches += int(authored.traversal_link_count > 0)
	Engine.time_scale = previous_time_scale

	check(batch.results.size() == 15, "Milestone matrix executes fourteen generated and one authored 5v5 match")
	check(batch.issue_count() == 0, "Every milestone match completes without a stall, timeout, round limit, or setup failure")
	for mission_kind in MISSION_KINDS:
		var mission_id := MissionCatalog.create_mission(mission_kind, 5).mission_id
		check(batch.results.filter(func(result: AIMatchSimulationResult): return result.mission_id == mission_id).size() >= 2, "Mission %s is exercised repeatedly" % mission_id)
	check(sources.has("generated_cover"), "Milestone covers standard generated maps")
	check(sources.has("generated_refinery"), "Milestone covers generated refinery maps")
	check(sources.has("authored"), "Milestone covers the authored test map")
	for dimensions in FlatMapGenerator.MAP_SIZES:
		check(sizes.has(dimensions), "Milestone covers generated map size %s" % dimensions)
	check(elevated_matches >= 10, "Milestone exercises elevation in most matches")
	check(traversal_matches >= 10, "Milestone exercises traversal links in most matches")
	print("[Prototype1] MATRIX — %s | sources %s | sizes %s | elevated %d | traversals %d" % [batch.summary(), sources, sizes, elevated_matches, traversal_matches])
	for result in batch.results:
		if not result.completed():
			print("[Prototype1] ISSUE — %s" % result.summary())
			var report_path := FailureReporter.save(result)
			if not report_path.is_empty():
				print("[Prototype1] FAILURE REPORT — %s" % report_path)
	print("Prototype 1 milestone: %d failure(s)" % failures)
	simulator.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _record_coverage(result: AIMatchSimulationResult, sources: Dictionary[String, int], sizes: Dictionary[Vector2i, int]) -> void:
	sources[result.map_source] = sources.get(result.map_source, 0) + 1
	sizes[result.map_size] = sizes.get(result.map_size, 0) + 1

