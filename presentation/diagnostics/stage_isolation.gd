class_name StageIsolation
extends RefCounted
## ADDA's one ACTIVE instrument, and it is labelled as an experiment: which modifier moves which bone, MEASURED by switching each SkeletonModifier3D off in turn and reading the final pose, instead of read from the
## declarations in PoseOwnership (which say what a stage may write, not what it did). It also covers modifiers that PoseOwnership does not know about (a stage someone added, a test fixture), which is the
## "a modifier unexpectedly changes a pose" case: an undeclared modifier whose removal moves a bone is reported as such.
##
## What it does and does not establish. It establishes: with THIS modifier off and everything else as it is, this bone ends up this far from where it ended up with it on, in this one held pose. It does not
## establish that the modifier "writes" the bone: a stage that only sets an IK target moves the arm through the solver after it, and switching it off moves the arm; the solver is then reported too. Run it on a HELD
## pose (the Workbench paused, a scenario stepped to a moment): when the pose is still changing the effect cannot be told from the motion, and the result says `inconclusive` (the baseline is sampled twice and its
## own drift is the noise floor). Every modifier's `active` flag is restored; the result says whether the pose came back.
##
## It changes state for a few updates, so it is NOT passive and must not run while a recording that should be exact is in progress. It is opt-in and nothing in the game calls it.

const FORMAT := "adda.isolation"
const VERSION := 1
## A modifier is reported as moving a bone when removing it changes the bone by at least this much (metres), and more than the drift of the baseline.
const EFFECT_THRESHOLD := 0.001
## A modifier is also reported when removing it changes a bone orientation by at least this many degrees (a rotation-only fault moves no origin of the bone it turns).
const ANGLE_THRESHOLD_DEG := 0.5
const UPDATES_PER_STEP := 2
## `window` > 1 samples that many consecutive updates per condition, so a fault that fires on some updates only (a pop) is seen as a SPIKE: the largest departure of a bone from its own median position in the window.
const DEFAULT_WINDOW := 1

var _skeleton: Skeleton3D
var _latest := {}
var _window := 1
var _series: Array[Dictionary] = []
var _bones: Array[StringName] = []
var _updates := 0


