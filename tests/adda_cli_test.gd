extends SceneTree
## ADDA's command line, end to end: the interface an agent uses. It starts real engine processes (headless, fixed 60 fps) and checks what an agent would see: exit codes, the report file, the printed findings, a
## comparison of two runs, a refusal with its reason, and that observing changes nothing.
##   1 list           the scenarios are named
##   2 run            exit 0, a report is written, it names scenario, character, equipment, revision, reproduction command and fps, and prints findings
##   3 reproducible   the same command twice gives the same metrics and the same findings, so a before/after difference is a real difference
##   4 inspect        a finding is printed in full; an unknown finding is a usage error
##   5 compare        two runs compare; armed against unarmed and Small MIRA against MIRA say what differs; a regression exits 1 under --fail-on=regression, an improvement does not
##   6 refusal        an unsupported configuration exits 2 and says why (no silent skip)
##   7 passive        the recorder, with and without leg-vertex sampling, leaves every final pose bit-identical (probe hash)
## It runs about fifteen engine processes (about one minute).
var failures := 0
var checks := 0
var _exe := OS.get_executable_path()
var _project := ProjectSettings.globalize_path("res://")

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Runs the engine on a script with arguments; returns {code, text}.
func _engine(script: String, args: Array, fixed_fps := true) -> Dictionary:
	var arguments: Array = ["--headless"]
	if fixed_fps:
		arguments.append_array(["--fixed-fps", "60"])
	arguments.append_array(["--path", _project, "--script", script, "--"])
	arguments.append_array(args)
	var output := []
	var code := OS.execute(_exe, arguments, output, true)
	return {"code": code, "text": "\n".join(output)}

func _adda(args: Array, fixed_fps := true) -> Dictionary:
	return _engine("res://tools/adda/adda.gd", args, fixed_fps)

func _load(path: String) -> Dictionary:
	var loaded := AddaReport.load_file(path)
	return loaded.report if bool(loaded.ok) else {}

