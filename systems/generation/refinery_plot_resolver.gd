class_name RefineryPlotResolver
extends RefCounted
## Resolves one bounded authored plot before battle activation. The returned
## placements are durable choices; replay must not rely on the seed alone.

const PlotCatalog = preload("res://systems/generation/refinery_plot_catalog.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")

static func resolve(seed: int, population_enabled: bool = true, requested: Dictionary = {}) -> Dictionary:
	var plot := _resolve_plot(seed, requested)
	if plot.is_empty():
		return _failure(seed, population_enabled, "UNKNOWN_PLOT", String(requested.get("plot_id", "")))
	var result := {"schema": 1, "plot_id": plot.plot_id, "plot_revision": plot.revision, "map_size": plot.map_size, "seed": seed, "population_enabled": population_enabled, "placements": [], "errors": []}
	if int(requested.get("plot_revision", plot.revision)) != int(plot.revision):
		result.errors.append(_error("STALE_PLOT_REVISION", String(plot.plot_id)))
		return result
	var requested_placements: Dictionary = {}
	for placement in requested.get("placements", []):
		requested_placements[StringName(placement.get("slot_id", &""))] = placement
	for slot_index in plot.slots.size():
		var slot: Dictionary = plot.slots[slot_index]
		var requested_placement: Dictionary = requested_placements.get(slot.slot_id, {})
		var parcel = _parcel_for_slot(slot, seed, requested_placement)
		if parcel == null:
			result.errors.append(_error("MISSING_COMPATIBLE_PARCEL", String(slot.slot_id)))
			continue
		var validation := _validate_slot(slot, parcel)
		if not validation.is_empty():
			result.errors.append(_error(validation, "%s/%s" % [plot.plot_id, slot.slot_id]))
			continue
		var population := _resolve_population(parcel, seed, slot_index, requested_placement, population_enabled)
		if population.has("error"):
			result.errors.append(_error(String(population.error), "%s/%s" % [plot.plot_id, slot.slot_id]))
			continue
		result.placements.append({"slot_id": slot.slot_id, "parcel_id": parcel.parcel_id, "parcel_revision": parcel.revision, "origin": slot.origin, "rotation": slot.rotation, "population": population.choices})
	return result

static func _resolve_population(parcel, seed: int, slot_index: int, requested: Dictionary, population_enabled: bool) -> Dictionary:
	var sockets: Array[Dictionary] = parcel.population_sockets()
	var regions: Array = parcel.population_regions()
	if sockets.is_empty():
		return {"choices": []}
	if not population_enabled:
		if not requested.is_empty() and not requested.get("population", []).is_empty():
			return {"error": "POPULATION_DISABLED_WITH_RECORDED_CHOICES"}
		return {"choices": []}
	if not requested.is_empty():
		if not requested.has("population"):
			return {"error": "MISSING_POPULATION_CHOICES"}
		var choices: Array = requested.population
		return {"choices": choices.duplicate(true)} if _population_valid(regions, sockets, choices) else {"error": "INVALID_POPULATION_CHOICES"}
	var choices: Array[Dictionary] = []
	for region_index in regions.size():
		var region = regions[region_index]
		var candidates := sockets.filter(func(socket): return socket.region_id == region.region_id)
		if candidates.size() < region.min_count or candidates.is_empty():
			return {"error": "INSUFFICIENT_POPULATION_SOCKETS"}
		var count: int = region.min_count + posmod(floori(seed / 2.0) + slot_index * 7 + region_index * 3, region.max_count - region.min_count + 1)
		var start := posmod(seed + slot_index + region_index, candidates.size())
		for offset in count:
			var socket: Dictionary = candidates[(start + offset) % candidates.size()]
			choices.append({"region_id": socket.region_id, "socket_id": socket.socket_id, "asset_id": socket.asset_id})
	return {"choices": choices}

static func _population_valid(regions: Array, sockets: Array[Dictionary], choices: Array) -> bool:
	var socket_by_id := {}
	for socket: Dictionary in sockets:
		socket_by_id[StringName(socket.socket_id)] = socket
	var counts := {}
	var used := {}
	for choice: Dictionary in choices:
		var socket_id := StringName(choice.get("socket_id", &""))
		if used.has(socket_id) or not socket_by_id.has(socket_id):
			return false
		var socket: Dictionary = socket_by_id[socket_id]
		if StringName(choice.get("region_id", &"")) != socket.region_id or String(choice.get("asset_id", "")) != socket.asset_id:
			return false
		used[socket_id] = true
		counts[socket.region_id] = int(counts.get(socket.region_id, 0)) + 1
	for region in regions:
		var count := int(counts.get(region.region_id, 0))
		if count < region.min_count or count > region.max_count:
			return false
	return true

static func is_valid(resolved: Dictionary) -> bool:
	return resolved.has("errors") and resolved.errors.is_empty()

static func _resolve_plot(seed: int, requested: Dictionary) -> Dictionary:
	return PlotCatalog.get_definition(StringName(requested.plot_id)) if requested.has("plot_id") else PlotCatalog.choose(seed)

static func _parcel_for_slot(slot: Dictionary, seed: int, requested: Dictionary):
	if not requested.is_empty():
		var parcel = ParcelCatalog.get_definition(StringName(requested.get("parcel_id", &"")))
		if parcel == null or parcel.revision != int(requested.get("parcel_revision", 0)):
			return null
		return parcel
	if slot.role == ParcelCatalog.LOADING_SERVICE:
		# Plot identity and content variation use different seed bits.
		return ParcelCatalog.choose(slot.role, slot.size, floori(seed / 2.0))
	var candidates := ParcelCatalog.candidates(slot.role, slot.size)
	return candidates[0] if not candidates.is_empty() else null

static func _validate_slot(slot: Dictionary, parcel) -> String:
	if parcel.role != slot.role or parcel.size != slot.size:
		return "INCOMPATIBLE_PARCEL_ROLE_OR_SIZE"
	if not parcel.allowed_rotations().has(int(slot.rotation)):
		return "UNSUPPORTED_PARCEL_ROTATION"
	var offered = parcel.connection()
	var required: Dictionary = slot.required_interface
	if offered == null or offered.kind != StringName(required.kind) or offered.width != int(required.width):
		return "INCOMPATIBLE_SERVICE_INTERFACE"
	if offered.world_cell(parcel.size, slot.origin, slot.rotation) != required.cell:
		return "MISALIGNED_SERVICE_INTERFACE"
	if offered.world_outward(slot.rotation) != required.outward:
		return "MISORIENTED_SERVICE_INTERFACE"
	return ""

static func _failure(seed: int, population_enabled: bool, code: String, detail: String) -> Dictionary:
	return {"schema": 1, "seed": seed, "population_enabled": population_enabled, "placements": [], "errors": [_error(code, detail)]}

static func _error(code: String, detail: String) -> Dictionary:
	return {"code": code, "detail": detail}
