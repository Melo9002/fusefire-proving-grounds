class_name FindingMarker
extends Node3D
## Draws one FINDING in the world: the recorded positions it is about (crosses for where the pose put things, diamonds for what was asked, lines between them, red crosses for offending mesh points) and a label,
## so "right shin vs ladder rung 10" can be seen on the body instead of read. It draws only what the recording holds (a row of SessionRecorder): nothing is looked up from the live rig, and it invents no
## geometry the environment did not supply (a rung is drawn only as a labelled point where the offending vertex is). One generic marker serves every animation family: it reads the finding's `subject` and the row.

const COLOUR_ACHIEVED := Color(0.2, 0.95, 1.0)
const COLOUR_INTENDED := Color(1.0, 0.85, 0.15)
const COLOUR_ERROR := Color(1.0, 0.15, 0.15)
const COLOUR_BONE := Color(1.0, 0.35, 0.95)

var _lines := MeshInstance3D.new()
var _mesh := ImmediateMesh.new()
var _label := Label3D.new()
var _open := false
## The world point the marker is centred on (for the camera), or Vector3.INF when nothing is shown.
var focus := Vector3.INF

static func attach(parent: Node) -> FindingMarker:
	var marker := FindingMarker.new()
	marker.name = "FindingMarker"
	parent.add_child(marker)
	return marker

func _ready() -> void:
	top_level = true
	_lines.mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_lines.material_override = material
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0016
	_label.font_size = 28
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.95, 0.6)
	add_child(_label)

func clear() -> void:
	_mesh.clear_surfaces()
	_label.text = ""
	focus = Vector3.INF

## A recorded character-space point as a world point, using the row's own root (the rows are history: the live root may have moved on).
static func world_of(row: Dictionary, point: Vector3) -> Vector3:
	return _vec(row.root) + Basis(Vector3.UP, float(row.yaw)) * point

## Shows `finding` at the moment of `row` (the finding's worst frame). Returns the world point the camera should look at.
func show_finding(finding: Dictionary, row: Dictionary) -> Vector3:
	clear()
	if row.is_empty():
		return focus
	_open = false
	var subject: Dictionary = finding.subject
	var points: Array[Vector3] = []
	for bone in subject.get("bones", []):
		var at: Variant = (row.bones as Dictionary).get(String(bone))
		if at != null:
			var world := world_of(row, _vec(at))
			points.append(world)
			_cross(world, 0.035, COLOUR_BONE)
	# What was asked against what was done, for the hand or foot the finding is about.
	var side := String(subject.get("side", ""))
	if String(finding.kind) in ["reach_exceeded", "target_error", "plant_slide", "plant_settle"]:
		for kind in [["hands", "target", "wrist"], ["feet", "planned", "ankle"]]:
			for entry: Dictionary in row.get(kind[0], []):
				if String(entry.name) == side and (String(subject.get("part", "")) == "hand") == (kind[0] == "hands"):
					_diamond(entry[kind[1]], 0.045, COLOUR_INTENDED)
					_cross(entry[kind[2]], 0.035, COLOUR_ACHIEVED)
					_line(entry[kind[1]], entry[kind[2]], COLOUR_ERROR)
					points.append(_vec(entry[kind[2]]))
	if row.has("mesh"):
		for offender: Dictionary in (row.mesh as Dictionary).get("top", []):
			var world := world_of(row, _vec(offender.point))
			_cross(world, 0.02, COLOUR_ERROR)
			points.append(world)
	if _open:
		_mesh.surface_end()
	if points.is_empty():
		points.append(_vec(row.root))
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	focus = centre / float(points.size())
	_label.global_position = focus + Vector3(0.0, 0.18, 0.0)
	_label.text = String(finding.title)
	return focus

static func _vec(v: Variant) -> Vector3:
	return v if v is Vector3 else Vector3(float(v[0]), float(v[1]), float(v[2]))

func _line(a: Variant, b: Variant, colour: Color) -> void:
	if not _open:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_open = true
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(_vec(a))
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(_vec(b))

func _cross(at: Variant, size: float, colour: Color) -> void:
	var p := _vec(at)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(p - axis * size, p + axis * size, colour)

func _diamond(at: Variant, size: float, colour: Color) -> void:
	var p := _vec(at)
	var tips := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for i in 6:
		for j in range(i + 1, 6):
			if (tips[i] as Vector3).dot(tips[j]) == 0.0:
				_line(p + (tips[i] as Vector3) * size, p + (tips[j] as Vector3) * size, colour)

func shutdown() -> void:
	queue_free()
