class_name SemanticAssetCatalog
extends RefCounted
## Human-meaning metadata for imported environment visuals.
##
## Measurements and visual calibration live in asset_calibrations.json. This
## catalog answers a different question: what an asset represents and where it
## may be used. Filename inference is deliberately provisional; durable project
## decisions live in asset_semantics.json and always win.

const DATA_PATH := "res://tools/asset_lab/asset_semantics.json"

const KINDS := [
	"unknown", "complete_building", "structural_fragment", "open_structure",
	"ground_infrastructure", "equipment", "utility_infrastructure",
	"tactical_obstacle", "decorative_prop",
]
const STRUCTURAL_ROLES := [
	"unspecified", "shell", "wall", "corner", "entrance", "window", "roof",
	"floor", "canopy", "road", "intersection", "sidewalk", "door",
	"machinery", "container", "sign", "light", "utility", "detail",
]
const COMPLETENESS := ["unknown", "complete", "fragment", "intentionally_open", "not_applicable"]
const FRONT_FACES := ["unknown", "+z", "-z", "+x", "-x", "axis_neutral"]
const SECONDARY_FRONT_FACES := ["none", "+z", "-z", "+x", "-x"]
const DIRECTIONAL_FACES := ["+z", "-z", "+x", "-x"]
const ATTACHMENTS := ["unknown", "ground", "source_origin", "wall", "overhead", "structural_socket", "ground_surface"]

static func default_data() -> Dictionary:
	return {"version": 2, "confirmed": {}}

static func load_data(path := DATA_PATH) -> Dictionary:
	var defaults := default_data()
	if not FileAccess.file_exists(path):
		return defaults
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return defaults
	var data: Dictionary = parsed
	if not data.has("confirmed") or not data.confirmed is Dictionary:
		data.confirmed = {}
	data.version = 2
	return data

