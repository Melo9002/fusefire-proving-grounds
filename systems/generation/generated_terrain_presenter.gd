class_name GeneratedTerrainPresenter
extends RefCounted

const HILL_SKIRT_CLEARANCE := 0.015

static func build(map_data: MapData, parent: Node3D, cell_size: float) -> void:
	if map_data.source_kind == "generated_refinery":
		preload("res://systems/generation/refinery_presenter.gd").build(map_data, parent, cell_size)
	var container_cells: Dictionary = {}
	var building_cells: Dictionary = {}
	for hill in map_data.hills:
		_build_hill(map_data, parent, hill)
	for platform in map_data.platforms:
		_build_platform(map_data, parent, cell_size, platform)
	for traversal in map_data.generated_traversals:
		_build_generated_traversal(map_data, parent, cell_size, traversal)
	for building in map_data.buildings:
		_build_building(map_data, parent, cell_size, building)
		for stair in building.stair_cells:
			building_cells[Vector3i(stair.x, 0, stair.z)] = true
		for x in range(building.footprint.position.x, building.footprint.end.x):
			for z in range(building.footprint.position.y, building.footprint.end.y):
				building_cells[Vector3i(x, 0, z)] = true
	for footprint in map_data.containers:
		_build_container(map_data, parent, cell_size, footprint)
		for x in range(footprint.position.x, footprint.end.x):
			for z in range(footprint.position.y, footprint.end.y):
				container_cells[Vector3i(x, 0, z)] = true
	for cell: MapCellData in map_data.cells.values():
		if container_cells.has(cell.grid_position) or building_cells.has(cell.grid_position):
			continue
		if cell.grid_position.y > 0:
			continue
		if cell.cover_type == MapCellData.CoverType.NONE:
			continue
		var block := MeshInstance3D.new()
		block.name = "Cover_%d_%d_%d" % [cell.grid_position.x, cell.grid_position.y, cell.grid_position.z]
		var box := BoxMesh.new()
		box.size = Vector3(cell_size * 0.9, cell.cover_height, cell_size * 0.9)
		block.mesh = box
		block.position = cell.world_position + Vector3.UP * cell.cover_height * 0.5
		block.material_override = _material_for(cell.cover_type)
		block.set_meta("grid_position", cell.grid_position)
		block.set_meta("cover_type", cell.cover_type)
		parent.add_child(block)
	if map_data.source_kind == "generated_industrial_warehouse":
		preload("res://systems/generation/industrial_warehouse_presenter.gd").build(map_data, parent, cell_size)
	elif map_data.source_kind == ModularIndustrialLayoutBuilder.SOURCE_KIND:
		ModularEnvironmentPresenter.build(map_data, parent, cell_size)

static func _build_platform(map_data: MapData, parent: Node3D, cell_size: float, platform: GeneratedPlatformData) -> void:
	var first := map_data.get_cell(platform.cells[0])
	var deck := Node3D.new()
	deck.name = "Platform_%d_%d_%d" % [platform.footprint.position.x, platform.elevation_level, platform.footprint.position.y]
	parent.add_child(deck)
	var dimensions := Vector3(platform.footprint.size.x * cell_size, 0.22, platform.footprint.size.y * cell_size)
	var center := first.world_position + Vector3(
		(platform.footprint.size.x - 1) * cell_size * 0.5,
		-dimensions.y * 0.5,
		(platform.footprint.size.y - 1) * cell_size * 0.5
	)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.29, 0.34)
	material.metallic = 0.35
	material.roughness = 0.7
	_add_box(deck, dimensions, center, material)
	_add_roof_collider(deck, dimensions, center)
	_build_platform_rails(map_data, deck, cell_size, platform)
	var ground := map_data.get_cell(Vector3i(platform.cells[0].x, 0, platform.cells[0].z))
	var deck_bottom := first.world_position.y - dimensions.y
	var support_height := deck_bottom - ground.world_position.y
	var corners := [
		Vector2(0, 0),
		Vector2(platform.footprint.size.x - 1, 0),
		Vector2(0, platform.footprint.size.y - 1),
		Vector2(platform.footprint.size.x - 1, platform.footprint.size.y - 1),
	]
	for corner in corners:
		var support_center := Vector3(
			first.world_position.x + corner.x * cell_size,
			ground.world_position.y + support_height * 0.5,
			first.world_position.z + corner.y * cell_size
		)
		_add_box(deck, Vector3(0.16, support_height, 0.16), support_center, material)

