extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var data := LoadingYardLayout.generate(17)
	var presentation := Node3D.new()
	root.add_child(presentation)
	LoadingYardLayout.present(presentation, 1)
	var occupants := 0
	for node: Node3D in presentation.find_children("*", "Node3D", true, false):
		if not node.has_meta("population_socket_id"): continue
		occupants += 1
		_check(node.is_visible_in_tree(), "Fixed Loading Yard occupant must be visible: " + String(node.name))
		var cell := Vector3i(floori(node.global_position.x + data.map_size.x * 0.5), 0, floori(node.global_position.z + data.map_size.y * 0.5))
		_check(not data.get_cell(cell).can_stop, "Visible authored occupant retains its compiled tactical reservation: " + String(node.name))
	_check(occupants == 3, "Fixed Loading Yard presents both containers and its truck")
	presentation.queue_free()
	await process_frame
	print("Loading Yard presentation: %d failure(s)" % failures)
	quit(1 if failures else 0)
func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
