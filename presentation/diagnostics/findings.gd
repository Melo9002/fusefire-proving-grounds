class_name Findings
extends RefCounted
## Turns TimelineAnalysis events into FINDINGS a person or an agent can act on, and keeps the two things apart that a diagnostic must not blur:
##   OBSERVATION  what the recorded numbers show (a measured fact, with its frames, values, method and what that method does not establish)
##   HYPOTHESIS   what might explain it: always "unconfirmed", always with the basis it rests on and an experiment that would test it
## and a CAUSE that is "unknown" unless something proves otherwise. ADDA never states a cause it has not measured; a finding with no grounded hypothesis says so rather than inventing one.
##
## Finding record (stable field names, schema 1):
##   key        stable across runs: kind|subject|ordinal (use it to match findings between two reports)
##   id         F1, F2 ... in severity order for THIS report (for talking about it)
##   severity   high | medium | low | info
##   title      one plain sentence
##   observation {text, facts{...}, frames{n0, n1, worst_n, t0, t1, st0}}
##   hypotheses [{text, status: "unconfirmed", basis, experiment}]
##   cause      "unknown"
##   subject    {kind, text, bones[], side, part, surface{kind, index}}   what to select or highlight
##   evidence   {kinds[], method, does_not_establish}
##   reproduce  {scenario, character, n, st, replay}

const SEVERITY_ORDER := {"high": 0, "medium": 1, "low": 2, "info": 3}

## `names` maps a bone name to its plain name ("mixamorig_RightLeg" -> "right shin"); `config` is the report's config block.
static func build(events: Array, rows: Array, config: Dictionary, names := {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in events:
		var finding := _from_event(event, events, rows, config, names)
		if finding.is_empty():
			continue
		out.append(finding)
	out = _collapse(out)
	_assign_keys(out)
	_not_measured(out, rows, config)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(SEVERITY_ORDER[a.severity])
		var sb := int(SEVERITY_ORDER[b.severity])
		return sa < sb or (sa == sb and int(a.observation.frames.n0) < int(b.observation.frames.n0)))
	for i in out.size():
		out[i]["id"] = "F%d" % (i + 1)
	return out

static func _from_event(event: Dictionary, events: Array, rows: Array, config: Dictionary, names: Dictionary) -> Dictionary:
	match String(event.kind):
		"reach_exceeded":
			return _reach(event, rows, config)
		"target_error":
			return _error(event, rows, config)
		"plant_slide":
			return _slide(event, events, rows, config)
		"plant_settle":
			return _settle(event, rows, config)
		"plant_offset":
			return _offset(event, events, rows, config)
		"pose_snap":
			return _snap(event, events, rows, config, names)
		"mesh_overlap":
			return _mesh(event, rows, config, names)
	return {}

## A defect that repeats (a shin that snaps at every rung, a toe that dips at every step) is ONE finding with its occurrences listed, not thirty: the pattern is the finding. The worst occurrence represents it;
## `observation.facts.occurrences` lists every one ({n, st, value}) and the key is that of the first, so it stays stable across runs.
const COLLAPSE_FROM := 3

## Stable identity for matching findings between two reports: what kind of thing it is and which part it is about (the worst bone of a snap, the body part of a mesh overlap, the hand or foot), numbered in time order
## among findings of the same identity. It does not depend on how many bones moved or on the numbers, so a defect that gets smaller is still the same finding.
static func _assign_keys(findings: Array[Dictionary]) -> void:
	findings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.observation.frames.n0) < int(b.observation.frames.n0))
	var ordinals := {}
	for finding in findings:
		var base := _group_key(finding)
		var ordinal := int(ordinals.get(base, 0))
		ordinals[base] = ordinal + 1
		finding["key"] = "%s|%d" % [base, ordinal]

static func _group_key(finding: Dictionary) -> String:
	var subject: Dictionary = finding.subject
	match String(finding.kind):
		"mesh_overlap":   # the leg, not the exact part: the same crossing is a shin on one body and a toe on another
			var part := String(subject.get("part", ""))
			var is_leg := false
			for word in ["thigh", "shin", "foot", "toes"]:
				is_leg = is_leg or part.ends_with(word)
			return "%s|%s" % [finding.kind, ("%s leg" % side_of(part)).strip_edges() if is_leg else part]
		"pose_snap":
			return "%s|%s" % [finding.kind, subject.get("text", "")]
	return "%s|%s" % [finding.kind, subject.get("text", "")]

