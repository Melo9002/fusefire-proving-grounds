class_name EvidenceTab
extends VBoxContainer
## "How do I reproduce, measure and communicate it?" A screenshot of the current view, a JSON report of the rig, the pose stages, the recent events and the contact summary, and the one command line that
## relaunches this exact configuration and scenario. Files go to user://workbench_evidence/ (the folder button opens it).

const FOLDER := "user://workbench_evidence"

var bench: Node3D
var _repro: Label
var _result: Label

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 5)
	var capture := WorkbenchUI.section(self, "Capture")
	capture.add_child(WorkbenchUI.row([["Screenshot", _screenshot, "Saves the window (panel included) as a PNG"], ["Export report (JSON)", _export_report], ["Open folder", _open_folder]]))
	_result = WorkbenchUI.label("", 12, WorkbenchUI.ACCENT)
	capture.add_child(_result)
	var repro := WorkbenchUI.section(self, "Reproduce")
	repro.add_child(WorkbenchUI.label("This command relaunches the current character, weapon state and the selected scenario:", 12, WorkbenchUI.DIM))
	_repro = WorkbenchUI.mono("", 11)
	_repro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repro.add_child(_repro)
	repro.add_child(WorkbenchUI.row([["Copy command", func() -> void: DisplayServer.clipboard_set(_repro.text)]]))
	var what := WorkbenchUI.section(self, "What the report contains", true)
	what.add_child(WorkbenchUI.label("Rig identity, roles, measurements and capabilities; the pose stages with their live state; the recent presentation events; and, when contact diagnostics are on, the latest contact measurement. Declared ownership and measured values are separate keys.", 12, WorkbenchUI.DIM))

func _path(extension: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var scenario := String(bench.scenario_runner.scenario.get("id", "free"))
	var character := String(WorkbenchSession.character) if WorkbenchSession.character != &"" else "mira_0"
	return "%s/%s-%s-%s.%s" % [FOLDER, character, scenario, Time.get_datetime_string_from_system().replace(":", "-"), extension]

func _screenshot() -> void:
	var image: Image = bench.get_viewport().get_texture().get_image()
	var path := _path("png")
	var error: int = image.save_png(path)
	_result.text = ("Saved %s" % ProjectSettings.globalize_path(path)) if error == OK else "Could not save the screenshot (error %d)" % error

func report() -> Dictionary:
	var data := {"command": WorkbenchSession.repro_command(bench.scenario_runner.scenario.get("id", &"")), "rig": RigInspection.report(bench.rig),
		"declared": {"stage_order": PoseOwnership.STAGE_ORDER.map(func(s: StringName) -> String: return String(s)), "order_problems": PoseStageReport.order_problems(bench.rig)},
		"runtime": {"stages": PoseStageReport.stages(bench.rig)}}
	var monitor: PresentationMonitor = bench.diagnostics.monitor
	if is_instance_valid(monitor):
		data.runtime["presentation"] = monitor.snapshot.duplicate()
		data.runtime["history"] = monitor.history.duplicate()
	var contacts: ContactErrorDiagnostics = bench.diagnostics.contacts
	if is_instance_valid(contacts) and not contacts.latest.is_empty():
		data.runtime["contacts"] = ContactErrorDiagnostics.scalars(contacts.latest)
		data.runtime["contact_recording"] = contacts.summary()
	return data

func _export_report() -> void:
	var path := _path("json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_result.text = "Could not write the report"
		return
	file.store_string(JSON.stringify(report(), "  ", true, true))
	_result.text = "Saved %s" % ProjectSettings.globalize_path(path)

func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(FOLDER))

func refresh() -> void:
	_repro.text = WorkbenchSession.repro_command(bench.scenario_runner.scenario.get("id", &""))
