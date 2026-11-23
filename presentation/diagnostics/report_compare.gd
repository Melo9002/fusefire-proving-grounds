class_name ReportCompare
extends RefCounted
## Compares two ADDA reports (AddaReport) and says, metric by metric, whether B improved on A, regressed, did not change beyond the measurement's noise, or CANNOT BE COMPARED and why. The point is that a number from
## two runs is only comparable when the runs measured the same thing the same way:
##   scenario     different scenarios exercise different motion: nothing is compared
##   body size    a length (mm, cm) from a different-sized body is divided by that body's `body_ratio` first; the result says it was
##   frame rate   a metric tagged "frame_rate" (a snap's speed, a count of snaps) changes with the step: refused when the steps differ by more than 5%
##   unit, kind   a metric whose unit changed is refused
##   missing      a metric one report did not measure is MISSING for that side, never zero
## Armed against unarmed is a legitimate experiment, so it is compared and noted, not refused. The result is plain data; `text()` is the readable form.

const FPS_TOLERANCE := 0.05
const SIZE_TOLERANCE := 0.01

static func compare(a: Dictionary, b: Dictionary) -> Dictionary:
	var result := {"format": "adda.comparison", "version": 1, "comparable": true, "reason": "", "verdict": "UNCHANGED", "differences": {}, "notes": [], "metrics": [], "findings": {"new": [], "resolved": [], "persisting": []},
		"counts": {"improved": 0, "regressed": 0, "unchanged": 0, "incomparable": 0, "missing": 0, "info": 0}}
	for report in [a, b]:
		if String(report.get("format", "")) != AddaReport.FORMAT:
			result.comparable = false
			result.reason = "not an ADDA report"
			result.verdict = "INCOMPARABLE"
			return result
	if int(a.version) != int(b.version):
		result.comparable = false
		result.reason = "report versions differ (%d against %d)" % [int(a.version), int(b.version)]
		result.verdict = "INCOMPARABLE"
		return result
	var ca: Dictionary = a.config
	var cb: Dictionary = b.config
	for key in ["scenario", "character", "armed", "fps", "mesh_sampling", "engine"]:
		if ca.get(key) != cb.get(key):
			result.differences[key] = {"a": ca.get(key), "b": cb.get(key)}
	var rev_a: Dictionary = ca.get("revision", {})
	var rev_b: Dictionary = cb.get("revision", {})
	result.differences["revision"] = {"a": "%s%s" % [rev_a.get("commit", "?"), "+dirty" if rev_a.get("dirty", false) else ""], "b": "%s%s" % [rev_b.get("commit", "?"), "+dirty" if rev_b.get("dirty", false) else ""]}
	if ca.get("scenario") != cb.get("scenario"):
		result.comparable = false
		result.reason = "different scenarios (%s and %s) exercise different motion, so no metric is compared" % [ca.get("scenario"), cb.get("scenario")]
		result.verdict = "INCOMPARABLE"
		return result
	var ratio_a := maxf(float(ca.get("body_ratio", 1.0)), 0.0001)
	var ratio_b := maxf(float(cb.get("body_ratio", 1.0)), 0.0001)
	var size_differs := absf(ratio_a - ratio_b) / ratio_a > SIZE_TOLERANCE
	var dt_a := float(ca.get("frame_dt_s", 0.0))
	var dt_b := float(cb.get("frame_dt_s", 0.0))
	var rate_differs := dt_a <= 0.0 or dt_b <= 0.0 or absf(dt_a - dt_b) / dt_a > FPS_TOLERANCE
	if size_differs:
		result.notes.append("Different body size (ratio %.3f against %.3f): lengths are compared after dividing by each body's ratio." % [ratio_a, ratio_b])
	if rate_differs:
		result.notes.append("Different frame rate (%.1f against %.1f fps): metrics tagged frame_rate are not compared." % [float(ca.get("fps", 0.0)), float(cb.get("fps", 0.0))])
	if ca.get("armed") != cb.get("armed"):
		result.notes.append("Armed state differs (%s against %s): compared as an experiment, not a regression test." % [ca.get("armed"), cb.get("armed")])
	if ca.get("engine") != cb.get("engine"):
		result.notes.append("Different engine builds (%s against %s)." % [ca.get("engine"), cb.get("engine")])
	var ma: Dictionary = a.summary.metrics
	var mb: Dictionary = b.summary.metrics
	var keys := []
	for key in ma:
		keys.append(key)
	for key in mb:
		if not keys.has(key):
			keys.append(key)
	keys.sort()
	for key in keys:
		var row := _metric(String(key), ma.get(key), mb.get(key), size_differs, ratio_a, ratio_b, rate_differs)
		result.metrics.append(row)
		var bucket := String(row.verdict).to_lower()
		result.counts[bucket] = int(result.counts.get(bucket, 0)) + 1
	_findings(a, b, result)
	var regressed := int(result.counts.regressed) > 0 or _new_serious(result)
	var improved := int(result.counts.improved) > 0 or not (result.findings.resolved as Array).is_empty()
	result.verdict = "REGRESSED" if regressed and not improved else ("MIXED" if regressed and improved else ("IMPROVED" if improved else "UNCHANGED"))
	return result