static func save_data(data: Dictionary, path := DATA_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return OK

static func effective(id: String, data := {}) -> Dictionary:
	if data.is_empty():
		data = load_data()
	var result := inferred(id)
	var confirmed: Dictionary = data.get("confirmed", {})
	var has_confirmed_working_faces: bool = confirmed.has(id) and confirmed[id] is Dictionary and confirmed[id].has("working_faces")
	if confirmed.has(id):
		result.merge(confirmed[id], true)
		result["interpretation_source"] = "confirmed"
		result["confidence"] = "confirmed"
		result["needs_identification"] = false
	else:
		result["interpretation_source"] = "inferred"
		# Even a strong filename inference remains a question until a human has
		# confirmed its architectural meaning. Confidence helps prioritize the
		# queue; it never silently promotes an asset to verified knowledge.
		result["needs_identification"] = true
	var source_faces: Array = result.get("working_faces", []) if has_confirmed_working_faces else [result.get("front_face", "unknown")]
	result["working_faces"] = normalize_working_faces(source_faces)
	if not result.working_faces.is_empty():
		result["front_face"] = result.working_faces[0]
	result["id"] = id
	return result

static func inferred(id: String) -> Dictionary:
	var semantic := semantic_category(id)
	var record := {
		"label": id.get_file().replace("-", " ").capitalize(),
		"semantic_category": semantic,
		"architectural_purpose": _purpose_for(semantic),
		"asset_kind": "decorative_prop",
		"structural_role": "detail",
		"completeness": "not_applicable",
		"front_face": "unknown",
		"working_faces": [],
		"attachment": "ground",
		"contexts": _contexts_for(semantic),
		"connections": [],
		"generation_ready": false,
		"confidence": "medium",
		"evidence": "Inferred from source pack and filename; visually verify before procedural use.",
		"notes": "",
	}
	if semantic in ["industrial_buildings"]:
		record.merge({"asset_kind": "complete_building", "structural_role": "shell", "completeness": "unknown", "confidence": "medium", "attachment": "ground"}, true)
	elif semantic in ["bridge_structures", "catwalk_modules", "factory_structure_modules", "space_corridors", "space_rooms", "space_wall_modules"]:
		record.merge({"asset_kind": "structural_fragment", "structural_role": _structural_role(id, semantic), "completeness": "fragment", "attachment": "structural_socket"}, true)
	elif semantic in ["road_modules", "paving_tiles", "factory_floor_modules", "factory_platforms", "space_floor_modules"]:
		record.merge({"asset_kind": "ground_infrastructure", "structural_role": _structural_role(id, semantic), "completeness": "fragment", "attachment": "ground_surface"}, true)
	elif semantic in ["factory_doors", "factory_entrances", "space_gates", "space_stairs"]:
		record.merge({"asset_kind": "structural_fragment", "structural_role": "entrance", "completeness": "fragment", "attachment": "structural_socket"}, true)
	elif semantic in ["cargo_containers"]:
		record.merge({"asset_kind": "tactical_obstacle", "structural_role": "container", "completeness": "complete", "front_face": "+z", "confidence": "high"}, true)
	elif semantic in ["industrial_chimneys", "tanks_and_towers", "wind_power", "cargo_boxes"]:
		record.merge({"asset_kind": "tactical_obstacle", "structural_role": "detail", "completeness": "complete"}, true)
	elif semantic in ["conveyor_modules", "crane_modules", "hoppers", "factory_machines", "machine_components", "pipe_modules", "robotics", "scanners"]:
		record.merge({"asset_kind": "equipment", "structural_role": "machinery", "completeness": "unknown", "confidence": "medium"}, true)
	elif semantic in ["electrical_infrastructure", "street_lighting", "traffic_signals"]:
		record.merge({"asset_kind": "utility_infrastructure", "structural_role": "utility", "completeness": "unknown", "confidence": "medium"}, true)
	elif semantic in ["unknown_manual_review"]:
		record.merge({"asset_kind": "unknown", "structural_role": "unspecified", "completeness": "unknown", "attachment": "unknown", "confidence": "low", "contexts": []}, true)
	return record

static func normalize_working_faces(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var face := str(value).to_lower()
		if face in DIRECTIONAL_FACES and face not in result:
			result.append(face)
		if result.size() == 2:
			break
	return result

static func semantic_category(id: String) -> String:
	var name := id.get_file()
	if id.begins_with("city_kit_industrial/"):
		if name.begins_with("building-"): return "industrial_buildings"
		if name.begins_with("shipping-container-"): return "cargo_containers"
		if name.begins_with("chimney-"): return "industrial_chimneys"
		if name.begins_with("detail-tank") or name == "water-tower": return "tanks_and_towers"
		if name.begins_with("solar-panel-"): return "solar_equipment"
		if name.begins_with("windmill"): return "wind_power"
	if id.begins_with("city_kit_roads/"):
		if name.begins_with("bridge-pillar"): return "bridge_structures"
		if name == "dumpster": return "waste_props"
		if name.begins_with("construction-"): return "construction_safety"
		if name.begins_with("electricity-"): return "electrical_infrastructure"
		if name.begins_with("light-"): return "street_lighting"
		if name.begins_with("road-sign-") or name.begins_with("sign-"): return "road_signage"
		if name.begins_with("traffic-light"): return "traffic_signals"
		if name.begins_with("tile-"): return "paving_tiles"
		if name.begins_with("road-"): return "road_modules"
	if id.begins_with("factory_kit/"):
		if name == "oopi": return "unknown_manual_review"
		if name.begins_with("arrow") or name.begins_with("warning-") or name.begins_with("indicator-special-"): return "floor_markings"
		if name.begins_with("box-"): return "cargo_boxes"
		if name.begins_with("button-") or name.begins_with("lever-"): return "controls_and_switches"
		if name.begins_with("catwalk-"): return "catwalk_modules"
		if name.begins_with("cog-") or name.begins_with("piston-"): return "machine_components"
		if name == "cone": return "safety_props"
		if name.begins_with("conveyor"): return "conveyor_modules"
		if name.begins_with("crane"): return "crane_modules"
		if name.begins_with("door"): return "factory_doors"
		if name.begins_with("floor"): return "factory_floor_modules"
		if name.begins_with("hopper-"): return "hoppers"
		if name.begins_with("machine"): return "factory_machines"
		if name.begins_with("pipe-"): return "pipe_modules"
		if name.begins_with("robot-arm-"): return "robotics"
		if name.begins_with("scanner-"): return "scanners"
		if name.begins_with("screen-"): return "screens_and_panels"
		if name.begins_with("structure-doorway"): return "factory_entrances"
		if name.begins_with("structure-"): return "factory_structure_modules"
		if name.begins_with("top"): return "factory_platforms"
	if id.begins_with("modular_space_kit/"):
		if name == "cables": return "space_utilities"
		if name.begins_with("corridor"): return "space_corridors"
		if name.begins_with("gate"): return "space_gates"
		if name.begins_with("room-"): return "space_rooms"
		if name.begins_with("stairs"): return "space_stairs"
		if name.begins_with("template-floor"): return "space_floor_modules"
		if name.begins_with("template-wall") or name.begins_with("template-corner"): return "space_wall_modules"
		if name.begins_with("template-detail"): return "space_details"
	return "unknown_manual_review"

static func broad_classification(id: String) -> String:
	var kind: String = inferred(id).asset_kind
	if kind in ["complete_building", "structural_fragment", "open_structure"]: return "structural"
	if kind == "ground_infrastructure": return "ground"
	if inferred(id).structural_role in ["entrance", "door"]: return "entrance"
	if kind in ["equipment", "tactical_obstacle"]: return "tactical_obstacle"
	if kind == "unknown": return "unclassified"
	return "decorative"

static func is_confirmed(id: String, data := {}) -> bool:
	if data.is_empty(): data = load_data()
	return data.get("confirmed", {}).has(id)

static func needs_identification(id: String, data := {}) -> bool:
	return bool(effective(id, data).needs_identification)

static func generation_candidates(ids: Array, data := {}, required_kind := "") -> Array[String]:
	if data.is_empty(): data = load_data()
	var result: Array[String] = []
	for value in ids:
		var id := str(value)
		var record := effective(id, data)
		if record.interpretation_source != "confirmed" or not record.get("generation_ready", false):
			continue
		if not required_kind.is_empty() and record.asset_kind != required_kind:
			continue
		result.append(id)
	return result

static func compatible_as_complete_building(id: String, data := {}) -> bool:
	var record := effective(id, data)
	return record.interpretation_source == "confirmed" and record.generation_ready and record.asset_kind == "complete_building" and record.completeness == "complete"

static func _structural_role(id: String, semantic: String) -> String:
	var name := id.get_file()
	if "corner" in name: return "corner"
	if "window" in name: return "window"
	if "doorway" in name or "gate" in name: return "entrance"
	if "wall" in name: return "wall"
	if "floor" in name or semantic in ["factory_floor_modules", "space_floor_modules"]: return "floor"
	if semantic == "road_modules": return "intersection" if name.contains("intersection") or name.contains("crossroad") else "road"
	if semantic == "paving_tiles": return "sidewalk"
	return "unspecified"

static func _contexts_for(semantic: String) -> Array[String]:
	if semantic.begins_with("space_"): return ["space_facility"]
	if semantic in ["road_modules", "paving_tiles", "road_signage", "street_lighting", "traffic_signals", "electrical_infrastructure"]: return ["industrial", "commercial", "mixed_service"]
	if semantic in ["industrial_buildings", "industrial_chimneys", "tanks_and_towers", "wind_power", "solar_equipment", "factory_machines", "conveyor_modules", "crane_modules", "hoppers", "robotics"]: return ["industrial"]
	if semantic in ["factory_structure_modules", "factory_entrances", "factory_floor_modules", "factory_platforms"]: return ["industrial", "mixed_service"]
	return ["industrial", "commercial", "mixed_service"]

static func _purpose_for(semantic: String) -> String:
	var purposes := {
		"industrial_buildings": "industrial_building",
		"cargo_containers": "cargo_storage",
		"industrial_chimneys": "industrial_exhaust",
		"tanks_and_towers": "material_storage",
		"solar_equipment": "power_generation",
		"wind_power": "power_generation",
		"road_modules": "vehicle_access",
		"paving_tiles": "pedestrian_surface",
		"road_signage": "traffic_guidance",
		"street_lighting": "street_lighting",
		"traffic_signals": "traffic_control",
		"electrical_infrastructure": "power_distribution",
		"factory_structure_modules": "industrial_structure",
		"factory_entrances": "building_access",
		"factory_floor_modules": "industrial_floor",
		"factory_platforms": "industrial_platform",
		"factory_machines": "industrial_process",
		"conveyor_modules": "material_handling",
		"crane_modules": "material_handling",
	}
	return purposes.get(semantic, semantic)
