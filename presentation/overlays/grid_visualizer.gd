extends MeshInstance3D
class_name GridVisualizer

@export var cell_size: float = 1.0
@export var grid_color: Color = Color(0.0, 1.0, 1.0, 0.5)
@export var target_floor: CSGBox3D

func _ready() -> void:
	if not target_floor:
		push_error("CRITICAL: GridVisualizer is missing its target_floor! Assign it in the Inspector.")
		return
	generate_grid_lines()

func generate_grid_lines() -> void:
	var imm_mesh = ImmediateMesh.new()
	self.mesh = imm_mesh

	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = grid_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var floor_dimensions = target_floor.size
	var half_width = floor_dimensions.x / 2.0
	var half_depth = floor_dimensions.z / 2.0
	var grid_width = int(floor_dimensions.x / cell_size)
	var grid_depth = int(floor_dimensions.z / cell_size)
	var y_offset = 0.01 # Prevent Z-fighting visual flicker
	for i in range(grid_depth + 1):
		var z = (i * cell_size) - half_depth
		imm_mesh.surface_add_vertex(Vector3(-half_width, y_offset, z))
		imm_mesh.surface_add_vertex(Vector3(half_width, y_offset, z))
	for i in range(grid_width + 1):
		var x = (i * cell_size) - half_width
		imm_mesh.surface_add_vertex(Vector3(x, y_offset, -half_depth))
		imm_mesh.surface_add_vertex(Vector3(x, y_offset, half_depth))

	imm_mesh.surface_end()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"): # 'TAB' Key
		visible = not visible
