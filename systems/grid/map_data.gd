class_name MapData
extends RefCounted

var cells: Dictionary = {}
var containers: Array[Rect2i] = []
var buildings: Array[GeneratedBuildingData] = []
var platforms: Array[GeneratedPlatformData] = []
var hills: Array[GeneratedHillData] = []
var columns: Dictionary = {}
var traversal_links: Array[TraversalLinkData] = []
var generated_traversals: Array[GeneratedTraversalData] = []
var los_blocking_cells: Array[MapCellData] = []
var zones: Dictionary[StringName, MapZoneData] = {}
var source_kind: String = "authored"
var generation_seed: int = 0
var map_size := Vector2i.ZERO
var transport_footprints: Dictionary = {}

func add_cell(cell: MapCellData) -> void:
	cells[cell.grid_position] = cell
	var column_key := Vector2i(cell.grid_position.x, cell.grid_position.z)
	if not columns.has(column_key):
		columns[column_key] = []
	var column: Array = columns[column_key]
	for index in column.size():
		if column[index].grid_position == cell.grid_position:
			column[index] = cell
			return
	column.append(cell)

func get_cell(grid_position: Vector3i) -> MapCellData:
	return cells.get(grid_position, null)

func has_cell(grid_position: Vector3i) -> bool:
	return cells.has(grid_position)

func get_column_cells(x: int, z: int) -> Array[MapCellData]:
	var column: Array[MapCellData] = []
	column.assign(columns.get(Vector2i(x, z), []))
	return column

func add_traversal_link(link: TraversalLinkData) -> void:
	traversal_links.append(link)

func add_spawn_cell(faction: TacticalUnit.Faction, grid_position: Vector3i) -> void:
	var zone_id := StringName("deployment_%d" % faction)
	var zone := get_zone(zone_id)
	if not zone:
		zone = MapZoneData.new(zone_id, MapZoneData.Kind.DEPLOYMENT, [], faction)
		set_zone(zone)
	zone.cells.append(grid_position)

func get_spawn_cells(faction: TacticalUnit.Faction) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for zone in get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
		if zone.faction == faction:
			result.append_array(zone.cells)
	return result

func get_total_spawn_count() -> int:
	var total := 0
	for zone in get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
		total += zone.cells.size()
	return total

func set_zone(zone: MapZoneData) -> void:
	if zone and not zone.zone_id.is_empty():
		zones[zone.zone_id] = zone

func get_zone(zone_id: StringName) -> MapZoneData:
	return zones.get(zone_id) as MapZoneData

func get_zones_by_kind(kind: MapZoneData.Kind) -> Array[MapZoneData]:
	var result: Array[MapZoneData] = []
	for zone in zones.values():
		if zone.kind == kind:
			result.append(zone)
	return result

func set_objective_zone(zone_id: StringName, zone_cells: Array[Vector3i]) -> void:
	var kind := MapZoneData.Kind.EXTRACTION if String(zone_id).ends_with("extract") else MapZoneData.Kind.OBJECTIVE
	set_zone(MapZoneData.new(zone_id, kind, zone_cells))

func get_objective_zone(zone_id: StringName) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var zone := get_zone(zone_id)
	if zone:
		result.assign(zone.cells)
	return result

func rebuild_los_index() -> void:
	los_blocking_cells.clear()
	for cell: MapCellData in cells.values():
		if cell.blocks_line_of_sight and cell.cover_height > 0.0:
			los_blocking_cells.append(cell)

func clear() -> void:
	transport_footprints.clear()
	containers.clear()
	buildings.clear()
	platforms.clear()
	hills.clear()
	cells.clear()
	columns.clear()
	traversal_links.clear()
	generated_traversals.clear()
	los_blocking_cells.clear()
	zones.clear()
	source_kind = "authored"
	generation_seed = 0
	map_size = Vector2i.ZERO