static func _collapse(findings: Array[Dictionary]) -> Array[Dictionary]:
	var groups := {}
	var order: Array[String] = []
	for finding in findings:
		var key := _group_key(finding)
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(finding)
	var out: Array[Dictionary] = []
	for key in order:
		var members: Array = groups[key]
		if members.size() < COLLAPSE_FROM:
			out.append_array(members)
			continue
		var worst: Dictionary = members[0]
		var occurrences := []
		var lowest := INF
		var highest := -INF
		for m: Dictionary in members:
			var value := _magnitude(m)
			occurrences.append({"n": m.observation.frames.worst_n, "st": m.observation.frames.st0, "value": value})
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
			if value > _magnitude(worst):
				worst = m
		var merged: Dictionary = worst.duplicate(true)
		var severity := "info"
		for m: Dictionary in members:
			if int(SEVERITY_ORDER[m.severity]) < int(SEVERITY_ORDER[severity]):
				severity = String(m.severity)
		merged["severity"] = severity
		merged["title"] = "%s (%d times)" % [worst.title, members.size()]
		var times: Array[String] = []
		for o in occurrences.slice(0, 8):
			times.append("%.2f" % float(o.st))
		merged.observation["text"] = "%s This happened %d times in the run (at %s%s s); the worst is described here." % [worst.observation.text, members.size(), ", ".join(times), ", ..." if occurrences.size() > 8 else ""]
		merged.observation.facts["occurrences"] = occurrences
		merged.observation.facts["occurrence_count"] = members.size()
		out.append(merged)
	return out

## The number a finding's occurrences are compared by.
static func _magnitude(finding: Dictionary) -> float:
	var facts: Dictionary = finding.observation.facts
	for key in ["deepest_mm", "step_cm", "deficit_cm", "slide_mm", "error_mm", "error_start_mm"]:
		if facts.has(key):
			return float(facts[key])
	if facts.has("largest") and not (facts.largest as Array).is_empty():
		return float(facts.largest[0].step_cm)
	return 0.0

static func _span(event: Dictionary, rows: Array) -> float:
	var dt := 0.0
	for row in rows:
		if int(row.n) >= int(event.n0) and int(row.n) <= int(event.n1):
			dt += float(row.dt)
	return dt

## When it happened. A finding that spans several rows also says when it was WORST (that is the moment to look at); a one-moment finding gives one time.
static func _when(event: Dictionary, rows := []) -> String:
	var t := float(event.st0) if float(event.st0) >= 0.0 else float(event.t0)
	var worst := _row(rows, int(event.get("worst_n", event.n0))) if int(event.get("worst_n", event.n0)) != int(event.n0) else {}
	if not worst.is_empty():
		var tw := float(worst.st) if float(event.st0) >= 0.0 and float(worst.get("st", -1.0)) >= 0.0 else float(worst.t)
		if absf(tw - t) >= 0.01:
			return "from %.2f s, worst at %.2f s" % [t, tw]
	return "at %.2f s" % t

static func _row(rows: Array, n: int) -> Dictionary:
	for row: Dictionary in rows:
		if int(row.n) == n:
			return row
	return {}

static func _make(event: Dictionary, severity: String, title: String, text: String, facts: Dictionary, hypotheses: Array, subject: Dictionary, kinds: Array[Measurement.Kind], method: String, config: Dictionary) -> Dictionary:
	var limits: Array[String] = []
	for kind in kinds:
		limits.append(String(Measurement.MEANING[kind][1]))
	return {"severity": severity, "kind": event.kind, "title": title,
		"observation": {"text": text, "facts": facts, "frames": {"n0": event.n0, "n1": event.n1, "worst_n": event.worst_n, "t0": snappedf(float(event.t0), 0.0001), "t1": snappedf(float(event.t1), 0.0001), "st0": snappedf(float(event.st0), 0.0001)}},
		"hypotheses": hypotheses, "cause": "unknown", "subject": subject,
		"evidence": {"kinds": kinds.map(func(k: Measurement.Kind) -> String: return Measurement.Kind.keys()[k]), "method": method, "does_not_establish": limits},
		"reproduce": {"scenario": String(config.get("scenario", "")), "character": String(config.get("character", "")), "n": event.worst_n, "st": snappedf(float(event.st0), 0.0001),
			"replay": "Replay the scenario paused at scenario time %.2f s (Why? tab: Replay to this moment), or run: %s" % [float(event.st0), _command(config)]}}

