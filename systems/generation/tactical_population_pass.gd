class_name TacticalPopulationPass
extends RefCounted
## Strategy A: bounded additions over an immutable accepted authored environment.
const VERSION := 1
const Spatial = preload("res://systems/generation/environment_spatial_queries.gd")
const Ledger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")
const Policy = preload("res://systems/generation/cover_placement_policy.gd")

static func canonical(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)
static func fail(message: String, code := "INVALID_POPULATION") -> Dictionary:
	return {"ok": false, "data": null, "document": null, "errors": [{"code": code, "field": "population", "reference": "", "message": message}]}

static func rules_error(rules: Dictionary, size: Vector2i, catalog: Dictionary) -> String:
	if rules.get("version") != VERSION or not rules.get("regions") is Array or not rules.get("routes") is Array: return "Unsupported or malformed population rules"
	if rules.regions.size() > 32 or rules.routes.size() > 64: return "Population exceeds bounded region/route budget"
	var ids := {}
	for region in rules.regions:
		if not region is Dictionary: return "Region must be an object"
		if not region.get("id") is String or region.id.is_empty() or ids.has(region.id): return "Region identity missing or duplicated"
		ids[region.id] = true
		if not region.get("bounds") is Array or region.bounds.size() != 4: return "Region requires rectangular bounds"
		for n in region.bounds:
			if not integer(n): return "Region bounds must be integers"
		var rect := Rect2i(region.bounds[0], region.bounds[1], region.bounds[2], region.bounds[3])
		if rect.size.x <= 0 or rect.size.y <= 0 or not Rect2i(Vector2i.ZERO, size).encloses(rect): return "Region outside battlefield"
		if not integer(region.get("elevation")) or region.elevation < 0: return "Region requires supported integer elevation"
		if not integer(region.get("count")) or region.count < 0 or region.count > 16: return "Region count outside bounded budget"
		if not region.get("anchors") is Array or region.anchors.is_empty() or region.anchors.size() > 64: return "Region needs 1..64 authored anchors"
		for at in region.anchors:
			if not at is Array or at.size() != 2 or not integer(at[0]) or not integer(at[1]) or not rect.has_point(Vector2i(at[0], at[1])): return "Anchor outside declared region"
		if not region.get("choices") is Array or region.choices.is_empty() or region.choices.size() > 16: return "Region needs bounded compatible choices"
		for choice in region.choices:
			if not choice is Dictionary or not catalog.has(StringName(choice.get("component_id", ""))): return "Unknown population component"
			var definition: EnvironmentModuleDefinition = catalog[StringName(choice.component_id)]
			if definition.placement_layer == EnvironmentModuleDefinition.PlacementLayer.GROUND or not definition.elevated_surfaces.is_empty(): return "Population cannot replace terrain or construct floors"
			if not integer(choice.get("rotation")) or int(choice.rotation) not in definition.allowed_rotations or not integer(choice.get("variation")) or choice.variation < 0: return "Invalid population transform/variant"
	for route in rules.routes:
		if not route is Array or route.is_empty() or route.size() > 4096: return "Route must list protected cells"
		var previous := Vector3i.ZERO
		for i in route.size():
			var encoded = route[i]
			if not encoded is Array or encoded.size() != 3: return "Invalid route cell"
			for n in encoded:
				if not integer(n): return "Route cell must be integer"
			var at := point(encoded)
			if at.y < 0 or not Rect2i(Vector2i.ZERO, size).has_point(Vector2i(at.x, at.z)): return "Route outside battlefield"
			if i > 0 and (at - previous).length_squared() != 1: return "Pilot routes must be contiguous cardinal cells"
			previous = at
	return ""
static func integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
static func point(value: Array) -> Vector3i: return Vector3i(value[0], value[1], value[2])

