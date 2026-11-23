extends SceneTree
## ADDA report comparison and the report file format, against hand-made reports whose answer is known. The comparison must report improvements, regressions and NOTHING when the change is inside the noise, and it
## must REFUSE to compare what cannot validly be compared (different scenario, different frame step for a frame-rate-dependent metric, a missing measurement) instead of printing a number.
##   1 verdicts        identical, improved, regressed, within noise
##   2 not comparable  other scenario, other report version, not an ADDA report
##   3 body size       lengths are divided by the body ratio; ratios and times are not
##   4 frame rate      a frame_rate metric is refused across steps, a time metric is not
##   5 missing         a metric one side did not measure is MISSING, never zero
##   6 findings        new and resolved findings are named, a serious new one is a regression even with equal metrics
##   7 format          jsonable rounds vectors, a wrong or newer report is refused on load, a saved report loads back identical
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_verdicts()
	_not_comparable()
	_body_size()
	_frame_rate()
	_missing()
	_findings()
	_format()
	print("adda_report_compare_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _metric(value: float, unit := "mm", better := "lower", tags := [], noise := 0.5) -> Dictionary:
	return {"value": value, "unit": unit, "better": better, "tags": tags, "noise": noise, "label": "test metric"}

func _report(metrics: Dictionary, config := {}, findings := []) -> Dictionary:
	var base := {"scenario": "contacts", "character": "mira_0", "armed": true, "fps": 60.0, "frame_dt_s": 0.016667, "body_ratio": 1.0, "mesh_sampling": false, "engine": "4.7.2", "revision": {"commit": "abc", "dirty": false}}
	base.merge(config, true)
	return {"format": AddaReport.FORMAT, "version": AddaReport.VERSION, "config": base, "summary": {"metrics": metrics, "headline": ""}, "findings": findings}

func _row(result: Dictionary, key: String) -> Dictionary:
	for row: Dictionary in result.metrics:
		if row.key == key:
			return row
	return {}

func _verdicts() -> void:
	var a := _report({"foot.error": _metric(20.0), "hand.error": _metric(5.0), "time.held": _metric(3.0, "s", "none", ["time"], 0.02)})
	var same := ReportCompare.compare(a, a.duplicate(true))
	check(same.comparable and same.verdict == "UNCHANGED" and int(same.counts.improved) == 0 and int(same.counts.regressed) == 0, "normal case: a report compared with itself is UNCHANGED")
	var better := ReportCompare.compare(a, _report({"foot.error": _metric(8.0), "hand.error": _metric(5.2), "time.held": _metric(3.0, "s", "none", ["time"], 0.02)}))
	check(_row(better, "foot.error").verdict == "IMPROVED" and better.verdict == "IMPROVED", "a foot error that fell from 20 to 8 mm is IMPROVED")
	check(_row(better, "hand.error").verdict == "UNCHANGED", "a change of 0.2 mm is inside the 0.5 mm noise and is NOT reported as a change")
	var worse := ReportCompare.compare(a, _report({"foot.error": _metric(20.0), "hand.error": _metric(9.0), "time.held": _metric(3.0, "s", "none", ["time"], 0.02)}))
	check(_row(worse, "hand.error").verdict == "REGRESSED" and worse.verdict == "REGRESSED", "a hand error that grew from 5 to 9 mm is REGRESSED, and the whole verdict says so")
	var mixed := ReportCompare.compare(a, _report({"foot.error": _metric(5.0), "hand.error": _metric(9.0), "time.held": _metric(3.0, "s", "none", ["time"], 0.02)}))
	check(mixed.verdict == "MIXED", "one metric better and one worse is MIXED, not averaged away")
	var info := ReportCompare.compare(a, _report({"foot.error": _metric(20.0), "hand.error": _metric(5.0), "time.held": _metric(5.0, "s", "none", ["time"], 0.02)}))
	check(_row(info, "time.held").verdict == "INFO" and info.verdict == "UNCHANGED", "a metric with no better direction is INFO: reported as changed, never as better or worse")
	check(ReportCompare.text(better).contains("IMPROVED") and ReportCompare.text(worse).contains("REGRESSED"), "the readable text names the verdicts")

func _not_comparable() -> void:
	var a := _report({"x": _metric(1.0)})
	var other := ReportCompare.compare(a, _report({"x": _metric(1.0)}, {"scenario": "landing"}))
	check(not other.comparable and other.verdict == "INCOMPARABLE" and (other.metrics as Array).is_empty() and String(other.reason).contains("different scenarios"), "different scenarios compare nothing, and the reason says why")
	check(ReportCompare.text(other).begins_with("NOT COMPARABLE"), "and the text leads with it")
	var newer := _report({"x": _metric(1.0)})
	newer["version"] = 2
	check(not ReportCompare.compare(a, newer).comparable, "different report versions are not compared")
	check(not ReportCompare.compare({"format": "something"}, a).comparable, "something that is not an ADDA report is refused")
	var armed := ReportCompare.compare(a, _report({"x": _metric(1.0)}, {"armed": false}))
	check(armed.comparable and (armed.notes as Array).any(func(n: String) -> bool: return n.contains("Armed state differs")), "armed against unarmed is a legitimate experiment: compared, and the difference is noted")

func _body_size() -> void:
	var a := _report({"foot.slide": _metric(20.0, "mm", "lower", ["length"], 1.0), "ratio.metric": _metric(4.0, "events", "lower", [], 0.0)})
	var small := _report({"foot.slide": _metric(15.0, "mm", "lower", ["length"], 1.0), "ratio.metric": _metric(4.0, "events", "lower", [], 0.0)}, {"character": "small_mira_0", "body_ratio": 0.75})
	var result := ReportCompare.compare(a, small)
	check(_row(result, "foot.slide").verdict == "UNCHANGED" and absf(float(_row(result, "foot.slide").b) - 20.0) < 0.01, "20 mm on a ratio-1 body and 15 mm on a 0.75-ratio body are the same slide once each is divided by its body ratio")
	check((result.notes as Array).any(func(n: String) -> bool: return n.contains("body size")), "and the note says the lengths were normalised")
	check(_row(result, "ratio.metric").verdict == "UNCHANGED", "a count is not a length: it is compared as it is")
	var worse := ReportCompare.compare(a, _report({"foot.slide": _metric(15.0, "mm", "lower", ["length"], 1.0), "ratio.metric": _metric(4.0, "events", "lower", [], 0.0)}))
	check(_row(worse, "foot.slide").verdict == "IMPROVED", "without normalisation (same body) 20 to 15 mm IS an improvement: the normalisation applies only to different bodies")

func _frame_rate() -> void:
	var a := _report({"snap.speed": _metric(8.0, "m/s", "lower", ["frame_rate"], 0.2), "held": _metric(3.0, "s", "none", ["time"], 0.02), "slide": _metric(10.0, "mm", "lower", ["length"], 1.0)})
	var slow := _report({"snap.speed": _metric(4.0, "m/s", "lower", ["frame_rate"], 0.2), "held": _metric(3.0, "s", "none", ["time"], 0.02), "slide": _metric(4.0, "mm", "lower", ["length"], 1.0)}, {"fps": 30.0, "frame_dt_s": 0.033333})
	var result := ReportCompare.compare(a, slow)
	check(_row(result, "snap.speed").verdict == "INCOMPARABLE" and String(_row(result, "snap.speed").reason).contains("frame step"), "a snap speed measured at 60 and 30 fps is refused, not reported as an improvement")
	check(_row(result, "slide").verdict == "IMPROVED" and _row(result, "held").verdict == "UNCHANGED", "a slide in millimetres and a time in seconds still compare across frame rates")
	check((result.notes as Array).any(func(n: String) -> bool: return n.contains("frame rate")), "and the note says why")
	var unknown_step := _report({"snap.speed": _metric(4.0, "m/s", "lower", ["frame_rate"], 0.2)}, {"frame_dt_s": 0.0})
	check(_row(ReportCompare.compare(a, unknown_step), "snap.speed").verdict == "INCOMPARABLE", "a report whose frame step is unknown cannot vouch for a frame-rate metric")

func _missing() -> void:
	var a := _report({"mesh.worst": _metric(12.0, "vertices", "lower", ["sampled"], 2.0), "foot.error": _metric(5.0)})
	var b := _report({"foot.error": _metric(5.0)})
	var result := ReportCompare.compare(a, b)
	check(_row(result, "mesh.worst").verdict == "MISSING" and String(_row(result, "mesh.worst").reason).contains("not measured in B") and _row(result, "mesh.worst").b == null, "a metric only A measured is MISSING in B, with no zero invented")
	check(int(result.counts.missing) == 1 and result.verdict == "UNCHANGED", "and it neither improves nor regresses the verdict")

func _finding(key: String, severity: String) -> Dictionary:
	return {"key": key, "severity": severity, "title": "finding %s" % key}

func _findings() -> void:
	var a := _report({"x": _metric(1.0)}, {}, [_finding("a", "high"), _finding("b", "medium")])
	var b := _report({"x": _metric(1.0)}, {}, [_finding("b", "medium"), _finding("c", "high")])
	var result := ReportCompare.compare(a, b)
	check((result.findings.new as Array).size() == 1 and result.findings.new[0].key == "c" and (result.findings.resolved as Array).size() == 1 and result.findings.resolved[0].key == "a" and (result.findings.persisting as Array).size() == 1, "findings are matched by their stable key: one new, one resolved, one persisting")
	check(result.verdict == "MIXED", "a new serious finding with a resolved one is MIXED")
	var regress := ReportCompare.compare(_report({"x": _metric(1.0)}), _report({"x": _metric(1.0)}, {}, [_finding("n", "high")]))
	check(regress.verdict == "REGRESSED", "a new high finding is a regression even when every metric is unchanged")
	var resolved := ReportCompare.compare(_report({"x": _metric(1.0)}, {}, [_finding("n", "high")]), _report({"x": _metric(1.0)}))
	check(resolved.verdict == "IMPROVED", "a resolved finding is an improvement")
	var note := ReportCompare.compare(_report({"x": _metric(1.0)}, {"revision": {"commit": "aaa", "dirty": false}}), _report({"x": _metric(1.0)}, {"revision": {"commit": "bbb", "dirty": true}}))
	check(note.differences.revision.a == "aaa" and note.differences.revision.b == "bbb+dirty", "the source revisions compared are reported, with the working-tree state")

func _format() -> void:
	var json: Dictionary = AddaReport.jsonable({"v": Vector3(1.23456789, 2.0, -0.00004), "list": [Vector3.ZERO, &"name"], "f": 0.123456789, "n": NAN, "i": 3})
	check(absf(float(json.v[0]) - 1.2346) < 0.00001 and float(json.v[2]) == 0.0 and (json.v as Array).size() == 3 and json.list[1] is String and absf(float(json.f) - 0.12346) < 0.000001 and json.n == null and json.i == 3, "jsonable: vectors become [x, y, z] to 0.1 mm, names strings, NaN null (%s)" % [JSON.stringify(json)])
	var report := _report({"x": _metric(1.5)})
	var path := "user://adda_test_report.json"
	check(AddaReport.save(report, path) == OK, "a report saves")
	var loaded := AddaReport.load_file(path)
	check(bool(loaded.ok) and loaded.report.summary.metrics.x.value == 1.5, "and loads back with the same numbers")
	var wrong := FileAccess.open("user://adda_test_wrong.json", FileAccess.WRITE)
	wrong.store_string('{"format": "something.else", "version": 1}')
	wrong.close()
	check(not bool(AddaReport.load_file("user://adda_test_wrong.json").ok), "a JSON file that is not an ADDA report is refused")
	var future := FileAccess.open("user://adda_test_future.json", FileAccess.WRITE)
	future.store_string('{"format": "%s", "version": 99}' % AddaReport.FORMAT)
	future.close()
	check(not bool(AddaReport.load_file("user://adda_test_future.json").ok) and String(AddaReport.load_file("user://adda_test_future.json").error).contains("newer"), "a report from a newer format version is refused, not guessed at")
	check(not bool(AddaReport.load_file("user://does_not_exist.json").ok), "a missing file is an error with a reason")
	for file in ["adda_test_report.json", "adda_test_wrong.json", "adda_test_future.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://%s" % file))
