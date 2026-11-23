extends SceneTree
## ADDA's command line: the interface a coding agent (or a person in a terminal) uses without the editor. One entry point, four commands. Use tools/adda.ps1 for the usual flags.
##
##   run      play a Workbench scenario headlessly with the recorder on, write an `adda.report` JSON, print the findings
##   inspect  print one finding of a report in full (observation, unconfirmed hypotheses, evidence, reproduction, the recorded rows around it)
##   compare  compare two reports: improved, regressed, unchanged, and what cannot validly be compared
##   list     the scenarios, characters and the report format
##
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/adda/adda.gd -- run --scenario=contacts --character=small_mira_0 --unarmed --mesh --out=user://adda/a.json
##
## Arguments (after `--`): run: --scenario=<id> [--character=<key>] [--unarmed] [--mesh[=N]] [--detail=full] [--window=n0-n1] [--out=<path>] [--fps=<n> (only recorded in the command line)] [--fail-on=high|medium]
##                         inspect: --report=<path> [--finding=<F1|key>] [--n=<row>]      compare: --a=<path> --b=<path> [--out=<path>] [--fail-on=regression]
## Exit codes: 0 done, 1 a --fail-on condition held, 2 a usage problem or a scenario that cannot run in this configuration (said plainly, never silently skipped).
const BENCH := "res://tools/animation_workbench/pose_workbench.tscn"
const DEFAULT_FOLDER := "user://adda"

func _initialize() -> void:
	_main.call_deferred()

func _parse() -> Dictionary:
	var out := {"command": "", "flags": {}}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var body := argument.trim_prefix("--")
			var at := body.find("=")
			if at >= 0:
				out.flags[body.substr(0, at)] = body.substr(at + 1)
			else:
				out.flags[body] = "true"
		elif String(out.command) == "":
			out.command = argument
	return out

func _fail(message: String, code := 2) -> void:
	printerr("adda: %s" % message)
	quit(code)

func _main() -> void:
	var parsed := _parse()
	var flags: Dictionary = parsed.flags
	match String(parsed.command):
		"run":
			await _run(flags)
		"inspect":
			_inspect(flags)
		"compare":
			_compare(flags)
		"list":
			_list()
		_:
			_fail("usage: run | inspect | compare | list   (see tools/adda/adda.gd)")

func _list() -> void:
	print("ADDA - AniLab Diagnostic & Debugging Assistant")
	print("scenarios (run --scenario=<id>):")
	for scenario in WorkbenchScenarios.all():
		print("  %-12s %s%s" % [scenario.id, scenario.title, "   (needs a weapon)" if scenario.needs_weapon else ""])
	print("characters (--character=<key>, optional --unarmed): %s" % ", ".join(PackedStringArray(Array(["mira_0", "small_mira_0"]))))
	print("report format: %s version %d" % [AddaReport.FORMAT, AddaReport.VERSION])
	quit(0)

# ---- run

func _run(flags: Dictionary) -> void:
	var id := StringName(String(flags.get("scenario", "")))
	var definition := WorkbenchScenarios.find(id)
	if definition.is_empty():
		_fail("unknown scenario '%s' (adda list shows them)" % id)
		return
	var bench: Node3D = (load(BENCH) as PackedScene).instantiate()
	root.add_child(bench)
	WorkbenchSession.autostart_scenario = &""   # this command starts the scenario itself, with the recorder already listening
	for i in 4:
		await process_frame
	var support := WorkbenchScenarios.supported(definition, bench.rig)
	if not bool(support.ok):
		_fail("scenario '%s' cannot run in this configuration: %s" % [id, support.reason])
		return
	var recorder := SessionRecorder.attach(bench.rig)
	recorder.clock = func() -> float: return float(bench.scenario_runner.time) if bench.scenario_runner.running else -1.0
	if flags.has("mesh"):
		recorder.enable_mesh(1 if String(flags.mesh) == "true" else maxi(int(flags.mesh), 1))
	bench.scenario_runner.step_run.connect(func(_index: int, label: String) -> void: recorder.mark(label, "scenario step"))
	recorder.start()
	bench.start_scenario(id)
	var limit := int((float(definition.duration) + 5.0) * 120.0)
	var frames := 0
	while bench.scenario_runner.running and frames < limit:
		await process_frame
		frames += 1
	recorder.stop()
	if bench.scenario_runner.running:
		_fail("the scenario did not finish within %d frames" % limit, 1)
		return
	var character := String(WorkbenchSession.character) if WorkbenchSession.character != &"" else "mira_0"
	var cli := "godot_console --headless%s --path . --script res://tools/adda/adda.gd -- run --scenario=%s --character=%s%s%s" % [(" --fixed-fps %s" % flags.fps) if flags.has("fps") else "", id, character, "" if WorkbenchSession.armed else " --unarmed", " --mesh" if flags.has("mesh") else ""]
	var window: Array = []
	if flags.has("window"):
		var parts := String(flags.window).split("-")
		if parts.size() == 2:
			window = [int(parts[0]), int(parts[1])]
	var report := AddaReport.build(recorder, {"scenario": String(id), "character": character, "command": WorkbenchSession.repro_command(id), "cli": cli, "detail": String(flags.get("detail", "summary")), "window": window})
	var default_path := "%s/%s-%s%s.json" % [DEFAULT_FOLDER, character, id, "" if WorkbenchSession.armed else "-unarmed"]
	var path := String(flags.get("out", default_path))
	var error := AddaReport.save(report, path)
	_print_summary(report, path, error)
	bench.queue_free()
	await process_frame
	var fail_on := String(flags.get("fail-on", ""))
	var counts: Dictionary = report.summary.findings
	if error != OK:
		quit(1)
	elif fail_on == "high" and int(counts.high) > 0 or fail_on == "medium" and int(counts.high) + int(counts.medium) > 0:
		quit(1)
	else:
		quit(0)

