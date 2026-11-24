class_name WhyTab
extends VBoxContainer
## "Why is my robot doing that?" The one tab that answers it in words. It reads ADDA's recording of what the skeleton actually did (SessionRecorder), finds what stands out (TimelineAnalysis), and lists FINDINGS in plain
## sentences: what was MEASURED, what MIGHT explain it (always marked unconfirmed, with what it rests on and how to test it), and that the cause is UNKNOWN unless it was measured. Pick one to see it on the body, replay the
## scenario to that moment, or open the technical detail. Everything here is read-only: the recorder reads inside skeleton_updated and writes nothing to the rig.
## The same report is what `tools/adda.ps1 run` writes for an agent (docs/claude/adda/07-usage.md).

const FOLDER := "user://adda"

var bench: Node3D
var _report := {}
var _selected := {}
var _headline: Label
var _status: Label
var _list: VBoxContainer
var _more: Button
var _show_all := false
var _observed: Label
var _causes: Label
var _detail: Label
var _actions: HBoxContainer
var _marker: FindingMarker
var _mesh_check: CheckBox
var _part_choice: OptionButton
var _part_text: Label
var _isolation_text: Label
var _compare_text: Label
var _export_text: Label
var _parts: Array[String] = []

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 5)
	var start := WorkbenchUI.section(self, "Record, then ask")
	start.add_child(WorkbenchUI.label("Play a scenario (Start or Scenario tab) and it is recorded. Then 'What happened?' lists what stood out. Recording only reads the pose; it changes nothing.", 12, WorkbenchUI.DIM))
	start.add_child(WorkbenchUI.row([["Record (free play)", _toggle_recording, "Records whatever the character does until you stop"], ["What happened?", _analyze, "Analyse the recording so far"]]))
	_mesh_check = WorkbenchUI.check("Also sample leg vertices against the ladder (slow, about 3.5 ms a frame)", false, func(_on: bool) -> void: pass, "Needed to say whether legs cross rungs; off means ADDA says it did not look")
	start.add_child(_mesh_check)
	_status = WorkbenchUI.label("not recording", 12, WorkbenchUI.ACCENT)
	start.add_child(_status)
	var findings := WorkbenchUI.section(self, "What stood out")
	_headline = WorkbenchUI.label("Nothing analysed yet.", 13)
	findings.add_child(_headline)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	findings.add_child(_list)
	_more = WorkbenchUI.button("Show all findings", func() -> void:
		_show_all = not _show_all
		_rebuild_list())
	findings.add_child(_more)
	var chosen := WorkbenchUI.section(self, "The selected finding")
	_observed = WorkbenchUI.label("Select a finding above.", 13)
	chosen.add_child(_observed)
	_causes = WorkbenchUI.label("", 12, WorkbenchUI.WARN)
	chosen.add_child(_causes)
	_actions = WorkbenchUI.row([["Go there", go_there, "Plays the scenario again, pauses at the worst moment of this finding and marks it on the body"], ["Mark it again", _show_it, "Marks it on the body in the current pose and moves the camera to it"], ["Copy reproduction", _copy_repro]])
	chosen.add_child(_actions)
	var technical := WorkbenchUI.section(self, "Technical detail of the selected finding", true)
	_detail = WorkbenchUI.mono("", 11)
	technical.add_child(_detail)
	var inspect := WorkbenchUI.section(self, "Inspect a body part", true)
	_parts = BodyParts.parts(bench.rig)
	_part_choice = OptionButton.new()
	_part_choice.add_item("(choose a part)")
	for part in _parts:
		_part_choice.add_item(part)
	_part_choice.item_selected.connect(_on_part)
	inspect.add_child(_part_choice)
	_part_text = WorkbenchUI.mono("", 11)
	inspect.add_child(_part_text)
	inspect.add_child(WorkbenchUI.row([["Which pose stage moves it? (experiment)", _isolate, "Pauses the pose, switches each pose modifier off in turn and reports which ones move this part, including modifiers nobody declared. Changes state for a few frames and restores it."]]))
	_isolation_text = WorkbenchUI.mono("", 11)
	inspect.add_child(_isolation_text)
	var compare := WorkbenchUI.section(self, "Compare with an earlier run", true)
	compare.add_child(WorkbenchUI.row([["Save as baseline", _save_baseline, "Keeps this analysis for this character and scenario"], ["Compare with baseline", _compare, "Improved, regressed, unchanged, and what cannot be compared"]]))
	_compare_text = WorkbenchUI.mono("", 11)
	compare.add_child(_compare_text)
	var export := WorkbenchUI.section(self, "Hand it to someone (or an agent)", true)
	export.add_child(WorkbenchUI.row([["Export report (JSON)", _export, "The same adda.report an agent gets from the command line"], ["Copy agent command", _copy_cli, "The headless command that reproduces this run"]]))
	_export_text = WorkbenchUI.label("", 12, WorkbenchUI.ACCENT)
	export.add_child(_export_text)
	_marker = FindingMarker.attach(bench)

