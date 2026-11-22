class_name MotionTrail
extends Node
## Optional, read-only trajectory of a character's ROOT over time: a drawn trail in the world (colour = speed) and a bounded speed/facing history for readouts. Created by diagnostic hosts only, freed when switched off.
## Ordinary hosts sample once per rendered frame. Hosts with a manual/pauseable presentation clock may pause automatic sampling and explicitly record a single stepped frame after advancing their character.
## The elapsed value sums ONLY sampled frame deltas; paused wall-clock time is excluded. It does not move, time or steer the character.

const MAX_POINTS := 600
const SLOW := Color(0.3, 0.6, 1.0)
const FAST := Color(1.0, 0.45, 0.15)

var rig: CharacterRig
var enabled := false
var sampling_paused := false
var points: Array[Dictionary] = []   # {position, speed, yaw_deg, t}
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _t := 0.0
var _last_position := Vector3.INF
var max_speed_shown := 6.0

static func attach(p_rig: CharacterRig) -> MotionTrail:
	if not is_instance_valid(p_rig) or p_rig.character_root == null:
		return null
	var trail := MotionTrail.new()
	trail.name = "MotionTrail"
	trail.rig = p_rig
	p_rig.add_child(trail)
	return trail

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	set_process(on and not sampling_paused)
	_last_position = Vector3.INF   # the root may have moved while the trail was off: the first sample has no step, never a speed spike
	if on:
		_lines = MeshInstance3D.new()
		_lines.name = "MotionTrailLines"
		_lines.top_level = true
		_mesh = ImmediateMesh.new()
		_lines.mesh = _mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		_lines.material_override = material
		_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_lines)
	else:
		if is_instance_valid(_lines):
			_lines.queue_free()
		_lines = null
		_mesh = null

func clear() -> void:
	points.clear()
	_last_position = Vector3.INF
	_t = 0.0
	_redraw()

func _ready() -> void:
	set_process(false)

## A manual-clock host pauses background sampling, avoiding duplicate/stationary points while its simulation is stopped.
func set_sampling_paused(on: bool) -> void:
	if on != sampling_paused:
		_last_position = Vector3.INF   # whatever moved the root while sampling was paused is not a step of the next sample
	sampling_paused = on
	set_process(enabled and not on)

## Called by a manual-clock host AFTER it has advanced one complete simulation step.
func record_step(delta: float) -> void:
	if enabled and sampling_paused:
		_record(delta)

func _process(delta: float) -> void:
	if enabled and not sampling_paused:
		_record(delta)

func _record(delta: float) -> void:
	if not enabled or not is_instance_valid(rig):
		return
	var position := rig.character_root.global_position
	var step := 0.0 if _last_position == Vector3.INF else position.distance_to(_last_position)
	_t += delta
	_last_position = position
	var yaw := rad_to_deg(rig.character_root.global_basis.orthonormalized().get_euler().y)
	points.append({"position": position + Vector3(0, 0.03, 0), "speed": step / maxf(delta, 0.0001), "yaw_deg": yaw, "t": _t})
	while points.size() > MAX_POINTS:
		points.pop_front()
	_redraw()

func _redraw() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	if points.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		_mesh.surface_set_color(SLOW.lerp(FAST, clampf(float(point.speed) / max_speed_shown, 0.0, 1.0)))
		_mesh.surface_add_vertex(point.position)
	_mesh.surface_end()

## Peak and mean of the recorded speed and the total yaw swept, for a readout.
func summary() -> Dictionary:
	var peak := 0.0
	var total := 0.0
	var swept := 0.0
	for index in points.size():
		peak = maxf(peak, float(points[index].speed))
		total += float(points[index].speed)
		if index > 0:
			swept += absf(angle_difference(deg_to_rad(float(points[index - 1].yaw_deg)), deg_to_rad(float(points[index].yaw_deg))))
	return {"points": points.size(), "peak_speed": peak, "mean_speed": total / maxf(points.size(), 1), "yaw_swept_deg": rad_to_deg(swept)}