static func populate(base: BattlefieldLayoutDocument, rules: Dictionary, population_seed: int, context: EnvironmentResolutionContext = null) -> Dictionary:
	if context == null: context = EnvironmentResolutionContext.new()
	if base == null: return fail("Missing authored base")
	if base.provenance.has("population"): return fail("Population requires an unpopulated base; reload the authored source")
	var error := rules_error(rules, base.map_size(), context.catalog)
	if not error.is_empty(): return fail(error)
	if base.mission_context.get("status") != "preserved": return fail("Bind mission space before population")
	var baseline := BattlefieldLayoutDocumentCompiler.compile(base, 1.0, 5, context)
	if not baseline.ok: return baseline
	if not baseline.repairs.is_empty(): return fail("Base deployment requires repair; correct the authored source first")
	var accepted: BattlefieldLayoutDocument = BattlefieldLayoutDocument.from_dictionary(base.to_dictionary())
	var current: MapData = baseline.data
	var layout := base.to_module_layout(context.catalog)
	var reservations := Ledger.from_map(current)
	reservations.reservations.append_array(Ledger.decoded_records(base.spatial_layout.get("reservations", [])))
	for i in rules.routes.size():
		for encoded in rules.routes[i]:
			var at := point(encoded)
			var cell := current.get_cell(at)
			if cell == null or not cell.walkable or not cell.can_stop: return fail("Authored protected route is not usable at %s" % at)
			# Deliberately whole-column: keep access/headroom safe from all optional population.
			reservations.reservations.append({"reservation_id": "route_%d" % i, "owner_ref": "population", "role": Ledger.PEDESTRIAN_ACCESS, "scope": Ledger.WHOLE_COLUMN, "cells": [Vector2i(at.x, at.z)]})
	var rng := RandomNumberGenerator.new()
	rng.seed = population_seed
	var regions: Array = rules.regions.duplicate(true)
	regions.sort_custom(func(a, b): return a.id < b.id)
	var choices: Array = []
	var diagnostics: Array = []
	var attempts := 0
	for region in regions:
		var candidates: Array = []
		for anchor in region.anchors:
			for option in region.choices: candidates.append({"origin": anchor, "option": option})
		for i in range(candidates.size() - 1, 0, -1):
			var other := rng.randi_range(0, i)
			var held = candidates[i]
			candidates[i] = candidates[other]
			candidates[other] = held
		var placed := 0
		for candidate in candidates:
			if placed >= int(region.count): break
			attempts += 1
			if attempts > 512: return fail("Population exhausted its 512-attempt operation budget", "POPULATION_EXHAUSTED")
			var option: Dictionary = candidate.option
			var instance := EnvironmentModulePlacement.new(StringName(option.component_id), Vector2i(candidate.origin[0], candidate.origin[1]), int(option.rotation), int(option.variation), int(region.elevation), "population_%s_%02d" % [region.id, placed])
			if layout.placements.any(func(existing): return existing.placement_id == instance.placement_id): return fail("Population identity collides with fixed content")
			var definition: EnvironmentModuleDefinition = context.catalog[instance.component_id]
			var reason := candidate_error(definition, instance, region, layout, current, reservations)
			if not reason.is_empty():
				diagnostics.append({"region": region.id, "origin": candidate.origin, "reason": reason})
				continue
			var trial_layout := accepted.to_module_layout(context.catalog)
			if not trial_layout.try_add(definition, instance, base.map_size()): continue
			var trial := BattlefieldLayoutDocument.from_dictionary(accepted.to_dictionary())
			var edits := trial.apply_edited_layout(trial_layout, context)
			if not edits.is_empty(): continue
			# Editing metadata must not alter the authored ownership/access contracts.
			trial.relationships.assign(base.relationships.duplicate(true))
			for record in trial.spatial_layout.placements:
				if str(record.placement_id).begins_with("population_") and not str(record.assembly_ref).is_empty(): trial.relationships.append({"relationship_id": "assembly_" + record.placement_id, "kind": "assembly_instance", "subject_ref": record.placement_id, "object_ref": "assembly:" + record.assembly_ref, "required": true})
			trial.spatial_layout["reservations"] = base.spatial_layout.get("reservations", []).duplicate(true)
			trial.spatial_layout["parcels"] = base.spatial_layout.get("parcels", []).duplicate(true)
			trial.mission_context = base.mission_context.duplicate(true)
			# The writer is transactional; use it for local candidate effects, then run
			# graph/mission compilation once on the completed document below.
			var addition := EnvironmentModuleLayout.new(&"population_candidate")
			addition.placements.append(instance)
			var contribution_errors := EnvironmentModuleMapWriter.apply(current, addition, context.catalog, 1.0)
			if not contribution_errors.is_empty():
				diagnostics.append({"region": region.id, "origin": candidate.origin, "reason": "shared writer rejected candidate", "errors": contribution_errors})
				continue
			accepted = trial
			layout = trial_layout
			choices.append({"region": region.id, "placement": instance.to_record()})
			placed += 1
		if placed < int(region.count): return fail("Region %s exhausted %d candidates: accepted %d of %d required additions" % [region.id, candidates.size(), placed, region.count], "POPULATION_EXHAUSTED")
	accepted.provenance = base.provenance.duplicate(true)
	accepted.provenance["origin"] = "edited"
	accepted.provenance["source_origin"] = "authored"
	accepted.provenance["generator_id"] = "bounded_tactical_population"
	accepted.provenance["has_generation_seed"] = true
	accepted.provenance["generation_seed"] = population_seed
	accepted.provenance["population"] = {"version": VERSION, "seed": population_seed, "base_signature": base.signature(), "base_placements": base.spatial_layout.placements.duplicate(true), "base_mission": base.mission_context.duplicate(true), "base_relationships": base.relationships.duplicate(true), "base_reservations": base.spatial_layout.get("reservations", []).duplicate(true), "base_parcels": base.spatial_layout.get("parcels", []).duplicate(true), "rules": rules.duplicate(true), "choices": choices, "attempts": attempts}
	var result := BattlefieldLayoutDocumentCompiler.compile(accepted, 1.0, 5, context)
	result["diagnostics"] = diagnostics
	return result

