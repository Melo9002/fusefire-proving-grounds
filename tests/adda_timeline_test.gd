extends SceneTree
## ADDA temporal diagnostics, checked against SYNTHETIC recordings so the answer is known: the same rows always give the same events. Each instrument gets a negative control (a defect injected into the rows is
## found) and a normal case (the clean rows are not accused), and the findings are checked for what they must never do: state a cause, or present a hypothesis as confirmed.
##   1 foot slide      a planted ankle that drifts against its foothold is a plant_slide of the right size; a still one is not; one closing in on its foothold is a plant_settle, not a slide
##   2 snapping        a one-frame step far above the neighbouring frames is a pose_snap; a smooth fast swing is not; a paused (zero-time) row is no speed at all
##   3 grouping        bones that jump together are one moment; a defect that repeats is one finding with its occurrences
##   4 contacts        acquisition and release at the claim weight, reach beyond the arm only while a contact claims it
##   5 ownership       state, context and stage changes are events
##   6 retarget        a pose snap while its target jumped says so; while the target held still says that instead
##   7 frame rate      the same slide measured at 30 and 60 fps is the same millimetres
##   8 findings        hypotheses are unconfirmed, the cause is unknown, an empty finding list is not "fine"
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
	_foot_slide()
	_snapping()
	_grouping()
	_contacts()
	_ownership()
	_retarget()
	_frame_rate()
	_findings()
	print("adda_timeline_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

# ---- synthetic rows

## One row. `bones` maps a name to a character-space position; the root stays at the origin facing forward unless given.
func _row(n: int, dt: float, extra := {}) -> Dictionary:
	var row := {"n": n, "frame": n, "update": n, "t": float(n) * dt, "dt": dt if n > 0 else 0.0, "st": float(n) * dt, "state": "idle", "context": "free", "stages": [], "root": Vector3.ZERO, "yaw": 0.0, "bones": {}, "hands": [], "feet": []}
	row.merge(extra, true)
	return row

func _foot(planted: bool, weight: float, ankle: Vector3, planned: Vector3, source := "ladder solver") -> Dictionary:
	return {"name": "right", "ankle": ankle, "planned": planned, "error_mm": (ankle - planned).length() * 1000.0, "planted": planted, "weight": weight, "source": source, "plan_ok": true}

func _hand(weight: float, unreachable: bool, margin_cm: float, error_mm := 0.0, target := Vector3(0.2, 1.0, 0.3)) -> Dictionary:
	return {"name": "left", "target": target, "wrist": target + Vector3(error_mm / 1000.0, 0, 0), "error_mm": error_mm, "reach_margin_cm": margin_cm, "arm_cm": 50.0, "unreachable": unreachable, "weight": weight, "owner": "contact claim"}

func _kinds(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return String(e.kind))

func _count(events: Array, kind: String) -> int:
	return _kinds(events).count(kind)

func _first(events: Array, kind: String) -> Dictionary:
	for e: Dictionary in events:
		if e.kind == kind:
			return e
	return {}

# ---- 1

func _plant_rows(fps: float, drift_mm_total: float, settle := false) -> Array:
	var dt := 1.0 / fps
	var rows := []
	var frames := int(fps)   # one second
	for i in frames:
		var f := float(i) / float(frames - 1)
		var planned := Vector3(0.1, 0.5, 0.2)
		var offset := Vector3(drift_mm_total / 1000.0 * f, 0, 0)
		if settle:
			offset = Vector3(0.03 * (1.0 - f), 0, 0)   # 30 mm off at the start, closing to zero
		rows.append(_row(i, dt, {"feet": [_foot(true, 1.0, planned + offset, planned)]}))
	return rows

func _foot_slide() -> void:
	var slid := TimelineAnalysis.analyze(_plant_rows(60.0, 25.0))
	var slide := _first(slid.events, "plant_slide")
	check(not slide.is_empty() and absf(float(slide.value) - 25.0) < 0.5, "a planted ankle drifting 25 mm against its foothold is a plant_slide of 25 mm (got %s)" % [slide.get("value")])
	check(absf(float(slid.metrics["foot.right.worst_slide_mm"].value) - 25.0) < 0.5, "the metric says 25 mm")
	var still := TimelineAnalysis.analyze(_plant_rows(60.0, 0.0))
	check(_count(still.events, "plant_slide") == 0 and _count(still.events, "plant_settle") == 0 and float(still.metrics["foot.right.worst_slide_mm"].value) < 0.5, "normal case: a still planted ankle is not accused")
	var settled := TimelineAnalysis.analyze(_plant_rows(60.0, 0.0, true))
	check(_count(settled.events, "plant_settle") == 1 and _count(settled.events, "plant_slide") == 0, "an ankle that closes in on its foothold is a plant_settle, not a slide (events %s)" % [_kinds(settled.events)])
	check(float(settled.metrics["foot.right.worst_slide_mm"].value) < 0.5 and float(settled.metrics["foot.right.worst_settle_mm"].value) > 25.0, "and the metrics keep the two apart")
	var swing := _plant_rows(60.0, 40.0)
	for row in swing:
		row.feet[0].planted = false   # the plan does not claim it planted: nothing to slide against
	check(_count(TimelineAnalysis.analyze(swing).events, "plant_slide") == 0, "a foot the plan does not claim planted is never reported as sliding")

# ---- 2

## A wrist on a smooth fast arc (sine, 2 m/s peak) with an optional one-frame jump at `jump_at`.
func _arc_rows(fps: float, jump_at := -1, jump_cm := 0.0, paused_at := -1) -> Array:
	var dt := 1.0 / fps
	var rows := []
	var x := 0.0
	for i in 90:
		x += 1.0 * sin(float(i) / 90.0 * PI) * dt * 2.0
		if i == jump_at:
			x += jump_cm / 100.0
		var this_dt := dt
		var row := _row(i, this_dt, {"bones": {"wrist": Vector3(x, 1.0, 0.0)}})
		if i == paused_at:
			row.dt = 0.0
		rows.append(row)
	return rows

func _snapping() -> void:
	var clean := TimelineAnalysis.analyze(_arc_rows(60.0))
	check(_count(clean.events, "pose_snap") == 0, "normal case: a smooth fast arc is not a snap (%s)" % [_kinds(clean.events)])
	var snapped := TimelineAnalysis.analyze(_arc_rows(60.0, 40, 8.0))
	var snap := _first(snapped.events, "pose_snap")
	check(not snap.is_empty() and absf(float(snap.value) - 8.0) < 0.6 and int(snap.n0) == 40, "an 8 cm jump at row 40 is one pose_snap of about 8 cm at row 40 (got %s at %s)" % [snap.get("value"), snap.get("n0")])
	check(_count(snapped.events, "pose_snap") == 1, "and exactly one")
	check(float(snapped.metrics["discontinuity.worst_step_cm"].value) > 7.0 and float(clean.metrics["discontinuity.worst_step_cm"].value) == 0.0, "the metric separates the two runs")
	# A paused row (no time elapsed) has no speed: a pause is not a snap, and a step after a pause is judged by its own time.
	var paused := TimelineAnalysis.analyze(_arc_rows(60.0, -1, 0.0, 45))
	check(_count(paused.events, "pose_snap") == 0, "a row with no elapsed time (a paused step) is not a snap")
	var small := TimelineAnalysis.analyze(_arc_rows(60.0, 40, 0.5))
	check(_count(small.events, "pose_snap") == 0, "a 5 mm step stays below the snap threshold (4 cm beyond the neighbouring motion): the values decide what is reported, and the threshold is stated")
	# A hard but CONTINUOUS kink (a hand moving at 2 m/s that stops within one frame: 3.3 cm of excess at 60 fps) is not a pop: positions never jump, they only stop quickly.
	var stop := []
	for i in 60:
		stop.append(_row(i, 1.0 / 60.0, {"bones": {"hand": Vector3(minf(float(i), 30.0) * 2.0 / 60.0, 1.0, 0.0)}}))
	check(_count(TimelineAnalysis.analyze(stop).events, "pose_snap") == 0, "a continuous hard stop (2 m/s to 0 in one frame) is not reported as a snap")
	# A body that is carried (the root moves, the bones follow) is a smooth move, and one that teleports is a snap of the root and every bone with it.
	var carried := []
	var teleport := []
	for i in 60:
		var at := Vector3(float(i) * 0.02, 0, 0)
		carried.append(_row(i, 1.0 / 60.0, {"root": at, "bones": {"hips": Vector3(0, 1, 0), "head": Vector3(0, 1.6, 0)}}))
		var jump := Vector3(float(i) * 0.02 + (0.4 if i >= 30 else 0.0), 0, 0)
		teleport.append(_row(i, 1.0 / 60.0, {"root": jump, "bones": {"hips": Vector3(0, 1, 0), "head": Vector3(0, 1.6, 0)}}))
	check(_count(TimelineAnalysis.analyze(carried).events, "pose_snap") == 0, "normal case: a body walking at 1.2 m/s is not a snap")
	var teleported := TimelineAnalysis.analyze(teleport)
	var group := _first(teleported.events, "pose_snap")
	check(not group.is_empty() and int(group.detail.count) == 3 and absf(float(group.value) - 40.0) < 1.0, "a 40 cm teleport is one pose_snap of root, hips and head together (%s)" % [group.get("detail", {}).get("count")])

# ---- 3

func _grouping() -> void:
	var rows := []
	for i in 40:
		var bones := {}
		for name in ["a", "b", "c", "d", "e"]:
			bones[name] = Vector3(0.0 if i < 20 else 0.2, 1.0, 0.0)
		rows.append(_row(i, 1.0 / 60.0, {"bones": bones}))
	var result := TimelineAnalysis.analyze(rows)
	check(_count(result.events, "pose_snap") == 1 and int(_first(result.events, "pose_snap").detail.count) == 5, "five bones jumping at once are ONE pose snap (%d events)" % _count(result.events, "pose_snap"))
	check(float(result.metrics["discontinuity.count"].value) == 1.0, "and one moment in the metric")
	# The same defect four times in a run is one finding that lists its occurrences.
	var repeated := []
	for i in 240:
		var jump := 0.0
		for at in [40, 90, 140, 190]:
			if i >= at:
				jump += 0.08
		repeated.append(_row(i, 1.0 / 60.0, {"bones": {"shin": Vector3(jump + (0.0 if (i % 50) > 3 else 0.0), 1.0, 0.0)}}))
	var analysed := TimelineAnalysis.analyze(repeated)
	var findings := Findings.build(analysed.events, repeated, {"scenario": "synthetic", "character": "none", "command": ""}, {"shin": "right shin"})
	check(findings.size() == 1 and int(findings[0].observation.facts.get("occurrence_count", 0)) == 4, "four recurrences are one finding with four occurrences (%d findings)" % findings.size())
	check(findings.size() == 1 and String(findings[0].title).contains("4 times") and (findings[0].observation.facts.occurrences as Array).size() == 4, "its title says how many times and the occurrences are listed")

# ---- 4

func _contacts() -> void:
	var rows := []
	for i in 120:
		var weight := 0.0
		if i >= 30 and i < 90:
			weight = 1.0
		var unreachable := i >= 50 and i < 70
		rows.append(_row(i, 1.0 / 60.0, {"hands": [_hand(weight, unreachable or (i >= 5 and i < 10), -12.0 if unreachable else 8.0, 3.0)]}))
	var result := TimelineAnalysis.analyze(rows)
	check(_count(result.events, "contact_acquired") == 1 and int(_first(result.events, "contact_acquired").n0) == 30, "a contact claimed at row 30 is acquired at row 30")
	check(_count(result.events, "contact_released") == 1 and int(_first(result.events, "contact_released").n0) == 90, "and released at row 90")
	var reach := _first(result.events, "reach_exceeded")
	check(not reach.is_empty() and int(reach.n0) == 50 and int(reach.n1) == 69 and absf(float(reach.value) - 12.0) < 0.01, "the 12 cm of reach deficit while claimed is one reach_exceeded over rows 50 to 69")
	check(_count(result.events, "reach_exceeded") == 1, "an unreachable target while NO contact claims it (rows 5 to 9) is not reported: there is no contact to be out of reach")
	check(absf(float(result.metrics["hand.left.worst_deficit_cm"].value) - 12.0) < 0.01 and absf(float(result.metrics["hand.left.unreachable_s"].value) - 20.0 / 60.0) < 0.01, "the metrics: 12 cm, a third of a second")
	var misses := []
	for i in 60:
		misses.append(_row(i, 1.0 / 60.0, {"hands": [_hand(1.0, false, 10.0, 34.0 if i >= 20 and i < 40 else 2.0)]}))
	var missed := TimelineAnalysis.analyze(misses)
	check(_count(missed.events, "target_error") == 1 and absf(float(_first(missed.events, "target_error").value) - 34.0) < 0.1, "a wrist 34 mm off a reachable target while held is a target_error of 34 mm (the overlay's 20 mm line)")
	check(float(TimelineAnalysis.analyze(misses.slice(0, 20)).metrics["hand.left.worst_error_mm"].value) < 3.0 and _count(TimelineAnalysis.analyze(misses.slice(0, 20)).events, "target_error") == 0, "normal case: 2 mm is not an error")

# ---- 5

func _ownership() -> void:
	var rows := []
	for i in 60:
		rows.append(_row(i, 1.0 / 60.0, {"state": "idle" if i < 20 else "move", "context": "free" if i < 40 else "ladder", "stages": [] if i < 30 else ["Traversal"]}))
	var result := TimelineAnalysis.analyze(rows)
	check(_count(result.events, "state_changed") == 1 and int(_first(result.events, "state_changed").n0) == 20, "the animation state change is an event at the row it happened")
	check(_count(result.events, "context_changed") == 1 and _first(result.events, "context_changed").detail.to == "ladder", "the change of context (free to ladder) is an event")
	check(_count(result.events, "stage_engaged") == 1 and _first(result.events, "stage_engaged").subject == "Traversal", "a pose stage becoming engaged is an event naming the stage")

# ---- 6

func _retarget() -> void:
	var held := []
	var moved := []
	for i in 80:
		var wrist_x := 0.0 if i < 40 else 0.12
		var target_held := Vector3(0.2, 1.0, 0.3)
		var target_moved := Vector3(0.2 + wrist_x, 1.0, 0.3)
		held.append(_row(i, 1.0 / 60.0, {"bones": {"hand": Vector3(wrist_x, 1.0, 0.0)}, "hands": [_hand(1.0, false, 10.0, 0.0, target_held)]}))
		moved.append(_row(i, 1.0 / 60.0, {"bones": {"hand": Vector3(wrist_x, 1.0, 0.0)}, "hands": [_hand(1.0, false, 10.0, 0.0, target_moved)]}))
	var names := {"hand": "left hand"}
	var config := {"scenario": "synthetic", "character": "none", "command": ""}
	var a := TimelineAnalysis.analyze(held)
	var b := TimelineAnalysis.analyze(moved)
	var fa := Findings.build(a.events, held, config, names)
	var fb := Findings.build(b.events, moved, config, names)
	check(fa.size() == 1 and String(fa[0].observation.text).contains("did not jump") and not bool(fa[0].observation.facts.targets_jumped.size() > 0), "a pose snap while its target held still says the pose itself changed (%s)" % [fa[0].observation.text if not fa.is_empty() else "no finding"])
	check(fb.size() == 1 and String(fb[0].observation.text).contains("followed a retarget") and _count(b.events, "target_jump") == 1, "a pose snap while its target jumped too says the pose followed a retarget")

# ---- 7

func _frame_rate() -> void:
	var at60 := TimelineAnalysis.analyze(_plant_rows(60.0, 25.0))
	var at30 := TimelineAnalysis.analyze(_plant_rows(30.0, 25.0))
	check(absf(float(at60.metrics["foot.right.worst_slide_mm"].value) - float(at30.metrics["foot.right.worst_slide_mm"].value)) < 1.0, "the same 25 mm of slide reads the same at 30 and 60 fps (%.1f, %.1f)" % [float(at60.metrics["foot.right.worst_slide_mm"].value), float(at30.metrics["foot.right.worst_slide_mm"].value)])
	for fps in [30.0, 60.0, 120.0]:
		var result := TimelineAnalysis.analyze(_arc_rows(fps, 40, 8.0))
		check(_count(result.events, "pose_snap") == 1, "an 8 cm jump is found at %.0f fps" % fps)
	check((TimelineAnalysis.analyze(_arc_rows(60.0, 40, 8.0)).metrics["discontinuity.worst_speed_mps"].tags as Array).has("frame_rate"), "and the snap's speed is tagged frame_rate, so a comparison refuses to compare it across frame rates")

# ---- 8

func _findings() -> void:
	var rows := []
	for i in 120:
		var weight := 1.0
		rows.append(_row(i, 1.0 / 60.0, {"hands": [_hand(weight, i >= 50 and i < 70, -12.0 if i >= 50 and i < 70 else 8.0, 400.0 if i >= 50 and i < 70 else 0.0)], "feet": [_foot(true, 1.0, Vector3(0.0 + (0.03 if i >= 40 else 0.0) * float(i) / 120.0, 0.5, 0.2), Vector3(0.0, 0.5, 0.2))]}))
	var analysed := TimelineAnalysis.analyze(rows)
	var findings := Findings.build(analysed.events, rows, {"scenario": "synthetic", "character": "none", "command": "cmd"}, {})
	check(findings.size() >= 1, "the injected defects produce findings")
	var honest := true
	var detailed := true
	for f: Dictionary in findings:
		honest = honest and f.cause == "unknown"
		for h: Dictionary in f.hypotheses:
			honest = honest and h.status == "unconfirmed" and String(h.basis) != "" and String(h.experiment) != ""
		detailed = detailed and (f.evidence.kinds as Array).size() > 0 and (f.evidence.does_not_establish as Array).size() > 0 and f.key != "" and f.id != "" and f.reproduce.has("replay")
	check(honest, "every finding says the cause is unknown and every hypothesis is unconfirmed, with its basis and an experiment")
	check(detailed, "every finding carries a stable key, an id, its measurement kinds, what they do not establish and how to reproduce it")
	var reach := findings.filter(func(f: Dictionary) -> bool: return f.kind == "reach_exceeded")
	check(reach.size() == 1 and String(reach[0].observation.text).contains("12.0 cm") and String(reach[0].observation.text).contains("400 mm"), "the reach finding states the deficit and where the wrist ended (%s)" % [reach[0].observation.text if not reach.is_empty() else ""])
	var none := Findings.build([], [], {}, {})
	check(Findings.headline(none).contains("not proof"), "no findings is not reported as 'fine': the headline says it is not proof")
	var text := Findings.explain(findings[0], false)
	check(text.contains("NOT confirmed") or text.contains("unknown"), "the plain text says what is unconfirmed or unknown")
