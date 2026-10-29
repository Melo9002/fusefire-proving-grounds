class_name PlotCompositionSnapshot
extends RefCounted
## Exact registered chunk choices in the common accepted document. No reroll on load.
const VERSION := 1
static func failure(message: String, code := "INVALID_COMPOSITION") -> Dictionary:
	return {"ok":false,"errors":[{"code":code,"field":"composition","reference":"","message":message}]}
static func registered(revision: String, context: EnvironmentResolutionContext) -> Dictionary:
	if context.chunk_revision_cache.has(revision): return context.chunk_revision_cache[revision]
	var checked := context.chunk_library.inspect(revision,context)
	if checked.ok and (not checked.record.get("registered",false) or not context.chunk_library.review_error(checked.record,revision).is_empty()): checked = {"ok":false,"error":"Revision lacks registration or exact human review"}
	context.chunk_revision_cache[revision] = checked
	return checked
static func zones(plot: EnvironmentPlotSource) -> Array:
	var result: Array = []
	for requirement in plot.data.mission_requirements:
		if requirement.mission not in ["all",plot.data.active_mission]: continue
		var cells: Array = requirement.cells.duplicate(true)
		cells.sort_custom(func(a,b): return Vector2i(a[0],a[1]) < Vector2i(b[0],b[1]))
		result.append({"zone_id":requirement.id,"kind":0 if requirement.kind == "deployment" else 1,"faction":int(requirement.faction),"cells":cells.slice(0,int(requirement.capacity)).map(func(c): return [int(c[0]),0,int(c[1])])})
	result.sort_custom(func(a,b): return a.zone_id < b.zone_id)
	return result
static func reservations(plot: EnvironmentPlotSource) -> Array:
	var result: Array = []
	for record in plot.data.reservations:
		var saved: Dictionary = record.duplicate(true)
		saved["reservation_id"] = record.id; saved["owner_ref"] = "plot:"+plot.data.plot_id
		result.append(saved)
	return result
static func prepare(document: BattlefieldLayoutDocument, context: EnvironmentResolutionContext) -> Dictionary:
	if not document.provenance.has("composition"): return {"ok":true,"errors":[],"layout":EnvironmentModuleLayout.new(),"explicit":{},"resolved":[],"bounds":[]}
	if not document.spatial_layout.get("placements") is Array or not document.spatial_layout.get("reservations") is Array or not document.mission_context.get("zones") is Array: return failure("Malformed composed placements, reservations or mission zones")
	if document.spatial_layout.get("resolution_version") != 2: return failure("Chunk snapshots require resolution contract 2")
	var info = document.provenance.composition
	if not info is Dictionary or info.get("version") != VERSION or not info.get("plot") is Dictionary or not info.get("choices") is Array: return failure("Malformed/unsupported composition snapshot")
	if info.get("implementation") != implementation_signature(): return failure("Composition compiler changed; regenerate under the current contract","STALE_COMPOSITION_COMPILER")
	if not document.spatial_layout.get("placements",[]).is_empty() and not document.provenance.has("population"): return failure("Unrecorded additions: composed chunks accept only declared population")
	var key := ChunkPublicationCompiler.canonical([info,document.mission_context,document.spatial_layout])
	if context.composition_cache.has(key): return context.composition_cache[key]
	var plot := EnvironmentPlotSource.new(); plot.data = info.plot.duplicate(true)
	var errors := EnvironmentPlotSource.source_errors(plot.data)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	if document.map_size() != Vector2i(plot.data.map_size[0],plot.data.map_size[1]): return failure("Snapshot map boundary differs from plot")
	if ChunkPublicationCompiler.canonical(document.mission_context.get("zones",[])) != ChunkPublicationCompiler.canonical(zones(plot)): return failure("Bound mission differs from active plot requirements")
	if reservation_signature(document.spatial_layout.get("reservations",[])) != reservation_signature(reservations(plot)): return failure("Plot reservations changed")
	var entries := {}; var selected := {}; var seen := {}
	for choice in info.choices:
		if not choice is Dictionary or not choice.get("id") is String or not choice.get("chunk_id") is String or not choice.get("revision") is String or not EnvironmentPlotSource.Chunk._vector(choice.get("origin"),2) or not EnvironmentPlotSource.quarter(choice.get("rotation")): return failure("Malformed selected chunk record")
		if seen.has(choice.id): return failure("Duplicate selected chunk identity: "+choice.id)
		seen[choice.id] = true
		var checked := registered(choice.revision,context)
		if not checked.ok: return failure(choice.id+": "+checked.error,"CHUNK_REVISION_UNAVAILABLE")
		if checked.source.data.chunk_id != choice.chunk_id: return failure("Revision does not identify "+choice.chunk_id)
		if entries.has(choice.chunk_id) and entries[choice.chunk_id].revision != choice.revision: return failure("Pilot uses one exact revision per chunk ID")
		entries[choice.chunk_id] = {"source":checked.source,"compiled":checked.compiled,"eligible":true,"revision":choice.revision,"ambiguous":false}
		selected[choice.id] = choice
	var assessment := PlotFeasibility.assess(plot,entries)
	if not assessment.ok: return assessment
	var known := {}
	for street in plot.data.fixed_streets:
		known[street.id] = true
		if not selected.has(street.id): return failure("Required fixed street missing: "+street.id)
		var choice: Dictionary = selected[street.id]
		if choice.chunk_id != street.chunk_id or choice.revision != street.revision or choice.rotation != street.rotation or ChunkPublicationCompiler.canonical(choice.origin) != ChunkPublicationCompiler.canonical(street.origin): return failure("Fixed street differs from pinned plot: "+street.id)
	for slot in plot.data.slots:
		known[slot.id] = true
		if not selected.has(slot.id):
			if slot.required: return failure("Required slot missing: "+slot.id)
			continue
		var choice: Dictionary = selected[slot.id]
		if not assessment.candidates[slot.id].any(func(c): return c.chunk_id == choice.chunk_id and c.revision == choice.revision and c.rotation == choice.rotation and ChunkPublicationCompiler.canonical(c.origin) == ChunkPublicationCompiler.canonical(choice.origin)): return failure("Selected chunk fails actual slot/port geometry: "+slot.id)
	for id in selected:
		if not known.has(id): return failure("Unknown selected slot/street: "+id)
	var prepared := {"ok":true,"errors":[],"layout":EnvironmentModuleLayout.new(),"explicit":{"surfaces":[],"effects":[],"links":[]},"resolved":[],"bounds":[],"plan":assessment.plan,"plot":plot}
	var ids := selected.keys(); ids.sort()
	for id in ids:
		var choice: Dictionary = selected[id]; var entry: Dictionary = entries[choice.chunk_id]
		append_chunk(prepared,choice,entry)
	var rules_error := TacticalPopulationPass.rules_error(plot.population_rules(),document.map_size(),context.catalog)
	if not rules_error.is_empty(): return failure(rules_error)
	# Population regions are plot-owned open space, not implicit permission to edit a chunk.
	for region in plot.population_rules().regions:
		for bounds in prepared.bounds:
			if PlotFeasibility.rect(region.bounds).intersects(bounds): return failure("Population region %s overlaps immutable chunk space" % region.id)
	context.composition_cache[key] = prepared
	return prepared
