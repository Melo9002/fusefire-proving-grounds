extends SceneTree
## Measures the loaded ladder for every carrier/passenger pairing in both directions, in paused fixed steps, from the FINAL pose (see tests/support/loaded_ladder_measure.gd for exactly what is and is not measured:
## contact-target errors, passenger continuity and clearances against the ground, the deck and the rails and rungs; not mesh penetration).
##
##   godot_console --headless --path . --script res://tools/quality/loaded_ladder_probe.gd -- [json=<path>] [carriers=a,b] [passengers=a,b|none] [armed=false] [directions=1,-1]
##       [ax= ay= az= (the climbing carry's anchor from the neck) ux= (the spine's lean to the carrier's right) fx= fz= (the belly's facing) lean= (trunk lean, degrees)]   <- sweeps without editing resources
## `passengers=none` is the UNLOADED baseline: the same climb with nobody carried, for what the loaded climb should be compared against.

const Measure := preload("res://tests/support/loaded_ladder_measure.gd")

var _args := {"json": "", "carriers": "", "passengers": "", "armed": "false", "directions": "1,-1", "ax": "", "ay": "", "az": "", "ux": "", "fx": "", "fz": "", "lean": "", "roll": "", "pitch": "", "yaw": ""}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	var characters := PassengerDefinition.known_characters()
	if characters.is_empty():
		characters.assign([&"mira_0", &"small_mira_0"])
	var carriers: Array = characters if String(_args.carriers).is_empty() else String(_args.carriers).split(",")
	var passengers: Array = characters if String(_args.passengers).is_empty() else String(_args.passengers).split(",")
	var report: Array[Dictionary] = []
	for carrier in carriers:
		for passenger in passengers:
			for direction in String(_args.directions).split(","):
				var measure := Measure.new()
				report.append(await measure.run(self, StringName(carrier), StringName(passenger), int(direction), {"armed": _args.armed == "true", "tune": _tune}))
	for entry in report:
		print("LADDER %-13s carries %-13s %-4s | free hand %.1f cm (max %.1f) support hand %.1f cm (max %.1f) | feet max %.1f cm | carrier chest step max %.1f cm, passenger step max %.1f cm (relative to the chest %.1f cm at %.1f s), bone step max %.1f cm | above ground/deck: %.2f / %.2f m | limb-to-ladder clearance min %.3f m (%s at %.1f s) | transfer %.2f s, restored %s" % [
			entry.carrier, entry.passenger, "up" if entry.direction > 0 else "down", entry.free_hand_mean_cm, entry.free_hand_max_cm, entry.support_hand_mean_cm, entry.support_hand_max_cm,
			entry.feet_max_cm, entry.chest_step_max_cm, entry.passenger_step_max_cm, entry.relative_step_max_cm, entry.relative_step_at_s, entry.bone_step_max_cm, entry.lowest_m, entry.deck_clearance_min_m,
			entry.ladder_clearance_min_m, entry.ladder_clearance_bone, entry.ladder_clearance_at_s, entry.transfer_seconds, entry.restored])
	if not String(_args.json).is_empty():
		var file := FileAccess.open(String(_args.json), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	quit()


## Profile overrides for sweeps, without editing resources.
func _tune(rig: CharacterRig) -> void:
	var profile := rig.loaded_climb_profile
	var anchor := profile.anchor_from_neck
	if String(_args.ax) != "": anchor.x = float(_args.ax)
	if String(_args.ay) != "": anchor.y = float(_args.ay)
	if String(_args.az) != "": anchor.z = float(_args.az)
	profile.anchor_from_neck = anchor
	var up := profile.body_up
	if String(_args.ux) != "": up.x = float(_args.ux)
	profile.body_up = up
	var face := profile.body_face
	if String(_args.fx) != "": face.x = float(_args.fx)
	if String(_args.fz) != "": face.z = float(_args.fz)
	profile.body_face = face
	var angles := profile.orientation_degrees
	if String(_args.pitch) != "": angles.x = float(_args.pitch)
	if String(_args.yaw) != "": angles.y = float(_args.yaw)
	if String(_args.roll) != "": angles.z = float(_args.roll)
	profile.orientation_degrees = angles
	if String(_args.lean) != "": profile.climb_lean_degrees = float(_args.lean)
