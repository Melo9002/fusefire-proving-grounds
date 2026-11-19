class_name HandContactOverlay
extends Node3D
## Debug geometry for hand-to-weapon contact, drawn from a HandContactSampler sample. Created only by
## HandContactDiagnostics when diagnostics are switched on, and freed when they are switched off, so
## normal gameplay never carries it. World-space (top_level): it ignores the rig's own scale and rotation.
##
## Colour key (also in the readout legend):
##   dominant hand  IK target orange, wrist yellow        support hand  IK target blue, wrist cyan
##   palm (approx, from bones) magenta     intended palm (from the weapon profile) green
##   weapon references white     elbow violet     elbow pole pink     fingertips = their hand's wrist colour
##   target-to-wrist lines in the hand's colour; palm-to-intended line red
##   reach line (shoulder to wrist): green at a relaxed arm, to red as the arm runs out of length
##   axes from each palm: finger direction red (actual) / pale red (intended); palm normal lime (actual) / pale lime (intended)

const COLOR_DOMINANT_TARGET := Color(1.0, 0.55, 0.1)
const COLOR_DOMINANT_WRIST := Color(1.0, 0.92, 0.2)
const COLOR_SUPPORT_TARGET := Color(0.25, 0.5, 1.0)
const COLOR_SUPPORT_WRIST := Color(0.2, 0.95, 1.0)
const COLOR_PALM := Color(1.0, 0.2, 0.85)
const COLOR_INTENDED_PALM := Color(0.2, 1.0, 0.4)
const COLOR_WEAPON := Color(1.0, 1.0, 1.0)
const COLOR_ELBOW := Color(0.7, 0.4, 1.0)
const COLOR_POLE := Color(1.0, 0.5, 0.7)
const COLOR_PALM_ERROR := Color(1.0, 0.15, 0.15)
const COLOR_FINGER := Color(1.0, 0.2, 0.2)
const COLOR_FINGER_INTENDED := Color(1.0, 0.72, 0.72)
const COLOR_NORMAL := Color(0.6, 1.0, 0.2)
const COLOR_NORMAL_INTENDED := Color(0.82, 1.0, 0.65)
## Display ramp for the reach line: this fraction of the arm's length is green, the full length is red.
## A drawing scale only: it is not a limit and nothing is judged against it.
const REACH_GREEN_FRACTION := 0.80
const MARKER_RADIUS := 0.010
const FINGERTIP_RADIUS := 0.0055
const LINE_RADIUS := 0.0028
const AXIS_LENGTH := 0.07
## Pixel offsets that keep the labels of neighbouring markers from sitting on one another (Label3D.offset).
## Dominant-hand labels stack up and to the left, support-hand labels down and to the right.
const LABEL_OFFSETS := {
	"dominant_ik": Vector2(-64, -26), "dominant_wrist": Vector2(-64, -52), "dominant_palm": Vector2(-64, 26), "dominant_intended_palm": Vector2(-64, 52),
	"dominant_elbow": Vector2(-50, -20), "dominant_pole": Vector2(50, -20),
	"support_ik": Vector2(64, 26), "support_wrist": Vector2(64, 52), "support_palm": Vector2(64, -26), "support_intended_palm": Vector2(64, -52),
	"support_elbow": Vector2(50, 20), "support_pole": Vector2(-50, 20),
	"stock": Vector2(0, -26), "firing_grip": Vector2(-20, 30), "support_grip": Vector2(20, 30),
}

var labels_visible := false
var _markers: Dictionary = {}
var _labels: Dictionary = {}
var _segments: Array[MeshInstance3D] = []
var _segments_used := 0
var _materials: Dictionary = {}
var _sphere: SphereMesh
var _cylinder: CylinderMesh

func _init() -> void:
	name = "HandContactOverlay"
	top_level = true
	_sphere = SphereMesh.new()
	_sphere.radial_segments = 12
	_sphere.rings = 6
	_cylinder = CylinderMesh.new()
	_cylinder.top_radius = 1.0
	_cylinder.bottom_radius = 1.0
	_cylinder.height = 1.0
	_cylinder.radial_segments = 6
	_cylinder.rings = 1
	_cylinder.cap_top = false
	_cylinder.cap_bottom = false

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Visible through the body and the weapon, and drawn last, so it stays legible in any pose.
		material.no_depth_test = true
		material.render_priority = 100
		_materials[key] = material
	return _materials[key]

func _marker(key: String, position_value: Vector3, color: Color, radius: float, label_text := "") -> void:
	var marker: MeshInstance3D = _markers.get(key)
	if marker == null:
		marker = MeshInstance3D.new()
		marker.mesh = _sphere
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
		_markers[key] = marker
	marker.visible = position_value.is_finite()
	if not marker.visible:
		return
	marker.material_override = _material(color)
	marker.global_position = position_value
	marker.scale = Vector3.ONE * radius * 2.0
	var label: Label3D = _labels.get(key)
	if label_text.is_empty():
		if label: label.visible = false
		return
	if label == null:
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0007
		label.font_size = 24
		label.outline_size = 7
		label.offset = LABEL_OFFSETS.get(key, Vector2(0, -24))
		label.render_priority = 101
		label.outline_render_priority = 100
		add_child(label)
		_labels[key] = label
	label.text = label_text
	label.modulate = color
	label.global_position = position_value
	label.visible = labels_visible