static func _hypothesis(text: String, basis: String, experiment: String) -> Dictionary:
	return {"text": text, "status": "unconfirmed", "basis": basis, "experiment": experiment}

static func _reach(event: Dictionary, rows: Array, config: Dictionary) -> Dictionary:
	var row := _row(rows, int(event.worst_n))
	var detail: Dictionary = event.detail
	var arm := float(detail.get("arm_cm", 0.0))
	var side := String(event.subject).split(" ")[0]
	var seconds := _span(event, rows)
	var hand_row := _side_of_row(row, side)
	var wrist_error := float(hand_row.get("error_mm", 0.0))
	var text := "%s target is %.1f cm beyond the arm's reach (the limit used is 97%% of a %.0f cm arm), for %.2f s, %s. The wrist ended %.0f mm from it, while the contact claimed weight %.2f." % [String(event.subject).capitalize(), float(event.value), arm, seconds, _when(event, rows), wrist_error, float(detail.get("weight", 0.0))]
	var hypotheses := [
		_hypothesis("The contact point is farther from the shoulder than this body's arm can span: it was placed for a different-sized body or the body is not where the contact expects it.",
			"reach is shoulder-to-target distance against arm length (%.0f cm here); the deficit is geometry, not a solver result" % arm,
			"Run the same scenario on the other character (--character) or unarmed and compare 'hand.%s.worst_deficit_cm'" % side)]
	return _make(event, "high" if float(event.value) >= 5.0 else "medium", "%s target out of reach" % String(event.subject).capitalize(), text, {"deficit_cm": event.value, "wrist_error_mm": snappedf(wrist_error, 0.1), "arm_cm": arm, "seconds": snappedf(seconds, 0.001), "owner": detail.get("owner", ""), "weight": detail.get("weight", 0.0),
		"stages_engaged": detail.get("stages", [])}, hypotheses, {"kind": "target", "text": "%s contact target" % side, "side": side, "part": "hand", "bones": []},
		[Measurement.Kind.REACH_FEASIBILITY, Measurement.Kind.TARGET_ERROR], "shoulder bone and contact target read inside skeleton_updated; reach = distance against 97% of shoulder-elbow-wrist length", config)

static func _side_of_row(row: Dictionary, side: String) -> Dictionary:
	for hand: Dictionary in row.get("hands", []):
		if String(hand.name) == side:
			return hand
	return {}

static func _error(event: Dictionary, rows: Array, config: Dictionary) -> Dictionary:
	var detail: Dictionary = event.detail
	var side := String(event.subject).split(" ")[0]
	var seconds := _span(event, rows)
	var margin := float(detail.get("reach_margin_cm", 0.0))
	var stages: Array = detail.get("stages", [])
	var text := "%s ended %.1f mm from its contact target while a contact held it (%s marks 20 mm and above), for %.2f s, %s." % [String(event.subject).capitalize(), float(event.value), "the contact overlay", seconds, _when(event, rows)]
	var hypotheses := []
	if margin < 3.0:
		hypotheses.append(_hypothesis("The target is close to the arm's reach limit, so the solver may not fully reach it.", "reach margin is only %.1f cm at the worst frame" % margin, "Compare against a longer-armed character, or check 'hand.%s.worst_deficit_cm'" % side))
	if stages.size() > 1:
		hypotheses.append(_hypothesis("Another engaged stage may also write this arm after the contact stage.", "stages engaged at the worst frame: %s" % ", ".join(stages), "Diagnostics tab, 'Why is this bone moving', for the %s hand and forearm" % side))
	return _make(event, "high" if float(event.value) >= 50.0 else "medium", "%s misses its target" % String(event.subject).capitalize(), text, {"error_mm": event.value, "seconds": snappedf(seconds, 0.001), "reach_margin_cm": margin, "owner": detail.get("owner", ""),
		"weight": detail.get("weight", 0.0), "stages_engaged": stages}, hypotheses, {"kind": "limb", "text": "%s hand" % side, "side": side, "part": "hand", "bones": []},
		[Measurement.Kind.TARGET_ERROR], "final wrist bone against the contact target node, read inside skeleton_updated", config)