## Coroutine: `await StageIsolation.new().measure(rig, [bone names])`. `tree` is any node's tree.
func measure(rig: CharacterRig, bone_names: Array, tree: SceneTree, window := DEFAULT_WINDOW) -> Dictionary:
	_window = maxi(window, 1)
	_skeleton = rig.skeleton
	_bones.clear()
	var missing: Array[String] = []
	for name in bone_names:
		if _skeleton.find_bone(String(name)) >= 0:
			_bones.append(StringName(name))
		else:
			missing.append(String(name))
	var result := {"format": FORMAT, "version": VERSION, "status": "ok", "reason": "", "bones": _bones.map(func(b: StringName) -> String: return String(b)), "missing_bones": missing, "window": _window,
		"modifiers": [], "unit": "mm", "limits": [
			"An effect is what changes when ONE modifier is switched off with the others as they are, in one held pose; it is not a declaration of what the modifier writes.",
			"A modifier that only sets a target moves a bone through the solver after it: both are reported.",
			"Two modifiers that cancel each other's effect on a bone each show an effect; a modifier whose effect is below the baseline drift cannot be attributed."]}
	if _bones.is_empty():
		result.status = "unavailable"
		result.reason = "none of the requested bones exists in this skeleton"
		return result
	var witness := PoseWitness.acquire(_skeleton)
	witness.final_pose.connect(_capture)
	var modifiers: Array[SkeletonModifier3D] = []
	for child in _skeleton.get_children():
		if child is SkeletonModifier3D:
			modifiers.append(child)
	var saved: Array[bool] = []
	for modifier in modifiers:
		saved.append(modifier.active)
	var first := await _settle(tree)
	var second := await _settle(tree)
	if first.is_empty() or second.is_empty():
		result.status = "unavailable"
		result.reason = "the skeleton produced no update (is it paused in a way that stops skeleton updates?)"
		_finish(witness, modifiers, saved)
		return result
	var drift := _distance(first.last, second.last)
	result["drift_mm"] = drift * 1000.0
	var baseline: Dictionary = second.last
	var baseline_spike := _spikes(second.series)
	for i in modifiers.size():
		var modifier := modifiers[i]
		var declared := PoseOwnership.STAGE_ORDER.has(StringName(modifier.name))
		if not saved[i]:
			result.modifiers.append({"name": String(modifier.name), "declared": declared, "was_active": false, "effect_mm": {}, "effect_deg": {}, "spike_mm": {}, "max_mm": 0.0, "max_deg": 0.0, "moves_bones": false, "kind": "", "note": "was not active, so it contributes nothing to compare"})
			continue
		modifier.active = false
		var without := await _settle(tree)
		modifier.active = true
		var effect := _per_bone(baseline, without.last)
		var angle := _per_bone_angle(baseline, without.last)
		var without_spike := _spikes(without.series)
		var spike := {}
		var maximum := 0.0
		var max_spike := 0.0
		var max_angle := 0.0
		for bone in effect:
			maximum = maxf(maximum, float(effect[bone]))
			max_angle = maxf(max_angle, float(angle[bone]))
			spike[bone] = maxf(float(baseline_spike.get(bone, 0.0)) - float(without_spike.get(bone, 0.0)), 0.0)
			max_spike = maxf(max_spike, float(spike[bone]))
		var floor_m := maxf(EFFECT_THRESHOLD, drift * 2.0)
		var kind := ""
		if maximum >= floor_m:
			kind = "steady"
		elif max_spike >= floor_m:
			kind = "intermittent"
		elif max_angle >= ANGLE_THRESHOLD_DEG:
			kind = "rotation only"
		result.modifiers.append({"name": String(modifier.name), "declared": declared, "was_active": true, "effect_mm": _mm(effect), "effect_deg": _deg(angle), "spike_mm": _mm(spike),
			"max_mm": maxf(maximum, max_spike) * 1000.0, "max_deg": max_angle, "moves_bones": kind != "", "kind": kind})
	# Everything off: how much the modifiers contribute in total (the clip alone is the reference).
	for modifier in modifiers:
		modifier.active = false
	var all_off := await _settle(tree)
	for i in modifiers.size():
		modifiers[i].active = saved[i]
	result["all_modifiers_off_mm"] = _mm(_per_bone(baseline, all_off.last))
	var restored := await _settle(tree)
	var restore_error := _distance(baseline, restored.last)
	result["restored"] = restore_error <= maxf(0.0005, drift * 2.0) or _window > 1
	result["restore_error_mm"] = restore_error * 1000.0
	if drift > EFFECT_THRESHOLD and _window == 1:
		result.status = "inconclusive"
		result.reason = "the pose was still moving by %.1f mm between two samples of the SAME state, so an effect below that cannot be attributed; hold the pose (pause, or step a scenario to a moment) and run again" % (drift * 1000.0)
	elif not bool(result.restored):
		result.status = "inconclusive"
		result.reason = "the pose did not return to its baseline after the modifiers were restored (%.1f mm off): a modifier keeps state, so read these effects with that in mind" % (restore_error * 1000.0)
	_finish(witness, modifiers, saved)
	return result


func _finish(witness: PoseWitness, modifiers: Array[SkeletonModifier3D], saved: Array[bool]) -> void:
	for i in modifiers.size():
		if is_instance_valid(modifiers[i]):
			modifiers[i].active = saved[i]
	if witness.final_pose.is_connected(_capture):
		witness.final_pose.disconnect(_capture)
	witness.release()


func _capture() -> void:
	_updates += 1
	var now := {}
	for bone in _bones:
		now[bone] = _skeleton.get_bone_global_pose(_skeleton.find_bone(String(bone)))
	_latest = now
	_series.append(now)


## Waits for UPDATES_PER_STEP updates, then collects `window` more. Returns {last: the final pose, series: the collected poses} ({} when no update arrived).
func _settle(tree: SceneTree) -> Dictionary:
	_latest = {}
	_series = []
	for i in UPDATES_PER_STEP:
		await tree.process_frame
	if _window > 1:
		_series = []
		for i in _window:
			await tree.process_frame
	if _latest.is_empty():
		return {}
	if _series.is_empty():
		_series = [_latest]
	return {"last": _latest, "series": _series.duplicate()}


