class_name ContactErrorDiagnostics
extends Node
## Optional, read-only measurement and drawing of CONTACT ERROR for a CharacterRig: for each hand, where its contact target is (what the solver was asked for), where the wrist really ended up, how far apart they are,
## whether the shoulder can reach the target at all (reach margin and deficit); for each foot, the planned foothold against the final ankle during stairs and ladders; and the contact's owner and strength.
## It is the contact-agnostic sibling of HandContactDiagnostics (which measures a weapon's grips): it works for ladder, carry, relaxed and weapon hands alike, armed or unarmed, and never needs a weapon.
##
## WHEN IT SAMPLES. Exactly like HandContactDiagnostics: only from the skeleton's `skeleton_updated` signal, which fires after every modifier has run. Before that signal `Skeleton3D.get_bone_global_pose` is the
## animation pose WITHOUT the modifiers, and a wrist read there can be tens of centimetres from where it is drawn; so `latest` is only ever written from the callback, and there is no other sampling entry point.
##
## WHAT IS MEASURED AND WHAT IS NOT. Measured: bone positions in the final pose, the target markers' positions, the grip modifier's claimed weights and directions, the stair planner's and ladder solver's planned feet.
## Not measured: mesh contact or penetration (no surface exists), and the planner's intent beyond the typed data the rig holds. A target farther than `arm_length * REACH_LIMIT_FRACTION` from the shoulder is called
## UNREACHABLE: that fraction is a display convention shared with the hand-contact test, not a limit the rig enforces. Nothing here fixes an unreachable contact; it only shows it (issue #55 is the ladder's case).
## Drawing is optional per layer; with the node disabled there is no overlay, no listener and no cost.

signal sampled(sample: Dictionary)

const REACH_LIMIT_FRACTION := 0.97
const HAND_NAMES := ["left", "right"]   # the grip modifier's convention: index 0 left, 1 right
const LAYERS := {
	"targets": "Intended targets (diamonds)",
	"solved": "Solved wrists and ankles (crosses)",
	"errors": "Target-to-solved error lines",
	"reach": "Shoulder reach (green = within arm, red = beyond it)",
	"feet": "Planned footholds against ankles",
	"frames": "Orientation vectors and the character frame",
}
## Short names for compact UI (the long descriptions above stay the tooltips).
const LAYER_SHORT := {"targets": "Targets", "solved": "Solved", "errors": "Error lines", "reach": "Shoulder reach", "feet": "Feet plan", "frames": "Frames"}
const COLOR_TARGET := Color(1.0, 0.85, 0.15)
const COLOR_SOLVED := Color(0.2, 0.95, 1.0)
const COLOR_ERROR := Color(1.0, 0.15, 0.15)
const COLOR_REACH_OK := Color(0.3, 1.0, 0.4)
const COLOR_REACH_OVER := Color(1.0, 0.25, 0.1)
const COLOR_FOOT_PLANNED := Color(0.4, 1.0, 0.6)
const COLOR_FOOT_ACTUAL := Color(1.0, 0.6, 0.2)
const COLOR_FINGERS := Color(1.0, 0.3, 0.3)
const COLOR_NORMAL := Color(0.6, 1.0, 0.2)

var rig: CharacterRig
var enabled := false
var latest: Dictionary = {}
## The pose witness (sampling happens from its `final_pose`, the moment the skeleton's pose is final) and the stamp of `latest`.
var witness: PoseWitness
var stamp := {}
var layers := {"targets": true, "solved": true, "errors": true, "reach": true, "feet": true, "frames": false}
var recording := false
var history: Array[Dictionary] = []
const MAX_HISTORY := 1800
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _skeleton: Skeleton3D
var _open := false
var _previous_sample := {}

