class_name ChunkPublicationCompiler
extends RefCounted
## Local publication boundary. Uses the shared tactical writer; no missions or approval.
const VERSION := "chunk-publication-1"
const PROFILES := "res://systems/generation/chunk_port_profiles.json"
const Assets = preload("res://tools/asset_lab/asset_catalog.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")

static func canonical(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)
static func source_hash(source: EnvironmentChunkSource) -> String: return canonical(source.data).sha256_text()
static func compile(source: EnvironmentChunkSource, context: EnvironmentResolutionContext = null) -> Dictionary:
	var errors := EnvironmentChunkSource.source_errors(source.data)
	var result := {"ok": false, "errors": errors, "dependencies": [], "data": null, "resolved": [], "source_hash": source_hash(source)}
	if not errors.is_empty(): return result
	if context == null: context = EnvironmentResolutionContext.new()
	context.errors.clear() # Isolate diagnostics while retaining per-operation resolution caches.
	var size := Vector2i(int(source.data.bounds[0]), int(source.data.bounds[1]))
	var height := int(source.data.height)
	if size.x * size.y > 65536 or height > 256:
		fail(errors, "PILOT_EXTENT_LIMIT", "bounds", "Publication supports at most 65,536 cells per floor and height 256")
		return result
	var layout := EnvironmentModuleLayout.new(StringName(source.data.chunk_id))
	var tactical := EnvironmentModuleLayout.new(StringName(source.data.chunk_id))
	var dependencies := {}
	var records: Array[Dictionary] = []
	var ids := {}
	var visual_only: Array = source.data.tactical.get("visual_only", [])
	if source.data.instances.is_empty(): fail(errors, "EMPTY_CHUNK", "instances", "Add content before publication")
	if source.data.rotations.is_empty(): fail(errors, "NO_ROTATIONS", "rotations", "Declare a supported orientation")
	for record in source.data.instances:
		var id := str(record.placement_id)
		ids[id] = true
		var placement := EnvironmentModulePlacement.from_record(record)
		var definition: EnvironmentModuleDefinition = context.catalog.get(placement.component_id)
		var contributes: bool = id in source.data.tactical.components
		if contributes and id in visual_only: fail(errors, "CONFLICTING_ROLE", id, "Choose component behavior or visual-only, not both")
		if definition == null:
			var asset_id := str(placement.component_id).trim_prefix("asset:")
			if not str(placement.component_id).begins_with("asset:") or asset_id not in Assets.all_ids():
				fail(errors, "UNKNOWN_COMPONENT", id, str(placement.component_id))
				continue
			if id not in visual_only or contributes:
				fail(errors, "UNDECLARED_TACTICAL_ROLE", id, "Raw assets need an explicit visual-only declaration; use a tactical component for blocking/cover")
			var meaning := Semantics.effective(asset_id, context.semantic_data)
			if meaning.completeness not in ["complete", "not_applicable"] or meaning.structural_role in ["wall", "corner", "entrance", "window", "roof", "stairs", "platform", "floor", "shell"]:
				fail(errors, "INCOMPLETE_STRUCTURE", id, "Raw structural fragments require a complete validated assembly; visual-only cannot waive this")
			pin(dependencies, context.asset_dependency(asset_id), id)
			var asset_preview_root := Node3D.new()
			Assets.place(asset_preview_root, asset_id, Vector3(placement.origin.x, placement.elevation, placement.origin.y), -float(placement.rotation) * PI * 0.5, context.calibration_data)
			var bounds := Placement.mesh_bounds(asset_preview_root)
			check_envelope(bounds, size, height, errors, id)
			asset_preview_root.free()
			records.append({"placement": placement, "definition": null, "asset_id": asset_id, "calibration": context.asset(asset_id).profile.duplicate(true), "visual_bounds": bounds})
			continue
		if not contributes and id not in visual_only: fail(errors, "UNDECLARED_TACTICAL_ROLE", id, "Declare component contribution or visual-only")
		if id in visual_only and definition.tactical_role != EnvironmentModuleDefinition.TacticalRole.VISUAL_ONLY:
			fail(errors, "TACTICAL_ROLE_WAIVER", id, "A structural or blocking component cannot be declared visual-only")
		if definition.tactical_role == EnvironmentModuleDefinition.TacticalRole.STRUCTURE and (definition.structural_assembly_id.is_empty() or not definition.assembly_complete):
			fail(errors, "INCOMPLETE_STRUCTURE", id, "Publication requires a complete structure assembly, not a loose building fragment")
		if not layout.try_add(definition, placement, size): fail(errors, "INVALID_PLACEMENT", id, layout.errors.back())
		for rotation in source.data.rotations:
			if posmod(placement.rotation + int(rotation), 4) not in definition.allowed_rotations: fail(errors, "UNSUPPORTED_ROTATION", id, "Chunk rotation is not supported by this component")
		if contributes: tactical.placements.append(placement)
		pin(dependencies, context.module_dependency(placement.component_id), id)
		for asset_id in context.resolved_assets(definition, placement.variation): pin(dependencies, context.asset_dependency(asset_id), id)
		if not definition.structural_assembly_id.is_empty(): pin(dependencies, context.assembly_dependency(str(definition.structural_assembly_id)), id)
		var single := EnvironmentModuleLayout.new()
		single.placements.append(placement)
		var resolved := context.resolve_layout(single)
		if resolved.is_empty(): continue
		records.append(resolved[0])
		var view_data := MapData.new()
		view_data.add_cell(MapCellData.new(Vector3i(placement.origin.x, 0, placement.origin.y), Vector3(placement.origin.x, 0, placement.origin.y)))
		var root := Node3D.new()
		for visual in resolved[0].visuals:
			if visual.get("kind", "asset") == "box": fail(errors, "DERIVED_STRUCTURE_NOT_IN_PILOT", id, "Pilot structures must use downloaded geometry")
			ModularEnvironmentPresenter._add_visual(view_data, root, definition, placement, visual, 1.0)
		if root.get_child_count() > 0: check_envelope(Placement.mesh_bounds(root), size, height, errors, id)
		root.free()
		var geometry := EnvironmentSpatialQueries.record(definition, placement)
		if maxf(geometry.occupied_span.y, geometry.clearance_span.y) > height: fail(errors, "HEIGHT_EXCEEDED", id, "Occupied volume or clearance exceeds chunk height")
	for id in source.data.tactical.components + visual_only:
		if not ids.has(id): fail(errors, "MISSING_INSTANCE", str(id), "Tactical declaration references a missing instance")
	for error in context.errors: errors.append(error.duplicate(true))
	var keys := dependencies.keys()
	keys.sort()
	for key in keys:
		dependencies[key].required_by.sort()
		result.dependencies.append(dependencies[key])
	# Pins are not refreshed by validation. Empty pins are allowed for a new
	# source; the immutable validation revision records the resolved dependencies.
	for expected in source.data.dependencies:
		var key := str(expected.kind) + ":" + str(expected.id)
		if not dependencies.has(key):
			fail(errors, "UNUSED_DEPENDENCY", key, "Remove obsolete pins explicitly")
			continue
		for field in ["revision", "geometry_sha256", "calibration_signature", "semantic_signature", "certification_signature"]:
			if dependencies[key].has(field) and expected.get(field, "") != dependencies[key][field]: fail(errors, "STALE_DEPENDENCY", key, "Changed " + field + "; update pins explicitly and review again")
		if expected.get("required_by", []) != dependencies[key].required_by: fail(errors, "STALE_DEPENDENCY_OWNERS", key, "Dependency owners changed; update pins explicitly")
	var profiles_read := GenerationJsonStore.parse(FileAccess.get_file_as_string(PROFILES))
	if not profiles_read.ok:
		fail(errors, "PROFILE_DATA_INVALID", "ports", profiles_read.error)
		return result
	for category in ["surfaces", "effects", "links"]:
		for spec in source.data.tactical[category]:
			for key in (["from", "to"] if category == "links" else ["cell"]):
				var at := point(spec[key])
				if not inside(at, size, height): fail(errors, "TACTICAL_OUT_OF_BOUNDS", category, str(at))
	if not errors.is_empty(): return result
	var data := MapData.new()
	data.map_size = size
	errors.append_array(EnvironmentModuleMapWriter.apply(data, tactical, context.catalog, 1.0, source.data.tactical))
	if data.cells.is_empty(): fail(errors, "NO_SURFACES", "tactical.surfaces", "Add explicit ground/support surfaces")
	validate_ports(source, data, layout, context.catalog, profiles_read.value, errors)
	for record in records:
		if record.definition == null:
			var placement: EnvironmentModulePlacement = record.placement
			if not data.has_cell(Vector3i(placement.origin.x, placement.elevation, placement.origin.y)): fail(errors, "UNSUPPORTED_VISUAL", placement.placement_id, "Raw decoration needs an authored support surface")
	for region in source.data.clearances:
		if region.cells.is_empty(): fail(errors, "EMPTY_CLEARANCE", str(region.id), "Declare clearance cells")
		for cell in region.cells:
			var at := point(cell)
			if not inside(at, size, height): fail(errors, "CLEARANCE_OUT_OF_BOUNDS", str(region.id), str(at))
			var span := Vector2(0, height) if region.scope == "whole_column" else Vector2(at.y, at.y + float(region.height))
			if span.y > height: fail(errors, "CLEARANCE_OUT_OF_BOUNDS", str(region.id), "Clearance exceeds height")
			for record in records:
				if record.definition == null and EnvironmentSpatialQueries.visual_intersects_cells(record.visual_bounds, [Vector2i(at.x, at.z)], span): fail(errors, "BLOCKED_CLEARANCE", str(region.id), "Decoration %s intrudes into reserved access" % record.placement.placement_id)
			for placement in layout.placements:
				var geometry := EnvironmentSpatialQueries.record(context.catalog[placement.component_id], placement)
				if geometry.layer == EnvironmentModuleDefinition.PlacementLayer.GROUND: continue
				if (Vector2i(at.x, at.z) in geometry.cells and EnvironmentSpatialQueries.interval_intersects(span, geometry.occupied_span)) or EnvironmentSpatialQueries.visual_intersects_cells(geometry.visual, [Vector2i(at.x, at.z)], span): fail(errors, "BLOCKED_CLEARANCE", str(region.id), "%s intersects %s" % [at, placement.placement_id])
	result.ok = errors.is_empty()
	result.data = data if result.ok else null
	result.resolved = records
	result["compiler"] = VERSION
	result["profiles_sha256"] = FileAccess.get_sha256(PROFILES)
	result["implementation"] = implementation_signature()
	result["revision"] = canonical({"source": source.data, "dependencies": result.dependencies, "compiler": VERSION, "implementation": result.implementation, "profiles": result.profiles_sha256}).sha256_text()
	return result

