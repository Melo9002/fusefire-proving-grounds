class_name EnvironmentModuleMapWriter
extends RefCounted

static func apply(data: MapData, layout: EnvironmentModuleLayout, catalog: Dictionary, cell_size: float) -> void:
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		for local_cell in definition.cell_effects:
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			var cell := data.get_cell(Vector3i(placement.origin.x + rotated.x, placement.elevation, placement.origin.y + rotated.y))
			if cell == null:
				continue
			var effect: Dictionary = definition.cell_effects[local_cell]
			cell.cover_type = effect.get("cover_type", MapCellData.CoverType.NONE)
			cell.cover_height = float(effect.get("cover_height", 0.0)) * cell_size
			cell.walkable = effect.get("walkable", true)
			cell.can_stop = effect.get("can_stop", cell.walkable)
			cell.blocks_line_of_sight = effect.get("blocks_los", false)
			cell.movement_cost = maxi(1, int(effect.get("movement_cost", 1)))
		for local_cell in definition.elevated_surfaces:
			var surface: Dictionary = definition.elevated_surfaces[local_cell]
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			var elevation := placement.elevation + int(surface.elevation)
			var ground := data.get_cell(Vector3i(placement.origin.x + rotated.x, placement.elevation, placement.origin.y + rotated.y))
			if ground == null:
				continue
			var position := Vector3i(placement.origin.x + rotated.x, elevation, placement.origin.y + rotated.y)
			var elevated := MapCellData.new(position, ground.world_position + Vector3.UP * float(elevation - placement.elevation) * cell_size)
			elevated.walkable = surface.get("walkable", true)
			elevated.can_stop = surface.get("can_stop", true)
			elevated.cover_type = surface.get("cover_type", MapCellData.CoverType.NONE)
			elevated.cover_height = float(surface.get("cover_height", 0.0)) * cell_size
			elevated.blocks_line_of_sight = surface.get("blocks_los", false)
			elevated.movement_cost = maxi(1, int(surface.get("movement_cost", 1)))
			data.add_cell(elevated)
		for link in definition.vertical_links:
			var from_cell := _world_vertical_point(definition, placement, link.from)
			var to_cell := _world_vertical_point(definition, placement, link.to)
			data.add_traversal_link(TraversalLinkData.new(from_cell, to_cell, link.bidirectional))
			data.generated_traversals.append(GeneratedTraversalData.new(link.kind, from_cell, to_cell))

static func _world_vertical_point(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, local: Vector3i) -> Vector3i:
	var rotated := definition.rotate_cell(Vector2i(local.x, local.z), placement.rotation)
	return Vector3i(placement.origin.x + rotated.x, placement.elevation + local.y, placement.origin.y + rotated.y)
