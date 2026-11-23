extends SceneTree
## ADDA's diagnostic challenges, end to end through the command line an agent uses: six scenarios with an injected fault of KNOWN cause (tools/adda/challenges), run against a fault-free baseline, with the same steps an
## investigator would take (compare, isolate, experiment, score). This test is a SCRIPTED solver that knows the answer; it proves the evidence is there to be found, not that an agent will find it (see the challenge
## write-up for what was and was not independently attempted).
##   CH01 right hand moved 50 mm after HandGrip       compare shows a NEW finding; isolation names the undeclared modifier and 50 mm; the baseline's isolation names none
##   CH02 hips turned 25 degrees after CoverCrouch    isolation finds it by its ANGLE (the hips origin does not move)
##   CH03 right knee pops 120 mm one update in 70     isolation sees it only with a window; switching the modifier off (--disable) returns the run to the baseline EXACTLY
##   CH04 left foot creeps 10 mm/s after TraversalFoot  compare shows a new "off its foothold" finding (the finding added for this challenge); isolation names the modifier
##   CH05 head 67 mm off, nothing reported            a KNOWN BLIND SPOT: compare says unchanged (no tracked target, no snap), isolation finds it once the head is asked about
##   CH06 control, no fault                           compare says unchanged and isolation names no undeclared modifier
## It runs about thirty engine processes (several minutes).
var failures := 0
var checks := 0
var _exe := OS.get_executable_path()
var _project := ProjectSettings.globalize_path("res://")
const FOLDER := "user://adda_challenge_test"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _adda(args: Array) -> Dictionary:
	var arguments: Array = ["--headless", "--fixed-fps", "60", "--path", _project, "--script", "res://tools/adda/adda.gd", "--"]
	arguments.append_array(args)
	var output := []
	var code := OS.execute(_exe, arguments, output, true)
	return {"code": code, "text": "\n".join(output)}

func _path(name: String) -> String:
	return "%s/%s.json" % [FOLDER, name]

func _config(scenario: String, character: String, armed: bool) -> Array:
	return ["--scenario=%s" % scenario, "--character=%s" % character] + ([] if armed else ["--unarmed"])

## Baseline run and fault run of one challenge, compared. Returns {compare: text, code}.
func _compare(entry: Dictionary, id: String) -> Dictionary:
	var config := _config(entry.scenario, entry.character, entry.armed)
	var base := _path("base-%s-%s-%s" % [entry.scenario, entry.character, entry.armed])
	if not FileAccess.file_exists(base):
		_adda(["run"] + config + ["--out=%s" % base])
	var run := _adda(["run"] + config + ["--challenge=%s" % id, "--out=%s" % _path(id)])
	var compared := _adda(["compare", "--a=%s" % base, "--b=%s" % _path(id), "--fail-on=regression"])
	compared["run_code"] = run.code
	return compared

func _isolate(entry: Dictionary, id: String, at: String, bones: String, extra := []) -> Dictionary:
	var config := _config(entry.scenario, entry.character, entry.armed)
	var arguments: Array = ["isolate"] + config + ["--at=%s" % at, "--bones=%s" % bones]
	if id != "":
		arguments.append("--challenge=%s" % id)
	arguments.append_array(extra)
	return _adda(arguments)