func _recorder() -> SessionRecorder:
	return bench.diagnostics.recorder if bench.diagnostics != null else null

func _toggle_recording() -> void:
	if bench.diagnostics.recording_on():
		bench.diagnostics.end_recording()
	else:
		bench.diagnostics.begin_recording(func() -> float: return float(bench.scenario_runner.time) if bench.scenario_runner.running else -1.0, _mesh_check.button_pressed)

func _options() -> Dictionary:
	var scenario := String(bench.scenario_runner.scenario.get("id", "free"))
	var character := String(WorkbenchSession.character) if WorkbenchSession.character != &"" else "mira_0"
	return {"scenario": scenario, "character": character, "command": WorkbenchSession.repro_command(StringName(scenario) if scenario != "free" else &""),
		"cli": "tools/adda.ps1 run -Scenario %s -Character %s%s%s" % [scenario, character, "" if WorkbenchSession.armed else " -Unarmed", " -Mesh" if _mesh_check.button_pressed else ""]}

## Builds the report from the recording so far and lists its findings.
func _analyze() -> void:
	var recorder := _recorder()
	if recorder == null or recorder.rows.is_empty():
		# Never leave an older run's findings on screen under a "no recording" line: they would read as this run's.
		_report = {}
		_selected = {}
		_marker.clear()
		for child in _list.get_children():
			child.queue_free()
		_more.visible = false
		_observed.text = "Select a finding above."
		_causes.text = ""
		_detail.text = ""
		_headline.text = "There is no recording yet. Play a scenario (Start tab) or press 'Record (free play)', then ask again."
		return
	_report = AddaReport.build(recorder, _options())
	_selected = {}
	_marker.clear()
	_headline.text = "%s  (%s)" % [String(_report.summary.headline), _run_label()]
	_rebuild_list()

func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	var findings: Array = _report.get("findings", [])
	var shown := 0
	for finding: Dictionary in findings:
		if not _show_all and shown >= 8:
			break
		shown += 1
		var button := Button.new()
		button.text = list_label(finding)
		button.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = String(finding.observation.text)
		button.add_theme_color_override("font_color", _colour(String(finding.severity)))
		button.pressed.connect(_select.bind(finding))
		_list.add_child(button)
	_more.visible = findings.size() > 8
	_more.text = "Show fewer" if _show_all else "Show the other %d" % (findings.size() - shown)   # the remaining items, notes included: never a total that disagrees with the headline

## Who the run was: the scenario and character, so a list is never mistaken for another run's.
func _run_label() -> String:
	var config: Dictionary = _report.get("config", {})
	var scenario := WorkbenchScenarios.find(StringName(String(config.get("scenario", ""))))
	return "%s, %s" % [String(scenario.get("short", config.get("scenario", "free play"))) if not scenario.is_empty() else "free play", String(config.get("character", ""))]

## A finding as one list line, WHEN and WHAT first: "5.42 s  right forearm  HIGH  Pose snap: 2 bones at once".
func list_label(finding: Dictionary) -> String:
	var at := moment_of(finding)
	var part := String(finding.get("subject", {}).get("text", ""))
	var when := ("%.2f s  " % at) if at >= 0.0 else ""
	return "%s%s%s  %s" % [when, (part + "  ") if part != "" and not String(finding.title).to_lower().begins_with(part.to_lower()) else "", String(finding.severity).to_upper(), finding.title]

## The scenario time of a finding's WORST frame (where to look), or its start when that row was not kept; -1 when the run had no scenario clock.
func moment_of(finding: Dictionary) -> float:
	var row := _row_of(finding)
	if not row.is_empty() and float(row.get("st", -1.0)) >= 0.0:
		return float(row.st)
	return float(finding.get("reproduce", {}).get("st", -1.0))