static func _build_platform_rails(data: MapData, parent: Node3D, cell_size: float, platform: GeneratedPlatformData) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.63, 0.16)
	var rails := Node3D.new()
	rails.name = "PlatformRails"
	parent.add_child(rails)
	for position in platform.cells:
		# Leave a full cell opening at access landings.
		var landing := false
		for traversal in data.generated_traversals:
			if traversal.from_cell == position or traversal.to_cell == position:
				landing = true
				break
		if landing:
			continue
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var neighbor := data.get_cell(position + direction)
			if neighbor and neighbor.walkable:
				continue
			var outward := Vector3(direction)
			var along := Vector3(-outward.z, 0, outward.x)
			var center := data.get_cell(position).world_position + outward * cell_size * 0.47
			var start := center - along * cell_size * 0.5
			var finish := center + along * cell_size * 0.5
			for height in [0.5, 0.95]:
				var offset := Vector3.UP * float(height) * cell_size
				_add_stair_beam(rails, start + offset, finish + offset, cell_size * 0.045, material)
			_add_stair_beam(rails, center, center + Vector3.UP * cell_size * 0.95, cell_size * 0.045, material)

static func _build_hill(map_data: MapData, parent: Node3D, hill: GeneratedHillData) -> void:
	var terrain := Node3D.new()
	terrain.name = "Hill_%d_%d" % [hill.footprint.position.x, hill.footprint.position.y]
	parent.add_child(terrain)
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.29, 0.24, 0.16)
	earth.roughness = 1.0
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Dictionary = {}
	for position in hill.surface_cells:
		heights[Vector2i(position.x, position.z)] = map_data.get_cell(position).world_position
	var bounds := hill.footprint.grow(1)
	for x in range(bounds.position.x, bounds.end.x - 1):
		for z in range(bounds.position.y, bounds.end.y - 1):
			var points: Array[Vector3] = []
			for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]:
				var key: Vector2i = Vector2i(x, z) + offset
				if heights.has(key):
					points.append(heights[key])
				else:
					# The sloped skirt shares its outer boundary with the map floor.
					# A small clearance prevents coplanar triangles from z-fighting.
					var ground := map_data.get_cell(Vector3i(key.x, 0, key.y))
					points.append(ground.world_position + Vector3.UP * HILL_SKIRT_CLEARANCE)
			for index in [0, 1, 2, 0, 2, 3]:
				surface.add_vertex(points[index])
	surface.generate_normals()
	var mesh := surface.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = earth
	terrain.add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	body.add_child(collider)
	terrain.add_child(body)

static func _build_generated_traversal(map_data: MapData, parent: Node3D, cell_size: float, traversal: GeneratedTraversalData) -> void:
	var structure := Node3D.new()
	structure.name = "Traversal_%d_%s" % [traversal.kind, traversal.to_cell]
	parent.add_child(structure)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.58, 0.12) if traversal.kind == GeneratedTraversalData.Kind.LADDER else Color(0.38, 0.43, 0.46)
	material.metallic = 0.45
	material.roughness = 0.62
	if traversal.kind == GeneratedTraversalData.Kind.LADDER:
		_build_ladder_between(map_data, structure, cell_size, traversal.from_cell, traversal.to_cell)
		return
	if traversal.kind == GeneratedTraversalData.Kind.BRIDGE:
		for position in traversal.path_cells.slice(1, traversal.path_cells.size() - 1):
			var cell := map_data.get_cell(position)
			var dimensions := Vector3(cell_size, 0.18, cell_size)
			var center := cell.world_position - Vector3.UP * dimensions.y * 0.5
			_add_box(structure, dimensions, center, material)
			_add_roof_collider(structure, dimensions, center)
		return
	if traversal.kind == GeneratedTraversalData.Kind.STAIRS:
		_build_open_stairs(map_data, structure, cell_size, traversal, material)
		return
	for position in traversal.path_cells:
		if position.y == 0 or position == traversal.to_cell:
			continue
		var cell := map_data.get_cell(position)
		var dimensions := Vector3(cell_size * 0.9, cell.world_position.y, cell_size * 0.9)
		var center := cell.world_position - Vector3.UP * dimensions.y * 0.5
		_add_box(structure, dimensions, center, material)
		_add_roof_collider(structure, dimensions, center)