static func _slide(event: Dictionary, events: Array, rows: Array, config: Dictionary) -> Dictionary:
	var detail: Dictionary = event.detail
	var side := String(event.subject).split(" ")[0]
	var seconds := _span(event, rows)
	var text := "%s moved %.1f mm against its foothold while the %s claimed it planted, over %.2f s, %s." % [String(event.subject).capitalize(), float(event.value), String(detail.get("source", "plan")), seconds, _when(event, rows)]
	var hypotheses := []
	var jumps := _near(events, "target_jump", int(event.n0), int(event.n1), 2, "%s foot" % side)
	if not jumps.is_empty():
		hypotheses.append(_hypothesis("The foothold itself was retargeted during the span, so the ankle followed a moving plan.", "target_jump events on this foot at rows %s" % ", ".join(jumps.map(func(e: Dictionary) -> String: return str(e.n0))), "Look at 'foot.%s' footholds around those rows" % side))
	if float(detail.get("weight", 1.0)) < 0.99:
		hypotheses.append(_hypothesis("The plan had not taken full hold of the leg (weight %.2f at the worst frame)." % float(detail.weight), "the claimed weight is below 1 at the worst frame", "Compare the weight ramp in another scenario or frame rate"))
	return _make(event, "high" if float(event.value) >= 40.0 else "medium", "%s slides while planted" % String(event.subject).capitalize(), text, {"slide_mm": event.value, "seconds": snappedf(seconds, 0.001), "source": detail.get("source", ""),
		"weight": detail.get("weight", 0.0), "stages_engaged": detail.get("stages", [])}, hypotheses, {"kind": "limb", "text": "%s foot" % side, "side": side, "part": "foot", "bones": []},
		[Measurement.Kind.SUPPORT_CLAIM, Measurement.Kind.TARGET_ERROR], "ankle minus the planner's foothold, change since the span began; the claim is the plan's planted flag and weight, not physical support", config)

## A foot the plan holds that stays off its foothold: the absolute error, not a slide (a slow drift moves little within one planted span yet ends far off).
static func _offset(event: Dictionary, events: Array, rows: Array, config: Dictionary) -> Dictionary:
	var detail: Dictionary = event.detail
	var side := String(event.subject).split(" ")[0]
	var seconds := _span(event, rows)
	var stages: Array = detail.get("stages", [])
	var text := "%s stayed up to %.1f mm from its foothold (%.1f mm when the %s took hold, %.1f mm at the end) for %.2f s while the plan claimed it planted, %s." % [String(event.subject).capitalize(), float(event.value), float(detail.get("error_start_mm", 0.0)), String(detail.get("source", "plan")), float(detail.get("error_end_mm", 0.0)), seconds, _when(event, rows)]
	var hypotheses := []
	var jumps := _near(events, "target_jump", int(event.n0), int(event.n1), 2, "%s foot" % side)
	if not jumps.is_empty():
		hypotheses.append(_hypothesis("The foothold itself was retargeted during the span, so the ankle followed a moving plan.", "target_jump events on this foot at rows %s" % ", ".join(jumps.map(func(e: Dictionary) -> String: return str(e.n0))), "Look at the foothold around those rows"))
	hypotheses.append(_hypothesis("Something after the leg planner may have moved the foot off the plan: a stage, or a modifier that is not declared in PoseOwnership.", "the ankle ends %.1f mm from a foothold that did not move; stages engaged at the worst frame: %s" % [float(event.value), ", ".join(stages) if not stages.is_empty() else "none reported"], "Run the isolation experiment on the %s foot (adda isolate --bones=@%s_foot): it switches each modifier off in turn and reports which ones move the foot" % [side, side]))
	return _make(event, "high" if float(event.value) >= 60.0 else "medium", "%s is off its foothold while planted" % String(event.subject).capitalize(), text, {"error_max_mm": event.value, "error_start_mm": detail.get("error_start_mm", 0.0), "error_end_mm": detail.get("error_end_mm", 0.0),
		"seconds": snappedf(seconds, 0.001), "source": detail.get("source", ""), "weight": detail.get("weight", 0.0), "stages_engaged": stages}, hypotheses, {"kind": "limb", "text": "%s foot" % side, "side": side, "part": "foot", "bones": []},
		[Measurement.Kind.SUPPORT_CLAIM, Measurement.Kind.TARGET_ERROR], "ankle minus the planner's foothold while the plan held the leg at full weight and did not close in; the claim is the plan's planted flag and weight, not physical support", config)

