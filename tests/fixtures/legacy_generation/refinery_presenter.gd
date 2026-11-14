extends RefCounted

const Layout = preload("res://tests/fixtures/legacy_generation/refinery_layout_builder.gd")

# Box-only industrial blockout. Equipment stays inside its reserved footprint.
static func build(data: MapData, parent: Node3D, cell_size: float) -> void:
	var plant := Node3D.new()
	plant.name = "RefineryEquipment"
	parent.add_child(plant)
	var steel := _material(Color(0.49, 0.57, 0.59))
	var dark := _material(Color(0.17, 0.23, 0.27))
	var ochre := _material(Color(0.85, 0.57, 0.12))
	for spec in Layout.EQUIPMENT:
		var footprint: Rect2i = spec[0]
		var height := float(spec[1]) * cell_size
		var origin := data.get_cell(Vector3i(footprint.position.x, 0, footprint.position.y)).world_position
		var center := origin + Vector3(1, 0, 1) * cell_size
		_box(plant, Vector3(2.9, 0.25, 2.9) * cell_size, center + Vector3.UP * 0.125 * cell_size, dark)
		_box(plant, Vector3(2.5 * cell_size, height - 0.5 * cell_size, 2.5 * cell_size), center + Vector3.UP * height * 0.5, steel)
		for fraction in [0.25, 0.7]:
			_box(plant, Vector3(2.65, 0.15, 2.65) * cell_size, center + Vector3.UP * height * fraction, ochre)
		_box(plant, Vector3(2.7, 0.2, 2.7) * cell_size, center + Vector3.UP * (height - 0.1 * cell_size), dark)
		# Vertical process duct on the vessel face, fully within the blocked area.
		_box(plant, Vector3(0.18 * cell_size, height * 0.8, 0.18 * cell_size), center + Vector3(1.35 * cell_size, height * 0.45, 0), ochre)
		var label := Label3D.new()
		label.text = spec[2]
		label.font_size = 40
		label.pixel_size = 0.009 * cell_size
		label.position = center + Vector3(0, height * 0.55, 1.27 * cell_size)
		plant.add_child(label)
	# Pipe runs below the catwalk edges leave the walking surface clear.
	for traversal in data.generated_traversals:
		if traversal.kind != GeneratedTraversalData.Kind.BRIDGE:
			continue
		var first := data.get_cell(traversal.from_cell).world_position
		var last := data.get_cell(traversal.to_cell).world_position
		var length := absf(last.z - first.z)
		for side in [-1.0, 1.0]:
			_box(plant, Vector3(0.12 * cell_size, 0.12 * cell_size, length), (first + last) * 0.5 + Vector3(side * 0.4, -0.3, 0) * cell_size, ochre)

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material

static func _box(parent: Node3D, dimensions: Vector3, center: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)
