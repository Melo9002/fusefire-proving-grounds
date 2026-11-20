class_name HandContactDiagnostics
extends Node
## Optional hand-to-weapon contact diagnostics for a CharacterRig: numbers (HandContactSampler), a drawn
## overlay (HandContactOverlay) and a compact readout. Only diagnostic tools create it (the MIRA pose
## workbench, tests, capture scripts); gameplay never does. It reads the rig and never writes to it.
##
## WHEN IT SAMPLES. The rig finishes a frame's pose in this order: animation, CoverCrouch, WeaponArmIK,
## HandGrip, then the skeleton emits `skeleton_updated`, whose first listeners are the weapon socket
## attachment and then the rig's own `_align_weapon_to_aim`. This node connects to `skeleton_updated`
## when enabled, after both, so its sample sees the final bones AND the final weapon transform of the
## frame about to be drawn. A sample taken from `_process` instead sees the previous update's bones and
## the weapon as the previous update left it; compare_timing() measures that difference.
## The production update order is not touched. If another system connected to `skeleton_updated` after
## this node and moved the weapon, this node would read that stale; sample() reports the weapon's
## orientation error against the rig's own expectation (`weapon_basis_error_deg`) so that shows up.
##
## WHY ONLY THEN. Outside that callback `Skeleton3D.get_bone_global_pose` returns the animation pose WITHOUT
## the results of the skeleton modifiers (crouch, arm IK, hand grip): measured from a `_process` while the
## character moves, wrists came out up to 0.75 m from where they are drawn. That is far more than one frame
## of staleness, so a sample from anywhere else is not a "slightly old" reading, it is a different pose.
## Hence `latest` is only ever written from the post-update callback, and the one method that samples
## elsewhere is named for what it is (sample_unsynchronised) and is kept out of `latest` and the overlay.

signal sampled(sample: Dictionary)

var rig: Node3D
var sampler := HandContactSampler.new()
var overlay: HandContactOverlay
var latest: Dictionary = {}
var enabled := false
var labels_visible := false
var readout_visible := true
## Hand contact measured at the last mark_reference(): where each palm and wrist sat in the weapon's frame.
var reference: Dictionary = {}
## Current and peak distance (metres) of each hand's palm and wrist from that reference, in the weapon frame.
var displacement := {"dominant": {"palm": 0.0, "wrist": 0.0}, "support": {"palm": 0.0, "wrist": 0.0}}
var peak_displacement := {"dominant": {"palm": 0.0, "wrist": 0.0}, "support": {"palm": 0.0, "wrist": 0.0}}
var recording := false
var history: Array[Dictionary] = []
var _readout: Label
var _readout_layer: CanvasLayer

## Creates diagnostics for `p_rig` (not yet enabled). Returns null when the rig cannot be measured.
static func attach(p_rig: Node3D) -> HandContactDiagnostics:
	var diagnostics := HandContactDiagnostics.new()
	diagnostics.name = "HandContactDiagnostics"
	if not diagnostics.sampler.setup(p_rig):
		diagnostics.free()
		return null
	diagnostics.rig = p_rig
	p_rig.add_child(diagnostics)
	return diagnostics

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	var skeleton := sampler.skeleton
	if on:
		overlay = HandContactOverlay.new()
		overlay.labels_visible = labels_visible
		add_child(overlay)
		if not skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
			skeleton.skeleton_updated.connect(_on_skeleton_updated)
		_ensure_readout()
		# No sample here: one taken outside the skeleton update would not be a final pose. The first real
		# sample arrives with the next update.
	else:
		if skeleton != null and skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
			skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
		if is_instance_valid(overlay):
			overlay.queue_free()
		overlay = null
		if is_instance_valid(_readout_layer):
			_readout_layer.queue_free()
		elif is_instance_valid(_readout):
			_readout.queue_free()
		_readout = null
		_readout_layer = null
		recording = false

func set_labels_visible(on: bool) -> void:
	labels_visible = on
	if is_instance_valid(overlay):
		overlay.set_labels_visible(on)

func set_readout_visible(on: bool) -> void:
	readout_visible = on
	if is_instance_valid(_readout):
		_readout.visible = on

func _ensure_readout() -> void:
	if is_instance_valid(_readout):
		return
	_readout = Label.new()
	_readout.name = "HandContactReadout"
	_readout.visible = readout_visible
	_readout.add_theme_font_size_override("font_size", 15)
	_readout.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_readout.add_theme_constant_override("outline_size", 6)
	_readout.anchor_left = 1.0
	_readout.anchor_right = 1.0
	_readout.offset_left = -880.0
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.custom_minimum_size = Vector2(860.0, 0.0)
	_readout.offset_right = -16.0
	_readout.offset_top = 18.0
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var host := rig.get_node_or_null("UI")
	if host == null:
		_readout_layer = CanvasLayer.new()
		_readout_layer.name = "HandContactReadoutLayer"
		add_child(_readout_layer)
		host = _readout_layer
	host.add_child(_readout)

