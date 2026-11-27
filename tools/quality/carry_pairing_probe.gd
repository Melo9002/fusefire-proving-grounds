extends SceneTree
## Measures the steady carry for every carrier/passenger pairing in the Workbench's real rig, sampled inside `skeleton_updated` (the final pose). Read-only evidence for the mixed-size carry (animation assignment):
## each body's own scale, the passenger's extents against the floor and the carrier's frame, and each carrier hand's distance to its contact and share of arm reach.
##
##   godot_console --headless --path . --script res://tools/quality/carry_pairing_probe.gd -- [json=user://carry_pairings.json] [armed=false]

const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"

var _final := {}


func _initialize() -> void:
	_run.call_deferred()


func _arguments() -> Dictionary:
	var result := {"json": "", "armed": "false"}
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2:
			result[parts[0]] = parts[1]
	return result


func _run() -> void:
	var args := _arguments()
	var characters := PassengerDefinition.known_characters()
	if characters.is_empty():
		characters.assign([&"mira_0", &"small_mira_0"])
	var report: Array[Dictionary] = []
	for carrier in characters:
		for passenger in characters:
			report.append(await _measure(carrier, passenger, args.armed == "true"))
	for entry in report:
		print("PAIRING %s carries %s: passenger scale %.3f (own %.3f) %s | passenger y %.2f..%.2f m, lateral +-%.2f m, lowest %.2f m above the floor (%s; carrier neck at %.2f m) | hands: %s | fit %s" % [
			entry.carrier, entry.passenger, entry.passenger_scale, entry.passenger_own_scale, "OK" if entry.identity_ok else "WRONG BODY",
			entry.passenger_y[0], entry.passenger_y[1], entry.lateral, entry.lowest, entry.lowest_bone, entry.neck_height, entry.hands, JSON.stringify(entry.fit)])
	if not String(args.json).is_empty():
		var file := FileAccess.open(String(args.json), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	quit()


func _measure(carrier: StringName, passenger: StringName, armed: bool) -> Dictionary:
	WorkbenchSession.character = carrier
	WorkbenchSession.armed = armed
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	for i in 10:
		await process_frame
	var rig: CharacterRig = bench.rig
	var definition := PassengerDefinition.for_character(passenger)
	rig.passenger_definition = definition
	rig.skeleton.skeleton_updated.connect(func() -> void: _capture(rig))
	rig.begin_carry()
	rig.animation_controller.play(&"carry_idle")
	for i in 60:
		await process_frame
	var result := _summarise(rig, carrier, passenger, definition)
	bench.queue_free()
	await process_frame
	return result


func _capture(rig: CharacterRig) -> void:
	if not is_instance_valid(rig.carry_passenger) or rig.carry_passenger.skeleton == null:
		return
	var carried: Skeleton3D = rig.carry_passenger.skeleton
	var points: Array[Vector3] = []
	var names: Array[String] = []
	for bone in carried.get_bone_count():
		points.append(carried.global_transform * carried.get_bone_global_pose(bone).origin)
		names.append(carried.get_bone_name(bone))
	var wrists: Array[Vector3] = []
	var shoulders: Array[Vector3] = []
	for chain in [rig.right_arm_bones, rig.left_arm_bones]:
		shoulders.append(rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(chain[0])).origin)
		wrists.append(rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(chain[2])).origin)
	_final = {"points": points, "names": names, "neck": rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(rig.neck_bone_name)).origin, "wrists": wrists, "shoulders": shoulders, "report": rig.carry_contact_report.duplicate(true)}


func _summarise(rig: CharacterRig, carrier: StringName, passenger: StringName, definition: PassengerDefinition) -> Dictionary:
	var floor_y := rig.character_root.global_position.y
	var frame := rig.character_root.global_transform.affine_inverse()
	var low := INF
	var high := -INF
	var lateral := 0.0
	var lowest_bone := ""
	var index := 0
	for point: Vector3 in _final.get("points", []):
		if point.y - floor_y < low:
			lowest_bone = String(_final.names[index])
		index += 1
		low = minf(low, point.y - floor_y)
		high = maxf(high, point.y - floor_y)
		lateral = maxf(lateral, absf((frame * point).x))
	var hands: Array[String] = []
	var arm_lengths: Array[float] = [_arm_length(rig, rig.right_arm_bones), _arm_length(rig, rig.left_arm_bones)]
	for side in 2:
		var entry: Dictionary = (_final.report[side] as Dictionary) if _final.has("report") and side < (_final.report as Array).size() else {}
		if entry.is_empty():
			hands.append("-")
			continue
		var wrist: Vector3 = _final.wrists[side]
		var palm: Vector3 = entry.intended_palm
		hands.append("%s %.1f cm off, reach %.0f%%" % [entry.contact, wrist.distance_to(palm) * 100.0, 100.0 * wrist.distance_to(_final.shoulders[side]) / arm_lengths[side]])
	return {
		"carrier": String(carrier), "passenger": String(passenger),
		"passenger_scale": snappedf(rig.carry_passenger.find_child("PassengerModel", true, false).scale.x, 0.001), "passenger_own_scale": definition.scale,
		"identity_ok": rig.carry_passenger.definition == definition and is_equal_approx(rig.carry_passenger.find_child("PassengerModel", true, false).scale.x, definition.scale),
		"lowest_bone": lowest_bone, "neck_height": snappedf(_final.neck.y - floor_y, 0.01),
		"passenger_y": [snappedf(low if low != INF else 0.0, 0.01), snappedf(high if high != -INF else 0.0, 0.01)],
		"lateral": snappedf(lateral, 0.01), "lowest": snappedf(low if low != INF else 0.0, 0.01), "hands": ", ".join(hands),
		"fit": {"fitted": rig.carry_fit.get("fitted", false), "tuck": rig.carry_fit.get("tuck", 1.0), "slide": str(rig.carry_fit.get("slide", Vector3.ZERO)), "predicted_lowest": snappedf(float(rig.carry_fit.get("lowest", 0.0)), 0.01), "predicted_reach": (rig.carry_fit.get("reach", []) as Array).map(func(r): return snappedf(float(r), 0.01))},
	}


## Shoulder-to-elbow plus elbow-to-wrist, from the rest pose, in metres.
func _arm_length(rig: CharacterRig, chain: Array) -> float:
	var skeleton := rig.skeleton
	var scale := skeleton.global_basis.get_scale().y
	var a := skeleton.get_bone_global_rest(skeleton.find_bone(chain[0])).origin
	var b := skeleton.get_bone_global_rest(skeleton.find_bone(chain[1])).origin
	var c := skeleton.get_bone_global_rest(skeleton.find_bone(chain[2])).origin
	return (a.distance_to(b) + b.distance_to(c)) * scale
