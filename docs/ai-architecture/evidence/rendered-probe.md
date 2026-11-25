# Reproduce the normal-speed frame probe

[Performance report](../performance.md#rendered-normal-speed-sample) · [Observed data](samples.json)

This is the temporary Step 12 probe reused for this research, with its output path pointed at this run. Save the GDScript below as `artifacts/ai-architecture-research/rendered_probe.gd`. The project needs an existing import cache. Run alone, with a writable user-data location.

~~~powershell
$dir = (Resolve-Path artifacts/ai-architecture-research).Path
godot_console --path . --resolution 1280x720 --max-fps 60 --rendering-method gl_compatibility --log-file "$dir/rendered-engine.log" --script res://artifacts/ai-architecture-research/rendered_probe.gd -- profile-ai *> "$dir/rendered-probe.log"
~~~

The exit code tests whether the capture was reached. Check `[RenderedResult]` independently for completion or timeout, `[RenderedCapture]` for the screenshot save status, and the logs for script errors. Capture startup separately for steady-state comparisons. Each recorded frame interval is labeled with the latest transaction at the sampling instant. The initial interval and later busy samples can include work from multiple owners.

~~~gdscript
extends SceneTree

var simulator: AIMatchSimulator
var previous_tick := 0
var intervals: Array[float] = []
var worst: Array[Dictionary] = []
var capture_started := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.time_scale = 1.0
	simulator = AIMatchSimulator.new()
	root.add_child(simulator)
	process_frame.connect(_sample)
	var result := await simulator.run_match({
		"seed": 16, "battlefield_id": BattlefieldCatalog.SERVICE_DEPOT,
		"map_size": Vector2i(40, 40), "mission_kind": MissionObjectiveDefinition.Kind.RESCUE,
		"difficulty": AIDifficultyPolicy.Tier.HARD, "player_count": 5, "enemy_count": 5, "ally_count": 1,
		"timeout_seconds": 75.0, "stall_seconds": 15.0, "maximum_rounds": 30,
	})
	intervals.sort()
	if not intervals.is_empty():
		print("[RenderedFrames] ", JSON.stringify({"count": intervals.size(), "median_ms": intervals[intervals.size() / 2],
			"p95_ms": intervals[ceili(intervals.size() * 0.95) - 1], "max_ms": intervals.back(), "worst": worst}))
	print("[RenderedResult] ", result.summary())
	quit(0 if capture_started else 1)

func _sample() -> void:
	if simulator.get_child_count() == 0:
		return
	var level := simulator.get_child(0) as BattleLevel
	if not is_instance_valid(level) or level.turn_manager.current_round <= 0:
		return
	var service := level.battle_controller.action_service
	var now := Time.get_ticks_usec()
	if previous_tick > 0:
		var interval := float(now - previous_tick) / 1000.0
		intervals.append(interval)
		if worst.size() < 10 or interval > worst.back().ms:
			worst.append({"ms": interval, "last_transaction": service.last_transaction_id, "busy": service.is_busy})
			worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
			if worst.size() > 10:
				worst.pop_back()
	previous_tick = now
	if not capture_started and service.last_transaction_id >= 40:
		capture_started = true
		_capture.call_deferred()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://artifacts/ai-architecture-research/depot-rescue-rendered.png")
	print("[RenderedCapture] ", error)
~~~