func _line(text: String, needle: String) -> String:
	for line in text.split("
"):
		if line.contains(needle):
			return line.strip_edges()
	return ""

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var listed := _adda(["challenges"])
	var entries := {}
	for entry: Dictionary in ChallengeSet.index():
		entries[String(entry.id)] = entry
	check(listed.code == 0 and entries.size() >= 6 and String(listed.text).contains("CH01") and not String(listed.text).contains("AuxPass"), "the index lists six challenges and prints symptoms only, never the injected modifier (exit %d, %d entries)" % [listed.code, entries.size()])
	for id in entries:
		check(not String(entries[id].symptom).contains("AuxPass") and not String(entries[id].symptom).contains("offset") and not entries[id].has("fault"), "%s: the public entry holds no answer" % id)

	# CH01 -------------------------------------------------------------------------------------------------
	var c1: Dictionary = entries.CH01
	var compared := _compare(c1, "CH01")
	check(compared.run_code == 0 and compared.code == 1 and String(compared.text).contains("NEW FINDING"), "CH01: compared with the fault-free baseline the run has a NEW finding and a regression exit (code %d)" % compared.code)
	var iso := _isolate(c1, "CH01", "3.5", "@right_hand,@right_elbow")
	check(iso.code == 0 and String(iso.text).contains("AuxPass1") and String(iso.text).contains("NOT declared") and String(iso.text).contains("50.0 mm"), "CH01: isolation names the undeclared modifier and its 50.0 mm on the hand")
	var iso_base := _isolate(c1, "", "3.5", "@right_hand,@right_elbow")
	check(iso_base.code == 0 and not String(iso_base.text).contains("NOT declared"), "CH01 control: the same isolation on the fault-free run names no undeclared modifier")
	var right := _adda(["score", "--challenge=CH01", "--stage=AuxPass1", "--bone=@right_hand", "--kind=offset"])
	var wrong := _adda(["score", "--challenge=CH01", "--stage=WeaponArmIK", "--bone=@right_hand", "--kind=offset"])
	check(right.code == 0 and String(right.text).contains("CORRECT") and wrong.code == 1 and String(wrong.text).contains("stage: does not match"), "CH01: scoring accepts the right answer and says which part of a wrong one fails")

	# CH02 -------------------------------------------------------------------------------------------------
	var c2: Dictionary = entries.CH02
	var compared2 := _compare(c2, "CH02")
	check(compared2.run_code == 0 and not String(compared2.text).contains("VERDICT: UNCHANGED"), "CH02: the facing fault is noticed as a change of the run (verdict is not UNCHANGED): %s" % String(compared2.text).split("\n")[0])
	var iso2 := _isolate(c2, "CH02", "6.0", "@hips")
	check(String(iso2.text).contains("AuxPass2") and String(iso2.text).contains("turns 25.0 deg") and not _line(iso2.text, "AuxPass2").contains("moves"), "CH02: isolation finds it by its 25.0 degree turn, not by a movement of the hips: %s" % _line(iso2.text, "AuxPass2"))

	# CH03 -------------------------------------------------------------------------------------------------
	var c3: Dictionary = entries.CH03
	var compared3 := _compare(c3, "CH03")
	check(compared3.run_code == 0 and compared3.code == 1, "CH03: the run regresses against the baseline (exit %d)" % compared3.code)
	var narrow := _isolate(c3, "CH03", "3.0", "@right_knee,@left_knee")
	var wide := _isolate(c3, "CH03", "3.0", "@right_knee,@left_knee", ["--window=150"])
	check(String(wide.text).contains("AuxPass3") and String(wide.text).contains("intermittent") and String(wide.text).contains("120.0 mm"), "CH03: with a window of 150 updates isolation finds the modifier as an intermittent 120.0 mm spike")
	check(not String(narrow.text).contains("AuxPass3 "), "CH03: with one update per condition it does not claim to have seen it (a pop that is not firing cannot be attributed)")
	var off := _adda(["run"] + _config(c3.scenario, c3.character, c3.armed) + ["--challenge=CH03", "--disable=AuxPass3", "--out=%s" % _path("CH03-off")])
	var base3 := _path("base-%s-%s-%s" % [c3.scenario, c3.character, c3.armed])
	var back := _adda(["compare", "--a=%s" % base3, "--b=%s" % _path("CH03-off"), "--fail-on=regression"])
	check(off.code == 0 and back.code == 0 and String(back.text).contains("VERDICT: UNCHANGED"), "CH03: switching the modifier off with --disable returns the run to the baseline (verdict %s)" % String(back.text).split("\n")[0])
	var loaded := AddaReport.load_file(_path("CH03-off"))
	check(bool(loaded.ok) and (loaded.report.config.experiment as Array).size() == 1 and String(loaded.report.config.experiment[0]).contains("disabled AuxPass3"), "and the report says it was an experiment: %s" % [loaded.report.config.get("experiment", []) if bool(loaded.ok) else "unreadable"])
	check(bool(loaded.ok) and String(loaded.report.config.cli).contains("--challenge=CH03") and String(loaded.report.config.cli).contains("--disable=AuxPass3"), "and its reproduction command carries the levers (%s)" % [String(loaded.report.config.cli).get_slice("--", 2) if bool(loaded.ok) else ""])
	var missing := _adda(["run", "--scenario=landing", "--disable=NotAModifier"])
	check(missing.code == 2 and String(missing.text).contains("no modifier named"), "an experiment naming a modifier that does not exist is a usage error, not silently ignored")

	# --set: a property of a node under the rig, and the refusals.
	var bad_node := _adda(["run", "--scenario=rescue", "--set=Nope.x=1"])
	var bad_property := _adda(["run", "--scenario=rescue", "--set=.no_such_property=1"])
	check(bad_node.code == 2 and String(bad_node.text).contains("no node 'Nope'") and bad_property.code == 2 and String(bad_property.text).contains("has no property"), "--set naming a node or a property that does not exist is a usage error (exit %d and %d)" % [bad_node.code, bad_property.code])
	var no_contacts := _adda(["run", "--scenario=rescue", "--set=.carry_contacts_enabled=false", "--out=%s" % _path("rescue-no-contacts")])
	var rescue_base := _adda(["run", "--scenario=rescue", "--out=%s" % _path("rescue-base")])
	var rescue_a := AddaReport.load_file(_path("rescue-base"))
	var rescue_b := AddaReport.load_file(_path("rescue-no-contacts"))
	var out_of_reach := func(report: Dictionary) -> int:
		return (report.findings as Array).filter(func(f: Dictionary) -> bool: return String(f.kind) == "reach_exceeded").size()
	check(no_contacts.code == 0 and rescue_base.code == 0 and bool(rescue_a.ok) and bool(rescue_b.ok) and out_of_reach.call(rescue_a.report) > 0 and out_of_reach.call(rescue_b.report) == 0, "--set=.carry_contacts_enabled=false: the rescue's out-of-reach findings (%d) are gone when the carry contacts are not claimed (%d): the claim, not the hand IK, is what they were about" % [out_of_reach.call(rescue_a.report) if bool(rescue_a.ok) else -1, out_of_reach.call(rescue_b.report) if bool(rescue_b.ok) else -1])
	check(bool(rescue_b.ok) and String(rescue_b.report.config.experiment[0]).contains("set .carry_contacts_enabled = false"), "and the report says what was set: %s" % [rescue_b.report.config.experiment if bool(rescue_b.ok) else "unreadable"])

	# CH04 -------------------------------------------------------------------------------------------------
	var c4: Dictionary = entries.CH04
	var compared4 := _compare(c4, "CH04")
	check(compared4.run_code == 0 and String(compared4.text).contains("NEW FINDING") and String(compared4.text).contains("off its foothold"), "CH04: the slow drift shows up as a new 'off its foothold' finding (it showed only as a metric before this challenge)")
	var iso4 := _isolate(c4, "CH04", "4.0", "@left_foot")
	check(String(iso4.text).contains("AuxPass4") and String(iso4.text).contains("NOT declared"), "CH04: isolation names the undeclared modifier")
	check(String(iso4.text).contains("INCONCLUSIVE"), "CH04: and says the pose is still changing while it measured (the creep is real motion, so the sizes are approximate)")

	# CH05 -------------------------------------------------------------------------------------------------
	var c5: Dictionary = entries.CH05
	var compared5 := _compare(c5, "CH05")
	check(compared5.run_code == 0 and String(compared5.text).contains("VERDICT: UNCHANGED"), "CH05: a constant offset of an untracked bone is NOT noticed by compare: %s (known blind spot, documented)" % String(compared5.text).split("\n")[0])
	var iso5 := _isolate(c5, "CH05", "5.0", "@head")
	check(String(iso5.text).contains("AuxPass5") and String(iso5.text).contains("67.1 mm"), "CH05: asked about the head, isolation finds the modifier and 67.1 mm")

	# CH06 -------------------------------------------------------------------------------------------------
	var c6: Dictionary = entries.CH06
	var compared6 := _compare(c6, "CH06")
	check(compared6.run_code == 0 and compared6.code == 0 and String(compared6.text).contains("VERDICT: UNCHANGED") and not String(compared6.text).contains("NEW FINDING"), "CH06 control: no fault gives UNCHANGED and no new finding")
	var iso6 := _isolate(c6, "CH06", "4.0", "@left_foot,@right_foot")
	check(String(iso6.text).contains("No modifier moved"), "CH06 control: isolation names no modifier")
	var none := _adda(["score", "--challenge=CH06", "--stage=none", "--kind=none"])
	check(none.code == 0, "CH06: 'there is no fault' is a scorable answer")
	# Hold-out challenges: their answers are only in sealed/, never in this file. The scripted solver reads the hint for each from the sealed file and checks the evidence is there, so a hold-out is known to be solvable.
	for id in entries:
		if not bool(entries[id].get("holdout", false)):
			continue
		var sealed = JSON.parse_string(FileAccess.get_file_as_string("res://tools/adda/challenges/sealed/%s.json" % id))
		var solve: Dictionary = sealed.solve
		var extra := ["--window=%s" % solve.window] if solve.has("window") else []
		var found := _isolate(entries[id], id, String(solve.at), String(solve.bones), extra)
		check(found.code == 0 and String(found.text).contains(String(sealed.answer.stage)) and String(found.text).contains("NOT declared"), "%s (hold-out): the evidence for the sealed answer is there to be found" % id)
		var control := _isolate(entries[id], "", String(solve.at), String(solve.bones), extra)
		check(control.code == 0 and not String(control.text).contains("NOT declared"), "%s (hold-out) control: the fault-free run names no undeclared modifier" % id)
		check(_adda(["score", "--challenge=%s" % id, "--stage=%s" % sealed.answer.stage, "--bone=%s" % sealed.answer.bone, "--kind=%s" % sealed.answer.kind]).code == 0, "%s (hold-out): its sealed answer scores correct" % id)
	print("adda_challenge_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