static func attach(p_rig: CharacterRig) -> ContactErrorDiagnostics:
	if not is_instance_valid(p_rig) or p_rig.skeleton == null or p_rig.bones == null:
		return null
	var diagnostics := ContactErrorDiagnostics.new()
	diagnostics.name = "ContactErrorDiagnostics"
	diagnostics.rig = p_rig
	diagnostics._skeleton = p_rig.skeleton
	p_rig.add_child(diagnostics)
	return diagnostics

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_lines = MeshInstance3D.new()
		_lines.name = "ContactErrorOverlay"
		_lines.top_level = true   # world space: it ignores the rig's own scale and rotation
		_mesh = ImmediateMesh.new()
		_lines.mesh = _mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.no_depth_test = true   # a contact behind the body is still a contact
		_lines.material_override = material
		_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_lines)
		witness = PoseWitness.acquire(_skeleton)
		witness.final_pose.connect(_on_skeleton_updated)
	else:
		if witness != null and witness.final_pose.is_connected(_on_skeleton_updated):
			witness.final_pose.disconnect(_on_skeleton_updated)
			witness.release()
			witness = null
		if is_instance_valid(_lines):
			_lines.queue_free()
		_lines = null
		_mesh = null
		recording = false
		_previous_sample = {}

func set_layer(layer: String, on: bool) -> void:
	if layers.has(layer):
		layers[layer] = on
		_draw(latest)

## True when nothing of this diagnostic remains attached to the skeleton or the scene.
func is_clean() -> bool:
	return not enabled and not is_instance_valid(_lines) and not (witness != null and witness.final_pose.is_connected(_on_skeleton_updated))

func _on_skeleton_updated() -> void:
	stamp = witness.stamp()
	latest = measure()
	if latest.is_empty():
		return
	for foot: Dictionary in latest.feet:
		foot["plant_drift_mm"] = -1.0
		if not foot.planted or foot.weight < 0.9 or int(_previous_sample.get("frame", -2)) + 1 != int(latest.frame):
			continue
		for prior: Dictionary in _previous_sample.feet:
			if prior.name == foot.name and prior.source == foot.source and prior.planted and prior.weight >= 0.9:
				var offset: Vector3 = foot.ankle - prior.ankle
				foot.plant_drift_mm = Vector2(offset.x, offset.z).length() * 1000.0
	_previous_sample = latest
	if recording:
		history.append(scalars(latest))
		if history.size() > MAX_HISTORY:
			history.pop_front()
	_draw(latest)
	sampled.emit(latest)

## One measurement of the CURRENT pose. Call it from a skeleton_updated callback only (that is the sole place the pose is final); the node does, and stores the result in `latest`.
func measure() -> Dictionary:
	if not is_instance_valid(rig) or rig.skeleton == null or rig.bones == null:
		return {}
	var skeleton := rig.skeleton
	var origin := skeleton.global_transform
	var grip := rig.grip_modifier
	var to_world := skeleton.global_basis.orthonormalized()
	var hands: Array = []
	for side in 2:
		var arm: Array[StringName] = rig.left_arm_bones if side == 0 else rig.right_arm_bones
		var upper := skeleton.find_bone(arm[0])
		var fore := skeleton.find_bone(arm[1])
		var hand := skeleton.find_bone(arm[2])
		if upper < 0 or fore < 0 or hand < 0:
			continue
		var shoulder: Vector3 = origin * skeleton.get_bone_global_pose(upper).origin
		var elbow: Vector3 = origin * skeleton.get_bone_global_pose(fore).origin
		var wrist: Vector3 = origin * skeleton.get_bone_global_pose(hand).origin
		var target_node: Node3D = rig.support_ik_target if side == 0 else rig.right_hand_target
		var target: Vector3 = target_node.global_position if is_instance_valid(target_node) else wrist
		var arm_length := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
		var reach := shoulder.distance_to(target)
		var contact_weight := 0.0
		var owner_name := "none"
		var fingers := Vector3.ZERO
		var palm := Vector3.ZERO
		if grip != null:
			contact_weight = float(grip.contact_weight[side])
			if contact_weight > 0.001:
				owner_name = "contact claim"
				fingers = to_world * (grip.contact_forward[side] as Vector3)
				palm = to_world * (grip.contact_normal[side] as Vector3)
			elif grip.orient_weight > 0.001 and rig.has_weapon():
				owner_name = "weapon grip"
		hands.append({"name": HAND_NAMES[side], "target": target, "wrist": wrist, "shoulder": shoulder, "elbow": elbow, "arm_length": arm_length, "error": target.distance_to(wrist), "reach": reach,
			"reach_margin": arm_length * REACH_LIMIT_FRACTION - reach, "unreachable": reach > arm_length * REACH_LIMIT_FRACTION, "weight": contact_weight, "owner": owner_name, "fingers": fingers, "palm": palm})
	var feet: Array = []
	var knees: Array[Vector3] = []
	for side in 2:
		var leg: Array[StringName] = rig.bones.left_leg if side == 0 else rig.bones.right_leg
		if leg.size() < 3:
			continue
		var ankle_bone := skeleton.find_bone(leg[2])
		if ankle_bone < 0:
			continue
		var ankle: Vector3 = origin * skeleton.get_bone_global_pose(ankle_bone).origin
		var knee_bone := skeleton.find_bone(leg[1])
		if knee_bone >= 0:
			knees.append(origin * skeleton.get_bone_global_pose(knee_bone).origin)
		var planned := Vector3.INF
		var source := ""
		var plan_weight := 0.0
		var plan_ok := true
		var planted := false
		if rig.stairs != null and rig.stairs.pose != null and side < rig.stairs.pose.feet.size():
			planned = rig.stairs.pose.feet[side].position
			source = "stair planner"
			plan_weight = rig.stairs.pose.weight
			plan_ok = rig.stairs.pose.pelvis_ok   # false: the legs cannot reach the pelvis height the planner chose (a stair too steep for this body)
			planted = rig.stairs.pose.feet[side].planted
		elif rig.ladder != null and rig.ladder.pose != null and rig.ladder.pose.on_ladder:
			planned = rig.character_root.to_global(rig.ladder.pose.feet[side])
			source = "ladder solver"
			plan_weight = rig.ladder.pose.weight
			planted = is_zero_approx(rig.ladder.pose.foot_swing[side])
		if source == "":
			continue
		feet.append({"name": HAND_NAMES[side], "ankle": ankle, "planned": planned, "error": ankle.distance_to(planned), "source": source, "weight": plan_weight, "plan_ok": plan_ok, "planted": planted})
	var root := rig.character_root.global_basis.orthonormalized() if is_instance_valid(rig.character_root) else Basis.IDENTITY
	var sample := {"hands": hands, "feet": feet, "frame": Engine.get_process_frames(), "timing": "post-update", "root_origin": rig.character_root.global_position if is_instance_valid(rig.character_root) else Vector3.ZERO, "root_basis": root}
	if knees.size() == 2 and feet.size() == 2 and feet[0].source == "ladder solver":
		sample["knee_width_cm"] = absf((knees[0] - knees[1]).dot(root.x)) * 100.0
		sample["ankle_width_cm"] = absf(((feet[0].ankle as Vector3) - (feet[1].ankle as Vector3)).dot(root.x)) * 100.0
	return sample

