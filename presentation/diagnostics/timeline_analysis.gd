class_name TimelineAnalysis
extends RefCounted
## Turns SessionRecorder rows into EVENTS (what happened and when) and METRICS (the numbers a comparison uses). Pure functions over plain data: no rig, no scene, no clock, so a synthetic recording can be fed in
## on purpose (the negative controls) and the same rows always give the same answer.
##
## Every event is an OBSERVATION about the rows: it says what the recorded numbers did, never why. The thresholds are the project's own display conventions where one exists (20 mm hand, 30 mm foot: the overlay's
## red line; 97% of the arm: ContactErrorDiagnostics.REACH_LIMIT_FRACTION) and otherwise stated heuristics (a snap is a speed far above the neighbouring frames). A threshold decides what gets REPORTED, not what is
## "wrong": the values are in the event.
##
## Event record: {kind, subject, n0, n1, t0, t1, st0, value, unit, detail, worst_n}. n is the recorder's row number, t presenter seconds, st the scenario clock (-1 when none).
## Kinds: pose_snap (grouped from per-bone discontinuity events), contact_acquired, contact_released, foot_planted, foot_released, reach_exceeded, target_error, plant_slide, plant_settle, plant_offset, discontinuity, target_jump, state_changed, stage_engaged, stage_released, context_changed, mesh_overlap.

const CONTACT_ON := 0.5          # a claimed contact weight at or above this counts as "in contact" for acquisition and release
const CONTACT_HELD := 0.9        # at or above this the plan has hold of the limb (the ramps at either end follow the clip, not the plan)
const HAND_ERROR_MM := 20.0      # the contact overlay's red line
const FOOT_ERROR_MM := 30.0
const SLIDE_MM := 15.0           # how far an ankle may move against its own foothold while the plan claims it planted, before it is reported
const SNAP_FACTOR := 0.5         # a step is a snap when its velocity departs from the neighbouring frames' median velocity by more than this fraction of that velocity ...
const SNAP_FLOOR_MPS := 1.0      # ... plus this much (so a fast curved swing is not reported). Frame-rate sensitive by nature: 1 m/s is 1.7 cm in a 60 fps step, 3.3 cm at 30 fps.
const SNAP_MIN_M := 0.04         # ... and the step must be at least this far (4 cm) beyond what the neighbouring frames predict: a hard but continuous kink (a foot stopping in a frame) is not a pop
const SNAP_WINDOW := 3
const MIN_SPAN_FRAMES := 1

static func analyze(rows: Array) -> Dictionary:
	var events: Array[Dictionary] = []
	var metrics := {}
	if rows.is_empty():
		return {"events": events, "metrics": metrics}
	_transitions(rows, events)
	_contacts(rows, events, metrics)
	_feet(rows, events, metrics)
	_snaps(rows, events, metrics)
	_mesh(rows, events, metrics)
	var last: Dictionary = rows.back()
	var first: Dictionary = rows.front()
	var root_speed := 0.0
	for i in range(1, rows.size()):
		var dt := float(rows[i].dt)
		if dt > 0.0:
			root_speed = maxf(root_speed, ((rows[i].root as Vector3) - (rows[i - 1].root as Vector3)).length() / dt)
	_metric(metrics, "duration_s", float(last.t) - float(first.t), "s", "none", [], 0.05, "recorded time")
	_metric(metrics, "root.max_speed_mps", root_speed, "m/s", "none", ["rate"], 0.05, "fastest the root travelled")
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.n0) < int(b.n0))
	var counts := {}
	for event in events:
		counts[event.kind] = int(counts.get(event.kind, 0)) + 1
	return {"events": events, "metrics": metrics, "counts": counts}

static func _metric(metrics: Dictionary, key: String, value: float, unit: String, better: String, tags: Array, noise: float, label: String) -> void:
	metrics[key] = {"value": snappedf(value, 0.0001), "unit": unit, "better": better, "tags": tags, "noise": noise, "label": label}

static func _event(kind: String, subject: String, rows: Array, i0: int, i1: int, value: Variant, unit: String, detail: Dictionary, worst: int = -1) -> Dictionary:
	return {"kind": kind, "subject": subject, "n0": int(rows[i0].n), "n1": int(rows[i1].n), "t0": float(rows[i0].t), "t1": float(rows[i1].t), "st0": float(rows[i0].st), "value": value, "unit": unit, "detail": detail,
		"worst_n": int(rows[worst if worst >= 0 else i0].n)}

