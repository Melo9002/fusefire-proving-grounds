class_name CoverVisualizer
extends Node3D

@export var grid_manager: GridManager
@export var low_cover_color := Color(0.2, 0.85, 1.0, 0.95)
@export var full_cover_color := Color(1.0, 0.7, 0.15, 0.95)
@export_range(0.05, 0.3, 0.01) var edge_width := 0.12

var low_indicator_count := 0
var full_indicator_count := 0
var _low_mesh := MeshInstance3D.new()
var _full_mesh := MeshInstance3D.new()

const DIRECTIONS: Array[Vector3i] = [
	Vector3i.RIGHT,
	Vector3i.LEFT,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

func _ready() -> void:
	add_child(_low_mesh)
	add_child(_full_mesh)
	_low_mesh.material_override = _create_material(low_cover_color)
	_full_mesh.material_override = _create_material(full_cover_color)

func draw_for_cells(destination_cells: Array[Vector3i]) -> void:
	var low_edges: Array = []
	var full_edges: Array = []
	for cell in destination_cells:
		for direction in DIRECTIONS:
			var cover = grid_manager.get_cell_data(cell + direction)
			if not cover or cover.cover_type == MapCellData.CoverType.NONE:
				continue
			var edge = [cell, direction]
			if cover.cover_type == MapCellData.CoverType.FULL:
				full_edges.append(edge)
			else:
				low_edges.append(edge)

	low_indicator_count = low_edges.size()
	full_indicator_count = full_edges.size()
	_low_mesh.mesh = _build_edge_mesh(low_edges)
	_full_mesh.mesh = _build_edge_mesh(full_edges)

func clear() -> void:
	low_indicator_count = 0
	full_indicator_count = 0
	_low_mesh.mesh = null
	_full_mesh.mesh = null

func _build_edge_mesh(edges: Array) -> Mesh:
	if edges.is_empty():
		return null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half = grid_manager.cell_size * 0.46
	for edge in edges:
		_add_edge(surface, grid_manager.grid_to_world(edge[0]), edge[1], half)
	surface.generate_normals()
	return surface.commit()

func _add_edge(surface: SurfaceTool, center: Vector3, direction: Vector3i, half: float) -> void:
	var outer_a: Vector3
	var outer_b: Vector3
	var inner_a: Vector3
	var inner_b: Vector3
	var y = center.y + 0.07
	if direction.x != 0:
		var outer_x = center.x + direction.x * half
		var inner_x = outer_x - direction.x * edge_width
		outer_a = Vector3(outer_x, y, center.z - half)
		outer_b = Vector3(outer_x, y, center.z + half)
		inner_a = Vector3(inner_x, y, center.z - half)
		inner_b = Vector3(inner_x, y, center.z + half)
	else:
		var outer_z = center.z + direction.z * half
		var inner_z = outer_z - direction.z * edge_width
		outer_a = Vector3(center.x - half, y, outer_z)
		outer_b = Vector3(center.x + half, y, outer_z)
		inner_a = Vector3(center.x - half, y, inner_z)
		inner_b = Vector3(center.x + half, y, inner_z)

	surface.add_vertex(outer_a)
	surface.add_vertex(outer_b)
	surface.add_vertex(inner_b)
	surface.add_vertex(outer_a)
	surface.add_vertex(inner_b)
	surface.add_vertex(inner_a)

func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
