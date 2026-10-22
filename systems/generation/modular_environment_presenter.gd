class_name ModularEnvironmentPresenter
extends RefCounted

const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
const AssetCatalog = preload("res://tools/asset_lab/asset_catalog.gd")
const SemanticCatalog = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const Streetscape = preload("res://systems/generation/road_streetscape_profile.gd")

enum RoadPresentationMode {
	ASSET_FIRST,
	DERIVED_DIAGNOSTIC,
}

static func build(data: MapData, parent: Node3D, cell_size: float, road_presentation_mode := RoadPresentationMode.ASSET_FIRST) -> void:
	var catalog := IndustrialModuleCatalog.create()
	var root := Node3D.new()
	root.name = "ModularEnvironment"
	root.set_meta("road_presentation_mode", RoadPresentationMode.keys()[road_presentation_mode].to_lower())
	var identity := resolve_environment_identity(data)
	root.set_meta("environment_identity", identity.environment_id)
	root.set_meta("environment_identity_source", identity.source)
	parent.add_child(root)
	if not identity.ok:
		push_error("Modular environment presentation rejected: %s" % identity.error)
		return
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
		module_root.set_meta("structural_assembly_id", definition.structural_assembly_id)
		module_root.set_meta("architectural_purpose", definition.architectural_purpose)
		module_root.set_meta("assembly_enclosure", definition.assembly_enclosure)
		module_root.set_meta("assembly_complete", definition.assembly_complete)
		root.add_child(module_root)
		for local_cell in definition.cell_effects:
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			var position := placement.origin + rotated
			var block := parent.get_node_or_null("Cover_%d_0_%d" % [position.x, position.y]) as Node3D
			if block:
				block.visible = false
		_add_ground_marker(data, module_root, definition, placement, cell_size)
		if road_presentation_mode == RoadPresentationMode.DERIVED_DIAGNOSTIC:
			_add_road_streetscape(data, module_root, definition, placement, cell_size)
		_add_elevated_surface_markers(data, module_root, definition, placement, cell_size)
		for visual in definition.visuals:
			_add_visual(data, module_root, definition, placement, visual, cell_size)

static func _add_visual(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, visual: Dictionary, cell_size: float) -> void:
	if visual.get("kind", "asset") == "socket_assembly":
		_add_socket_assembly_visual(data, parent, definition, placement, visual, cell_size)
		return
	if visual.get("kind", "asset") == "box":
		_add_box_visual(data, parent, definition, placement, visual, cell_size)
		return
	var paths: Array = visual.get("asset_variants", [])
	var asset_path: String = visual.get("asset_path", "")
	var factor := float(visual.get("scale", 1.0))
	var anchor := int(visual.get("anchor", 0))
	var saved_yaw := 0.0
	var saved_offset := Vector3.ZERO
	var asset_ids: Array = visual.get("asset_ids", [])
	if not asset_ids.is_empty():
		var approved := SemanticCatalog.generation_candidates(asset_ids)
		if approved.is_empty():
			push_warning("No semantically approved visual candidates for %s" % definition.component_id)
			return
		var asset_id: String = approved[placement.variation % approved.size()]
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
	var rotated := definition.rotate_point(local, placement.rotation)
	var at := _world(data, placement.origin, rotated, cell_size)
	at += Vector3.UP * float(placement.elevation) * cell_size
	var local_offset: Vector3 = visual.get("offset", Vector3.ZERO)
	at += (local_offset + saved_offset).rotated(Vector3.UP, definition.placement_yaw_radians(placement.rotation))
	var yaw := definition.placement_yaw_radians(placement.rotation + int(visual.get("yaw_quarters", 0))) + saved_yaw
	var node := AssetPlacement.instantiate_calibrated(parent, asset_path, at, factor, yaw, anchor)
	if node == null:
		return
	var scale_multiplier: Vector3 = visual.get("scale_multiplier", Vector3.ONE)
	if not scale_multiplier.is_equal_approx(Vector3.ONE):
		node.scale *= scale_multiplier
	node.set_meta("component_id", placement.component_id)
	node.set_meta("asset_path", asset_path)
	node.set_meta("scale_multiplier", scale_multiplier)
	node.set_meta("assembly_visual_role", visual.get("visual_role", &"component"))