static func candidate_error(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, region: Dictionary, layout: EnvironmentModuleLayout, data: MapData, reservations: EnvironmentSpatialReservationLedger) -> String:
	var rect := Rect2i(region.bounds[0], region.bounds[1], region.bounds[2], region.bounds[3])
	var geometry := Spatial.record(definition, placement)
	for cell in geometry.cells + geometry.clearance:
		if not rect.has_point(cell): return "Footprint or clearance leaves declared region"
	var bounds: AABB = geometry.visual
	if bounds.size != Vector3.ZERO and (bounds.position.x < rect.position.x - 0.5 or bounds.position.z < rect.position.y - 0.5 or bounds.end.x > rect.end.x - 0.5 or bounds.end.z > rect.end.y - 0.5): return "Visual envelope leaves declared region"
	var error := layout.placement_error(definition, placement, data.map_size)
	if not error.is_empty(): return error
	var reserved := reservations.placement_allowed(definition, placement, layout)
	if not reserved.ok: return reserved.message
	for cell in geometry.cells:
		if not Policy.available(data, Vector3i(cell.x, placement.elevation, cell.y), true): return "Unsupported, occupied or adjacent to full cover"
	return ""

## Rechecked on load/play/replay, without rerunning random selection.
static func verify(document: BattlefieldLayoutDocument, data: MapData, context: EnvironmentResolutionContext) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if not document.provenance.has("population"): return errors
	var info = document.provenance.population
	if not info is Dictionary or info.get("version") != VERSION or not info.get("rules") is Dictionary or not info.get("base_placements") is Array or not info.get("choices") is Array or not info.get("base_mission") is Dictionary or not info.get("base_relationships") is Array or not info.get("base_reservations") is Array or not info.get("base_parcels") is Array:
		errors.assign(fail("Malformed population snapshot").errors)
		return errors
	var error := rules_error(info.rules, document.map_size(), context.catalog)
	if not error.is_empty():
		errors.assign(fail(error).errors)
		return errors
	var fixed := {}
	for record in info.base_placements:
		if not record is Dictionary or not record.get("placement_id") is String or fixed.has(record.placement_id):
			errors.assign(fail("Malformed fixed-content snapshot").errors)
			return errors
		fixed[record.placement_id] = record
	for relation in info.base_relationships:
		if not document.relationships.any(func(r): return canonical(r) == canonical(relation)): errors.append_array(fail("Immutable base relationship changed").errors)
	if canonical(document.spatial_layout.get("reservations", [])) != canonical(info.base_reservations) or canonical(document.spatial_layout.get("parcels", [])) != canonical(info.base_parcels): errors.append_array(fail("Immutable spatial contracts changed").errors)
	var additions := {}
	for choice in info.choices:
		if not choice is Dictionary or not choice.get("placement") is Dictionary or not choice.get("region") is String:
			errors.assign(fail("Malformed accepted population choice").errors)
			return errors
		var id := str(choice.placement.get("placement_id", ""))
		if id.is_empty() or additions.has(id) or fixed.has(id):
			errors.assign(fail("Invalid accepted choice identity").errors)
			return errors
		additions[id] = choice
	var counts := {}
	var mission := Ledger.from_map(data)
	for route in info.rules.routes:
		for encoded in route:
			var at := point(encoded)
			mission.reservations.append({"reservation_id": "route", "owner_ref": "population", "role": Ledger.PEDESTRIAN_ACCESS, "scope": Ledger.WHOLE_COLUMN, "cells": [Vector2i(at.x, at.z)]})
	for record in document.spatial_layout.placements:
		if fixed.has(record.placement_id):
			if canonical(record) != canonical(fixed[record.placement_id]): errors.append_array(fail("Immutable base placement changed").errors)
			fixed.erase(record.placement_id)
		elif additions.has(record.placement_id):
			var choice: Dictionary = additions[record.placement_id]
			var placement := EnvironmentModulePlacement.from_record(record)
			var found: Array = info.rules.regions.filter(func(r): return r.id == choice.region)
			if canonical(placement.to_record()) != canonical(choice.placement) or found.size() != 1:
				errors.append_array(fail("Accepted choice changed or region missing").errors)
			else:
				var region: Dictionary = found[0]
				counts[choice.region] = int(counts.get(choice.region, 0)) + 1
				var allowed: bool = region.choices.any(func(o): return o.component_id == record.component_id and int(o.rotation) == placement.rotation and int(o.variation) == placement.variation)
				if not allowed or int(region.elevation) != placement.elevation or not region.anchors.any(func(a): return Vector2i(a[0], a[1]) == placement.origin): errors.append_array(fail("Choice not allowed by authored region").errors)
				var definition: EnvironmentModuleDefinition = context.catalog[placement.component_id]
				var rect := Rect2i(region.bounds[0], region.bounds[1], region.bounds[2], region.bounds[3])
				for cell in Spatial.record(definition, placement).cells + Spatial.record(definition, placement).clearance:
					if not rect.has_point(cell): errors.append_array(fail("Choice outside region").errors)
				if not mission.placement_allowed(definition, placement, null).ok: errors.append_array(fail("Population infringes mission reservation").errors)
			additions.erase(record.placement_id)
		else: errors.append_array(fail("Unrecorded population placement").errors)
	if not fixed.is_empty() or not additions.is_empty(): errors.append_array(fail("Required fixed/accepted placement missing").errors)
	if canonical(document.mission_context.get("zones", [])) != canonical(info.base_mission.get("zones", [])): errors.append_array(fail("Immutable mission space changed").errors)
	for region in info.rules.regions:
		if int(counts.get(region.id, 0)) != int(region.count): errors.append_array(fail("Population count changed").errors)
	for route in info.rules.routes:
		for encoded in route:
			var cell := data.get_cell(point(encoded))
			if cell == null or not cell.walkable or not cell.can_stop: errors.append_array(fail("Protected route no longer usable at %s" % str(encoded)).errors)
	return errors