static func point(shape: EnvironmentModuleDefinition, origin: Vector2i, rotation: int, encoded: Array) -> Array:
	var at := origin+shape.rotate_cell(Vector2i(encoded[0],encoded[2]),rotation)
	return [at.x,int(encoded[1]),at.y]
static func append_chunk(output: Dictionary, choice: Dictionary, entry: Dictionary) -> void:
	var source: EnvironmentChunkSource = entry.source
	var shape := PlotFeasibility.shape(source); var origin := Vector2i(choice.origin[0],choice.origin[1]); var turn := int(choice.rotation)
	output.bounds.append(Rect2i(origin,PlotFeasibility.extent(source,turn)))
	for category in ["surfaces","effects","links"]:
		for spec in source.data.tactical[category]:
			var world: Dictionary = spec.duplicate(true)
			for field in (["from","to"] if category == "links" else ["cell"]): world[field] = point(shape,origin,turn,spec[field])
			output.explicit[category].append(world)
	for record in entry.compiled.resolved:
		var local: EnvironmentModulePlacement = record.placement
		var world := local.copy(); world.placement_id = leaf_identity(choice.id,local.placement_id); world.rotation = posmod(local.rotation+turn,4)
		var resolved: Dictionary = record.duplicate()
		if record.definition != null:
			var definition: EnvironmentModuleDefinition = record.definition
			world.origin = origin+shape.rotate_cell(local.origin+definition.rotate_cell(Vector2i.ZERO,local.rotation),turn)-definition.rotate_cell(Vector2i.ZERO,world.rotation)
			if local.placement_id in source.data.tactical.components: output.layout.placements.append(world)
		else:
			world.origin = origin+shape.rotate_cell(local.origin,turn)
			resolved["local_placement"] = local.copy()
			var anchor := origin+shape.rotate_cell(Vector2i.ZERO,turn)
			resolved["chunk_transform"] = Transform3D(Basis(Vector3.UP,-turn*PI*0.5),Vector3(anchor.x,0,anchor.y))
		resolved.placement = world
		output.resolved.append(resolved)
static func verify_map(document: BattlefieldLayoutDocument, data: MapData, prepared: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if not document.provenance.has("composition"): return errors
	for reservation in prepared.plot.data.reservations:
		for encoded in reservation.cells:
			var cell := data.get_cell(Vector3i(encoded[0],0,encoded[1]))
			if cell == null or not cell.walkable or not cell.can_stop: errors.append_array(failure("Required route %s blocked at %s" % [reservation.id,encoded]).errors)
	if document.provenance.has("population"):
		var population = document.provenance.population
		if not population is Dictionary or not population.get("rules") is Dictionary or ChunkPublicationCompiler.canonical(population.rules) != ChunkPublicationCompiler.canonical(prepared.plot.population_rules()): errors.append_array(failure("Population rules differ from allowed plot regions").errors)
	return errors

static func reservation_signature(records: Array) -> String:
	var normalized: Array = records.duplicate(true)
	for record in normalized:
		if record is Dictionary: record.erase("validation_state")
	return ChunkPublicationCompiler.canonical(normalized)

static func implementation_signature() -> String:
	var hashes: Array = []
	for path in ["res://systems/generation/plot_composition_snapshot.gd","res://systems/generation/plot_feasibility.gd","res://systems/generation/battlefield_layout_document_compiler.gd","res://systems/generation/tactical_population_pass.gd"]: hashes.append(FileAccess.get_sha256(path))
	return ChunkPublicationCompiler.canonical(hashes).sha256_text()

static func leaf_identity(owner: String, local: String) -> String:
	return "chunk:%s/%s" % [owner.uri_encode(),local.uri_encode()]
