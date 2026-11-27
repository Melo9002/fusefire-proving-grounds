extends SceneTree
## Rendered evidence for the mixed-size carry (explicit-only: needs a GPU, not part of the standard tiers): the real animation workbench, every carrier/passenger pairing, from several cameras, panel hidden.
##   godot --path . --script res://tests/carry_pairing_capture.gd -- <output-folder> [phase=carry|ladder] [width=960 height=720] [carriers=a,b passengers=a,b]
## `phase=carry` is the steady ground carry; the loaded ladder phases are added by the ladder captures.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const VIEWS := {
	"front": [Vector3(0.0, 1.3, 3.2), Vector3(0.0, 0.9, 0.0)],
	"side": [Vector3(3.2, 1.3, 0.0), Vector3(0.0, 0.9, 0.0)],
	"rear": [Vector3(0.0, 1.3, -3.2), Vector3(0.0, 0.9, 0.0)],
	"three_quarter": [Vector3(2.4, 1.7, 2.4), Vector3(0.0, 0.9, 0.0)],
	"shoulder": [Vector3(1.1, 1.5, 1.3), Vector3(0.0, 1.0, 0.0)],
}
var out_dir := "res://docs/claude/images/carry-ladder"
var _args := {"phase": "carry", "width": "960", "height": "720", "carriers": "", "passengers": "", "views": ""}


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
	var characters := PassengerDefinition.known_characters()
	if characters.is_empty():
		characters.assign([&"mira_0", &"small_mira_0"])
	var carriers: Array = characters if String(_args.carriers).is_empty() else String(_args.carriers).split(",")
	var passengers: Array = characters if String(_args.passengers).is_empty() else String(_args.passengers).split(",")
	var views: Array = VIEWS.keys() if String(_args.views).is_empty() else String(_args.views).split(",")
	for carrier in carriers:
		for passenger in passengers:
			await _pairing(StringName(carrier), StringName(passenger), views)
	quit()


func _pairing(carrier: StringName, passenger: StringName, views: Array) -> void:
	WorkbenchSession.character = carrier
	WorkbenchSession.armed = false
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(20)
	bench.panel.visible = false
	var rig: CharacterRig = bench.rig
	rig.passenger_definition = PassengerDefinition.for_character(passenger)
	rig.begin_carry()
	rig.animation_controller.play(&"carry_idle")
	await _frames(40)
	for view in views:
		var camera: Array = VIEWS[view]
		bench.look_from(camera[0], camera[1])
		await _frames(6)
		var path := "%s/%s_carries_%s_%s_%s.png" % [out_dir, carrier, passenger, _args.phase, view]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		root.get_texture().get_image().save_png(path)
		print("saved %s" % path)
	bench.queue_free()
	await _frames(3)