## The last sample as ADDA measurements (see Measurement): per hand a TARGET_ERROR (wrist from the contact target) and a REACH_FEASIBILITY (shoulder to target against 97% of the arm), per foot a TARGET_ERROR
## (final ankle from the plan's foothold) and a SUPPORT_CLAIM (the plan says planted, with its weight). Each is FRESH only for the update it was taken in; with no sample, or a stale one, every entry says so
## instead of carrying numbers. A TARGET_ERROR does not say the target is reachable or right, and a SUPPORT_CLAIM is not physical support (see Measurement.MEANING).
func evidence(scenario := "") -> Array[Measurement]:
	var out: Array[Measurement] = []
	if witness == null or latest.is_empty():
		out.append(Measurement.missing(Measurement.Kind.TARGET_ERROR, "contact error", Measurement.Status.UNAVAILABLE, "no sample yet (enable the diagnostic and let a frame run)"))
		return out
	var verdict := witness.judge(stamp)
	for hand: Dictionary in latest.hands:
		var error := Measurement.make(Measurement.Kind.TARGET_ERROR, "%s hand: wrist from contact target" % hand.name, snappedf(float(hand.error) * 1000.0, 0.01), "mm")
		var reach := Measurement.make(Measurement.Kind.REACH_FEASIBILITY, "%s hand: target within 97%% of arm length" % hand.name, not bool(hand.unreachable), "bool")
		reach.tolerance = REACH_LIMIT_FRACTION
		for m in [error, reach]:
			out.append(_finish(m, verdict, "world", "bones read inside skeleton_updated; target = the contact target node", scenario))
	for foot: Dictionary in latest.feet:
		var ferror := Measurement.make(Measurement.Kind.TARGET_ERROR, "%s foot: ankle from %s foothold" % [foot.name, foot.source], snappedf(float(foot.error) * 1000.0, 0.01), "mm")
		var claim := Measurement.make(Measurement.Kind.SUPPORT_CLAIM, "%s foot: %s claims it planted" % [foot.name, foot.source], bool(foot.planted) and float(foot.weight) > 0.9, "bool")
		for m in [ferror, claim]:
			out.append(_finish(m, verdict, "world", "ankle bone read inside skeleton_updated; foothold = the planner's typed plan", scenario))
	return out