static func _add_socket_assembly_visual(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, visual: Dictionary, cell_size: float) -> void:
	var local: Vector2 = visual.local_cell
	var rotated := definition.rotate_point(local, placement.rotation)
	var anchor := _world(data, placement.origin, rotated, cell_size) + Vector3.UP * float(placement.elevation) * cell_size
	anchor += visual.get("offset", Vector3.ZERO).rotated(Vector3.UP, definition.placement_yaw_radians(placement.rotation))
	var module_basis := Basis(Vector3.UP, definition.placement_yaw_radians(placement.rotation))
	for component: Dictionary in visual.components:
		var asset_id: String = component.asset_id
		var scene := load(AssetCatalog.path_for(asset_id)) as PackedScene
		if scene == null: continue
		var source := scene.instantiate() as Node3D
		var transform: Transform3D = component.transform
		var factor := float(component.scale)
		var wrapper := TacticalVisualOccluder.new()
		wrapper.name = String(component.component_id)
		wrapper.position = anchor + module_basis * (transform.origin * factor)
		wrapper.basis = module_basis * transform.basis.scaled(Vector3.ONE * factor)
		wrapper.occlusion_bounds = AssetPlacement.mesh_bounds(source)
		wrapper.set_meta("asset_id", asset_id)
		wrapper.set_meta("asset_path", AssetCatalog.path_for(asset_id))
		wrapper.set_meta("socket_assembly_id", definition.structural_assembly_id)
		wrapper.set_meta("assembly_visual_role", visual.get("visual_role", &"equipment_assembly"))
		wrapper.add_child(source)
		parent.add_child(wrapper)

static func _add_box_visual(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, visual: Dictionary, cell_size: float) -> void:
	var authored_center: Vector3 = visual.get("local_center", Vector3.ZERO)
	var rotated := definition.rotate_point(Vector2(authored_center.x, authored_center.z), placement.rotation)
	var mesh := MeshInstance3D.new()
	mesh.name = str(visual.get("label", "DerivedStructure"))
	var box := BoxMesh.new()
	var dimensions: Vector3 = visual.get("dimensions", Vector3.ONE)
	box.size = dimensions * cell_size
	mesh.mesh = box
	mesh.position = _world(data, placement.origin, rotated, cell_size)
	mesh.position.y += (authored_center.y + float(placement.elevation)) * cell_size
	mesh.rotation.y = definition.placement_yaw_radians(placement.rotation)
	var material := StandardMaterial3D.new()
	material.albedo_color = visual.get("color", Color("596579"))
	material.roughness = 0.88
	mesh.material_override = material
	mesh.set_meta("derived_structural_visual", true)
	mesh.set_meta("assembly_visual_role", visual.get("visual_role", &"structural"))
	parent.add_child(mesh)

static func _add_road_streetscape(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, cell_size: float) -> void:
	if definition.module_type not in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
		return
	var sections := Streetscape.surface_sections(definition.component_id)
	if sections.is_empty():
		return
	var streetscape := Node3D.new()
	streetscape.name = "RoadStreetscape"
	streetscape.set_meta("carriageway_width", Streetscape.CARRIAGEWAY_WIDTH)
	streetscape.set_meta("sidewalk_width", Streetscape.SIDEWALK_WIDTH)
	parent.add_child(streetscape)
	var environment_id: StringName = resolve_environment_identity(data).environment_id
	var counts := {}
	for section in sections:
		var kind: StringName = section.kind
		var count := int(counts.get(kind, 0))
		counts[kind] = count + 1
		_add_street_section(data, streetscape, definition, placement, section, environment_id, cell_size, count)

