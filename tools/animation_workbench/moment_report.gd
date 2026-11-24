class_name MomentReport
extends RefCounted
## "Report this moment": a person pauses on something that looks wrong, writes one sentence, and this saves what a coding agent needs to reproduce and investigate it, in a folder they can commit and hand over:
##   adda_reports/<date>-<scenario>-<words>/
##     README.md     the note, how to reproduce it (window and command line), what was on screen, ADDA's observations near that moment, what is NOT established, and first steps for an agent
##     moment.json   the same as data (format adda.moment, version 1)
##     screenshot.png  the view when the report was made
##     adda_report.json  ADDA's analysis of the recording so far (when there is one), the same format `adda run` writes
##     tuning/       copies of the Tune drafts in use (they are local and not committed, so they travel with the report)
## The note is a person's judgement of how it LOOKS; ADDA's findings are measurements; neither is a cause. The report says so.

const FORMAT := "adda.moment"
const VERSION := 1
const FOLDER := "res://adda_reports"
## Findings whose worst moment is within this many seconds of the reported moment are listed as nearby evidence.
const NEAR_SECONDS := 1.0

## Where reports go (tests point it at a scratch folder).
static var folder := FOLDER

## Writes a report for what the workbench shows now. Returns {ok, path, message}.
static func save(bench: Node3D, note: String) -> Dictionary:
	var data := build(bench, note)
	var name := "%s-%s-%s" % [Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-"), String(data.moment.scenario if data.moment.scenario != "" else "free"), _slug(note)]
	var dir := folder.path_join(name)
	var absolute := ProjectSettings.globalize_path(dir)
	if folder.begins_with("res://") and not FileAccess.file_exists(folder.path_join(".gdignore")):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		_write(ProjectSettings.globalize_path(folder.path_join(".gdignore")), "")   # Godot does not import the screenshots and JSON as project assets
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		return {"ok": false, "path": dir, "message": "Could not create %s." % dir}
	# Evidence first, so the files it names exist.
	var files: Array[String] = []
	var image: Image = null
	if DisplayServer.get_name() != "headless" and bench.get_viewport() != null:   # headless has nothing drawn to capture
		image = bench.get_viewport().get_texture().get_image()
	if image != null and not image.is_empty() and image.save_png(absolute.path_join("screenshot.png")) == OK:
		files.append("screenshot.png")
	if not (data.adda_report as Dictionary).is_empty():
		if AddaReport.save(data.adda_report, dir.path_join("adda_report.json")) == OK:
			files.append("adda_report.json")
	for draft in data.tuning.drafts_in_use:
		var target := "tuning/%s" % String(draft).get_file()
		DirAccess.make_dir_recursive_absolute(absolute.path_join("tuning"))
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(String(draft)), absolute.path_join(target)) == OK:
			files.append(target)
	data.files = files
	var json := data.duplicate()
	json.erase("adda_report")   # it is its own file
	_write(absolute.path_join("moment.json"), JSON.stringify(json, "  "))
	_write(absolute.path_join("README.md"), markdown(json))
	return {"ok": true, "path": dir, "message": "Saved %s. Give an agent this folder (commit it if the agent works elsewhere)." % dir}

