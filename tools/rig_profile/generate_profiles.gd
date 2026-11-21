extends SceneTree
## Regenerates the MIRA profile (art/characters/mira_0/) and the alternate test profile (tests/fixtures/rigs/) from tests/fixtures/rigs/rig_fixtures.gd. Run when the schema or a fixture changes:
##   godot_console --headless --path . --script res://tools/rig_profile/generate_profiles.gd
const Fix := preload("res://tests/fixtures/rigs/rig_fixtures.gd")
func _initialize() -> void:
	var failures := 0
	for entry in [["res://art/characters/mira_0/mira_0_rig_profile.tres", Fix.mira_profile()], ["res://tests/fixtures/rigs/alternate_rig_profile.tres", Fix.alternate_profile()]]:
		var path: String = entry[0]
		var error := ResourceSaver.save(entry[1], path)
		print("saved ", path, " -> ", "OK" if error == OK else "error %d" % error)
		failures += 0 if error == OK else 1
	quit(1 if failures else 0)
