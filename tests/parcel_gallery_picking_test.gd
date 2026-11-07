extends SceneTree

const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cases := [
		[Catalog.REFINERY_2, 16, [Vector3i(16, 4, 27)]],
		[Catalog.REFINERY_FAMILY, 16, [Vector3i(8, 4, 52)]],
		[Catalog.URBAN_FAMILY, 17, [Vector3i(12, 4, 41), Vector3i(51, 4, 22)]],
	]
	for test_case in cases:
		var config := BattleConfiguration.new()
		config.generated_map = true
		config.select_battlefield(test_case[0])
		config.battle_seed = test_case[1]
		config.player_count = 2
		config.enemy_count = 2
		var level := BattleScene.instantiate() as BattleLevel
		level.configure_battle(config)
		root.add_child(level)
		await physics_frame
		await physics_frame
		_check(level.battle_initialization_succeeded, "%s initializes" % test_case[0])
		if level.battle_initialization_succeeded:
			var rig := level.get_node("CameraRig") as TacticalCamera
			rig.set_process(false)
			rig._cancel_selection_focus()
			var raycaster := level.get_node("Systems/MouseRaycaster") as MouseRaycaster
			var controller := level.battle_controller
			var grid := controller.grid_manager
			for expected: Vector3i in test_case[2]:
				var target := grid.grid_to_world(expected)
				rig.camera.global_position = target + Vector3(0, 18, 0.2)
				rig.camera.look_at(target)
				var screen_point := rig.camera.unproject_position(target)
				raycaster._inspect_level(4.0)
				var hit := raycaster.get_floor_raycast_result(screen_point)
				_check(hit.get("grid_position") == expected, "%s picks its authored deck at %s: %s" % [test_case[0], expected, hit])
				raycaster._inspect_level(0.0)
				var ground_position := Vector3i(expected.x, 0, expected.z)
				var ground := grid.get_cell_data(ground_position)
				var ground_hit := raycaster.get_floor_raycast_result(screen_point)
				if ground and ground.walkable and ground.can_stop:
					_check(ground_hit.get("grid_position") == ground_position, "%s can also pick ground below %s: %s" % [test_case[0], expected, ground_hit])
				else:
					_check(ground_hit.is_empty(), "%s leaves blocked ground under %s unpickable" % [test_case[0], expected])
				if test_case[0] == Catalog.REFINERY_FAMILY and hit.get("grid_position") == expected:
					var actor := level.turn_manager.active_unit
					var ladder_bottom := Vector3i(8, 0, 53)
					grid.update_unit_position(actor, actor.grid_position, ladder_bottom)
					actor.global_position = grid.grid_to_world(ladder_bottom) + Vector3.UP * actor.standing_height
					var completed := await controller.try_move(actor, grid.world_to_grid(hit.position))
					_check(completed and actor.grid_position == expected, "The picked upper cell can be reached through a real movement action")
		level.queue_free()
		await process_frame
		await process_frame
	print("Parcel gallery picking: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