# ---- state, stage and context changes (who owns the body, when)

static func _transitions(rows: Array, events: Array[Dictionary]) -> void:
	for i in range(1, rows.size()):
		var a: Dictionary = rows[i - 1]
		var b: Dictionary = rows[i]
		if String(a.get("state", "")) != String(b.get("state", "")):
			events.append(_event("state_changed", "animation state", rows, i, i, String(b.state), "", {"from": String(a.get("state", "")), "to": String(b.state)}))
		if String(a.get("context", "")) != String(b.get("context", "")):
			events.append(_event("context_changed", "body context", rows, i, i, String(b.context), "", {"from": String(a.get("context", "")), "to": String(b.context)}))
		var before: Array = a.get("stages", [])
		var after: Array = b.get("stages", [])
		for stage in after:
			if not before.has(stage):
				events.append(_event("stage_engaged", String(stage), rows, i, i, 1.0, "", {"stage": String(stage)}))
		for stage in before:
			if not after.has(stage):
				events.append(_event("stage_released", String(stage), rows, i, i, 0.0, "", {"stage": String(stage)}))

# ---- hands: contact acquisition and release, reach, target error

static func _contacts(rows: Array, events: Array[Dictionary], metrics: Dictionary) -> void:
	for side in ["left", "right"]:
		var held := false
		var reach_from := -1
		var reach_worst := 0.0
		var reach_worst_at := -1
		var error_from := -1
		var error_worst := 0.0
		var error_worst_at := -1
		var worst_reachable := 0.0
		var unreachable_s := 0.0
		var held_s := 0.0
		var worst_deficit := 0.0
		for i in rows.size():
			var hand := _side(rows[i].get("hands", []), side)
			var weight := float(hand.get("weight", 0.0))
			var in_contact := weight >= CONTACT_ON
			if not hand.is_empty() and in_contact != held:
				events.append(_event("contact_acquired" if in_contact else "contact_released", "%s hand" % side, rows, i, i, snappedf(weight, 0.001), "weight", {"owner": String(hand.get("owner", "")), "error_mm": snappedf(float(hand.error_mm), 0.1)}))
			held = in_contact and not hand.is_empty()
			var dt := float(rows[i].dt)
			var holding := weight >= CONTACT_HELD
			var unreachable := bool(hand.get("unreachable", false)) and weight >= CONTACT_ON
			if holding:
				held_s += dt
			if unreachable:
				unreachable_s += dt
				var deficit := -float(hand.reach_margin_cm)
				worst_deficit = maxf(worst_deficit, deficit)
				if reach_from < 0:
					reach_from = i
					reach_worst = 0.0
				if deficit > reach_worst:
					reach_worst = deficit
					reach_worst_at = i
			elif reach_from >= 0:
				events.append(_event("reach_exceeded", "%s hand" % side, rows, reach_from, i - 1, snappedf(reach_worst, 0.01), "cm", _hand_detail(rows[reach_worst_at], side), reach_worst_at))
				reach_from = -1
			var error_mm := float(hand.get("error_mm", 0.0))
			if holding and not unreachable:
				worst_reachable = maxf(worst_reachable, error_mm)
			if holding and not unreachable and error_mm > HAND_ERROR_MM:
				if error_from < 0:
					error_from = i
					error_worst = 0.0
				if error_mm > error_worst:
					error_worst = error_mm
					error_worst_at = i
			elif error_from >= 0:
				events.append(_event("target_error", "%s hand" % side, rows, error_from, i - 1, snappedf(error_worst, 0.1), "mm", _hand_detail(rows[error_worst_at], side), error_worst_at))
				error_from = -1
		if reach_from >= 0:
			events.append(_event("reach_exceeded", "%s hand" % side, rows, reach_from, rows.size() - 1, snappedf(reach_worst, 0.01), "cm", _hand_detail(rows[reach_worst_at], side), reach_worst_at))
		if error_from >= 0:
			events.append(_event("target_error", "%s hand" % side, rows, error_from, rows.size() - 1, snappedf(error_worst, 0.1), "mm", _hand_detail(rows[error_worst_at], side), error_worst_at))
		if _has_side(rows, "hands", side):
			_metric(metrics, "hand.%s.worst_error_mm" % side, worst_reachable, "mm", "lower", ["length"], 0.5, "%s hand: worst wrist-to-target error while holding a reachable target" % side)
			_metric(metrics, "hand.%s.unreachable_s" % side, unreachable_s, "s", "lower", ["time"], 0.05, "%s hand: time the target was beyond 97%% of the arm while in contact" % side)
			_metric(metrics, "hand.%s.worst_deficit_cm" % side, worst_deficit, "cm", "lower", ["length"], 0.2, "%s hand: how far beyond the arm's reach the target was, at worst" % side)
			_metric(metrics, "hand.%s.held_s" % side, held_s, "s", "none", ["time"], 0.05, "%s hand: time a contact had hold of it" % side)