static func _colour(severity: String) -> Color:
	match severity:
		"high":
			return WorkbenchUI.BAD
		"medium":
			return WorkbenchUI.WARN
		"info":
			return WorkbenchUI.DIM
	return WorkbenchUI.TEXT

func _select(finding: Dictionary) -> void:
	_selected = finding
	_observed.text = "%s\n\n%s" % [finding.title, finding.observation.text]
	var hypotheses: Array = finding.hypotheses
	var lines: Array[String] = []
	if hypotheses.is_empty():
		lines.append("Possible causes: none that the measurements support.")
	else:
		lines.append("Possible causes (NOT confirmed):")
		for h: Dictionary in hypotheses:
			lines.append("- %s  (because: %s)" % [h.text, h.basis])
	lines.append("Cause: unknown until one of these is tested.")
	_causes.text = "\n".join(lines)
	_detail.text = Findings.explain(finding, true)

func _row_of(finding: Dictionary) -> Dictionary:
	var worst := int(finding.observation.frames.worst_n)
	for row: Dictionary in _report.get("samples", {}).get("rows", []):
		if int(row.n) == worst:
			return row
	return {}

func _show_it() -> void:
	if _selected.is_empty():
		return
	var row := _row_of(_selected)
	var point := _marker.show_finding(_selected, row)
	var bones: Array[String] = []
	for bone in _selected.subject.get("bones", []):
		bones.append(String(bone))
	bench.diagnostics.highlight_bones(bones)
	if point != Vector3.INF:
		bench.focus_on_world(point)

func _replay() -> void:
	if _selected.is_empty():
		return
	var id := StringName(String(_selected.reproduce.scenario))
	bench.step_seconds = maxf(float(_report.config.frame_dt_s), 0.0001)
	if not bench.replay_to(id, float(_selected.reproduce.st)):
		_observed.text += "\n\nThis scenario cannot be replayed here (it is free play, or needs a weapon this configuration does not have)."

## One action for "show me this problem": replay to the finding's worst frame, pause there, then mark it. Returns when it has arrived (or could not replay).
func go_there() -> void:
	if _selected.is_empty():
		return
	var finding := _selected
	var id := StringName(String(finding.reproduce.scenario))
	bench.step_seconds = maxf(float(_report.config.frame_dt_s), 0.0001)
	var at := moment_of(finding)
	if at < 0.0 or not bench.replay_to(id, at):
		_observed.text += "\n\nThis cannot be replayed here (it was free play, or needs a weapon this configuration does not have). 'Mark it again' still marks it on the current pose."
		return
	_observed.text = "%s\n\nGoing to %.2f s..." % [finding.title, at]
	while is_inside_tree() and bench.pending_steps() > 0:
		await get_tree().process_frame
	if not is_inside_tree() or _selected != finding:
		return
	await get_tree().process_frame
	_observed.text = "%s\n\n%s\n\nPaused at %.2f s, the worst moment. Space resumes; 'Step frame' in the Scenario tab moves one frame." % [finding.title, finding.observation.text, at]
	_show_it()

func _copy_repro() -> void:
	if not _selected.is_empty():
		DisplayServer.clipboard_set(String(_selected.reproduce.replay))

func _copy_cli() -> void:
	DisplayServer.clipboard_set(String(_options().cli))

# ---- inspect a part (live, from the recorder's latest row)

func _on_part(index: int) -> void:
	if index <= 0:
		var none: Array[String] = []
		bench.diagnostics.highlight_bones(none)
		_part_text.text = ""
		return
	var bones := BodyParts.bones_of(bench.rig, _parts[index - 1])
	var names: Array[String] = []
	for bone in bones:
		names.append(bone)
		if is_instance_valid(_recorder()):
			_recorder().watch_bone(StringName(bone))
	bench.diagnostics.highlight_bones(names)
	if not bench.diagnostics.recording_on():
		_part_text.text = "Press 'Record (free play)' (or play a scenario) to read this part live."

## The isolation experiment on the chosen part: the pose is held (the bench is paused if it is not), every modifier is switched off in turn, and the result is written in words. The pause state is put back afterwards.
func _isolate() -> void:
	if _part_choice.selected <= 0:
		_isolation_text.text = "Choose a body part first."
		return
	var was_paused: bool = bench.sim_paused
	if not was_paused:
		bench.set_sim_paused(true)
	_isolation_text.text = "Running the experiment (about %d frames)..." % 14
	var bones := BodyParts.bones_of(bench.rig, _parts[_part_choice.selected - 1])
	var result: Dictionary = await StageIsolation.new().measure(bench.rig, bones, get_tree())
	_isolation_text.text = StageIsolation.text(result)
	if not was_paused:
		bench.set_sim_paused(false)

