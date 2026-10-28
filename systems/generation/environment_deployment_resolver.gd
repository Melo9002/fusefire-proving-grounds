class_name EnvironmentDeploymentResolver
extends RefCounted
## Shared deterministic deployment preservation policy for coherent generation
## and document-driven reconstruction. It moves only illegal deployment cells.

static func repair(data: MapData, reachable_anchors: Array[Vector3i] = []) -> Dictionary:
	var failures: Array[Dictionary] = []
	var repairs: Array[Dictionary] = []
	var used: Dictionary = {}
	var reachable := _connected_ground(data, reachable_anchors)
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ENEMY, TacticalUnit.Faction.ALLY]:
		for zone in data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
			if zone.faction != faction: continue
			var required_count := zone.cells.size()
			var repaired: Array[Vector3i] = []
			for original in zone.cells:
				var chosen: Vector3i = original
				var cell := data.get_cell(chosen)
				if cell == null or not cell.walkable or not cell.can_stop or used.has(chosen) or (not reachable.is_empty() and not reachable.has(chosen)):
					chosen = _nearest_deployment_cell(data, original, used, reachable)
					if chosen != Vector3i(-1, -1, -1): repairs.append({"zone_id": String(zone.zone_id), "from": original, "to": chosen})
				if chosen != Vector3i(-1, -1, -1):
					repaired.append(chosen)
					used[chosen] = true
			zone.cells.assign(repaired)
			if repaired.size() != required_count:
				failures.append({"code": "DEPLOYMENT_REPAIR_FAILED", "zone_id": String(zone.zone_id), "required": required_count, "placed": repaired.size(), "message": "required deployment cells could not be placed"})
	return {"ok": failures.is_empty(), "failures": failures, "repairs": repairs}

static func road_anchors(layout: EnvironmentModuleLayout, catalog: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null or definition.module_type not in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]: continue
		var candidates := layout.world_cells(definition, placement)
		for horizontal in candidates:
			var candidate := Vector3i(horizontal.x, placement.elevation, horizontal.y)
			if candidate not in result: result.append(candidate)
	return result

static func plan_anchors(plan: EnvironmentLayoutPlan) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for road_macro in plan.road_cells:
		result.append(Vector3i(road_macro.x * plan.macro_size + int(plan.macro_size / 2.0), 0, road_macro.y * plan.macro_size + int(plan.macro_size / 2.0)))
	return result

static func _connected_ground(data: MapData, anchors: Array[Vector3i]) -> Dictionary:
	var reached: Dictionary = {}
	var frontier: Array[Vector3i] = []
	for anchor in anchors:
		var cell := data.get_cell(anchor)
		if cell != null and cell.walkable:
			frontier.append(anchor)
			reached[anchor] = true
			break
	if frontier.is_empty(): return reached
	while not frontier.is_empty():
		var current: Vector3i = frontier.pop_back()
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var next: Vector3i = current + direction
			if reached.has(next): continue
			var next_cell := data.get_cell(next)
			if next_cell == null or not next_cell.walkable: continue
			reached[next] = true
			frontier.append(next)
	return reached

static func _nearest_deployment_cell(data: MapData, origin: Vector3i, used: Dictionary, allowed: Dictionary) -> Vector3i:
	var maximum_radius := maxi(data.map_size.x, data.map_size.y)
	for radius in range(1, maximum_radius + 1):
		for dz in range(-radius, radius + 1):
			var remaining := radius - absi(dz)
			for dx in ([-remaining] if remaining == 0 else [-remaining, remaining]):
				var candidate := Vector3i(origin.x + dx, 0, origin.z + dz)
				if candidate.x < 0 or candidate.z < 0 or candidate.x >= data.map_size.x or candidate.z >= data.map_size.y or used.has(candidate) or (not allowed.is_empty() and not allowed.has(candidate)): continue
				var cell := data.get_cell(candidate)
				if cell != null and cell.walkable and cell.can_stop: return candidate
	return Vector3i(-1, -1, -1)
