class_name EnvironmentSpatialQueries
extends RefCounted
## Shared construction-space geometry, in unscaled cell units. Semantic
## ownership/mission exceptions belong to callers, not these queries.
const MIN_FLOOR_HEADROOM := 2

static func world_point(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, local: Vector3i) -> Vector3i:
	var horizontal := definition.rotate_cell(Vector2i(local.x, local.z), placement.rotation)
	return Vector3i(placement.origin.x + horizontal.x, placement.elevation + local.y, placement.origin.y + horizontal.y)

static func cells(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, source: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in definition.rotated_cells(source, placement.rotation): result.append(placement.origin + cell)
	return result

static func interval_intersects(a: Vector2, b: Vector2) -> bool:
	return a.x < b.y and b.x < a.y and a.x < a.y and b.x < b.y

static func cells_intersect(a: Array, b: Array) -> bool:
	for cell in a:
		if cell in b: return true
	return false

static func visual_intersects_cells(bounds: AABB, footprint: Array, span: Vector2) -> bool:
	if bounds.size == Vector3.ZERO or not interval_intersects(Vector2(bounds.position.y, bounds.end.y), span): return false
	for cell: Vector2i in footprint:
		# Continuous module coordinates are relative to cell centers, matching
		# rotate_point and the presenter's origin-cell world position.
		if bounds.position.x < cell.x + 0.5 and bounds.end.x > cell.x - 0.5 and bounds.position.z < cell.y + 0.5 and bounds.end.z > cell.y - 0.5: return true
	return false

static func record(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Dictionary:
	var bottom := float(placement.elevation)
	return {"component_id": placement.component_id, "layer": definition.placement_layer,
		"cells": cells(definition, placement, definition.footprint_cells),
		"clearance": cells(definition, placement, definition.clearance_cells),
		"occupied_span": Vector2(bottom, bottom + definition.occupancy_height),
		"clearance_span": Vector2(bottom, bottom + definition.clearance_height),
		"visual": visual_envelope(definition, placement), "surfaces": surface_cells(definition, placement)}

static func surface_cells(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: Vector2i in definition.elevated_surfaces:
		result.append(world_point(definition, placement, Vector3i(cell.x, int(definition.elevated_surfaces[cell].elevation), cell.y)))
	return result

static func plane_conflict(at: Vector3i, other: Dictionary) -> bool:
	var horizontal := Vector2i(at.x, at.z)
	if horizontal in other.cells and other.occupied_span.x < at.y and other.occupied_span.y > at.y: return true
	if horizontal in other.clearance and other.clearance_span.x < at.y and other.clearance_span.y > at.y: return true
	var bounds: AABB = other.visual
	return bounds.position.y < at.y and bounds.end.y > at.y and visual_intersects_cells(bounds, [horizontal], Vector2(at.y - 0.001, at.y + 0.001))

static func conflict(a: Dictionary, b: Dictionary) -> String:
	for at in a.surfaces:
		if plane_conflict(at, b): return "floor intersects occupied volume or headroom"
	for at in b.surfaces:
		if plane_conflict(at, a): return "occupied volume or headroom intersects floor"
	# Ground is a composable surface layer. Other layers cannot exempt physical
	# intersections simply by assigning a different rendering category.
	var comparable: bool = a.layer == b.layer or (a.layer != EnvironmentModuleDefinition.PlacementLayer.GROUND and b.layer != EnvironmentModuleDefinition.PlacementLayer.GROUND)
	if not comparable: return ""
	if interval_intersects(a.occupied_span, b.occupied_span) and cells_intersect(a.cells, b.cells): return "occupied volumes overlap"
	if interval_intersects(a.occupied_span, b.clearance_span) and cells_intersect(a.cells, b.clearance): return "intrudes into clearance"
	if interval_intersects(b.occupied_span, a.clearance_span) and cells_intersect(b.cells, a.clearance): return "clearance overlaps occupancy"
	if a.visual.size != Vector3.ZERO and b.visual.size != Vector3.ZERO and a.visual.intersects(b.visual): return "visual envelope intersects"
	if visual_intersects_cells(a.visual, b.cells, b.occupied_span) or visual_intersects_cells(b.visual, a.cells, a.occupied_span): return "visual envelope intersects occupied volume"
	if visual_intersects_cells(a.visual, b.clearance, b.clearance_span) or visual_intersects_cells(b.visual, a.clearance, a.clearance_span): return "visual envelope intrudes into clearance"
	return ""

## Validate a completed authoring layout against the bounded flat-base pilot.
## Surface dependencies are resolved by elevation, never placement insertion order.
static func source_support_errors(layout: EnvironmentModuleLayout, catalog: Dictionary, map_dimensions: Vector2i) -> Array[Dictionary]:
	var known := {}
	var declarations: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	var has_surface := func(at: Vector3i): return (at.y == 0 and Rect2i(Vector2i.ZERO, map_dimensions).has_point(Vector2i(at.x, at.z))) or known.has(at)
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null: continue
		for cell: Vector2i in definition.elevated_surfaces:
			var base := world_point(definition, placement, Vector3i(cell.x, 0, cell.y))
			declarations.append({"base": base, "at": base + Vector3i(0, int(definition.elevated_surfaces[cell].elevation), 0), "reference": placement.placement_id})
	declarations.sort_custom(func(a, b): return a.at.y < b.at.y)
	for declaration in declarations:
		if declaration.at.y <= declaration.base.y or not has_surface.call(declaration.base):
			errors.append({"code": "MISSING_SURFACE_SUPPORT", "field": "spatial_layout.placements", "reference": declaration.reference, "message": "Unsupported surface at %s" % declaration.at})
		else: known[declaration.at] = true
	errors.append_array(support_errors(layout, catalog, has_surface))
	var columns := surface_columns(known.keys())
	for column in columns.values(): column.append(0)
	errors.append_array(headroom_errors(known.keys(), func(at): return columns.get(Vector2i(at.x, at.z), [])))
	return errors

static func surface_columns(positions: Array) -> Dictionary:
	var columns := {}
	for at: Vector3i in positions:
		var horizontal := Vector2i(at.x, at.z)
		if not columns.has(horizontal): columns[horizontal] = []
		if at.y not in columns[horizontal]: columns[horizontal].append(at.y)
	return columns

static func headroom_errors(positions: Array, column_heights: Callable) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for at: Vector3i in positions:
		for height: int in column_heights.call(at):
			if height != at.y and absi(height - at.y) < MIN_FLOOR_HEADROOM:
				errors.append({"code": "INSUFFICIENT_HEADROOM", "field": "spatial_layout.placements", "reference": str(at), "message": "Floors at %s and elevation %d require two cell units of headroom" % [at, height]})
	return errors

static func support_errors(layout: EnvironmentModuleLayout, catalog: Dictionary, has_surface: Callable) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null: continue
		for cell in cells(definition, placement, definition.footprint_cells) + cells(definition, placement, definition.clearance_cells):
			var at := Vector3i(cell.x, placement.elevation, cell.y)
			if not has_surface.call(at):
				errors.append({"code": "MISSING_PLACEMENT_SUPPORT", "field": "spatial_layout.placements", "reference": placement.placement_id, "message": "%s lacks support at %s" % [placement.component_id, at]})
	return errors

static func visual_envelope(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> AABB:
	var local := definition.visual_envelope
	if local.size == Vector3.ZERO:
		return AABB()
	var points: Array[Vector3] = []
	for x in [local.position.x, local.end.x]:
		for y in [local.position.y, local.end.y]:
			for z in [local.position.z, local.end.z]:
				var horizontal := definition.rotate_point(Vector2(x, z), placement.rotation)
				var point := Vector3(horizontal.x, y, horizontal.y)
				points.append(point + Vector3(placement.origin.x, placement.elevation, placement.origin.y))
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	# Authoring envelopes that only touch at their boundary are compatible.
	return bounds.grow(-0.01) if bounds.size.x > 0.02 and bounds.size.y > 0.02 and bounds.size.z > 0.02 else bounds
