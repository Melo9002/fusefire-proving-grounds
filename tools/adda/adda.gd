extends SceneTree
## ADDA's command line: the interface a coding agent (or a person in a terminal) uses without the editor. One entry point, four commands. Use tools/adda.ps1 for the usual flags.
##
##   run      play a Workbench scenario headlessly with the recorder on, write an `adda.report` JSON, print the findings
##   inspect  print one finding of a report in full (observation, unconfirmed hypotheses, evidence, reproduction, the recorded rows around it)
##   compare  compare two reports: improved, regressed, unchanged, and what cannot validly be compared
##   isolate  an EXPERIMENT: play a scenario to a moment, hold it, switch each pose modifier off in turn and report which ones move the named bones (declared stages and undeclared modifiers alike)
##   challenges  the diagnostic challenges (symptoms only); score checks an answer: score --challenge=<id> --stage=<modifier name> --bone=<name|@role> --kind=<offset|pop|drift|yaw|none>
##   list     the scenarios, characters and the report format
##
## An EXPERIMENT changes one thing on purpose and says so in the report (`config.experiment`): --disable=<modifier,...> runs with those pose modifiers switched off, --set=<NodePath>.<property>=<value> sets one property
## of a node under the rig (a number, true/false, or a Godot literal such as Vector3(0,1,0)); a path or property that does not exist is a usage error, never silently ignored.
##
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/adda/adda.gd -- run --scenario=contacts --character=small_mira_0 --unarmed --mesh --out=user://adda/a.json
##
## Arguments (after `--`): run: --scenario=<id> [--character=<key>] [--unarmed] [--mesh[=N]] [--detail=full] [--window=n0-n1] [--out=<path>] [--fps=<n> (only recorded in the command line)] [--fail-on=high|medium]
##                         (run and isolate also take --fault=<json> or --challenge=<id>: a known fault injected for diagnostic challenges, see docs/claude/adda/)
##                         isolate: --scenario=<id> --at=<seconds> --bones=<name|@role,...> [--window=<updates>: sample that many updates per condition, to see a fault that fires only on some] [--character=..] [--unarmed] [--out=<path>]
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
		"isolate":
			await _isolate(flags)
		"challenges":
			_challenges()
		"score":
			_score(flags)
		"inspect":
			_inspect(flags)
		"compare":
			_compare(flags)
		"list":
			_list()
		_:
			_fail("usage: run | inspect | compare | list   (see tools/adda/adda.gd)")

func _challenges() -> void:
	print("ADDA diagnostic challenges. Run one with: run --scenario=<s> --character=<c> [--unarmed] --challenge=<id>. Do not open tools/adda/challenges/sealed/ before you have scored an answer.")
	for entry: Dictionary in ChallengeSet.index():
		print("  %s  %s
      %s | %s%s
	  %s" % [entry.id, entry.title, entry.scenario, entry.character, "" if bool(entry.armed) else " (unarmed)", entry.symptom])
	quit(0)

func _score(flags: Dictionary) -> void:
	var answer := {}
	for field in ["stage", "bone", "kind"]:
		if flags.has(field):
			answer[field] = String(flags[field])
	var result := ChallengeSet.score(String(flags.get("challenge", "")), answer)
	if not bool(result.ok):
		_fail(String(result.error))
		return
	print("%s: %s  (checked %s)" % [result.challenge, "CORRECT" if bool(result.correct) else "NOT CORRECT", ", ".join(result.scored_fields)])
	for field in result.fields:
		print("  %s: %s" % [field, "matches" if bool(result.fields[field]) else "does not match"])
	quit(0 if bool(result.correct) else 1)

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
	var fault_note := _install_fault(bench, flags)
	var experiment := _apply_experiment(bench.rig, flags)
	if experiment.has("error"):
		_fail(String(experiment.error))
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
	var switched_back := {}
	while bench.scenario_runner.running and frames < limit:
		await process_frame
		frames += 1
		for name in experiment.get("disabled", []):
			if (bench.rig.skeleton.get_node(NodePath(String(name))) as SkeletonModifier3D).active:
				switched_back[name] = int(switched_back.get(name, 0)) + 1
	recorder.stop()
	if bench.scenario_runner.running:
		_fail("the scenario did not finish within %d frames" % limit, 1)
		return
	var character := String(WorkbenchSession.character) if WorkbenchSession.character != &"" else "mira_0"
	var cli := "godot_console --headless%s --path . --script res://tools/adda/adda.gd -- run --scenario=%s --character=%s%s%s%s" % [(" --fixed-fps %s" % flags.fps) if flags.has("fps") else "", id, character, "" if WorkbenchSession.armed else " --unarmed", " --mesh" if flags.has("mesh") else "", _lever_text(flags)]
	var window: Array = []
	if flags.has("window"):
		var parts := String(flags.window).split("-")
		if parts.size() == 2:
			window = [int(parts[0]), int(parts[1])]
	var report := AddaReport.build(recorder, {"scenario": String(id), "character": character, "command": WorkbenchSession.repro_command(id), "cli": cli, "detail": String(flags.get("detail", "summary")), "window": window, "experiment": _experiment_text(experiment, switched_back, frames)})
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

## Faults for diagnostic challenges. `--fault={json}` injects one directly; `--challenge=<id>` takes it from tools/adda/challenges (the answer is not printed: the point of a blind challenge).
func _install_fault(bench: Node, flags: Dictionary) -> String:
	var spec := {}
	if flags.has("fault"):
		var parsed = JSON.parse_string(String(flags.fault))
		if parsed is Dictionary:
			spec = parsed
	elif flags.has("challenge"):
		spec = ChallengeSet.fault_of(String(flags.challenge))
	if spec.is_empty():
		return ""
	ChallengeFault.install(bench.rig, spec, func() -> float: return bench.scenario_runner.time)
	return "fault installed"

## The experiment: stage the scenario to a moment, hold it, and ask StageIsolation which modifiers move the named bones.
func _isolate(flags: Dictionary) -> void:
	var id := StringName(String(flags.get("scenario", "")))
	var definition := WorkbenchScenarios.find(id)
	if definition.is_empty():
		_fail("unknown scenario '%s' (adda list shows them)" % id)
		return
	var bench: Node3D = (load(BENCH) as PackedScene).instantiate()
	root.add_child(bench)
	WorkbenchSession.autostart_scenario = &""
	for i in 4:
		await process_frame
	var support := WorkbenchScenarios.supported(definition, bench.rig)
	if not bool(support.ok):
		_fail("scenario '%s' cannot run in this configuration: %s" % [id, support.reason])
		return
	_install_fault(bench, flags)
	bench.step_seconds = 1.0 / 60.0
	if not bench.start_scenario(id, false):
		_fail("scenario '%s' did not start" % id)
		return
	bench.set_sim_paused(true)
	var steps := int(round(float(flags.get("at", "0")) * 60.0))
	bench.step_sim(steps)
	var guard := 0
	while bench.pending_steps() > 0 and guard < steps + 600:
		await process_frame
		guard += 1
	for i in 6:
		await process_frame
	var bones: Array[String] = []
	for name in String(flags.get("bones", "")).split(",", false):
		var resolved := ChallengeFault.resolve(bench.rig, name.strip_edges())
		if resolved != "":
			bones.append(resolved)
	var result := await StageIsolation.new().measure(bench.rig, bones, self, maxi(int(flags.get("window", "1")), 1))
	result["config"] = {"scenario": String(id), "character": String(WorkbenchSession.character), "armed": WorkbenchSession.armed, "at_s": float(flags.get("at", "0")), "frame_step_s": 1.0 / 60.0,
		"revision": AddaReport.revision(), "cli": "godot_console --headless --fixed-fps 60 --path . --script res://tools/adda/adda.gd -- isolate --scenario=%s --at=%s --bones=%s --character=%s%s%s%s" % [id, flags.get("at", "0"), flags.get("bones", ""), String(WorkbenchSession.character), "" if WorkbenchSession.armed else " --unarmed", _lever_text(flags), (" --window=%s" % flags.window) if flags.has("window") else ""]}
	result["config"]["held_at_s"] = snappedf(bench.scenario_runner.time, 0.001)
	print("Pose held at scenario time %.2f s (requested %s s; the scenario does not advance during the experiment)" % [bench.scenario_runner.time, flags.get("at", "0")])
	print(StageIsolation.text(result))
	if flags.has("out"):
		var file := FileAccess.open(String(flags.out), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "  ", true))
			file.close()
			print("isolation: %s" % ProjectSettings.globalize_path(String(flags.out)))
	bench.queue_free()
	await process_frame
	quit(0 if String(result.status) != "unavailable" else 2)