func refresh() -> void:
	var recorder := _recorder()
	if bench.sim_paused and bench.pending_steps() > 0:
		_status.text = "replaying to the moment: %d steps to go (one per frame)" % bench.pending_steps()
	elif recorder != null and recorder.recording:
		_status.text = "recording: %d frames, %.1f s%s" % [recorder.rows.size(), float(recorder.rows.back().t) if not recorder.rows.is_empty() else 0.0, "  (leg vertices sampled)" if recorder.mesh_every > 0 else ""]
	elif recorder != null and not recorder.rows.is_empty():
		_status.text = "stopped: %d frames recorded" % recorder.rows.size()
	else:
		_status.text = "not recording"
	if _part_choice.selected > 0 and recorder != null and not recorder.rows.is_empty():
		_part_text.text = _part_readout(recorder, _parts[_part_choice.selected - 1])

## One body part, live: where its bones are (the final pose, the character's frame), how fast they move, and which pose stages are declared to write them and are engaged right now.
func _part_readout(recorder: SessionRecorder, part: String) -> String:
	var row := recorder.latest()
	var before: Dictionary = recorder.rows[recorder.rows.size() - 2] if recorder.rows.size() > 1 else {}
	var lines: Array[String] = ["%s  (stage %s, %s)" % [part, row.context, row.state]]
	for bone in BodyParts.bones_of(bench.rig, part):
		var at: Variant = (row.bones as Dictionary).get(bone)
		if at == null:
			lines.append("%s: not in this recording yet" % bone)
			continue
		var speed := 0.0
		if not before.is_empty() and float(row.dt) > 0.0 and (before.bones as Dictionary).has(bone):
			speed = ((at as Vector3) - ((before.bones as Dictionary)[bone] as Vector3)).length() / float(row.dt)
		lines.append("%s\n  at (%.3f, %.3f, %.3f) m in the character's frame, moving %.2f m/s" % [bone, (at as Vector3).x, (at as Vector3).y, (at as Vector3).z, speed])
		var explained := PoseStageReport.explain_bone(bench.rig, bone)
		var writers: Array[String] = []
		for w: Dictionary in explained.declared_writers:
			writers.append("%s%s" % [w.stage, " (engaged)" if w.engaged else ""])
		lines.append("  stages declared to write it: %s" % (", ".join(writers) if not writers.is_empty() else "none (only the animation clip moves it)"))
	lines.append("(final pose, read inside skeleton_updated; stage ownership is DECLARED, not a measured change)")
	return "\n".join(lines)

# ---- compare, export

func _baseline_path() -> String:
	var options := _options()
	return "%s/baseline-%s-%s%s.json" % [FOLDER, options.character, options.scenario, "" if WorkbenchSession.armed else "-unarmed"]

func _save_baseline() -> void:
	if _report.is_empty():
		_compare_text.text = "Ask 'What happened?' first."
		return
	var error := AddaReport.save(_report, _baseline_path())
	_compare_text.text = "Baseline saved: %s" % ProjectSettings.globalize_path(_baseline_path()) if error == OK else "Could not save the baseline (error %d)" % error

func _compare() -> void:
	if _report.is_empty():
		_compare_text.text = "Ask 'What happened?' first."
		return
	var loaded := AddaReport.load_file(_baseline_path())
	if not bool(loaded.ok):
		_compare_text.text = "No baseline yet for this character and scenario (%s). Save one first." % loaded.error
		return
	_compare_text.text = ReportCompare.text(ReportCompare.compare(loaded.report, _report))

func _export() -> void:
	if _report.is_empty():
		_analyze()
	if _report.is_empty():
		_export_text.text = "Nothing recorded to export."
		return
	var options := _options()
	var path := "%s/%s-%s-%s.json" % [FOLDER, options.character, options.scenario, Time.get_datetime_string_from_system().replace(":", "-")]
	var error := AddaReport.save(_report, path)
	_export_text.text = "Saved %s" % ProjectSettings.globalize_path(path) if error == OK else "Could not save (error %d)" % error