static func _metric(key: String, ma: Variant, mb: Variant, size_differs: bool, ratio_a: float, ratio_b: float, rate_differs: bool) -> Dictionary:
	var row := {"key": key, "label": "", "unit": "", "a": null, "b": null, "delta": null, "verdict": "UNCHANGED", "reason": ""}
	var any: Dictionary = ma if ma != null else mb
	row.label = String(any.get("label", key))
	row.unit = String(any.get("unit", ""))
	if ma == null or mb == null:
		row.verdict = "MISSING"
		row.reason = "not measured in %s" % ("A" if ma == null else "B")
		row.a = ma.value if ma != null else null
		row.b = mb.value if mb != null else null
		return row
	if String(ma.unit) != String(mb.unit):
		row.verdict = "INCOMPARABLE"
		row.reason = "unit changed (%s against %s)" % [ma.unit, mb.unit]
		return row
	var tags: Array = ma.get("tags", [])
	if tags.has("frame_rate") and rate_differs:
		row.verdict = "INCOMPARABLE"
		row.reason = "depends on the frame step, which differs between the runs"
		row.a = ma.value
		row.b = mb.value
		return row
	var va := float(ma.value)
	var vb := float(mb.value)
	var noise := float(ma.get("noise", 0.0))
	if tags.has("length") and size_differs:
		va /= ratio_a
		vb /= ratio_b
		noise /= ratio_a
		row.unit = "%s per body ratio" % row.unit
	row.a = snappedf(va, 0.0001)
	row.b = snappedf(vb, 0.0001)
	row.delta = snappedf(vb - va, 0.0001)
	if absf(vb - va) <= noise:
		row.verdict = "UNCHANGED"
		row.reason = "within the measurement's noise (%s)" % str(snappedf(noise, 0.0001))
		return row
	match String(ma.get("better", "none")):
		"lower":
			row.verdict = "IMPROVED" if vb < va else "REGRESSED"
		"higher":
			row.verdict = "IMPROVED" if vb > va else "REGRESSED"
		_:
			row.verdict = "INFO"
			row.reason = "changed; this metric has no better direction"
	return row

static func _findings(a: Dictionary, b: Dictionary, result: Dictionary) -> void:
	var fa := {}
	var fb := {}
	for f: Dictionary in a.get("findings", []):
		fa[String(f.key)] = f
	for f: Dictionary in b.get("findings", []):
		fb[String(f.key)] = f
	for key in fb:
		if not fa.has(key):
			(result.findings.new as Array).append({"key": key, "severity": fb[key].severity, "title": fb[key].title})
		else:
			(result.findings.persisting as Array).append({"key": key, "severity": fb[key].severity, "title": fb[key].title})
	for key in fa:
		if not fb.has(key):
			(result.findings.resolved as Array).append({"key": key, "severity": fa[key].severity, "title": fa[key].title})

static func _new_serious(result: Dictionary) -> bool:
	for f: Dictionary in result.findings.new:
		if String(f.severity) in ["high", "medium"]:
			return true
	return false

static func text(result: Dictionary) -> String:
	var lines: Array[String] = []
	if not bool(result.comparable):
		return "NOT COMPARABLE: %s" % result.reason
	lines.append("VERDICT: %s   (improved %d, regressed %d, unchanged %d, not comparable %d, missing %d)" % [result.verdict, result.counts.improved, result.counts.regressed, result.counts.unchanged, result.counts.incomparable, result.counts.missing])
	for key in result.differences:
		var d: Dictionary = result.differences[key]
		if d.a != d.b:
			lines.append("  differs: %s: %s -> %s" % [key, str(d.a), str(d.b)])
	for note in result.notes:
		lines.append("  note: %s" % note)
	for row: Dictionary in result.metrics:
		if row.verdict == "UNCHANGED":
			continue
		var values := "" if row.a == null and row.b == null else "  %s -> %s %s" % [str(row.a), str(row.b), row.unit]
		lines.append("  %-12s %s%s%s" % [row.verdict, row.label, values, ("   (%s)" % row.reason) if row.reason != "" else ""])
	for f: Dictionary in result.findings.new:
		lines.append("  NEW FINDING [%s] %s" % [f.severity, f.title])
	for f: Dictionary in result.findings.resolved:
		lines.append("  RESOLVED     [%s] %s" % [f.severity, f.title])
	return "\n".join(lines)
