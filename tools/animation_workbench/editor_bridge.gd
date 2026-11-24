@tool
class_name EditorBridge
extends RefCounted
## The Workbench's way into the Godot editor. The Workbench writes a REQUEST ("open this file", "open this scene and select that node, on that clip") into the project's user folder; the ADDA bridge
## editor plugin (addons/adda_bridge) picks it up within a second and does it. The plugin also writes a HEARTBEAT while the editor is open, so the Workbench knows whether to start an editor or just ask the
## running one. Both sides use this file, so the format lives in one place. Nothing here runs in the game.

## Where requests and the heartbeat live. Tests point it elsewhere so a running editor never sees their requests.
static var folder := "user://adda_bridge"

static func request_file() -> String:
	return folder.path_join("request.json")

static func heartbeat_file() -> String:
	return folder.path_join("editor_alive.json")
## The editor counts as open when its heartbeat is younger than this (it writes one every second).
const ALIVE_SECONDS := 4.0

## A request: `path` a res:// file (a .tres opens in the Inspector, a .tscn opens as a scene, a .gd in the script editor), `node` a node path inside that scene to select, `animation` a clip for the selected
## AnimationPlayer to show in the Animation panel, `line` a script line.
static func request(path: String, node := "", animation := "", line := -1) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	return {"path": path, "node": node, "animation": animation, "line": line, "at": now, "id": "%d-%d" % [now * 1000.0, randi() % 100000]}

## A request older than this is ignored (an editor opened days later must not jump to an old file).
const STALE_SECONDS := 600.0

## Whether an editor with the bridge is running for this project now (`now` in Unix seconds; tests pass their own).
static func editor_alive(now := -1.0) -> bool:
	if not FileAccess.file_exists(heartbeat_file()):
		return false
	var beat = JSON.parse_string(FileAccess.get_file_as_string(heartbeat_file()))
	if typeof(beat) != TYPE_DICTIONARY:
		return false
	var at := now if now >= 0.0 else Time.get_unix_time_from_system()
	return at - float(beat.get("at", 0.0)) <= ALIVE_SECONDS

## Asks the editor to open `req`. Starts an editor for this project when none is running. Returns what happened, in words, for the panel.
static func send(req: Dictionary, launch := true) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(request_file(), FileAccess.WRITE)
	if file == null:
		return "Could not write the request (%s)." % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(req))
	file.close()
	if editor_alive():
		return "Opened in the Godot editor that is already running (switch to its window)."
	if not launch:
		return "The request is waiting; it opens when the Godot editor starts."
	var pid := OS.create_process(OS.get_executable_path(), ["--editor", "--path", ProjectSettings.globalize_path("res://")])
	if pid <= 0:
		return "Could not start the Godot editor. Open the project in Godot yourself: the request opens when it starts."
	return "Starting the Godot editor... it opens %s when it is ready (the first start can take a minute)." % req.path.get_file()

## The editor side: the request waiting, if it is new (not `last_id`) and recent, or {}.
static func pending(last_id: String, now := -1.0) -> Dictionary:
	if not FileAccess.file_exists(request_file()):
		return {}
	var req = JSON.parse_string(FileAccess.get_file_as_string(request_file()))
	if typeof(req) != TYPE_DICTIONARY or String(req.get("id", "")) == last_id or String(req.get("path", "")) == "":
		return {}
	var at := now if now >= 0.0 else Time.get_unix_time_from_system()
	if at - float(req.get("at", 0.0)) > STALE_SECONDS:
		return {}
	return req

## The editor side: the request was handled; it is removed so it never runs twice.
static func done() -> void:
	if FileAccess.file_exists(request_file()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(request_file()))

static func beat() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(heartbeat_file(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"at": Time.get_unix_time_from_system(), "pid": OS.get_process_id()}))
		file.close()
