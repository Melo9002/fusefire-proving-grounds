extends SceneTree

func _initialize() -> void:
	var ground := EnvironmentModuleDefinition.new(&"probe_ground", &"probe", Vector2i.ONE)
	ground.placement_layer = EnvironmentModuleDefinition.PlacementLayer.GROUND
	ground.set_effect(Vector2i.ZERO, {"walkable": true, "can_stop": true, "blocks_los": false})
	var obstacle := EnvironmentModuleDefinition.new(&"probe_obstacle", &"probe", Vector2i.ONE)
	obstacle.set_effect(Vector2i.ZERO, {"walkable": false, "can_stop": false, "blocks_los": true, "cover_type": MapCellData.CoverType.FULL})
	var catalog := {&"probe_ground": ground, &"probe_obstacle": obstacle}
	for reverse in [false, true]:
		var layout := EnvironmentModuleLayout.new(&"probe")
		var ids: Array = [&"probe_ground", &"probe_obstacle"] if not reverse else [&"probe_obstacle", &"probe_ground"]
		for id in ids:
			assert(layout.try_add(catalog[id], EnvironmentModulePlacement.new(id, Vector2i(2, 2)), Vector2i(8, 8)))
		var data := FlatMapGenerator.generate(8, 8, 1.0, 17)
		EnvironmentModuleMapWriter.apply(data, layout, catalog, 1.0)
		var cell := data.get_cell(Vector3i(2, 0, 2))
		print("ORDER reverse=%s walkable=%s blocks_los=%s" % [reverse, cell.walkable, cell.blocks_line_of_sight])
	var stacked := EnvironmentModuleLayout.new(&"stacked_probe")
	assert(stacked.try_add(obstacle, EnvironmentModulePlacement.new(&"probe_obstacle", Vector2i(2, 2), 0, 0, 0), Vector2i(8, 8)))
	var accepted := stacked.try_add(obstacle, EnvironmentModulePlacement.new(&"probe_obstacle", Vector2i(2, 2), 0, 0, 3), Vector2i(8, 8))
	print("STACKED distinct_elevation_accepted=%s errors=%s" % [accepted, stacked.errors])
	quit(0)
