extends SceneTree
## Compiles the Tactical Test Range and prints: errors, doors and their regions, the section's cells, and (with --dump <file>) a per-cell fingerprint of the whole map for before/after comparison.
##   godot_console --headless --path . --script res://docs/quality/evidence/door-test-section/section_probe.gd -- [dump_file]
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")


func _initialize() -> void:
	var map := Catalog.generate(Catalog.TACTICAL_TEST_RANGE, Vector2i.ZERO, 2, 1.0)
	print("errors ", map.generation_errors, " doors ", map.doors.keys())
	for id in map.doors.keys():
		var door: DoorData = map.doors[id]
		print("door ", id, " cell ", door.cell, " state ", door.state, " captured ", door.is_captured(), " region ", door.region())
	print("   8901234")
	for z in range(15, 24):
		var line := ""
		for x in range(8, 15):
			var cell: MapCellData = map.get_cell(Vector3i(x, 0, z))
			var ch := "?"
			if cell != null:
				ch = "." if cell.walkable and cell.can_stop else ("c" if cell.cover_type != MapCellData.CoverType.NONE and cell.walkable else "#")
			line += ch
		print("%02d %s" % [z, line])
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var out := FileAccess.open(args[0], FileAccess.WRITE)
		var keys := map.cells.keys()
		keys.sort()
		for position: Vector3i in keys:
			var c: MapCellData = map.cells[position]
			out.store_line("%s w%d s%d c%d h%.2f l%d p%s" % [position, int(c.walkable), int(c.can_stop), c.cover_type, c.cover_height, int(c.blocks_line_of_sight), c.world_position])
		out.close()
	quit()
