class_name AddaReport
extends RefCounted
## ADDA's structured report: one JSON document that says what was run, on what, what was measured and how, what was found, and where to look next, so a person or a coding agent never has to infer anything from a
## screenshot. Built from a SessionRecorder's rows (SessionRecorder -> TimelineAnalysis -> Findings), versioned, with stable field names.
##
## Format "adda.report" version 1 (the keys an agent can rely on):
##   format, version
##   config       scenario, character, identity, armed, body_ratio, frame_dt_s, fps, rows, duration_s, mesh_sampling, engine, revision{commit, branch, dirty}, command (how to relaunch it), cli (the headless run)
##   summary      headline (one sentence), findings{high, medium, low, info}, counts (events by kind), metrics (the numbers a comparison uses: value, unit, better, tags, noise, label)
##   findings     the list from Findings (observation / hypotheses / cause unknown / subject / evidence / reproduce)
##   worst_frames [{finding, n, st}] where to look first
##   events       every event TimelineAnalysis found (compact); markers the host named (scenario steps)
##   samples      the recorded rows around each worst frame (all rows with detail "full", a row window with `window`), positions as [x, y, z] metres
##   instruments  what each kind of measurement establishes and does not (Measurement.MEANING), whether it was taken, and what was left out
##   limitations  what this report cannot say
## Spaces: bones in `samples` are in the character's frame (x left, y up, z forward); root, targets, wrists and ankles are world. Units: metres, seconds, millimetres or centimetres as the field says.
## Unavailable measurements are listed in `instruments` and in findings of kind "not_measured": silence never means "fine".

const FORMAT := "adda.report"
const VERSION := 1
const CONTEXT_ROWS := 2

## `options`: scenario (String), character (key), command (relaunch line), cli (headless line), detail ("summary" | "full"), window ([n0, n1] rows to include in full).
static func build(recorder: SessionRecorder, options := {}) -> Dictionary:
	var rows: Array = recorder.rows
	var rig: CharacterRig = recorder.rig
	var analysis := TimelineAnalysis.analyze(rows)
	var description := recorder.describe()
	var names := {}
	if not rows.is_empty():
		for bone in (rows[0].bones as Dictionary):
			names[String(bone)] = String(BodyParts.describe(rig, String(bone)).text)
	var config := {"scenario": String(options.get("scenario", "")), "character": String(options.get("character", "")), "identity": Measurement.identity_of(rig),
		"armed": rig.has_weapon(), "body_ratio": snappedf(rig.body_ratio(), 0.0001), "frame_dt_s": description.frame_dt_s, "fps": snappedf(1.0 / float(description.frame_dt_s), 0.1) if float(description.frame_dt_s) > 0.0 else 0.0,
		"rows": description.rows, "dropped": description.dropped, "duration_s": snappedf(float(analysis.metrics.get("duration_s", {}).get("value", 0.0)), 0.001), "mesh_sampling": description.mesh_sampling,
		"engine": Engine.get_version_info().string, "revision": revision(), "command": String(options.get("command", "")), "cli": String(options.get("cli", ""))}
	var findings := Findings.build(analysis.events, rows, config, names)
	var counts := {"high": 0, "medium": 0, "low": 0, "info": 0}
	var worst_frames := []
	for finding: Dictionary in findings:
		counts[finding.severity] = int(counts[finding.severity]) + 1
		if finding.severity != "info" and worst_frames.size() < 12:
			worst_frames.append({"finding": finding.id, "n": finding.observation.frames.worst_n, "st": finding.observation.frames.st0})
	var report := {"format": FORMAT, "version": VERSION, "config": config,
		"summary": {"headline": Findings.headline(findings), "findings": counts, "counts": analysis.get("counts", {}), "metrics": analysis.metrics},
		"findings": findings, "worst_frames": worst_frames, "events": analysis.events, "markers": recorder.markers.duplicate(true),
		"samples": _samples(rows, findings, options), "instruments": instruments(rows, recorder), "limitations": limitations(),
		"meta": {"tool": "ADDA — AniLab Diagnostic & Debugging Assistant", "generated_utc": Time.get_datetime_string_from_system(true)}}
	return jsonable(report)

static func _samples(rows: Array, findings: Array, options: Dictionary) -> Dictionary:
	var wanted := {}
	if String(options.get("detail", "summary")) == "full":
		for row: Dictionary in rows:
			wanted[int(row.n)] = true
	else:
		var window: Array = options.get("window", [])
		if window.size() == 2:
			for row: Dictionary in rows:
				if int(row.n) >= int(window[0]) and int(row.n) <= int(window[1]):
					wanted[int(row.n)] = true
		else:
			for finding: Dictionary in findings:
				if finding.severity == "info":
					continue
				var worst := int(finding.observation.frames.worst_n)
				for n in range(worst - CONTEXT_ROWS, worst + CONTEXT_ROWS + 1):
					wanted[n] = true
			if not rows.is_empty():
				wanted[int(rows.front().n)] = true
				wanted[int(rows.back().n)] = true
	var picked := []
	for row: Dictionary in rows:
		if wanted.has(int(row.n)):
			picked.append(row)
	return {"selection": "full" if String(options.get("detail", "summary")) == "full" else ("window" if (options.get("window", []) as Array).size() == 2 else "worst frames and their neighbours"), "count": picked.size(), "rows": picked}

