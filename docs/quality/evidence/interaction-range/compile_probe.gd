extends SceneTree
## First look at how the existing compiler reads the Interaction Range (both door states): generation errors, spawn cells, which cells around the partition are standable, the doorway and window cells, and
## the nearest blockers. Output is text.
##   godot_console --headless --path . --script res://docs/quality/evidence/interaction-range/compile_probe.gd
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")


func _initialize() -> void:
	for map_seed in [2, 3]:
		var data := Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, map_seed, 1.0)
		print("== seed %d: errors %s, source %s, size %s, plot %s, parcel %s" % [map_seed, data.generation_errors, data.source_kind, data.map_size, data.content_manifest.get("plot_id"), data.content_manifest.get("placements", [])])
		for faction in [0, 1, 2]:
			print("  spawn faction %d: %s" % [faction, data.get_spawn_cells(faction)])
		# A grid of the parcel (x across 0..15, z down 0..31): '.' standable at the cell centre, 'o' standable but with the standing point displaced from the centre (the cell is only partly free), 'w' walkable
		# but not standable (low cover / vault), '#' blocked.
		for z in range(0, 32):
			var row := ""
			for x in range(0, 16):
				var cell := data.get_cell(Vector3i(x, 0, z))
				if cell == null:
					row += " "
				elif cell.walkable and cell.can_stop:
					var centre := cell.support_center
					var off := Vector2(cell.world_position.x - centre.x, cell.world_position.z - centre.z).length()
					row += "." if off < 0.05 else "o"
				elif cell.walkable:
					row += "w"
				else:
					row += "#"
			print("  z=%2d %s" % [z, row])
		for probe in [Vector3i(7, 0, 12), Vector3i(7, 0, 11), Vector3i(7, 0, 13), Vector3i(10, 0, 12), Vector3i(12, 0, 7), Vector3i(12, 0, 17), Vector3i(6, 0, 13)]:
			var cell := data.get_cell(probe)
			var off2 := Vector2(cell.world_position.x - cell.support_center.x, cell.world_position.z - cell.support_center.z)
			print("  offset %s cell %s: walkable %s can_stop %s cover %s height %.2f blocks_los %s shot_parts %d" % [off2, probe, cell.walkable, cell.can_stop, cell.cover_type, cell.cover_height, cell.blocks_los if "blocks_los" in cell else cell.blocks_line_of_sight, cell.authored_shot_parts.size()])
	quit()
