extends Node3D
class_name PathVisualizer

@export var grid_manager: GridManager
@export_range(0.0, 0.3, 0.01) var tile_padding: float = 0.08

@export var range_color: Color = Color(0.55, 0.32, 0.0, 0.65)
@export var path_color: Color = Color(0, 0.5, 1, 0.5)

var range_mesh_instance: MeshInstance3D
var path_mesh_instance: MeshInstance3D
var _range_material: StandardMaterial3D
var _path_material: StandardMaterial3D
var _last_path := PackedVector3Array()
var _last_path_cell_size := -1.0
var _last_path_padding := -1.0

func _ready() -> void:
	range_mesh_instance = MeshInstance3D.new()
	add_child(range_mesh_instance)

	path_mesh_instance = MeshInstance3D.new()
	add_child(path_mesh_instance)
	if not grid_manager:
		grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
		if not grid_manager:
			grid_manager = get_node_or_null("../GridManager") as GridManager

	_initialize_materials()

func _initialize_materials() -> void:
	_range_material = _create_base_material(range_color)
	_path_material = _create_base_material(path_color)

	range_mesh_instance.material_override = _range_material
	path_mesh_instance.material_override = _path_material

func draw_range_zone(grid_positions: Array[Vector3i], color: Color = range_color) -> void:
	print_rich("[color=cyan][PathVisualizer][/color] draw_range_zone called with count: ", grid_positions.size())

	if grid_positions.is_empty() or not grid_manager:
		print_rich("[color=yellow][PathVisualizer][/color] Bailed out! grid_positions empty: %s, grid_manager valid: %s" % [grid_positions.is_empty(), grid_manager != null])
		clear_range_zone()
		return

	_range_material.albedo_color = color
	var generated_mesh = _build_grid_mesh(grid_positions, 0.03)

	if not generated_mesh:
		print_rich("[color=red][PathVisualizer][/color] Error: _build_grid_mesh returned a null mesh!")
	else:
		print_rich("[color=green][PathVisualizer][/color] Mesh generated successfully. Vertex count: ", generated_mesh.get_faces().size())

	range_mesh_instance.mesh = generated_mesh

func draw_path(path_vectors: PackedVector3Array, color: Color = path_color) -> void:
	if path_vectors.size() < 1 or not grid_manager:
		clear_path()
		return

	_path_material.albedo_color = color
	# Color is independent of geometry. Preserve the mesh when only tint changes.
	if path_mesh_instance.mesh != null and path_vectors == _last_path \
		and grid_manager.cell_size == _last_path_cell_size and tile_padding == _last_path_padding:
		return
	_last_path = path_vectors.duplicate()
	_last_path_cell_size = grid_manager.cell_size
	_last_path_padding = tile_padding
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var visual_cell_size = grid_manager.cell_size * (1.0 - tile_padding)
	var half = visual_cell_size / 2.0

	for pos in path_vectors:
		var y = pos.y + 0.06 # Layer path slightly higher to prevent Z-fighting

		var v1 = Vector3(pos.x - half, y, pos.z - half)
		var v2 = Vector3(pos.x + half, y, pos.z - half)
		var v3 = Vector3(pos.x + half, y, pos.z + half)
		var v4 = Vector3(pos.x - half, y, pos.z + half)

		st.add_vertex(v1); st.add_vertex(v2); st.add_vertex(v3)
		st.add_vertex(v1); st.add_vertex(v3); st.add_vertex(v4)

	st.generate_normals()
	path_mesh_instance.mesh = st.commit()

func _build_grid_mesh(grid_positions: Array[Vector3i], y_offset: float) -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var visual_cell_size = grid_manager.cell_size * (1.0 - tile_padding)
	var half = visual_cell_size / 2.0

	for pos in grid_positions:
		var world_pos = grid_manager.grid_to_world(pos)
		var y = world_pos.y + y_offset

		var v1 = Vector3(world_pos.x - half, y, world_pos.z - half)
		var v2 = Vector3(world_pos.x + half, y, world_pos.z - half)
		var v3 = Vector3(world_pos.x + half, y, world_pos.z + half)
		var v4 = Vector3(world_pos.x - half, y, world_pos.z + half)

		st.add_vertex(v1); st.add_vertex(v2); st.add_vertex(v3)
		st.add_vertex(v1); st.add_vertex(v3); st.add_vertex(v4)

	st.generate_normals()
	return st.commit()

func _create_base_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.resource_local_to_scene = true
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = StandardMaterial3D.CULL_DISABLED
	return mat

func clear_range_zone() -> void:
	range_mesh_instance.mesh = null

func clear_path() -> void:
	if path_mesh_instance.mesh != null:
		path_mesh_instance.mesh = null
	_last_path.clear()
