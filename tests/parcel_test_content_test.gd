extends SceneTree
const Content = preload("res://systems/generation2/local_parcel_content.gd")
const Parcels = preload("res://systems/generation2/authored_parcel_catalog.gd")
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
var failures := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/local-content-test-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var source = Parcels.get_definition(Parcels.LOADING_YARD_A)
	var archived := Content.archive(source.scene)
	check(not archived.has("error"), "Preserve a parcel test snapshot: %s" % archived.get("error", ""))
	if archived.has("error"): quit(1); return
	var content: Dictionary = archived.content
	check(Content.validate(content).is_empty(), "A snapshot verifies its own file and project dependencies")
	var data := Catalog.generate(Catalog.PARCEL_TEST, source.size, 17, 1, {"local_content": content})
	check(data.generation_errors.is_empty(), "The local parcel uses Generation 2: %s" % [data.generation_errors])
	check(data.map_size == source.size and data.content_manifest.placements.size() == 1, "Local testing uses one exact parcel footprint")
	var restored := Catalog.generate(Catalog.PARCEL_TEST, source.size, 999, 1, data.content_manifest)
	check(restored.generation_errors.is_empty() and restored.content_manifest == data.content_manifest, "Exact reconstruction preserves local content and population choices")
	var recording := Recording.new()
	recording.configuration = {"battlefield_id": Catalog.PARCEL_TEST, "map_size": source.size, "content_manifest": data.content_manifest}
	var json := recording.to_dictionary()
	var decoded := Recording.from_dictionary(JSON.parse_string(JSON.stringify(json)))
	check(decoded.configuration.content_manifest.local_content == content, "Replay serialization retains the immutable snapshot dependency")
	var bad := content.duplicate(true)
	bad.snapshot = "../outside"
	check(Content.validate(bad) == "INVALID_LOCAL_PARCEL_HASH", "A replay cannot supply an arbitrary scene path")
	bad = content.duplicate(true)
	bad.dependencies.clear()
	check(Content.validate(bad) == "CHANGED_LOCAL_PARCEL_DEPENDENCIES", "Missing dependency fingerprints reject rather than bypass validation")
	bad = content.duplicate(true)
	bad.snapshot = "0".repeat(64)
	check(Content.validate(bad).begins_with("MISSING_LOCAL_PARCEL_SNAPSHOT"), "Unavailable content is rejected explicitly")
	var stage := Node3D.new()
	root.add_child(stage)
	check(Catalog.present(data, stage, 1), "Presentation reconstructs the same local parcel without editor dependencies")
	stage.free()
	if archived.created:
		DirAccess.remove_absolute(Content.snapshot_path(content.snapshot))
		check(Content.validate(content).begins_with("MISSING_LOCAL_PARCEL_SNAPSHOT"), "Missing local content gives a reproducible failure")
	print("Parcel test content: %d failure(s)" % failures)
	quit(1 if failures else 0)
