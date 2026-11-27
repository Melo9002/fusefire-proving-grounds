extends RefCounted
## Small opt-in battlefield. Existing mission and replay hosts reconstruct it
## from the named battlefield and seed. Odd seeds defend the player-side bay.

const SIZE := 12
const REST := Vector3i(6, 0, 3)
const TARGET := Vector3i(6, 0, 8)
const OFFSET := Vector3(0.24, 0, 0)
const WALL_OFFSET := Vector3(-0.425, 1.15, 1.20)
const WALL_SIZE := Vector3(1.0, 2.3, 0.10)

static func _rotated(seed_value: int) -> bool:
	return posmod(seed_value - 1, 4) >= 2

static func _cell_at(cell: Vector3i, seed_value: int) -> Vector3i:
	return Vector3i(SIZE - 1 - cell.x, cell.y, SIZE - 1 - cell.z) if _rotated(seed_value) else cell

static func _vector_at(point: Vector3, seed_value: int) -> Vector3:
	return Vector3(-point.x, point.y, -point.z) if _rotated(seed_value) else point

static func generate(seed_value: int, unit: float) -> MapData:
	var data := TacticalMapBuilder.generate(SIZE, SIZE, unit, seed_value)
	data.source_kind = "contextual_firing_bay"
	data.surface_placement_enabled = true
	var home := _cell_at(REST, seed_value)
	var wall := Node3D.new()
	wall.position = data.get_cell(home).world_position + _vector_at(WALL_OFFSET, seed_value)
	wall.set_meta("solid_size", WALL_SIZE)
	wall.set_meta("shot_label", "Corner wall")
	AuthoredSceneMapCompiler.compile(wall, data, unit)
	wall.free()
	# Bay recordings have a fixed seed-only layout, with no compiler manifest.
	SurfaceNavigation.resolve_map(data, unit, false)
	if is_equal_approx(unit, 1.0): data.contextual_steps[home] = _vector_at(OFFSET, seed_value)
	var shooter := TacticalUnit.Faction.PLAYER if seed_value % 2 != 0 else TacticalUnit.Faction.ENEMY
	var other := TacticalUnit.Faction.ENEMY if shooter == TacticalUnit.Faction.PLAYER else TacticalUnit.Faction.PLAYER
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ENEMY, TacticalUnit.Faction.ALLY]:
		data.zones.erase(StringName("deployment_%d" % faction))
	data.add_spawn_cell(shooter, home)
	data.add_spawn_cell(other, _cell_at(TARGET, seed_value))
	return data

static func present(data: MapData, parent: Node3D) -> void:
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = WALL_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.59, 0.47, 0.30)
	box.material = material
	wall.mesh = box
	parent.add_child(wall)
	var home := data.get_cell(_cell_at(REST, data.generation_seed)).world_position
	wall.position = home + _vector_at(WALL_OFFSET, data.generation_seed)
	var label := Label3D.new()
	label.text = "SIDE STEP FIRING BAY"
	label.font_size = 38
	label.pixel_size = 0.005
	label.rotation.x = -PI * 0.5
	parent.add_child(label)
	label.position = home + _vector_at(Vector3(0, 0.015, -0.6), data.generation_seed)
