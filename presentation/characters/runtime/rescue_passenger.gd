extends Node3D
## Lightweight rescue mannequin, replacing the hidden mission actor visually.
## Kept separate from the actor so presentation cannot change its lifecycle.

func _ready() -> void:
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color(0.8, 0.42, 0.13)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.73, 0.65, 0.55)
	_part(Vector3(0.48, 0.22, 0.3), Vector3.ZERO, fabric)
	_part(Vector3(0.2, 0.22, 0.2), Vector3(-0.36, -0.03, 0), skin)
	for z in [-0.12, 0.12]:
		_part(Vector3(0.42, 0.13, 0.13), Vector3(0.43, -0.08, z), fabric)
		_part(Vector3(0.12, 0.33, 0.13), Vector3(0.64, -0.27, z), fabric)
		_part(Vector3(0.12, 0.32, 0.12), Vector3(-0.22, -0.25, z * 1.7), fabric)

func _part(size: Vector3, location: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = location
	part.material_override = material
	add_child(part)
