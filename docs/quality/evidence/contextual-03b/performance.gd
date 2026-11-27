extends SceneTree
## Run serially. Profile lines bracket planning, presentation and whole frames.
var simulator: AIMatchSimulator
var previous_frame := 0
var previous_phase := "startup"
var previous_transaction := 0
var draw_started := 0
var draw_us := 0
var start := 0
var samples: Dictionary
var hitches: Array[Dictionary]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		Engine.time_scale = 12.0
	else:
		RenderingServer.frame_pre_draw.connect(func(): draw_started = Time.get_ticks_usec())
		RenderingServer.frame_post_draw.connect(func(): draw_us = Time.get_ticks_usec() - draw_started)
	simulator = AIMatchSimulator.new()
	root.add_child(simulator)
	var cases := [
		[BattlefieldCatalog.SERVICE_DEPOT, 3, 950507647],
		[BattlefieldCatalog.CONTEXTUAL_DEPOT, 3, 950507647],
		[BattlefieldCatalog.SERVICE_DEPOT, 5, 16],
		[BattlefieldCatalog.CONTEXTUAL_DEPOT, 5, 16],
	] if headless else [
		[BattlefieldCatalog.CONTEXTUAL_SHOWCASE, 2, 16],
		[BattlefieldCatalog.SERVICE_DEPOT, 3, 950507647],
		[BattlefieldCatalog.CONTEXTUAL_DEPOT, 3, 950507647],
	]
	for data in cases:
		await _match(data)
	quit(0)

func _match(data: Array) -> void:
	samples = {"startup": [], "warmup": [], "planning": [], "action_window": [], "cleanup": []}
	hitches = []
	previous_frame = 0
	previous_phase = "startup"
	previous_transaction = 0
	var site: StringName = data[0]
	var size: int = data[1]
	var seed_value: int = data[2]
	print("[ContextualPerfBegin] ", site, " ", size, "v", size, " seed=", seed_value)
	start = Time.get_ticks_usec()
	_sample()
	process_frame.connect(_sample)
	var result := await simulator.run_match({
		"seed": seed_value, "battlefield_id": site,
		"player_count": size, "enemy_count": size, "map_size": Vector2i(40, 40),
		"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE, "maximum_rounds": 30,
		"enemy_commander": AICommanderPolicy.Profile.CAUTIOUS if site == BattlefieldCatalog.CONTEXTUAL_SHOWCASE else AICommanderPolicy.Profile.DEFAULT,
		"stall_seconds": 25, "timeout_seconds": 140,
	})
	process_frame.disconnect(_sample)
	var sustained: Array = samples.planning + samples.action_window
	var stats := {"sustained": _distribution(sustained)}
	for phase in samples: stats[phase] = _distribution(samples[phase])
	hitches.sort_custom(func(a, b): return a.frame_ms > b.frame_ms)
	print("[ContextualPerf] ", site, " ", size, "v", size, " ", result.summary(),
		" rejected=", result.rejected_action_count, " frames=", JSON.stringify(stats),
		" largest_hitches=", JSON.stringify(hitches.slice(0, 10)))

func _sample() -> void:
	var now := Time.get_ticks_usec()
	var level := simulator.get_child(0) as BattleLevel if simulator.get_child_count() else null
	if previous_frame != 0:
		var interval := float(now - previous_frame) / 1000.0
		samples[previous_phase].append(interval)
		if interval >= 33.3:
			hitches.append({"frame_ms": interval, "elapsed_ms": (now - start) / 1000.0, "begin_phase": previous_phase,
				"begin_transaction": previous_transaction, "draw_ms": (draw_us / 1000.0) if draw_started >= previous_frame else 0.0,
				"engine_process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0})
	previous_frame = now
	if not is_instance_valid(level) or not level.battle_initialization_succeeded:
		previous_phase = "startup" if previous_transaction == 0 else "cleanup"
		return
	var service := level.battle_controller.action_service
	previous_transaction = service.last_transaction_id
	if level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING:
		previous_phase = "cleanup"
	elif previous_transaction == 0:
		previous_phase = "warmup"
	else:
		previous_phase = "action_window" if service.is_busy else "planning"

func _distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {"samples": 0}
	values.sort()
	return {"samples": values.size(), "median": values[ceili(values.size() * 0.5) - 1],
		"p95": values[ceili(values.size() * 0.95) - 1], "p99": values[ceili(values.size() * 0.99) - 1], "max": values[-1]}
