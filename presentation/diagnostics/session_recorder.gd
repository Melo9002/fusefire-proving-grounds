class_name SessionRecorder
extends RefCounted
## ADDA's temporal instrument: one row per rendered frame of what the skeleton actually showed, so a defect that lives in MOTION (a foot that slides, a wrist that snaps, a contact that arrives late) can be found in
## numbers instead of by watching. It is read-only and sits on the same PoseWitness as every other ADDA tool: a row is built only inside `final_pose`, so every bone in it is the final pose (see Measurement).
##
## WHAT A ROW HOLDS (all plain data, JSON-friendly after AddaReport.jsonable):
##   n, frame, update   the row number since recording began, the engine frame, the skeleton update it came from
##   t, dt              presenter seconds since the first row, and since the previous one (0 when the presenter did not tick: a paused step)
##   st                 the scenario clock from `clock`, or -1 (the clock is the host's; this class owns none)
##   state, context     the animation state and what the body is doing: free, ladder, stairs, carry
##   stages             the pose stages engaged right now (PoseStageReport: a weight above zero; interpretation, not a measured change)
##   root, yaw          character root, world
##   bones              the mapped bones' positions in CHARACTER space (x left, y up, z forward; the root's own frame, so root travel does not look like limb motion)
##   hands, feet        per side: the contact target or foothold (world), the final wrist or ankle (world), error, reach margin, claimed weight and owner (ContactErrorDiagnostics.measure)
##   ladder             climbed height, the rung each foot is planted on, swing, landing status (only on a ladder)
##   mesh               leg-vertex overlap with the ladder (only when mesh sampling is on: it costs about 3 ms a sample)
## One row per FRAME: the skeleton can update more than once in a frame and only the last update is what is drawn, so a later update replaces the earlier row of the same frame.
## It never writes to the rig, a modifier or a target. Costs are in docs/claude/adda/08-assignment-2-report.md.

signal row_recorded(row: Dictionary)

const SCHEMA := 1
const MAX_ROWS := 7200   # two minutes at 60 fps; older rows drop and `dropped` says how many

var rig: CharacterRig
var witness: PoseWitness
var rows: Array[Dictionary] = []
var markers: Array[Dictionary] = []
## Seconds of the host's scenario clock, or -1 when none runs. Set by the host (the workbench), because a scenario clock belongs to it.
var clock := Callable()
var recording := false
var dropped := 0
var mesh_every := 0
## True once mesh sampling has been on during this recording (stop() turns the sampler off, but the report must still say it was used).
var mesh_used := false
var _probe: ContactErrorDiagnostics
var _bone_names: Array[StringName] = []
var _extra: Array[StringName] = []
var _t0 := NAN
var _prev_t := NAN
var _counter := 0
var _mesh: LadderClearance
var _mesh_counter := 0
var _pending_mesh := {}

static func attach(p_rig: CharacterRig) -> SessionRecorder:
	if not is_instance_valid(p_rig) or p_rig.skeleton == null or p_rig.bones == null:
		return null
	var recorder := SessionRecorder.new()
	recorder.rig = p_rig
	recorder._probe = ContactErrorDiagnostics.new()   # never enters the tree: it is only the measure() function, called inside the final-pose window
	recorder._probe.rig = p_rig
	recorder._bone_names = _mapped_bones(p_rig)
	return recorder

static func _mapped_bones(p_rig: CharacterRig) -> Array[StringName]:
	var b := p_rig.bones
	var names: Array[StringName] = []
	for list in [[b.hips, b.spine, b.chest, b.neck, b.head, b.left_shoulder, b.right_shoulder, b.left_toes, b.right_toes], b.left_arm, b.right_arm, b.left_leg, b.right_leg]:
		for name: StringName in list:
			if name != &"" and p_rig.skeleton.find_bone(name) >= 0 and not names.has(name):
				names.append(name)
	return names

func start() -> void:
	if recording:
		return
	if not is_instance_valid(_probe):
		_probe = ContactErrorDiagnostics.new()
		_probe.rig = rig
	clear()
	witness = PoseWitness.acquire(rig.skeleton)
	witness.final_pose.connect(_on_final_pose)
	recording = true

## Stops and lets go of the witness (the skeleton carries no ADDA listener afterwards). The rows stay readable.
func stop() -> void:
	if recording:
		if witness != null and witness.final_pose.is_connected(_on_final_pose):
			witness.final_pose.disconnect(_on_final_pose)
		if witness != null:
			witness.release()
		witness = null
		recording = false
	disable_mesh()
	if is_instance_valid(_probe):
		_probe.free()
	_probe = null

