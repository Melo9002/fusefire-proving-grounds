class_name RigInspection
extends RefCounted
## Read-only description of WHAT a CharacterRig is: its identity, the rig profile it resolved, which semantic roles map to bones, the measured body proportions, which capabilities the body supports and why not,
## which stages degraded, and what it carries. Pure functions of a rig (and, for check_profile, of a profile and a skeleton): nothing here writes to the rig, and nothing here knows a host, a tactical type
## or a particular character. Everything comes from data the rig already holds (RigBones, the RigResolver result, the modifier nodes); a fact the rig does not expose is reported as unknown, never guessed.

const Resolver := preload("res://presentation/characters/rig_profile/rig_resolver.gd")
const Roles := preload("res://presentation/characters/rig_profile/rig_roles.gd")
const Diag := preload("res://presentation/characters/rig_profile/rig_diagnostics.gd")

## The whole report as plain data (JSON-friendly): identity, roles, measurements, capabilities, degraded stages, equipment and diagnostics.
static func report(rig: CharacterRig) -> Dictionary:
	var result := {"identity": {}, "roles": {}, "measurements": {}, "capabilities": [], "degraded": [], "diagnostics": [], "equipment": {}, "usable": false}
	if not is_instance_valid(rig) or rig.skeleton == null:
		result["problem"] = "The rig has no skeleton yet (it builds itself when it enters the scene tree)"
		return result
	var resolved = rig.resolved_rig
	var profile: Resource = rig.rig_profile
	result.identity = {
		"profile": String(profile.display_name) if profile != null else "(no profile)",
		"model": rig.character_scene.resource_path if rig.character_scene != null else "(no model)",
		"skeleton_bones": rig.skeleton.get_bone_count(),
		"character_scale": rig.character_scale,
		"body_ratio": snappedf(rig.body_ratio(), 0.001),
		"armed": rig.has_weapon(),
	}
	result.roles = roles_report(rig)
	if resolved != null:
		result.measurements = measurements_of(resolved)
		result.capabilities = capabilities_of(resolved)
		for entry in resolved.diagnostics.entries:
			result.diagnostics.append({"severity": ["info", "warning", "error"][entry.severity], "code": String(entry.code), "role": String(entry.role), "message": entry.message, "hint": entry.hint})
		result.usable = not resolved.diagnostics.has_errors()
	else:
		result.usable = false
		result.problem = "The rig carries no profile: roles, measurements and capabilities cannot be resolved"
	result.degraded = rig.bones.degraded.duplicate() if rig.bones != null else []
	result.equipment = {"state": PresentationTypes.EquipmentState.keys()[rig.equipment_state()], "weapon": rig.weapon.name if rig.has_weapon() else "", "stowed": rig.is_weapon_stowed() if rig.has_weapon() else false}
	return result

## Every role the animation stack requires or may use, and the bone it resolved to ("" when absent). `required` is Roles.REQUIRED; the rest are optional (their absence degrades a stage instead of stopping the rig).
static func roles_report(rig: CharacterRig) -> Dictionary:
	var rows: Array = []
	var absent: Array = []
	if rig.bones == null:
		return {"rows": rows, "missing_required": absent}
	var map: BoneMap = rig.rig_profile.skeleton_map if rig.rig_profile != null else null
	var wanted: Array = []
	for role: StringName in Roles.REQUIRED:
		wanted.append(role)
	for role: StringName in [&"Chest", &"UpperChest", &"Neck", &"LeftShoulder", &"RightShoulder", &"LeftToes", &"RightToes"]:
		wanted.append(role)
	for role: StringName in wanted:
		var bone: StringName = rig.bones.role(role)
		var required: bool = Roles.REQUIRED.has(role)
		var mapped := map != null and map.get_skeleton_bone_name(role) != &""
		var status := "ok" if bone != &"" else ("MISSING (profile maps a bone this skeleton lacks)" if mapped else ("MISSING (not mapped)" if required else "absent (optional)"))
		rows.append({"role": String(role), "bone": String(bone), "required": required, "status": status})
		if required and bone == &"":
			absent.append(String(role))
	return {"rows": rows, "missing_required": absent}

static func measurements_of(resolved) -> Dictionary:
	var m = resolved.measurements
	var out := {}
	for key in ["hip_height", "ankle_height", "thigh_length", "shin_length", "leg_length", "upper_arm_length", "forearm_length", "shoulder_width", "hip_width", "standing_height"]:
		var value: float = m.get(key)
		out[key] = null if is_nan(value) else snappedf(value, 0.001)
	return out

## Capabilities in a stable order: name, status (SUPPORTED, FALLBACK, UNSUPPORTED, NOT_IMPLEMENTED) and the reason the resolver gave.
static func capabilities_of(resolved) -> Array:
	var rows: Array = []
	var names: Array = resolved.capabilities.keys()
	names.sort()
	for capability: StringName in names:
		var entry = resolved.capabilities[capability]
		rows.append({"name": String(capability), "status": Resolver.Status.keys()[entry.status], "reason": entry.reason})
	return rows

## Whether a profile can drive a skeleton, WITHOUT building a rig: the resolver's diagnostics, so an incompatible configuration is explained before anything is instantiated. Returns {ok, errors, warnings, text}.
static func check_profile(profile: Resource, skeleton: Skeleton3D) -> Dictionary:
	var resolved = Resolver.resolve(profile, skeleton)
	var errors: Array = []
	var warnings: Array = []
	for entry in resolved.diagnostics.entries:
		var line := "%s%s: %s%s" % [String(entry.code), (" [%s]" % entry.role) if entry.role != &"" else "", entry.message, (" -> " + entry.hint) if entry.hint != "" else ""]
		if entry.severity == Diag.Severity.ERROR:
			errors.append(line)
		elif entry.severity == Diag.Severity.WARNING:
			warnings.append(line)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "text": resolved.diagnostics.format()}

## A compact multi-line text for a panel. Distinguishes what is measured from the profile and skeleton (everything here) from anything inferred.
static func text(info: Dictionary) -> String:
	if info.has("problem") and info.identity.is_empty():
		return str(info.problem)
	var lines: Array[String] = []
	var id: Dictionary = info.identity
	lines.append("%s    %s    scale %.2f    body ratio %.3f" % [id.profile, "ARMED" if id.armed else "UNARMED", float(id.character_scale), float(id.body_ratio)])
	lines.append("model %s (%d bones)" % [String(id.model).get_file(), int(id.skeleton_bones)])
	var missing: Array = info.roles.get("missing_required", [])
	lines.append("roles: %d mapped, required missing: %s" % [(info.roles.rows as Array).filter(func(r: Dictionary) -> bool: return r.bone != "").size(), str(missing) if not missing.is_empty() else "none"])
	var m: Dictionary = info.measurements
	if not m.is_empty():
		lines.append("leg %.2f m  arm %.2f+%.2f m  shoulders %.2f m  stands %s m" % [_f(m.leg_length), _f(m.upper_arm_length), _f(m.forearm_length), _f(m.shoulder_width), "?" if m.standing_height == null else "%.2f" % float(m.standing_height)])
	for row: Dictionary in info.capabilities:
		if row.status != "SUPPORTED":
			lines.append("  %s: %s%s" % [row.name, row.status, (" - " + row.reason) if row.reason != "" else ""])
	for stage in info.degraded:
		lines.append("  DEGRADED stage: %s" % stage)
	return "\n".join(lines)

static func _f(value: Variant) -> float:
	return 0.0 if value == null else float(value)
