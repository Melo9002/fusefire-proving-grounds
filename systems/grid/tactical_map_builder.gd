class_name TacticalMapBuilder
extends RefCounted
## Empty tactical grid and deterministic deployment candidates, independent of content generators.

static func generate(width: int, depth: int, cell_size: float, map_seed: int, spawn_capacity: int = 5, extra_ally_slots: int = 0) -> MapData:
	var map_data := MapData.new()
	map_data.source_kind = "generated_flat"
	map_data.generation_seed = map_seed
	map_data.map_size = Vector2i(width, depth)
	var half_width := float(width) * cell_size * 0.5
	var half_depth := float(depth) * cell_size * 0.5
	for x in width:
		for z in depth:
			var cell_position := Vector3i(x, 0, z)
			var world_position := Vector3(
				float(x) * cell_size - half_width + cell_size * 0.5,
				0.0,
				float(z) * cell_size - half_depth + cell_size * 0.5
			)
			map_data.add_cell(MapCellData.new(cell_position, world_position))

	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var available_rows: Array[int] = []
	for z in range(1, depth - 1):
		available_rows.append(z)
	_shuffle(available_rows, rng)
	var player_rows := available_rows.slice(0, spawn_capacity)
	_shuffle(available_rows, rng)
	var enemy_rows := available_rows.slice(0, spawn_capacity)
	_shuffle(available_rows, rng)
	var ally_rows := available_rows.slice(0, spawn_capacity + extra_ally_slots)
	var player_x := 1
	var enemy_x := width - 2
	if rng.randi_range(0, 1) == 1:
		player_x = width - 2
		enemy_x = 1
	for row in player_rows:
		map_data.add_spawn_cell(TacticalUnit.Faction.PLAYER, Vector3i(player_x, 0, row))
	for row in enemy_rows:
		map_data.add_spawn_cell(TacticalUnit.Faction.ENEMY, Vector3i(enemy_x, 0, row))
	var ally_x := player_x + (1 if player_x < enemy_x else -1)
	for row in ally_rows:
		map_data.add_spawn_cell(TacticalUnit.Faction.ALLY, Vector3i(ally_x, 0, row))
	map_data.rebuild_los_index()
	return map_data

static func _shuffle(values: Array[int], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap_index]
		values[swap_index] = held
