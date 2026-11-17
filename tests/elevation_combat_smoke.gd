extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func place(unit: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)

func _run() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1)
	root.add_child(level)
	await create_timer(0.15).timeout

	var battle = level.battle_controller
	var grid = battle.grid_manager
	var attacker: TacticalUnit = level.turn_manager.player_units[0]
	var target: TacticalUnit = level.turn_manager.enemy_units[0]
	attacker.attack_range = 20
	target.attack_range = 20

	var ladder_bottom := Vector3i(7, 0, 6)
	var ladder_top := Vector3i(7, 2, 5)
	place(attacker, ladder_bottom, grid)
	place(target, ladder_top, grid)
	check(battle.evaluate_attack(attacker, target).is_legal, "A ground unit can see a target at the platform edge")
	check(CombatRules.has_line_of_sight_to_position(attacker, grid.grid_to_world(ladder_top), grid, battle.get_world_3d()), "Elevated attack preview matches target validation")

	var elevated_attacker := Vector3i(14, 2, 8)
	grid.map_data.add_cell(MapCellData.new(elevated_attacker, grid.grid_to_world(elevated_attacker)))
	place(attacker, elevated_attacker, grid)
	place(target, Vector3i(18, 0, 8), grid)
	var descending_shot = battle.evaluate_attack(attacker, target)
	check(descending_shot.is_legal and descending_shot.hit_chance < 100, "An elevated attacker can take a penalized partial shot over a full-height wall")
	check(descending_shot.visibility_fraction > 0.0 and descending_shot.visibility_fraction < 1.0, "Descending fire reports the visible fraction of the target")

	var elevated_target := Vector3i(18, 2, 8)
	grid.map_data.add_cell(MapCellData.new(elevated_target, grid.grid_to_world(elevated_target)))
	place(target, elevated_target, grid)
	check(battle.evaluate_attack(attacker, target).is_legal, "A level shot above a wall remains legal")

	var target_above_low_cover := Vector3i(9, 2, 9)
	grid.map_data.add_cell(MapCellData.new(target_above_low_cover, grid.grid_to_world(target_above_low_cover)))
	place(attacker, Vector3i(9, 0, 6), grid)
	place(target, target_above_low_cover, grid)
	var elevated_cover = battle.evaluate_attack(attacker, target)
	check(elevated_cover.is_legal and elevated_cover.cover_type == MapCellData.CoverType.NONE and elevated_cover.height_modifier == -10 and elevated_cover.hit_chance == 90, "Ground cover does not protect the elevated target, but the shooter still has a low-ground penalty")

	level.queue_free()
	await process_frame
	print("Elevation combat smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
