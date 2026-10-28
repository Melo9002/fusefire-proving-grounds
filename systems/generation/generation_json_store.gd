class_name GenerationJsonStore
extends RefCounted
## Shared JSON I/O only. Each document owns its version/validation policy.
static func parse(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return failure("MALFORMED_JSON", "JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	if not parser.data is Dictionary: return failure("MALFORMED_DOCUMENT", "Expected a JSON object")
	return {"ok": true, "value": parser.data}

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return failure("FILE_NOT_FOUND", "No saved file at " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return failure("READ_FAILED", "Could not read " + path)
	return {"ok": true, "text": file.get_as_text()}

static func write(path: String, text: String) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK: return "Could not create destination directory: " + error_string(error)
	var temporary := absolute + ".tmp-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "Could not open temporary file: " + error_string(FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Save failed; previous file preserved: " + error_string(error)
	return ""

static func failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
