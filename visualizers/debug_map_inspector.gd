class_name DebugMapInspector
extends Node3D

@export var grid_manager: GridManager
@export var mouse_raycaster: MouseRaycaster

var inspection_enabled := false
var show_zones := true
var show_traversal_links := true
var hovered_cell: MapCellData
var _zone_mesh := MeshInstance3D.new()
var _link_mesh := MeshInstance3D.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_zone_mesh.name = "ZoneMarkers"
	_link_mesh.name = "TraversalLinks"
	add_child(_zone_mesh)
	add_child(_link_mesh)
	visible = false

func _process(_delta: float) -> void:
	if not inspection_enabled or not mouse_raycaster:
		hovered_cell = null
		return
	var hit := mouse_raycaster.get_floor_raycast_result()
	hovered_cell = null if hit.is_empty() else grid_manager.get_cell_data(hit.grid_position)

func set_inspection_enabled(enabled: bool) -> void:
	inspection_enabled = enabled
	visible = enabled
	if enabled:
		rebuild()
	else:
		hovered_cell = null

func set_zones_visible(enabled: bool) -> void:
	show_zones = enabled
	_zone_mesh.visible = enabled

func set_traversal_links_visible(enabled: bool) -> void:
	show_traversal_links = enabled
	_link_mesh.visible = enabled

func rebuild() -> void:
	if not grid_manager:
		return
	_zone_mesh.mesh = _build_zone_mesh()
	_zone_mesh.material_override = _material(Color.WHITE)
	_zone_mesh.visible = show_zones
	_link_mesh.mesh = _build_link_mesh()
	_link_mesh.material_override = _material(Color(1.0, 0.82, 0.15, 0.95))
	_link_mesh.visible = show_traversal_links

func get_map_summary() -> Array[String]:
	if not grid_manager:
		return ["MAP INSPECTOR: missing GridManager"]
	var data := grid_manager.map_data
	var walkable := 0
	var stoppable := 0
	var elevated := 0
	var low_cover := 0
	var full_cover := 0
	for cell: MapCellData in data.cells.values():
		walkable += int(cell.walkable)
		stoppable += int(cell.can_stop)
		elevated += int(cell.grid_position.y != 0)
		low_cover += int(cell.cover_type == MapCellData.CoverType.LOW)
		full_cover += int(cell.cover_type == MapCellData.CoverType.FULL)
	return [
		"MAP — %s | %dx%d | seed %d" % [data.source_kind, data.map_size.x, data.map_size.y, data.generation_seed],
		"Cells %d | walkable %d | stoppable %d | occupied %d" % [data.cells.size(), walkable, stoppable, grid_manager.occupancy_map.size()],
		"Elevation %d | cover L/F %d/%d | LOS blockers %d" % [elevated, low_cover, full_cover, data.los_blocking_cells.size()],
		"Zones %d | links %d | buildings %d | platforms %d | hills %d" % [data.zones.size(), data.traversal_links.size(), data.buildings.size(), data.platforms.size(), data.hills.size()],
	]

func get_hover_summary() -> Array[String]:
	if not hovered_cell:
		return ["CELL — hover a walkable surface", "Alt + wheel selects stacked surfaces"]
	var cell := hovered_cell
	var unit := grid_manager.get_unit_at(cell.grid_position)
	var zone_names: Array[String] = []
	for zone: MapZoneData in grid_manager.map_data.zones.values():
		if zone.cells.has(cell.grid_position):
			zone_names.append("%s:%s" % [zone.zone_id, MapZoneData.Kind.keys()[zone.kind]])
	var links: Array[String] = []
	for link: TraversalLinkData in grid_manager.map_data.traversal_links:
		if link.from_cell == cell.grid_position:
			links.append("→ %s%s" % [link.to_cell, " ↔" if link.bidirectional else ""])
		elif link.to_cell == cell.grid_position:
			links.append("← %s%s" % [link.from_cell, " ↔" if link.bidirectional else ""])
	return [
		"CELL — %s | world (%.1f, %.1f, %.1f)" % [cell.grid_position, cell.world_position.x, cell.world_position.y, cell.world_position.z],
		"Elevation %.1f | walkable %s | stop %s | move cost %d" % [cell.elevation, cell.walkable, cell.can_stop, cell.movement_cost],
		"Cover %s %.1fm | blocks LOS %s" % [MapCellData.CoverType.keys()[cell.cover_type], cell.cover_height, cell.blocks_line_of_sight],
		"Occupant %s | zones %s" % [unit.name if is_instance_valid(unit) else "none", ", ".join(zone_names) if not zone_names.is_empty() else "none"],
		"Traversal %s" % [", ".join(links) if not links.is_empty() else "none"],
	]

func _build_zone_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := grid_manager.cell_size * 0.38
	for zone: MapZoneData in grid_manager.map_data.zones.values():
		var color := _zone_color(zone)
		for coordinate in zone.cells:
			var cell := grid_manager.get_cell_data(coordinate)
			if not cell:
				continue
			var center := cell.world_position + Vector3.UP * 0.11
			var a := center + Vector3(-half, 0, -half)
			var b := center + Vector3(half, 0, -half)
			var c := center + Vector3(half, 0, half)
			var d := center + Vector3(-half, 0, half)
			surface.set_color(color); surface.add_vertex(a)
			surface.set_color(color); surface.add_vertex(b)
			surface.set_color(color); surface.add_vertex(c)
			surface.set_color(color); surface.add_vertex(a)
			surface.set_color(color); surface.add_vertex(c)
			surface.set_color(color); surface.add_vertex(d)
	return surface.commit()

func _build_link_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for link: TraversalLinkData in grid_manager.map_data.traversal_links:
		var from_cell := grid_manager.get_cell_data(link.from_cell)
		var to_cell := grid_manager.get_cell_data(link.to_cell)
		if not from_cell or not to_cell:
			continue
		surface.add_vertex(from_cell.world_position + Vector3.UP * 0.24)
		surface.add_vertex(to_cell.world_position + Vector3.UP * 0.24)
	return surface.commit()

func _zone_color(zone: MapZoneData) -> Color:
	match zone.kind:
		MapZoneData.Kind.DEPLOYMENT:
			return Color(0.2, 0.55, 1.0, 0.62) if zone.faction != TacticalUnit.Faction.ENEMY else Color(1.0, 0.22, 0.18, 0.62)
		MapZoneData.Kind.EXTRACTION:
			return Color(0.15, 1.0, 0.42, 0.68)
		_:
			return Color(0.75, 0.28, 1.0, 0.68)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.no_depth_test = true
	return material