static func _hand_detail(row: Dictionary, side: String) -> Dictionary:
	var hand := _side(row.get("hands", []), side)
	return {"owner": String(hand.get("owner", "")), "weight": snappedf(float(hand.get("weight", 0.0)), 0.001), "error_mm": snappedf(float(hand.get("error_mm", 0.0)), 0.1), "reach_margin_cm": snappedf(float(hand.get("reach_margin_cm", 0.0)), 0.01),
		"arm_cm": snappedf(float(hand.get("arm_cm", 0.0)), 0.01), "stages": row.get("stages", []), "context": row.get("context", "")}

# ---- feet: planted spans, slide against the foothold, error

static func _feet(rows: Array, events: Array[Dictionary], metrics: Dictionary) -> void:
	for side in ["left", "right"]:
		if not _has_side(rows, "feet", side):
			continue
		var span := {"from": -1}
		var worst_slide_all := 0.0
		var worst_settle_all := 0.0
		var worst_error := 0.0
		var planted_s := 0.0
		var planted_now := false
		for i in rows.size():
			var foot := _side(rows[i].get("feet", []), side)
			var claimed := not foot.is_empty() and bool(foot.planted) and float(foot.weight) >= CONTACT_ON
			if claimed != planted_now:
				events.append(_event("foot_planted" if claimed else "foot_released", "%s foot" % side, rows, i, i, snappedf(float(foot.get("weight", 0.0)), 0.001), "weight", {"source": String(foot.get("source", ""))}))
			planted_now = claimed
			var holding := claimed and float(foot.weight) >= CONTACT_HELD
			if holding:
				planted_s += float(rows[i].dt)
				worst_error = maxf(worst_error, float(foot.error_mm))
				var offset: Vector3 = (foot.ankle as Vector3) - (foot.planned as Vector3)
				if int(span.from) < 0 or String(foot.source) != String(span.get("source", "")):
					var closed := _close_span(span, rows, side, events, i - 1)
					worst_slide_all = maxf(worst_slide_all, closed[0])
					worst_settle_all = maxf(worst_settle_all, closed[1])
					span = {"from": i, "source": String(foot.source), "reference": offset, "worst": 0.0, "at": i, "start_error": float(foot.error_mm), "end_error": float(foot.error_mm), "worst_error": float(foot.error_mm), "error_at": i}
				else:
					var moved := (offset - (span.reference as Vector3)).length() * 1000.0
					span["end_error"] = float(foot.error_mm)
					if float(foot.error_mm) > float(span.worst_error):
						span["worst_error"] = float(foot.error_mm)
						span["error_at"] = i
					if moved > float(span.worst):
						span["worst"] = moved
						span["at"] = i
			else:
				var closed := _close_span(span, rows, side, events, i - 1)
				worst_slide_all = maxf(worst_slide_all, closed[0])
				worst_settle_all = maxf(worst_settle_all, closed[1])
				span = {"from": -1}
		var final_closed := _close_span(span, rows, side, events, rows.size() - 1)
		worst_slide_all = maxf(worst_slide_all, final_closed[0])
		worst_settle_all = maxf(worst_settle_all, final_closed[1])
		_metric(metrics, "foot.%s.worst_slide_mm" % side, worst_slide_all, "mm", "lower", ["length"], 1.0, "%s foot: most the ankle moved against its foothold while the plan claimed it planted (not counting settling onto the plan)" % side)
		_metric(metrics, "foot.%s.worst_settle_mm" % side, worst_settle_all, "mm", "lower", ["length", "frame_rate"], 1.0, "%s foot: how far from its foothold the ankle still was when the plan took full hold, before it closed in" % side)
		_metric(metrics, "foot.%s.worst_error_mm" % side, worst_error, "mm", "lower", ["length", "frame_rate"], 0.5, "%s foot: worst ankle-to-foothold error while the plan held the leg (the first held frame is sampled, so it depends on the frame step)" % side)
		_metric(metrics, "foot.%s.planted_s" % side, planted_s, "s", "none", ["time"], 0.05, "%s foot: time the plan held it planted" % side)