static func _settle(event: Dictionary, rows: Array, config: Dictionary) -> Dictionary:
	var detail: Dictionary = event.detail
	var side := String(event.subject).split(" ")[0]
	var seconds := _span(event, rows)
	var text := "%s was still %.1f mm from its foothold when the %s took full hold of the leg, and closed to %.1f mm over %.2f s, %s." % [String(event.subject).capitalize(), float(event.value), String(detail.get("source", "plan")), float(detail.get("error_end_mm", 0.0)), seconds, _when(event, rows)]
	var hypotheses := [_hypothesis("The plan's weight reached full strength before the ankle arrived, so the foot is still travelling onto its foothold while the plan claims it planted.", "the error at the first held frame (%.1f mm) is more than twice the error at the end (%.1f mm)" % [float(event.value), float(detail.get("error_end_mm", 0.0))], "Compare the weight ramp against the ankle's approach (Diagnostics tab, contact measurement) or at another frame rate")]
	return _make(event, "low", "%s settles onto its foothold late" % String(event.subject).capitalize(), text, {"error_start_mm": event.value, "error_end_mm": detail.get("error_end_mm", 0.0), "seconds": snappedf(seconds, 0.001), "source": detail.get("source", ""),
		"stages_engaged": detail.get("stages", [])}, hypotheses, {"kind": "limb", "text": "%s foot" % side, "side": side, "part": "foot", "bones": []},
		[Measurement.Kind.SUPPORT_CLAIM, Measurement.Kind.TARGET_ERROR], "ankle minus the planner's foothold at the first and last frame the plan held the leg; the claim is the plan's planted flag and weight, not physical support", config)

## Which intended point a body part follows, by its plain name: an arm part follows a hand target, a leg part a foothold (the rig's own targets; nothing is guessed for the torso or head).
static func _intended_of(plain: String) -> String:
	var side := side_of(plain)
	if side == "":
		return ""
	for part in ["upper arm", "forearm", "hand", "shoulder"]:
		if plain.ends_with(part):
			return "%s hand target" % side
	for part in ["thigh", "shin", "foot", "toes"]:
		if plain.ends_with(part):
			return "%s foothold" % side
	return ""

## Whether the rows around the event carry the intended point ("left hand target", "right foothold") at all: absence is not "it did not move".
static func _has_intended(rows: Array, n0: int, n1: int, intended: String) -> bool:
	var side := intended.split(" ")[0]
	var key := "hands" if intended.ends_with("hand target") else "feet"
	for row: Dictionary in rows:
		if int(row.n) >= n0 - 2 and int(row.n) <= n1 + 2:
			for entry: Dictionary in row.get(key, []):
				if String(entry.name) == side:
					return true
	return false

static func _has_poles(rows: Array, n0: int, n1: int) -> bool:
	for row: Dictionary in rows:
		if int(row.n) >= n0 - 2 and int(row.n) <= n1 + 2 and not ((row.get("ladder", {}) as Dictionary).get("knee_poles", []) as Array).is_empty():
			return true
	return false