func _print_summary(report: Dictionary, path: String, error: Error) -> void:
	var config: Dictionary = report.config
	print("ADDA run: %s | %s | %d rows over %.2f s at %.0f fps | revision %s%s" % [config.scenario, config.identity, config.rows, config.duration_s, config.fps, config.revision.commit, "+dirty" if config.revision.get("dirty", false) else ""])
	print(report.summary.headline)
	var shown := 0
	for finding: Dictionary in report.findings:
		if shown >= 10:
			print("  ... %d more (adda inspect --report=%s lists them all)" % [report.findings.size() - shown, path])
			break
		shown += 1
		print("  %s [%s] %s" % [finding.id, String(finding.severity).to_upper(), finding.title])
		print("      %s" % finding.observation.text)
	if error == OK:
		print("report: %s" % ProjectSettings.globalize_path(path))
		print("next:   adda inspect --report=%s --finding=F1" % path)
	else:
		printerr("adda: could not write %s (error %d)" % [path, error])

# ---- inspect

func _inspect(flags: Dictionary) -> void:
	var loaded := AddaReport.load_file(String(flags.get("report", "")))
	if not bool(loaded.ok):
		_fail(String(loaded.error))
		return
	var report: Dictionary = loaded.report
	if flags.has("n"):
		_print_row(report, int(flags.n))
		quit(0)
		return
	if not flags.has("finding"):
		print(report.summary.headline)
		for finding: Dictionary in report.findings:
			print(Findings.explain(finding))
		quit(0)
		return
	var wanted := String(flags.finding)
	for finding: Dictionary in report.findings:
		if finding.id == wanted or finding.key == wanted:
			print(Findings.explain(finding, true))
			var frames: Dictionary = finding.observation.frames
			print("  Recorded rows around the worst frame:")
			for n in range(int(frames.worst_n) - 2, int(frames.worst_n) + 3):
				_print_row(report, n, "    ")
			quit(0)
			return
	_fail("no finding '%s' in %s (ids: %s)" % [wanted, flags.report, ", ".join(report.findings.map(func(f: Dictionary) -> String: return String(f.id)))])

func _print_row(report: Dictionary, n: int, indent := "") -> void:
	for row: Dictionary in report.samples.rows:
		if int(row.n) != n:
			continue
		var parts: Array[String] = ["%srow %d  t %.3f s  scenario %.2f s  %s/%s  stages %s" % [indent, n, float(row.t), float(row.st), row.state, row.context, ",".join(row.stages)]]
		for hand: Dictionary in row.hands:
			parts.append("%s  %s hand: error %.1f mm, margin %.1f cm, weight %.2f, %s%s" % [indent, hand.name, float(hand.error_mm), float(hand.reach_margin_cm), float(hand.weight), hand.owner, " UNREACHABLE" if hand.unreachable else ""])
		for foot: Dictionary in row.feet:
			parts.append("%s  %s foot: error %.1f mm, %s weight %.2f %s" % [indent, foot.name, float(foot.error_mm), "planted" if foot.planted else "swing", float(foot.weight), foot.source])
		if row.has("mesh"):
			parts.append("%s  mesh: %s" % [indent, JSON.stringify(row.mesh)])
		print("\n".join(parts))
		return
	print("%srow %d is not among this report's samples (re-run with --window=%d-%d or --detail=full)" % [indent, n, maxi(n - 5, 0), n + 5])

# ---- compare

func _compare(flags: Dictionary) -> void:
	var a := AddaReport.load_file(String(flags.get("a", "")))
	var b := AddaReport.load_file(String(flags.get("b", "")))
	for loaded in [a, b]:
		if not bool(loaded.ok):
			_fail(String(loaded.error))
			return
	var result := ReportCompare.compare(a.report, b.report)
	print(ReportCompare.text(result))
	if flags.has("out"):
		var file := FileAccess.open(String(flags.out), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "  ", true))
			file.close()
			print("comparison: %s" % ProjectSettings.globalize_path(String(flags.out)))
	if String(flags.get("fail-on", "")) == "regression" and String(result.verdict) in ["REGRESSED", "MIXED"]:
		quit(1)
	else:
		quit(0)
