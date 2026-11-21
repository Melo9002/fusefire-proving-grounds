extends SceneTree
## Every res:// path and uid:// reference in the project's scripts, scenes and resources resolves. This is the safety net for file moves (Task 07): after a move step a stale path, a missing
## .uid sidecar or a scene whose script moved fails HERE, by name, instead of as a confusing load error somewhere else. Third-party addons and the engine's own cache are not scanned.
## Paths the program creates at run time (test output files) and format strings are skipped explicitly below.
const SKIP_DIRECTORIES := [".godot", ".git", "addons", "artifacts", "node_modules"]
const SCAN_EXTENSIONS := ["gd", "tscn", "tres"]
const RUNTIME_PREFIXES := ["addons/", "artifacts/", ".godot/", "tests/_", "tests/.", "user:"]
var failures := 0
var checks := 0
var files: Dictionary = {}       # every file path (project-relative) that exists
var uids: Dictionary = {}        # every uid that some file declares
var texts: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _walk(directory: String) -> void:
	var dir := DirAccess.open("res://" + directory)
	if dir == null:
		return
	for entry in dir.get_directories():
		if directory == "" and entry in SKIP_DIRECTORIES:
			continue
		_walk(entry if directory == "" else directory + "/" + entry)
	for file in dir.get_files():
		var path := file if directory == "" else directory + "/" + file
		files[path] = true

func _run() -> void:
	_walk("")
	var scanned := 0
	var uid_pattern := RegEx.create_from_string("uid://[a-z0-9]+")
	var header_pattern := RegEx.create_from_string("^\\[gd_(?:scene|resource)[^\\]]*uid=\"(uid://[a-z0-9]+)\"")
	var import_pattern := RegEx.create_from_string("(?m)^uid=\"(uid://[a-z0-9]+)\"")
	for path: String in files:
		var extension := path.get_extension()
		if extension == "uid":
			uids[FileAccess.get_file_as_string("res://" + path).strip_edges()] = true
		elif extension == "import":
			var found := import_pattern.search(FileAccess.get_file_as_string("res://" + path))
			if found:
				uids[found.get_string(1)] = true
		elif extension in SCAN_EXTENSIONS:
			var text := FileAccess.get_file_as_string("res://" + path)
			texts[path] = text
			scanned += 1
			if extension != "gd":
				var header := header_pattern.search(text)
				if header:
					uids[header.get_string(1)] = true
	var path_pattern := RegEx.create_from_string("res://([A-Za-z0-9_\\-\\./]+)")
	var broken_paths: Array[String] = []
	var broken_uids: Array[String] = []
	var path_count := 0
	var uid_count := 0
	for path: String in texts:
		var text: String = texts[path]
		for match in path_pattern.search_all(text):
			var reference := match.get_string(1)
			if reference.ends_with("/") or reference.ends_with(".") or reference.begins_with("."):
				if reference.ends_with("/") and not DirAccess.dir_exists_absolute("res://" + reference):
					broken_paths.append("%s -> %s" % [path, reference])
				continue
			if RUNTIME_PREFIXES.any(func(prefix: String) -> bool: return reference.begins_with(prefix)):
				continue
			if reference.get_extension() == "":
				if not DirAccess.dir_exists_absolute("res://" + reference):
					broken_paths.append("%s -> %s" % [path, reference])
				path_count += 1
				continue
			path_count += 1
			if not files.has(reference):
				broken_paths.append("%s -> %s" % [path, reference])
		for match in uid_pattern.search_all(text):
			uid_count += 1
			if not uids.has(match.get_string()):
				broken_uids.append("%s -> %s" % [path, match.get_string()])
	print("  scanned %d files: %d res:// references, %d uid:// references" % [scanned, path_count, uid_count])
	check(path_count > 500, "The scan actually found the project's references (%d)" % path_count)
	check(broken_paths.is_empty(), "Every res:// reference resolves to a file or folder (%d broken: %s)" % [broken_paths.size(), ", ".join(broken_paths.slice(0, 40))])
	check(broken_uids.is_empty(), "Every uid:// reference resolves to a .uid sidecar, an .import file or a scene/resource header (%d unresolved: %s)" % [broken_uids.size(), ", ".join(broken_uids.slice(0, 5))])
	# A script must have its sidecar (a missing one regenerates a NEW uid and silently breaks uid references).
	var missing_sidecars: Array[String] = []
	for path: String in files:
		if path.get_extension() == "gd" and not path.begins_with("research/zz") and not files.has(path + ".uid"):
			missing_sidecars.append(path)
	check(missing_sidecars.is_empty(), "Every script has its .uid sidecar (%d missing: %s)" % [missing_sidecars.size(), ", ".join(missing_sidecars.slice(0, 5))])
	print("Resource references: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
