class_name RefineryPlotResolver
extends RefCounted
## Resolves one bounded authored plot before battle activation. The returned
## placements are durable choices; replay must not rely on the seed alone.

const PlotCatalog = preload("res://systems/generation/refinery_plot_catalog.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const SlotContract = preload("res://systems/generation/parcel_slot_contract.gd")
## Bump if the shared authored compilation or deployment repair changes
## the tactical result for an unchanged exact manifest.
const COMPILER_REVISION := 2
const LEGACY_COMPILER_REVISION := 1

static func resolve(map_seed: int, population_enabled: bool = true, requested: Dictionary = {}, catalog = PlotCatalog) -> Dictionary:
	var plot: Dictionary = catalog.get_definition(StringName(requested.plot_id)) if requested.has("plot_id") else catalog.choose(map_seed)
	if plot.is_empty():
		return _failure(map_seed, population_enabled, "UNKNOWN_PLOT", String(requested.get("plot_id", "")))
	var result := {"schema": 1, "compiler_revision": COMPILER_REVISION, "plot_id": plot.plot_id, "plot_revision": plot.revision, "map_size": plot.map_size, "seed": map_seed, "population_enabled": population_enabled, "placements": [], "errors": []}
	if requested.has("plot_id"):
		result.seed = int(requested.get("seed", map_seed))
		if int(requested.get("schema", 0)) != 1 or requested.get("map_size") != plot.map_size:
			result.errors.append(_error("UNSUPPORTED_MANIFEST", String(plot.plot_id)))
			return result
		var revision: Variant = requested.get("compiler_revision", LEGACY_COMPILER_REVISION)
		if not (revision is int or revision is float) or revision not in [LEGACY_COMPILER_REVISION, COMPILER_REVISION]:
			result.errors.append(_error("UNSUPPORTED_COMPILER_REVISION", "%s requires %s. This build supports revisions %d and %d." % [plot.plot_id, revision, LEGACY_COMPILER_REVISION, COMPILER_REVISION]))
			return result
		result.compiler_revision = int(revision)
	if int(requested.get("plot_revision", plot.revision)) != int(plot.revision):
		result.errors.append(_error("STALE_PLOT_REVISION", String(plot.plot_id)))
		return result
	var footprint_error := SlotContract.validate_plot_footprints(plot)
	if not footprint_error.is_empty():
		result.errors.append(footprint_error)
		return result
	var requested_placements: Dictionary = {}
	for placement in requested.get("placements", []):
		requested_placements[StringName(placement.get("slot_id", &""))] = placement
	if requested.has("plot_id") and (not requested.has("placements") or requested_placements.size() != plot.slots.size() or requested.get("placements", []).size() != plot.slots.size()):
		result.errors.append(_error("INVALID_RECORDED_SLOTS", String(plot.plot_id)))
		return result
	var slots: Array = plot.slots
	if requested.has("plot_id"):
		# Preserve compile order as well as choices for an exact replay.
		var slots_by_id := {}
		for slot: Dictionary in slots:
			slots_by_id[slot.slot_id] = slot
		slots = []
		for placement: Dictionary in requested.placements:
			var slot_id := StringName(placement.get("slot_id", &""))
			if not slots_by_id.has(slot_id):
				result.errors.append(_error("INVALID_RECORDED_SLOTS", "%s/%s" % [plot.plot_id, slot_id]))
				return result
			slots.append(slots_by_id[slot_id])
	for slot: Dictionary in slots:
		var requested_placement: Dictionary = requested_placements.get(slot.slot_id, {})
		if requested.has("plot_id") and (requested_placement.is_empty() or requested_placement.get("origin") != slot.origin or requested_placement.get("rotation") != slot.rotation):
			result.errors.append(_error("INVALID_RECORDED_TRANSFORM", String(slot.slot_id)))
			continue
		var parcel = _parcel_for_slot(slot, map_seed, requested_placement)
		if parcel == null:
			result.errors.append(_error("MISSING_COMPATIBLE_PARCEL", String(slot.slot_id)))
			continue
		var parcel_errors: PackedStringArray = parcel.validate()
		if not parcel_errors.is_empty():
			result.errors.append(_error("INVALID_PARCEL_CONTRACT", "%s: %s" % [slot.slot_id, "; ".join(parcel_errors)]))
			continue
		var offered: ParcelConnection = parcel.connection()
		var validation := SlotContract.validate(slot, parcel, offered)
		if not validation.is_empty():
			result.errors.append(_error(validation, "%s/%s" % [plot.plot_id, slot.slot_id]))
			continue
		var approach_error := SlotContract.validate_approach(plot, slot, offered)
		if not approach_error.is_empty():
			result.errors.append(approach_error)
			continue
		var population := _resolve_population(parcel, map_seed, requested_placement, population_enabled, "%s/%s" % [plot.plot_id, slot.slot_id])
		if population.has("error"):
			result.errors.append(_error(String(population.error), "%s/%s" % [plot.plot_id, slot.slot_id]))
			continue
		result.placements.append({"slot_id": slot.slot_id, "parcel_id": parcel.parcel_id, "parcel_revision": parcel.revision, "origin": slot.origin, "rotation": slot.rotation, "population": population.choices})
	return result

static func _resolve_population(parcel, map_seed: int, requested: Dictionary, population_enabled: bool, instance_id: String) -> Dictionary:
	var sockets: Array[Dictionary] = parcel.population_sockets()
	var regions: Array = parcel.population_regions()
	if sockets.is_empty():
		if not requested.get("population", []).is_empty():
			return {"error": "INVALID_POPULATION_CHOICES"}
		return {"choices": []}
	if not population_enabled:
		if not requested.is_empty() and not requested.get("population", []).is_empty():
			return {"error": "POPULATION_DISABLED_WITH_RECORDED_CHOICES"}
		return {"choices": []}
	if not requested.is_empty():
		if not requested.has("population"):
			return {"error": "MISSING_POPULATION_CHOICES"}
		var recorded_choices: Array = requested.population
		return {"choices": recorded_choices.duplicate(true)} if _population_valid(regions, sockets, recorded_choices) else {"error": "INVALID_POPULATION_CHOICES"}
	var choices: Array[Dictionary] = []
	regions.sort_custom(func(a, b): return String(a.region_id) < String(b.region_id))
	for region in regions:
		var candidates := sockets.filter(func(socket): return socket.region_id == region.region_id)
		if candidates.size() < region.min_count or candidates.is_empty():
			return {"error": "INSUFFICIENT_POPULATION_SOCKETS"}
		var maximum := mini(region.max_count, candidates.size())
		var scope := [map_seed, instance_id, String(parcel.parcel_id), String(region.region_id)]
		var count: int = region.min_count + _stable_roll(scope + ["population_count_v1"]) % (maximum - region.min_count + 1)
		var ranks := {}
		for candidate in candidates:
			ranks[candidate.socket_id] = _stable_roll(scope + [String(candidate.socket_id), "population_socket_v1"])
		candidates.sort_custom(func(a, b):
			if ranks[a.socket_id] == ranks[b.socket_id]:
				return String(a.socket_id) < String(b.socket_id)
			return ranks[a.socket_id] < ranks[b.socket_id])
		for index in count:
			var socket: Dictionary = candidates[index]
			var choice := {"region_id": socket.region_id, "socket_id": socket.socket_id, "asset_id": socket.asset_id}
			if socket.has("asset_options"):
				var options: PackedStringArray = socket.asset_options
				choice.asset_id = options[_stable_roll(scope + [String(socket.socket_id), "painted_parking_asset_v1"]) % options.size()]
			var turns: PackedInt32Array = socket.allowed_yaw_turns
			if turns.size() > 1:
				var heading := _stable_roll(scope + [String(socket.socket_id), "parking_heading_v1"]) % turns.size()
				choice.yaw_turns = turns[heading]
			choices.append(choice)
	return {"choices": choices}

static func _stable_roll(key: Array) -> int:
	return JSON.stringify(key).sha256_text().substr(0, 8).hex_to_int()

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
		if StringName(choice.get("region_id", &"")) != socket.region_id or String(choice.get("asset_id", "")) not in socket.get("asset_options", [socket.asset_id]):
			return false
		var yaw: Variant = choice.get("yaw_turns", 0)
		if not (yaw is int or yaw is float) or float(yaw) != int(yaw) or not socket.allowed_yaw_turns.has(int(yaw)):
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

static func _resolve_plot(map_seed: int, requested: Dictionary) -> Dictionary:
	return PlotCatalog.get_definition(StringName(requested.plot_id)) if requested.has("plot_id") else PlotCatalog.choose(map_seed)

static func _parcel_for_slot(slot: Dictionary, map_seed: int, requested: Dictionary):
	if not requested.is_empty():
		var parcel = ParcelCatalog.get_definition(StringName(requested.get("parcel_id", &"")))
		if parcel == null or parcel.revision != int(requested.get("parcel_revision", 0)):
			return null
		return parcel
	if slot.has("preferred_parcel_id"):
		return ParcelCatalog.get_definition(slot.preferred_parcel_id)
	if slot.role == ParcelCatalog.LOADING_SERVICE:
		# Plot identity and content variation use different seed bits.
		return ParcelCatalog.choose(slot.role, slot.size, floori(map_seed / 2.0))
	var candidates := ParcelCatalog.candidates(slot.role, slot.size)
	return candidates[0] if not candidates.is_empty() else null

static func _failure(map_seed: int, population_enabled: bool, code: String, detail: String) -> Dictionary:
	return {"schema": 1, "seed": map_seed, "population_enabled": population_enabled, "placements": [], "errors": [_error(code, detail)]}

static func _error(code: String, detail: String) -> Dictionary:
	return {"code": code, "detail": detail}
