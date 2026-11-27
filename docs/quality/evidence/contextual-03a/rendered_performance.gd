extends SceneTree
## Whole-match visible frame samples. Run with "-- profile-ai". Timings cover
## scene setup and real combat windows as well as per-decision logs.
var last := 0
var samples: Array[float] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	for fixture in [
		{"label": "bay", "site": BattlefieldCatalog.CONTEXTUAL_BAY, "count": 1, "seed": 2},
		{"label": "depot", "site": BattlefieldCatalog.SERVICE_DEPOT, "count": 3, "seed": 950507647},
	]:
		var clocks := _sample
		last = 0
		samples.clear()
		process_frame.connect(clocks)
		print("[FrameBegin] ",fixture.label)
		var result := await simulator.run_match({
			"seed": fixture.seed, "battlefield_id": fixture.site,
			"player_count": fixture.count, "enemy_count": fixture.count,
			"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE,
			"map_size": Vector2i(40, 40),
			"maximum_rounds": 30, "stall_seconds": 30, "timeout_seconds": 150,
		})
		process_frame.disconnect(clocks)
		samples.sort()
		var p95 := samples[ceili(samples.size() * 0.95) - 1] if not samples.is_empty() else -1.0
		var max_frame := samples[-1] if not samples.is_empty() else -1.0
		print("[FrameMatch] ",fixture.label," n=", samples.size()," p95_ms=",p95," max_ms=",max_frame,
			" rejected=",result.rejected_action_count," ",result.summary())
		if not result.completed() or result.rejected_action_count != 0:
			quit(1)
			return
	quit(0)

func _sample() -> void:
	var now := Time.get_ticks_usec()
	if last != 0: samples.append(float(now - last) / 1000.0)
	last = now
