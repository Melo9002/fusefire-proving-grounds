extends SceneTree
## What ADDA's Assignment-2 instruments cost. Run on a real Workbench rig mid-climb, at a fixed frame rate:
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/adda_overhead_probe.gd
## Prints microseconds per call for the recorder's row, the leg-vertex sample, the analysis of a whole 13 s run, and building and saving the report, plus the whole-frame cost with and without the recorder.
const BENCH := "res://tools/animation_workbench/pose_workbench.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _time(count: int, work: Callable) -> float:
	var start := Time.get_ticks_usec()
	for i in count:
		work.call()
	return float(Time.get_ticks_usec() - start) / float(count)

func _frame_ms(bench: Node3D, frames: int) -> float:
	var start := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	return float(Time.get_ticks_usec() - start) / float(frames) / 1000.0

func _run() -> void:
	var bench: Node3D = (load(BENCH) as PackedScene).instantiate()
	root.add_child(bench)
	WorkbenchSession.autostart_scenario = &""
	for i in 4:
		await process_frame
	var rig: CharacterRig = bench.rig
	bench.start_scenario(&"contacts")
	bench.diagnostics.end_recording()
	await _frames(60)
	var bare := await _frame_ms(bench, 120)
	var recorder := SessionRecorder.attach(rig)
	recorder.start()
	var recorded := await _frame_ms(bench, 120)
	recorder.stop()
	recorder.enable_mesh(1)
	recorder.start()
	await _frames(240)   # the climb: ladder rows with the leg-vertex sampler
	var meshed := await _frame_ms(bench, 120)
	recorder.stop()
	# The recorded runs, for the offline costs.
	bench.scenario_runner.stop()
	bench.start_scenario(&"contacts")
	bench.set_sim_paused(true)
	bench.step_seconds = 1.0 / 60.0
	var run_recorder: SessionRecorder = bench.diagnostics.recorder
	var guard := 0
	while bench.scenario_runner.running and guard < 3000:
		bench.step_sim(1)
		await process_frame
		guard += 1
	var rows: Array = run_recorder.rows
	var analysis_us := _time(5, func() -> void: TimelineAnalysis.analyze(rows))
	var report_us := _time(3, func() -> void: AddaReport.build(run_recorder, {"scenario": "contacts", "character": "mira_0"}))
	var report := AddaReport.build(run_recorder, {"scenario": "contacts", "character": "mira_0"})
	AddaReport.save(report, "user://adda_overhead.json")
	var size_kb := FileAccess.get_file_as_bytes("user://adda_overhead.json").size() / 1024
	var full := AddaReport.build(run_recorder, {"scenario": "contacts", "character": "mira_0", "detail": "full"})
	AddaReport.save(full, "user://adda_overhead_full.json")
	var full_kb := FileAccess.get_file_as_bytes("user://adda_overhead_full.json").size() / 1024
	var compare_us := _time(50, func() -> void: ReportCompare.compare(report, report))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://adda_overhead.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://adda_overhead_full.json"))
	print("ADDA overhead (frame %.2f ms bare, %.2f ms recording, %.2f ms recording with leg-vertex sampling on a climb)" % [bare, recorded, meshed])
	print("  recorder: %+.2f ms a frame; leg-vertex sampling adds %+.2f ms a frame" % [recorded - bare, meshed - recorded])
	print("  analysis of %d rows: %.1f ms; report build %.1f ms; compare %.0f us" % [rows.size(), analysis_us / 1000.0, report_us / 1000.0, compare_us])
	print("  report file: %d KB (summary), %d KB (every row); %d rows kept in memory" % [size_kb, full_kb, rows.size()])
	quit(0)

func _frames(count: int) -> void:
	for i in count:
		await process_frame
