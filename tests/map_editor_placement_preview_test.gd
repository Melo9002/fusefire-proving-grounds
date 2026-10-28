extends SceneTree
class EditorHarness extends "res://tools/map_editor.gd":
	var rebuilds := 0
	func _rebuild() -> void: rebuilds += 1
	func _select_placement_index(index: int) -> void:
		inspection_module.set_meta("placement_id", custom_layout.placements[index].placement_id)

var failures := 0
func _initialize(): _run.call_deferred()
func _run():
	var editor := EditorHarness.new()
	editor.preview_map_size = Vector2i(40, 30)
	var layout := EnvironmentModuleLayout.new(&"preview_test")
	for x in [8, 18]:
		check(layout.try_add(editor.editor_catalog.cargo_container, EnvironmentModulePlacement.new(&"cargo_container", Vector2i(x, 10)), editor.preview_map_size), "cargo fixture fits")
	editor.custom_document = BattlefieldLayoutDocument.from_authored(layout, editor.preview_map_size, &"industrial_district", "preview_test")
	editor.custom_layout = editor.custom_document.to_module_layout(editor.editor_catalog)
	editor.inspection_module = Node3D.new()
	editor._select_placement_index(0)
	var original := editor.custom_document.to_json()
	var original_id := editor.custom_layout.placements[0].placement_id
	editor._duplicate_selected_placement()
	check(editor.preview_placement != null and not editor._placement_preview_error().is_empty(), "overlapping duplicate remains a visible pending candidate")
	check(not editor._confirm_placement_preview() and editor.custom_document.to_json() == original, "overlap cannot confirm or mutate document")
	for i in 8: editor._rotate_selected_placement(1)
	check(editor.rebuilds == 0 and editor.custom_document.to_json() == original, "repeated rotations do not compile or rebuild committed map")
	editor._move_selected_placement(Vector2i(0, 8))
	check(editor._placement_preview_error().is_empty(), "preview can move away from obstruction")
	check(editor._confirm_placement_preview(), "legal duplicate confirms through real compiler")
	check(editor.custom_layout.placements.size() == 3 and editor.custom_layout.placements.back().placement_id != original_id and editor.rebuilds == 1, "confirm creates one fresh identity and rebuild")
	check(editor.pending_compilation.ok, "confirmed compilation is available for one-use presentation")
	editor._select_placement_index(0)
	original = editor.custom_document.to_json()
	editor._rotate_selected_placement(1)
	check(not editor.inspection_module.visible, "original hidden only while transform preview is active")
	editor._cancel_placement_preview()
	check(editor.custom_document.to_json() == original and editor.inspection_module.visible and editor.preview_placement == null, "cancel restores original without consuming identity or changing document")
	editor._rotate_selected_placement(1)
	check(editor._confirm_placement_preview(), "rotation confirms")
	check(editor.custom_layout.placements[0].placement_id == original_id and editor.custom_layout.placements[0].rotation == 1, "confirmed rotation preserves identity")
	# Spatially clear but deliberately protected mission space must still reject.
	editor._select_placement_index(0)
	editor._duplicate_selected_placement()
	editor._move_selected_placement(Vector2i(12, 7))
	var at := editor.preview_placement.origin
	editor.custom_document.spatial_layout["reservations"] = [{"reservation_id": "protected", "role": "deployment_region", "owner_ref": "zone:protected", "scope": "whole_column", "cells": [[at.x, at.y]], "required": true}]
	editor.custom_document.mission_context = {"status": "preserved", "zone_source": "test", "zones": [{"zone_id": "protected", "kind": MapZoneData.Kind.OBJECTIVE, "faction": -1, "cells": [[at.x, 0, at.y]]}]}
	var protected_document := editor.custom_document.to_json()
	var probe := editor.custom_document.duplicate_placements([original_id], at - editor.custom_layout.placements[0].origin, editor.editor_catalog)
	check(probe.ok and probe.document.validate().any(func(issue): return issue.code == "RESERVED_REGION_BLOCKED"), "negative fixture fails for protected space, not malformed metadata")
	check(not editor._confirm_placement_preview() and editor.preview_placement != null and editor.custom_document.to_json() == protected_document, "full validation rejects invalid commit without losing preview or original")
	editor._cancel_placement_preview()
	editor.inspection_module.free()
	editor.free()
	print("Placement preview: %d failure(s)" % failures)
	quit(1 if failures else 0)
func check(value: bool, message: String):
	print(("PASS: " if value else "FAIL: ") + message)
	if not value: failures += 1
