extends SceneTree
## Characterizes the current approximation in live gameplay. An intentional
## geometry improvement should revise the documented limitation assertions.
const Bounds = preload("res://tools/parcel_editor/mesh_tactical_bounds.gd")
const Content = preload("res://systems/generation2/local_parcel_content.gd")
var failures := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/mesh-battle-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _part(at: Vector3, size: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	part.mesh.size = size
	part.position = at
	return part

func _arch(at: Vector3, combined: bool) -> Node3D:
	var object := Node3D.new()
	object.position = at
	var surface := SurfaceTool.new()
	for spec in [[Vector3(-2, 1.2, 0), Vector3(1, 2.4, 1)], [Vector3(2, 1.2, 0), Vector3(1, 2.4, 1)], [Vector3(0, 3.2, 0), Vector3(5, 0.4, 1)]]:
		var part := _part(spec[0], spec[1])
		if combined:
			surface.append_from(part.mesh, 0, part.transform)
			part.free()
		else: object.add_child(part)
	if combined:
		var part := MeshInstance3D.new()
		part.mesh = surface.commit()
		object.add_child(part)
	Bounds.add_to(object)
	return object

func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)

func _run() -> void:
	var source: AuthoredParcelDefinition = AuthoredParcelCatalog.get_definition(AuthoredParcelCatalog.LOADING_YARD_A)
	var parcel: Node3D = source.instantiate()
	var separate := _arch(Vector3(10, 0, 25), false)
	var combined := _arch(Vector3(4, 0, 21), true)
	parcel.add_child(separate)
	parcel.add_child(combined)
	var raised := Node3D.new()
	raised.position = Vector3(10, 0, 20)
	raised.add_child(_part(Vector3(0, 1, 0), Vector3(1, 1, 2)))
	Bounds.add_to(raised)
	parcel.add_child(raised)
	for added in [separate, combined, raised]:
		added.owner = parcel
		_own(added, parcel)
	var packed := PackedScene.new()
	check(packed.pack(parcel) == OK, "Preserve the difficult-shape test content")
	parcel.free()
	var archived := Content.archive(packed)
	check(not archived.has("error"), "Archive the exact geometry for a real Generation 2 battle")
	if archived.has("error"): quit(1); return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.PARCEL_TEST)
	config.content_manifest = {"local_content": archived.content, "population_enabled": false}
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	for frame in 240:
		if level.battle_initialization_succeeded or not level.battle_initialization_errors.is_empty(): break
		await process_frame
	check(level.battle_initialization_succeeded, "Difficult mesh parts compile in a real validated battle: " + str(level.battle_initialization_errors))
	if level.battle_initialization_succeeded:
		var grid := level.battle_controller.grid_manager
		check(grid.map_data.get_cell(Vector3i(10, 0, 25)).can_stop, "Separate doorway parts preserve the walkable center under a high beam")
		check(not level.battle_controller.pathfinder.calculate_3d_path(Vector3i(10, 0, 23), Vector3i(10, 0, 27)).is_empty(), "Live battle pathfinding can traverse the open doorway")
		check(not grid.map_data.get_cell(Vector3i(4, 0, 21)).can_stop, "Documented limitation: the same doorway combined into one mesh fills its opening with a box")
		check(not grid.map_data.get_cell(Vector3i(10, 0, 20)).can_stop, "A raised body reserves standing clearance")
		var from := grid.grid_to_world(Vector3i(10, 0, 23)) + Vector3.UP
		var to := grid.grid_to_world(Vector3i(10, 0, 27)) + Vector3.UP
		check(CombatRules.get_blocking_cell(from, to, grid) == null, "The real shot query passes through the separate-parts opening")
		from = grid.grid_to_world(Vector3i(4, 0, 19)) + Vector3.UP
		to = grid.grid_to_world(Vector3i(4, 0, 23)) + Vector3.UP
		check(CombatRules.get_blocking_cell(from, to, grid) != null, "Documented limitation: one combined concave mesh blocks a shot through the visible hole")
		from = grid.grid_to_world(Vector3i(8, 0, 20)) + Vector3.UP * 0.15
		to = grid.grid_to_world(Vector3i(12, 0, 20)) + Vector3.UP * 0.15
		check(CombatRules.get_blocking_cell(from, to, grid) == null, "Standing clearance does not invent shot blockers beneath a raised part")
		check(CombatRules.get_blocking_cell(from + Vector3.UP * 0.85, to + Vector3.UP * 0.85, grid) != null, "The same raised part blocks shots through its visible body")
	level.queue_free()
	await process_frame
	await process_frame
	if archived.created: DirAccess.remove_absolute(Content.snapshot_path(archived.content.snapshot))
	print("Mesh boundary live battle: %d failure(s)" % failures)
	quit(1 if failures else 0)
