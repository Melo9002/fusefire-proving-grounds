extends RefCounted
## Fixed objects with authored exceptions or automatic visible-mesh boundaries.

const Assets = preload("res://tools/asset_lab/asset_catalog.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const MeshBounds = preload("res://tools/parcel_editor/mesh_tactical_bounds.gd")
const TACTICAL := {
	"city_kit_industrial/detail-tank": preload("res://art/environments/authored/objects/horizontal_drum.tscn"),
	"factory_kit/box-large": preload("res://art/environments/authored/objects/box_large.tscn"),
	"city_kit_industrial/shipping-container-a": preload("res://art/environments/authored/objects/container_a.tscn"),
	"city_kit_industrial/shipping-container-b": preload("res://art/environments/authored/objects/container_b.tscn"),
	"car_kit/delivery": preload("res://art/environments/authored/objects/delivery.tscn"),
}

static func entries() -> Dictionary:
	var result := {}
	var semantics := Semantics.load_data()
	for id in Assets.all_ids():
		var meaning := Semantics.effective(id, semantics)
		if id in TACTICAL:
			result[id] = "Authored boundaries"
		elif (meaning.asset_kind == "decorative_prop" or (meaning.asset_kind in ["tactical_obstacle", "equipment"] and meaning.completeness == "complete")) and meaning.attachment == "ground" and not meaning.needs_identification:
			result[id] = "Mesh boundaries"
	return result

static func create(id: String) -> Node3D:
	if id in TACTICAL:
		return TACTICAL[id].instantiate() as Node3D
	# Reuse the calibrated pivot and scale inside a grid-centered wrapper.
	var root := Node3D.new()
	if Assets.place(root, id, Vector3.ZERO) == null:
		root.free()
		return null
	root.set_meta("asset_id", id)
	MeshBounds.add_to(root)
	return root
