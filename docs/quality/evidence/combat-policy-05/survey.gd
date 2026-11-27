extends "res://docs/quality/evidence/contextual-03b/survey.gd"
## Compare both directions at each unordered pair. One in four stops, all
## inherited vectors. The parent only enables Fleet contextual fire for this survey.

func _survey(site: StringName, grid: GridManager, actor: TacticalUnit, enemy: TacticalUnit) -> void:
	var raw := {}
	var totals := [{"mutual": 0, "one_way": 0, "neither": 0}, {"mutual": 0, "one_way": 0, "neither": 0},
		{"mutual": 0, "one_way": 0, "neither": 0}, {"mutual": 0, "one_way": 0, "neither": 0}]
	var pairs := {}
	var rejects := 0
	for cell: MapCellData in grid.map_data.cells.values():
		var source := cell.grid_position
		if not cell.can_stop or posmod(source.x + 3 * source.z + source.y, 4) != 0: continue
		if is_instance_valid(grid.get_unit_at(source)): continue
		for delta in VECTORS:
			var dest: Vector3i = source + delta
			var target := grid.map_data.get_cell(dest)
			if not target or not target.can_stop or is_instance_valid(grid.get_unit_at(dest)): continue
			if pairs.has([dest, source]): continue
			pairs[[source, dest]] = true
			var forward := _geometry(actor, source, enemy, dest, grid)
			var reverse := _geometry(enemy, dest, actor, source, grid)
			var legacy_count := int(forward[0]) + int(reverse[0])
			var core_count := int(forward[1]) + int(reverse[1])
			for i in [0, 1, 2, 3]:
				var count := legacy_count if i == 0 or i == 2 else core_count
				if i >= 2 and count == 1: count = 0
				var key: String = ["neither", "one_way", "mutual"][count]
				totals[i][key] += 1
			rejects += int(legacy_count == 1)
			_count(raw, "mutual_direct", int(forward[2] and reverse[2]))
			_count(raw, "mutual_requiring_step", int(legacy_count == 2 and not (forward[2] and reverse[2])))
			_count(raw, "peripheral_only_directions", int(forward[0] and not forward[1]) + int(reverse[0] and not reverse[1]))
			_count(raw, "centrally_exposed_directions", core_count)
	print("[PolicySurvey] ", JSON.stringify({"map": site, "pairs": pairs.size(), "A_B_C_D": totals, "symmetric_rejects": rejects, "physical": raw}))

func _geometry(actor: TacticalUnit, source: Vector3i, target: TacticalUnit, dest: Vector3i, grid: GridManager) -> Array[bool]:
	var direct: Dictionary = CombatRules._evaluate_target_visibility_cells(actor, source, target, dest, grid)
	var legacy: bool = direct.visible_count > 0
	var central: bool = direct.central_visible
	return [legacy or CombatRules._contextual_step(actor, source, target, dest, grid, {}, true) != null,
		central or CombatRules._contextual_step(actor, source, target, dest, grid, {}, true, true) != null, legacy]

func _count(data: Dictionary, key: String, amount: int) -> void:
	data[key] = int(data.get(key, 0)) + amount
