extends RefCounted
## Curated visual calibration, not a tactical module/occupancy registry.
const ROOT := "res://art/environments/kenney/"
const PACKS := ["city_kit_industrial", "city_kit_roads", "factory_kit", "modular_space_kit"]
const Placement = preload("res://presentation/environment_asset_placement.gd")
const PROFILES := {
	"city_kit_industrial/shipping-container-a": {"scale": 5.5, "anchor": 0, "category": "cargo", "orientation": "Long axis Z; doors face +Z.", "note": "2.05 x 1.91 x 4.52 world units. Reserve clearance separately."},
	"city_kit_industrial/building-a": {"scale": 5.5, "anchor": 0, "category": "exterior", "orientation": "Y-up closed shell; facade choice remains placement-specific.", "note": "Closed miniature building; experimental scale only. Not an enterable warehouse module."},
	"city_kit_roads/road-straight": {"scale": 6.0, "anchor": 2, "category": "road", "orientation": "Traffic axis Z.", "note": "6-unit road tile. Preserve this family scale; road surface anchor is TOP_CENTER."},
	"city_kit_roads/road-side": {"scale": 6.0, "anchor": 1, "category": "road", "orientation": "Traffic axis Z; sidewalk projects toward -Z in its source AABB.", "note": "Keep source origin and translate Y by -0.12 for road-top zero."},
	"city_kit_roads/tile-low": {"scale": 6.0, "anchor": 2, "category": "paving", "orientation": "Axis-neutral square tile.", "note": "6-unit tile; same scale as road family."},
	"factory_kit/structure-wall": {"scale": 1.5, "anchor": 1, "category": "structure", "orientation": "Bay axis X; visible facade faces +Z.", "note": "1.5-unit calibrated X bay; 4.5 tall; Z bounds -0.5..1.5 include projecting structure. Preserve origin."},
	"factory_kit/structure-doorway-wide": {"scale": 1.5, "anchor": 1, "category": "entrance", "orientation": "Bay axis X; opening crosses Z.", "note": "3-unit calibrated X bay. Opening needs separate clearance/connector authoring; bounds are not solid occupancy."},
	"factory_kit/structure-window": {"scale": 1.5, "anchor": 1, "category": "structure", "orientation": "Bay axis X; visible facade faces +Z.", "note": "1.5-unit calibrated X bay sharing wall height and origin."},
	"factory_kit/machine": {"scale": 1.0, "anchor": 0, "category": "machinery", "orientation": "Working face visually identifiable; no connector authored.", "note": "Native 1.2 x 1.3 x 1.5; under two grid cells wide. Work area requires extra clearance."},
	"factory_kit/conveyor-long": {"scale": 1.0, "anchor": 0, "category": "machinery", "orientation": "Conveyor axis X.", "note": "2-unit pitch; native belt 0.4 high. Demo raises it 0.4 on a service stand."},
	"factory_kit/crane": {"scale": 1.0, "anchor": 0, "category": "machinery", "orientation": "Boom extends primarily +Z from its offset source pivot.", "note": "Strongly offset source Z pivot. Floor-centering useful for isolated prop; open bounds not a solid obstacle."},
	"modular_space_kit/template-floor": {"scale": 1.0, "anchor": 1, "category": "floor", "orientation": "Axis-neutral 4-unit square.", "note": "4-unit pitch; preserve source origin for matching wall sections."},
	"modular_space_kit/template-wall": {"scale": 1.0, "anchor": 1, "category": "structure", "orientation": "Bay axis X; interior face toward +Z in the inspected assembly.", "note": "4-unit X bay, 4.25 high; asymmetric Z thickness. Not interchangeable with Factory walls."},
	"modular_space_kit/corridor": {"scale": 1.0, "anchor": 1, "category": "room", "orientation": "Connections along Z in the inspected straight section.", "note": "4-unit footprint, 4.25 tall; enclosed geometry requires future cutaway and connector metadata."}
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
	return PROFILES.get(id, {"scale": 1.0, "anchor": 0, "category": "unreviewed", "orientation": "Not visually verified.", "note": "Uncalibrated: native scale with floor centering. Inspect before use."}).duplicate(true)

static func place(parent: Node3D, id: String, at: Vector3, yaw := 0.0) -> Node3D:
	var p := profile(id)
	return Placement.instantiate_calibrated(parent, path_for(id), at, p.scale, yaw, p.anchor)
