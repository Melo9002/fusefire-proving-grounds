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
	var result := {"format": "adda.comparison", "version": 1, "comparable": true, "reason": "", "verdict": "UNCHANGED", "differences": {}, "notes": [], "metrics": [], "findings": {"new": [], "resolved": [], "persisting": [], "changed": [], "unverifiable": []},
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

## Findings are matched by their stable key. A finding on one side only is NEW or RESOLVED only when the other run could have shown it; otherwise it is UNVERIFIABLE (the other run did not sample the leg vertices, or ran at
## a frame rate where a snap is not comparable) and says why. `not_measured` notes are not findings about the motion and are left out.
static func _findings(a: Dictionary, b: Dictionary, result: Dictionary) -> void:
	var fa := {}
	var fb := {}
	for f: Dictionary in a.get("findings", []):
		if String(f.kind) != "not_measured":
			fa[String(f.key)] = f
	for f: Dictionary in b.get("findings", []):
		if String(f.kind) != "not_measured":
			fb[String(f.key)] = f
	var rate_differs := _rate_differs(a.config, b.config)
	# A snap whose grouping changed (a fix that stops the legs jumping turns "6 bones" into "4 bones" with a different worst bone) has a different key but is the same moment: pair it with the
	# unmatched snap of the other run at that moment and report it CHANGED, not NEW and RESOLVED (issue 72).
	var paired := _pair_snaps_by_moment(fa, fb)
	for key in fb:
		if paired.has(key):
			var was: Dictionary = fa[paired[key]]
			(result.findings.changed as Array).append({"key": key, "was_key": paired[key], "severity": fb[key].severity, "was_severity": was.severity, "title": fb[key].title, "was_title": was.title})
			continue
		var entry := {"key": key, "severity": fb[key].severity, "title": fb[key].title}
		if fa.has(key):
			(result.findings.persisting as Array).append(entry)
		else:
			var why := _unverifiable(fb[key], a.config, "A", rate_differs)
			if why != "":
				entry["reason"] = why
				(result.findings.unverifiable as Array).append(entry)
			else:
				(result.findings.new as Array).append(entry)
	for key in fa:
		if not fb.has(key) and not paired.values().has(key):
			var entry := {"key": key, "severity": fa[key].severity, "title": fa[key].title}
			var why := _unverifiable(fa[key], b.config, "B", rate_differs)
			if why != "":
				entry["reason"] = why
				(result.findings.unverifiable as Array).append(entry)
			else:
				(result.findings.resolved as Array).append(entry)

## Tolerance, in recorder rows, for two snaps to be the same moment.
const SNAP_MOMENT_ROWS := 2

## Pairs the pose snaps present in only ONE run's key set when they happen at the same moment (one-to-one, nearest first). Returns {key in B: key in A}.
static func _pair_snaps_by_moment(fa: Dictionary, fb: Dictionary) -> Dictionary:
	var paired := {}
	var taken := {}
	for key_b in fb:
		if fa.has(key_b) or String(fb[key_b].kind) != "pose_snap":
			continue
		var best := ""
		var best_gap := SNAP_MOMENT_ROWS + 1
		for key_a in fa:
			if fb.has(key_a) or taken.has(key_a) or String(fa[key_a].kind) != "pose_snap":
				continue
			var gap := _moment_gap(fa[key_a], fb[key_b])
			if gap < best_gap:
				best_gap = gap
				best = key_a
		if best != "":
			paired[key_b] = best
			taken[best] = true
	return paired

## The smallest distance, in rows, between any moment of one finding and any of the other (its worst frame and every listed occurrence). Large when a finding carries no frame.
static func _moment_gap(x: Dictionary, y: Dictionary) -> int:
	var gap := 1000000
	for mx in _moments(x):
		for my in _moments(y):
			gap = mini(gap, absi(mx - my))
	return gap

static func _moments(finding: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var observation: Dictionary = finding.get("observation", {})
	var frames: Dictionary = observation.get("frames", {})
	if frames.has("worst_n"):
		out.append(int(frames.worst_n))
	for o: Dictionary in observation.get("facts", {}).get("occurrences", []):
		out.append(int(o.n))
	return out

static func _rate_differs(ca: Dictionary, cb: Dictionary) -> bool:
	var dt_a := float(ca.get("frame_dt_s", 0.0))
	var dt_b := float(cb.get("frame_dt_s", 0.0))
	return dt_a <= 0.0 or dt_b <= 0.0 or absf(dt_a - dt_b) / dt_a > FPS_TOLERANCE

## Why a finding seen in ONE run cannot be called new or resolved: what the OTHER run (`other`) could not have shown. "" when it could.
static func _unverifiable(finding: Dictionary, other_config: Dictionary, other: String, rate_differs: bool) -> String:
	if String(finding.kind) == "mesh_overlap" and not bool(other_config.get("mesh_sampling", false)):
		return "run %s did not sample the leg vertices" % other
	if String(finding.kind) == "pose_snap" and rate_differs:
		return "a snap depends on the frame step, which differs between the runs"
	return ""

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
	for f: Dictionary in result.findings.changed:
		lines.append("  CHANGED      [%s] %s   (was: [%s] %s; same moment, grouped differently)" % [f.severity, f.title, f.was_severity, f.was_title])
	for f: Dictionary in result.findings.resolved:
		lines.append("  RESOLVED     [%s] %s" % [f.severity, f.title])
	for f: Dictionary in result.findings.unverifiable:
		lines.append("  UNVERIFIABLE [%s] %s   (%s)" % [f.severity, f.title, f.reason])
	return "\n".join(lines)