## Experiment levers. Returns {applied: [text,...]} or {error}.
func _apply_experiment(rig: CharacterRig, flags: Dictionary) -> Dictionary:
	var applied: Array[String] = []
	var disabled: Array[String] = []
	for name in String(flags.get("disable", "")).split(",", false):
		var modifier := rig.skeleton.get_node_or_null(NodePath(name.strip_edges())) as SkeletonModifier3D
		if modifier == null:
			return {"error": "--disable: no modifier named '%s' under the skeleton (modifiers: %s)" % [name, ", ".join(rig.skeleton.get_children().filter(func(c: Node) -> bool: return c is SkeletonModifier3D).map(func(c: Node) -> String: return String(c.name)))]}
		modifier.active = false
		disabled.append(name.strip_edges())
		applied.append("disabled %s" % name.strip_edges())
	for item in String(flags.get("set", "")).split(";", false):
		var eq := item.find("=")
		var dot := item.rfind(".", eq if eq >= 0 else item.length())
		if eq < 0 or dot < 0 or dot > eq:
			return {"error": "--set: expected <NodePath>.<property>=<value>, got '%s'" % item}
		var path := item.substr(0, dot)
		var property := item.substr(dot + 1, eq - dot - 1)
		var node: Node = rig if path in ["", "."] else rig.get_node_or_null(NodePath(path))
		if node == null:
			return {"error": "--set: no node '%s' under the rig" % path}
		if not property in node:
			return {"error": "--set: node '%s' has no property '%s'" % [path, property]}
		node.set(property, str_to_var(item.substr(eq + 1)))
		applied.append("set %s.%s = %s" % [path, property, item.substr(eq + 1)])
	return {"applied": applied, "disabled": disabled}

## What the report says about the experiment, including a modifier its owner kept switching back on (then the experiment did not hold, and a "no change" would be a false negative).
func _experiment_text(experiment: Dictionary, switched_back: Dictionary, frames: int) -> Array:
	var out: Array = []
	for line in experiment.get("applied", []):
		var text := String(line)
		for name in switched_back:
			if text == "disabled %s" % name:
				text += " (NOT HELD: the rig switched it back on in %d of %d frames, so this did not test what it says)" % [int(switched_back[name]), frames]
		out.append(text)
	return out

## The levers of a run as command-line text (the challenge or fault that was injected, the modifiers disabled, the values set), so a reproduction command repeats the same run.
func _lever_text(flags: Dictionary) -> String:
	var text := ""
	if flags.has("challenge"):
		text += " --challenge=%s" % flags.challenge
	elif flags.has("fault"):
		text += " --fault=%s" % flags.fault
	if flags.has("disable"):
		text += " --disable=%s" % flags.disable
	if flags.has("set"):
		text += ' --set="%s"' % flags.set
	return text

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
