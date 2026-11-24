class_name StartTab
extends VBoxContainer
## The first screen: watch, report what looks wrong, find what ADDA measured, change how she moves; each one button, so nobody has to read a guide to begin. "Report this moment" (MomentReport) is the
## hand-over to a coding agent. It only calls what the other tabs and tools already do.

var bench: Node3D
var _now: Label
var _scenarios: Array[Dictionary] = []
var _note: LineEdit
var _report_status: Label

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

	add_child(WorkbenchUI.label("2. Something looks wrong? Report it", 15))
	_note = LineEdit.new()
	_note.placeholder_text = "What looks wrong? (e.g. her feet slide on the first stair)"
	_note.text_submitted.connect(func(_t: String) -> void: report())
	add_child(_note)
	add_child(WorkbenchUI.button("Report this moment", report, "Pauses, then saves your note, a screenshot, the exact moment, the settings and what ADDA measured, in a folder a coding agent can use (F2 from anywhere)"))
	_report_status = WorkbenchUI.label("It pauses and saves everything an agent needs to see the same moment. F2 jumps here.", 13, WorkbenchUI.DIM)
	add_child(_report_status)

	add_child(WorkbenchUI.label("3. See what ADDA measured", 15))
	add_child(WorkbenchUI.button("What went wrong in that run?", _find_problems, "Lists the moments where the pose jumped or a hand or foot missed its target, worst first"))
	add_child(WorkbenchUI.label("Pick a problem in the list, then press 'Go there' to see it paused.", 13, WorkbenchUI.DIM))

	add_child(WorkbenchUI.label("4. Change how she moves", 15))
	add_child(WorkbenchUI.button("Open the settings and clips (crouch, walk, ladder, stairs, weapon)", func() -> void: _open(&"Tune"), "Try values live; nothing changes the game until you press Apply to game. A clip can be edited by hand in the Godot editor from there"))
	add_child(WorkbenchUI.label("Changes there are experiments: the game only changes when you press 'Apply to game'. 'Edit in Godot' opens the same thing in the Godot editor.", 13, WorkbenchUI.DIM))

	var words := WorkbenchUI.section(self, "Words you will see", true)
	words.add_child(WorkbenchUI.label(GLOSSARY, 13, WorkbenchUI.DIM))

const GLOSSARY := "Target: where the animation wants a hand or foot to be.\nSnap / jump: a body part moved much faster than in the frames around it (a pop).\nPlanted: the animation says the foot should stay still on its step.\nStage: one step of the pose pipeline (crouch, ladder, weapon...) that bends the body after the animation clip.\nIK: the part that bends an arm or leg so the hand or foot reaches its target.\nKnee pole: the point the knee is pointed towards.\nCause unknown: ADDA measured something odd but has not proven why."

## Pauses where it is and saves a report of this moment with the note typed above. Returns {ok, path, message} (await it: it lets the screen redraw first).
func report() -> Dictionary:
	if bench.scenario_runner.running and not bench.sim_paused:
		bench.set_sim_paused(true)
	# The screenshot must show what is true now: refresh the status line and this tab, then let one frame draw before it is taken.
	bench._update_status()
	refresh()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var result := MomentReport.save(bench, _note.text)
	if result.ok:
		DisplayServer.clipboard_set("Investigate the animation report in %s (read its README.md first)." % String(result.path).trim_prefix("res://"))
		_report_status.text = "%s A message for your agent is on the clipboard." % result.message
		_report_status.add_theme_color_override("font_color", WorkbenchUI.GOOD)
		_note.text = ""
	else:
		_report_status.text = result.message
		_report_status.add_theme_color_override("font_color", WorkbenchUI.BAD)
	return result

## F2: pause and put the cursor in the note box.
func begin_report() -> void:
	if bench.scenario_runner.running and not bench.sim_paused:
		bench.set_sim_paused(true)
	_note.grab_focus()

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
