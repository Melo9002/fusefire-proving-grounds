extends SceneTree
## ADDA Assignment 3: what each tier of diagnostics costs per frame, on one steady workload (a long ladder climbed at a constant rate by the Workbench, so every tier sees the same motion), at a fixed frame rate
## and without rendering. Tiers, cheapest first:
##   0 ADDA disabled               nothing of ADDA is attached
##   1 witness                     PoseWitness listening (every other tool shares it)
##   2 settle watcher              PoseSettle walking every bone each update
##   3 contact overlays            the Workbench contact diagnostics (ContactErrorDiagnostics + markers)
##   4 recorder                    SessionRecorder rows (what `adda run` uses)
##   5 recorder + leg vertices     skinned-mesh sampling against the ladder, every update, every 4th, every 15th
##   6 ladder overlay              LadderClearance + the red-vertex overlay (also skins the legs)
## Then the one-off costs: a StageIsolation (frames and wall time), the analysis, report build and comparison of a recording.
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/adda_overhead_tiers_probe.gd
## Headless frame times exclude rendering and the GPU; they are the CPU cost of the scripts, which is what these tools add. Each tier is measured three times and the median is reported.
const BENCH := "res://tools/animation_workbench/pose_workbench.tscn"
const FRAMES := 180
const REPEATS := 3

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _frame_ms(frames: int) -> float:
	var start := Time.get_ticks_usec()
	await _frames(frames)
	return float(Time.get_ticks_usec() - start) / float(frames) / 1000.0

func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]

func _tier(name: String, results: Array) -> void:
	var samples: Array[float] = []
	for i in REPEATS:
		samples.append(await _frame_ms(FRAMES))
	results.append({"name": name, "ms": _median(samples)})

func _run() -> void:
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.character = &"mira_0"
	WorkbenchSession.armed = false
	var bench: Node3D = (load(BENCH) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(10)
	var rig: CharacterRig = bench.rig
	bench.start_ladder_demo(60.0, 1, 0.25)
	await _frames(60)
	var results := []
	await _tier("0 ADDA disabled", results)
	var witness := PoseWitness.acquire(rig.skeleton)
	await _tier("1 witness only", results)
	var settle := PoseSettle.new(rig.skeleton)
	await _tier("2 + settle watcher", results)
	settle.release()
	witness.release()
	bench.diagnostics.set_contacts(true)
	await _tier("3 contact overlays", results)
	bench.diagnostics.set_contacts(false)
	var recorder := SessionRecorder.attach(rig)
	recorder.start()
	await _tier("4 recorder", results)
	recorder.stop()
	for every in [1, 4, 15]:
		recorder = SessionRecorder.attach(rig)
		recorder.enable_mesh(every)
		recorder.start()
		await _tier("5 recorder + leg vertices every %d" % every, results)
		recorder.stop()
	bench.diagnostics.set_ladder_overlay(true)
	await _tier("6 ladder overlay (skinned legs, every update)", results)
	bench.diagnostics.set_ladder_overlay(false)
	await _tier("0 ADDA disabled (again, drift check)", results)
	var base: float = results[0].ms
	print("ADDA overhead tiers (MIRA unarmed, ladder climb, %d frames x %d, median ms a frame, headless)" % [FRAMES, REPEATS])
	for entry in results:
		print("  %-52s %6.2f ms   %+6.2f ms" % [entry.name, entry.ms, entry.ms - base])
	# One-off: an isolation.
	bench.set_sim_paused(true)
	var wall := Time.get_ticks_usec()
	var frames_before := Engine.get_process_frames()
	var isolation := await StageIsolation.new().measure(rig, [String(rig.bones.right_arm[2])], self)
	var iso_ms := float(Time.get_ticks_usec() - wall) / 1000.0
	var iso_frames := Engine.get_process_frames() - frames_before
	wall = Time.get_ticks_usec()
	frames_before = Engine.get_process_frames()
	await StageIsolation.new().measure(rig, [String(rig.bones.right_arm[2])], self, 150)
	var wide_ms := float(Time.get_ticks_usec() - wall) / 1000.0
	var wide_frames := Engine.get_process_frames() - frames_before
	print("  isolation of one bone: %d frames, %.0f ms wall (status %s); with window 150: %d frames, %.0f ms wall" % [iso_frames, iso_ms, isolation.status, wide_frames, wide_ms])
	bench.set_sim_paused(false)
	# One-off: the recording's analysis.
	bench.end_ladder_demo()
	bench.step_seconds = 1.0 / 60.0
	bench.start_scenario(&"contacts")
	bench.set_sim_paused(true)
	var run_recorder: SessionRecorder = bench.diagnostics.recorder
	var guard := 0
	while bench.scenario_runner.running and guard < 3000:
		bench.step_sim(1)
		await process_frame
		guard += 1
	var rows: Array = run_recorder.rows
	var start := Time.get_ticks_usec()
	var analysis := TimelineAnalysis.analyze(rows)
	var analysis_ms := float(Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var report := AddaReport.build(run_recorder, {"scenario": "contacts", "character": "mira_0"})
	var report_ms := float(Time.get_ticks_usec() - start) / 1000.0
	AddaReport.save(report, "user://adda_tiers.json")
	var kb := FileAccess.get_file_as_bytes("user://adda_tiers.json").size() / 1024
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://adda_tiers.json"))
	print("  recording of %d rows: analysis %.0f ms (%d events), report build %.0f ms, file %d KB" % [rows.size(), analysis_ms, analysis.events.size(), report_ms, kb])
	quit(0)
