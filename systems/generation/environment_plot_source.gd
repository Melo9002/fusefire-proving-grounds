class_name EnvironmentPlotSource
extends RefCounted
## Authored world intent; chunk internals remain in local sources. No selection/packing.
const FORMAT := "fusefire_plot_source"
const VERSION := 2
const Chunk = preload("res://systems/generation/environment_chunk_source.gd")
var data: Dictionary
func _init(id := "new_plot") -> void:
	data = {"format": FORMAT, "schema_version": VERSION, "plot_id": id, "map_size": [60,50], "active_mission": "eliminate", "fixed_streets": [], "slots": [], "reservations": [], "mission_requirements": [], "population": {"version":1,"regions":[],"routes":[]}}
func copy() -> EnvironmentPlotSource:
	var result := EnvironmentPlotSource.new()
	result.data = data.duplicate(true)
	return result
static func issue(code: String, field: String, message: String) -> Dictionary: return {"code": code, "field": field, "message": message}
static func source_errors(value: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if not Chunk._json_value(value): return [issue("MALFORMED_PLOT", "source", "Expected finite JSON values")]
	var fields := {"format":TYPE_STRING,"schema_version":TYPE_NIL,"plot_id":TYPE_STRING,"map_size":TYPE_ARRAY,"active_mission":TYPE_STRING,"fixed_streets":TYPE_ARRAY,"slots":TYPE_ARRAY,"reservations":TYPE_ARRAY,"mission_requirements":TYPE_ARRAY}
	if value.get("schema_version") == 2: fields["population"] = TYPE_DICTIONARY
	if not Chunk._fields(value,fields,errors,"source"): return errors
	if value.format != FORMAT or (value.schema_version != 1 and value.schema_version != 2) or not Chunk._integer(value.schema_version): errors.append(issue("UNSUPPORTED_PLOT_VERSION","source","Unsupported plot format/version"))
	if value.plot_id.is_empty() or not Chunk._vector(value.map_size,2) or value.map_size.any(func(n): return n < 1 or n > 256): errors.append(issue("INVALID_PLOT_BOUNDS","map_size","Use integer map dimensions 1..256"))
	if value.active_mission not in ["eliminate","terminal"]: errors.append(issue("UNSUPPORTED_MISSION","active_mission","Pilot supports Eliminate and Terminal"))
	var identities := {}
	for group in ["fixed_streets","slots","reservations","mission_requirements"]:
		if value[group].size() > 128: errors.append(issue("PLOT_BUDGET",group,"At most 128 records per group")); continue
		for record in value[group]:
			var schema: Dictionary
			match group:
				"fixed_streets": schema = {"id":TYPE_STRING,"chunk_id":TYPE_STRING,"revision":TYPE_STRING,"origin":TYPE_ARRAY,"rotation":TYPE_NIL,"exits":TYPE_ARRAY}
				"slots": schema = {"id":TYPE_STRING,"bounds":TYPE_ARRAY,"candidates":TYPE_ARRAY,"rotations":TYPE_ARRAY,"required":TYPE_BOOL,"obligations":TYPE_ARRAY}
				"reservations": schema = {"id":TYPE_STRING,"role":TYPE_STRING,"cells":TYPE_ARRAY,"scope":TYPE_STRING,"elevation":TYPE_NIL,"height":TYPE_NIL}
				_: schema = {"id":TYPE_STRING,"mission":TYPE_STRING,"kind":TYPE_STRING,"faction":TYPE_NIL,"capacity":TYPE_NIL,"cells":TYPE_ARRAY,"access_ref":TYPE_STRING}
			if not Chunk._fields(record,schema,errors,group): continue
			if record.id.is_empty() or identities.has(record.id): errors.append(issue("DUPLICATE_PLOT_ID",group,"Record identity missing or duplicated: " + record.id))
			identities[record.id] = true
			match group:
				"fixed_streets":
					if not Chunk._vector(record.origin,2) or not quarter(record.rotation) or not record.exits.all(func(v): return v is String): errors.append(issue("INVALID_STREET",record.id,"Street needs integer origin, quarter turn and exit port IDs"))
				"slots":
					if not Chunk._vector(record.bounds,4) or record.bounds[2] < 1 or record.bounds[3] < 1 or not record.candidates.all(func(v): return v is String) or not record.rotations.all(quarter): errors.append(issue("INVALID_SLOT",record.id,"Slot needs positive rectangular bounds, chunk IDs and quarter turns"))
					for obligation in record.obligations:
						Chunk._fields(obligation,{"port_id":TYPE_STRING,"profile":TYPE_STRING,"target_ref":TYPE_STRING,"kind":TYPE_STRING},errors,record.id + ".obligations")
				"reservations":
					if record.role not in EnvironmentSpatialReservationLedger.ROLES or record.scope not in ["floor","whole_column"] or not Chunk._integer(record.elevation) or record.elevation != 0 or not (record.height is float or record.height is int) or record.height <= 0: errors.append(issue("INVALID_RESERVATION",record.id,"Pilot reserves ground-level floor or whole-column space with positive height"))
					if not record.cells.all(func(c): return Chunk._vector(c,2)): errors.append(issue("INVALID_RESERVATION_CELLS",record.id,"Expected X/Z cells"))
				"mission_requirements":
					if record.mission not in ["all","eliminate","terminal"] or record.kind not in ["deployment","objective"] or not Chunk._integer(record.capacity) or record.capacity < 1 or not Chunk._integer(record.faction) or int(record.faction) not in [-1,0,1,2] or not record.cells.all(func(c): return Chunk._vector(c,2)): errors.append(issue("INVALID_MISSION_REQUIREMENT",record.id,"Use supported mission, kind, faction, positive capacity and X/Z cells"))
	return errors
static func quarter(value) -> bool: return Chunk._integer(value) and int(value) in [0,1,2,3]

static func load_file(path: String) -> Dictionary:
	var read := GenerationJsonStore.read(path)
	if not read.ok: return read
	var parsed := GenerationJsonStore.parse(read.text)
	if not parsed.ok: return parsed
	var errors := source_errors(parsed.value)
	if not errors.is_empty(): return {"ok":false,"error":errors[0].message,"errors":errors}
	var source := EnvironmentPlotSource.new()
	source.data = parsed.value
	return {"ok":true,"source":source}
func save_file(path: String) -> String:
	var errors := source_errors(data)
	if not errors.is_empty(): return errors[0].message
	return GenerationJsonStore.write(path,JSON.stringify(data,"\t",false)+"\n")

## Use the existing plan as a derived view, not a second road/parcel authority.
func to_plan() -> EnvironmentLayoutPlan:
	var plan := EnvironmentLayoutPlan.new(&"industrial_district")
	plan.topology = &"authored_plot"
	for slot in data.slots:
		plan.parcels.append({"id":StringName(slot.id),"bounds":Rect2i(slot.bounds[0],slot.bounds[1],slot.bounds[2],slot.bounds[3]),"template":&"chunk_slot","required":slot.required,"candidates":slot.candidates.duplicate(),"rotations":slot.rotations.duplicate(),"obligations":slot.obligations.duplicate(true)})
	for record in data.reservations:
		var converted: Dictionary = record.duplicate(true)
		converted["reservation_id"] = record.id
		converted["owner_ref"] = "plot:" + data.plot_id
		converted.cells = record.cells.map(func(c): return Vector2i(c[0],c[1]))
		plan.reservations.append(converted)
	return plan

func population_rules() -> Dictionary:
	return data.get("population",{"version":1,"regions":[],"routes":[]}).duplicate(true)
