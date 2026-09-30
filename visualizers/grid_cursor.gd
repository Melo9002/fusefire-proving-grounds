extends MeshInstance3D
class_name GridCursor

@export var grid_manager: GridManager
@export var highlight_color: Color = Color(1.0, 0.0, 0.0, 0.4)

func _ready() -> void:
	mesh = _build_cursor_mesh(grid_manager.cell_size if grid_manager else 1.0)
	material_override = _create_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_cursor_mesh(cell_size: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := cell_size * 0.5
	var a := Vector3(-half, 0.0, -half)
	var b := Vector3(half, 0.0, -half)
	var c := Vector3(half, 0.0, half)
	var d := Vector3(-half, 0.0, half)
	surface.add_vertex(a); surface.add_vertex(b); surface.add_vertex(c)
	surface.add_vertex(a); surface.add_vertex(c); surface.add_vertex(d)
	return surface.commit()

func _create_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = highlight_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func update_hover_position(raw_position: Vector3) -> void:
	if not grid_manager:
		return

	var center = grid_manager.get_tile_center(raw_position)
	global_position = Vector3(center.x, center.y + 0.08, center.z)
