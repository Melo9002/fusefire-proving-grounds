class_name AIScoringOverlay
extends Node3D

@export var grid_manager: GridManager
@export_group("Heatmap")
## Lowest legal movement scores. Violet avoids movement-range cyan and attack red.
@export var cold_color := Color(0.18, 0.08, 0.42, 0.42)
@export var middle_color := Color(0.62, 0.16, 0.62, 0.58)
## Highest legal movement scores.
@export var hot_color := Color(1.0, 0.55, 0.06, 0.82)
@export var chosen_color := Color(1.0, 0.92, 0.25, 0.96)
@export var rejected_color := Color(0.20, 0.16, 0.26, 0.24)
## Rejected cells are normally omitted for faster, clearer large-map diagnostics.
@export var show_rejected_cells := false
@export_group("Score Labels")
## Optional exact values for close inspection. The heatmap is the readable default.
@export var show_numeric_labels := false
## Maximum legal destinations labelled at once. The chosen destination is always included.
@export_range(1, 20, 1) var max_score_labels := 8
## High resolution keeps labels sharp; Pixel Size controls their apparent size.
@export_range(24, 128, 1) var label_font_resolution := 64
@export_range(0.0005, 0.005, 0.0001, "suffix:m/px") var label_pixel_size := 0.0010
@export_range(0, 16, 1) var label_outline_size := 5
@export_group("")

var overlay_enabled := false
var latest_record: Dictionary = {}
var _position_mesh := MeshInstance3D.new()
var _target_mesh := MeshInstance3D.new()
var _score_labels := Node3D.new()

func _ready() -> void:
	_position_mesh.name = "PositionScores"
	_target_mesh.name = "TargetScores"
	_score_labels.name = "MovementScoreLabels"
	add_child(_position_mesh)
	add_child(_target_mesh)
	add_child(_score_labels)
	_position_mesh.material_override = _material()
	_target_mesh.material_override = _material()
	visible = false

func set_overlay_enabled(enabled: bool) -> void:
	overlay_enabled = enabled
	visible = enabled
	if enabled and not latest_record.is_empty():
		display(latest_record)
	elif not enabled:
		clear()

func display(record: Dictionary) -> void:
	# BattleController already emits an owned diagnostic snapshot. Retaining it avoids
	# another deep copy of hundreds of candidate dictionaries on large maps.
	latest_record = record
	if not overlay_enabled or not grid_manager:
		return
	var position_candidates: Array = record.get("position_candidates", [])
	_position_mesh.mesh = _build_position_mesh(position_candidates)
	_target_mesh.mesh = _build_target_mesh(record.get("target_candidates", []))
	_build_score_labels(position_candidates)

func clear() -> void:
	_position_mesh.mesh = null
	_target_mesh.mesh = null
	_clear_score_labels()

func _build_position_mesh(candidates: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var score_range := _score_range(candidates)
	for candidate in candidates:
		if not candidate.has("cell"):
			continue
		if candidate.get("status", "") == "rejected" and not show_rejected_cells:
			continue
		var cell := grid_manager.get_cell_data(candidate.cell)
		if not cell:
			continue
		var color := _candidate_color(candidate, score_range)
		var half := grid_manager.cell_size * (0.43 if candidate.get("chosen", false) else 0.31)
		_add_quad(surface, cell.world_position + Vector3.UP * 0.16, half, color)
	return surface.commit()

func _build_score_labels(candidates: Array) -> void:
	_clear_score_labels()
	if not show_numeric_labels:
		return
	var labelled: Array = candidates.filter(func(candidate: Dictionary):
		return candidate.get("status", "") != "rejected" and candidate.has("score") and candidate.has("cell")
	)
	labelled.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) > float(b.score))
	labelled = labelled.slice(0, max_score_labels)
	var chosen: Dictionary = {}
	for candidate in candidates:
		if candidate.get("chosen", false):
			chosen = candidate
			break
	if not chosen.is_empty() and chosen not in labelled:
		if labelled.size() >= max_score_labels:
			labelled.pop_back()
		labelled.append(chosen)
	for candidate in labelled:
		var cell := grid_manager.get_cell_data(candidate.cell)
		if not cell:
			continue
		var label := Label3D.new()
		label.text = "%+.0f" % float(candidate.score)
		label.position = cell.world_position + Vector3.UP * 0.3
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.font_size = label_font_resolution
		label.pixel_size = label_pixel_size
		label.outline_size = label_outline_size
		label.modulate = Color(0.15, 1.0, 1.0) if candidate.get("chosen", false) else Color.WHITE
		label.no_depth_test = true
		_score_labels.add_child(label)

func _clear_score_labels() -> void:
	for child in _score_labels.get_children():
		child.queue_free()

func _build_target_mesh(candidates: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var score_range := _score_range(candidates)
	for candidate in candidates:
		if not candidate.has("cell"):
			continue
		if candidate.get("status", "") == "rejected" and not show_rejected_cells:
			continue
		var cell := grid_manager.get_cell_data(candidate.cell)
		if not cell:
			continue
		var color := _candidate_color(candidate, score_range)
		var half := grid_manager.cell_size * (0.36 if candidate.get("chosen", false) else 0.24)
		var center := cell.world_position + Vector3.UP * 0.2
		_add_diamond(surface, center, half, color)
	return surface.commit()

func _candidate_color(candidate: Dictionary, score_range: Vector2) -> Color:
	if candidate.get("chosen", false):
		return chosen_color
	if candidate.get("status", "") == "rejected":
		return rejected_color
	var score := float(candidate.get("score", 0.0))
	var ratio := 0.5 if is_equal_approx(score_range.x, score_range.y) else inverse_lerp(score_range.x, score_range.y, score)
	if ratio < 0.5:
		return cold_color.lerp(middle_color, ratio * 2.0)
	return middle_color.lerp(hot_color, (ratio - 0.5) * 2.0)

func _score_range(candidates: Array) -> Vector2:
	var minimum := INF
	var maximum := -INF
	for candidate in candidates:
		if candidate.get("status", "") == "rejected" or not candidate.has("score"):
			continue
		minimum = minf(minimum, float(candidate.score))
		maximum = maxf(maximum, float(candidate.score))
	return Vector2(0.0, 0.0) if minimum == INF else Vector2(minimum, maximum)

func _add_quad(surface: SurfaceTool, center: Vector3, half: float, color: Color) -> void:
	var a := center + Vector3(-half, 0, -half)
	var b := center + Vector3(half, 0, -half)
	var c := center + Vector3(half, 0, half)
	var d := center + Vector3(-half, 0, half)
	_triangle(surface, a, b, c, color)
	_triangle(surface, a, c, d, color)

func _add_diamond(surface: SurfaceTool, center: Vector3, half: float, color: Color) -> void:
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

func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	return material

