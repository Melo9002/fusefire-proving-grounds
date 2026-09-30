class_name ShotTrajectoryVisualizer
extends Node3D

@export_range(0.01, 0.15, 0.005) var radius: float = 0.035
@export var debug_enabled: bool = true
@export var grid_manager: GridManager

var mesh_instance: MeshInstance3D
var blocker_marker: MeshInstance3D
var last_origin := Vector3.ZERO
var last_destination := Vector3.ZERO
var last_reason := ""
var last_blocking_cell: MapCellData

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	blocker_marker = MeshInstance3D.new()
	blocker_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blocker_marker)

func draw_trajectory(origin: Vector3, destination: Vector3, evaluation: CombatRules.AttackEvaluation) -> void:
	last_origin = origin
	last_destination = destination
	last_reason = evaluation.reason
	if not debug_enabled or origin.is_equal_approx(destination):
		clear()
		return

	var direction := destination - origin
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = direction.length()
	cylinder.radial_segments = 8
	cylinder.rings = 1
	mesh_instance.mesh = cylinder
	mesh_instance.position = (origin + destination) * 0.5
	mesh_instance.quaternion = Quaternion(Vector3.UP, direction.normalized())
	mesh_instance.material_override = _make_material(_get_color(evaluation))
	_draw_blocker(evaluation)

func clear() -> void:
	if mesh_instance:
		mesh_instance.mesh = null
	if blocker_marker:
		blocker_marker.mesh = null
	last_reason = ""
	last_blocking_cell = null

func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled
	if not enabled:
		clear()

func _get_color(evaluation: CombatRules.AttackEvaluation) -> Color:
	if not evaluation.is_legal:
		return Color(1.0, 0.15, 0.1, 0.65)
	if evaluation.cover_type != MapCellData.CoverType.NONE or evaluation.obstruction != "Clear":
		return Color(1.0, 0.72, 0.1, 0.65)
	return Color(0.2, 1.0, 0.45, 0.65)

func _draw_blocker(evaluation: CombatRules.AttackEvaluation) -> void:
	blocker_marker.mesh = null
	last_blocking_cell = null
	if evaluation.reason != "Blocked" or not grid_manager:
		return
	last_blocking_cell = evaluation.blocking_cell
	if not last_blocking_cell:
		return
	var box := BoxMesh.new()
	box.size = Vector3(grid_manager.cell_size * 0.92, last_blocking_cell.cover_height, grid_manager.cell_size * 0.92)
	blocker_marker.mesh = box
	blocker_marker.position = last_blocking_cell.world_position + Vector3.UP * last_blocking_cell.cover_height * 0.5
	blocker_marker.material_override = _make_material(Color(1.0, 0.05, 0.05, 0.28))

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 0.8
	material.no_depth_test = true
	return material
