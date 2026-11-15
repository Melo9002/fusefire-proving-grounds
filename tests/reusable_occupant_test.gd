extends SceneTree
## Extraction contract: preserve the geometry and tactical metadata authored at
## 4c465f2, while ordinary object creation must not load an example parcel.
const PARCELS := ["loading_yard", "loading_yard_alt", "industrial_office_parking", "industrial_office_painted_parking", "industrial_office_parking_rules", "loading_yard_painted_containers"]
const OBJECTS := {
	"box_large": ["loading_yard", "CrateA"],
	"container_a": ["loading_yard", "ContainerA"],
	"container_b": ["loading_yard", "ContainerB"],
	"container_c": ["loading_yard_alt", "ContainerC"],
	"delivery": ["loading_yard", "Truck"],
	"sedan": ["industrial_office_parking", "SedanWest"],
	"suv": ["industrial_office_parking", "SuvMid"],
	"taxi": ["industrial_office_parking", "TaxiEast"],
}
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func snapshot(node: Node, normalize_root := false) -> Array:
	var metadata := {}
	for key in node.get_meta_list():
		if normalize_root and String(key).begins_with("population_"): continue
		metadata[String(key)] = var_to_str(node.get_meta(key))
	var value: Array = [String(node.name) if not normalize_root else "Object", node.get_class(), metadata]
	if node is Node3D:
		value.append(var_to_str(Transform3D.IDENTITY if normalize_root else node.transform))
		value.append(true if normalize_root else node.visible)
	if node is MeshInstance3D:
		value.append(var_to_str(node.mesh.get_aabb()) if node.mesh else "no mesh")
		# Mesh arrays also protect visual geometry, independently of its resource identity.
		if node.mesh:
			for surface in node.mesh.get_surface_count():
				value.append(var_to_str(node.mesh.surface_get_arrays(surface)))
	for child in node.get_children(): value.append(snapshot(child))
	return value

func digest(node: Node, normalize_root := false) -> String:
	return JSON.stringify(snapshot(node, normalize_root)).sha256_text()

func parcel_path(id: String) -> String:
	return "res://art/environments/authored/parcels/%s.tscn" % id

func _run() -> void:
	var library = load("res://tools/parcel_editor/parcel_placement_library.gd")
	for asset_id in library.TACTICAL:
		var piece: Node3D = library.create(asset_id)
		check(piece != null and piece.visible and piece.position == Vector3.ZERO, "Tactical object is independently placeable: %s" % asset_id)
		check(not piece.has_meta("population_socket_id") and not piece.has_meta("population_region_id"), "Placement does not inherit parcel population membership")
		piece.free()
	var vehicles = load("res://systems/generation2/parking_vehicle_templates.gd").new()
	check(vehicles.asset_ids() == PackedStringArray(["car_kit/sedan", "car_kit/suv", "car_kit/taxi"]), "Vehicle ordering preserves seeded choices")
	for id in ["loading_yard", "industrial_office_parking"]:
		check(not ResourceLoader.has_cached(parcel_path(id)), "Object creation must not load the example parcel %s" % id)
	vehicles = null

	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reusable_occupants_baseline.json"))
	for id in PARCELS:
		var parcel: Node3D = load(parcel_path(id)).instantiate()
		check(digest(parcel) == expected.parcels[id], "Parcel geometry, transforms, visibility and tactical metadata survive extraction: %s" % id)
		parcel.free()
	for id in OBJECTS:
		var object_path := "res://art/environments/authored/objects/%s.tscn" % id
		var piece: Node3D = load(object_path).instantiate()
		check(digest(piece, true) == expected.objects[id], "Reusable object retains its original calibrated mesh and all tactical parts: %s" % id)
		check(piece.transform == Transform3D.IDENTITY and piece.visible, "Reusable source starts visible at its local origin: %s" % id)
		piece.free()
	print("Reusable occupants: %d failure(s)" % failures)
	quit(1 if failures else 0)
