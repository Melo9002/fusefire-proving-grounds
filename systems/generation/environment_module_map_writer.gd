class_name EnvironmentModuleMapWriter
extends RefCounted

const Spatial = preload("res://systems/generation/environment_spatial_queries.gd")

const FIELDS := ["walkable", "can_stop", "cover_type", "cover_height", "blocks_los", "movement_cost"]
const DEFAULT_SURFACE := {"walkable": true, "can_stop": true, "cover_type": MapCellData.CoverType.NONE, "cover_height": 0.0, "blocks_los": false, "movement_cost": 1}

## Compile transactionally: surfaces, effects, then links. Sorting controls only
## deterministic insertion/diagnostics; compatibility and merge rules are explicit.
static func apply(data: MapData, layout: EnvironmentModuleLayout, catalog: Dictionary, cell_size: float, explicit: Dictionary = {}) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var surfaces: Dictionary = {}
	var effects: Dictionary = {}
	var links: Array[Dictionary] = []
	var placements := layout.placements.duplicate()
	placements.sort_custom(func(a, b): return _reference(a) < _reference(b))
	for placement: EnvironmentModulePlacement in placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		var ref := _reference(placement)
		if definition == null:
			_fail(errors, "UNKNOWN_COMPONENT", placement.origin, ref)
			continue
		for local: Vector2i in definition.elevated_surfaces:
			var spec: Dictionary = definition.elevated_surfaces[local]
			var base := _world_vertical_point(definition, placement, Vector3i(local.x, 0, local.y))
			var at := base + Vector3i(0, int(spec.elevation), 0)
			if int(spec.elevation) <= 0:
				_fail(errors, "INVALID_SURFACE_ELEVATION", at, ref)
				continue
			var values := DEFAULT_SURFACE.duplicate()
			values.merge(_values(spec, cell_size), true)
			var claim := {"base": base, "values": values, "reference": ref}
			if surfaces.has(at) and (surfaces[at].base != base or surfaces[at].values != values):
				_fail(errors, "CONFLICTING_SURFACE", at, "%s / %s" % [surfaces[at].reference, ref])
			else: surfaces[at] = claim
		for local: Vector2i in definition.cell_effects:
			var at := _world_vertical_point(definition, placement, Vector3i(local.x, 0, local.y))
			if not effects.has(at): effects[at] = {}
			var layer := definition.placement_layer
			if not effects[at].has(layer): effects[at][layer] = {"values": {}, "owners": {}}
			var claim: Dictionary = effects[at][layer]
			var values := _values(definition.cell_effects[local], cell_size)
			for field in values:
				if claim.values.has(field) and claim.values[field] != values[field]:
					_fail(errors, "CONFLICTING_EFFECT", at, "%s / %s (%s)" % [claim.owners[field], ref, field])
				else:
					claim.values[field] = values[field]
					claim.owners[field] = ref
		for link in definition.vertical_links:
			links.append({"from": _world_vertical_point(definition, placement, link.from), "to": _world_vertical_point(definition, placement, link.to), "kind": link.kind, "bidirectional": link.bidirectional, "reference": ref})
	# Chunk-local declarations enter the same transaction as module contributions.
	# They never mutate a precompiled map in a second pass.
	for spec in explicit.get("surfaces", []):
		var at := _point(spec.cell)
		var base := Vector3i(at.x, 0, at.z)
		var values := _values(spec.values, cell_size)
		if surfaces.has(at):
			for field in values:
				if surfaces[at].values.has(field) and surfaces[at].values[field] != values[field]: _fail(errors, "CONFLICTING_SURFACE", at, "explicit surface / " + surfaces[at].reference)
				else: surfaces[at].values[field] = values[field]
		else: surfaces[at] = {"base": base, "values": values, "reference": "explicit surface"}
	for spec in explicit.get("effects", []):
		var at := _point(spec.cell)
		var layer := int(spec.layer)
		if not effects.has(at): effects[at] = {}
		if not effects[at].has(layer): effects[at][layer] = {"values": {}, "owners": {}}
		var claim: Dictionary = effects[at][layer]
		for field in spec.values:
			var value = _values(spec.values, cell_size)[field]
			if claim.values.has(field) and claim.values[field] != value: _fail(errors, "CONFLICTING_EFFECT", at, "explicit effect / " + str(claim.owners.get(field, "")))
			else:
				claim.values[field] = value
				claim.owners[field] = "explicit effect"
	for spec in explicit.get("links", []):
		links.append({"from": _point(spec.from), "to": _point(spec.to), "kind": int(spec.kind), "bidirectional": spec.bidirectional, "reference": "explicit link"})
	if not errors.is_empty(): return errors

	# Stage cells, leaving the input map completely unchanged on any failure.
	var staged: Dictionary = {}
	var positions := surfaces.keys()
	positions.sort_custom(_position_less)
	for at: Vector3i in positions:
		var claim: Dictionary = surfaces[at]
		var base: MapCellData = staged.get(claim.base, data.get_cell(claim.base))
		if base == null and at.y != 0:
			_fail(errors, "MISSING_SURFACE_SUPPORT", at, claim.reference)
			continue
		var world := Vector3((at.x - data.map_size.x * 0.5 + 0.5) * cell_size, 0, (at.z - data.map_size.y * 0.5 + 0.5) * cell_size) if base == null else base.world_position + Vector3.UP * float(at.y - claim.base.y) * cell_size
		var cell := MapCellData.new(at, world)
		var values := DEFAULT_SURFACE.duplicate()
		values.merge(claim.values, true)
		_set_values(cell, values)
		var existing := data.get_cell(at)
		if existing != null:
			if _cell_values(existing) != _cell_values(cell):
				_fail(errors, "CONFLICTING_SURFACE", at, claim.reference)
				continue
			cell = _copy_cell(existing)
		staged[at] = cell
	errors.append_array(Spatial.support_errors(layout, catalog, func(at): return staged.has(at) or data.has_cell(at)))
	var columns := Spatial.surface_columns(surfaces.keys())
	var heights := func(at: Vector3i):
		var result: Array = columns.get(Vector2i(at.x, at.z), []).duplicate()
		for cell: MapCellData in data.get_column_cells(at.x, at.z): result.append(cell.grid_position.y)
		return result
	errors.append_array(Spatial.headroom_errors(surfaces.keys(), heights))
	var floor_planes := surfaces.keys()
	for at: Vector3i in data.cells:
		if at.y > 0 and at not in floor_planes: floor_planes.append(at)
	for placement in placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		var geometry := Spatial.record(definition, placement)
		for at: Vector3i in floor_planes:
			if at in geometry.surfaces: continue
			if Spatial.plane_conflict(at, geometry):
				_fail(errors, "SURFACE_INTERSECTS_VOLUME", at, _reference(placement))
	positions = effects.keys()
	positions.sort_custom(_position_less)
	for at: Vector3i in positions:
		var source: MapCellData = staged.get(at, data.get_cell(at))
		if source == null:
			_fail(errors, "MISSING_EFFECT_SURFACE", at, str(effects[at]))
			continue
		var cell := _copy_cell(source)
		for claim: Dictionary in effects[at].values():
			for field in claim.values:
				var value = claim.values[field]
				match field:
					"walkable": cell.walkable = cell.walkable and bool(value)
					"can_stop": cell.can_stop = cell.can_stop and bool(value)
					"blocks_los": cell.blocks_line_of_sight = cell.blocks_line_of_sight or bool(value)
					"cover_type": cell.cover_type = maxi(cell.cover_type, int(value)) as MapCellData.CoverType
					"cover_height": cell.cover_height = maxf(cell.cover_height, float(value))
					"movement_cost": cell.movement_cost = maxi(cell.movement_cost, int(value))
		cell.can_stop = cell.can_stop and cell.walkable
		staged[at] = cell
	for link in links:
		for at: Vector3i in [link.from, link.to]:
			var endpoint: MapCellData = staged.get(at, data.get_cell(at))
			if endpoint == null: _fail(errors, "MISSING_TRAVERSAL_ENDPOINT", at, link.reference)
			elif not endpoint.walkable: _fail(errors, "BLOCKED_TRAVERSAL_ENDPOINT", at, link.reference)
	if not errors.is_empty(): return errors

	positions = staged.keys()
	positions.sort_custom(_position_less)
	for at: Vector3i in positions:
		var existing := data.get_cell(at)
		if existing == null: data.add_cell(staged[at])
		else: _set_values(existing, _cell_values(staged[at]))
	links.sort_custom(func(a, b): return str([a.from, a.to, a.kind, a.bidirectional]) < str([b.from, b.to, b.kind, b.bidirectional]))
	for link in links:
		data.add_traversal_link(TraversalLinkData.new(link.from, link.to, link.bidirectional))
		data.generated_traversals.append(GeneratedTraversalData.new(link.kind, link.from, link.to))
	return errors

