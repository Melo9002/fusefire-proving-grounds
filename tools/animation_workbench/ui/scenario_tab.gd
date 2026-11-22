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
	_progress.custom_minimum_size = Vector2(0, 10)
	presets.add_child(_progress)
	_now = WorkbenchUI.label("", 12, WorkbenchUI.ACCENT)
	presets.add_child(_now)
	_log = WorkbenchUI.mono("", 11)
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
	_now.text = "%s  %.1f / %.1f s%s" % [runner.current_label(), runner.time, float(runner.scenario.get("duration", 0.0)), "   PAUSED" if bench.sim_paused else ""] if runner.running else ("PAUSED" if bench.sim_paused else "no scenario running")
	var lines: Array[String] = []
	for index in range(maxi(0, runner.log.size() - 8), runner.log.size()):
		lines.append(runner.log[index])
	_log.text = "\n".join(lines)
