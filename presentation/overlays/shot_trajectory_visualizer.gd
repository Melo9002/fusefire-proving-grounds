class_name ShotTrajectoryVisualizer
extends Node3D

@export_range(0.01, 0.15, 0.005) var radius: float = 0.035
@export var debug_enabled: bool = false
@export var grid_manager: GridManager

var mesh_instance: MeshInstance3D
var blocker_marker: MeshInstance3D
var destination_lines: Array[ShotTrajectoryVisualizer] = []

var last_origin := Vector3.ZERO
var last_destination := Vector3.ZERO
var last_line_end := Vector3.ZERO
var last_reason := ""
var last_blocking_cell: MapCellData

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	blocker_marker = MeshInstance3D.new()
	blocker_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blocker_marker)

func draw_trajectory(origin: Vector3, destination: Vector3, evaluation: CombatRules.AttackEvaluation, targeting := false, action_available := true) -> void:
	if evaluation.firing_solution:
		origin = evaluation.firing_solution.origin
		destination = evaluation.firing_solution.aim_point()
	last_origin = origin
	last_destination = destination
	last_reason = evaluation.reason
	if (not debug_enabled and not targeting) or origin.is_equal_approx(destination):
		clear()
		return

	# The explained sample can extend beyond a blocker, but the drawn line cannot.
	last_line_end = destination if evaluation.is_legal else origin
	if evaluation.reason == "Blocked" and evaluation.blocking_point.is_finite():
		last_line_end = evaluation.blocking_point
	_draw_blocker(evaluation)
	var direction := last_line_end - origin
	if direction.is_zero_approx():
		mesh_instance.mesh = null
		return
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = direction.length()
	cylinder.radial_segments = 8
	cylinder.rings = 1
	mesh_instance.mesh = cylinder
	mesh_instance.position = (origin + last_line_end) * 0.5
	mesh_instance.quaternion = Quaternion(Vector3.UP, direction.normalized())
	mesh_instance.material_override = _make_material(_get_color(evaluation, action_available))

func clear() -> void:
	if mesh_instance:
		mesh_instance.mesh = null
	if blocker_marker:
		blocker_marker.mesh = null
	last_reason = ""
	last_blocking_cell = null

func draw_destination_options(actor: TacticalUnit, destination: Vector3i, options: Array[Dictionary]) -> void:
	clear_destination_options()
	var origin := CombatRules.get_support_position(destination, grid_manager) + Vector3.UP * actor.standing_height
	# Show clear lanes in the overview. Keep obstruction details for a
	# single inspected target or debug mode, where the marker has context.
	var overview := options.size() > 1 and not debug_enabled
	for option in options:
		var evaluation: CombatRules.AttackEvaluation = option.outgoing
		if overview and not evaluation.is_legal: continue
		var line := ShotTrajectoryVisualizer.new()
		line.grid_manager = grid_manager
		add_child(line)
		destination_lines.append(line)
		line.draw_trajectory(origin, evaluation.aim_point, evaluation, true, option.unavailable.is_empty())

func clear_destination_options() -> void:
	for line in destination_lines: line.free()
	destination_lines.clear()

func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled
	if not enabled:
		clear()

func _get_color(evaluation: CombatRules.AttackEvaluation, action_available := true) -> Color:
	var color := TacticalFeedbackText.chance_color(evaluation.hit_chance, evaluation.is_legal and action_available)
	color.a = 0.75
	return color

func _draw_blocker(evaluation: CombatRules.AttackEvaluation) -> void:
	blocker_marker.mesh = null
	last_blocking_cell = null
	if evaluation.reason != "Blocked" or not grid_manager:
		return
	last_blocking_cell = evaluation.blocking_cell
	if not last_blocking_cell:
		return
	if evaluation.blocking_point.is_finite() and not debug_enabled:
		var impact := SphereMesh.new()
		impact.radius = 0.085
		impact.height = 0.17
		blocker_marker.mesh = impact
		blocker_marker.position = evaluation.blocking_point
		blocker_marker.material_override = _make_material(Color(1.0, 0.23, 0.16, 1.0))
		return
	var box := BoxMesh.new()
	box.size = Vector3(grid_manager.cell_size * 0.92, last_blocking_cell.cover_height, grid_manager.cell_size * 0.92)
	blocker_marker.mesh = box
	blocker_marker.position = last_blocking_cell.world_position + Vector3.UP * last_blocking_cell.cover_height * 0.5
	if last_blocking_cell.authored_shot_bounds.has_volume():
		box.size = last_blocking_cell.authored_shot_bounds.size
		blocker_marker.position = last_blocking_cell.authored_shot_bounds.get_center()
	if evaluation.blocking_bounds.has_volume():
		box.size = evaluation.blocking_bounds.size
		blocker_marker.position = evaluation.blocking_bounds.get_center()
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