static func _values(spec: Dictionary, cell_size: float) -> Dictionary:
	var result := {}
	for field in FIELDS:
		if not spec.has(field): continue
		result[field] = spec[field]
		if field == "cover_height": result[field] = float(spec[field]) * cell_size
		elif field == "movement_cost": result[field] = maxi(1, int(spec[field]))
	return result

static func _cell_values(cell: MapCellData) -> Dictionary:
	return {"walkable": cell.walkable, "can_stop": cell.can_stop, "cover_type": cell.cover_type, "cover_height": cell.cover_height, "blocks_los": cell.blocks_line_of_sight, "movement_cost": cell.movement_cost}

static func _set_values(cell: MapCellData, values: Dictionary) -> void:
	for field in values:
		cell.set("blocks_line_of_sight" if field == "blocks_los" else field, values[field])

static func _copy_cell(source: MapCellData) -> MapCellData:
	var cell := MapCellData.new(source.grid_position, source.world_position)
	_set_values(cell, _cell_values(source))
	cell.elevation = source.elevation
	cell.hazard_condition = source.hazard_condition
	return cell

static func _position_less(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y: return a.y < b.y
	if a.x != b.x: return a.x < b.x
	return a.z < b.z

static func _reference(placement: EnvironmentModulePlacement) -> String:
	return placement.placement_id if not placement.placement_id.is_empty() else placement.signature()

static func _fail(errors: Array[Dictionary], code: String, at, ref: String) -> void:
	errors.append({"code": code, "field": "compiled_map", "reference": ref, "message": "%s at %s: %s" % [code, at, ref]})

static func _world_vertical_point(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, local: Vector3i) -> Vector3i:
	return Spatial.world_point(definition, placement, local)

static func _point(value: Array) -> Vector3i:
	return Vector3i(int(value[0]), int(value[1]), int(value[2]))