## What each measurement kind establishes and whether this report took it.
static func instruments(rows: Array, recorder: SessionRecorder) -> Array:
	var has_hands := false
	var has_feet := false
	var has_bones := false
	var has_mesh := false
	for row: Dictionary in rows:
		has_hands = has_hands or not (row.hands as Array).is_empty()
		has_feet = has_feet or not (row.feet as Array).is_empty()
		has_bones = has_bones or not (row.bones as Dictionary).is_empty()
		has_mesh = has_mesh or row.has("mesh")
	var out := []
	var taken := {Measurement.Kind.JOINT_POSITION: has_bones, Measurement.Kind.TARGET_ERROR: has_hands or has_feet, Measurement.Kind.REACH_FEASIBILITY: has_hands, Measurement.Kind.SUPPORT_CLAIM: has_feet,
		Measurement.Kind.VERTEX_OVERLAP: has_mesh}
	for kind in Measurement.Kind.values():
		var status := "TAKEN" if taken.get(kind, false) else "NOT TAKEN"
		var reason := ""
		if kind == Measurement.Kind.MESH_INTERSECTION or kind == Measurement.Kind.PHYSICAL_COLLISION:
			status = "UNSUPPORTED"
			reason = "ADDA has no instrument for this"
		elif kind == Measurement.Kind.CAPSULE_OVERLAP:
			reason = "available in the Workbench (Diagnostics tab) but not recorded per frame"
		elif not taken.get(kind, false):
			reason = "nothing of this kind occurred in the recording, or the instrument was off"
		out.append({"kind": Measurement.Kind.keys()[kind], "status": status, "reason": reason, "establishes": Measurement.MEANING[kind][0], "does_not_establish": Measurement.MEANING[kind][1]})
	return out

static func limitations() -> Array:
	return ["Every pose value is read inside skeleton_updated (the final pose) and is one row per rendered frame; the last update of a frame wins.",
		"A finding is an observation of recorded numbers. Hypotheses are unconfirmed; the cause is unknown unless a finding says it was measured.",
		"Thresholds decide what is reported (20 mm hand, 30 mm foot, 15 mm slide, 97% of the arm, snap = speed over 4x the neighbours plus 1 m/s); the values are always in the finding.",
		"Snap and frame-count metrics depend on the frame rate; lengths depend on the body size. Compare reports with ReportCompare, which says when a comparison is not valid.",
		"Vertex overlap counts sampled skinned vertices only; full mesh intersection and physical collision are not measured.",
		"A support claim is the animation system's claim, not physical support."]

## The source revision when git is available: {commit, branch, dirty}. {commit: "unavailable", reason} when it is not (never a guess).
static func revision() -> Dictionary:
	var root := ProjectSettings.globalize_path("res://")
	var output := []
	if OS.execute("git", ["-C", root, "rev-parse", "--short", "HEAD"], output, true) != 0 or output.is_empty():
		return {"commit": "unavailable", "branch": "", "dirty": false, "reason": "git was not available from the engine"}
	var commit := String(output[0]).strip_edges()
	var branch := []
	OS.execute("git", ["-C", root, "rev-parse", "--abbrev-ref", "HEAD"], branch, true)
	var status := []
	OS.execute("git", ["-C", root, "status", "--porcelain", "--untracked-files=no"], status, true)
	return {"commit": commit, "branch": String(branch[0]).strip_edges() if not branch.is_empty() else "", "dirty": not status.is_empty() and String(status[0]).strip_edges() != ""}

## Plain JSON-able data: vectors as [x, y, z] (0.1 mm), floats rounded, names as strings.
static func jsonable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3:
			var v: Vector3 = value
			return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
		TYPE_FLOAT:
			return snappedf(value, 0.00001) if is_finite(value) else null
		TYPE_STRING_NAME:
			return String(value)
		TYPE_DICTIONARY:
			var out := {}
			for key in (value as Dictionary):
				out[String(key)] = jsonable(value[key])
			return out
		TYPE_ARRAY:
			var list := []
			for item in (value as Array):
				list.append(jsonable(item))
			return list
		TYPE_PACKED_STRING_ARRAY:
			return Array(value)
	return value

static func save(report: Dictionary, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var compact: bool = String(report.get("samples", {}).get("selection", "")) == "full"
	file.store_string(JSON.stringify(report, "" if compact else "  ", true))
	file.close()
	return OK

## {ok, report, error}: a report read back, with a format and version check (an unknown format is refused, not guessed at).
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found: %s" % path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {"ok": false, "error": "not a JSON object: %s" % path}
	if String(parsed.get("format", "")) != FORMAT:
		return {"ok": false, "error": "not an ADDA report (format '%s')" % String(parsed.get("format", ""))}
	if int(parsed.get("version", 0)) > VERSION:
		return {"ok": false, "error": "report version %d is newer than this reader (%d)" % [int(parsed.version), VERSION]}
	return {"ok": true, "report": parsed, "error": ""}
