extends SceneTree
## Modifier-stack performance baseline (Task 07): CPU time per frame for N production MIRA visuals, headless, idle pose. A BASELINE to compare against after the
## presenter migration, not a pass/fail gate (machine dependent). Run: godot_console --headless --path . --script res://tools/quality/animation_perf_baseline.gd
## Measurement limitation (Task 14 audit): the timed loop repeats within ONE engine frame.
## Frame-id guards skip some per-frame paths; these are comparative idle microbenchmarks,
## not complete rendered-frame or active-interaction costs. Measurement repair is deferred.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const COUNTS := [1, 8, 24]
const WARMUP := 30
const FRAMES := 240

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("animation_perf_baseline: Godot %s, %d warmup + %d measured frames per case" % [Engine.get_version_info().string, WARMUP, FRAMES])
	for count in COUNTS:
		var holder := Node3D.new()
		root.add_child(holder)
		var visuals: Array = []
		for i in count:
			var v: TacticalCharacterAdapter = VISUAL.instantiate()
			holder.add_child(v)
			v.position = Vector3(i % 6 * 1.5, 0, i / 6 * 1.5)
			visuals.append(v)
		for i in WARMUP:
			await process_frame
		# Headless frames are paced by the engine and the process monitor is coarse, so the cost is timed directly: the adapter's own per-frame work (_process) and the full modifier stack
		# (Skeleton3D.advance runs the animation mixer and every modifier) for all characters, many times with different time steps; frame-number guards still apply (see the caveat above).
		# Take the mixer and the modifiers off the automatic schedule so the timing loop below is the only thing driving them.
		for v in visuals:
			v.rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
			v.rig.animation_controller.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var process_samples: Array[float] = []
		var stack_samples: Array[float] = []
		for frame in FRAMES:
			var delta := 1.0 / 60.0 + float(frame % 3) * 0.001
			var t0 := Time.get_ticks_usec()
			for v in visuals:
				v._process(delta)
			var t1 := Time.get_ticks_usec()
			for v in visuals:
				v.rig.animation_controller.animation_tree.advance(delta)
				v.rig.skeleton.advance(delta)
			var t2 := Time.get_ticks_usec()
			process_samples.append((t1 - t0) / 1000.0)
			stack_samples.append((t2 - t1) / 1000.0)
		print("  idle  n=%-3d  adapter _process: %s   AnimationTree + modifier stack: %s" % [count, _stats(process_samples, count), _stats(stack_samples, count)])
		holder.queue_free()
		await process_frame
	quit(0)

func _stats(samples: Array[float], count: int) -> String:
	samples.sort()
	var total := 0.0
	for v in samples:
		total += v
	var mean := total / samples.size()
	return "mean %.3f ms (%.3f ms/char), p95 %.3f ms" % [mean, mean / count, samples[int(samples.size() * 0.95)]]
