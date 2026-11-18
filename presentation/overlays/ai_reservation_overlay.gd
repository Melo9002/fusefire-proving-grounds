class_name AIReservationOverlay
extends Node3D
## Developer overlay: what the squads have claimed this round. Read-only; it draws entries
## the F3 panel collects from the existing squad contexts and never creates or changes one.
##   destination (cyan square + owner)  corridor (green)  focus target (magenta diamond)

@export var grid_manager: GridManager
@export var destination_color := Color(0.2, 0.9, 1.0, 0.62)
@export var corridor_color := Color(0.3, 1.0, 0.45, 0.4)
@export var target_color := Color(1.0, 0.35, 0.85, 0.78)
@export_range(1, 24, 1) var max_labels := 12

var overlay_enabled := false
var latest_entries: Array[Dictionary] = []
var _mesh := MeshInstance3D.new()
var _labels := Node3D.new()

func _init() -> void:
	_mesh.name = "Reservations"
	_labels.name = "ReservationLabels"
	add_child(_mesh)
	add_child(_labels)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_mesh.material_override = material
	visible = false

func set_overlay_enabled(enabled: bool) -> void:
	overlay_enabled = enabled
	visible = enabled
	if enabled: show_entries(latest_entries)
	else: clear()

## entries: {"cell": Vector3i, "kind": "destination" | "corridor" | "target", "owner": String}
func show_entries(entries: Array[Dictionary]) -> void:
	latest_entries = entries
	if not overlay_enabled or not grid_manager:
		return
	_clear_labels()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var labelled := 0
	for entry in entries:
		var data := grid_manager.get_cell_data(entry.cell)
		if data == null: continue
		var center := data.world_position
		match String(entry.kind):
			"corridor": _quad(surface, center + Vector3.UP * 0.1, grid_manager.cell_size * 0.3, corridor_color)
			"target": _diamond(surface, center + Vector3.UP * 0.22, grid_manager.cell_size * 0.5, target_color)
			_:
				_quad(surface, center + Vector3.UP * 0.12, grid_manager.cell_size * 0.4, destination_color)
				if labelled < max_labels and not String(entry.get("owner", "")).is_empty():
					labelled += 1
					_label(String(entry.owner), center + Vector3.UP * 0.35)
	_mesh.mesh = surface.commit()

func clear() -> void:
	_mesh.mesh = null
	_clear_labels()

func entry_count(kind: String) -> int:
	return latest_entries.filter(func(entry: Dictionary) -> bool: return entry.kind == kind).size()

func _clear_labels() -> void:
	for child in _labels.get_children():
		child.queue_free()

func _label(text: String, position_value: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = position_value
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.font_size = 48
	label.pixel_size = 0.0009
	label.outline_size = 5
	label.modulate = Color(0.75, 1.0, 1.0)
	label.no_depth_test = true
	_labels.add_child(label)

func _quad(surface: SurfaceTool, center: Vector3, half: float, color: Color) -> void:
	var a := center + Vector3(-half, 0, -half)
	var b := center + Vector3(half, 0, -half)
	var c := center + Vector3(half, 0, half)
	var d := center + Vector3(-half, 0, half)
	_triangle(surface, a, b, c, color)
	_triangle(surface, a, c, d, color)

func _diamond(surface: SurfaceTool, center: Vector3, half: float, color: Color) -> void:
	var north := center + Vector3(0, 0, -half)
	var east := center + Vector3(half, 0, 0)
	var south := center + Vector3(0, 0, half)
	var west := center + Vector3(-half, 0, 0)
	_triangle(surface, north, east, south, color)
	_triangle(surface, north, south, west, color)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color); surface.add_vertex(a)
	surface.set_color(color); surface.add_vertex(b)
	surface.set_color(color); surface.add_vertex(c)