## Empties the rows and starts the numbering again.
func clear() -> void:
	rows.clear()
	markers.clear()
	dropped = 0
	_counter = 0
	_t0 = NAN
	_prev_t = NAN
	_pending_mesh = {}
	mesh_used = mesh_every > 0

## Names a bone to record in addition to the mapped ones (a selection made in the inspector).
func watch_bone(bone: StringName) -> void:
	if rig.skeleton.find_bone(bone) >= 0 and not _bone_names.has(bone) and not _extra.has(bone):
		_extra.append(bone)

## Samples the leg vertices against the ladder every `every` rows (0 = off). Optional because the skinned-surface capture costs about 3 ms a sample.
func enable_mesh(every := 1) -> void:
	mesh_every = maxi(every, 1)
	mesh_used = true
	if _mesh == null:
		_mesh = LadderClearance.new(rig)
		_mesh.sampled.connect(_on_mesh_sampled)

func disable_mesh() -> void:
	mesh_every = 0
	if _mesh != null:
		if _mesh.sampled.is_connected(_on_mesh_sampled):
			_mesh.sampled.disconnect(_on_mesh_sampled)
		_mesh.release()
		_mesh = null

## A labelled moment (a scenario step, an experiment) on the same time axis as the rows.
func mark(label: String, kind := "marker") -> void:
	markers.append({"kind": kind, "label": label, "n": _counter, "t": _prev_t - _t0 if not is_nan(_prev_t) else 0.0, "st": _scenario_time()})

func latest() -> Dictionary:
	return rows.back() if not rows.is_empty() else {}

func is_clean() -> bool:
	return not recording and witness == null and _mesh == null

func _scenario_time() -> float:
	return float(clock.call()) if clock.is_valid() else -1.0

func _on_final_pose() -> void:
	if not is_instance_valid(rig) or rig.skeleton == null:
		return
	var stamp := witness.stamp()
	var presenter_time := float(rig.presenter.time) if rig.presenter != null else float(stamp.msec) * 0.001
	if is_nan(_t0):
		_t0 = presenter_time
	var replaced := not rows.is_empty() and int(rows.back().frame) == int(stamp.frame)
	if replaced:
		rows.pop_back()
	else:
		_counter += 1
	var row_t := presenter_time - _t0
	var row := {"n": _counter - 1, "frame": int(stamp.frame), "update": int(stamp.update), "t": row_t, "dt": 0.0 if rows.is_empty() else maxf(row_t - float(rows.back().t), 0.0), "st": _scenario_time(),
		"state": String(rig.animation_controller.current_state) if is_instance_valid(rig.animation_controller) else "", "context": _context(), "stages": _stages(),
		"root": rig.character_root.global_position, "yaw": rig.character_root.global_rotation.y, "bones": _bones()}
	var sample := _probe.measure() if is_instance_valid(_probe) else {}
	row["hands"] = _hands(sample)
	row["feet"] = _feet(sample)
	if rig.ladder != null and rig.ladder.pose != null and rig.ladder.pose.on_ladder:
		row["ladder"] = {"climbed": snappedf(rig.ladder.climbed, 0.0001), "foot_rung": [rig.ladder.pose.foot_rung[0], rig.ladder.pose.foot_rung[1]], "foot_swing": [snappedf(rig.ladder.pose.foot_swing[0], 0.001), snappedf(rig.ladder.pose.foot_swing[1], 0.001)],
			"landing": String(rig.ladder.landing_status), "knee_poles": _markers(rig.knee_poles), "foot_targets": _markers(rig.foot_targets)}
	_prev_t = presenter_time
	if int(_pending_mesh.get("update", -1)) == int(stamp.update):
		row["mesh"] = _pending_mesh.data
		_pending_mesh = {}
	rows.append(row)
	if rows.size() > MAX_ROWS:
		rows.pop_front()
		dropped += 1
	row_recorded.emit(row)

## World positions of the rig's IK helper nodes (the inputs the traversal stages feed the leg solver), read-only; empty when the rig has none.
func _markers(nodes: Array) -> Array:
	var out := []
	for node: Marker3D in nodes:
		if is_instance_valid(node):
			out.append(node.global_position)
	return out

func _context() -> String:
	if rig.ladder != null and rig.ladder.pose != null and rig.ladder.pose.on_ladder:
		return "ladder"
	if rig.stairs != null and rig.stairs.pose != null:
		return "stairs"
	if rig.interaction_active() or is_instance_valid(rig.carry_passenger):
		return "carry"
	return "free"

func _stages() -> Array[String]:
	var engaged: Array[String] = []
	for stage in PoseOwnership.STAGE_ORDER:
		if PoseStageReport.runtime_of(rig, stage).engaged:
			engaged.append(String(stage))
	return engaged