static func _build_open_stairs(map_data: MapData, parent: Node3D, cell_size: float, traversal: GeneratedTraversalData, material: Material) -> void:
	var bottom := map_data.get_cell(traversal.from_cell).world_position
	var top := map_data.get_cell(traversal.to_cell).world_position
	var direction := Vector3(top.x - bottom.x, 0, top.z - bottom.z).normalized()
	var across := Vector3(-direction.z, 0.0, direction.x)
	var rail_material := StandardMaterial3D.new()
	rail_material.albedo_color = Color(0.85, 0.63, 0.16)
	# Five visual treads per graph edge. Movement keeps the existing ramp-like
	# interpolation between cells; the decoration adds no movement obstacles.
	for index in range(traversal.path_cells.size() - 1):
		var start := map_data.get_cell(traversal.path_cells[index]).world_position
		var finish := map_data.get_cell(traversal.path_cells[index + 1]).world_position
		var run := Vector2(finish.x - start.x, finish.z - start.z).length()
		for step in range(5):
			var point := start.lerp(finish, float(step) / 5.0)
			var size := Vector3(cell_size * 0.88, cell_size * 0.06, run / 5.0)
			if absf(direction.x) > 0.5:
				size = Vector3(run / 5.0, cell_size * 0.06, cell_size * 0.88)
			_add_box(parent, size, point - Vector3.UP * size.y * 0.5, material)
		# Invisible sloping input surface follows the same world-space route.
		var surface := Node3D.new()
		parent.add_child(surface)
		surface.position = (start + finish) * 0.5
		surface.basis = Basis(-across, (finish - start).normalized().cross(-across), (finish - start).normalized())
		_add_roof_collider(surface, Vector3(cell_size * 0.88, 0.04 * cell_size, start.distance_to(finish)), Vector3.DOWN * 0.02 * cell_size)
	for side in [-1.0, 1.0]:
		var offset: Vector3 = across * float(side) * cell_size * 0.46
		_add_stair_beam(parent, bottom + offset - Vector3.UP * cell_size * 0.12, top + offset - Vector3.UP * cell_size * 0.12, cell_size * 0.12, material)
		for height in [0.5, 0.95]:
			_add_stair_beam(parent, bottom + offset + Vector3.UP * float(height) * cell_size, top + offset + Vector3.UP * float(height) * cell_size, cell_size * 0.045, rail_material)
		for position in traversal.path_cells:
			var point := map_data.get_cell(position).world_position + offset
			_add_stair_beam(parent, point, point + Vector3.UP * cell_size * 0.95, cell_size * 0.045, rail_material)

static func _add_stair_beam(parent: Node3D, start: Vector3, finish: Vector3, width: float, material: Material) -> void:
	var beam := Node3D.new()
	parent.add_child(beam)
	beam.position = (start + finish) * 0.5
	var axis := (finish - start).normalized()
	var reference_axis := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var across := reference_axis.cross(axis).normalized()
	beam.basis = Basis(across, axis.cross(across), axis)
	_add_box(beam, Vector3(width, width, start.distance_to(finish)), Vector3.ZERO, material)

static func _material_for(cover_type: MapCellData.CoverType) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.08, 0.08) if cover_type == MapCellData.CoverType.LOW else Color(0.32, 0.015, 0.015)
	material.roughness = 0.82
	return material

