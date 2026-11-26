extends SceneTree
## Compare the exact same authored manifests and match configurations on the
## historical cargo box and split shot bounds. Run with "-- profile-ai".

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.time_scale = 12.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var configs := [
		{"seed": 950507647, "count": 3},
		{"seed": 16, "count": 5},
	]
	var unfinished := 0
	for fixture in configs:
		var seed_value: int = fixture.seed
		var generated := BattlefieldCatalog.generate(BattlefieldCatalog.SERVICE_DEPOT, Vector2i.ZERO, seed_value, 1.0)
		for revision in [9, 10]:
			var manifest := generated.content_manifest.duplicate(true)
			manifest.compiler_revision = revision
			print("[CoverBenchmarkBegin] seed=", seed_value, " count=", fixture.count, " compiler=", revision)
			var result := await simulator.run_match({
				"seed": seed_value,
				"battlefield_id": BattlefieldCatalog.SERVICE_DEPOT,
				"map_size": Vector2i(40, 40),
				"player_count": fixture.count, "enemy_count": fixture.count,
				"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE,
				"difficulty": AIDifficultyPolicy.Tier.NORMAL,
				"content_manifest": manifest,
				"maximum_rounds": 35, "stall_seconds": 12.0, "timeout_seconds": 60.0,
			})
			print("[CoverBenchmarkResult] ",result.summary())
			if not result.completed() or result.rejected_action_count != 0: unfinished += 1
	simulator.queue_free()
	await process_frame
	quit(0 if unfinished == 0 else 1)
