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
	"tactical_obstacle", "decorative_prop", "character_reference",
]
const STRUCTURAL_ROLES := [
	"unspecified", "shell", "wall", "corner", "entrance", "window", "roof",
	"floor", "canopy", "road", "intersection", "junction", "roundabout",
	"driveway", "crossing", "slope", "sidewalk", "door", "stairs",
	"platform", "railing", "barrier", "bridge_support", "corridor", "room",
	"gate", "machinery", "conveyor", "pipe", "control", "cargo", "container",
	"sign", "light", "marking", "utility", "character", "detail",
]
const COMPLETENESS := ["unknown", "complete", "fragment", "intentionally_open", "not_applicable"]
const FRONT_FACES := ["unknown", "+z", "-z", "+x", "-x", "axis_neutral"]
const SECONDARY_FRONT_FACES := ["none", "+z", "-z", "+x", "-x"]
const DIRECTIONAL_FACES := ["+z", "-z", "+x", "-x"]
const ATTACHMENTS := ["unknown", "ground", "source_origin", "wall", "overhead", "structural_socket", "ground_surface"]
const REVIEW_FLAGS := ["identity", "working_faces", "connections", "clearance", "assembly"]
const SOCKET_NORMALS := ["+x", "-x", "+y", "-y", "+z", "-z"]

## Rendered from all six local axes. Empty arrays are deliberate axis-neutral
## findings rather than missing data.
const REVIEWED_WORKING_FACES := {
	"city_kit_industrial/building-a": ["-z"],
	"city_kit_industrial/building-b": ["-z"],
	"city_kit_industrial/building-c": ["-z"],
	"city_kit_industrial/building-d": ["-z"],
	"city_kit_industrial/building-e": ["-z"],
	"city_kit_industrial/building-f": ["-z"],
	"city_kit_industrial/building-g": ["+z"],
	"city_kit_industrial/building-l": ["-z"],
	"city_kit_industrial/building-m": ["+z"],
	"city_kit_industrial/building-n": ["-z"],
	"city_kit_industrial/building-p": ["-z"],
	"city_kit_industrial/building-q": ["-z"],
	"city_kit_industrial/building-r": ["-z"],
	"city_kit_industrial/building-s": ["-z"],
	"city_kit_industrial/building-t": ["-z"],
	"city_kit_roads/road-sign-empty": [],
	"city_kit_roads/road-sign-empty-hanging": [],
	"city_kit_roads/road-sign-street": [],
	"city_kit_roads/road-sign-warning": ["-x"],
	"city_kit_roads/sign-highway": ["-z"],
	"city_kit_roads/sign-highway-detailed": ["-z"],
	"city_kit_roads/sign-highway-wide": ["-z"],
	"city_kit_roads/traffic-light-hanging": ["-x"],
	"city_kit_roads/traffic-light-object-hanging": ["-x"],
	"city_kit_roads/traffic-light-object-horizontal": ["-x"],
	"city_kit_roads/traffic-light-object-vertical": ["-x"],
	"factory_kit/button-floor-round": [],
	"factory_kit/button-floor-round-small": [],
	"factory_kit/button-floor-square": [],
	"factory_kit/button-floor-square-small": [],
	"factory_kit/lever-double": ["+z"],
	"factory_kit/lever-single": ["+z"],
	"factory_kit/oopi": ["-x"],
	"factory_kit/screen-flat": ["-z"],
	"factory_kit/screen-hanging-small": ["-z"],
	"factory_kit/screen-hanging-wide": ["-z"],
	"factory_kit/screen-panel-flat": ["-z"],
	"factory_kit/screen-panel-small": ["-z"],
	"factory_kit/screen-panel-wide": ["-z"],
	"factory_kit/screen-small": ["-z"],
	"factory_kit/screen-wide": ["-z"],
	"modular_space_kit/gate": ["+z", "-z"],
	"modular_space_kit/gate-door": ["+z", "-z"],
	"modular_space_kit/gate-door-window": ["+z", "-z"],
	"modular_space_kit/gate-lasers": ["+z", "-z"],
}

