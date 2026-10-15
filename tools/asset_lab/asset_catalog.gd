extends RefCounted
## Curated visual calibration, not a tactical module/occupancy registry.
const ROOT := "res://art/environments/kenney/"
const PACKS := ["city_kit_industrial", "city_kit_roads", "factory_kit", "modular_space_kit"]
const Placement = preload("res://presentation/environment_asset_placement.gd")
const CITY_SCALE := 9.0
const STREET_FURNITURE_SCALE := 5.0
const NATIVE_SCALE := 1.0
const DEFAULT_SCALE := CITY_SCALE
const STREET_FURNITURE := {
	"city_kit_roads/construction-barrier": true,
	"city_kit_roads/construction-cone": true,
	"city_kit_roads/construction-fence": true,
	"city_kit_roads/construction-light": true,
	"city_kit_roads/dumpster": true,
}
const PROFILES := {
	"city_kit_industrial/shipping-container-a": {"anchor": 0, "category": "cargo", "orientation": "Long axis Z; doors face +Z.", "note": "Reserve clearance separately."},
	"city_kit_industrial/building-a": {"anchor": 0, "category": "exterior", "orientation": "Y-up closed shell; facade choice remains placement-specific.", "note": "Closed building; not an enterable warehouse module."},
	"city_kit_roads/road-straight": {"anchor": 2, "category": "road", "orientation": "Traffic axis Z.", "note": "9-unit road tile at the selected baseline; road surface anchor is TOP_CENTER."},
	"city_kit_roads/road-side": {"anchor": 1, "category": "road", "orientation": "Traffic axis Z; sidewalk projects toward -Z in its source AABB.", "note": "Keep source origin and the existing selection offset."},
	"city_kit_roads/tile-low": {"anchor": 2, "category": "paving", "orientation": "Axis-neutral square tile.", "note": "9-unit tile at the selected baseline; same scale as the road family."},
	"factory_kit/structure-wall": {"anchor": 1, "category": "structure", "orientation": "Bay axis X; visible facade faces +Z.", "note": "1-unit native X bay; Z bounds include projecting structure. Preserve origin."},
	"factory_kit/structure-doorway-wide": {"anchor": 1, "category": "entrance", "orientation": "Bay axis X; opening crosses Z.", "note": "2-unit native entrance bay. Opening needs separate clearance/connector authoring; bounds are not solid occupancy."},
	"factory_kit/structure-window": {"anchor": 1, "category": "structure", "orientation": "Bay axis X; visible facade faces +Z.", "note": "1-unit native X bay sharing wall height and origin."},
	"factory_kit/machine": {"anchor": 0, "category": "machinery", "orientation": "Working face visually identifiable; no connector authored.", "note": "Work area requires extra authored clearance."},
	"factory_kit/conveyor-long": {"anchor": 0, "category": "machinery", "orientation": "Conveyor axis X.", "note": "2-unit visual pitch at native scale."},
	"factory_kit/crane": {"anchor": 0, "category": "machinery", "orientation": "Boom extends primarily +Z from its offset source pivot.", "note": "Strongly offset source Z pivot. Floor-centering is useful; open bounds are not a solid obstacle."},
	"modular_space_kit/template-floor": {"anchor": 1, "category": "floor", "orientation": "Axis-neutral 4-unit square.", "note": "4-unit visual pitch at native scale; preserve source origin for matching wall sections."},
	"modular_space_kit/template-wall": {"anchor": 1, "category": "structure", "orientation": "Bay axis X; interior face toward +Z in the inspected assembly.", "note": "4-unit native X bay with asymmetric Z thickness."},
	"modular_space_kit/corridor": {"anchor": 1, "category": "room", "orientation": "Connections along Z in the inspected straight section.", "note": "4-unit footprint at native scale; enclosed geometry requires future cutaway and connector metadata."}
}

static func path_for(id: String) -> String:
	var parts := id.split("/")
	return ROOT + parts[0] + "/models/" + parts[1] + ".glb"

static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for pack in PACKS:
		for file in DirAccess.get_files_at(ROOT + pack + "/models"):
			if file.ends_with(".glb"):
				ids.append(pack + "/" + file.get_basename())
	ids.sort()
	return ids

static func profile(id: String) -> Dictionary:
	var result: Dictionary = PROFILES.get(id, {"anchor": 0, "category": "unreviewed", "orientation": "Not visually verified.", "note": "Family baseline with floor centering. Inspect before tactical authoring."}).duplicate(true)
	result["scale"] = scale_for(id)
	return result

static func scale_for(id: String) -> float:
	if STREET_FURNITURE.has(id):
		return STREET_FURNITURE_SCALE
	if id.begins_with("factory_kit/") or id.begins_with("modular_space_kit/"):
		return NATIVE_SCALE
	return CITY_SCALE

static func place(parent: Node3D, id: String, at: Vector3, yaw := 0.0) -> Node3D:
	var p := profile(id)
	return Placement.instantiate_calibrated(parent, path_for(id), at, p.scale, yaw, p.anchor)
