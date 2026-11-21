class_name PlaygroundHealthBar
extends Node3D
## A small world-space health bar (sandbox): a dark back and a fill that shrinks, always facing the camera.

const WIDTH := 0.9
const HEIGHT := 0.09

var _fill: MeshInstance3D


func _init() -> void:
	var back := _quad(Color(0.08, 0.08, 0.08, 0.85), 0)
	back.scale = Vector3(1.04, 1.5, 1.0)
	add_child(back)
	_fill = _quad(Color(0.85, 0.15, 0.12), 1)
	add_child(_fill)


func _quad(color: Color, priority: int) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	mesh_instance.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.render_priority = priority
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	return mesh_instance


## 1 is full, 0 is empty.
func set_fraction(fraction: float) -> void:
	var f := clampf(fraction, 0.001, 1.0)
	_fill.scale = Vector3(f, 1.0, 1.0)
	_fill.position = Vector3(-(1.0 - f) * WIDTH * 0.5, 0.0, 0.0)
	(_fill.material_override as StandardMaterial3D).albedo_color = Color(0.85, 0.15, 0.12).lerp(Color(0.2, 0.8, 0.25), clampf(fraction, 0.0, 1.0))