## Per bone: the largest departure of its position in the series from the component-wise median position of the series.
func _spikes(series: Array) -> Dictionary:
	var out := {}
	if series.size() < 3:
		return out
	for bone in series[0]:
		var xs: Array[float] = []
		var ys: Array[float] = []
		var zs: Array[float] = []
		for pose in series:
			var o: Vector3 = (pose[bone] as Transform3D).origin
			xs.append(o.x)
			ys.append(o.y)
			zs.append(o.z)
		xs.sort()
		ys.sort()
		zs.sort()
		var median := Vector3(xs[xs.size() / 2], ys[ys.size() / 2], zs[zs.size() / 2])
		var worst := 0.0
		for pose in series:
			worst = maxf(worst, ((pose[bone] as Transform3D).origin).distance_to(median))
		out[bone] = worst
	return out


func _per_bone(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for bone in a:
		out[bone] = ((a[bone] as Transform3D).origin).distance_to((b[bone] as Transform3D).origin) if b.has(bone) else 0.0
	return out


func _per_bone_angle(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for bone in a:
		out[bone] = rad_to_deg((a[bone] as Transform3D).basis.get_rotation_quaternion().angle_to((b[bone] as Transform3D).basis.get_rotation_quaternion())) if b.has(bone) else 0.0
	return out


func _distance(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	var per := _per_bone(a, b)
	for bone in per:
		worst = maxf(worst, float(per[bone]))
	return worst


func _deg(per_bone: Dictionary) -> Dictionary:
	var out := {}
	for bone in per_bone:
		out[String(bone)] = float(per_bone[bone])
	return out


func _mm(per_bone: Dictionary) -> Dictionary:
	var out := {}
	for bone in per_bone:
		out[String(bone)] = float(per_bone[bone]) * 1000.0
	return out


## Plain words for a result: who moves the bones, undeclared modifiers first, and what the experiment cannot say.
static func text(result: Dictionary) -> String:
	var lines: Array[String] = []
	if String(result.status) == "unavailable":
		return "Stage isolation could not run: %s" % result.reason
	lines.append("Stage isolation (an experiment: each modifier switched off in turn, in one held pose). Bones: %s. Baseline drift %.2f mm." % [", ".join(result.bones), float(result.get("drift_mm", 0.0))])
	if String(result.status) == "inconclusive":
		lines.append("INCONCLUSIVE: %s" % result.reason)
	var movers: Array = (result.modifiers as Array).filter(func(m: Dictionary) -> bool: return bool(m.moves_bones))
	movers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.max_mm) > float(b.max_mm))
	if movers.is_empty():
		lines.append("No modifier moved these bones by at least %.0f mm when switched off: the clip alone (or the state of the bones) produces this pose. Cause: unknown beyond that." % (EFFECT_THRESHOLD * 1000.0))
	for mover: Dictionary in movers:
		var detail: Array[String] = []
		for bone in mover.effect_mm:
			if float(mover.effect_mm[bone]) >= EFFECT_THRESHOLD * 1000.0:
				detail.append("%s moves %.1f mm" % [bone, float(mover.effect_mm[bone])])
			elif float(mover.spike_mm.get(bone, 0.0)) >= EFFECT_THRESHOLD * 1000.0:
				detail.append("%s spikes %.1f mm on some updates" % [bone, float(mover.spike_mm[bone])])
			if float(mover.effect_deg.get(bone, 0.0)) >= ANGLE_THRESHOLD_DEG:
				detail.append("%s turns %.1f deg" % [bone, float(mover.effect_deg[bone])])
		lines.append("  %s%s (%s): %s" % [mover.name, "" if bool(mover.declared) else "  (NOT declared in PoseOwnership)", mover.kind, ", ".join(detail)])
	lines.append("  restored: %s (%.2f mm)" % ["yes" if bool(result.get("restored", false)) else "NO", float(result.get("restore_error_mm", 0.0))])
	lines.append("(An effect is what changes when one modifier is switched off; it is not a statement of what the modifier is declared to write.)")
	return "\n".join(lines)