static func _snap(event: Dictionary, events: Array, rows: Array, config: Dictionary, names: Dictionary) -> Dictionary:
	var detail: Dictionary = event.detail
	var subjects: Array = detail.subjects
	var count := int(detail.count)
	var top: Dictionary = subjects[0]
	var worst_name := String(names.get(String(top.subject), String(top.subject)))
	var listed: Array[String] = []
	for i in mini(subjects.size(), 3):
		var plain := String(names.get(String(subjects[i].subject), String(subjects[i].subject)))
		listed.append("%s %.1f cm" % [plain, float(subjects[i].step_cm)])
	var text := ""
	if count == 1:
		text = "%s jumped %.1f cm beyond the motion of the frames around it (%.1f m/s against about %.1f m/s around it), %s." % [("The " + worst_name) if String(top.subject) == "root" else worst_name.capitalize(), float(top.step_cm), float(top.speed_mps), float(top.neighbour_speed_mps), _when(event, rows)]
	else:
		text = "%d bones jumped at the same moment, %s, beyond the motion of the frames around them. Largest jumps: %s." % [count, _when(event, rows), ", ".join(listed)]
	# What the intended points did in the same frames, and what else changed: these are the facts that separate "the pose followed a retarget" from "the pose itself changed".
	var jumped := _near(events, "target_jump", int(event.n0), int(event.n1), 2, "")
	var jumped_text: Array[String] = []
	for j in jumped:
		jumped_text.append("%s %.1f cm" % [j.subject, float(j.value)])
	var follows := ""
	var followed := ""   # the intended point that also jumped, for the unconfirmed hypothesis below
	var plain_top := _intended_of(worst_name)
	if plain_top != "":
		var moved := false
		for j in jumped:
			if String(j.subject) == plain_top:
				moved = true
		if not _has_intended(rows, int(event.n0), int(event.n1), plain_top):
			follows = " It has no %s in these frames to compare against (no stair, ladder or contact supplies one), so a retarget cannot be told apart from the pose itself changing." % plain_top.trim_prefix("left ").trim_prefix("right ")
		else:
			# Observation only. A target that moved in the same frames is a coincidence until a test says otherwise (on a ladder the footholds move at every step); one that did not move rules that target out.
			follows = (" The %s also jumped in the same frames; the pose may have followed it (not confirmed)." % plain_top) if moved else (" The %s did not jump in those frames, so the jump did not come from that target." % plain_top)
			if moved:
				followed = plain_top
	var hypotheses := []
	if followed != "":
		hypotheses.append(_hypothesis("The pose followed the %s, which was moved (retargeted) in the same frames." % followed, "target_jump on the %s within 2 rows of this snap" % followed, "Look at what sets the %s at this moment; if it should not move here, hold it and see whether the snap goes" % followed))
	# The knee pole (an input of the leg solver, recorded on a ladder): did it jump in the frames where a leg bone did?
	var leg_side := side_of(worst_name)
	if leg_side != "" and (worst_name.ends_with("shin") or worst_name.ends_with("thigh") or worst_name.ends_with("foot")):
		var pole_jumps := _near(events, "target_jump", int(event.n0), int(event.n1), 2, "%s knee pole" % leg_side)
		if not pole_jumps.is_empty():
			follows += " The %s knee pole, the point the leg solver bends the knee toward, jumped %.1f cm in the same frames." % [leg_side, float(pole_jumps[0].value)]
			hypotheses.append(_hypothesis("The leg solver was handed a knee pole that jumped, so the knee followed it.", "target_jump on the %s knee pole at rows %s, the same frames as this snap" % [leg_side, ", ".join(pole_jumps.map(func(e: Dictionary) -> String: return str(e.n0)))], "Find what writes the pole (the traversal stage sets it) and run the same scenario with --disable=Traversal to see whether the snap goes with it"))
		elif _has_poles(rows, int(event.n0), int(event.n1)):
			follows += " The %s knee pole did not jump in those frames." % leg_side
	var context_changes := _near(events, "context_changed", int(event.n0), int(event.n1), 2, "")
	for change: Dictionary in context_changes:
		hypotheses.append(_hypothesis("The body's context changed at this frame (%s to %s), so one pose may have been replaced by another at once." % [change.detail.from, change.detail.to], "context_changed event at row %d" % int(change.n0), "Look at the stage weights across the change (Diagnostics tab, pose stages) and whether the exit is blended"))
	# The animation state (clip) changed in the same frames: a transition between two clips moves bones at once, and which stage happened to engage then is a coincidence until a test says otherwise.
	for change: Dictionary in _near(events, "state_changed", int(event.n0), int(event.n1), 2, ""):
		hypotheses.append(_hypothesis("The animation state changed at this frame (%s to %s): a transition between two clips that is not cross-faded can move many bones at once." % [change.detail.from, change.detail.to], "state_changed event at row %d" % int(change.n0), "Replay to this moment (Why? tab) and step across it frame by frame; a stage-off run (--disable=<stage>) does not test this one"))
	var stage_changes := _near(events, "stage_engaged", int(event.n0), int(event.n1), 2, "") + _near(events, "stage_released", int(event.n0), int(event.n1), 2, "")
	if not stage_changes.is_empty():
		hypotheses.append(_hypothesis("A pose stage changed its engagement at about the same frame, which can add or remove an offset at once.", "stage events within 2 rows: %s" % ", ".join(stage_changes.map(func(e: Dictionary) -> String: return "%s %s (row %d)" % [e.subject, String(e.kind).trim_prefix("stage_"), int(e.n0)])), "Diagnostics tab, 'Why is this bone moving', for the bone that moved most"))
	var facts := {"bones_moved": count, "step_cm": float(top.step_cm), "largest": subjects.slice(0, 5), "targets_jumped": jumped_text, "stages_engaged": detail.get("stages", []), "context": detail.get("context", "")}
	var step := float(top.step_cm)
	var severity := "high" if step >= 10.0 else ("medium" if step >= 3.0 else "low")
	var title := "Pose snap: %d bones at once" % count if count > 1 else "%s snaps" % worst_name.capitalize()
	return _make(event, severity, title, text + follows, facts, hypotheses, {"kind": "bone", "text": worst_name, "side": side_of(worst_name), "part": worst_name, "bones": subjects.slice(0, 5).map(func(x: Dictionary) -> String: return String(x.subject)).filter(func(x: String) -> bool: return x != "root")},
		[Measurement.Kind.JOINT_POSITION], "bone position per frame, in the world (character frame plus the root's own position and heading), read inside skeleton_updated; a snap is a velocity that departs from the median of the 3 frames either side by more than %.1fx that velocity plus %.1f m/s (frame-rate sensitive); adjacent rows are one moment" % [TimelineAnalysis.SNAP_FACTOR, TimelineAnalysis.SNAP_FLOOR_MPS], config)