func _finish(m: Measurement, verdict: Dictionary, space: String, method: String, scenario: String) -> Measurement:
	m.pose = Measurement.Pose.FINAL
	m.space = space
	m.source = "ContactErrorDiagnostics.measure"
	m.method = method
	m.stamped(witness, stamp)
	if verdict.status != Measurement.Status.FRESH:
		m.status = verdict.status
		m.reason = verdict.reason
		m.value = null
	return m.with_identity(rig, scenario)

## The numbers of a sample without the vectors (for history and export).
static func scalars(sample: Dictionary) -> Dictionary:
	var out := {"frame": sample.frame, "hands": [], "feet": []}
	if sample.has("knee_width_cm"):
		out["knee_width_cm"] = sample.knee_width_cm
		out["ankle_width_cm"] = sample.ankle_width_cm
	for hand: Dictionary in sample.hands:
		out.hands.append({"name": hand.name, "error_mm": snappedf(float(hand.error) * 1000.0, 0.01), "reach_cm": snappedf(float(hand.reach) * 100.0, 0.01), "arm_cm": snappedf(float(hand.arm_length) * 100.0, 0.01), "margin_cm": snappedf(float(hand.reach_margin) * 100.0, 0.01), "unreachable": hand.unreachable, "weight": snappedf(float(hand.weight), 0.001), "owner": hand.owner})
	for foot: Dictionary in sample.feet:
		out.feet.append({"name": foot.name, "error_mm": snappedf(float(foot.error) * 1000.0, 0.01), "source": foot.source, "weight": snappedf(float(foot.weight), 0.001), "plan_ok": foot.plan_ok, "planted": foot.planted, "plant_drift_mm": foot.get("plant_drift_mm", -1.0)})
	return out

## Summarises the recorded frames per hand and foot: the worst target-to-wrist error among REACHABLE contacts, how many frames asked for an unreachable one and the worst deficit, and the worst ankle error.
func summary() -> Dictionary:
	var result := {"frames": history.size(), "hands": {}, "feet": {}}
	for entry in history:
		for hand: Dictionary in entry.hands:
			var row: Dictionary = result.hands.get(hand.name, {"worst_reachable_error_mm": 0.0, "unreachable_frames": 0, "worst_deficit_cm": 0.0, "contact_frames": 0})
			if float(hand.weight) > 0.9:
				row.contact_frames += 1
				if hand.unreachable:
					row.unreachable_frames += 1
					row.worst_deficit_cm = maxf(row.worst_deficit_cm, -float(hand.margin_cm))
				else:
					row.worst_reachable_error_mm = maxf(row.worst_reachable_error_mm, float(hand.error_mm))
			result.hands[hand.name] = row
		for foot: Dictionary in entry.feet:
			var frow: Dictionary = result.feet.get(foot.name, {"worst_error_mm": 0.0, "source": foot.source, "worst_plant_drift_mm": 0.0, "plant_drift_pairs": 0})
			if float(foot.weight) > 0.9:   # while the plan has hold of the leg (at its ramps the ankle follows the clip, not the plan)
				frow.worst_error_mm = maxf(frow.worst_error_mm, float(foot.error_mm))
			if float(foot.plant_drift_mm) >= 0.0:
				frow.worst_plant_drift_mm = maxf(frow.worst_plant_drift_mm, float(foot.plant_drift_mm))
				frow.plant_drift_pairs += 1
			result.feet[foot.name] = frow
	return result

func start_recording() -> void:
	history.clear()
	recording = true

func stop_recording() -> Dictionary:
	recording = false
	return summary()

static func _mm(metres: float) -> String:
	return "%.1f mm" % (metres * 1000.0)

