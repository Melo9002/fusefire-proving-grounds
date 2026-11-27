extends SceneTree
## Rendered evidence for the loaded ladder (explicit-only: needs a GPU, not part of the standard tiers): one carrier/passenger pairing climbing or descending the Workbench's ladder with the landing, in paused fixed steps
## so every frame is reproducible, with PNGs at chosen scenario times.
##   godot --path . --script res://tests/loaded_ladder_capture.gd -- <output-folder> carrier=mira_0 passenger=small_mira_0 [direction=1|-1] [times=0,0.5,...] [view=side|front|three_quarter] [width=800 height=800]
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const VIEWS := {
	"side": [Vector3(3.4, 1.7, 0.35), Vector3(0.0, 1.5, 0.35)],
	"front": [Vector3(0.0, 1.8, 3.4), Vector3(0.0, 1.4, 0.0)],
	"three_quarter": [Vector3(2.6, 1.9, 2.6), Vector3(0.0, 1.4, 0.2)],
	"rear": [Vector3(0.0, 1.8, -3.4), Vector3(0.0, 1.4, 0.0)],
	"upper": [Vector3(2.4, 2.4, 1.6), Vector3(0.0, 1.8, 0.1)],
	"rear_quarter": [Vector3(2.0, 1.9, -2.6), Vector3(0.0, 1.35, 0.25)],
	"front_quarter": [Vector3(2.2, 1.6, 3.0), Vector3(0.0, 1.3, 0.2)],
}
var out_dir := "res://artifacts/carry-captures/ladder"
var _args := {"carrier": "mira_0", "passenger": "mira_0", "direction": "1", "times": "0,0.5,1,1.5,2.5,3.5,4.5,5.5", "view": "side", "width": "800", "height": "800", "armed": "false", "landing": "rails", "roll": "", "pitch": "", "yaw": "", "ux": "", "fx": "", "fz": "", "ax": "", "ay": "", "az": "", "lean": "", "thigh": "", "shin": ""}


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var plain := []
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
		else:
			plain.append(argument)
	if plain.size() > 0:
		out_dir = plain[0]
	root.size = Vector2i(int(_args.width), int(_args.height))
	await _frames(3)
	WorkbenchSession.character = StringName(_args.carrier)
	WorkbenchSession.armed = _args.armed == "true"
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(20)
	bench.panel.visible = false
	var rig: CharacterRig = bench.rig
	rig.passenger_definition = PassengerDefinition.for_character(StringName(_args.passenger))
	_tune(rig.loaded_climb_profile)
	rig.begin_carry()
	rig.animation_controller.play(&"carry_idle")
	await _frames(30)
	var camera: Array = VIEWS[_args.view]
	bench.look_from(camera[0], camera[1])
	bench.step_seconds = 1.0 / 30.0
	var direction := int(_args.direction)
	bench.start_ladder_demo(3.0, direction, 0.85, -1.0, String(_args.landing))
	bench.set_sim_paused(true)
	var wanted: Array = String(_args.times).split(",")
	var shot := 0
	var elapsed := 0.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var guard := 0
	while shot < wanted.size() and guard < 3000:
		guard += 1
		if elapsed + 0.0001 >= float(wanted[shot]):
			await _frames(2)
			var name := "%s_carries_%s_%s_t%04.1f_%s.png" % [_args.carrier, _args.passenger, "up" if direction > 0 else "down", float(wanted[shot]), _args.view]
			root.get_texture().get_image().save_png("%s/%s" % [out_dir, name])
			print("saved %s  (climbed %.2f, blend %.2f, ready %s)" % [name, float(bench.ladder_demo.get("climbed", -1)), rig.loaded_ladder.blend if rig.loaded_ladder != null else -1.0, rig.loaded_ladder_ready()])
			shot += 1
			continue
		bench.step_sim()
		await process_frame
		elapsed += 1.0 / 30.0
	quit()


## Capture-time overrides of the profile (for iterating on the carry without editing resources): roll/pitch/yaw degrees, ax/ay/az the anchor from the neck, lean, thigh/shin angles.
func _tune(profile: LoadedClimbProfile) -> void:
	var angles := profile.orientation_degrees
	if String(_args.pitch) != "": angles.x = float(_args.pitch)
	if String(_args.yaw) != "": angles.y = float(_args.yaw)
	if String(_args.roll) != "": angles.z = float(_args.roll)
	profile.orientation_degrees = angles
	var anchor := profile.anchor_from_neck
	if String(_args.ax) != "": anchor.x = float(_args.ax)
	if String(_args.ay) != "": anchor.y = float(_args.ay)
	if String(_args.az) != "": anchor.z = float(_args.az)
	profile.anchor_from_neck = anchor
	if String(_args.lean) != "": profile.climb_lean_degrees = float(_args.lean)
	var up := profile.body_up
	if String(_args.ux) != "": up.x = float(_args.ux)
	profile.body_up = up
	var face := profile.body_face
	if String(_args.fx) != "": face.x = float(_args.fx)
	if String(_args.fz) != "": face.z = float(_args.fz)
	profile.body_face = face
	var pose := profile.pose_overrides.duplicate()
	if String(_args.thigh) != "": pose["thigh"] = float(_args.thigh)
	if String(_args.shin) != "": pose["shin"] = float(_args.shin)
	profile.pose_overrides = pose