static func _build_container(map_data: MapData, parent: Node3D, cell_size: float, footprint: Rect2i) -> void:
	var first := map_data.get_cell(Vector3i(footprint.position.x, 0, footprint.position.y))
	var container := Node3D.new()
	container.name = "Container_%d_%d" % [footprint.position.x, footprint.position.y]
	container.position = first.world_position + Vector3((footprint.size.x - 1) * cell_size * 0.5, 0, (footprint.size.y - 1) * cell_size * 0.5)
	parent.add_child(container)
	var dimensions := Vector3(footprint.size.x * cell_size, first.cover_height, footprint.size.y * cell_size)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.16, 0.35, 0.42)
	steel.roughness = 0.7
	_add_box(container, dimensions, Vector3.UP * dimensions.y * 0.5, steel)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.32, 0.48, 0.5)
	# Thin ribs stay inside the declared footprint.
	for side in [-1.0, 1.0]:
		for index in range(1, footprint.size.x * 4):
			var x := -dimensions.x * 0.5 + index * cell_size * 0.25
			_add_box(container, Vector3(0.045, dimensions.y - 0.12, 0.025), Vector3(x, dimensions.y * 0.5, side * (dimensions.z * 0.5 - 0.01)), trim)
		for index in range(1, footprint.size.y * 4):
			var z := -dimensions.z * 0.5 + index * cell_size * 0.25
			_add_box(container, Vector3(0.025, dimensions.y - 0.12, 0.045), Vector3(side * (dimensions.x * 0.5 - 0.01), dimensions.y * 0.5, z), trim)

static func _add_box(parent: Node3D, dimensions: Vector3, center: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	instance.mesh = box
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)

static func _build_building(map_data: MapData, parent: Node3D, cell_size: float, building: GeneratedBuildingData) -> void:
	var first := map_data.get_cell(Vector3i(building.footprint.position.x, 0, building.footprint.position.y))
	var structure := Node3D.new()
	structure.name = "Building_%d_%d" % [building.footprint.position.x, building.footprint.position.y]
	parent.add_child(structure)
	var dimensions := Vector3(
		building.footprint.size.x * cell_size,
		float(building.roof_level) * cell_size,
		building.footprint.size.y * cell_size
	)
	var center := first.world_position + Vector3(
		(building.footprint.size.x - 1) * cell_size * 0.5,
		dimensions.y * 0.5,
		(building.footprint.size.y - 1) * cell_size * 0.5
	)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.34, 0.38, 0.43)
	wall_material.roughness = 0.95
	var wall_dimensions := dimensions - Vector3(0, 0.12, 0)
	_add_box(structure, wall_dimensions, center - Vector3.UP * 0.06, wall_material)
	_add_building_details(structure, dimensions, center, cell_size)
	_add_roof_collider(structure, dimensions, center)
	_build_ladder(map_data, structure, cell_size, building)
	for stair in building.stair_cells:
		var cell := map_data.get_cell(stair)
		var size := Vector3(cell_size, cell.world_position.y, cell_size)
		var stair_center := cell.world_position - Vector3.UP * size.y * 0.5
		_add_box(structure, size, stair_center, wall_material)
		_add_roof_collider(structure, size, stair_center)
	if not building.upper_cells.is_empty():
		var first_upper := map_data.get_cell(Vector3i(building.upper_footprint.position.x, building.roof_level + 3, building.upper_footprint.position.y))
		var size := Vector3(building.upper_footprint.size.x * cell_size, 3.0, building.upper_footprint.size.y * cell_size)
		var upper_center := first_upper.world_position + Vector3((building.upper_footprint.size.x - 1) * cell_size * 0.5, -1.5, (building.upper_footprint.size.y - 1) * cell_size * 0.5)
		_add_box(structure, size - Vector3(0, 0.12, 0), upper_center - Vector3.UP * 0.06, wall_material)
		_add_utility_room_details(structure, size, upper_center)
		_add_roof_collider(structure, size, upper_center)
		var upper_ladder := GeneratedBuildingData.new(building.footprint, 3, building.upper_ladder_ground_cell, building.upper_ladder_roof_cell)
		_build_ladder(map_data, structure, cell_size, upper_ladder)