static func _mesh(event: Dictionary, rows: Array, config: Dictionary, names: Dictionary) -> Dictionary:
	var detail: Dictionary = event.detail
	var top: Array = detail.get("top", [])
	if top.is_empty():
		return {}
	var worst: Dictionary = top[0]
	var part := String(worst.get("part", worst.bone))
	var bar := String(worst.bar)
	var seconds := _span(event, rows)
	var text := "%s: %d sampled mesh vertices are inside ladder %s, the deepest by %.1f mm, for %.2f s, %s. (Sampled vertices of the skinned leg mesh only: not a full mesh intersection.)" % [part.capitalize(), int(event.value), bar, float(worst.depth_mm), seconds, _when(event, rows)]
	var ladder: Dictionary = detail.get("ladder", {})
	var hypotheses := []
	var facts := {"vertices": event.value, "deepest_mm": worst.depth_mm, "bar": bar, "rung": worst.get("rung", -1), "bone": worst.bone, "seconds": snappedf(seconds, 0.001), "ladder": ladder}
	if worst.has("bar_a"):
		facts["bar"] = {"space": "character", "axis_a": worst.bar_a, "axis_b": worst.bar_b, "radius_m": worst.bar_radius_m, "nearest_on_axis": worst.bar_nearest, "surface_normal": worst.surface_normal, "vertex": worst.point,
			"source": "LadderGeometry (the environment's own cylinder); the normal runs from its axis to the vertex"}
	if not ladder.is_empty() and int(worst.get("rung", -1)) >= 0:
		var rung := int(worst.rung)
		var on: Array = ladder.get("foot_rung", [-1, -1])
		var side_index := 0 if part.begins_with("left") else 1
		if int(on[side_index]) == rung:
			facts["foot_on_this_rung"] = true
			hypotheses.append(_hypothesis("This is the rung that foot is planted on, so the overlap may be the sole sinking into its own rung.", "the %s foot is planted on rung %d at the worst frame" % ["left" if side_index == 0 else "right", rung], "Check the sole-to-rung distance (LadderClearance.planted_sole_vs_rung)"))
		elif not on.has(rung):
			facts["foot_on_this_rung"] = false
			hypotheses.append(_hypothesis("The leg is crossing a rung neither foot is on, so the overlap is more likely the leg's path than a foot placement.", "feet are planted on rungs %s and %s; the overlap is rung %d" % [str(on[0]), str(on[1]), rung], "Compare knee spread and ladder pitch (docs/claude/ladder-landing-generalization-2026-11-23.md)"))
	return _make(event, "high" if int(event.value) >= 10 else "medium", "%s vs ladder %s" % [part.capitalize(), bar], text, facts, hypotheses,
		{"kind": "surface", "text": "%s and ladder %s" % [part, bar], "side": String(side_of(part)), "part": part, "bones": [String(worst.bone)], "surface": {"kind": "ladder rung" if int(worst.get("rung", -1)) >= 0 else "ladder rail", "index": int(worst.get("rung", -1)), "name": bar}},
		[Measurement.Kind.VERTEX_OVERLAP], "SkinnedSurface (linear blend skinning from poses cached inside skeleton_updated) of the leg bones; each vertex tested against the rung and rail cylinders, 3 mm threshold", config)

static func side_of(part: String) -> String:
	return "left" if part.begins_with("left") else ("right" if part.begins_with("right") else "")

## Events of `kind` within `slack` rows of [n0, n1] whose subject starts with `prefix`.
static func _near(events: Array, kind: String, n0: int, n1: int, slack: int, prefix: String) -> Array:
	var out := []
	for event: Dictionary in events:
		if String(event.kind) == kind and int(event.n0) >= n0 - slack and int(event.n0) <= n1 + slack and String(event.subject).begins_with(prefix):
			out.append(event)
	return out