## The report as data, from what the workbench shows now.
static func build(bench: Node3D, note: String) -> Dictionary:
	var rig: CharacterRig = bench.rig
	var runner: WorkbenchScenarioRunner = bench.scenario_runner
	var scenario_id := String(runner.scenario.get("id", "")) if runner.running else ""
	var st := float(runner.time) if runner.running else -1.0
	var step := float(bench.step_seconds)
	var character := String(WorkbenchSession.character) if WorkbenchSession.character != &"" else "mira_0"
	var monitor: PresentationMonitor = bench.diagnostics.monitor if bench.diagnostics != null and is_instance_valid(bench.diagnostics.monitor) else null
	if monitor != null:
		monitor.refresh()
	var moment := {
		"scenario": scenario_id, "scenario_title": String(runner.scenario.get("title", "")) if scenario_id != "" else "free play",
		"scenario_time_s": snappedf(st, 0.0001), "scenario_step": runner.current_label() if scenario_id != "" else "",
		"frame": int(round(st / maxf(step, 0.0001))) if st >= 0.0 else -1, "frame_step_s": step,
		"paused": bool(bench.sim_paused), "presenter_time_s": snappedf(float(rig.presenter.time), 0.0001) if is_instance_valid(rig.presenter) else -1.0}
	var state := {"animation_state": String(rig.animation_controller.current_state) if is_instance_valid(rig.animation_controller) else "", "where": bench.where_text(),
		"speed_mps": snappedf(float(rig.presenter.speed), 0.001) if is_instance_valid(rig.presenter) else 0.0}
	if monitor != null:
		for key in ["posture", "posture_depth", "readiness", "equipment", "aim_blend", "contexts", "facing_yaw_deg"]:
			state[key] = monitor.snapshot.get(key)
	var stages: Array[String] = []
	for stage in PoseOwnership.STAGE_ORDER:
		var node := rig.skeleton.get_node_or_null(NodePath(String(stage))) if is_instance_valid(rig.skeleton) else null
		if node is SkeletonModifier3D and (node as SkeletonModifier3D).active and (node as SkeletonModifier3D).influence > 0.0:
			stages.append(String(stage))
	state["pose_stages_active"] = stages
	var tuning := _tuning(rig)
	var reproduce := _reproduce(scenario_id, character, bool(WorkbenchSession.armed), st, not (tuning.drafts_in_use as Array).is_empty())
	var evidence := _evidence(bench, scenario_id, character, st)
	return {"format": FORMAT, "version": VERSION, "note": note.strip_edges(), "created": Time.get_datetime_string_from_system(false, true),
		"revision": AddaReport.revision(), "engine": Engine.get_version_info().string,
		"character": character, "armed": bool(WorkbenchSession.armed), "moment": moment, "on_screen": state, "tuning": tuning, "reproduce": reproduce,
		"evidence": evidence.summary, "adda_report": evidence.report,
		"not_established": ["The note is a person's judgement of how the animation looks at this moment. It is not a measurement and it names no cause.",
			"ADDA's findings near the moment are measurements (a jump, a distance to a target). They do not say the animation is wrong or why; a clean list does not say it is right.",
			"A numerical improvement after a change is not proof the animation looks better: a person compares the result."]}

static func _tuning(rig: CharacterRig) -> Dictionary:
	var drafts: Array[String] = []
	var game: Array[String] = []
	var root := rig.tuning_folder()
	if root != "":
		for property in CharacterRig.TUNED_PROFILES:
			if TuningFiles.has_draft(rig, property) and CharacterRig.use_drafts:
				drafts.append(TuningFiles.draft_path(rig, property))
			if FileAccess.file_exists(root.path_join("%s.tres" % property)):
				game.append(root.path_join("%s.tres" % property))
		if CharacterRig.use_drafts and FileAccess.file_exists(ClipFiles.library_path(rig)):
			drafts.append(ClipFiles.library_path(rig))
		if FileAccess.file_exists(ClipFiles.game_path(rig)):
			game.append(ClipFiles.game_path(rig))
	return {"drafts_in_use": drafts, "game_files": game, "changes_from_game": TuningFiles.all_changes(rig) if CharacterRig.use_drafts else {},
		"clips_not_in_game": ClipFiles.changed_clips(rig).map(func(c: StringName) -> String: return String(c)) if CharacterRig.use_drafts else []}

