extends SceneTree
## Scene contracts and geometry invariants. Future balance is deliberately not asserted.
const Generator = preload("res://systems/generation2/generator.gd")
var failures := 0
var checks := 0
var level: BattleLevel
var grid: GridManager
var examples: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _point(path: String) -> Vector3:
	return (examples.get_node(path) as Node3D).global_position

func _probe(station: String, lane: String, blocked: bool) -> void:
	var source := _point(station + "/" + lane + "Shooter")
	var target := _point(station + "/" + lane + "Target")
	for reverse in [false, true]:
		var hit := CombatRules.get_blocking_cell(target if reverse else source, source if reverse else target, grid)
		check((hit != null) == blocked, "%s/%s reverse=%s matches authored geometry" % [station, lane, reverse])

func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell)

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.battle_seed = 17
	config.content_manifest = {"population_enabled": false}
	config.player_count = 1
	config.enemy_count = 1
	config.ally_count = 0
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "The edited range starts through the real Generation 2 battle pipeline")
	if not level.battle_initialization_succeeded:
		level.free()
		quit(1)
		return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	grid = level.battle_controller.grid_manager
	examples = level.find_child("CombatExamples", true, false) as Node3D
	check(examples != null, "Battle presentation includes the editable example scene")
	if examples == null:
		level.free()
		quit(1)
		return
	_probe("Truck", "Cargo", true)
	_probe("Truck", "Hood", false)
	_probe("Doorway", "Opening", false)
	_probe("Doorway", "Wall", true)
	_probe("Doorway", "Lintel", true)
	_probe("Corners", "Seam", true)
	_probe("Corners", "Single", false)
	var beam_source := _point("RaisedBeam/Shooter")
	var beam_target := _point("RaisedBeam/Target")
	check(CombatRules.get_blocking_cell(beam_source, beam_target, grid) != null, "Raised beam blocks independently of any deck")
	check(CombatRules.get_blocking_cell(beam_target, beam_source, grid) != null, "Raised beam blocks independently in reverse")
	check(CombatRules.get_blocking_cell(beam_source - Vector3.UP * 1.7, beam_target - Vector3.UP * 1.7, grid) == null, "Raised beam leaves the ground-level firing lane clear")
	check(grid.get_cell_data(Vector3i(17, 0, 17)).can_stop, "Raised beam does not become an invisible ground wall")
	var seam_source := _point("Corners/SeamShooter") + Vector3.UP * 2
	var seam_target := _point("Corners/SeamTarget") + Vector3.UP * 2
	check(CombatRules.get_blocking_cell(seam_source, seam_target, grid) == null, "A shot above the sealed corner remains clear")
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var target: TacticalUnit = level.turn_manager.enemy_units[0]
	for prefix in ["Low", "Full"]:
		var source_cell := grid.world_to_grid(_point("Crates/" + prefix + "Shooter"))
		var target_cell := grid.world_to_grid(_point("Crates/" + prefix + "Target"))
		check(grid.can_unit_occupy_cell(actor, source_cell) and grid.can_unit_occupy_cell(target, target_cell), prefix + " crate endpoints are valid standing cells")
		_place(actor, source_cell)
		_place(target, target_cell)
		var evaluation := CombatRules.evaluate_attack(actor, target, grid, level.get_world_3d())
		check(evaluation.is_legal and evaluation.visibility_fraction > 0 and evaluation.visibility_fraction < 1, prefix + " crate allows a genuinely partially exposed body shot")
		var expected_cover := MapCellData.CoverType.LOW if prefix == "Low" else MapCellData.CoverType.FULL
		check(evaluation.cover_type == expected_cover, prefix + " crate compiles to its intended cover class")
		var flank := target_cell + Vector3i(2, 0, 0)
		_place(actor, flank)
		check(CombatRules.evaluate_attack(actor, target, grid, level.get_world_3d()).cover_type == MapCellData.CoverType.NONE, prefix + " crate has an open side for a controlled flank")
	var doorway_cell := Vector3i(17, 0, 22)
	check(grid.get_cell_data(doorway_cell).walkable and grid.get_cell_data(doorway_cell).can_stop, "Door opening is usable ground, not just a visual gap")
	check(not grid.get_cell_data(Vector3i(15, 0, 22)).can_stop, "Door wall blocks standing as well as shots")
	var pathfinder := Pathfinder.new()
	MapGraphBuilder.build(grid.map_data, pathfinder)
	check(not pathfinder.calculate_3d_path(Vector3i(17, 0, 20), Vector3i(17, 0, 24)).is_empty(), "Traversal can pass through the doorway")
	for column in [Vector2i(6, 6), Vector2i(8, 7)]:
		for elevation in [0, 3, 6]:
			check(grid.map_data.has_cell(Vector3i(column.x, elevation, column.y)), "Stacked gallery retains distinct surface %s at height %d" % [column, elevation])
	check(not pathfinder.calculate_3d_path(Vector3i(6, 0, 15), Vector3i(6, 3, 11)).is_empty(), "Existing stairs connect ground to the lower gallery")
	check(not pathfinder.calculate_3d_path(Vector3i(11, 0, 15), Vector3i(11, 3, 11)).is_empty(), "Existing ramp connects ground to the lower gallery")
	check(not pathfinder.calculate_3d_path(Vector3i(7, 3, 9), Vector3i(7, 6, 7)).is_empty(), "Existing ladder connects the two stacked floors")
	check(not pathfinder.calculate_3d_path(Vector3i(15, 0, 23), Vector3i(15, 3, 22)).is_empty(), "Doorway beam has real ladder access rather than a disconnected tactical surface")
	var under_gallery := grid.grid_to_world(Vector3i(8, 0, 7)) + Vector3.UP
	var over_gallery := grid.grid_to_world(Vector3i(8, 6, 7)) + Vector3.UP
	check(CombatRules.get_blocking_cell(under_gallery, over_gallery, grid) != null, "Stacked floor slabs block shooting vertically through the galleries")
	actor.attack_range = 10
	_place(actor, grid.world_to_grid(_point("RangeLane/Shooter")))
	for destination in ["SafeTarget", "FalloffTarget", "EdgeTarget", "BeyondTarget"]:
		_place(target, grid.world_to_grid(_point("RangeLane/" + destination)))
		var shot := CombatRules.evaluate_attack(actor, target, grid, level.get_world_3d())
		check(shot.is_legal == (destination != "BeyondTarget"), "Clear range lane %s obeys maximum reach without asserting future hit chances" % destination)
	var exact := Generator.generate(Generator.RANGE_SOURCE, 999, 1.0, grid.map_data.content_manifest)
	check(exact.generation_errors.is_empty() and exact.content_manifest == grid.map_data.content_manifest, "Recorded range choices reconstruct without substituting a new seed")
	var stale := grid.map_data.content_manifest.duplicate(true)
	stale.placements[0].parcel_revision = 1
	var rejected := Generator.generate(Generator.RANGE_SOURCE, 17, 1.0, stale)
	check(not rejected.generation_errors.is_empty(), "Pre-edit range revision is rejected explicitly rather than replayed with new obstacles")
	var original_data := grid.map_data
	for map_seed in [16, 17]:
		for population in [false, true]:
			var variant := Generator.generate(Generator.RANGE_SOURCE, map_seed, 1.0, {"population_enabled": population})
			check(variant.generation_errors.is_empty(), "Seed %d population=%s compiles without errors" % [map_seed, population])
			grid.map_data = variant
			_probe("Truck", "Cargo", true)
			_probe("Truck", "Hood", false)
			_probe("Doorway", "Opening", false)
			_probe("Doorway", "Lintel", true)
			_probe("Corners", "Seam", true)
			_probe("Corners", "Single", false)
	grid.map_data = original_data
	if OS.get_cmdline_user_args().has("capture") and DisplayServer.get_name() != "headless":
		await _capture()
	level.queue_free()
	await process_frame
	await process_frame
	print("Controlled combat examples: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _capture() -> void:
	level.get_node("Visualizers/BattleUI").hide()
	# The fixed ray diagnostic must not be cleared by normal mouse-hover updates.
	level.battle_controller.set_process(false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.make_current()
	DirAccess.make_dir_recursive_absolute("res://artifacts/combat-examples")
	for view in [
		["range-overview", Vector3(23, 32, 29), Vector3(0, 0, 0), 40],
		["doorway-and-crates", Vector3(16, 10, 20), Vector3(6, 1, 5), 19],
		["doorway-front", Vector3(1.5, 3.5, 15), Vector3(1.5, 1.4, 6.5), 9],
		["truck-and-corners", Vector3(15, 12, 9), Vector3(7, 0, -10), 18],
		["raised-beam", Vector3(10, 7, 13), Vector3(1.5, 1.5, 1.5), 12],
	]:
		camera.size = view[3]
		camera.position = view[1]
		camera.look_at(view[2])
		if view[0] == "raised-beam":
			var source := _point("RaisedBeam/Shooter")
			var destination := _point("RaisedBeam/Target")
			var blocker := CombatRules.get_blocking_cell(source, destination, grid)
			var diagnostic := CombatRules.AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Blocked", destination, 0, "Blocked", blocker)
			level.battle_controller.shot_trajectory_visualizer.draw_trajectory(source, destination, diagnostic, true)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://artifacts/combat-examples/%s.png" % view[0]) == OK, "Rendered view saved: %s" % view[0])
	camera.free()
