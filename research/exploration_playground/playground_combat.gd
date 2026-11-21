class_name PlaygroundCombat
extends Node
## Aim and shoot (sandbox package): right mouse raises the rifle, left mouse fires. The shot is SHOWN by the character host (the shared attack sequence: raise, align, fire, recover); WHAT it hits is decided here with a
## ray from the camera through the crosshair, and a hit lowers a target's bar. No AP, no turns, no hit chance.

const DAMAGE := 20.0
const RAY_LENGTH := 80.0

var ctx: Node
var crosshair: Label
var aiming := false


func setup(controller: Node, ui_layer: CanvasLayer) -> void:
	ctx = controller
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.visible = false
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.add_theme_color_override("font_outline_color", Color.BLACK)
	crosshair.add_theme_constant_override("outline_size", 6)
	ui_layer.add_child(crosshair)


func can_use_weapon() -> bool:
	return ctx.armed and not ctx.dead and not ctx.visual.is_carrying() and not ctx.visual.is_climbing() and not ctx.visual.is_on_stairs()


func set_aim(on: bool) -> void:
	aiming = on and can_use_weapon()
	ctx.visual.set_aiming(aiming)
	crosshair.visible = aiming
	if aiming:
		ctx.visual.presenter.hold_facing()   # she keeps facing where she aims while she moves
	else:
		ctx.visual.presenter.release_facing_hold()


## Called every frame: while aiming the body turns to the point under the crosshair (outside cover, where the wall owns the facing).
func update(_delta: float) -> void:
	if aiming and not can_use_weapon():
		set_aim(false)
	if aiming and not ctx.visual.is_in_cover():
		ctx.visual.face_point(aim_point())


## The world point under the crosshair (the camera's centre ray), or a far point straight ahead.
func aim_point() -> Vector3:
	return _ray()["position"]


func _ray() -> Dictionary:
	var from: Vector3 = ctx.camera.global_position
	var to: Vector3 = from + (-ctx.camera.global_basis.z) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [ctx.body.get_rid()]
	var hit: Dictionary = ctx.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": to, "collider": null}
	return hit


func fire() -> void:
	if not can_use_weapon() or ctx.visual.presenter.attack.is_active():
		return
	var hit := _ray()
	var point: Vector3 = hit["position"]
	var collider: Object = hit["collider"]
	var handle: AttackHandle = ctx.visual.fire(point)
	handle.shot.when_done(func(outcome: PresentationTypes.Outcome) -> void:
		if outcome != PresentationTypes.Outcome.COMPLETED:
			return
		_effects(point)
		if collider != null and collider.has_meta(&"target"):
			(collider.get_meta(&"target") as PlaygroundTarget).take_hit(DAMAGE))


## A tracer from the muzzle and a spark where it landed (both vanish at once).
func _effects(point: Vector3) -> void:
	var muzzle: Vector3 = ctx.visual.rig.muzzle_socket.global_position if is_instance_valid(ctx.visual.rig.muzzle_socket) else ctx.visual.global_position + Vector3.UP
	var length := muzzle.distance_to(point)
	if length < 0.05:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, length)
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.4)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.material_override = material
	ctx.add_child(tracer)
	tracer.global_position = muzzle.lerp(point, 0.5)
	tracer.look_at(point, Vector3.UP)
	var spark := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.1
	ball.height = 0.2
	spark.mesh = ball
	spark.material_override = material
	ctx.add_child(spark)
	spark.global_position = point
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(tracer):
		tracer.queue_free()
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(spark):
		spark.queue_free()
