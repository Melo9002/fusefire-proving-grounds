class_name ScenarioTab
extends VBoxContainer
## "What am I asking this character to do?" Scenario presets (WorkbenchScenarios) with play, pause, single-frame step, reset and repeat, then the manual controls the workbench has always had, grouped into folding sections.
## Unsupported combinations are shown disabled with the reason. Pause stops the scenario clock and the character together; stepping advances both by one frame at 1/60 s.

var bench: Node3D
var _picked := 0
var _choice: OptionButton
var _summary: Label
var _context: Label
var _support: Label
var _progress: ProgressBar
var _now: Label
var _log: Label
var _play: Button
var _pause: Button
var _moments: VBoxContainer
var _scenarios: Array[Dictionary] = []

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 5)
	var presets := WorkbenchUI.section(self, "Scenario presets")
	_scenarios = WorkbenchScenarios.all()
	_choice = OptionButton.new()
	for scenario in _scenarios:
		_choice.add_item(scenario.title)
	_choice.item_selected.connect(func(index: int) -> void:
		_picked = index
		_describe())
	presets.add_child(_choice)
	_summary = WorkbenchUI.label("", 12)
	presets.add_child(_summary)
	_context = WorkbenchUI.label("", 12, WorkbenchUI.WARN)
	presets.add_child(_context)
	_support = WorkbenchUI.label("", 12)
	presets.add_child(_support)
	_play = WorkbenchUI.button("Play / repeat", _play_picked, "Resets the workbench and runs the scenario from its start")
	_pause = WorkbenchUI.button("Pause", _toggle_pause, "Pauses the scenario and the character together")
	var controls := HBoxContainer.new()
	for node: Button in [_play, _pause, WorkbenchUI.button("Step frame", func() -> void: bench.step_sim(), "While paused: one frame at 1/60 s"), WorkbenchUI.button("Reset", _reset, "Stops the scenario and returns everything to neutral")]:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(node)
	presets.add_child(controls)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 14)
	_progress.tooltip_text = "Click to jump to that moment (it pauses there)"
	_progress.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_progress.gui_input.connect(_on_bar_input)
	presets.add_child(_progress)
	_now = WorkbenchUI.label("", 12, WorkbenchUI.ACCENT)
	presets.add_child(_now)
	presets.add_child(WorkbenchUI.label("Jump to a moment (it pauses there):", 13, WorkbenchUI.DIM))
	_moments = VBoxContainer.new()
	_moments.add_theme_constant_override("separation", 1)
	presets.add_child(_moments)
	presets.add_child(WorkbenchUI.row([["Back 1 s", func() -> void: _jump_by(-1.0), "Goes one second back and pauses (replays from the start, so it takes a moment)"], ["Forward 1 s", func() -> void: _jump_by(1.0), "Plays one more second and pauses"]]))
	_log = WorkbenchUI.mono("", 11)
	_log.visible = false   # the steps already run: kept for code that reads it; the clickable moments above say the same
	presets.add_child(_log)
	_describe()
	var manual := WorkbenchUI.section(self, "Manual controls (locomotion, cover, ladder, stairs, path, camera)", true)
	var legacy := LocomotionTestPanel.new()
	manual.add_child(legacy)
	legacy.setup(bench)
	var keys := WorkbenchUI.section(self, "Keyboard shortcuts", true)
	keys.add_child(WorkbenchUI.label(KEYS, 12, WorkbenchUI.DIM))

const KEYS := "1 idle  2 move  3 aim  4 shoot  5 hit  6 defeat   Space: sequence\nArrows: direction   T: turn preview   [ / ]: pace   I: IK   C: camera preset   RMB drag: orbit\n7/8: low/high cover   9/0: expose left/right   V B N L: vault, climb, descend, land   F: gesture\nR: pickup  P: carry idle  M: carry move  E: boarding  Q: release  K: carrier-death drop  O: pause rescue timeline  , / .: scrub 0.1 s  Y: passenger motion\nH: weapon-grip contact diagnostics  J: labels  G: mark contact  Z: pose preset  X: diagnostic view\nF1: hide or show this panel   Esc: close"

func _describe() -> void:
	var scenario := _scenarios[_picked]
	var support := WorkbenchScenarios.supported(scenario, bench.rig)
	_summary.text = scenario.summary
	_context.text = scenario.context
	_support.text = "Available on this configuration." if support.ok else "UNAVAILABLE: %s." % support.reason
	_support.add_theme_color_override("font_color", WorkbenchUI.GOOD if support.ok else WorkbenchUI.BAD)
	_play.disabled = not support.ok
	for child in _moments.get_children():
		child.queue_free()
	for step: Dictionary in scenario.steps:
		var button := WorkbenchUI.button("%.1f s   %s" % [float(step.t), step.label], jump_to.bind(scenario.id, float(step.t) + MOMENT_AFTER), "Plays the scenario to just after this step and pauses")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.disabled = not support.ok
		_moments.add_child(button)

## A step's moment is shown a little after the step starts, so its effect is visible.
const MOMENT_AFTER := 0.3

## Replays `id` to scenario time `seconds` and pauses there (the Why? tab's "Go there" does the same for a finding).
func jump_to(id: StringName, seconds: float) -> void:
	if bench.replay_to(id, maxf(seconds, 0.0)):
		_pause.text = "Resume"

func _jump_by(seconds: float) -> void:
	var runner: WorkbenchScenarioRunner = bench.scenario_runner
	if runner.scenario.is_empty():
		return
	if seconds > 0.0 and runner.running:
		if not bench.sim_paused:
			bench.set_sim_paused(true)
		bench.step_sim(int(round(seconds / maxf(bench.step_seconds, 0.0001))))
		_pause.text = "Resume"
	else:
		jump_to(runner.scenario.id, runner.time + seconds)

func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var scenario: Dictionary = _scenarios[_picked] if bench.scenario_runner.scenario.is_empty() else bench.scenario_runner.scenario
		var fraction := clampf(event.position.x / maxf(_progress.size.x, 1.0), 0.0, 1.0)
		jump_to(scenario.id, fraction * float(scenario.get("duration", 0.0)))

func _play_picked() -> void:
	bench.start_scenario(_scenarios[_picked].id)
	_pause.text = "Pause"

func _toggle_pause() -> void:
	bench.set_sim_paused(not bench.sim_paused)
	_pause.text = "Resume" if bench.sim_paused else "Pause"
	bench._update_status()

func _reset() -> void:
	bench.scenario_runner.stop()
	bench.set_sim_paused(false)
	bench.reset_scene()
	_pause.text = "Pause"

func refresh() -> void:
	var runner: WorkbenchScenarioRunner = bench.scenario_runner
	_progress.value = runner.progress() if runner.running else 0.0
	_now.text = bench.playback_text() + (("   (" + runner.current_label() + ")") if runner.running else "")
	_pause.text = "Resume" if bench.sim_paused and bench.pending_steps() == 0 else "Pause"
	var lines: Array[String] = []
	for index in range(maxi(0, runner.log.size() - 8), runner.log.size()):
		lines.append(runner.log[index])
	_log.text = "\n".join(lines)
