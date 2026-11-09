extends RefCounted
## Imported ground decoration and tactical templates with authored volumes.

const Assets = preload("res://tools/asset_lab/asset_catalog.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const LoadingYard = preload("res://art/environments/authored/parcels/loading_yard.tscn")
const TACTICAL := {
	"factory_kit/box-large": "CrateA",
	"city_kit_industrial/shipping-container-a": "ContainerA",
	"city_kit_industrial/shipping-container-b": "ContainerB",
	"car_kit/delivery": "Truck",
}

static func entries() -> Dictionary:
	var result := {}
	var semantics := Semantics.load_data()
	for id in Assets.all_ids():
		var meaning := Semantics.effective(id, semantics)
		if id in TACTICAL:
			result[id] = "Tactical"
		elif meaning.asset_kind == "decorative_prop" and meaning.attachment == "ground" and not meaning.needs_identification:
			result[id] = "Decoration"
	return result

static func create(id: String) -> Node3D:
	if id in TACTICAL:
		var source := LoadingYard.instantiate()
		var piece := source.get_node(TACTICAL[id]).duplicate() as Node3D
		source.free()
		piece.position = Vector3.ZERO
		piece.show()
		for property in ["population_socket_id", "population_region_id", "population_surface_id", "population_yaw_turns"]:
			piece.remove_meta(property)
		return piece
	# Reuse the calibrated pivot and scale inside a grid-centered wrapper.
	var root := Node3D.new()
	if Assets.place(root, id, Vector3.ZERO) == null:
		root.free()
		return null
	root.set_meta("asset_id", id)
	return root
