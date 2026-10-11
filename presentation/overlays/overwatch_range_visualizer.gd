extends Node3D
class_name OverwatchRangeVisualizer

## Read-only presentation of the potential range currently guarded by friendly
## Overwatch. Cover and line of sight are still evaluated at each real trigger;
## TacticalActionService remains the authority for whether a reaction is legal.

@export var grid_manager: GridManager
@export var guard_color := Color(0.58, 0.24, 0.88, 0.28)
@export_range(0.0, 0.3, 0.01) var tile_padding := 0.12

var displayed_cells: Array[Vector3i] = []
var _mesh_instance: MeshInstance3D

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GuardedCells"
	add_child(_mesh_instance)
	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = guard_color
	material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = StandardMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = material

func show_cells(cells: Array[Vector3i]) -> void:
	displayed_cells.assign(cells)
	displayed_cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x < b.x or (a.x == b.x and (a.z < b.z or (a.z == b.z and a.y < b.y))))
	if displayed_cells.is_empty() or not is_instance_valid(grid_manager):
		clear()
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := grid_manager.cell_size * (1.0 - tile_padding) * 0.5
	for cell in displayed_cells:
		var center := grid_manager.grid_to_world(cell) + Vector3.UP * 0.045
		var a := center + Vector3(-half, 0.0, -half)
		var b := center + Vector3(half, 0.0, -half)
		var c := center + Vector3(half, 0.0, half)
		var d := center + Vector3(-half, 0.0, half)
		surface.add_vertex(a); surface.add_vertex(b); surface.add_vertex(c)
		surface.add_vertex(a); surface.add_vertex(c); surface.add_vertex(d)
	surface.generate_normals()
	_mesh_instance.mesh = surface.commit()

func clear() -> void:
	displayed_cells.clear()
	if is_instance_valid(_mesh_instance):
		_mesh_instance.mesh = null