func _bones() -> Dictionary:
	var out := {}
	var to_root := rig.character_root.global_transform.affine_inverse() * rig.skeleton.global_transform
	for list in [_bone_names, _extra]:
		for name: StringName in list:
			var index := rig.skeleton.find_bone(name)
			if index >= 0:
				out[String(name)] = to_root * rig.skeleton.get_bone_global_pose(index).origin
	return out

func _hands(sample: Dictionary) -> Array:
	var out := []
	for hand: Dictionary in sample.get("hands", []):
		out.append({"name": hand.name, "target": hand.target, "wrist": hand.wrist, "error_mm": float(hand.error) * 1000.0, "reach_margin_cm": float(hand.reach_margin) * 100.0, "arm_cm": float(hand.arm_length) * 100.0,
			"unreachable": hand.unreachable, "weight": float(hand.weight), "owner": hand.owner})
	return out

func _feet(sample: Dictionary) -> Array:
	var out := []
	for foot: Dictionary in sample.get("feet", []):
		out.append({"name": foot.name, "ankle": foot.ankle, "planned": foot.planned, "error_mm": float(foot.error) * 1000.0, "planted": foot.planted, "weight": float(foot.weight), "source": foot.source, "plan_ok": foot.plan_ok})
	return out

func _on_mesh_sampled() -> void:
	if _mesh == null or rig.ladder == null or rig.ladder.geometry == null or not rig.ladder.pose.on_ladder:
		return
	_mesh_counter += 1
	if mesh_every > 1 and _mesh_counter % mesh_every != 0:
		return
	var verdict := _mesh.witness.judge(_mesh.stamp)
	var data := {}
	if verdict.status != Measurement.Status.FRESH:
		data = {"status": Measurement.Status.keys()[verdict.status], "reason": verdict.reason}
	else:
		var found := _mesh.offenders(rig.ladder.geometry, rig.ladder.climbed, 0.003, 100000)
		var top := []
		for i in mini(found.size(), 4):
			var f: Dictionary = found[i]
			var entry := {"bone": f.bone, "part": BodyParts.describe(rig, String(f.bone)).text, "bar": f.bar, "rung": f.rung, "depth_mm": snappedf(float(f.depth) * 1000.0, 0.1), "point": f.point}
			entry.merge(_bar_of(rig.ladder.geometry, rig.ladder.climbed, f), true)
			top.append(entry)
		data = {"status": "FRESH", "count": found.size(), "top": top, "threshold_mm": 3.0}
	var update := int(_mesh.stamp.update)
	if not rows.is_empty() and int(rows.back().update) == update:
		rows.back()["mesh"] = data
	else:
		_pending_mesh = {"update": update, "data": data}

## The bar a vertex is inside, as the environment (LadderGeometry) supplies it, in the character's frame: the axis (bar_a to bar_b), its radius, the point on the axis nearest the vertex, and the surface normal there
## (from that axis to the vertex). Nothing is invented: it is the cylinder the clearance test used.
static func _bar_of(geometry: LadderGeometry, climbed: float, offender: Dictionary) -> Dictionary:
	var down := Vector3(0.0, climbed, 0.0)   # ladder frame to character frame
	var half := geometry.rail_half_span()
	var a: Vector3
	var b: Vector3
	var radius: float
	if int(offender.rung) >= 0:
		var y := geometry.rung_height(int(offender.rung))
		a = Vector3(-half, y, geometry.plane_ahead) - down
		b = Vector3(half, y, geometry.plane_ahead) - down
		radius = geometry.rung_radius
	else:
		var side := 1.0 if String(offender.bar).begins_with("left") else -1.0
		a = Vector3(half * side, 0.0, geometry.plane_ahead) - down
		b = Vector3(half * side, geometry.rise, geometry.plane_ahead) - down
		radius = geometry.rail_radius
	var point: Vector3 = offender.point
	var axis := b - a
	var along := clampf((point - a).dot(axis) / maxf(axis.length_squared(), 0.000001), 0.0, 1.0)
	var nearest := a + axis * along
	var normal := (point - nearest).normalized() if (point - nearest).length() > 0.0001 else Vector3.ZERO
	return {"bar_a": a, "bar_b": b, "bar_radius_m": radius, "bar_nearest": nearest, "surface_normal": normal}

## What this recording says about itself, for a report: how many rows, the typical step, what was left out.
func describe() -> Dictionary:
	var steps: Array[float] = []
	for row in rows:
		if float(row.dt) > 0.0:
			steps.append(float(row.dt))
	steps.sort()
	return {"rows": rows.size(), "dropped": dropped, "frame_dt_s": snappedf(steps[steps.size() / 2], 0.00001) if not steps.is_empty() else 0.0, "mesh_sampling": mesh_used or mesh_every > 0, "bones": _bone_names.size() + _extra.size()}
