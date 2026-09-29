extends SceneTree

var failures := 0

func _initialize() -> void:
	var grid := GridManager.new()
	grid.map_data = MapData.new()
	for x in 4:
		for z in 4:
			var cell := Vector3i(x, 0, z)
			grid.map_data.add_cell(MapCellData.new(cell, Vector3(x, 0, z)))
	check(CombatRules.can_reach_adjacent(Vector3i.ZERO, Vector3i(1, 0, 1), grid), "Clear diagonal rescue")
	var first := grid.get_cell_data(Vector3i.RIGHT)
	first.walkable = false
	first.can_stop = false
	first.blocks_line_of_sight = true
	first.cover_height = 2.0
	check(not CombatRules.can_reach_adjacent(Vector3i.ZERO, Vector3i(1, 0, 1), grid), "Rescue cannot cut one corner")
	var second := grid.get_cell_data(Vector3i.BACK)
	second.walkable = false
	second.can_stop = false
	second.blocks_line_of_sight = true
	second.cover_height = 2.0
	grid.map_data.rebuild_los_index()
	check(CombatRules.get_blocking_cell(Vector3(0, 1, 0), Vector3(1, 1, 1), grid) != null, "Touching blocks seal diagonal shot")
	check(CombatRules.get_blocking_cell(Vector3(1, 1, 1), Vector3(0, 1, 0), grid) != null, "Seam blocks in reverse too")
	check(CombatRules.get_blocking_cell(Vector3(0, 3, 0), Vector3(1, 3, 1), grid) == null, "Shots above obstacles remain legal")
	second.cover_height = 0.0
	grid.map_data.rebuild_los_index()
	check(CombatRules.get_blocking_cell(Vector3(0, 1, 0), Vector3(1, 1, 1), grid) == null, "Single corner may be grazed")
	check(not CombatRules.can_reach_adjacent(Vector3i.ZERO, Vector3i(1, 1, 1), grid), "Rescue does not bridge elevation")
	grid.free()
	print("[DiagonalCombat] %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