static func _reproduce(scenario_id: String, character: String, armed: bool, st: float, drafts: bool) -> Dictionary:
	var unarmed := "" if armed else " --unarmed"
	var unarmed_ps := "" if armed else " -Unarmed"
	if scenario_id == "":
		return {"window": "godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=%s%s" % [character, unarmed], "headless": "", "at": "",
			"note": "Free play: there is no scripted scenario to replay, so the exact moment cannot be reproduced; the screenshot and on-screen state are what there is."}
	var drafts_note := " The report's tuning/ folder holds the Tune drafts that were in use: copy them to art/characters/%s/tuning/drafts/ and add -Drafts to reproduce exactly what the person saw." % character if drafts else ""
	return {"window": "godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=%s%s --scenario=%s" % [character, unarmed, scenario_id],
		"at": "%.2f" % st,
		"headless": ".\\tools\\adda.ps1 run -Scenario %s -Character %s%s%s -Detail full -Out adda-moment.json" % [scenario_id, character, unarmed_ps, " -Drafts" if drafts else ""],
		"isolate": ".\\tools\\adda.ps1 isolate -Scenario %s -Character %s%s%s -At %.2f -Bones \"@left_foot,@right_foot,@left_knee,@right_knee,@left_hand,@right_hand\"" % [scenario_id, character, unarmed_ps, " -Drafts" if drafts else "", st],
		"note": "In the window: start the scenario, then the Scenario tab's progress bar or 'Back 1 s' reaches %.2f s; or the Why? tab's 'Go there' on a nearby finding. Runs are deterministic at a fixed step.%s" % [st, drafts_note]}

## ADDA's observations near the moment, from the recording the workbench keeps while a scenario plays.
static func _evidence(bench: Node3D, scenario_id: String, character: String, st: float) -> Dictionary:
	var recorder: SessionRecorder = bench.diagnostics.recorder if bench.diagnostics != null else null
	if recorder == null or recorder.rows.is_empty():
		return {"summary": {"recorded": false, "why": "nothing was recorded (play a scenario from the Start tab to record it)"}, "report": {}}
	var report := AddaReport.build(recorder, {"scenario": scenario_id, "character": character, "command": WorkbenchSession.repro_command(StringName(scenario_id)) if scenario_id != "" else "", "cli": ""})
	var rows: Array = recorder.rows   # every row, so a finding's worst moment is always found
	var near: Array = []
	for finding: Dictionary in report.get("findings", []):
		var at := _moment_of(finding, rows)
		if st >= 0.0 and at >= 0.0 and absf(at - st) <= NEAR_SECONDS:
			near.append({"id": finding.id, "severity": finding.severity, "title": finding.title, "at_s": snappedf(at, 0.01), "observed": finding.observation.text,
				"possible_causes_not_confirmed": (finding.hypotheses as Array).map(func(h: Dictionary) -> String: return "%s (test: %s)" % [h.text, h.experiment])})
	var last: Dictionary = recorder.rows.back()
	var contacts := {"hands": last.get("hands", []), "feet": last.get("feet", [])}
	return {"summary": {"recorded": true, "rows": recorder.rows.size(), "headline": report.summary.headline, "findings_within_s": NEAR_SECONDS, "near": near,
		"contacts_now": JSON.parse_string(JSON.stringify(contacts, "", false, true))}, "report": report}

static func _moment_of(finding: Dictionary, rows: Array) -> float:
	var worst := int(finding.get("observation", {}).get("frames", {}).get("worst_n", -1))
	for row: Dictionary in rows:
		if int(row.n) == worst and float(row.get("st", -1.0)) >= 0.0:
			return float(row.st)
	return float(finding.get("reproduce", {}).get("st", -1.0))

