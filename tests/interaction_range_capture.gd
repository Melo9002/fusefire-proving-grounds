extends SceneTree
## Rendered views of the Interaction Range in both static door states (explicit-only, needs a display):
##   godot_console --path . --script res://tests/interaction_range_capture.gd -- <directory> [width=1280] [height=800]
## Opens a real battle on seeds 2 (door closed) and 3 (open) and saves an overview and close views of the door, the window and an exterior doorway, from the battle's own camera rig.
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
var _directory := ""
var _size := Vector2i(1280, 800)


func _initialize() -> void:
	_run.call_deferred()


func _snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [_directory, name])
	print("saved ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_directory = args[0]
	DirAccess.make_dir_recursive_absolute(_directory)
	for map_seed in [2, 3]:
		var state := "closed" if map_seed % 2 == 0 else "open"
		var config := BattleConfiguration.new()
		config.generated_map = true
		config.select_battlefield(Catalog.INTERACTION_RANGE)
		config.player_count = 2
		config.enemy_count = 2
		config.battle_seed = map_seed
		var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		level.configure_battle(config)
		root.add_child(level)
		await create_timer(1.5).timeout
		level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
		var rig := level.get_node("CameraRig") as TacticalCamera
		var grid: GridManager = level.battle_controller.grid_manager
		for view in [["overview", Vector3i(7, 0, 15), 26.0], ["door", Vector3i(7, 0, 12), 7.0], ["window", Vector3i(10, 0, 12), 7.0], ["doorway", Vector3i(12, 0, 7), 7.0]]:
			rig.global_position = grid.grid_to_world(view[1])
			rig._set_zoom(view[2])
			await create_timer(0.8).timeout
			await _snap("%s_%s" % [state, view[0]])
		level.queue_free()
		await process_frame
		await process_frame
	quit()