## Ends a planted span: a plant_slide event when the ankle moved against its foothold at a roughly constant error, a plant_settle event when it was off the foothold at the start and closed in (the plan took hold before
## the ankle arrived). Returns [slide_mm, settle_mm] for the metrics.
static func _close_span(span: Dictionary, rows: Array, side: String, events: Array[Dictionary], last_row: int) -> Array[float]:
	var result: Array[float] = [0.0, 0.0]
	if int(span.from) < 0 or last_row < int(span.from):
		return result
	var worst := float(span.worst)
	var start_error := float(span.start_error)
	var end_error := float(span.end_error)
	var settling := start_error >= SLIDE_MM * 0.8 and end_error <= start_error * 0.5
	var detail := _foot_detail(rows[int(span.at)], side)
	detail["error_start_mm"] = snappedf(start_error, 0.1)
	detail["error_end_mm"] = snappedf(end_error, 0.1)
	if settling:
		result[1] = start_error
		events.append(_event("plant_settle", "%s foot" % side, rows, int(span.from), last_row, snappedf(start_error, 0.1), "mm", detail, int(span.from)))
	else:
		result[0] = worst
		if worst > SLIDE_MM:
			events.append(_event("plant_slide", "%s foot" % side, rows, int(span.from), last_row, snappedf(worst, 0.1), "mm", detail, int(span.at)))
		# A foot the plan holds that does not arrive and does not close in: off its foothold by more than the foot tolerance for the whole span (a slow drift moves little within a span, so it is no slide, but it ends far off).
		if float(span.worst_error) > FOOT_ERROR_MM and end_error > FOOT_ERROR_MM:
			var offset_detail := _foot_detail(rows[int(span.error_at)], side)
			offset_detail["error_start_mm"] = snappedf(start_error, 0.1)
			offset_detail["error_end_mm"] = snappedf(end_error, 0.1)
			events.append(_event("plant_offset", "%s foot" % side, rows, int(span.from), last_row, snappedf(float(span.worst_error), 0.1), "mm", offset_detail, int(span.error_at)))
	return result

static func _foot_detail(row: Dictionary, side: String) -> Dictionary:
	var foot := _side(row.get("feet", []), side)
	return {"source": String(foot.get("source", "")), "weight": snappedf(float(foot.get("weight", 0.0)), 0.001), "error_mm": snappedf(float(foot.get("error_mm", 0.0)), 0.1), "stages": row.get("stages", []), "context": row.get("context", "")}

# ---- snapping: the pose (achieved) against the targets (intended)

