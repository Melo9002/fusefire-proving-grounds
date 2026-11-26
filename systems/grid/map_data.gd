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
## Raised parts can obstruct rays without intersecting any standing surface.
var shot_obstacles: Array[MapCellData] = []
var shot_columns: Dictionary = {}
## Presentation-query invalidation; not simulation state or replay evidence.
var los_revision := 0
## Authoritative curves and their column index for standing, sweeps and shots.
var curved_parts: Array[CylinderPart] = []
var curved_columns: Dictionary = {}
var curved_envelope := AABB()
## Presentation-only shapes for round assets, in world units. Tactics never read these: the
## reserved tiles, cover, shots and standing points are unchanged. Cover markers and pose
## contacts use them so they follow the real wall instead of the tile-sized stand-ins below.
var presentation_cylinders: Array[CylinderPart] = []
var presentation_boxes: Array[AABB] = []
## The tile-sized boxes the compiler reserved in place of a round asset. Presentation skips them.
var presentation_stand_ins: Dictionary = {}
## Current compilation uses one deterministic point per supported cell.
var surface_placement_enabled := false
var surface_points_resolved := false
var surface_unit := 1.0
var body_radius := 0.28
var body_height := 1.8
var body_clearance := 0.04
var movement_parts: Array[AABB] = []
## Certified local footing offsets, indexed by the canonical resting cell.
var contextual_steps: Dictionary[Vector3i, Vector3] = {}
var movement_columns: Dictionary = {}
var movement_index_count := -1
var movement_routes: Dictionary = {}
var zones: Dictionary[StringName, MapZoneData] = {}
var source_kind: String = "authored"
var generation_seed: int = 0
var map_size := Vector2i.ZERO
## Exact authored content choices used to construct this map. A seed records
## provenance but is not a durable substitute for these resolved choices.
var content_manifest: Dictionary = {}
## Fatal construction diagnostics. Callers must not activate a battle when
## this list is non-empty.
var generation_errors: Array[Dictionary] = []
var transport_footprints: Dictionary = {}
## Optional presentation names keyed by authoritative grid elevation. Missing
## names fall back to Ground / Level N in generic floor controls.
var elevation_labels: Dictionary[int, String] = {0: "Ground"}

func add_cell(cell: MapCellData) -> void:
	los_revision += 1
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
	los_revision += 1
	los_blocking_cells.clear()
	for cell: MapCellData in cells.values():
		if cell.blocks_line_of_sight and cell.cover_height > 0.0:
			los_blocking_cells.append(cell)
	los_blocking_cells.append_array(shot_obstacles)

func add_shot_obstacle(obstacle: MapCellData) -> void:
	los_revision += 1
	obstacle.is_shot_only = true
	shot_obstacles.append(obstacle)
	var column := Vector2i(obstacle.grid_position.x, obstacle.grid_position.z)
	if not shot_columns.has(column): shot_columns[column] = []
	shot_columns[column].append(obstacle)

## Index one obstacle identity across its full envelope. The envelope is only
## for lookup/debug drawing; the exact shape answers movement and shot queries.
func add_curved_obstacle(part: CylinderPart, unit: float) -> void:
	var bounds := part.enclosing_bounds()
	var half := Vector2(map_size) * 0.5
	var lower := Vector2i(floori(bounds.position.x / unit + half.x), floori(bounds.position.z / unit + half.y)).max(Vector2i.ZERO)
	var upper := Vector2i(ceili(bounds.end.x / unit + half.x), ceili(bounds.end.z / unit + half.y)).min(map_size)
	if lower.x >= upper.x or lower.y >= upper.y: return
	curved_envelope = bounds if curved_parts.is_empty() else curved_envelope.merge(bounds)
	curved_parts.append(part)
	var obstacle := MapCellData.new(Vector3i(lower.x, floori(part.center.y / unit), lower.y), part.center)
	obstacle.curved_part = part
	obstacle.authored_shot_bounds = bounds
	obstacle.cover_height = part.height
	obstacle.cover_type = MapCellData.CoverType.FULL if part.height >= unit * 1.2 else MapCellData.CoverType.LOW
	obstacle.walkable = false
	obstacle.can_stop = false
	obstacle.blocks_line_of_sight = true
	add_shot_obstacle(obstacle)
	for x in range(lower.x, upper.x):
		for z in range(lower.y, upper.y):
			var key := Vector2i(x, z)
			if not curved_columns.has(key): curved_columns[key] = []
			curved_columns[key].append(obstacle)
			if key == lower: continue
			if not shot_columns.has(key): shot_columns[key] = []
			shot_columns[key].append(obstacle)

func get_walkable_elevation_levels() -> Array[int]:
	var seen: Dictionary = {}
	for cell: MapCellData in cells.values():
		if cell.walkable and cell.can_stop:
			seen[cell.grid_position.y] = true
	var levels: Array[int] = []
	for level in seen.keys():
		levels.append(int(level))
	levels.sort()
	return levels

func get_elevation_label(level: int) -> String:
	return elevation_labels.get(level, "Ground" if level == 0 else "Level %d" % level)

func get_inspectable_elevation_levels() -> Array[int]:
	var walkable := get_walkable_elevation_levels()
	var levels: Array[int] = []
	for level in elevation_labels.keys():
		if walkable.has(int(level)):
			levels.append(int(level))
	levels.sort()
	return levels

func clear() -> void:
	los_revision += 1
	curved_parts.clear()
	curved_columns.clear()
	curved_envelope = AABB()
	presentation_cylinders.clear()
	presentation_boxes.clear()
	presentation_stand_ins.clear()
	surface_placement_enabled = false
	surface_points_resolved = false
	movement_parts.clear()
	contextual_steps.clear()
	movement_columns.clear()
	movement_index_count = -1
	movement_routes.clear()
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
	shot_obstacles.clear()
	shot_columns.clear()
	zones.clear()
	source_kind = "authored"
	generation_seed = 0
	map_size = Vector2i.ZERO
	content_manifest.clear()
	generation_errors.clear()
	elevation_labels = {0: "Ground"}
