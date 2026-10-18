class_name ModularEnvironmentPresenter
extends RefCounted

const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
const AssetCatalog = preload("res://tools/asset_lab/asset_catalog.gd")

static func build(data: MapData, parent: Node3D, cell_size: float) -> void:
	var catalog := IndustrialModuleCatalog.create()
	var root := Node3D.new()
	root.name = "ModularEnvironment"
	parent.add_child(root)
	for placement_index in data.environment_modules.size():
		var placement: EnvironmentModulePlacement = data.environment_modules[placement_index]
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null:
			continue
		var module_root := Node3D.new()
		module_root.name = "%s_%d_%d" % [placement.component_id, placement.origin.x, placement.origin.y]
		module_root.set_meta("component_id", placement.component_id)
		module_root.set_meta("placement_index", placement_index)
		module_root.set_meta("origin", placement.origin)
		module_root.set_meta("rotation", placement.rotation)
		module_root.set_meta("variation", placement.variation)
		module_root.set_meta("elevation", placement.elevation)
		module_root.set_meta("tactical_role", EnvironmentModuleDefinition.TacticalRole.keys()[definition.tactical_role].to_lower())
		module_root.set_meta("module_type", EnvironmentModuleDefinition.ModuleType.keys()[definition.module_type].to_lower())
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
		_add_continuous_road_surface(data, module_root, definition, placement, cell_size)
		_add_elevated_surface_markers(data, module_root, definition, placement, cell_size)
		for visual in definition.visuals:
			_add_visual(data, module_root, definition, placement, visual, cell_size)

static func _add_visual(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, visual: Dictionary, cell_size: float) -> void:
	var paths: Array = visual.get("asset_variants", [])
	var asset_path: String = visual.get("asset_path", "")
	var factor := float(visual.get("scale", 1.0))
	var anchor := int(visual.get("anchor", 0))
	var saved_yaw := 0.0
	var saved_offset := Vector3.ZERO
	var asset_ids: Array = visual.get("asset_ids", [])
	if not asset_ids.is_empty():
		var asset_id: String = asset_ids[placement.variation % asset_ids.size()]
		var profile := AssetCatalog.profile(asset_id)
		asset_path = AssetCatalog.path_for(asset_id)
		factor = float(profile.scale)
		anchor = int(profile.anchor)
		saved_yaw = deg_to_rad(float(profile.yaw_degrees))
		var saved: Array = profile.anchor_position
		saved_offset = Vector3(float(saved[0]), float(saved[1]), float(saved[2]))
	if not paths.is_empty():
		asset_path = paths[placement.variation % paths.size()]
	if asset_path.is_empty():
		return
	var local: Vector2 = visual.local_cell
	var rotated := _rotate_point(local, definition.size, placement.rotation)
	var at := _world(data, placement.origin, rotated, cell_size)
	at += Vector3.UP * float(placement.elevation) * cell_size
	var local_offset: Vector3 = visual.get("offset", Vector3.ZERO)
	at += (local_offset + saved_offset).rotated(Vector3.UP, float(placement.rotation) * PI * 0.5)
	var yaw := float(posmod(placement.rotation + int(visual.get("yaw_quarters", 0)), 4)) * PI * 0.5 + saved_yaw
	var node := AssetPlacement.instantiate_calibrated(parent, asset_path, at, factor, yaw, anchor)
	if node == null:
		return
	node.set_meta("component_id", placement.component_id)
	node.set_meta("asset_path", asset_path)

static func _add_continuous_road_surface(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, cell_size: float) -> void:
	if definition.module_type not in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
		return
	var dimensions := definition.rotated_size(placement.rotation)
	var mesh := MeshInstance3D.new()
	mesh.name = "ContinuousRoadSurface"
	var box := BoxMesh.new()
	box.size = Vector3(dimensions.x * cell_size, 0.035, dimensions.y * cell_size)
	mesh.mesh = box
	mesh.position = _world(data, placement.origin, Vector2(dimensions - Vector2i.ONE) * 0.5, cell_size) + Vector3.UP * 0.0175
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("30363b")
	material.roughness = 0.96
	mesh.material_override = material
	parent.add_child(mesh)

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
	if not definition.visuals.is_empty() or definition.placement_layer != EnvironmentModuleDefinition.PlacementLayer.GROUND:
		return
	var dimensions := definition.rotated_size(placement.rotation)
	var mesh := MeshInstance3D.new()
	mesh.name = "InteriorFloor"
	var box := BoxMesh.new()
	box.size = Vector3(dimensions.x * cell_size, 0.025, dimensions.y * cell_size)
	mesh.mesh = box
	mesh.position = _world(data, placement.origin, Vector2(dimensions - Vector2i.ONE) * 0.5, cell_size) + Vector3.UP * 0.0125
	var material := StandardMaterial3D.new()
	material.albedo_color = _ground_color(definition.module_type)
	material.roughness = 0.95
	mesh.material_override = material
	parent.add_child(mesh)

static func _ground_color(type: EnvironmentModuleDefinition.ModuleType) -> Color:
	match type:
		EnvironmentModuleDefinition.ModuleType.ALLEY: return Color("515c62")
		EnvironmentModuleDefinition.ModuleType.LOADING_DOCK: return Color("77736a")
		EnvironmentModuleDefinition.ModuleType.COURTYARD: return Color("7a807d")
		_: return Color("697471")

static func _add_elevated_surface_markers(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, cell_size: float) -> void:
	if definition.elevated_surfaces.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("56636b")
	material.roughness = 0.9
	for local_cell in definition.elevated_surfaces:
		var rotated := definition.rotate_cell(local_cell, placement.rotation)
		var surface: Dictionary = definition.elevated_surfaces[local_cell]
		var elevation := placement.elevation + int(surface.elevation)
		var cell := data.get_cell(Vector3i(placement.origin.x + rotated.x, elevation, placement.origin.y + rotated.y))
		if cell == null:
			continue
		var mesh := MeshInstance3D.new()
		mesh.name = "ElevatedSurface_%d_%d" % [rotated.x, rotated.y]
		var box := BoxMesh.new()
		box.size = Vector3(cell_size, 0.08, cell_size)
		mesh.mesh = box
		mesh.position = cell.world_position - Vector3.UP * 0.04
		mesh.material_override = material
		parent.add_child(mesh)
