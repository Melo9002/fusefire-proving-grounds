class_name MotionReadout
extends RefCounted
## A family-neutral, read-only text of what a MotionPresenter is presenting, from its `snapshot()` alone (no skeleton, no rig): the shared values (family, time, speed, vertical speed, intended velocity, facing request,
## capabilities) and whatever scalar values the family chose to expose. It is the non-humanoid counterpart of the workbench's presentation monitor, deliberately small.

const COMMON := ["family", "time", "frames", "duplicates", "capabilities", "acting", "velocity", "horizontal_speed", "vertical_speed", "intended_velocity", "facing_mode"]

static func text(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "no snapshot"
	var intent := ""
	if snapshot.get("intended_velocity") != null:
		var wanted: Vector3 = snapshot.intended_velocity
		intent = "  wanted %.1f m/s" % wanted.length()
	var lines: Array[String] = ["%s   t %.1f s   moving %.2f m/s horizontally, %+.2f m/s vertically%s   facing request %s" % [
		String(snapshot.get("family", "?")).to_upper(), float(snapshot.get("time", 0.0)), float(snapshot.get("horizontal_speed", 0.0)), float(snapshot.get("vertical_speed", 0.0)), intent, snapshot.get("facing_mode", "-")]]
	var extras: Array[String] = []
	var keys := snapshot.keys()
	keys.sort()
	for key in keys:
		if not COMMON.has(key) and (snapshot[key] is float or snapshot[key] is int):
			extras.append("%s %.1f" % [String(key).replace("_", " "), float(snapshot[key])])
	if not extras.is_empty():
		lines.append("   " + "   ".join(extras))
	var capabilities: Array = snapshot.get("capabilities", [])
	lines.append("   can: %s   cannot: %s%s" % [", ".join(capabilities.map(func(c: StringName) -> String: return String(c))), ", ".join(MotionPresenter.ALL_CAPABILITIES.filter(func(c: StringName) -> bool: return not capabilities.has(c)).map(func(c: StringName) -> String: return String(c))), "   (acting)" if snapshot.get("acting", false) else ""])
	return "\n".join(lines)