static func _add_building_details(parent: Node3D, dimensions: Vector3, center: Vector3, cell_size: float) -> void:
	var roof_material := StandardMaterial3D.new()
	roof_material.albedo_color = Color(0.18, 0.21, 0.25)
	roof_material.roughness = 0.88
	_add_box(parent, Vector3(dimensions.x + 0.08, 0.12, dimensions.z + 0.08), center + Vector3.UP * (dimensions.y * 0.5 - 0.06), roof_material)

	var window_material := StandardMaterial3D.new()
	window_material.albedo_color = Color(0.12, 0.28, 0.36)
	window_material.metallic = 0.25
	window_material.roughness = 0.32
	window_material.emission_enabled = true
	window_material.emission = Color(0.025, 0.07, 0.09)
	var door_material := StandardMaterial3D.new()
	door_material.albedo_color = Color(0.12, 0.14, 0.16)
	door_material.roughness = 0.72

	# Flat facade panels add readable urban scale without changing collision.
	var facade_y := center.y - dimensions.y * 0.12
	_add_box(parent, Vector3(cell_size * 0.62, 1.65, 0.035), Vector3(center.x, 0.825, center.z + dimensions.z * 0.5 + 0.018), door_material)
	for x_offset in [-dimensions.x * 0.27, dimensions.x * 0.27]:
		_add_box(parent, Vector3(cell_size * 0.55, 0.62, 0.03), Vector3(center.x + x_offset, facade_y, center.z + dimensions.z * 0.5 + 0.02), window_material)
		_add_box(parent, Vector3(cell_size * 0.55, 0.62, 0.03), Vector3(center.x + x_offset, facade_y, center.z - dimensions.z * 0.5 - 0.02), window_material)
	for z_offset in [-dimensions.z * 0.27, dimensions.z * 0.27]:
		_add_box(parent, Vector3(0.03, 0.62, cell_size * 0.55), Vector3(center.x + dimensions.x * 0.5 + 0.02, facade_y, center.z + z_offset), window_material)
		_add_box(parent, Vector3(0.03, 0.62, cell_size * 0.55), Vector3(center.x - dimensions.x * 0.5 - 0.02, facade_y, center.z + z_offset), window_material)

static func _add_utility_room_details(parent: Node3D, dimensions: Vector3, center: Vector3) -> void:
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color(0.16, 0.19, 0.22)
	cap_material.roughness = 0.9
	_add_box(parent, Vector3(dimensions.x + 0.06, 0.1, dimensions.z + 0.06), center + Vector3.UP * (dimensions.y * 0.5 - 0.05), cap_material)
	var vent_material := StandardMaterial3D.new()
	vent_material.albedo_color = Color(0.08, 0.11, 0.13)
	vent_material.metallic = 0.4
	_add_box(parent, Vector3(0.44, 0.55, 0.025), Vector3(center.x, center.y, center.z + dimensions.z * 0.5 + 0.015), vent_material)

static func _add_roof_collider(parent: Node3D, dimensions: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "RoofInputSurface"
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	parent.add_child(body)

static func _build_ladder(map_data: MapData, parent: Node3D, cell_size: float, building: GeneratedBuildingData) -> void:
	_build_ladder_between(map_data, parent, cell_size, building.ladder_ground_cell, building.ladder_roof_cell)

static func _build_ladder_between(map_data: MapData, parent: Node3D, cell_size: float, bottom_cell: Vector3i, top_cell: Vector3i) -> void:
	var bottom := map_data.get_cell(bottom_cell).world_position
	var top := map_data.get_cell(top_cell).world_position
	var horizontal := Vector3(top.x - bottom.x, 0, top.z - bottom.z).normalized()
	var across := Vector3(-horizontal.z, 0, horizontal.x)
	var facade_center := (bottom + top) * 0.5
	var ladder_material := StandardMaterial3D.new()
	ladder_material.albedo_color = Color(0.75, 0.62, 0.18)
	ladder_material.metallic = 0.65
	ladder_material.roughness = 0.45
	var height := top.y - bottom.y
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.07, height, 0.07), facade_center + across * side * cell_size * 0.28, ladder_material)
	var rung_sections := maxi(2, top_cell.y - bottom_cell.y) * 3
	for rung_index in range(1, rung_sections):
		var rung_center := Vector3(facade_center.x, bottom.y + float(rung_index) * height / float(rung_sections), facade_center.z)
		var rung_dimensions := Vector3(cell_size * 0.62, 0.055, 0.055) if absf(across.x) > 0.5 else Vector3(0.055, 0.055, cell_size * 0.62)
		_add_box(parent, rung_dimensions, rung_center, ladder_material)