const MACHINE_CONNECTION_REVIEWS := {
	"factory_kit/machine-connection-hole": {
		"connections": ["factory_pipe"],
		"sockets": [{"name": "top_pipe_receiver", "type": "factory_pipe", "position": [0.0, 1.293, 0.36], "normal": "+y", "role": "receiver", "example_mate": {"asset": "factory_kit/pipe-large", "asset_socket": [-0.5, 0.5, 0.0], "rotation_degrees": [0.0, 0.0, 90.0], "origin_offset": [0.5, 0.5, 0.0]}}],
		"assembly_notes": "The visible top receiver is centered at native local (0, 1.293, 0.36). A pipe-large -X end mates after +90 degrees around Z with its origin offset (+0.5, +0.5, 0) from this socket. Glass pipes remain a separate network.",
	},
	"factory_kit/machine-connection-pipe": {
		"connections": ["factory_pipe"],
		"sockets": [{"name": "top_pipe_outlet", "type": "factory_pipe", "position": [0.0, 1.75, 0.36], "normal": "+y", "role": "outlet", "example_mate": {"asset": "factory_kit/pipe-large", "asset_socket": [-0.5, 0.5, 0.0], "rotation_degrees": [0.0, 0.0, 90.0], "origin_offset": [0.5, 0.5, 0.0]}}],
		"assembly_notes": "The integrated vertical stub terminates at native local (0, 1.75, 0.36). A pipe-large -X end mates after +90 degrees around Z with its origin offset (+0.5, +0.5, 0) from this socket.",
	},
}

static func default_data() -> Dictionary:
	return {"version": 4, "confirmed": {}}

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
	data.version = 4
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
		result["review_flags"] = confirmed[id].get("review_flags", [])
		result["needs_identification"] = false
	else:
		result["interpretation_source"] = "inferred"
		result["needs_identification"] = "identity" in result.get("review_flags", [])
	result["needs_review"] = not result.get("review_flags", []).is_empty()
	var source_faces: Array
	if confirmed.has(id):
		source_faces = result.get("working_faces", []) if has_confirmed_working_faces else [result.get("front_face", "unknown")]
	else:
		source_faces = result.get("working_faces", [])
		if source_faces.is_empty():
			source_faces = [result.get("front_face", "unknown")]
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
		"sockets": [],
		"generation_ready": false,
		"confidence": "high",
		"evidence": "Classified from source-pack naming and rendered family comparison; procedural eligibility remains separate.",
		"review_flags": [],
		"orientation_notes": "Axis-neutral or not required for this role.",
		"clearance_notes": "Use calibrated visual bounds; no additional semantic clearance established.",
		"assembly_notes": "Standalone visual unless a module authors stricter placement behavior.",
		"notes": "",
	}
	_apply_family_traits(record, id, semantic)
	_apply_reviewed_findings(record, id, semantic)
	return record

static func _apply_reviewed_findings(record: Dictionary, id: String, semantic: String) -> void:
	if REVIEWED_WORKING_FACES.has(id):
		var faces: Array = REVIEWED_WORKING_FACES[id]
		record["working_faces"] = faces.duplicate()
		record["front_face"] = faces[0] if not faces.is_empty() else "axis_neutral"
		record.review_flags.erase("working_faces")
		record["orientation_notes"] = _reviewed_orientation_note(id, semantic, faces)
		record["evidence"] = "Reviewed from labeled local-axis renders of the imported GLB; calibration yaw remains separate."
	if semantic == "machine_components":
		var animated := id.get_file().begins_with("piston-")
		record["completeness"] = "complete"
		record["attachment"] = "ground"
		record["connections"] = []
		record["sockets"] = []
		record.review_flags.erase("connections")
		record["evidence"] = "Six-axis geometry review found no keyed mating surface; matching envelopes alone are not treated as connection evidence."
		record["assembly_notes"] = "Animated standalone piston machinery; preserve its AnimationPlayer and author clearance around its vertical stroke." if animated else "Standalone cog machinery/decoration. Its central bore is not a verified socket; combine only in an authored composition."
	if semantic == "factory_machines":
		record.review_flags.erase("connections")
		record["connections"] = []
		record["sockets"] = []
		record["evidence"] = "Reviewed from six-axis renders, native bounds, pivots, and explicit seam assemblies."
		if MACHINE_CONNECTION_REVIEWS.has(id):
			record.merge(MACHINE_CONNECTION_REVIEWS[id], true)
		elif id.get_file() == "machine-bed":
			record["assembly_notes"] = "Complete large machine-bed variant with no verified external socket; do not join it to another machine solely because envelopes overlap."
		else:
			record["assembly_notes"] = "Complete machine-body variant with no verified external socket. Its top detail is not a general-purpose mount."

