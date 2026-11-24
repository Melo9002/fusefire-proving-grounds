class_name StartTab
extends VBoxContainer
## The first screen: three steps in plain words (watch, find problems, change how she moves), each one button, so nobody has to read a guide to begin. It only calls what the other tabs already do.

var bench: Node3D
var _now: Label
var _scenarios: Array[Dictionary] = []

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 8)
	add_child(WorkbenchUI.label("Watch MIRA move, find what looks wrong, change it.", 16, WorkbenchUI.ACCENT))

	add_child(WorkbenchUI.label("1. Watch her do something", 15))
	_scenarios = WorkbenchScenarios.all()
	for scenario in _scenarios:
		var support := WorkbenchScenarios.supported(scenario, bench.rig)
		var button := WorkbenchUI.button(String(scenario.get("short", scenario.title)), _play.bind(scenario.id), String(scenario.summary))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not support.ok
		if not support.ok:
			button.tooltip_text = "Not available: %s" % support.reason
		add_child(button)
	_now = WorkbenchUI.label("Nothing playing. Pick one above.", 13, WorkbenchUI.DIM)
	add_child(_now)
	add_child(WorkbenchUI.label("Space pauses. Right-drag turns the camera, the wheel zooms. F1 hides this panel.", 13, WorkbenchUI.DIM))

	add_child(WorkbenchUI.label("2. Find what looks wrong", 15))
	add_child(WorkbenchUI.button("What went wrong in that run?", _find_problems, "Lists the moments where the pose jumped or a hand or foot missed its target, worst first"))
	add_child(WorkbenchUI.label("Pick a problem in the list, then press 'Go there' to see it paused.", 13, WorkbenchUI.DIM))

	add_child(WorkbenchUI.label("3. Change how she moves", 15))
	add_child(WorkbenchUI.button("Open the settings and clips (crouch, walk, ladder, stairs, weapon)", func() -> void: _open(&"Tune"), "Sliders that change the animation live; Save keeps them. A clip can be edited by hand in the Godot editor from there"))
	add_child(WorkbenchUI.label("Each one has 'Edit in Godot': it opens the Godot editor on that setting or clip, and what you save there shows up here.", 13, WorkbenchUI.DIM))

	var words := WorkbenchUI.section(self, "Words you will see", true)
	words.add_child(WorkbenchUI.label(GLOSSARY, 13, WorkbenchUI.DIM))

const GLOSSARY := "Target: where the animation wants a hand or foot to be.\nSnap / jump: a body part moved much faster than in the frames around it (a pop).\nPlanted: the animation says the foot should stay still on its step.\nStage: one step of the pose pipeline (crouch, ladder, weapon...) that bends the body after the animation clip.\nIK: the part that bends an arm or leg so the hand or foot reaches its target.\nKnee pole: the point the knee is pointed towards.\nCause unknown: ADDA measured something odd but has not proven why."

func _play(id: StringName) -> void:
	bench.start_scenario(id)

func _find_problems() -> void:
	var why: WhyTab = bench.panel.tab_named(&"Why?")
	_open(&"Why?")
	if why != null:
		why._analyze()

func _open(tab: StringName) -> void:
	bench.panel.show_tab(tab)

func refresh() -> void:
	var runner: WorkbenchScenarioRunner = bench.scenario_runner
	if bench.pending_steps() > 0:
		_now.text = "Going to the moment... (%d frames left)" % bench.pending_steps()
	elif runner.running:
		_now.text = "%s: %s  (%.1f of %.0f s)%s" % [String(runner.scenario.get("short", runner.scenario.title)), runner.current_label(), runner.time, float(runner.scenario.get("duration", 0.0)), "  PAUSED" if bench.sim_paused else ""]
	else:
		_now.text = "Nothing playing. Pick one above." if runner.scenario.is_empty() else "Finished. Press step 2 to see what went wrong, or play it again."
