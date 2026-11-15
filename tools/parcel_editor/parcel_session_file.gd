extends RefCounted
## One file for the complete parcel edit. Existing draft payloads and validators
## remain the contract; validate both before replacing either active draft.
const Objects = preload("res://tools/parcel_editor/parcel_draft_session.gd")
const Fields = preload("res://tools/parcel_editor/population_field_draft.gd")
const Catalog = preload("res://systems/generation2/authored_parcel_catalog.gd")
const FORMAT := "fusefire-parcel-session"

static func save_to(path: String, objects, fields) -> String:
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return error_string(error)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify({"format": FORMAT, "version": 1, "objects": objects.to_record(), "population": fields.to_record()}, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return error_string(error)
	objects.mark_saved()
	fields._mark_saved()
	return ""

static func open_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Cannot open parcel session: " + error_string(FileAccess.get_open_error())}
	if file.get_length() > 8 * 1024 * 1024: return {"error": "Parcel session exceeds 8 MB."}
	var record: Variant = JSON.parse_string(file.get_as_text())
	if not record is Dictionary or record.get("format") != FORMAT or record.get("version") != 1 or not record.get("objects") is Dictionary or not record.get("population") is Dictionary:
		return {"error": "Not a supported parcel session. Old object/field files use the legacy import controls."}
	var definition = Catalog.get_definition(StringName(record.objects.get("base_parcel_id", "")))
	if definition == null: return {"error": "The session's source parcel is unavailable."}
	var root: Node3D = definition.instantiate()
	var objects := Objects.new()
	objects.begin(definition, root)
	var fields := Fields.new()
	fields.begin(definition, root)
	var error := ""
	if not objects.load_record(record.objects, definition, root): error = objects.last_error
	elif not fields.load_record(record.population): error = fields.last_error
	else: error = "; ".join(objects.apply(root))
	root.free()
	if not error.is_empty(): return {"error": error}
	return {"definition": definition, "objects": objects, "population": fields}