static func resolve_environment_identity(data: MapData) -> Dictionary:
	if data.battlefield_layout_document != null:
		var document_id := StringName(data.battlefield_layout_document.environment_id)
		if String(document_id) in BattlefieldLayoutDocument.ENVIRONMENTS: return {"ok": true, "environment_id": document_id, "source": "layout_document"}
		return {"ok": false, "environment_id": &"", "source": "invalid_layout_document", "error": "unsupported document environment identity '%s'" % document_id}
	if data.environment_layout_plan != null:
		if String(data.environment_layout_plan.environment_id) in BattlefieldLayoutDocument.ENVIRONMENTS: return {"ok": true, "environment_id": data.environment_layout_plan.environment_id, "source": "layout_plan"}
		return {"ok": false, "environment_id": &"", "source": "invalid_layout_plan", "error": "unsupported plan environment identity '%s'" % data.environment_layout_plan.environment_id}
	# Legacy modular fixtures predate the document and remain supported until
	# their persistence migration. The metadata makes this fallback observable.
	return {"ok": true, "environment_id": &"mixed_service", "source": "documented_legacy_fallback"}

static func _add_street_section(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, section: Dictionary, environment_id: StringName, cell_size: float, index: int) -> void:
	var kind: StringName = section.kind
	var authored_center: Vector2 = section.center
	var center := definition.rotate_point(authored_center, placement.rotation)
	var authored_size: Vector2 = section.size
	var rotated_size := authored_size if posmod(placement.rotation, 2) == 0 else Vector2(authored_size.y, authored_size.x)
	var height := Streetscape.ROAD_HEIGHT
	if kind == Streetscape.SIDEWALK:
		height = Streetscape.SIDEWALK_HEIGHT
	elif kind == Streetscape.CURB:
		height = Streetscape.CURB_HEIGHT
	elif kind == Streetscape.MARKING:
		height = Streetscape.MARKING_HEIGHT
	var mesh := MeshInstance3D.new()
	mesh.name = "%s_%02d" % [String(kind).to_pascal_case(), index]
	var box := BoxMesh.new()
	box.size = Vector3(rotated_size.x * cell_size, height * cell_size, rotated_size.y * cell_size)
	mesh.mesh = box
	mesh.position = _world(data, placement.origin, center, cell_size) + Vector3.UP * _street_section_center_y(kind, cell_size)
	var material := StandardMaterial3D.new()
	material.albedo_color = _street_section_color(kind, environment_id)
	material.roughness = 0.94
	mesh.material_override = material
	parent.add_child(mesh)

static func _street_section_center_y(kind: StringName, cell_size: float) -> float:
	if kind == Streetscape.SIDEWALK:
		return Streetscape.SIDEWALK_HEIGHT * 0.5 * cell_size
	if kind == Streetscape.CURB:
		return Streetscape.CURB_HEIGHT * 0.5 * cell_size
	if kind == Streetscape.MARKING:
		return (Streetscape.ROAD_HEIGHT + Streetscape.MARKING_HEIGHT * 0.5) * cell_size
	return Streetscape.ROAD_HEIGHT * 0.5 * cell_size

static func _street_section_color(kind: StringName, environment_id: StringName) -> Color:
	if kind == Streetscape.ASPHALT:
		return Color("2e3438") if environment_id == &"industrial_district" else Color("353a3d")
	if kind == Streetscape.SIDEWALK:
		match environment_id:
			&"industrial_district": return Color("687176")
			&"commercial_street": return Color("92918a")
			_: return Color("777d7a")
	if kind == Streetscape.CURB:
		return Color("b8b7ad") if environment_id == &"commercial_street" else Color("8b9292")
	return Color("d4aa43")

static func _world(data: MapData, origin: Vector2i, offset: Vector2, cell_size: float) -> Vector3:
	var base := data.get_cell(Vector3i(origin.x, 0, origin.y))
	return base.world_position + Vector3(offset.x * cell_size, 0.0, offset.y * cell_size)

static func _add_ground_marker(data: MapData, parent: Node3D, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, cell_size: float) -> void:
	if definition.module_type in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
		return
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
