extends SceneTree
## Bounded mission-completion evidence for both authored refinery plots.
## Replay is covered separately by refinery_family_ai_smoke.gd.

const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const Layout = preload("res://systems/generation/refinery_family_layout.gd")

const CASES := [
	{"label": "Site A eliminate", "seed": 16, "mission": MissionObjectiveDefinition.Kind.ELIMINATE, "allies": 0},
	{"label": "Site B rescue", "seed": 17, "mission": MissionObjectiveDefinition.Kind.RESCUE, "allies": 1},
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var passed := true
	for test_case: Dictionary in CASES:
		var simulator := AIMatchSimulator.new()
		root.add_child(simulator)
		var result := await simulator.run_match({
			"seed": test_case.seed,
			"mission_kind": test_case.mission,
			"player_count": 3,
			"enemy_count": 2,
			"ally_count": test_case.allies,
			"map_size": Vector2i(64, 64),
			"battlefield_id": Catalog.REFINERY_FAMILY,
			"difficulty": AIDifficultyPolicy.Tier.NORMAL,
			"maximum_rounds": 24,
			"stall_seconds": 6.0,
			"timeout_seconds": 60.0,
		})
		var case_passed := result.map_source == Layout.SOURCE_KIND \
			and result.validation_errors.is_empty() \
			and result.decision_count > 0 \
			and result.status == AIMatchSimulationResult.Status.COMPLETED
		passed = case_passed and passed
		print("Refinery mission %s: %s — %s" % [test_case.label, "PASSED" if case_passed else "FAILED", result.summary()])
		simulator.queue_free()
		await process_frame
	Engine.time_scale = previous_time_scale
	print("Refinery family mission matrix: %s" % ("PASSED" if passed else "FAILED"))
	if not passed:
		push_error("Refinery family mission matrix failed")
	quit(0 if passed else 1)