static func _snaps(rows: Array, events: Array[Dictionary], metrics: Dictionary) -> void:
	var series: Array[Dictionary] = []
	series.append({"subject": "root", "read": func(r: Dictionary) -> Variant: return r.get("root")})
	for bone_key in _bone_keys(rows):
		series.append({"subject": bone_key, "read": func(r: Dictionary) -> Variant:
			var local: Variant = (r.get("bones", {}) as Dictionary).get(bone_key)
			return world_of(r, local) if local != null else null})   # what the eye sees: the root's own motion is added back, so a body that is carried or turned is not a snap
	var spikes: Array[Dictionary] = []
	for entry in series:
		for spike in _spikes(rows, entry.read):
			spike["subject"] = entry.subject
			spikes.append(spike)
			events.append(_event("discontinuity", String(entry.subject), rows, int(spike.i), int(spike.i), snappedf(float(spike.step) * 100.0, 0.1), "cm", {"speed_mps": snappedf(float(spike.speed), 0.01), "neighbour_speed_mps": snappedf(float(spike.median), 0.01),
				"stages": rows[int(spike.i)].get("stages", []), "context": rows[int(spike.i)].get("context", "")}))
	# One POSE SNAP per moment: a body that pops moves dozens of bones in the same frame, and thirty findings for one pop would hide it. Spikes at adjacent rows are one moment.
	spikes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.i) < int(b.i))
	var worst_step := 0.0
	var worst_speed := 0.0
	var group: Array[Dictionary] = []
	var groups: Array = []
	for spike in spikes:
		if not group.is_empty() and int(spike.i) - int(group.back().i) > 2:
			groups.append(group)
			group = []
		group.append(spike)
	if not group.is_empty():
		groups.append(group)
	for all_spikes: Array in groups:
		all_spikes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.step) > float(b.step))
		var members: Array[Dictionary] = []   # one entry per bone (its biggest step): a glitch that goes out and comes back is two spikes of one bone
		var seen := {}
		for spike in all_spikes:
			if not seen.has(spike.subject):
				seen[spike.subject] = true
				members.append(spike)
		var top: Dictionary = members[0]
		var listed := []
		for k in mini(members.size(), 8):
			listed.append({"subject": String(members[k].subject), "step_cm": snappedf(float(members[k].step) * 100.0, 0.1), "speed_mps": snappedf(float(members[k].speed), 0.01), "neighbour_speed_mps": snappedf(float(members[k].median), 0.01)})
		var first := 1 << 30
		var last := -1
		for member in all_spikes:
			first = mini(first, int(member.i))
			last = maxi(last, int(member.i))
		worst_step = maxf(worst_step, float(top.step) * 100.0)
		worst_speed = maxf(worst_speed, float(top.speed))
		events.append(_event("pose_snap", "pose snap", rows, first, last, snappedf(float(top.step) * 100.0, 0.1), "cm", {"count": members.size(), "rows_affected": last - first + 1, "subjects": listed, "worst_subject": String(top.subject),
			"stages": rows[int(top.i)].get("stages", []), "context": rows[int(top.i)].get("context", "")}, int(top.i)))
	# Retargets: an intended point (a contact target, a foothold) that jumped against its own neighbouring frames (the same test as a pose snap, so a swing trajectory is not a jump). Reported apart: a pose that
	# snaps while its target held still is a different thing from a target that was handed over.
	for side in ["left", "right"]:
		for kind in [["hands", "target", "hand target"], ["feet", "planned", "foothold"]]:
			var field: String = kind[1]
			var list_key: String = kind[0]
			var reader := func(r: Dictionary) -> Variant:
				var entry := _side(r.get(list_key, []), side)
				return entry.get(field) if not entry.is_empty() else null
			for spike in _spikes(rows, reader):
				events.append(_event("target_jump", "%s %s" % [side, kind[2]], rows, int(spike.i), int(spike.i), snappedf(float(spike.step) * 100.0, 0.1), "cm", {"context": rows[int(spike.i)].get("context", ""), "speed_mps": snappedf(float(spike.speed), 0.01)}))
	# The knee pole the traversal stage hands to the leg solver (recorded on a ladder): a knee that pops because its pole popped is a different statement from a knee that popped by itself.
	for idx in 2:
		var pole_reader := func(r: Dictionary) -> Variant:
			var poles: Array = (r.get("ladder", {}) as Dictionary).get("knee_poles", [])
			return poles[idx] if poles.size() > idx else null
		for spike in _spikes(rows, pole_reader):
			events.append(_event("target_jump", "%s knee pole" % ["left", "right"][idx], rows, int(spike.i), int(spike.i), snappedf(float(spike.step) * 100.0, 0.1), "cm", {"context": rows[int(spike.i)].get("context", ""), "speed_mps": snappedf(float(spike.speed), 0.01)}))
	# The carried passenger: a body that jumps against the carrier is an attachment break, whatever the carrier's own pose did.
	var passenger_reader := func(r: Dictionary) -> Variant:
		var carry: Dictionary = r.get("carry", {})
		return carry.get("passenger") if not carry.is_empty() else null
	for spike in _spikes(rows, passenger_reader):
		events.append(_event("target_jump", "passenger", rows, int(spike.i), int(spike.i), snappedf(float(spike.step) * 100.0, 0.1), "cm", {"context": rows[int(spike.i)].get("context", ""), "speed_mps": snappedf(float(spike.speed), 0.01)}))
	_metric(metrics, "discontinuity.count", float(groups.size()), "moments", "lower", ["frame_rate"], 0.0, "pose snaps: moments when a bone moved far faster than the frames around it")
	_metric(metrics, "discontinuity.worst_step_cm", worst_step, "cm", "lower", ["frame_rate", "length"], 0.5, "the largest one-frame step of any bone at a pose snap")
	_metric(metrics, "discontinuity.worst_speed_mps", worst_speed, "m/s", "lower", ["frame_rate"], 0.2, "the fastest snap")

## A recorded character-space point in the world (the row's own root position and heading).
static func world_of(row: Dictionary, local: Vector3) -> Vector3:
	return (row.get("root", Vector3.ZERO) as Vector3) + Basis(Vector3.UP, float(row.get("yaw", 0.0))) * local

