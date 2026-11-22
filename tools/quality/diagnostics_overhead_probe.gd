extends SceneTree
## Measures what the Task 12 diagnostics cost per frame on the workbench's rig (headless: CPU time of the diagnostic work only, not rendering). Run:
##   godot --headless --path . --script res://tools/quality/diagnostics_overhead_probe.gd
const SCENE := "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn"
const ROUNDS := 2000

func _initialize() -> void:
	_run.call_deferred()

func _time(label: String, work: Callable) -> void:
	var start := Time.get_ticks_usec()
	for i in ROUNDS:
		work.call()
	print("  %-44s %7.1f us per call" % [label, float(Time.get_ticks_usec() - start) / ROUNDS])

func _run() -> void:
	var host: ExplorationCharacterHost = (load(SCENE) as PackedScene).instantiate()
	root.add_child(host)
	for i in 30:
		await process_frame
	var rig: CharacterRig = host.rig
	rig.begin_traversal(&"ladder", 4.0, 1)
	rig.set_traversal_progress(2.0)
	for i in 10:
		await process_frame
	var monitor := PresentationMonitor.attach(rig)
	var contacts := ContactErrorDiagnostics.attach(rig)
	contacts.set_enabled(true)
	for i in 5:
		await process_frame
	print("diagnostics_overhead_probe (CPU, %d calls each):" % ROUNDS)
	_time("PresentationMonitor.refresh (snapshot + diff)", func() -> void: monitor.refresh())
	_time("ContactErrorDiagnostics.measure", func() -> void: contacts.measure())
	_time("ContactErrorDiagnostics measure + draw", func() -> void:
		contacts.latest = contacts.measure()
		contacts._draw(contacts.latest))
	_time("PoseStageReport.stages (8 stages)", func() -> void: PoseStageReport.stages(rig))
	_time("PoseStageReport.text", func() -> void: PoseStageReport.text(rig))
	_time("RigInspection.report", func() -> void: RigInspection.report(rig))
	var frames := 300
	var start := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	print("  whole frame with monitor + contact overlay on: %.2f ms (headless, includes the rig's own work)" % (float(Time.get_ticks_usec() - start) / frames / 1000.0))
	contacts.set_enabled(false)
	monitor.shutdown()
	for i in 5:
		await process_frame
	start = Time.get_ticks_usec()
	for i in frames:
		await process_frame
	print("  whole frame with both off:                     %.2f ms" % (float(Time.get_ticks_usec() - start) / frames / 1000.0))
	quit()