static func _reviewed_orientation_note(id: String, semantic: String, faces: Array) -> String:
	if faces.is_empty():
		if id.get_file().begins_with("button-floor-"):
			return "Top-actuated floor control; no horizontal working face."
		return "Geometry has no unique horizontal operating face; placement topology remains separate."
	if semantic == "industrial_buildings":
		return "Door, loading-bay, and window composition identifies the reviewed street/service facade."
	if semantic == "road_signage":
		return "Colored sign panel identifies the reviewed traffic-facing side."
	if semantic == "traffic_signals":
		return "Signal lenses identify the reviewed traffic-facing side."
	if semantic == "controls_and_switches":
		return "Control handle presentation identifies the reviewed operator side."
	if semantic == "screens_and_panels":
		return "Dark display surface identifies the reviewed operator/viewing side."
	if semantic == "space_gates":
		return "Gate passage is bidirectional along local Z; +Z and -Z are equal working faces."
	if semantic == "easter_egg_character":
		return "Oopi's visible face points toward local -X."
	return "Reviewed from labeled local-axis renders."

static func socket_summary(sockets: Array) -> String:
	if sockets.is_empty():
		return "none"
	var parts: Array[String] = []
	for value in sockets:
		var socket: Dictionary = value
		parts.append("%s:%s %s @ %s" % [socket.get("name", "socket"), socket.get("type", "unknown"), socket.get("normal", "?"), socket.get("position", [])])
	return "; ".join(parts)

