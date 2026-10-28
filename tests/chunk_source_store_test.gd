extends SceneTree
const Source = preload("res://systems/generation/environment_chunk_source.gd")
const Store = preload("res://tools/chunk_source_store.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var directory := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").path_join("t05-drafts")
	if directory == "t05-drafts": directory = "res://artifacts/t05-drafts"
	var source := Source.new("unfinished_yard", "Unfinished yard")
	source.data.bounds = [7, 13]
	source.data.height = 4
	var id := source.add_instance(EnvironmentModulePlacement.new(&"missing_future_component", Vector2i(-2, 20)))
	source.data.ports.append({"id": "gate", "role": "", "profile": "", "cells": [], "normal": [0, 1], "elevation": 0, "minimum_width": 2, "connection": "required"})
	source.data.clearances.append({"id": "access", "cells": [[1, 0, 1]], "height": 2.0, "scope": "floor"})
	source.data.tactical.surfaces.append({"cell": [0, 0, 0], "values": {"walkable": true}})
	source.data.tactical.effects.append({"cell": [2, 0, 1], "values": {"walkable": false, "cover_type": 2}, "layer": 1})
	source.data.tactical.links.append({"from": [0, 0, 0], "to": [0, 3, 0], "kind": 0, "bidirectional": true})
	check(Source.source_errors(source.data).is_empty(), "incomplete local source is structurally valid")
	check(not source.draft_diagnostics().is_empty(), "incomplete draft is not mistaken for complete content")
	check(Store.save_named(source, directory, "Yard draft").ok, "named incomplete draft saves")
	var loaded := Store.load_named(directory, "Yard draft")
	check(loaded.ok and _normalized(loaded.source) == _normalized(source), "all explicit fields round-trip without requiring playability")
	if not loaded.ok:
		print(loaded)
		quit(1)
		return
	var another := Source.new("other", "Other")
	check(Store.save_named(another, directory, "Second draft").ok, "second named draft has independent destination")
	var instance_a: EnvironmentChunkSource = loaded.source.copy()
	var instance_b: EnvironmentChunkSource = loaded.source.copy()
	instance_a.data.instances[0].origin[0] = 99
	instance_a.data.ports[0].cells.append([0, 0])
	instance_a.data.tactical.effects[0].values.walkable = true
	check(instance_b.data.instances[0].origin[0] == -2 and instance_b.data.ports[0].cells.is_empty() and not instance_b.data.tactical.effects[0].values.walkable, "two uses of source own independent nested records")
	check(instance_b.data.instances[0].placement_id == id, "local identity survives independent copy")
	var next := instance_b.add_instance(EnvironmentModulePlacement.from_record(instance_b.data.instances[0]))
	check(next != id, "shared allocator gives added copy fresh identity")
	var before := FileAccess.get_file_as_string(Store.path_for(directory, "Yard draft"))
	for mutation in ["version", "fraction", "duplicate", "missing_id", "mission", "approval", "wrong_type", "effect", "dependency", "non_json"]:
		var broken := source.copy()
		match mutation:
			"version": broken.data.schema_version = 999
			"fraction": broken.data.instances[0].origin[0] = 1.25
			"duplicate": broken.data.instances.append(broken.data.instances[0].duplicate(true))
			"missing_id": broken.data.instances[0].erase("placement_id")
			"mission": broken.data["mission_context"] = {}
			"approval": broken.data["owner_visual_approval"] = true
			"wrong_type": broken.data.ports = "bad"
			"effect": broken.data.tactical.effects[0].values.walkable = "false"
			"dependency": broken.data.dependencies = [{"kind": "module", "id": "cargo_container", "revision": 123}]
			"non_json": broken.data.provenance["bad"] = Vector3.ZERO
		if mutation != "non_json":
			var decoded := Store.decode(Store.encode(broken))
			check(not decoded.ok and decoded.source == null, mutation + " rejects without replacement source")
		check(not Store.save_named(broken, directory, "Yard draft").ok and FileAccess.get_file_as_string(Store.path_for(directory, "Yard draft")) == before, mutation + " invalid save preserves existing file")
	check(not Store.decode("{broken").ok, "malformed JSON rejects")
	check(Store.path_for(directory, "../outside").is_empty() and Store.path_for(directory, "CON").is_empty(), "names cannot escape directory or use reserved device name")
	source.data.name = "Revised draft"
	check(Store.save_named(source, directory, "Yard draft").ok and Store.load_named(directory, "Yard draft").source.data.name == "Revised draft", "atomic replacement saves valid revisions")
	_pinned_draft(directory)
	_legacy(directory)
	print("Chunk source/store: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _pinned_draft(directory: String) -> void:
	var context := EnvironmentResolutionContext.new()
	var source := Source.new("pinned", "Pinned draft")
	source.data.bounds = [20, 20]
	source.data.height = 10
	source.add_instance(EnvironmentModulePlacement.new(&"cargo_container", Vector2i(3, 3)))
	var layout := EnvironmentModuleLayout.new(&"pinned")
	layout.placements.append(EnvironmentModulePlacement.from_record(source.data.instances[0]))
	var reference_document := BattlefieldLayoutDocument.from_authored(layout, Vector2i(20, 20), &"industrial_district", "pinned", null, context)
	source.data.dependencies = reference_document.dependencies.duplicate(true)
	check(source.draft_diagnostics(context).is_empty(), "shared geometry/dependency diagnostics accept current pinned component")
	for dependency in source.data.dependencies:
		if dependency.kind == "module": dependency.revision = "old_revision"
	check(source.draft_diagnostics(context).any(func(issue): return issue.code == "STALE_MODULE_DEPENDENCY"), "stale source dependency is diagnosed using shared resolver")
	check(Store.save_named(source, directory, "Stale draft").ok and Store.load_named(directory, "Stale draft").ok, "stale dependency can still be saved as editable draft")
	check(source.data.dependencies.any(func(dep): return dep.get("revision", "") == "old_revision"), "diagnosis/save never refresh stale pins")

func _legacy(directory: String) -> void:
	var path := "res://tools/map_editor/layouts/starter_layout.json"
	var original := FileAccess.get_file_as_string(path)
	check(not Store.decode(original).ok, "ordinary source load never silently imports legacy layout")
	var first := Store.import_legacy(original, "starter_copy", "Starter copy")
	var second := Store.import_legacy(original, "starter_copy", "Starter copy")
	check(first.ok and second.ok and _normalized(first.source) == _normalized(second.source), "explicit legacy import assigns deterministic identities")
	check(first.diagnostics.size() >= 3 and first.source.data.dependencies.is_empty() and not first.source.data.has("mission_context"), "legacy information loss is diagnosed without inventing dependencies or mission binding")
	check(FileAccess.get_file_as_string(path) == original and Store.save_named(first.source, directory, "Imported starter").ok, "import preserves original and saves separately")
	var document_text := FileAccess.get_file_as_string("res://docs/architecture/examples/persisted-edited-industrial-layout.json")
	var old := Store.import_legacy(document_text, "historical", "Historical draft")
	check(old.ok and not old.source.data.dependencies.is_empty(), "stale battlefield imports as draft with original dependency pins")
	check(old.ok and not old.source.data.has("mission_context") and not old.source.data.has("owner_visual_approval"), "battlefield import strips world binding and never certifies")
	var unsupported: Dictionary = JSON.parse_string(original)
	unsupported.schema_version = 42
	check(not Store.import_legacy(JSON.stringify(unsupported), "bad", "Bad").ok, "unsupported legacy version rejects explicitly")
	unsupported = JSON.parse_string(original)
	unsupported.placements[0]["placement_id"] = "keep_me"
	var identified := Store.import_legacy(JSON.stringify(unsupported), "ids", "IDs")
	check(identified.ok and identified.source.data.instances[0].placement_id == "keep_me", "explicit importer preserves existing stable identity")
	unsupported = JSON.parse_string(original)
	unsupported.placements[0].rotation = 0.5
	check(not Store.import_legacy(JSON.stringify(unsupported), "bad", "Bad").ok, "legacy import never truncates fractional transforms")
func _normalized(source: EnvironmentChunkSource) -> String: return JSON.stringify(JSON.parse_string(Store.encode(source)), "", true)
func check(condition: bool, message: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition: failures += 1
