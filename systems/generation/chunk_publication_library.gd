class_name ChunkPublicationLibrary
extends RefCounted
## One local index: immutable source revisions, evidence and explicit review state.
const DEFAULT_DIRECTORY := "res://content/chunks/library"
const Compiler = preload("res://systems/generation/chunk_publication_compiler.gd")
var directory: String
func _init(root := DEFAULT_DIRECTORY) -> void: directory = root
func _index() -> Dictionary:
	var path := directory.path_join("index.json")
	if not FileAccess.file_exists(path): return {"schema_version": 1, "revisions": {}, "active": {}}
	var parsed := GenerationJsonStore.parse(FileAccess.get_file_as_string(path))
	if not parsed.ok or parsed.value.get("schema_version") != 1 or not parsed.value.get("revisions") is Dictionary or not parsed.value.get("active") is Dictionary: return {}
	for revision in parsed.value.revisions:
		var record = parsed.value.revisions[revision]
		if not revision is String or not _revision_id(revision) or not record is Dictionary: return {}
		if not record.get("source_path") is String or not record.get("evidence") is Array or not record.get("review") is Dictionary or not record.get("registered") is bool: return {}
	for id in parsed.value.active:
		if not id is String or not parsed.value.active[id] is String or not parsed.value.revisions.has(parsed.value.active[id]): return {}
	return parsed.value
func _write(index: Dictionary) -> String: return GenerationJsonStore.write(directory.path_join("index.json"), JSON.stringify(index, "\t"))
func validate_and_store(source: EnvironmentChunkSource, source_path: String, context: EnvironmentResolutionContext = null) -> Dictionary:
	var disk := ChunkSourceStore.decode(FileAccess.get_file_as_string(source_path)) if FileAccess.file_exists(source_path) else {"ok": false}
	if not disk.ok or Compiler.source_hash(disk.source) != Compiler.source_hash(source): return failure("Save this exact draft before validation")
	var compiled := Compiler.compile(source, context)
	if not compiled.ok: return {"ok": false, "error": "Technical validation failed", "errors": compiled.errors}
	var revision: String = compiled.revision
	var manifest := {"schema_version": 1, "revision": revision, "source_hash": compiled.source_hash, "source": source.to_dictionary(), "dependencies": compiled.dependencies, "compiler": compiled.compiler, "implementation": compiled.implementation, "profiles_sha256": compiled.profiles_sha256}
	var index := _index()
	if index.is_empty(): return failure("Malformed library index; existing state preserved")
	var path := directory.path_join("revisions").path_join(revision + ".json")
	if FileAccess.file_exists(path):
		var existing := GenerationJsonStore.parse(FileAccess.get_file_as_string(path))
		if not existing.ok or Compiler.canonical(existing.value) != Compiler.canonical(manifest): return failure("Immutable revision file differs; refusing overwrite")
	else:
		var error := GenerationJsonStore.write(path, JSON.stringify(manifest, "\t"))
		if not error.is_empty(): return failure(error)
	if not index.revisions.has(revision): index.revisions[revision] = {"source_path": source_path, "evidence": [], "review": {}, "registered": false}
	var error := _write(index)
	if not error.is_empty(): return failure(error)
	return {"ok": true, "revision": revision, "compiled": compiled, "error": ""}
func inspect(revision: String, context: EnvironmentResolutionContext = null) -> Dictionary:
	if not _revision_id(revision): return failure("Invalid revision ID")
	var index := _index()
	if not index.get("revisions", {}).has(revision): return failure("Unknown validated revision")
	var record: Dictionary = index.revisions[revision]
	var parsed := GenerationJsonStore.parse(FileAccess.get_file_as_string(directory.path_join("revisions").path_join(revision + ".json")))
	if not parsed.ok: return failure("Missing or malformed immutable revision")
	var manifest: Dictionary = parsed.value
	if manifest.get("schema_version") != 1 or manifest.get("revision") != revision or not manifest.get("source") is Dictionary: return failure("Invalid immutable revision")
	var decoded := ChunkSourceStore.decode(JSON.stringify(manifest.source))
	if not decoded.ok: return failure("Invalid source in revision")
	var disk_path := str(record.get("source_path", ""))
	if not FileAccess.file_exists(disk_path): return failure("Draft source file is missing")
	var current := ChunkSourceStore.decode(FileAccess.get_file_as_string(disk_path))
	if not current.ok or Compiler.source_hash(current.source) != manifest.source_hash: return failure("Source has changed: save/validate a new draft revision")
	var compiled := Compiler.compile(decoded.source, context)
	if not compiled.ok or compiled.revision != revision: return failure("Stale content/compiler dependencies; validate and review a new revision")
	if Compiler.canonical(compiled.dependencies) != Compiler.canonical(manifest.get("dependencies", [])) or manifest.get("implementation") != compiled.implementation or manifest.get("source_hash") != compiled.source_hash or manifest.get("compiler") != compiled.compiler or manifest.get("profiles_sha256") != compiled.profiles_sha256: return failure("Immutable manifest was modified")
	return {"ok": true, "manifest": manifest, "record": record, "compiled": compiled, "source": decoded.source, "error": ""}
