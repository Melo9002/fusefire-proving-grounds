extends SceneTree
## Offline investigation only. Does not enable destruction in playable battles.
const Examples := preload("res://art/environments/authored/components/combat_examples.tscn")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _scene(offset := 0.0, overlapping := false) -> Node3D:
	var examples := Examples.instantiate()
	var scene := Node3D.new()
	var crate := examples.get_node("Crates/FullCrate").duplicate() as Node3D
	crate.position.x += offset
	scene.add_child(crate)
	if overlapping:
		var independent := crate.duplicate()
		independent.name = "IndependentBlocker"
		scene.add_child(independent)
	examples.free()
	return scene

func _compile(scene: Node3D) -> MapData:
	var data := TacticalMapBuilder.generate(32, 32, 1, 17)
	AuthoredSceneMapCompiler.compile(scene, data, 1, Transform3D(Basis.IDENTITY, Vector3(-15.5, 0, -15.5)))
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	return data

func _blocked(grid: GridManager) -> bool:
	var from := grid.get_cell_data(Vector3i(27, 0, 13)).world_position + Vector3.UP
	var to := grid.get_cell_data(Vector3i(27, 0, 17)).world_position + Vector3.UP
	return CombatRules.get_blocking_cell(from, to, grid) != null

func _run() -> void:
	var scene := _scene()
	var grid := GridManager.new()
	root.add_child(grid)
	grid.map_data = _compile(scene)
	var intact := grid.map_data
	var crate_cell := Vector3i(27, 0, 16)
	var target := Vector3i(27, 0, 17)
	var shooter := Vector3i(27, 0, 13)
	check(not intact.get_cell(crate_cell).can_stop and not SurfaceNavigation.body_clear(intact, intact.get_cell(crate_cell).support_center), "Intact real full-crate geometry rejects a standing body")
	check(_blocked(grid), "The crate blocks a chest-height shot through its body")
	check(CombatRules.get_directional_cover(shooter, target, grid) == MapCellData.CoverType.FULL, "The adjacent target gets physical full cover")
	var initial_signature := SurfaceNavigation.signature(intact)
	var crate := scene.get_node("FullCrate") as Node3D
	crate.hide()
	check(SurfaceNavigation.signature(_compile(scene)) == initial_signature, "Hiding the mesh does not remove tactical metadata during compilation")
	crate.free()
	intact.rebuild_los_index()
	check(_blocked(grid) and not intact.get_cell(crate_cell).can_stop, "Deleting the source node and refreshing LOS alone leaves compiled collision/standing data intact")
	var removed := _compile(scene)
	grid.map_data = removed
	check(removed.get_cell(crate_cell).can_stop and SurfaceNavigation.body_clear(removed, removed.get_cell(crate_cell).world_position), "Fresh compilation without the crate permits standing in its former footprint")
	check(not _blocked(grid), "Fresh compilation removes the crate's shot obstruction")
	check(CombatRules.get_directional_cover(shooter, target, grid) == MapCellData.CoverType.NONE, "Fresh compilation removes its directional cover")
	var pathfinder := Pathfinder.new()
	MapGraphBuilder.build(removed, pathfinder)
	check(pathfinder.get_reachable_cells(target, 1).has(crate_cell), "Rebuilt navigation reaches the newly open ground")
	check(initial_signature != SurfaceNavigation.signature(removed), "The existing geometry/standing fingerprint distinguishes intact and removed maps")
	# A revisioned identity + removed state can reconstruct equivalent geometry,
	# but this toy record is deliberately not a production battle replay command.
	var decision := {"object_id": "range_full_crate", "state": "removed"}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(decision))
	var reconstructed := _scene()
	if saved.object_id == "range_full_crate" and saved.state == "removed": reconstructed.get_node("FullCrate").free()
	check(SurfaceNavigation.signature(_compile(reconstructed)) == SurfaceNavigation.signature(removed), "An explicit identity/state reconstructs the same post-removal geometry through JSON")
	check(not ReplayRecordTools.validate_action_record({"kind": "destroy_cover", "actor": "PlayerUnit1"}, BattleReplayRecording.CURRENT_SCHEMA_VERSION).is_empty(), "The current replay schema does not silently accept a new destruction action")
	reconstructed.free()
	scene.free()
	# A fresh global solve can move existing stand points even if their cell IDs
	# do not change. A live feature must preserve occupied positions explicitly.
	var shifted := _scene(0.35)
	var before := _compile(shifted)
	shifted.get_node("FullCrate").free()
	var after := _compile(shifted)
	var neighbor := Vector3i(28, 0, 16)
	check(before.get_cell(neighbor).can_stop and after.get_cell(neighbor).can_stop and not before.get_cell(neighbor).world_position.is_equal_approx(after.get_cell(neighbor).world_position), "Global recompilation recenters an adjacent supported point without changing its cell identity")
	print("[Destruction study] Adjacent standing point: %s -> %s" % [before.get_cell(neighbor).world_position, after.get_cell(neighbor).world_position])
	shifted.free()
	var overlap := _scene(0, true)
	var both := _compile(overlap)
	overlap.get_node("FullCrate").free()
	grid.map_data = _compile(overlap)
	check(both.movement_parts.size() == 1 and grid.map_data.movement_parts.size() == 1, "Identical overlapping movement volumes are deduplicated without owner identities")
	check(_blocked(grid) and not grid.map_data.get_cell(crate_cell).can_stop, "Removing one source preserves the independent overlapping blocker")
	overlap.free()
	grid.free()
	print("Destructible cover investigation: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
