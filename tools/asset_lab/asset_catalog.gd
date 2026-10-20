extends RefCounted
## Visual calibration catalog. Tactical occupancy remains authored separately in MapData/modules.
const ROOT := "res://art/environments/kenney/"
const DATA_PATH := "res://tools/asset_lab/asset_calibrations.json"
const PACKS := ["city_kit_industrial", "city_kit_roads", "factory_kit", "modular_space_kit"]
const Placement = preload("res://presentation/environment_asset_placement.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const DEFAULT_SCALE := 1.0
const PROFILES := {
	"city_kit_industrial/shipping-container-a": {"anchor": 0, "category": "cargo", "orientation": "Long axis Z; doors face +Z.", "note": "Reserve clearance separately."},
	"city_kit_industrial/building-a": {"anchor": 0, "category": "exterior", "orientation": "Y-up closed shell; facade choice remains placement-specific.", "note": "Closed building; not an enterable warehouse module."},
	"city_kit_roads/road-straight": {"anchor": 2, "category": "road", "orientation": "Source traffic axis X; environment modules normalize it to local Z.", "note": "Road surface anchor is TOP_CENTER."},
	"city_kit_roads/road-side": {"anchor": 1, "anchor_position": [0.0, -0.12, 0.0], "category": "road", "orientation": "Traffic axis Z; sidewalk projects toward -Z in its source AABB.", "note": "Keep source origin and selection offset."},
	"city_kit_roads/tile-low": {"anchor": 2, "category": "paving", "orientation": "Axis-neutral square tile.", "note": "Same scale as the road family."},
	"factory_kit/structure-wall": {"anchor": 1, "category": "structure", "orientation": "Bay axis X; visible facade faces +Z.", "note": "Z bounds include projecting structure. Preserve origin."},
	"factory_kit/structure-doorway-wide": {"anchor": 1, "category": "entrance", "orientation": "Bay axis X; opening crosses Z.", "note": "Opening needs separate clearance/connector authoring; bounds are not solid occupancy."},
	"factory_kit/structure-window": {"anchor": 1, "category": "structure", "orientation": "Bay axis X; visible facade faces +Z.", "note": "Shares wall height and origin."},
	"factory_kit/machine": {"anchor": 0, "category": "machinery", "orientation": "Working face visually identifiable; no connector authored.", "note": "Work area requires extra authored clearance."},
	"factory_kit/conveyor-long": {"anchor": 0, "category": "machinery", "orientation": "Conveyor axis X.", "note": "Two-unit visual pitch at native scale."},
	"factory_kit/crane": {"anchor": 0, "category": "machinery", "orientation": "Boom extends primarily +Z from its offset source pivot.", "note": "Strongly offset source Z pivot; open bounds are not a solid obstacle."},
	"modular_space_kit/template-floor": {"anchor": 1, "category": "floor", "orientation": "Axis-neutral 4-unit square.", "note": "Preserve source origin for matching wall sections."},
	"modular_space_kit/template-wall": {"anchor": 1, "category": "structure", "orientation": "Bay axis X; interior face toward +Z in the inspected assembly.", "note": "Asymmetric Z thickness."},
	"modular_space_kit/corridor": {"anchor": 1, "category": "room", "orientation": "Connections along Z in the inspected straight section.", "note": "Enclosed geometry requires future cutaway and connector metadata."}
}

static func default_data() -> Dictionary:
	return {
		"version": 2,
		"fallback": {"scale": DEFAULT_SCALE},
		"category_presets": {
			"buildings": {"scale": 10.0}, "shipping_containers": {"scale": 8.0},
			"chimneys": {"scale": 5.0}, "water_tanks": {"scale": 5.0},
			"solar_panels": {"scale": 10.0}, "industrial_other": {"scale": 5.0},
			"roads_and_paving": {"scale": 5.0}, "signs_and_signals": {"scale": 5.0},
			"electricity_infrastructure": {"scale": 10.0}, "road_lights": {"scale": 5.0},
			"construction_fences": {"scale": 5.0}, "dumpsters": {"scale": 5.0},
			"construction_equipment": {"scale": 5.0},
			"factory_unclassified": {"scale": 1.5},
			"space_unclassified": {"scale": 1.0}
		},
		"asset_overrides": {}, "reviewed": []
	}

static func load_calibrations(path := DATA_PATH) -> Dictionary:
	var defaults := default_data()
	if not FileAccess.file_exists(path):
		return defaults
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return defaults
	var data: Dictionary = parsed
	for key in ["fallback", "category_presets", "asset_overrides", "reviewed"]:
		if not data.has(key) or typeof(data[key]) != typeof(defaults[key]):
			data[key] = defaults[key].duplicate(true)
	data["version"] = 2
	return data

static func save_calibrations(data: Dictionary, path := DATA_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return OK

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

static func calibration_category(id: String) -> String:
	var name := id.get_file()
	if id.begins_with("city_kit_industrial/"):
		if name.begins_with("building-"): return "buildings"
		if name.begins_with("shipping-container-"): return "shipping_containers"
		if name.begins_with("chimney-"): return "chimneys"
		if name.begins_with("detail-tank") or name == "water-tower": return "water_tanks"
		if name.begins_with("solar-panel-"): return "solar_panels"
		return "industrial_other"
	if id.begins_with("city_kit_roads/"):
		if name == "construction-fence": return "construction_fences"
		if name == "dumpster": return "dumpsters"
		if name.begins_with("construction-"): return "construction_equipment"
		if name.begins_with("electricity-"): return "electricity_infrastructure"
		if name.begins_with("light-"): return "road_lights"
		if name.begins_with("sign-") or name.begins_with("road-sign-") or name.begins_with("traffic-light-"): return "signs_and_signals"
		return "roads_and_paving"
	if id.begins_with("factory_kit/"): return "factory_unclassified"
	if id.begins_with("modular_space_kit/"): return "space_unclassified"
	return "unclassified"

## Human-facing role grouping. This is based on pack and filename semantics; it
## does not claim scale, tactical occupancy, or visual approval.
static func semantic_category(id: String) -> String:
	return Semantics.semantic_category(id)

static func inferred_classification(id: String) -> String:
	return Semantics.broad_classification(id)

static func profile(id: String, data := {}) -> Dictionary:
	if data.is_empty(): data = load_calibrations()
	var result: Dictionary = PROFILES.get(id, {"anchor": 0, "category": "unreviewed", "orientation": "Not visually verified.", "note": "Inspect before tactical authoring."}).duplicate(true)
	result["yaw_degrees"] = 0.0
	result["anchor_position"] = result.get("anchor_position", [0.0, 0.0, 0.0])
	result["calibration_category"] = calibration_category(id)
	result["semantic_category"] = semantic_category(id)
	result["classification"] = inferred_classification(id)
	result["scale"] = float(data.get("fallback", {}).get("scale", DEFAULT_SCALE))
	result["calibration_source"] = "default"
	var category_presets: Dictionary = data.get("category_presets", {})
	if category_presets.has(result.calibration_category):
		result.merge(category_presets[result.calibration_category], true)
		result["calibration_source"] = "category"
	var overrides: Dictionary = data.get("asset_overrides", {})
	if overrides.has(id):
		result.merge(overrides[id], true)
		result["calibration_source"] = "asset override"
	result["reviewed"] = id in data.get("reviewed", [])
	return result

static func scale_for(id: String, data := {}) -> float:
	return float(profile(id, data).scale)

static func place(parent: Node3D, id: String, at: Vector3, yaw := 0.0, data := {}) -> Node3D:
	var p := profile(id, data)
	var saved_offset := Vector3(float(p.anchor_position[0]), float(p.anchor_position[1]), float(p.anchor_position[2]))
	return Placement.instantiate_calibrated(parent, path_for(id), at + saved_offset, p.scale,
		yaw + deg_to_rad(float(p.yaw_degrees)), p.anchor)
