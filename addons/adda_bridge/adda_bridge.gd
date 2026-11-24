@tool
extends EditorPlugin
## The editor half of the Workbench's "Edit in Godot" buttons. Every second it writes a heartbeat (so the Workbench knows an editor is open) and looks for a request the Workbench left
## (tools/animation_workbench/editor_bridge.gd). A request opens a .tres in the Inspector, a .tscn as a scene (selecting a node, and for an AnimationPlayer the clip asked for), or a .gd in the script editor.
## It edits nothing by itself and never saves.

const Bridge := preload("res://tools/animation_workbench/editor_bridge.gd")

var _timer: Timer
var _last := ""

func _enter_tree() -> void:
	if DisplayServer.get_name() == "headless":
		return   # an import or a test run is not an editor a person can switch to
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_tick.call_deferred()

func _exit_tree() -> void:
	if not is_instance_valid(_timer):
		return
	_timer.queue_free()
	if FileAccess.file_exists(Bridge.heartbeat_file()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Bridge.heartbeat_file()))   # a closed editor is not "open"

func _tick() -> void:
	Bridge.beat()
	var req := Bridge.pending(_last)
	if req.is_empty():
		return
	_last = String(req.id)
	Bridge.done()
	_open(req)

func _open(req: Dictionary) -> void:
	var path := String(req.path)
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("ADDA bridge: %s does not exist" % path)
		return
	if path.ends_with(".tscn"):
		EditorInterface.open_scene_from_path(path)
		for i in 3:
			await get_tree().process_frame
		var root := EditorInterface.get_edited_scene_root()
		var node: Node = root.get_node_or_null(NodePath(String(req.get("node", "")))) if root != null and String(req.get("node", "")) != "" else null
		if node != null:
			if node is AnimationPlayer and String(req.get("animation", "")) != "" and (node as AnimationPlayer).has_animation(StringName(req.animation)):
				(node as AnimationPlayer).assigned_animation = StringName(req.animation)
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(node)
			EditorInterface.edit_node(node)
		EditorInterface.set_main_screen_editor("3D")
	elif path.ends_with(".gd"):
		EditorInterface.edit_script(load(path), maxi(int(req.get("line", 0)), 0))
		EditorInterface.set_main_screen_editor("Script")
	else:
		var resource := load(path)
		EditorInterface.edit_resource(resource)
		EditorInterface.get_file_system_dock().navigate_to_path(path)
	DisplayServer.window_move_to_foreground()
