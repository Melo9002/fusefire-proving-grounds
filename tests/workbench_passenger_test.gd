extends SceneTree
## The ADDA Workbench with a carrier and a casualty chosen independently (animation assignment): the session and its reproduction line, the Character tab's selector, a clean reset when the casualty changes, and the
## loaded-ladder scenario played to its end for every pairing with the recorder listening, whose report names who carried whom and whose command line reproduces it. Real time per run: a few seconds each.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const IDS: Array[StringName] = [&"mira_0", &"small_mira_0"]

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _bench(carrier: StringName, passenger: StringName, armed := false) -> Node3D:
	WorkbenchSession.character = carrier
	WorkbenchSession.passenger = passenger
	WorkbenchSession.armed = armed
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = WorkbenchPanel.index_of(&"Character")
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(10)
	return bench


func _run() -> void:
	await _session_and_selector()
	await _scenario_definition()
	for carrier in IDS:
		for passenger in IDS:
			await _scenario_run(carrier, passenger)
	WorkbenchSession.passenger = &""
	WorkbenchSession.character = &""
	WorkbenchSession.armed = true
	WorkbenchSession.start_tab = -1
	print("workbench_passenger_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


func _session_and_selector() -> void:
	WorkbenchSession.passenger = &""
	check(not WorkbenchSession.repro_command(&"loaded_ladder").contains("--passenger"), "With no passenger chosen the reproduction line names none")
	WorkbenchSession.character = &"small_mira_0"
	WorkbenchSession.passenger = &"mira_0"
	var command := WorkbenchSession.repro_command(&"loaded_ladder")
	check(command.contains("--character=small_mira_0") and command.contains("--passenger=mira_0") and command.contains("--scenario=loaded_ladder"), "The reproduction line names the carrier, the passenger and the scenario (%s)" % command)
	var bench := await _bench(&"mira_0", &"small_mira_0")
	var rig: CharacterRig = bench.rig
	check(rig.passenger_definition != null and rig.passenger_definition.character_id == &"small_mira_0", "A launch with a chosen passenger gives the rig that body")
	rig.begin_carry()
	await _frames(5)
	check(rig.carry_passenger.definition.character_id == &"small_mira_0", "and a carry builds it, whatever the carrier is")
	# The Character tab: choose the casualty without reloading.
	var tab: CharacterTab = bench.panel.tab_named(&"Character")
	check(tab != null and tab._passenger_choice != null and tab._passenger_choice.item_count == 3, "The Character tab has a passenger selector with the same-as-carrier choice and both models")
	check(tab._passenger_note.text.contains("small_mira_0"), "and says who is carried (%s)" % tab._passenger_note.text)
	tab._passenger_choice.select(1)   # the first model in the list
	tab._apply_passenger()
	await _frames(5)
	check(not is_instance_valid(rig.carry_passenger) and rig.loaded_ladder == null and rig.ladder == null, "Changing the casualty lets go of the one carried: a clean reset, nothing orphaned")
	var chosen: StringName = bench.CHARACTER_RIGS.keys()[0]
	check(WorkbenchSession.passenger == chosen and rig.passenger_definition.character_id == chosen, "and the choice is kept for the session and applied to the rig")
	check(WorkbenchSession.character == &"mira_0", "while the carrier is still the carrier it was")
	tab._passenger_choice.select(0)
	tab._apply_passenger()
	await _frames(2)
	check(WorkbenchSession.passenger == &"" and rig.passenger_definition == null and tab._passenger_note.text.contains("own kind"), "Choosing 'same as the carrier' goes back to the carrier's own kind")
	bench.queue_free()
	await _frames(2)


func _scenario_definition() -> void:
	var definition := WorkbenchScenarios.find(WorkbenchScenarios.LOADED_LADDER)
	check(not definition.is_empty() and WorkbenchScenarios.all().size() == 6, "The loaded-ladder scenario is one of the workbench's presets")
	var bench := await _bench(&"mira_0", &"")
	check(bool(WorkbenchScenarios.supported(definition, bench.rig).ok), "and runs unarmed")
	bench.queue_free()
	await _frames(2)
	bench = await _bench(&"mira_0", &"", true)
	check(bool(WorkbenchScenarios.supported(definition, bench.rig).ok), "and armed (the weapon is slung while carrying)")
	bench.queue_free()
	await _frames(2)


func _scenario_run(carrier: StringName, passenger: StringName) -> void:
	var label := "%s carries %s" % [carrier, passenger]
	var bench := await _bench(carrier, passenger)
	var rig: CharacterRig = bench.rig
	var recorder := SessionRecorder.attach(rig)
	recorder.clock = func() -> float: return float(bench.scenario_runner.time) if bench.scenario_runner.running else -1.0
	bench.scenario_runner.step_run.connect(func(_index: int, step_label: String) -> void: recorder.mark(step_label, "scenario step"))
	recorder.start()
	check(bench.start_scenario(WorkbenchScenarios.LOADED_LADDER, false), "%s: the scenario starts" % label)
	bench.set_sim_paused(true)
	bench.step_seconds = 1.0 / 30.0
	var saw_loaded_up := false
	var saw_loaded_down := false
	var identity_held := true
	var guard := 0
	while bench.scenario_runner.running and guard < 1200:
		guard += 1
		bench.step_sim()
		await process_frame
		if rig.loaded_ladder != null and rig.ladder != null:
			saw_loaded_up = saw_loaded_up or rig.ladder.direction > 0
			saw_loaded_down = saw_loaded_down or rig.ladder.direction < 0
		if is_instance_valid(rig.carry_passenger):
			identity_held = identity_held and rig.carry_passenger.definition.character_id == passenger
	recorder.stop()
	check(not bench.scenario_runner.running, "%s: the scenario runs to its end (%d steps)" % [label, guard])
	check(saw_loaded_up and saw_loaded_down, "%s: it climbs and descends with the loaded presentation" % label)
	check(identity_held, "%s: the casualty is itself at every step" % label)
	check(not is_instance_valid(rig.carry_passenger) and rig.loaded_ladder == null, "%s: it ends with the casualty put down and nothing of the climb left on the carrier" % label)
	var report := AddaReport.build(recorder, {"scenario": "loaded_ladder", "character": String(carrier), "passenger": String(passenger), "command": WorkbenchSession.repro_command(&"loaded_ladder"), "cli": "", "detail": "summary"})
	check(String(report.config.passenger) == String(passenger), "%s: the report names the passenger" % label)
	check(String(report.config.command).contains("--passenger=%s" % passenger) and String(report.config.command).contains("--character=%s" % carrier), "%s: and its command reproduces the pairing" % label)
	check(int(report.config.rows) > 600, "%s: the recorder listened throughout (%d rows)" % [label, int(report.config.rows)])
	bench.queue_free()
	await _frames(2)
