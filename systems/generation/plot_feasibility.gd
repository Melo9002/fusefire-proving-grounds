class_name PlotFeasibility
extends RefCounted
## Authoring feasibility only. T10 chooses registered revisions and solves combinations.
const Compiler = preload("res://systems/generation/chunk_publication_compiler.gd")
static func library_catalog() -> Dictionary:
	var context := EnvironmentResolutionContext.new()
	var registered := {}
	for entry in ChunkPublicationLibrary.new().eligible(context): registered[entry.id] = entry
	var entries := {}
	var errors: Array[Dictionary] = []
	for directory in ["res://content/chunks/industrial", ChunkSourceStore.DEFAULT_DIRECTORY]:
		if not DirAccess.dir_exists_absolute(directory): continue
		for file in DirAccess.get_files_at(directory):
			if not file.ends_with(".json"): continue
			var loaded := ChunkSourceStore.load_named(directory,file)
			if not loaded.ok: errors.append(EnvironmentPlotSource.issue("INVALID_CHUNK_SOURCE",file,loaded.error)); continue
			var source: EnvironmentChunkSource = loaded.source
			var id: String = source.data.chunk_id
			if entries.has(id):
				entries[id].ambiguous = true
				errors.append(EnvironmentPlotSource.issue("AMBIGUOUS_CHUNK_ID",id,"Multiple sources claim this chunk ID"))
				continue
			var compiled := Compiler.compile(source,context)
			entries[id] = {"source":source,"compiled":compiled,"eligible":registered.has(id) and compiled.ok and compiled.revision == registered[id].revision,"revision":str(registered[id].revision) if registered.has(id) else "","ambiguous":false}
	# Registered sources outside the pilot/draft folders remain visible through the same index.
	for id in registered:
		if not entries.has(id):
			var entry: Dictionary = registered[id]
			entries[id] = {"source":entry.source,"compiled":Compiler.compile(entry.source,context),"eligible":true,"revision":entry.revision,"ambiguous":false}
	return {"entries":entries,"errors":errors}
static func shape(source: EnvironmentChunkSource) -> EnvironmentModuleDefinition:
	return EnvironmentModuleDefinition.new(&"chunk_bounds",&"plot",Vector2i(source.data.bounds[0],source.data.bounds[1]))
static func extent(source: EnvironmentChunkSource, rotation: int) -> Vector2i:
	var size := Vector2i(source.data.bounds[0],source.data.bounds[1])
	return Vector2i(size.y,size.x) if rotation % 2 else size