## A measurement from wherever the caller happens to be in the frame. It is NOT a final pose (see above), is
## not stored in `latest` and is not drawn; it exists to show how wrong that would be (compare_timing).
func sample_unsynchronised(timing := "unsynchronised") -> Dictionary:
	return sampler.sample(timing)

func _on_skeleton_updated() -> void:
	var result := sampler.sample("post-update")
	if not result.is_empty():
		_accept(result)

func _accept(result: Dictionary) -> void:
	latest = result
	_update_displacement(result)
	if is_instance_valid(overlay):
		overlay.show_sample(result)
	if is_instance_valid(_readout) and _readout.visible:
		_readout.text = format_readout(result)
	if recording:
		var entry := HandContactSampler.scalars(result)
		entry["displacement_mm"] = {"dominant": _mm_pair(displacement.dominant), "support": _mm_pair(displacement.support)}
		history.append(entry)
	sampled.emit(result)

func _mm_pair(pair: Dictionary) -> Dictionary:
	return {"palm": snappedf(float(pair.palm) * 1000.0, 0.001), "wrist": snappedf(float(pair.wrist) * 1000.0, 0.001)}

## Remembers where each palm and wrist sit in the weapon's frame right now and clears the peaks. Later
## samples report how far the hands have moved relative to the weapon since.
func mark_reference() -> void:
	if latest.is_empty():
		return
	var current := latest
	reference.clear()
	for hand: Dictionary in current.get("hands", []):
		if hand.has("palm_in_weapon_frame"):
			reference[hand.name] = {"palm": hand.palm_in_weapon_frame, "wrist": hand.wrist_in_weapon_frame}
	for hand_name in ["dominant", "support"]:
		displacement[hand_name] = {"palm": 0.0, "wrist": 0.0}
		peak_displacement[hand_name] = {"palm": 0.0, "wrist": 0.0}

func _update_displacement(result: Dictionary) -> void:
	for hand: Dictionary in result.get("hands", []):
		if not reference.has(hand.name) or not hand.has("palm_in_weapon_frame"):
			continue
		var base: Dictionary = reference[hand.name]
		var palm_shift: float = (hand.palm_in_weapon_frame as Vector3).distance_to(base.palm)
		var wrist_shift: float = (hand.wrist_in_weapon_frame as Vector3).distance_to(base.wrist)
		displacement[hand.name] = {"palm": palm_shift, "wrist": wrist_shift}
		var peak: Dictionary = peak_displacement[hand.name]
		peak_displacement[hand.name] = {"palm": maxf(float(peak.palm), palm_shift), "wrist": maxf(float(peak.wrist), wrist_shift)}

func start_recording() -> void:
	history.clear()
	recording = true

## Stops recording and summarises the recorded frames: peaks of the errors, the least reach margin and the
## largest contact displacement. Raw per-frame data stays in `history`.
func stop_recording() -> Dictionary:
	recording = false
	var summary := {"frames": history.size()}
	for hand_index in 2:
		var hand_name: String = HandContactSampler.HAND_NAMES[hand_index]
		var worst := {"wrist_to_ik_target_mm": 0.0, "palm_to_intended_mm_max": 0.0, "palm_to_intended_mm_min": INF,
			"reach_margin_mm_min": INF, "reach_fraction_max": 0.0, "finger_direction_error_deg_max": 0.0, "palm_normal_error_deg_max": 0.0,
			"palm_displacement_mm_max": 0.0, "wrist_displacement_mm_max": 0.0}
		for entry in history:
			var hand: Dictionary = (entry.hands as Array)[hand_index]
			worst.wrist_to_ik_target_mm = maxf(worst.wrist_to_ik_target_mm, float(hand.get("wrist_to_ik_target", 0.0)) * 1000.0)
			if hand.has("palm_to_intended"):
				worst.palm_to_intended_mm_max = maxf(worst.palm_to_intended_mm_max, float(hand.palm_to_intended) * 1000.0)
				worst.palm_to_intended_mm_min = minf(worst.palm_to_intended_mm_min, float(hand.palm_to_intended) * 1000.0)
			worst.reach_margin_mm_min = minf(worst.reach_margin_mm_min, float(hand.get("reach_margin", INF)) * 1000.0)
			worst.reach_fraction_max = maxf(worst.reach_fraction_max, float(hand.get("reach_fraction", 0.0)))
			worst.finger_direction_error_deg_max = maxf(worst.finger_direction_error_deg_max, float(hand.get("finger_direction_error_deg", 0.0)))
			worst.palm_normal_error_deg_max = maxf(worst.palm_normal_error_deg_max, float(hand.get("palm_normal_error_deg", 0.0)))
			var shift: Dictionary = (entry.get("displacement_mm", {}) as Dictionary).get(hand_name, {})
			worst.palm_displacement_mm_max = maxf(worst.palm_displacement_mm_max, float(shift.get("palm", 0.0)))
			worst.wrist_displacement_mm_max = maxf(worst.wrist_displacement_mm_max, float(shift.get("wrist", 0.0)))
		for key in worst:
			if is_inf(float(worst[key])):
				worst[key] = null
			else:
				worst[key] = snappedf(float(worst[key]), 0.001)
		summary[hand_name] = worst
	return summary