## The README an agent (or a person) reads first.
static func markdown(data: Dictionary) -> String:
	var m: Dictionary = data.moment
	var r: Dictionary = data.reproduce
	var e: Dictionary = data.evidence
	var t: Dictionary = data.tuning
	var lines: Array[String] = []
	lines.append("# Animation report: %s" % (data.note if String(data.note) != "" else "(no note)"))
	lines.append("")
	lines.append("> %s" % (data.note if String(data.note) != "" else "The person did not write a note."))
	lines.append("")
	lines.append("| | |")
	lines.append("|---|---|")
	lines.append("| Character | %s, %s |" % [data.character, "armed" if bool(data.armed) else "unarmed"])
	lines.append("| Scenario | %s |" % ("%s (`%s`), step \"%s\"" % [m.scenario_title, m.scenario, m.scenario_step] if String(m.scenario) != "" else "free play"))
	lines.append("| Moment | %s |" % ("scenario time %.2f s, frame %d at %.4f s a frame%s" % [m.scenario_time_s, m.frame, m.frame_step_s, ", paused" if bool(m.paused) else ", playing"] if float(m.scenario_time_s) >= 0.0 else "no scenario clock"))
	lines.append("| Revision | %s on %s%s |" % [data.revision.get("commit", "?"), data.revision.get("branch", "?"), " (uncommitted changes)" if bool(data.revision.get("dirty", false)) else ""])
	lines.append("| On screen | state `%s`, %s, %.2f m/s, stages %s |" % [data.on_screen.animation_state, data.on_screen.where, data.on_screen.speed_mps, ", ".join(data.on_screen.pose_stages_active)])
	lines.append("| Tuning | %s |" % ("game values only" if (t.drafts_in_use as Array).is_empty() else "Tune DRAFTS in use (copied into `tuning/`): %s" % ", ".join((t.drafts_in_use as Array).map(func(p: String) -> String: return p.get_file()))))
	lines.append("")
	if data.files.has("screenshot.png"):
		lines.append("![the moment](screenshot.png)")
		lines.append("")
	lines.append("## Reproduce")
	lines.append("")
	lines.append(String(r.get("note", "")))
	lines.append("")
	lines.append("```powershell")
	lines.append(String(r.window))
	if String(r.get("headless", "")) != "":
		lines.append(String(r.headless))
		lines.append(String(r.isolate))
	lines.append("```")
	lines.append("")
	if not (t.changes_from_game as Dictionary).is_empty() or not (t.clips_not_in_game as Array).is_empty():
		lines.append("## Tuning that differs from the game")
		lines.append("")
		for property in t.changes_from_game:
			for change: Dictionary in t.changes_from_game[property]:
				lines.append("* `%s.%s`: game %s, used here %s" % [property, change.path, change.game, change.now])
		for clip in t.clips_not_in_game:
			lines.append("* clip `%s`: edited by hand, not in the game" % clip)
		lines.append("")
	lines.append("## What ADDA measured near this moment (observations)")
	lines.append("")
	if not bool(e.get("recorded", false)):
		lines.append("Nothing: %s." % e.get("why", "no recording"))
	elif (e.near as Array).is_empty():
		lines.append("No finding within %.1f s of the moment. That does not mean nothing is wrong: ADDA measures jumps and distances to targets, not whether the action is the right one. Run summary: %s" % [e.findings_within_s, e.headline])
	else:
		for finding: Dictionary in e.near:
			lines.append("* **%s %s** at %.2f s: %s" % [String(finding.severity).to_upper(), finding.title, finding.at_s, finding.observed])
			for cause in finding.possible_causes_not_confirmed:
				lines.append("  * possible cause, NOT confirmed: %s" % cause)
		lines.append("")
		lines.append("Run summary: %s The whole analysis is in `adda_report.json`." % e.headline)
	lines.append("")
	lines.append("## Not established")
	lines.append("")
	for item in data.not_established:
		lines.append("* %s" % item)
	lines.append("")
	lines.append("## For a coding agent")
	lines.append("")
	lines.append("1. Read the note and look at the screenshot: that is the defect as a person sees it.")
	lines.append("2. Reproduce with the headless run above and confirm the measurements near %s s (`adda inspect`)." % (r.get("at", "?")))
	lines.append("3. Separate what is measured from what you suspect (docs/claude/adda/10-agent-workflow.md); test one change at a time (`-Disable`, `-Set`, or code) and `adda compare` before and after.")
	lines.append("4. Hand back to the person: what you changed, the compare, and a way to see the same moment (the window command and time above). Do not claim it looks better because the numbers improved.")
	lines.append("")
	return "\n".join(lines)

static func _slug(text: String) -> String:
	var words: Array[String] = []
	for word in text.to_lower().split(" ", false):
		var clean := ""
		for c in word:
			if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
				clean += c
		if clean != "":
			words.append(clean)
		if words.size() >= 5:
			break
	return "-".join(words) if not words.is_empty() else "moment"

static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