static func ports(source: EnvironmentChunkSource, origin: Vector2i, rotation: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var transform := shape(source)
	for local in source.data.ports:
		var port: Dictionary = local.duplicate(true)
		port.cells = []
		for cell in local.cells:
			var at := origin + transform.rotate_cell(Vector2i(cell[0],cell[1]),rotation)
			port.cells.append([at.x,at.y])
		var normal := transform.rotate_direction(Vector2i(local.normal[0],local.normal[1]),rotation)
		port.normal = [normal.x,normal.y]
		result.append(port)
	return result
static func walkable_cells(entry: Dictionary, origin: Vector2i, rotation: int) -> Dictionary:
	var result := {}
	var transform := shape(entry.source)
	for at: Vector3i in entry.compiled.data.cells:
		var cell: MapCellData = entry.compiled.data.cells[at]
		if at.y == 0 and cell.walkable and cell.can_stop: result[origin + transform.rotate_cell(Vector2i(at.x,at.z),rotation)] = true
	return result
static func available(entry: Dictionary) -> bool: return not entry.get("ambiguous",false) and entry.compiled.ok
static func rect(value: Array) -> Rect2i: return Rect2i(value[0],value[1],value[2],value[3])
static func add(errors: Array[Dictionary], code: String, field: String, message: String) -> void: errors.append(EnvironmentPlotSource.issue(code,field,message))

static func assess(source: EnvironmentPlotSource, library: Dictionary) -> Dictionary:
	var errors := EnvironmentPlotSource.source_errors(source.data)
	var warnings: Array[Dictionary] = []
	var candidates := {}
	var streets := {}
	var owners := {}
	var routes := {}
	var plan := source.to_plan() if errors.is_empty() else EnvironmentLayoutPlan.new()
	var result := {"ok":false,"generation_ready":false,"errors":errors,"warnings":warnings,"candidates":candidates,"street_owners":owners,"plan":plan}
	if not errors.is_empty(): return result
	var map_rect := Rect2i(Vector2i.ZERO,Vector2i(source.data.map_size[0],source.data.map_size[1]))
	for record in source.data.fixed_streets:
		if not library.has(record.chunk_id) or not available(library[record.chunk_id]): add(errors,"MISSING_STREET_CONTENT",record.id,"Street chunk missing, ambiguous or technically invalid: " + record.chunk_id); continue
		var entry: Dictionary = library[record.chunk_id]
		var chunk: EnvironmentChunkSource = entry.source
		if not chunk.data.rotations.any(func(v): return int(v) == int(record.rotation)) or chunk.data.ports.is_empty() or not chunk.data.ports.all(func(p): return p.role == "street"): add(errors,"NOT_A_STREET",record.id,"Fixed street must use a supported street chunk/rotation"); continue
		var origin := Vector2i(record.origin[0],record.origin[1])
		var bounds := Rect2i(origin,extent(chunk,record.rotation))
		if not map_rect.encloses(bounds): add(errors,"STREET_OUTSIDE_PLOT",record.id,"Street/sidewalk footprint leaves map boundary")
		var walkable := walkable_cells(entry,origin,record.rotation)
		streets[record.id] = {"bounds":bounds,"ports":ports(chunk,origin,record.rotation),"walkable":walkable,"exits":record.exits,"entry":entry,"origin":origin,"rotation":int(record.rotation)}
		for x in range(bounds.position.x,bounds.end.x):
			for z in range(bounds.position.y,bounds.end.y):
				var at := Vector2i(x,z)
				if owners.has(at): add(errors,"STREET_OWNERSHIP_CONFLICT",record.id,"Street and bundled sidewalk at %s already belong to %s" % [at,owners[at]])
				owners[at] = record.id
				plan.road_cells.append(at)
		if not entry.eligible or record.revision != entry.revision or record.revision.is_empty(): add(warnings,"UNAPPROVED_FIXED_REVISION",record.id,"Pin an approved registered revision before generation")
	for id in streets:
		var street: Dictionary = streets[id]
		for exit_id in street.exits:
			if not street.ports.any(func(p): return p.id == exit_id): add(errors,"UNKNOWN_STREET_EXIT",id,"No port " + exit_id)
		for port in street.ports:
			var normal := Vector2i(port.normal[0],port.normal[1])
			if port.id in street.exits:
				if not port.cells.all(func(c): return not map_rect.has_point(Vector2i(c[0],c[1])+normal)): add(errors,"INTERIOR_STREET_EXIT",id,"An exit must reach the map boundary: " + port.id)
				continue
			var matched := false
			for other in streets:
				if other != id and streets[other].ports.any(func(p): return Compiler.ports_match(port,p)): matched = true
			if not matched: add(errors,"UNCONNECTED_STREET_PORT",id,"No matching neighbor or boundary exit for " + port.id)
	var reserved := {}
	for reservation in source.data.reservations:
		var cells := {}
		for encoded in reservation.cells:
			var at := Vector2i(encoded[0],encoded[1])
			if not map_rect.has_point(at): add(errors,"RESERVATION_OUTSIDE_PLOT",reservation.id,"Reservation outside map at %s" % at)
			cells[at] = true
			if not reserved.has(at): reserved[at] = []
			reserved[at].append(Vector2(0,INF if reservation.scope == "whole_column" else float(reservation.height)))
		routes[reservation.id] = cells
		if cells.is_empty() or not connected(cells): add(errors,"DISCONNECTED_RESERVATION",reservation.id,"Access reservation must contain a connected set of cells")
		if not cells.keys().any(func(at): return owners.has(at)): add(errors,"NO_STREET_ACCESS",reservation.id,"Access reservation must reach an owned street/sidewalk")
	var missions: Array = source.data.mission_requirements.filter(func(r): return r.mission in ["all",source.data.active_mission])
	for faction in [0,1]:
		if not missions.any(func(r): return r.kind == "deployment" and r.faction == faction): add(errors,"MISSING_DEPLOYMENT","mission","Active mission needs deployment capacity for faction %d" % faction)
	if source.data.active_mission == "terminal" and not missions.any(func(r): return r.kind == "objective" and r.mission == "terminal"): add(errors,"MISSING_TERMINAL","mission","Active Terminal mission requires an objective reservation")
	var mission_cells := {}
	for requirement in missions:
		var unique := {}
		for encoded in requirement.cells:
			var at := Vector2i(encoded[0],encoded[1])
			unique[at] = true
			if not map_rect.has_point(at): add(errors,"MISSION_OUTSIDE_PLOT",requirement.id,"Mission cell leaves map")
			if mission_cells.has(at): add(errors,"MISSION_CAPACITY_CONFLICT",requirement.id,"Cell already reserved by " + str(mission_cells[at]))
			mission_cells[at] = requirement.id
			if not reserved.has(at): reserved[at] = []
			reserved[at].append(Vector2(0,EnvironmentSpatialQueries.MIN_FLOOR_HEADROOM))
			if not routes.has(requirement.access_ref) or not routes[requirement.access_ref].has(at): add(errors,"MISSING_MISSION_ACCESS",requirement.id,"Every mission cell must belong to access reservation " + requirement.access_ref)
		if unique.size() < requirement.capacity: add(errors,"INSUFFICIENT_MISSION_CAPACITY",requirement.id,"Need %d distinct cells; found %d" % [requirement.capacity,unique.size()])
	var previous: Array = []
	for slot in source.data.slots:
		# Reference loss is independent of candidate-fit failures; never mask it
		# behind an earlier size/rotation rejection.
		for obligation in slot.obligations:
			if obligation.kind not in ["frontage","access"]:
				add(errors,"INVALID_OBLIGATION",slot.id,"Unknown obligation kind: " + obligation.kind)
			elif (obligation.kind == "frontage" and not streets.has(obligation.target_ref)) or (obligation.kind == "access" and not routes.has(obligation.target_ref)):
				add(errors,"MISSING_PLOT_REFERENCE",slot.id,"Required port %s lost %s target %s" % [obligation.port_id,obligation.kind,obligation.target_ref])
		var bounds := rect(slot.bounds)
		if not map_rect.encloses(bounds): add(errors,"SLOT_OUTSIDE_PLOT",slot.id,"Slot leaves map boundary")
		for id in streets:
			if bounds.intersects(streets[id].bounds): add(errors,"SLOT_STREET_OVERLAP",slot.id,"Slot cannot own street or bundled sidewalk belonging to " + id)
		for other in previous:
			if bounds.intersects(rect(other.bounds)): add(errors,"SLOT_OVERLAP",slot.id,"Slot overlaps " + other.id)
		previous.append(slot)
		var viable: Array = []
		var rejected: Array[String] = []
		for id in slot.candidates:
			if not library.has(id) or not available(library[id]): rejected.append(id + ": missing/ambiguous/invalid source"); continue
			var entry: Dictionary = library[id]
			for rotation in slot.rotations:
				var reason := candidate_error(slot,entry,rotation,streets,routes,reserved)
				if reason.is_empty(): viable.append({"chunk_id":id,"rotation":rotation,"origin":[bounds.position.x,bounds.position.y],"revision":entry.revision,"eligible":entry.eligible})
				else: rejected.append("%s r%d: %s" % [id,rotation,reason])
		candidates[slot.id] = viable
		if viable.is_empty() and slot.required: add(errors,"IMPOSSIBLE_SLOT",slot.id,"No compatible chunk: " + ("; ".join(rejected) if not rejected.is_empty() else "choose candidate IDs and rotations"))
		elif slot.required and not viable.any(func(c): return c.eligible): add(warnings,"NO_REGISTERED_CANDIDATE",slot.id,"Geometry fits draft content, but no matching revision is approved and registered")
	# Reservations crossing fixed content must retain usable surfaces.
	for at in reserved:
		if owners.has(at) and not streets[owners[at]].walkable.has(at): add(errors,"BLOCKED_FIXED_ACCESS",str(owners[at]),"Required access is blocked at %s" % at)
	for id in streets:
		var street: Dictionary = streets[id]
		var conflict := reservation_conflict(street.entry,street.origin,street.rotation,reserved)
		if not conflict.is_empty(): add(errors,"FIXED_CLEARANCE_CONFLICT",id,conflict)
	result.ok = errors.is_empty()
	result.generation_ready = result.ok and warnings.is_empty()
	return result

static func candidate_error(slot: Dictionary, entry: Dictionary, rotation: int, streets: Dictionary, routes: Dictionary, reserved: Dictionary) -> String:
	var chunk: EnvironmentChunkSource = entry.source
	if not chunk.data.rotations.any(func(v): return int(v) == rotation): return "rotation not supported"
	var bounds := rect(slot.bounds)
	var size := extent(chunk,rotation)
	if size.x > bounds.size.x or size.y > bounds.size.y: return "needs %s; slot allows %s (no stretching)" % [size,bounds.size]
	var actual := Rect2i(bounds.position,size)
	var walkable := walkable_cells(entry,bounds.position,rotation)
	for at in reserved:
		if actual.has_point(at) and not walkable.has(at): return "required access/mission cell blocked at %s" % at
	var conflict := reservation_conflict(entry,bounds.position,rotation,reserved)
	if not conflict.is_empty(): return conflict
	var transformed := ports(chunk,bounds.position,rotation)
	var obligations := {}
	for obligation in slot.obligations:
		if obligation.kind not in ["frontage","access"]: return "unsupported obligation kind"
		if obligations.has(obligation.port_id): return "port has duplicate obligations"
		obligations[obligation.port_id] = true
		var matches: Array = transformed.filter(func(p): return p.id == obligation.port_id and p.profile == obligation.profile)
		if matches.size() != 1: return "missing port/profile %s / %s" % [obligation.port_id,obligation.profile]
		var port: Dictionary = matches[0]
		if port.connection == "terminated": return "terminated port cannot satisfy an obligation: " + port.id
		var target := {}
		if obligation.kind == "frontage":
			if not streets.has(obligation.target_ref): return "missing street owner " + obligation.target_ref
			target = streets[obligation.target_ref].walkable
		else:
			if not routes.has(obligation.target_ref): return "missing access reservation " + obligation.target_ref
			target = routes[obligation.target_ref]
		var normal := Vector2i(port.normal[0],port.normal[1])
		if port.elevation != 0 or not port.cells.all(func(c): return target.has(Vector2i(c[0],c[1])+normal)): return "port %s does not meet the actual %s geometry" % [port.id,obligation.target_ref]
	for port in transformed:
		if port.connection == "required" and not obligations.has(port.id): return "required port %s needs a frontage/access obligation" % port.id
	return ""
static func connected(cells: Dictionary) -> bool:
	if cells.is_empty(): return false
	var visited := {cells.keys()[0]:true}
	var queue: Array = visited.keys()
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = at + direction
			if cells.has(next) and not visited.has(next): visited[next] = true; queue.append(next)
	return visited.size() == cells.size()

## Transform reservation queries into chunk-local space; reuse T03 volume predicates.
static func reservation_conflict(entry: Dictionary, origin: Vector2i, rotation: int, reserved: Dictionary) -> String:
	var size := extent(entry.source,rotation)
	var inverse := EnvironmentModuleDefinition.new(&"inverse_chunk",&"plot",size)
	var bounds := Rect2i(origin,size)
	for at: Vector2i in reserved:
		if not bounds.has_point(at): continue
		var local := inverse.rotate_cell(at-origin,posmod(-rotation,4))
		for span: Vector2 in reserved[at]:
			for record in entry.compiled.resolved:
				var overlaps := false
				if record.definition == null:
					overlaps = EnvironmentSpatialQueries.visual_intersects_cells(record.visual_bounds,[local],span)
				else:
					var geometry := EnvironmentSpatialQueries.record(record.definition,record.placement)
					if geometry.layer == EnvironmentModuleDefinition.PlacementLayer.GROUND: continue
					overlaps = (local in geometry.cells and EnvironmentSpatialQueries.interval_intersects(span,geometry.occupied_span)) or EnvironmentSpatialQueries.visual_intersects_cells(geometry.visual,[local],span)
				if overlaps: return "reserved clearance at %s intersects %s" % [at,record.placement.placement_id]
	return ""