func capture_evidence(revision: String, picture: Image, view_name: String) -> Dictionary:
	var checked := inspect(revision)
	if not checked.ok: return checked
	if picture == null or picture.is_empty(): return failure("A rendered capture is required")
	if view_name not in ["overview", "opposite", "overhead"]: return failure("Use overview, opposite or overhead view")
	if not checked.record.review.is_empty(): return failure("Review evidence is sealed; revoke review before replacing it")
	var png := picture.save_png_to_buffer()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(png)
	var digest := hash.finish().hex_encode()
	var path := directory.path_join("evidence").path_join(revision).path_join(view_name + "-" + digest + ".png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if not FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return failure("Cannot save review capture")
		file.store_buffer(png)
		file.close()
	var index := _index()
	var evidence: Array = index.revisions[revision].evidence
	evidence = evidence.filter(func(item): return item.view != view_name)
	evidence.append({"view": view_name, "path": path, "sha256": digest})
	index.revisions[revision].evidence = evidence
	var error := _write(index)
	return {"ok": error.is_empty(), "error": error, "path": path}
func evidence_error(record: Dictionary) -> String:
	var views := {}
	for item in record.get("evidence", []):
		if not item is Dictionary or not item.get("path") is String or not item.get("sha256") is String: return "Malformed review evidence"
		if not FileAccess.file_exists(item.path) or FileAccess.get_sha256(item.path) != item.sha256: return "Review capture missing or changed"
		views[item.get("view", "")] = true
	for required in ["overview", "opposite", "overhead"]:
		if not views.has(required): return "Capture overview, opposite and overhead views before owner approval"
	return ""
func approve_by_owner(revision: String, reviewer: String, affirmation: bool) -> Dictionary:
	# Called only by the explicit owner confirmation dialog (or isolated tests).
	# This local record is an attestation, not an authentication service.
	if not affirmation or reviewer.strip_edges().is_empty(): return failure("Explicit owner affirmation and reviewer name are required")
	var checked := inspect(revision)
	if not checked.ok: return checked
	var error := evidence_error(checked.record)
	if not error.is_empty(): return failure(error)
	var index := _index()
	index.revisions[revision].review = {"kind": "owner_visual_approval", "reviewer": reviewer.strip_edges(), "revision": revision, "evidence_signature": Compiler.canonical(checked.record.evidence).sha256_text(), "timestamp_utc": Time.get_datetime_string_from_system(true)}
	error = _write(index)
	return {"ok": error.is_empty(), "error": error}
func register(revision: String) -> Dictionary:
	var checked := inspect(revision)
	if not checked.ok: return checked
	var error := review_error(checked.record, revision)
	if not error.is_empty(): return failure(error)
	var index := _index()
	index.revisions[revision].registered = true
	index.active[checked.manifest.source.chunk_id] = revision
	error = _write(index)
	return {"ok": error.is_empty(), "error": error}
func review_error(record: Dictionary, revision: String) -> String:
	var error := evidence_error(record)
	if not error.is_empty(): return error
	var review: Dictionary = record.get("review", {})
	if review.get("kind") != "owner_visual_approval" or review.get("revision") != revision or str(review.get("reviewer", "")).is_empty() or review.get("evidence_signature") != Compiler.canonical(record.evidence).sha256_text(): return "Exact revision still needs owner visual approval"
	return ""
func revoke_review(revision: String) -> Dictionary:
	var index := _index()
	if not index.get("revisions", {}).has(revision): return failure("Unknown revision")
	index.revisions[revision].review = {}
	index.revisions[revision].registered = false
	for id in index.active.keys():
		if index.active[id] == revision: index.active.erase(id)
	var error := _write(index)
	return {"ok": error.is_empty(), "error": error}
func eligible(context: EnvironmentResolutionContext = null) -> Array[Dictionary]:
	if context == null: context = EnvironmentResolutionContext.new()
	var index := _index()
	var result: Array[Dictionary] = []
	var ids: Array = index.get("active", {}).keys()
	ids.sort()
	for id in ids:
		var revision := str(index.active[id])
		var checked := inspect(revision, context)
		if checked.ok and checked.record.get("registered", false) and review_error(checked.record, revision).is_empty():
			result.append({"id": id, "revision": revision, "source": checked.source, "dependencies": checked.manifest.dependencies, "resolved": checked.compiled.resolved, "data": checked.compiled.data})
	return result
static func _revision_id(value: String) -> bool:
	return value.length() == 64 and value.is_valid_hex_number(false)
static func failure(message: String) -> Dictionary: return {"ok": false, "error": message}