static func _bone_keys(rows: Array) -> Array[String]:
	var keys: Array[String] = []
	for row in rows:
		for key in (row.get("bones", {}) as Dictionary):
			if not keys.has(String(key)):
				keys.append(String(key))
	return keys

## Steps that depart from the motion of the frames around them: [{i, step (m beyond what the neighbours predict), speed (m/s), median (m/s)}]. The test is on VELOCITY, not speed: a fast smooth swing has a velocity
## close to its neighbours' (component-wise median of the 3 frames either side), a snap does not. A row with no elapsed time (a paused step) has no velocity and is skipped.
static func _spikes(rows: Array, getter: Callable) -> Array[Dictionary]:
	var velocity: Array = []
	var dts: Array[float] = []
	velocity.resize(rows.size())
	dts.resize(rows.size())
	for i in rows.size():
		velocity[i] = null
		dts[i] = float(rows[i].dt)
		if i == 0 or dts[i] <= 0.0:
			continue
		var a: Variant = getter.call(rows[i - 1])
		var b: Variant = getter.call(rows[i])
		if a == null or b == null:
			continue
		velocity[i] = ((b as Vector3) - (a as Vector3)) / dts[i]
	var found: Array[Dictionary] = []
	for i in rows.size():
		if velocity[i] == null:
			continue
		var xs: Array[float] = []
		var ys: Array[float] = []
		var zs: Array[float] = []
		for j in range(maxi(i - SNAP_WINDOW, 0), mini(i + SNAP_WINDOW + 1, rows.size())):
			if j != i and velocity[j] != null:
				xs.append((velocity[j] as Vector3).x)
				ys.append((velocity[j] as Vector3).y)
				zs.append((velocity[j] as Vector3).z)
		if xs.size() < 3:
			continue
		xs.sort()
		ys.sort()
		zs.sort()
		var middle := xs.size() / 2
		var median := Vector3(xs[middle], ys[middle], zs[middle])
		var deviation := ((velocity[i] as Vector3) - median).length()
		if deviation * dts[i] >= SNAP_MIN_M and deviation > SNAP_FLOOR_MPS + SNAP_FACTOR * median.length():
			found.append({"i": i, "step": deviation * dts[i], "speed": (velocity[i] as Vector3).length(), "median": median.length()})
	return found

# ---- mesh overlap spans

static func _mesh(rows: Array, events: Array[Dictionary], metrics: Dictionary) -> void:
	var sampled := false
	var worst := 0
	var overlap_s := 0.0
	var from := -1
	var span_worst := 0
	var span_at := -1
	for i in rows.size():
		var mesh: Dictionary = rows[i].get("mesh", {})
		var usable := not mesh.is_empty() and String(mesh.get("status", "")) == "FRESH"
		if usable:
			sampled = true
		var count := int(mesh.get("count", 0)) if usable else 0
		if count > 0:
			overlap_s += float(rows[i].dt)
			worst = maxi(worst, count)
			if from < 0:
				from = i
				span_worst = 0
			if count > span_worst:
				span_worst = count
				span_at = i
		elif from >= 0 and usable:
			events.append(_event("mesh_overlap", "leg vertices against the ladder", rows, from, i - 1, span_worst, "vertices", {"top": rows[span_at].mesh.top, "threshold_mm": 3.0, "context": rows[span_at].get("context", ""), "ladder": rows[span_at].get("ladder", {})}, span_at))
			from = -1
	if from >= 0:
		events.append(_event("mesh_overlap", "leg vertices against the ladder", rows, from, rows.size() - 1, span_worst, "vertices", {"top": rows[span_at].mesh.top, "threshold_mm": 3.0, "context": rows[span_at].get("context", ""), "ladder": rows[span_at].get("ladder", {})}, span_at))
	if sampled:
		_metric(metrics, "mesh.worst_vertices", float(worst), "vertices", "lower", ["sampled"], 2.0, "most skinned leg vertices inside a ladder bar at once (sampled vertices, not a full intersection)")
		_metric(metrics, "mesh.overlap_s", overlap_s, "s", "lower", ["time"], 0.05, "time any sampled leg vertex was inside a ladder bar")

# ---- helpers

static func _side(list: Array, side: String) -> Dictionary:
	for entry: Dictionary in list:
		if String(entry.name) == side:
			return entry
	return {}

static func _has_side(rows: Array, key: String, side: String) -> bool:
	for row in rows:
		if not _side(row.get(key, []), side).is_empty():
			return true
	return false
