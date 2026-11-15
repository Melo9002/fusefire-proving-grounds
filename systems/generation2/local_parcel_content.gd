extends RefCounted
## Immutable local test snapshots. Replays name a hash, never an arbitrary
## scene path. Missing snapshots or changed project dependencies reject clearly.
const DIRECTORY := "user://parcel_test_content"

static func directory() -> String:
	var test_output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	return test_output.path_join("parcel_test_content") if not test_output.is_empty() else DIRECTORY

static func snapshot_path(digest: String) -> String:
	return directory().path_join(digest + ".tscn")

static func archive(scene: PackedScene) -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(directory())
	if error != OK: return {"error": error_string(error)}
	var temporary := directory().path_join("pending_%d_%d.tscn" % [OS.get_process_id(), Time.get_ticks_usec()])
	error = ResourceSaver.save(scene, temporary)
	if error != OK: return {"error": "Cannot preserve parcel test content: " + error_string(error)}
	var dependencies := {}
	var issue := _dependencies(temporary, dependencies)
	var digest := FileAccess.get_sha256(temporary)
	var path := snapshot_path(digest)
	var created := not FileAccess.file_exists(path)
	if issue.is_empty() and created:
		error = DirAccess.rename_absolute(temporary, path)
		if error != OK: issue = error_string(error)
	if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
	if not issue.is_empty(): return {"error": issue}
	return {"content": {"snapshot": digest, "dependencies": dependencies}, "created": created}

static func validate(content: Variant) -> String:
	if not content is Dictionary or not content.get("snapshot") is String or not content.get("dependencies") is Dictionary:
		return "INVALID_LOCAL_PARCEL_CONTENT"
	var digest: String = content.snapshot
	if digest.length() != 64: return "INVALID_LOCAL_PARCEL_HASH"
	for index in digest.length():
		if not "0123456789abcdef".contains(digest.substr(index, 1)): return "INVALID_LOCAL_PARCEL_HASH"
	var path := snapshot_path(digest)
	if not FileAccess.file_exists(path): return "MISSING_LOCAL_PARCEL_SNAPSHOT: " + digest
	if FileAccess.get_sha256(path) != digest: return "CHANGED_LOCAL_PARCEL_SNAPSHOT: " + digest
	var dependencies := {}
	var issue := _dependencies(path, dependencies)
	if not issue.is_empty(): return issue
	if dependencies != content.dependencies: return "CHANGED_LOCAL_PARCEL_DEPENDENCIES"
	return ""

static func open_scene(content: Variant) -> Dictionary:
	var issue := validate(content)
	if not issue.is_empty(): return {"error": issue}
	var scene := ResourceLoader.load(snapshot_path(content.snapshot), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return {"scene": scene} if scene else {"error": "INVALID_LOCAL_PARCEL_SCENE"}

static func _dependencies(path: String, result: Dictionary) -> String:
	if result.size() > 512: return "LOCAL_PARCEL_DEPENDENCY_LIMIT"
	for dependency in ResourceLoader.get_dependencies(path):
		var target := String(dependency).split("::")[-1].simplify_path()
		if not target.begins_with("res://") or ".." in target.split("/"):
			return "UNSUPPORTED_LOCAL_PARCEL_DEPENDENCY: " + target
		if result.has(target): continue
		if not FileAccess.file_exists(target): return "MISSING_LOCAL_PARCEL_DEPENDENCY: " + target
		result[target] = FileAccess.get_sha256(target)
		var issue := _dependencies(target, result)
		if not issue.is_empty(): return issue
	return ""