static func validate_ports(source: EnvironmentChunkSource, data: MapData, layout: EnvironmentModuleLayout, catalog: Dictionary, profiles: Dictionary, errors: Array[Dictionary]) -> void:
	var size := data.map_size
	var access: Array[Vector3i] = []
	var street_cells := {}
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		if definition.module_type not in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]: continue
		var sidewalks := RoadStreetscapeProfile.sidewalk_cells(placement.component_id)
		for local in definition.footprint_cells:
			var at := EnvironmentSpatialQueries.world_point(definition, placement, Vector3i(local.x, 0, local.y))
			street_cells[at] = "sidewalk" if local in sidewalks else "carriageway"
	if source.data.ports.is_empty(): fail(errors, "NO_PORTS", "ports", "A reusable pilot chunk needs at least one access port")
	for port in source.data.ports:
		var id := str(port.id)
		var normal := Vector2i(int(port.normal[0]), int(port.normal[1]))
		var cells: Array[Vector3i] = []
		for cell in port.cells: cells.append(Vector3i(int(cell[0]), int(port.elevation), int(cell[1])))
		cells.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.z < b.z))
		if not profiles.has(port.profile):
			fail(errors, "UNKNOWN_PORT_PROFILE", id, "Choose a profile from chunk_port_profiles.json")
			continue
		if port.connection != "terminated" and int(port.elevation) + EnvironmentSpatialQueries.MIN_FLOOR_HEADROOM > int(source.data.height): fail(errors, "PORT_HEADROOM", id, "Port needs headroom within chunk height")
		var profile: Dictionary = profiles[port.profile]
		if port.role != profile.role or int(port.minimum_width) != int(profile.width) or cells.size() != int(profile.width): fail(errors, "PORT_PROFILE_MISMATCH", id, "Role, span and minimum width must match " + str(port.profile))
		for index in cells.size():
			var at := cells[index]
			if not inside(at, size, int(source.data.height)) or (normal.x < 0 and at.x != 0) or (normal.x > 0 and at.x != size.x - 1) or (normal.y < 0 and at.z != 0) or (normal.y > 0 and at.z != size.y - 1): fail(errors, "PORT_NOT_ON_BOUNDARY", id, str(at))
			if index > 0 and at.distance_squared_to(cells[index - 1]) != 1: fail(errors, "NONCONTIGUOUS_PORT", id, "Port cells must be a unique contiguous span")
			if port.connection == "terminated": continue
			for check_at in [at, at - Vector3i(normal.x, 0, normal.y)]:
				var cell := data.get_cell(check_at)
				if cell == null or not cell.walkable or not cell.can_stop: fail(errors, "BLOCKED_PORT", id, "%s needs a clear surface and approach" % check_at)
			access.append(at)
			if profile.role == "street":
				var expected := "sidewalk" if index in Array(profile.sidewalk_lanes).map(func(value): return int(value)) else "carriageway"
				if street_cells.get(at, "") != expected: fail(errors, "STREET_GEOMETRY_MISMATCH", id, "Port lane %d is not %s in the resolved street piece" % [index, expected])
	if access.is_empty(): return
	var seen := {access[0]: true}
	var queue: Array[Vector3i] = [access[0]]
	var cursor := 0
	while cursor < queue.size():
		var at := queue[cursor]
		cursor += 1
		var next_cells: Array[Vector3i] = []
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]: next_cells.append(at + direction)
		for link in data.traversal_links:
			if link.from_cell == at: next_cells.append(link.to_cell)
			if link.bidirectional and link.to_cell == at: next_cells.append(link.from_cell)
		for next in next_cells:
			var cell := data.get_cell(next)
			if not seen.has(next) and cell != null and cell.walkable:
				seen[next] = true
				queue.append(next)
	for at in access:
		if not seen.has(at): fail(errors, "DISCONNECTED_PORT", "ports", "%s cannot reach the other chunk accesses" % at)
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		if definition.structural_assembly_id.is_empty(): continue
		for cell in definition.clearance_cells:
			var at := EnvironmentSpatialQueries.world_point(definition, placement, Vector3i(cell.x, 0, cell.y))
			if not seen.has(at): fail(errors, "INACCESSIBLE_ASSEMBLY", placement.placement_id, "Working/entrance clearance %s cannot be reached from an active port" % at)

