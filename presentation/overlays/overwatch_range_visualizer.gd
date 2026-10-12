extends Node3D
class_name OverwatchRangeVisualizer

## Read-only presentation of the same range and line-of-sight cells used by the
## Attack preview. TacticalActionService still revalidates every real trigger.

@export var grid_manager: GridManager
@export var preview_color := Color(0.58, 0.24, 0.88, 0.28)
@export var committed_guard_color := Color(0.24, 0.08, 0.38, 0.42)
@export_range(0.0, 0.3, 0.01) var tile_padding := 0.12

var displayed_cells: Array[Vector3i] = []
var preview_cells: Array[Vector3i] = []
var committed_cells: Array[Vector3i] = []
var _preview_mesh: MeshInstance3D
var _committed_mesh: MeshInstance3D

func _ready() -> void:
	_preview_mesh = _create_mesh_instance("GuardPreviewCells", preview_color)
	_committed_mesh = _create_mesh_instance("GuardedCells", committed_guard_color)

func _create_mesh_instance(node_name: String, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	add_child(mesh_instance)
	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = StandardMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	return mesh_instance

func show_cells(cells: Array[Vector3i]) -> void:
	show_ranges(cells, [])

func show_ranges(pending_cells: Array[Vector3i], active_cells: Array[Vector3i]) -> void:
	preview_cells.assign(pending_cells)
	committed_cells.assign(active_cells)
	displayed_cells.assign(committed_cells)
	for cell in preview_cells:
		if not displayed_cells.has(cell): displayed_cells.append(cell)
	_sort_cells(preview_cells)
	_sort_cells(committed_cells)
	_sort_cells(displayed_cells)
	_draw_cells(_preview_mesh, preview_cells, 0.05)
	_draw_cells(_committed_mesh, committed_cells, 0.045)

func _sort_cells(cells: Array[Vector3i]) -> void:
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x < b.x or (a.x == b.x and (a.z < b.z or (a.z == b.z and a.y < b.y))))

func _draw_cells(mesh_instance: MeshInstance3D, cells: Array[Vector3i], height: float) -> void:
	if not is_instance_valid(mesh_instance):
		return
	if cells.is_empty() or not is_instance_valid(grid_manager):
		mesh_instance.mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := grid_manager.cell_size * (1.0 - tile_padding) * 0.5
	for cell in cells:
		var center := grid_manager.grid_to_world(cell) + Vector3.UP * height
		var a := center + Vector3(-half, 0.0, -half)
		var b := center + Vector3(half, 0.0, -half)
		var c := center + Vector3(half, 0.0, half)
		var d := center + Vector3(-half, 0.0, half)
		surface.add_vertex(a); surface.add_vertex(b); surface.add_vertex(c)
		surface.add_vertex(a); surface.add_vertex(c); surface.add_vertex(d)
	surface.generate_normals()
	mesh_instance.mesh = surface.commit()

func clear() -> void:
	displayed_cells.clear()
	preview_cells.clear()
	committed_cells.clear()
	if is_instance_valid(_preview_mesh): _preview_mesh.mesh = null
	if is_instance_valid(_committed_mesh): _committed_mesh.mesh = null