func _segment(from_point: Vector3, to_point: Vector3, color: Color, radius := LINE_RADIUS) -> void:
	if not from_point.is_finite() or not to_point.is_finite():
		return
	var length := from_point.distance_to(to_point)
	if length < 0.0005:
		return
	var segment: MeshInstance3D
	if _segments_used < _segments.size():
		segment = _segments[_segments_used]
	else:
		segment = MeshInstance3D.new()
		segment.mesh = _cylinder
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(segment)
		_segments.append(segment)
	_segments_used += 1
	segment.visible = true
	segment.material_override = _material(color)
	var up := (to_point - from_point) / length
	var helper := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
	var x_axis := up.cross(helper).normalized()
	var z_axis := x_axis.cross(up).normalized()
	segment.global_transform = Transform3D(Basis(x_axis * radius, up * length, z_axis * radius), (from_point + to_point) * 0.5)

static func reach_color(fraction: float) -> Color:
	var amount := clampf((fraction - REACH_GREEN_FRACTION) / (1.0 - REACH_GREEN_FRACTION), 0.0, 1.0)
	return Color(0.2, 1.0, 0.3).lerp(Color(1.0, 0.15, 0.1), amount)

## Redraws everything from one sample. Cheap enough to run every skeleton update while diagnostics are on.
func show_sample(sample: Dictionary) -> void:
	_segments_used = 0
	if sample.is_empty():
		hide_all()
		return
	var points: Dictionary = sample.points
	_marker("stock", points.stock, COLOR_WEAPON, MARKER_RADIUS, "stock")
	_marker("firing_grip", points.firing_grip, COLOR_WEAPON, MARKER_RADIUS, "grip")
	_marker("support_grip", points.support_grip, COLOR_WEAPON, MARKER_RADIUS, "front")
	var prefixes := ["R", "L"]
	var target_colors := [COLOR_DOMINANT_TARGET, COLOR_SUPPORT_TARGET]
	var wrist_colors := [COLOR_DOMINANT_WRIST, COLOR_SUPPORT_WRIST]
	for hand in 2:
		var data: Dictionary = (sample.hands as Array)[hand]
		var prefix: String = prefixes[hand]
		var key_prefix: String = String(data.name)
		var target_color: Color = target_colors[hand]
		var wrist_color: Color = wrist_colors[hand]
		_marker(key_prefix + "_ik", data.ik_target, target_color, MARKER_RADIUS, "%s IK" % prefix)
		_marker(key_prefix + "_wrist", data.wrist, wrist_color, MARKER_RADIUS, "%s wrist" % prefix)
		_marker(key_prefix + "_elbow", data.elbow, COLOR_ELBOW, MARKER_RADIUS * 0.8, "%s elbow" % prefix)
		_marker(key_prefix + "_pole", data.pole, COLOR_POLE, MARKER_RADIUS * 0.8, "%s pole" % prefix)
		_marker(key_prefix + "_shoulder", data.shoulder, COLOR_ELBOW, MARKER_RADIUS * 0.6)
		_segment(data.ik_target, data.wrist, wrist_color, LINE_RADIUS * 1.4)
		_segment(data.shoulder, data.elbow, COLOR_ELBOW)
		_segment(data.elbow, data.wrist, COLOR_ELBOW)
		_segment(data.elbow, data.pole, COLOR_POLE, LINE_RADIUS * 0.7)
		_segment(data.shoulder, data.wrist, reach_color(float(data.reach_fraction)), LINE_RADIUS * 0.8)
		if data.has("palm"):
			_marker(key_prefix + "_palm", data.palm, COLOR_PALM, MARKER_RADIUS, "%s palm~" % prefix)
			_marker(key_prefix + "_intended_palm", data.intended_palm, COLOR_INTENDED_PALM, MARKER_RADIUS, "%s palm tgt" % prefix)
			_segment(data.palm, data.intended_palm, COLOR_PALM_ERROR, LINE_RADIUS * 1.4)
			var tips: Array = data.fingertips
			for finger in tips.size():
				_marker("%s_tip%d" % [key_prefix, finger], tips[finger], wrist_color, FINGERTIP_RADIUS)
			_segment(data.palm, data.palm + (data.finger_direction as Vector3) * AXIS_LENGTH, COLOR_FINGER)
			_segment(data.palm, data.palm + (data.intended_finger_direction as Vector3) * AXIS_LENGTH, COLOR_FINGER_INTENDED, LINE_RADIUS * 0.7)
			_segment(data.palm, data.palm + (data.palm_normal as Vector3) * AXIS_LENGTH, COLOR_NORMAL)
			if data.has("intended_palm_normal"):
				_segment(data.palm, data.palm + (data.intended_palm_normal as Vector3) * AXIS_LENGTH, COLOR_NORMAL_INTENDED, LINE_RADIUS * 0.7)
	for index in range(_segments_used, _segments.size()):
		_segments[index].visible = false

func hide_all() -> void:
	for marker: MeshInstance3D in _markers.values():
		marker.visible = false
	for label: Label3D in _labels.values():
		label.visible = false
	for segment in _segments:
		segment.visible = false

func set_labels_visible(on: bool) -> void:
	labels_visible = on
	for key: String in _labels:
		var marker: MeshInstance3D = _markers.get(key)
		(_labels[key] as Label3D).visible = on and marker != null and marker.visible

## How many drawable nodes the overlay currently owns; tests use it to prove the overlay is gone when off.
func drawable_count() -> int:
	return _markers.size() + _segments.size() + _labels.size()
