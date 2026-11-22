class_name PrimitiveBodies
extends RefCounted
## Primitive Godot geometry for the Task 13 motion-family examples: no imported art, no skeleton. Each builder returns the nodes its presenter drives, and every one of them lives under a `visual` node that is a CHILD of the
## entity (the authoritative node is the caller's). Colours mark the front (red nose, +Z) and make wheel and rotor spin visible.

static func _mesh(parent: Node3D, mesh: Mesh, colour: Color, at := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.7
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

static func _box(parent: Node3D, size: Vector3, colour: Color, at := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, colour, at)

## A four-wheeled platform. Returns {visual, wheels (spin pivots, rotated about the axle X), steer_pivots (the front two), wheel_radius}.
static func build_wheeled(entity: Node3D) -> Dictionary:
	var visual := Node3D.new()
	visual.name = "WheeledVisual"
	entity.add_child(visual)
	var radius := 0.3
	_box(visual, Vector3(1.2, 0.4, 2.0), Color(0.35, 0.45, 0.55), Vector3(0, radius + 0.1, 0))
	_box(visual, Vector3(0.5, 0.25, 0.4), Color(0.9, 0.25, 0.2), Vector3(0, radius + 0.35, 0.8))   # the red nose: the platform's front
	_box(visual, Vector3(0.8, 0.3, 0.7), Color(0.25, 0.3, 0.38), Vector3(0, radius + 0.45, -0.3))
	var wheels: Array[Node3D] = []
	var steer_pivots: Array[Node3D] = []
	for corner in [Vector3(-0.7, radius, 0.7), Vector3(0.7, radius, 0.7), Vector3(-0.7, radius, -0.7), Vector3(0.7, radius, -0.7)]:
		var hub := Node3D.new()
		hub.position = corner
		visual.add_child(hub)
		if corner.z > 0.0:
			steer_pivots.append(hub)
		var spin := Node3D.new()
		hub.add_child(spin)
		wheels.append(spin)
		var tyre := CylinderMesh.new()
		tyre.top_radius = radius
		tyre.bottom_radius = radius
		tyre.height = 0.22
		var tyre_instance := _mesh(spin, tyre, Color(0.08, 0.08, 0.09))
		tyre_instance.rotation.z = PI * 0.5   # the cylinder's axis becomes the axle (X)
		_box(spin, Vector3(0.24, radius * 1.6, 0.07), Color(0.95, 0.85, 0.2))   # a bar across the wheel: spin is visible
	return {"visual": visual, "wheels": wheels, "steer_pivots": steer_pivots, "wheel_radius": radius}

## A quadrotor-style drone. Returns {visual, tilt_pivot (the body that pitches and banks), rotors (spin pivots, about Y)}.
static func build_drone(entity: Node3D) -> Dictionary:
	var visual := Node3D.new()
	visual.name = "DroneVisual"
	entity.add_child(visual)
	var tilt := Node3D.new()
	tilt.name = "TiltPivot"
	visual.add_child(tilt)
	var body := SphereMesh.new()
	body.radius = 0.32
	body.height = 0.5
	_mesh(tilt, body, Color(0.82, 0.84, 0.88))
	_box(tilt, Vector3(0.18, 0.12, 0.3), Color(0.9, 0.25, 0.2), Vector3(0, 0, 0.32))   # the red nose: the drone's front
	for angle in [PI * 0.25, -PI * 0.25]:
		var strut := _box(tilt, Vector3(1.55, 0.04, 0.06), Color(0.3, 0.32, 0.36), Vector3(0, 0.1, 0))
		strut.rotation.y = angle
	var rotors: Array[Node3D] = []
	for arm in [Vector3(-0.55, 0.12, 0.55), Vector3(0.55, 0.12, 0.55), Vector3(-0.55, 0.12, -0.55), Vector3(0.55, 0.12, -0.55)]:
		var pivot := Node3D.new()
		pivot.position = arm
		tilt.add_child(pivot)
		rotors.append(pivot)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.26
		disc.bottom_radius = 0.26
		disc.height = 0.02
		_mesh(pivot, disc, Color(0.2, 0.7, 0.95))
		_box(pivot, Vector3(0.56, 0.03, 0.07), Color(0.05, 0.05, 0.08), Vector3(0, 0.02, 0))
	return {"visual": visual, "tilt_pivot": tilt, "rotors": rotors}
