extends SceneTree
## Task 12: the animation workbench as a developer tool. It loads WITHOUT a tactical mission, for both humanoids, armed and unarmed (character and weapon state come from WorkbenchSession, as a relaunch would set
## them); its panel has the four workflow tabs and fits ordinary window sizes; the three scenario presets drive the REAL presenter and rig; pause, single-frame step, reset, repeat and interruption leave nothing behind;
## and unsupported combinations are named instead of skipped. Scenarios are stepped deterministically (paused, fixed step) so the test does not depend on frame timing.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _say(text: String) -> void:
	print("[%6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, text])

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _bench(character: StringName, armed: bool) -> Node3D:
	WorkbenchSession.character = character
	WorkbenchSession.armed = armed
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(12)
	bench.step_seconds = 0.05
	return bench

## Plays a scenario to its end in fixed paused steps (or `until` seconds of it). Returns the frames it took.
func _play(bench: Node3D, id: StringName, until := INF) -> int:
	check(bench.start_scenario(id), "scenario %s starts" % id)
	bench.set_sim_paused(true)
	var frames := 0
	while bench.scenario_runner.running and bench.scenario_runner.time < until and frames < 2000:
		bench.step_sim()
		await process_frame
		frames += 1
	return frames

func _is_neutral(bench: Node3D, label: String) -> void:
	var rig: CharacterRig = bench.rig
	var presenter := rig.presenter
	check(bench.cover_demo.is_empty() and bench.ladder_demo.is_empty() and bench.stair_demo.is_empty() and bench.path_demo.is_empty(), "%s: every bench is ended" % label)
	check(rig.ladder == null and rig.stairs == null and not rig.interaction_active() and not is_instance_valid(rig.carry_passenger), "%s: no traversal, interaction or carry remains" % label)
	check(not presenter.is_holding() and presenter.postures.resolved() == PresentationTypes.Posture.STAND and not presenter.attack.is_active(), "%s: no hold, no attack, standing" % label)
	check(bench.preview_speed == 0.0 and is_nan(bench.turn_goal) and rig.animation_controller.current_state == &"rifle_idle", "%s: the walk is stopped and the idle clip plays" % label)
	var grip := rig.grip_modifier
	if rig.has_weapon():
		check(grip.contact_weight == [0.0, 0.0], "%s: the weapon's grip owns the hands again" % label)

func _run() -> void:
	_say("start")
	# --- 1. Both humanoids load without a tactical mission, armed and unarmed.
	var profiles := {}
	for character in [&"mira_0", &"small_mira_0"]:
		for armed in [true, false]:
			var bench := await _bench(character, armed)
			var label := "%s %s" % [character, "armed" if armed else "unarmed"]
			check(is_instance_valid(bench.rig) and bench.rig.skeleton != null and bench.diagnostics != null and is_instance_valid(bench.diagnostics.monitor), "%s: the workbench builds its rig and its monitor with no mission" % label)
			check(bench.rig.has_weapon() == armed, "%s: the weapon state follows the session" % label)
			var info := RigInspection.report(bench.rig)
			profiles[character] = info.identity.profile
			check(info.usable and bench.panel != null and bench.panel.tabs.get_tab_count() == 4, "%s: the report is usable and the panel has four tabs" % label)
			bench.queue_free()
			await _frames(2)
	check(profiles[&"mira_0"] != profiles[&"small_mira_0"], "switching the character changes the rig profile (%s / %s)" % [profiles[&"mira_0"], profiles[&"small_mira_0"]])

	_say("section 1 done")
	# --- 2. The panel: the four tabs, in order, and it fits ordinary and small windows.
	var bench := await _bench(&"mira_0", true)
	var names: Array[String] = []
	for index in bench.panel.tabs.get_tab_count():
		names.append(bench.panel.tabs.get_tab_title(index))
	check(names == ["Character", "Scenario", "Diagnostics", "Evidence"], "the tabs are Character, Scenario, Diagnostics, Evidence (%s)" % [names])
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(960, 600)]:
		root.size = size
		await _frames(3)
		# The project stretches its canvas (canvas_items, expand): the panel is laid out in canvas units, so it is judged against the canvas the window shows.
		var canvas := bench.get_viewport().get_visible_rect().size
		var panel: WorkbenchPanel = bench.panel
		check(panel.size.x <= WorkbenchPanel.MAX_WIDTH + 1.0 and panel.size.x >= WorkbenchPanel.MIN_WIDTH - 1.0 and panel.position.x + panel.size.x <= canvas.x and panel.position.y >= 0.0 and panel.position.y + panel.size.y <= canvas.y + 0.5,
			"the panel fits a %dx%d window (canvas %.0fx%.0f: x %.0f w %.0f y %.0f h %.0f)" % [size.x, size.y, canvas.x, canvas.y, panel.position.x, panel.size.x, panel.position.y, panel.size.y])
		_panel_readability(panel, "%dx%d" % [size.x, size.y])
		check(panel.size.x <= canvas.x * 0.5 and bench.camera.h_offset > 0.0, "%dx%d: the panel leaves at least half the canvas and the 3D view is shifted clear of it (h_offset %.2f)" % [size.x, size.y, bench.camera.h_offset])
	root.size = Vector2i(1152, 648)
	await _frames(2)
	bench.panel._unhandled_key_input(_key(KEY_F1))
	check(not bench.panel.visible and bench.panel.occupied_width() == 0.0, "F1 hides the panel and the view is no longer shifted for it")
	bench.panel._unhandled_key_input(_key(KEY_F1))
	check(bench.panel.visible, "F1 shows it again")
	await _trail_clock_checks(bench)
	# Evidence: the report is complete and serialises; the repro command names character, weapon state and scenario.
	var evidence: EvidenceTab = bench.panel.tab_nodes[3]
	var report := evidence.report()
	check(report.has("rig") and report.has("declared") and report.has("runtime") and JSON.stringify(report).length() > 500, "the evidence report has the rig, declared ownership and runtime sections and serialises")
	check(report.declared.order_problems.is_empty() and report.runtime.stages.size() == 8, "the report's stage section agrees with the declared order")
	WorkbenchSession.character = &"small_mira_0"
	WorkbenchSession.armed = false
	check(WorkbenchSession.repro_command(&"contacts") == "godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=small_mira_0 --unarmed --scenario=contacts", "the repro command relaunches character, weapon state and scenario (%s)" % WorkbenchSession.repro_command(&"contacts"))
	# Overlays: switching a diagnostic on and off through the panel's own control leaves nothing behind.
	bench.diagnostics.set_contacts(true)
	await _frames(3)
	check(bench.diagnostics.contacts_on() and not bench.diagnostics.contacts.latest.is_empty(), "contact diagnostics switch on from the workbench")
	bench.diagnostics.set_contacts(false)
	await _frames(2)
	check(bench.diagnostics.contacts.is_clean(), "and off: no overlay, no listener")
	bench.queue_free()
	await _frames(3)

	_say("section 2 done")
	# --- 3. The three scenarios on the real stack. MIRA armed runs all three.
	bench = await _bench(&"mira_0", true)
	var states: Array[StringName] = []
	bench.rig.animation_controller.state_changed.connect(func(state: StringName) -> void: states.append(state))
	# A: tactical-style.
	await _play(bench, WorkbenchScenarios.TACTICAL)
	var tactical := WorkbenchScenarios.tactical()
	check(bench.scenario_runner.log.size() == tactical.steps.size(), "A: every step ran, in order (%d/%d)" % [bench.scenario_runner.log.size(), tactical.steps.size()])
	var history: String = bench.diagnostics.monitor.history_text(60)
	check(&"move" in states and &"aim" in states and (&"shoot" in states or &"shoot_left" in states or &"shoot_right" in states) and (history.contains("posture STAND -> CROUCH") or history.contains("posture STAND -> KNEEL")) and history.contains("-> STAND"), "A: the character really moved, took cover (lowered its posture), aimed, fired and stood again (states %s)" % [states.slice(0, 12)])
	_is_neutral(bench, "A after finishing")
	check(WorkbenchScenarios.tactical().context.contains("SYNTHETIC"), "A: the synthetic tactical context is labelled")
	_say("A done")
	# B: exploration-style, with the outcomes in the history.
	states.clear()
	bench.diagnostics.monitor.clear_history()
	await _play(bench, WorkbenchScenarios.EXPLORATION)
	history = bench.diagnostics.monitor.history_text(60)
	check(bench.scenario_runner.log.size() == WorkbenchScenarios.exploration().steps.size() and &"acknowledge" in states and &"nod" in states and &"hit" in states, "B: gestures, inspection and the reaction really ran (states %s)" % [states.slice(0, 14)])
	check(history.contains("gesture acknowledge: COMPLETED") and history.contains("inspect: COMPLETED") and history.contains("reaction: COMPLETED"), "B: the outcomes of the gesture, inspection and reaction are in the history")
	check(history.contains("gesture acknowledge: INTERRUPTED") and history.contains("hold replaced (gesture -> reaction)"), "B: the gesture the reaction cut short settles INTERRUPTED and the hold replacement is logged")
	_is_neutral(bench, "B after finishing")
	_say("B done")
	# C: contacts.
	bench.diagnostics.monitor.clear_history()
	var foot_worst := 0.0
	var feet_seen := 0
	var hands_claimed := false
	check(bench.start_scenario(WorkbenchScenarios.CONTACTS), "C starts")
	bench.set_sim_paused(true)
	var frames := 0
	while bench.scenario_runner.running and frames < 2000:
		bench.step_sim()
		await process_frame
		frames += 1
		var contacts: ContactErrorDiagnostics = bench.diagnostics.contacts
		if is_instance_valid(contacts) and not contacts.latest.is_empty():
			for foot: Dictionary in contacts.latest.feet:
				if foot.source == "stair planner" and float(foot.weight) > 0.99:
					feet_seen += 1
					foot_worst = maxf(foot_worst, float(foot.error))
			hands_claimed = hands_claimed or float(contacts.latest.hands[1].weight) > 0.9
	history = bench.diagnostics.monitor.history_text(60)
	check(is_instance_valid(bench.diagnostics.contacts) and bench.diagnostics.contacts_on(), "C: the scenario switched the contact diagnostics on")
	check(feet_seen > 20 and foot_worst < 0.03, "C: on the stair the planned foothold and the final ankle agree (%d samples, worst %.1f mm)" % [feet_seen, foot_worst * 1000.0])
	check(hands_claimed and history.contains("stairs began") and history.contains("stairs ended") and history.contains("ladder began") and history.contains("ladder ended"), "C: the stair and the ladder began and ended, and the hands held contacts on the ladder")
	_is_neutral(bench, "C after finishing")
	await _frames(3)
	check(bench.rig.grip_modifier.contact_weight == [0.0, 0.0], "C: the interrupted ladder left no contact weight on the grip")

	_say("C done")
	# --- 4. Pause, step, reset, repeat, interruption.
	check(bench.start_scenario(WorkbenchScenarios.EXPLORATION), "B starts for the pause test")
	bench.set_sim_paused(true)
	bench.step_sim(10)
	await _frames(12)
	var paused_time: float = bench.rig.presenter.time
	var runner_time: float = bench.scenario_runner.time
	var yaw_before: float = bench.rig.character_root.rotation.y
	await _frames(20)
	check(bench.rig.presenter.time == paused_time and bench.scenario_runner.time == runner_time and bench.rig.character_root.rotation.y == yaw_before, "paused: the presenter's clock, the scenario clock and the body do not move")
	bench.step_sim()
	await _frames(3)
	check(is_equal_approx(bench.rig.presenter.time - paused_time, bench.step_seconds) and is_equal_approx(bench.scenario_runner.time - runner_time, bench.step_seconds), "one step advances both clocks by exactly the step (%.3f s)" % (bench.rig.presenter.time - paused_time))
	bench.set_sim_paused(false)
	check(bench.rig.animation_controller.animation_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE, "resuming gives the animation tree its normal mode back")
	# Interrupt in the middle of the crouch, mid-gesture and mid-ladder: stopping always lands on the neutral state.
	for entry in [[WorkbenchScenarios.EXPLORATION, 5.5], [WorkbenchScenarios.EXPLORATION, 8.0], [WorkbenchScenarios.CONTACTS, 8.5], [WorkbenchScenarios.TACTICAL, 7.0]]:
		await _play(bench, entry[0], entry[1])
		check(bench.scenario_runner.running, "%s is running at %.1f s" % [entry[0], entry[1]])
		bench.scenario_runner.stop()
		await _frames(3)
		_is_neutral(bench, "%s stopped at %.1f s" % [entry[0], entry[1]])
	# Replacing a scenario with another resets first; repeating a scenario gives the same log.
	await _play(bench, WorkbenchScenarios.CONTACTS, 8.5)
	check(bench.ladder_demo.is_empty() == false, "C is on the ladder at 8.5 s")
	await _play(bench, WorkbenchScenarios.EXPLORATION, 1.0)
	check(bench.ladder_demo.is_empty() and bench.rig.ladder == null, "starting B while C was on the ladder ended the ladder first")
	bench.scenario_runner.stop()
	await _play(bench, WorkbenchScenarios.EXPLORATION)
	var first: Array = bench.scenario_runner.log.map(func(line: String) -> String: return line.substr(line.find("  ")))
	await _play(bench, WorkbenchScenarios.EXPLORATION)
	var second: Array = bench.scenario_runner.log.map(func(line: String) -> String: return line.substr(line.find("  ")))
	check(first == second and first.size() == WorkbenchScenarios.exploration().steps.size(), "repeating a scenario runs the same steps (%d)" % first.size())
	# Reset while paused works, and a reset leaves the diagnostics (a read-only observer) in place.
	await _play(bench, WorkbenchScenarios.CONTACTS, 8.0)
	bench.set_sim_paused(true)
	bench.reset_scene()
	bench.set_sim_paused(false)
	await _frames(4)
	_is_neutral(bench, "reset while paused")
	check(is_instance_valid(bench.diagnostics.monitor) and bench.diagnostics.monitor.is_listening(), "a reset leaves the observer attached")
	# Unsupported combinations are named: a weapon scenario needs a weapon.
	bench.queue_free()
	await _frames(3)

	# --- 5. Small MIRA unarmed: the exploration and contact scenarios run; the tactical one is reported unavailable and does not start.
	bench = await _bench(&"small_mira_0", false)
	var support := WorkbenchScenarios.supported(WorkbenchScenarios.tactical(), bench.rig)
	check(not support.ok and support.reason.contains("unarmed") and not bench.start_scenario(WorkbenchScenarios.TACTICAL) and not bench.scenario_runner.running, "an unarmed character cannot start the weapon scenario and is told why (%s)" % support.reason)
	var scenario_tab: ScenarioTab = bench.panel.tab_nodes[1]
	scenario_tab._choice.select(0)
	scenario_tab._choice.item_selected.emit(0)
	check(scenario_tab._play.disabled and scenario_tab._support.text.contains("UNAVAILABLE"), "the Scenario tab disables the unavailable preset and says why")
	scenario_tab._choice.select(1)
	scenario_tab._choice.item_selected.emit(1)
	check(not scenario_tab._play.disabled, "and enables the ones that fit")
	await _play(bench, WorkbenchScenarios.EXPLORATION)
	_is_neutral(bench, "small unarmed B")
	var unreachable := 0
	var seen := 0
	check(bench.start_scenario(WorkbenchScenarios.CONTACTS), "C starts on Small MIRA unarmed")
	bench.set_sim_paused(true)
	frames = 0
	while bench.scenario_runner.running and frames < 2000:
		bench.step_sim()
		await process_frame
		frames += 1
		var contacts: ContactErrorDiagnostics = bench.diagnostics.contacts
		if is_instance_valid(contacts) and not contacts.latest.is_empty():
			for hand: Dictionary in contacts.latest.hands:
				if float(hand.weight) > 0.9:
					seen += 1
					unreachable += 1 if hand.unreachable else 0
	check(seen > 20 and unreachable > 0, "C on Small MIRA shows its ladder contacts and flags the unreachable ones (%d of %d samples, issue 55)" % [unreachable, seen])
	_is_neutral(bench, "small unarmed C")
	bench.queue_free()
	await _frames(3)
	WorkbenchSession.character = &""
	WorkbenchSession.armed = true
	print("workbench_scenarios_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The panel's real controls, not a sample label: every text control in every tab is at least 14 pt, and no tab's content is wider than the panel can show (a wide table would be clipped at the window edge).
func _panel_readability(panel: WorkbenchPanel, label: String) -> void:
	var smallest := 99
	var widest_excess := 0.0
	for index in panel.tabs.get_tab_count():
		var scroll := panel.tabs.get_child(index) as ScrollContainer
		var content := scroll.get_child(0) as Control
		widest_excess = maxf(widest_excess, content.get_combined_minimum_size().x - scroll.size.x)
		for node in content.find_children("*", "Control", true, false):
			if node is RichTextLabel:
				smallest = mini(smallest, (node as RichTextLabel).get_theme_font_size("normal_font_size"))
			elif node is Label or node is CheckBox:
				smallest = mini(smallest, node.get_theme_font_size("font_size"))
	check(smallest >= 14, "%s: every text control in the panel is at least 14 pt (smallest %d)" % [label, smallest])
	check(widest_excess <= 1.0, "%s: no tab's content is wider than the panel shows (excess %.0f px)" % [label, widest_excess])

## The root trail and the workbench pause: a paused workbench records nothing by itself, one step records exactly one sample timed by the step, resuming restores automatic sampling, and the trail survives toggling,
## a reset and teardown coherently. The workbench root walks in place, so every speed is zero: a spike would be a bug.
func _trail_clock_checks(bench: Node3D) -> void:
	var suite: WorkbenchDiagnostics = bench.diagnostics
	suite.set_trail(true)
	await _frames(3)
	var trail: MotionTrail = suite.trail
	check(trail.points.size() >= 2 and not trail.sampling_paused, "unpaused, the trail samples rendered frames")
	bench.set_sim_paused(true)
	await _frames(2)
	var count := trail.points.size()
	var elapsed: float = float(trail.points.back().t)
	await _frames(6)
	check(trail.points.size() == count and trail.points.back().t == elapsed, "paused: no sample and no elapsed time accumulate over rendered frames")
	suite.record_step(0.5)
	check(trail.points.size() == count + 1 and is_equal_approx(float(trail.points.back().t), elapsed + 0.5), "(control) a diagnostics-level record_step records exactly what it is handed")
	count = trail.points.size()
	elapsed = float(trail.points.back().t)
	for step in 5:
		bench.step_sim()
		await _frames(2)
	check(trail.points.size() == count + 5 and absf(float(trail.points.back().t) - elapsed - 5.0 * bench.step_seconds) < 0.0001, "five steps record exactly five samples, together exactly five step lengths (%d samples)" % (trail.points.size() - count))
	var worst := 0.0
	for point in trail.points:
		worst = maxf(worst, float(point.speed))
	check(worst < 0.01, "no speed spike in the trail (worst %.3f m/s)" % worst)
	bench.set_sim_paused(false)
	await _frames(2)
	count = trail.points.size()
	trail.record_step(1.0)
	check(trail.points.size() == count and not trail.sampling_paused, "resumed: automatic sampling is back and a stray record_step adds nothing")
	await _frames(3)
	check(trail.points.size() > count, "resumed: rendered frames add samples again")
	suite.set_trail(false)
	bench.set_sim_paused(true)
	suite.set_trail(true)
	count = trail.points.size()
	await _frames(4)
	check(trail.sampling_paused and trail.points.size() == count, "a trail switched on while paused does not sample by itself")
	bench.step_sim()
	await _frames(2)
	check(trail.points.size() == count + 1, "and records one sample for one step")
	bench.reset_scene()
	check(trail.points.is_empty(), "a reset empties the trail")
	bench.set_sim_paused(false)
	suite.set_trail(false)
	bench.set_sim_paused(true)
	suite.set_trail(true)
	suite.shutdown()
	await _frames(3)
	check(suite.is_clean(), "shutting the diagnostics down while paused leaves no trail")
	bench.diagnostics = WorkbenchDiagnostics.new(bench.rig)   # the bench frees its own on exit: give it a fresh one
	bench.diagnostics.ensure_monitor()
	bench.set_sim_paused(false)

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
