class_name MissionTerminalPresenter
extends Node3D

## Visual consumer of ObjectiveManager's authoritative terminal state.
@export var objective_manager: ObjectiveManager
@export var grid_manager: GridManager

var terminal_nodes: Dictionary[StringName, Node3D] = {}

func _ready() -> void:
	if not objective_manager or not grid_manager:
		push_warning("MissionTerminalPresenter requires ObjectiveManager and GridManager.")
		return
	objective_manager.terminals_initialized.connect(_rebuild)
	objective_manager.terminal_state_changed.connect(_on_terminal_changed)

func _rebuild() -> void:
	for child in get_children(): child.queue_free()
	terminal_nodes.clear()
	for terminal_id in objective_manager.get_terminal_ids():
		var state := objective_manager.get_terminal_state(terminal_id)
		if not state: continue
		var root := Node3D.new()
		root.name = String(terminal_id)
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.72, 1.25, 0.62)
		body.mesh = box
		body.position.y = 0.625
		root.add_child(body)
		var screen := MeshInstance3D.new()
		var panel := BoxMesh.new()
		panel.size = Vector3(0.5, 0.34, 0.05)
		screen.mesh = panel
		screen.position = Vector3(0.0, 0.86, -0.335)
		root.add_child(screen)
		add_child(root)
		root.global_position = grid_manager.grid_to_world(state.definition.grid_position)
		terminal_nodes[terminal_id] = root
		_apply_state(state)

func _on_terminal_changed(state: MissionTerminalState) -> void:
	_apply_state(state)

func _apply_state(state: MissionTerminalState) -> void:
	var root := terminal_nodes.get(state.definition.terminal_id) as Node3D
	if not is_instance_valid(root): return
	var body := root.get_child(0) as MeshInstance3D
	var screen := root.get_child(1) as MeshInstance3D
	body.material_override = _material(Color(0.18, 0.22, 0.3) if not state.is_activated else Color(0.16, 0.42, 0.28))
	screen.material_override = _material(Color(0.72, 0.26, 0.92) if not state.is_activated else Color(0.28, 1.0, 0.55))

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.55
	return material