static func ports_match(a: Dictionary, b: Dictionary) -> bool:
	if a.profile != b.profile or a.role != b.role or a.elevation != b.elevation or a.minimum_width != b.minimum_width or a.connection == "terminated" or b.connection == "terminated": return false
	var normal := Vector2i(int(a.normal[0]), int(a.normal[1]))
	if normal != -Vector2i(int(b.normal[0]), int(b.normal[1])) or a.cells.size() != b.cells.size(): return false
	var translated: Array = a.cells.map(func(cell): return [int(cell[0]) + normal.x, int(cell[1]) + normal.y])
	return canonical(sorted_cells(translated)) == canonical(sorted_cells(b.cells))
static func sorted_cells(cells: Array) -> Array:
	var result := cells.duplicate(true)
	result.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return result
static func pin(pins: Dictionary, dependency: Dictionary, id: String) -> void:
	var key := str(dependency.kind) + ":" + str(dependency.id)
	if not pins.has(key): pins[key] = dependency.duplicate(true)
	if id not in pins[key].required_by: pins[key].required_by.append(id)
static func check_envelope(bounds: AABB, size: Vector2i, height: int, errors: Array[Dictionary], id: String) -> void:
	# Thin road/paving bases extend slightly below their support plane.
	if bounds.position.x < -0.51 or bounds.position.z < -0.51 or bounds.end.x > size.x - 0.49 or bounds.end.z > size.y - 0.49 or bounds.position.y < -0.25 or bounds.end.y > height + 0.01: fail(errors, "VISUAL_OUT_OF_BOUNDS", id, str(bounds))
static func point(cell: Array) -> Vector3i: return Vector3i(int(cell[0]), int(cell[1]), int(cell[2]))
static func inside(at: Vector3i, size: Vector2i, height: int) -> bool: return at.x >= 0 and at.z >= 0 and at.x < size.x and at.z < size.y and at.y >= 0 and at.y <= height
static func fail(errors: Array[Dictionary], code: String, field: String, message: String) -> void: errors.append({"code": code, "field": field, "message": message})

static func implementation_signature() -> String:
	var hashes: Array[String] = []
	for path in ["chunk_publication_compiler.gd", "chunk_publication_library.gd", "environment_chunk_source.gd", "environment_module_map_writer.gd", "environment_spatial_queries.gd", "environment_resolution_context.gd", "modular_environment_presenter.gd"]:
		hashes.append(FileAccess.get_sha256("res://systems/generation/" + path))
	return "|".join(hashes).sha256_text()
