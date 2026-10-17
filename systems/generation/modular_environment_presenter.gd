class_name ModularEnvironmentPresenter
extends RefCounted

const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")

static func build(data: MapData, parent: Node3D, cell_size: float) -> void:
	var catalog := IndustrialModuleCatalog.create()
	var root := Node3D.new()
	root.name = "ModularEnvironment"
	parent.add_child(root)
	for placement in data.environment_modules:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null:
			continue
		var module_root := Node3D.new()
		module_root.name = "%s_%d_%d" % [placement.component_id, placement.origin.x, placement.origin.y]
		module_root.set_meta("component_id", placement.component_id)
		module_root.set_meta("rotation", placement.rotation)
		module_root.set_meta("tactical_role", EnvironmentModuleDefinition.TacticalRole.keys()[definition.tactical_role].to_lower())
		module_root.set_meta("visual_origin_snap", definition.visual_origin_snap)
		module_root.set_meta("visual_assembly_pitch", definition.visual_assembly_pitch)
		root.add_child(module_root)
		for local_cell in definition.cell_effects:
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			var position := placement.origin + rotated
			var block := parent.get_node_or_null("Cover_%d_0_%d" % [position.x, position.y]) as Node3D
			if block:
				block.visible = false
		_add_ground_marker(data, module_root, definition, placement, cell_size)
		for visual in definition.visuals:
			_add_visual(data, module_root, definition, placement, visual, cell_size)

static func _add_visual(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, visual: Dictionary, cell_size: float) -> void:
	var paths: Array = visual.get("asset_variants", [])
	var asset_path: String = visual.get("asset_path", "")
	if not paths.is_empty():
		asset_path = paths[placement.variation % paths.size()]
	if asset_path.is_empty():
		return
	var local: Vector2 = visual.local_cell
	var rotated := _rotate_point(local, definition.size, placement.rotation)
	var at := _world(data, placement.origin, rotated, cell_size)
	var yaw := float(posmod(placement.rotation + int(visual.get("yaw_quarters", 0)), 4)) * PI * 0.5
	var node := AssetPlacement.instantiate_calibrated(parent, asset_path, at, float(visual.scale), yaw, int(visual.anchor))
	node.set_meta("component_id", placement.component_id)
	node.set_meta("asset_path", asset_path)

static func _rotate_point(point: Vector2, size: Vector2i, rotation: int) -> Vector2:
	match posmod(rotation, 4):
		1: return Vector2(float(size.y - 1) - point.y, point.x)
		2: return Vector2(float(size.x - 1) - point.x, float(size.y - 1) - point.y)
		3: return Vector2(point.y, float(size.x - 1) - point.x)
		_: return point

static func _world(data: MapData, origin: Vector2i, offset: Vector2, cell_size: float) -> Vector3:
	var base := data.get_cell(Vector3i(origin.x, 0, origin.y))
	return base.world_position + Vector3(offset.x * cell_size, 0.0, offset.y * cell_size)

static func _add_ground_marker(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, cell_size: float) -> void:
	if definition.family != &"factory_structure" or placement.component_id not in [&"factory_interior_floor"]:
		return
	var dimensions := definition.rotated_size(placement.rotation)
	var mesh := MeshInstance3D.new()
	mesh.name = "InteriorFloor"
	var box := BoxMesh.new()
	box.size = Vector3(dimensions.x * cell_size, 0.025, dimensions.y * cell_size)
	mesh.mesh = box
	mesh.position = _world(data, placement.origin, Vector2(dimensions - Vector2i.ONE) * 0.5, cell_size) + Vector3.UP * 0.0125
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("697471")
	material.roughness = 0.95
	mesh.material_override = material
	parent.add_child(mesh)