func _run() -> void:
	var folder := "user://adda_cli_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var a_path := "%s/a.json" % folder
	var b_path := "%s/b.json" % folder
	var unarmed_path := "%s/unarmed.json" % folder
	var small_path := "%s/small.json" % folder

	var listed := _adda(["list"], false)
	check(listed.code == 0 and String(listed.text).contains("contacts") and String(listed.text).contains("landing") and String(listed.text).contains("rescue") and String(listed.text).contains("adda.report"), "list: exit 0 and the scenarios and the report format are named")

	var first := _adda(["run", "--scenario=contacts", "--fps=60", "--out=%s" % a_path])
	check(first.code == 0, "run: exit 0 (%d)" % first.code)
	check(String(first.text).contains("ADDA run: contacts") and String(first.text).contains("finding") and String(first.text).contains("report:"), "run prints what it ran, the findings and where the report is")
	var a := _load(a_path)
	check(not a.is_empty() and a.config.scenario == "contacts" and a.config.character == "mira_0" and a.config.armed == true, "the report loads and says what was run (%s)" % [a.get("config", {}).get("identity", "")])
	check(a.config.has("revision") and String(a.config.revision.commit) != "" and String(a.config.cli).contains("adda.gd") and absf(float(a.config.fps) - 60.0) < 0.5, "and where the source was (%s), how to repeat it, and the frame rate (%.1f)" % [a.get("config", {}).get("revision", {}).get("commit", ""), float(a.get("config", {}).get("fps", 0.0))])

	var second := _adda(["run", "--scenario=contacts", "--fps=60", "--out=%s" % b_path])
	var b := _load(b_path)
	var identical := not a.is_empty() and not b.is_empty() and (a.summary.metrics as Dictionary).size() == (b.summary.metrics as Dictionary).size()
	var worst := 0.0
	if identical:
		for key in a.summary.metrics:
			worst = maxf(worst, absf(float(a.summary.metrics[key].value) - float(b.summary.metrics[key].value)))
	check(second.code == 0 and identical and worst == 0.0, "reproducible: the same command twice gives the same %d metrics exactly (worst difference %.6f)" % [(a.get("summary", {}).get("metrics", {}) as Dictionary).size(), worst])
	check(identical and (a.findings as Array).map(func(f: Dictionary) -> String: return String(f.key)) == (b.findings as Array).map(func(f: Dictionary) -> String: return String(f.key)), "and the same findings under the same keys")

	var inspected := _adda(["inspect", "--report=%s" % ProjectSettings.globalize_path(a_path), "--finding=F1"], false)
	check(inspected.code == 0 and String(inspected.text).contains("Observed:") and String(inspected.text).contains("Does not establish") and String(inspected.text).contains("Reproduce:") and String(inspected.text).contains("row "), "inspect: a finding in full, with what it does not establish, how to reproduce it and the recorded rows around it")
	var unknown := _adda(["inspect", "--report=%s" % ProjectSettings.globalize_path(a_path), "--finding=F999"], false)
	check(unknown.code == 2, "an unknown finding is a usage error (exit %d)" % unknown.code)
	check(_adda(["inspect", "--report=%s" % ProjectSettings.globalize_path("%s/missing.json" % folder)], false).code == 2, "so is a missing report")

	var same := _adda(["compare", "--a=%s" % ProjectSettings.globalize_path(a_path), "--b=%s" % ProjectSettings.globalize_path(b_path), "--fail-on=regression"], false)
	check(same.code == 0 and String(same.text).contains("VERDICT: UNCHANGED"), "compare: two identical runs are UNCHANGED and exit 0 under --fail-on=regression")

	var unarmed := _adda(["run", "--scenario=contacts", "--unarmed", "--fps=60", "--out=%s" % unarmed_path])
	var small := _adda(["run", "--scenario=contacts", "--character=small_mira_0", "--fps=60", "--out=%s" % small_path])
	check(unarmed.code == 0 and small.code == 0 and not _load(unarmed_path).is_empty() and not _load(small_path).is_empty(), "run: unarmed and Small MIRA runs write reports")
	var armed_vs_unarmed := _adda(["compare", "--a=%s" % ProjectSettings.globalize_path(a_path), "--b=%s" % ProjectSettings.globalize_path(unarmed_path)], false)
	check(armed_vs_unarmed.code == 0 and String(armed_vs_unarmed.text).contains("Armed state differs"), "compare: armed against unarmed says it is an experiment")
	var bodies := _adda(["compare", "--a=%s" % ProjectSettings.globalize_path(a_path), "--b=%s" % ProjectSettings.globalize_path(small_path)], false)
	check(bodies.code == 0 and String(bodies.text).contains("body size"), "compare: MIRA against Small MIRA says the lengths were normalised by body size")

	# A regression and an improvement, made by editing a copy of A: a foot error ten times larger, and one ten times smaller.
	var worse := a.duplicate(true)
	var better := a.duplicate(true)
	for key in worse.summary.metrics:
		if String(key).ends_with("worst_error_mm") and String(key).begins_with("foot"):
			worse.summary.metrics[key].value = float(worse.summary.metrics[key].value) * 10.0 + 20.0
			better.summary.metrics[key].value = float(better.summary.metrics[key].value) / 10.0
	AddaReport.save(worse, "%s/worse.json" % folder)
	AddaReport.save(better, "%s/better.json" % folder)
	var regression := _adda(["compare", "--a=%s" % ProjectSettings.globalize_path(a_path), "--b=%s" % ProjectSettings.globalize_path("%s/worse.json" % folder), "--fail-on=regression"], false)
	check(regression.code == 1 and String(regression.text).contains("REGRESSED"), "a regression exits 1 under --fail-on=regression and says REGRESSED (exit %d)" % regression.code)
	var improvement := _adda(["compare", "--a=%s" % ProjectSettings.globalize_path(a_path), "--b=%s" % ProjectSettings.globalize_path("%s/better.json" % folder), "--fail-on=regression"], false)
	check(improvement.code == 0 and String(improvement.text).contains("IMPROVED") or String(improvement.text).contains("UNCHANGED"), "an improvement does not fail the gate (exit %d)" % improvement.code)

	var refused := _adda(["run", "--scenario=tactical", "--unarmed", "--out=%s/refused.json" % folder])
	check(refused.code == 2 and String(refused.text).contains("needs a weapon") and not FileAccess.file_exists("%s/refused.json" % folder), "refusal: tactical with no weapon exits 2, says it needs a weapon, and writes no report")
	check(_adda(["run", "--scenario=nonsense"]).code == 2, "an unknown scenario exits 2")

	# Passivity: the same fixed-rate run with no recorder, with the recorder, and with the recorder and the leg-vertex sampler.
	var plain := _engine("res://tools/quality/adda_passivity_probe.gd", [])
	var recorded := _engine("res://tools/quality/adda_passivity_probe.gd", ["--record"])
	var meshed := _engine("res://tools/quality/adda_passivity_probe.gd", ["--record", "--mesh"])
	var nudged := _engine("res://tools/quality/adda_passivity_probe.gd", ["--perturb"])
	var hashes := []
	for run in [plain, recorded, meshed]:
		for line in String(run.text).split("\n"):
			if line.begins_with("POSEHASH"):
				hashes.append(line.split(" ROWS")[0])
	check(hashes.size() == 3 and hashes[0] == hashes[1] and hashes[1] == hashes[2], "passive: every final pose of hips, wrists and ankles is bit-identical with no recorder, with it, and with leg-vertex sampling (%s)" % [hashes])
	var nudged_hash := ""
	for line in String(nudged.text).split("
"):
		if line.begins_with("POSEHASH"):
			nudged_hash = line.split(" ROWS")[0]
	check(nudged_hash != "" and hashes.size() == 3 and nudged_hash != hashes[0], "negative control: a 1 mm nudge of the body changes the hash, so equal hashes mean something (%s against %s)" % [nudged_hash, hashes[0] if hashes.size() > 0 else ""])
	check(String(recorded.text).contains("ROWS 7") or String(recorded.text).contains("ROWS 8") or String(recorded.text).contains("ROWS 9"), "(and the recorder did record: %s)" % [String(recorded.text).split("\n")[-2] if String(recorded.text).split("\n").size() > 1 else ""])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("adda_cli_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