static func format_readout(sample: Dictionary) -> String:
	if sample.is_empty():
		return "no sample yet (contacts are measured after the skeleton's modifiers have run)"
	var lines: Array[String] = []
	for hand: Dictionary in sample.hands:
		var verdict := "UNREACHABLE by %.1f cm" % (-float(hand.reach_margin) * 100.0) if hand.unreachable else "ok, %.1f cm spare" % (float(hand.reach_margin) * 100.0)
		lines.append("%s hand: %s, weight %.2f
  target->wrist %s  reach %.0f/%.0f cm  %s" % [String(hand.name).to_upper(), hand.owner, float(hand.weight), _mm(float(hand.error)), float(hand.reach) * 100.0, float(hand.arm_length) * 100.0, verdict])
	for foot: Dictionary in sample.feet:
		lines.append("%-5s foot  %s (weight %.2f)%s  planned->ankle %s" % [String(foot.name).to_upper(), foot.source, float(foot.weight), "" if foot.plan_ok else " PLAN UNREACHABLE for this leg", _mm(float(foot.error))])
		if float(foot.get("plant_drift_mm", -1.0)) >= 0.0:
			lines.append("  planted ankle drift %.1f mm since previous frame" % float(foot.plant_drift_mm))
	if sample.has("knee_width_cm"):
		lines.append("Ladder spread: knees %.1f cm, ankles %.1f cm" % [float(sample.knee_width_cm), float(sample.ankle_width_cm)])
	if sample.feet.is_empty():
		lines.append("feet: no stair or ladder plan to compare against")
	return "\n".join(lines)

# ----------------------------------------------------------------------------------------------------- drawing

func _draw(sample: Dictionary) -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	if sample.is_empty():
		return
	_open = false
	for hand: Dictionary in sample.hands:
		var show_contact: bool = float(hand.weight) > 0.001 or layers.errors
		if not show_contact:
			continue
		if layers.targets:
			_diamond(hand.target, 0.035 + 0.025 * clampf(float(hand.weight), 0.0, 1.0), COLOR_TARGET)
		if layers.solved:
			_cross(hand.wrist, 0.03, COLOR_SOLVED)
		if layers.errors:
			_line(hand.target, hand.wrist, COLOR_ERROR if float(hand.error) > 0.02 else Color(1.0, 0.6, 0.6))
		if layers.reach:
			var shoulder: Vector3 = hand.shoulder
			var toward: Vector3 = (hand.target as Vector3) - shoulder
			if toward.length() > 0.0001:
				var within: Vector3 = shoulder + toward.normalized() * minf(toward.length(), float(hand.arm_length))
				_line(shoulder, within, COLOR_REACH_OK)
				if toward.length() > float(hand.arm_length):
					_line(within, hand.target, COLOR_REACH_OVER)
		if layers.frames and (hand.fingers as Vector3).length() > 0.1:
			_line(hand.target, (hand.target as Vector3) + (hand.fingers as Vector3).normalized() * 0.09, COLOR_FINGERS)
			_line(hand.target, (hand.target as Vector3) + (hand.palm as Vector3).normalized() * 0.09, COLOR_NORMAL)
	if layers.feet:
		for foot: Dictionary in sample.feet:
			_diamond(foot.planned, 0.04, COLOR_FOOT_PLANNED)
			_cross(foot.ankle, 0.035, COLOR_FOOT_ACTUAL)
			_line(foot.planned, foot.ankle, COLOR_ERROR if float(foot.error) > 0.03 else Color(1.0, 0.7, 0.7))
	if layers.frames:
		var basis: Basis = sample.root_basis
		var at: Vector3 = sample.root_origin + Vector3(0, 0.02, 0)
		_line(at, at + basis.x * 0.3, Color(1, 0.3, 0.3))
		_line(at, at + basis.y * 0.3, Color(0.3, 1, 0.3))
		_line(at, at + basis.z * 0.45, Color(0.3, 0.5, 1))   # forward: the way the character faces
	if _open:
		_mesh.surface_end()

func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	if not _open:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)   # begun on the first line: an empty surface is an engine error
		_open = true
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(b)

func _cross(at: Vector3, size: float, colour: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(at - axis * size, at + axis * size, colour)

## An octahedron outline: a different shape from the solved cross, so an intended point is never mistaken for a solved one.
func _diamond(at: Vector3, size: float, colour: Color) -> void:
	var tips := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for i in 6:
		for j in range(i + 1, 6):
			if (tips[i] as Vector3).dot(tips[j]) == 0.0:
				_line(at + (tips[i] as Vector3) * size, at + (tips[j] as Vector3) * size, colour)