## What was NOT measured, said plainly, so silence is never read as "fine".
static func _not_measured(out: Array[Dictionary], rows: Array, config: Dictionary) -> void:
	var on_ladder := false
	var mesh_seen := false
	for row in rows:
		if String(row.get("context", "")) == "ladder":
			on_ladder = true
		if row.has("mesh"):
			mesh_seen = true
	if on_ladder and not mesh_seen:
		out.append({"key": "not_measured|ladder mesh|0", "severity": "info", "kind": "not_measured", "title": "Leg-against-ladder overlap was not measured",
			"observation": {"text": "The character climbed a ladder, but the skinned leg mesh was not sampled against the bars (mesh sampling is off: it costs about 3 ms a sample). No overlap was looked for, so none was found; that is not evidence of a clean climb.", "facts": {}, "frames": {"n0": 0, "n1": 0, "worst_n": 0, "t0": 0.0, "t1": 0.0, "st0": 0.0}},
			"hypotheses": [], "cause": "unknown", "subject": {"kind": "none", "text": "ladder", "side": "", "part": "", "bones": []},
			"evidence": {"kinds": ["VERTEX_OVERLAP"], "method": "not taken", "does_not_establish": [String(Measurement.MEANING[Measurement.Kind.VERTEX_OVERLAP][1])]},
			"reproduce": {"scenario": String(config.get("scenario", "")), "character": String(config.get("character", "")), "n": 0, "st": 0.0, "replay": "Run again with --mesh: %s" % _command(config)}})

## A sentence a person can read first: how many findings of what weight, or that nothing was found and what that does not mean.
static func headline(findings: Array) -> String:
	var counts := {"high": 0, "medium": 0, "low": 0}
	var real := 0
	for finding: Dictionary in findings:
		if finding.severity != "info":
			real += 1
			counts[finding.severity] = int(counts.get(finding.severity, 0)) + 1
	if real == 0:
		return "ADDA found nothing wrong among the things it measured (listed under 'measured'). That is not proof the motion is right: anything not listed was not looked at."
	return "%d finding%s: %d high, %d medium, %d low. These are measurements; the causes are unknown unless a finding says otherwise." % [real, "" if real == 1 else "s", counts.high, counts.medium, counts.low]

## A finding as readable text. Plain first (what was measured, what might explain it, that the cause is unknown); `detailed` adds the facts, what the method does not establish, and how to reproduce.
static func explain(finding: Dictionary, detailed := false) -> String:
	var lines: Array[String] = []
	lines.append("%s  [%s]  %s" % [finding.get("id", ""), String(finding.severity).to_upper(), finding.title])
	lines.append("  Observed: %s" % finding.observation.text)
	var hypotheses: Array = finding.get("hypotheses", [])
	if hypotheses.is_empty():
		lines.append("  Possible causes: none that the measurements support. Cause: unknown.")
	else:
		lines.append("  Possible causes (NOT confirmed; cause is unknown until one is tested):")
		for h: Dictionary in hypotheses:
			lines.append("    - %s" % h.text)
			lines.append("        because: %s" % h.basis)
			lines.append("        test it: %s" % h.experiment)
	if detailed:
		lines.append("  Facts: %s" % JSON.stringify(finding.observation.facts))
		var frames: Dictionary = finding.observation.frames
		lines.append("  Frames: rows %d-%d (worst %d), presenter %.2f-%.2f s, scenario %.2f s" % [int(frames.n0), int(frames.n1), int(frames.worst_n), float(frames.t0), float(frames.t1), float(frames.st0)])
		lines.append("  Measured with: %s  [%s]" % [finding.evidence.method, ", ".join(finding.evidence.kinds)])
		for limit in finding.evidence.does_not_establish:
			lines.append("  Does not establish: %s" % limit)
		lines.append("  Subject: %s" % JSON.stringify(finding.subject))
		lines.append("  Reproduce: %s" % finding.reproduce.replay)
	return "\n".join(lines)


## The command that reproduces a finding. The Workbench command cannot carry a run's experiment levers (--challenge, --fault, --disable, --set), so when the run used one the exact headless command is named too: without it a copied command reproduces the unlevered scenario.
static func _command(config: Dictionary) -> String:
	var command := String(config.get("command", ""))
	var cli := String(config.get("cli", ""))
	for lever in [" --challenge=", " --fault=", " --disable=", " --set="]:
		if cli.contains(lever):
			return "%s  (this run used an experiment lever the Workbench command does not carry; the exact headless run is: %s)" % [command, cli]
	return command