static func _apply_family_traits(record: Dictionary, id: String, semantic: String) -> void:
	var name := id.get_file()
	if semantic == "easter_egg_character":
		record.merge({"asset_kind": "character_reference", "structural_role": "character", "completeness": "complete", "attachment": "ground", "confidence": "medium", "contexts": ["easter_egg"], "review_flags": ["working_faces"], "evidence": "The exact Oopi filename and rendered alien form match Kenney's Oopi character; retained as a non-environment reference.", "orientation_notes": "Character-facing direction remains to be confirmed.", "clearance_notes": "Character reference only; do not derive tactical occupancy.", "assembly_notes": "Standalone easter egg, not an environment module."}, true)
	elif semantic == "industrial_buildings":
		record.merge({"asset_kind": "complete_building", "structural_role": "shell", "completeness": "complete", "attachment": "ground", "review_flags": ["working_faces"], "orientation_notes": "Complete sealed exterior shell; select a street face only when a parcel needs one.", "clearance_notes": "Reserve the calibrated envelope plus entrance/service access where visible.", "assembly_notes": "Use as an exterior-only monolithic building; it does not provide an accessible interior."}, true)
	elif semantic == "cargo_containers":
		record.merge({"asset_kind": "tactical_obstacle", "structural_role": "container", "completeness": "complete", "front_face": "+z", "working_faces": ["+z"], "orientation_notes": "Long axis Z; cargo doors face local +Z.", "clearance_notes": "Keep door-side working clearance when access matters."}, true)
	elif semantic == "industrial_chimneys":
		record.merge({"asset_kind": "utility_infrastructure", "structural_role": "utility", "completeness": "complete", "front_face": "axis_neutral", "orientation_notes": "Vertical exhaust stack; rotationally neutral.", "clearance_notes": "Tall landmark envelope; reserve base access and overhead clearance."}, true)
	elif semantic == "tanks_and_towers":
		record.merge({"asset_kind": "equipment", "structural_role": "machinery", "completeness": "complete", "front_face": "axis_neutral", "orientation_notes": "Freestanding storage vessel or tower.", "clearance_notes": "Reserve full base and maintenance clearance; do not infer solidity from the AABB alone."}, true)
	elif semantic in ["solar_equipment", "wind_power"]:
		record.merge({"asset_kind": "utility_infrastructure", "structural_role": "utility", "completeness": "complete", "front_face": "axis_neutral", "orientation_notes": "Freestanding power-generation equipment.", "clearance_notes": "Grouped panels and turbine blades require their complete visual envelope."}, true)
	elif semantic == "bridge_structures":
		record.merge({"asset_kind": "structural_fragment", "structural_role": "bridge_support", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["road_bridge_support"], "assembly_notes": "Supports the road-bridge deck; never use as a freestanding complete structure."}, true)
	elif semantic in ["construction_safety", "waste_props"]:
		var tactical := name in ["construction-barrier", "construction-fence", "dumpster"]
		record.merge({"asset_kind": "tactical_obstacle" if tactical else "decorative_prop", "structural_role": "barrier" if "barrier" in name or "fence" in name else "detail", "completeness": "complete", "front_face": "axis_neutral", "clearance_notes": "Roadside safety furniture; tactical behavior requires an authored module."}, true)
	elif semantic == "electrical_infrastructure":
		var wires_only := name.begins_with("electricity-wires")
		record.merge({"asset_kind": "utility_infrastructure", "structural_role": "utility", "completeness": "fragment", "attachment": "overhead" if wires_only else "ground", "front_face": "axis_neutral", "connections": ["electricity_span"], "clearance_notes": "Maintain the authored pole/wire span and overhead clearance.", "assembly_notes": "Single, side and wide variants form one electrical distribution family."}, true)
	elif semantic == "street_lighting":
		record.merge({"asset_kind": "utility_infrastructure", "structural_role": "light", "completeness": "complete", "front_face": "axis_neutral", "clearance_notes": "Place outside the vehicle and pedestrian clear path."}, true)
	elif semantic == "road_signage":
		var component := name.begins_with("road-sign-object-")
		record.merge({"asset_kind": "structural_fragment" if component else "decorative_prop", "structural_role": "sign", "completeness": "fragment" if component else "complete", "attachment": "structural_socket" if component else "ground", "review_flags": [] if component else ["working_faces"], "connections": ["road_sign_mount"] if component else [], "orientation_notes": "Sign face is directional; confirm the local face before placement."}, true)
	elif semantic == "traffic_signals":
		var component := name.begins_with("traffic-light-object-")
		record.merge({"asset_kind": "structural_fragment" if component else "utility_infrastructure", "structural_role": "light", "completeness": "fragment" if component else "complete", "attachment": "structural_socket" if component else "ground", "review_flags": ["working_faces"], "connections": ["traffic_signal_mount"] if component else [], "orientation_notes": "Signal lenses are directional; confirm the local traffic-facing side."}, true)
	elif semantic == "road_barrier_modules":
		record.merge({"asset_kind": "structural_fragment", "structural_role": "barrier", "completeness": "fragment", "attachment": "ground_surface", "front_face": "axis_neutral", "connections": ["road_edge"], "assembly_notes": "Rendered inspection confirms this is an edge/barrier overlay, not a complete road surface."}, true)
	elif semantic == "road_modules":
		record.merge({"asset_kind": "ground_infrastructure", "structural_role": _road_role(name), "completeness": "fragment", "attachment": "ground_surface", "front_face": "axis_neutral", "connections": _road_connections(name), "orientation_notes": "Road topology is encoded by named edges; no semantic working face.", "assembly_notes": "Join only through compatible road, sidewalk and elevation edges."}, true)
	elif semantic == "paving_tiles":
		record.merge({"asset_kind": "ground_infrastructure", "structural_role": "sidewalk", "completeness": "fragment", "attachment": "ground_surface", "front_face": "axis_neutral", "connections": ["paving_edge"], "assembly_notes": "Tile variants form level or sloped pedestrian surfaces."}, true)
	elif semantic == "floor_markings":
		record.merge({"asset_kind": "decorative_prop", "structural_role": "marking", "completeness": "complete", "attachment": "ground_surface", "front_face": "axis_neutral", "clearance_notes": "Surface marking has no independent tactical occupancy."}, true)
	elif semantic == "cargo_boxes":
		record.merge({"asset_kind": "tactical_obstacle", "structural_role": "cargo", "completeness": "complete", "front_face": "axis_neutral", "clearance_notes": "Freestanding cargo; tactical cover and stacking remain module-authored."}, true)
	elif semantic == "controls_and_switches":
		record.merge({"asset_kind": "equipment", "structural_role": "control", "completeness": "complete", "attachment": "ground", "review_flags": ["working_faces"], "clearance_notes": "Reserve an operator side when the control is interactive."}, true)
	elif semantic == "catwalk_modules":
		var role := "stairs" if "stairs" in name else ("corner" if "corner" in name else ("junction" if "junction" in name or "cross" in name else "platform"))
		record.merge({"asset_kind": "structural_fragment", "structural_role": role, "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["factory_catwalk"], "clearance_notes": "Preserve walking surface and vertical clearance.", "assembly_notes": "Rotation-aware catwalk network module."}, true)
	elif semantic == "machine_components":
		record.merge({"asset_kind": "equipment", "structural_role": "machinery", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["factory_machine_mount"], "review_flags": ["connections"], "assembly_notes": "Rendered as a machine component; exact supported mounts remain to be authored."}, true)
	elif semantic == "safety_props":
		record.merge({"asset_kind": "decorative_prop", "structural_role": "detail", "completeness": "complete", "front_face": "axis_neutral"}, true)
	elif semantic == "conveyor_modules":
		record.merge({"asset_kind": "equipment", "structural_role": "conveyor", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["factory_conveyor"], "clearance_notes": "Reserve belt path and side guards; slope variants also require vertical clearance.", "assembly_notes": "Connect end, middle, corner, T and cross variants within the conveyor family."}, true)
	elif semantic == "crane_modules":
		var attachment_piece := name != "crane"
		record.merge({"asset_kind": "equipment", "structural_role": "machinery", "completeness": "fragment" if attachment_piece else "complete", "attachment": "structural_socket" if attachment_piece else "ground", "connections": ["factory_crane_attachment"], "front_face": "axis_neutral", "clearance_notes": "Reserve the boom swing and suspended-load volume.", "assembly_notes": "Lift and magnet are crane attachments; the crane is a complete freestanding machine."}, true)
	elif semantic in ["factory_doors", "factory_entrances"]:
		record.merge({"asset_kind": "structural_fragment", "structural_role": "entrance" if semantic == "factory_entrances" else "door", "completeness": "fragment", "attachment": "structural_socket", "front_face": "+z", "working_faces": ["+z"], "connections": ["factory_bay"], "orientation_notes": "Opening crosses Z and the reviewed factory facade convention faces local +Z.", "clearance_notes": "Keep the opening and door travel volume clear."}, true)
	elif semantic == "factory_floor_modules":
		record.merge({"asset_kind": "ground_infrastructure", "structural_role": "floor", "completeness": "fragment", "attachment": "ground_surface", "front_face": "axis_neutral", "connections": ["factory_floor_edge"]}, true)
	elif semantic == "hoppers":
		record.merge({"asset_kind": "equipment", "structural_role": "machinery", "completeness": "complete", "attachment": "ground", "front_face": "axis_neutral", "clearance_notes": "Preserve loading clearance above and discharge clearance below."}, true)
	elif semantic == "factory_machines":
		record.merge({"asset_kind": "equipment", "structural_role": "machinery", "completeness": "complete", "attachment": "ground", "front_face": "+z", "working_faces": ["+z"], "connections": ["factory_machine_port"], "review_flags": ["connections"], "orientation_notes": "Rendered variants share a local +Z operating/open face.", "clearance_notes": "Reserve the open operating side and any top pipe connection."}, true)
	elif semantic == "pipe_modules":
		record.merge({"asset_kind": "equipment", "structural_role": "pipe", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["factory_glass_pipe" if name.begins_with("pipe-glass-") else "factory_pipe"], "assembly_notes": "Large opaque and glass pipes are separate but dimensionally related networks."}, true)
	elif semantic == "robotics":
		record.merge({"asset_kind": "equipment", "structural_role": "machinery", "completeness": "complete", "attachment": "ground", "front_face": "axis_neutral", "clearance_notes": "Reserve a radial operating envelope around the articulated arm."}, true)
	elif semantic == "scanners":
		record.merge({"asset_kind": "open_structure", "structural_role": "gate", "completeness": "intentionally_open", "attachment": "ground", "front_face": "axis_neutral", "connections": ["factory_passage"], "clearance_notes": "Keep the scanner opening traversable; its AABB is not solid occupancy."}, true)
	elif semantic == "screens_and_panels":
		var hanging := "hanging" in name
		record.merge({"asset_kind": "equipment", "structural_role": "control", "completeness": "complete", "attachment": "overhead" if hanging else "ground", "review_flags": ["working_faces"], "clearance_notes": "Reserve sight and operator clearance on the display side."}, true)
	elif semantic == "factory_structure_modules":
		var role := _structural_role(id, semantic)
		var faces: Array = ["+z", "+x"] if name == "structure-corner-inner" else (["-z", "-x"] if name == "structure-corner-outer" else (["+z"] if role in ["wall", "window"] else []))
		var flags: Array = []
		record.merge({"asset_kind": "structural_fragment", "structural_role": role, "completeness": "fragment", "attachment": "structural_socket", "front_face": faces[0] if not faces.is_empty() else "unknown", "working_faces": faces, "connections": ["factory_bay"], "review_flags": flags, "orientation_notes": "Factory bay facade convention uses local +Z; corners may expose two equal working faces.", "assembly_notes": "Wall, window and corner pieces require a structural assembly and roof/floor coverage."}, true)
	elif semantic == "factory_railings":
		record.merge({"asset_kind": "structural_fragment", "structural_role": "railing", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["factory_railing"], "assembly_notes": "Rendered inspection identifies these height variants as post-and-rail modules, not walls."}, true)
	elif semantic == "factory_platforms":
		record.merge({"asset_kind": "ground_infrastructure", "structural_role": "platform", "completeness": "fragment", "attachment": "ground_surface", "front_face": "axis_neutral", "connections": ["factory_platform_edge"]}, true)
	elif semantic == "safety_indicators":
		record.merge({"asset_kind": "utility_infrastructure", "structural_role": "light", "completeness": "complete", "attachment": "ground", "front_face": "axis_neutral"}, true)
	elif semantic == "space_utilities":
		record.merge({"asset_kind": "decorative_prop", "structural_role": "utility", "completeness": "complete", "attachment": "ground_surface", "front_face": "axis_neutral", "clearance_notes": "Loose cable dressing; no independent tactical effect."}, true)
	elif semantic == "space_corridors":
		record.merge({"asset_kind": "structural_fragment", "structural_role": "corridor", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["space_corridor"], "clearance_notes": "Preserve the walkable corridor opening.", "assembly_notes": "Open-top presentation is intentional for tactical visibility; connect only on named corridor edges."}, true)
	elif semantic == "space_gates":
		record.merge({"asset_kind": "structural_fragment", "structural_role": "gate", "completeness": "fragment", "attachment": "structural_socket", "review_flags": ["working_faces"], "connections": ["space_corridor"], "clearance_notes": "Keep the gate opening and moving/laser volume clear."}, true)
	elif semantic == "space_rooms":
		record.merge({"asset_kind": "open_structure", "structural_role": "room", "completeness": "intentionally_open", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["space_corridor"], "clearance_notes": "Interior floor is intended to remain accessible.", "assembly_notes": "Complete open-top room module for tactical cutaway presentation; connection edges remain modular."}, true)
	elif semantic == "space_stairs":
		record.merge({"asset_kind": "structural_fragment", "structural_role": "stairs", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["space_floor", "space_vertical"], "clearance_notes": "Preserve stair run, landing and headroom."}, true)
	elif semantic == "space_floor_modules":
		var raised := "layer" in name
		record.merge({"asset_kind": "structural_fragment" if raised else "ground_infrastructure", "structural_role": "platform" if raised else "floor", "completeness": "fragment", "attachment": "structural_socket" if raised else "ground_surface", "front_face": "axis_neutral", "connections": ["space_floor"], "clearance_notes": "Layer variants require vertical support and under-platform clearance."}, true)
	elif semantic == "space_wall_modules":
		var role := _structural_role(id, semantic)
		record.merge({"asset_kind": "structural_fragment", "structural_role": role, "completeness": "fragment", "attachment": "structural_socket", "front_face": "+z" if role == "wall" else "axis_neutral", "working_faces": ["+z"] if role == "wall" else [], "connections": ["space_wall"], "orientation_notes": "Reviewed template-wall interior convention faces local +Z.", "assembly_notes": "Space-kit wall grammar is independent from Factory Kit bay dimensions."}, true)
	elif semantic == "space_details":
		record.merge({"asset_kind": "structural_fragment", "structural_role": "detail", "completeness": "fragment", "attachment": "structural_socket", "front_face": "axis_neutral", "connections": ["space_structure"]}, true)
	else:
		record.merge({"asset_kind": "unknown", "structural_role": "unspecified", "completeness": "unknown", "attachment": "unknown", "confidence": "low", "contexts": [], "review_flags": ["identity", "working_faces", "connections", "assembly"], "evidence": "Rendered model and filename do not establish a reliable function.", "orientation_notes": "Unknown.", "clearance_notes": "Unknown.", "assembly_notes": "Unknown."}, true)

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
		if name.begins_with("road-") and "barrier" in name: return "road_barrier_modules"
		if name.begins_with("road-"): return "road_modules"
	if id.begins_with("factory_kit/"):
		if name == "oopi": return "easter_egg_character"
		if name.begins_with("arrow") or name.begins_with("indicator-special-"): return "floor_markings"
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
		if name.begins_with("structure-yellow-") or name in ["structure-high", "structure-medium", "structure-short", "structure-tall"]: return "factory_railings"
		if name.begins_with("structure-"): return "factory_structure_modules"
		if name.begins_with("top"): return "factory_platforms"
		if name.begins_with("warning-"): return "safety_indicators"
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

static func _road_role(name: String) -> String:
	if "roundabout" in name: return "roundabout"
	if "crossroad" in name or "intersection" in name or "split" in name: return "intersection"
	if "driveway" in name: return "driveway"
	if "crossing" in name: return "crossing"
	if "slant" in name: return "slope"
	return "road"

static func _road_connections(name: String) -> Array[String]:
	var result: Array[String] = ["road_edge"]
	if "path" in name or "side" in name or "pavement" in name or "sidewalk" in name or "driveway" in name:
		result.append("paving_edge")
	if "slant" in name or "bridge" in name:
		result.append("road_elevation")
	return result

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

static func needs_review(id: String, data := {}) -> bool:
	return bool(effective(id, data).needs_review)

static func audit(ids: Array, data := {}) -> Dictionary:
	if data.is_empty(): data = load_data()
	var result := {
		"total": ids.size(), "confirmed": 0, "catalog_classified": 0,
		"needs_review": 0, "unknown_identity": 0, "generation_ready": 0,
		"categories": {}, "review_flags": {},
	}
	for value in ids:
		var record := effective(str(value), data)
		if record.interpretation_source == "confirmed": result.confirmed += 1
		else: result.catalog_classified += 1
		if record.needs_review: result.needs_review += 1
		if record.needs_identification: result.unknown_identity += 1
		if record.generation_ready: result.generation_ready += 1
		result.categories[record.semantic_category] = int(result.categories.get(record.semantic_category, 0)) + 1
		for flag in record.review_flags:
			result.review_flags[flag] = int(result.review_flags.get(flag, 0)) + 1
	return result

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
	if "stairs" in name: return "stairs"
	if "wall" in name: return "wall"
	if "floor" in name or semantic in ["factory_floor_modules", "space_floor_modules"]: return "floor"
	if semantic == "space_corridors": return "corridor"
	if semantic == "space_rooms": return "room"
	if semantic == "road_modules": return _road_role(name)
	if semantic == "paving_tiles": return "sidewalk"
	return "unspecified"

static func _contexts_for(semantic: String) -> Array[String]:
	if semantic == "easter_egg_character": return ["easter_egg"]
	if semantic.begins_with("space_"): return ["space_facility"]
	if semantic in ["road_modules", "road_barrier_modules", "paving_tiles", "road_signage", "street_lighting", "traffic_signals", "electrical_infrastructure", "construction_safety", "waste_props"]: return ["industrial", "commercial", "mixed_service"]
	if semantic in ["industrial_buildings", "industrial_chimneys", "tanks_and_towers", "wind_power", "solar_equipment", "factory_machines", "conveyor_modules", "crane_modules", "hoppers", "robotics"]: return ["industrial"]
	if semantic in ["factory_structure_modules", "factory_railings", "factory_entrances", "factory_floor_modules", "factory_platforms", "scanners", "screens_and_panels"]: return ["industrial", "mixed_service"]
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
		"road_barrier_modules": "road_edge_safety",
		"paving_tiles": "pedestrian_surface",
		"road_signage": "traffic_guidance",
		"street_lighting": "street_lighting",
		"traffic_signals": "traffic_control",
		"electrical_infrastructure": "power_distribution",
		"factory_structure_modules": "industrial_structure",
		"factory_railings": "industrial_safety_railing",
		"factory_entrances": "building_access",
		"factory_floor_modules": "industrial_floor",
		"factory_platforms": "industrial_platform",
		"factory_machines": "industrial_process",
		"conveyor_modules": "material_handling",
		"crane_modules": "material_handling",
		"space_corridors": "space_facility_circulation",
		"space_rooms": "space_facility_room",
		"space_gates": "space_facility_access",
		"space_stairs": "space_vertical_access",
		"easter_egg_character": "character_reference",
	}
	return purposes.get(semantic, semantic)