## Measures the cost of sampling at the wrong moment: takes an unsynchronised sample right now (from the caller's
## place in the frame) and returns how far it is from the last post-update sample, per hand (metres) and in
## weapon orientation (degrees). Call it from a `_process`, where the bones exclude the modifiers' results.
func compare_timing() -> Dictionary:
	var now := sample_unsynchronised("process")
	var result := {}
	if now.is_empty() or latest.is_empty():
		return result
	for index in 2:
		var a: Dictionary = (now.hands as Array)[index]
		var b: Dictionary = (latest.hands as Array)[index]
		var entry := {"wrist": (a.wrist as Vector3).distance_to(b.wrist), "ik_target": (a.ik_target as Vector3).distance_to(b.ik_target)}
		if a.has("palm") and b.has("palm"):
			entry["palm"] = (a.palm as Vector3).distance_to(b.palm)
		result[a.name] = entry
	result["weapon_basis_deg"] = rad_to_deg(((now.meta as Dictionary).weapon_basis as Basis).get_rotation_quaternion().angle_to(((latest.meta as Dictionary).weapon_basis as Basis).get_rotation_quaternion()))
	result["latest_timing"] = (latest.meta as Dictionary).timing
	result["latest_frame"] = (latest.meta as Dictionary).frame
	result["now_frame"] = Engine.get_process_frames()
	return result

static func _mm(metres: float) -> String:
	return "%.1f mm" % (metres * 1000.0) if is_finite(metres) else "n/a"

static func _deg(degrees: float) -> String:
	return "%.1f deg" % degrees if is_finite(degrees) else "n/a"

## The compact on-screen readout. A trailing "~" marks an approximation (palm estimated from bones); every
## other figure is measured directly. Distances are shown in millimetres (reach in centimetres).
func format_readout(result: Dictionary) -> String:
	if result.is_empty():
		return "HAND CONTACT: no sample yet"
	var meta: Dictionary = result.meta
	var lines: Array[String] = []
	lines.append("HAND CONTACT  state %s  aim %.2f  crouch %.2f m  kneel %.2f  [%s]" % [meta.state, meta.aim_blend, meta.crouch_depth, meta.kneel, meta.timing])
	for hand: Dictionary in result.hands:
		var title := String(hand.name).to_upper()
		var line := "%-8s wrist->IK %s" % [title, _mm(float(hand.wrist_to_ik_target))]
		if hand.has("palm_to_intended"):
			line += " | palm->intended %s~ | finger dir %s | palm normal %s~" % [_mm(float(hand.palm_to_intended)), _deg(float(hand.finger_direction_error_deg)), _deg(float(hand.get("palm_normal_error_deg", INF)))]
		lines.append(line)
	for hand: Dictionary in result.hands:
		lines.append("%-8s reach %.1f/%.1f cm (%d%%) margin %.1f cm | elbow %.0f deg | elbow->pole %s" % [String(hand.name).to_upper(), float(hand.reach) * 100.0, float(hand.arm_length) * 100.0, roundi(float(hand.reach_fraction) * 100.0), float(hand.reach_margin) * 100.0, float(hand.elbow_angle_deg), _mm(float(hand.elbow_to_pole))])
	if not reference.is_empty():
		var d: Dictionary = displacement
		var p: Dictionary = peak_displacement
		lines.append("CONTACT SHIFT since mark (palm~, in weapon frame): dominant %s (peak %s)  support %s (peak %s)" % [_mm(float(d.dominant.palm)), _mm(float(p.dominant.palm)), _mm(float(d.support.palm)), _mm(float(p.support.palm))])
	else:
		lines.append("CONTACT SHIFT: press G to mark a reference pose")
	if meta.has("protraction_total_deg"):
		lines.append("SUPPORT SHOULDER reach %.1f deg (base %.1f + %.1f added, limit %.0f)%s | still short of the arm's length: %s | short of the comfortable bend: %s" % [meta.protraction_total_deg, meta.protraction_base_deg, meta.protraction_extra_deg, meta.protraction_limit_deg, " LIMIT REACHED" if meta.protraction_limited else "", _mm(float(meta.support_deficit_mm) / 1000.0), _mm(float(meta.support_comfort_deficit_mm) / 1000.0)])
	elif not bool(meta.get("weapon_pose_modifier", false)):
		lines.append("WeaponPose modifier off: legacy targets from the animation-only shoulder")
	if meta.has("weapon_basis_error_deg"):
		lines.append("weapon vs rig expectation %s | ~ = approximation from bones (no palm bone); no mesh contact is measured" % _deg(float(meta.weapon_basis_error_deg)))
	lines.append("colours: orange/yellow dominant IK target/wrist, blue/cyan support, magenta palm~, green intended palm, red palm error")
	return "\n".join(lines)
