extends Node3D
## Terrain footprint belongs to the planner. This node supplies mesh and UI.
var objectives: ObjectiveManager
var leave_button: Button
var confirmation: ConfirmationDialog

func _process(_delta: float) -> void:
	if not is_instance_valid(leave_button) or not is_instance_valid(objectives): return
	var camera := get_viewport().get_camera_3d()
	var point := global_position + Vector3.UP * 2.1
	leave_button.visible = camera != null and not camera.is_position_behind(point) and objectives.can_end_mission_early() and not objectives._battle_controller.replay_mode
	if leave_button.visible:
		leave_button.position = camera.unproject_position(point) - leave_button.size * 0.5
		leave_button.disabled = objectives._battle_controller.is_action_in_progress

func _request_leave() -> void:
	confirmation.dialog_text = "Leave now? %d units will be left behind." % objectives.get_units_left_behind()
	confirmation.popup_centered()

func _confirm_leave() -> void:
	objectives.end_mission_early()

func setup(grid: GridManager, cells: Array[Vector3i], enemy_owned: bool, footprint: Array = []) -> void:
	if cells.is_empty() or not grid.map_floor:
		return
	var center := Vector3.ZERO
	for cell in cells:
		center += grid.grid_to_world(cell)
	center /= cells.size()
	var floor_center := grid.map_floor.global_position
	var half := grid.map_floor.size * 0.5
	var edges := [Vector3(floor_center.x - half.x - 2.0, center.y, center.z), Vector3(floor_center.x + half.x + 2.0, center.y, center.z), Vector3(center.x, center.y, floor_center.z - half.z - 2.0), Vector3(center.x, center.y, floor_center.z + half.z + 2.0)]
	var nearest: Vector3 = edges[0]
	for edge: Vector3 in edges:
		if edge.distance_squared_to(center) < nearest.distance_squared_to(center):
			nearest = edge
	global_position = nearest
	global_position.y = floor_center.y + half.y
	# Long axis parallel to the edge, entirely outside playable space.
	rotation.y = PI / 2.0 if absf(nearest.x - center.x) < 0.01 else 0.0
	if not footprint.is_empty():
		global_position = Vector3.ZERO
		var min_x: int = footprint[0].x
		var max_x := min_x
		for cell: Vector3i in footprint:
			global_position += grid.grid_to_world(cell) / footprint.size()
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)
		rotation.y = PI / 2.0 if max_x - min_x == 3 else 0.0
		scale = Vector3.ONE * grid.cell_size
	if not enemy_owned:
		objectives = get_tree().get_first_node_in_group("objective_manager") as ObjectiveManager
		if objectives:
			var canvas := CanvasLayer.new()
			add_child(canvas)
			leave_button = Button.new()
			leave_button.text = "Leave"
			leave_button.visible = false
			canvas.add_child(leave_button)
			leave_button.pressed.connect(_request_leave)
			confirmation = ConfirmationDialog.new()
			confirmation.title = "Depart in transport"
			confirmation.ok_button_text = "Leave now"
			canvas.add_child(confirmation)
			confirmation.confirmed.connect(_confirm_leave)
	var body := Color(0.24, 0.29, 0.20)
	var accent := Color(1.0, 0.25, 0.1) if enemy_owned else Color(0.15, 0.9, 0.5)
	_box("Chassis", Vector3(1.65, 0.4, 3.5), Vector3(0, 0.6, 0), body)
	_box("Cab", Vector3(1.6, 1.0, 1.1), Vector3(0, 1.25, 1.05), body)
	_box("Windshield", Vector3(1.3, 0.4, 0.04), Vector3(0, 1.45, 1.62), Color(0.09, 0.18, 0.23))
	_box("PassengerCanopy", Vector3(1.6, 1.2, 2.0), Vector3(0, 1.35, -0.6), Color(0.32, 0.36, 0.25))
	_box("RearDoor", Vector3(1.2, 0.95, 0.05), Vector3(0, 1.2, -1.63), Color(0.08, 0.1, 0.08))
	_box("BoardingStep", Vector3(1.4, 0.15, 0.4), Vector3(0, 0.38, -1.85), body)
	for x in [-0.84, 0.84]:
		for z in [-1.1, 1.1]:
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.38
			mesh.bottom_radius = 0.38
			mesh.height = 0.22
			wheel.mesh = mesh
			wheel.rotation.z = PI / 2
			wheel.position = Vector3(x, 0.4, z)
			wheel.material_override = _material(Color(0.045, 0.045, 0.045))
			add_child(wheel)
	_box("Beacon", Vector3(0.55, 0.12, 0.3), Vector3(0, 1.82, 1.0), accent)
	var label := Label3D.new()
	label.text = "EVAC TRANSPORT"
	label.position.y = 2.4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.modulate = accent
	add_child(label)

func _box(part_name: String, size: Vector3, location: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = location
	part.material_override = _material(color)
	add_child(part)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
