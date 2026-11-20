extends SceneTree
## Regenerates profiles/*.tres from fixtures.gd. Run when the schema or a fixture changes:
##   godot_console --headless --path . --script res://research/rig_profile_prototype/generate_profiles.gd
const Fix := preload("res://research/rig_profile_prototype/fixtures.gd")
func _initialize() -> void:
	var failures := 0
	for entry in [["mira_rig_profile", Fix.mira_profile()], ["alternate_rig_profile", Fix.alternate_profile()]]:
		var path := "res://research/rig_profile_prototype/profiles/%s.tres" % entry[0]
		var error := ResourceSaver.save(entry[1], path)
		print("saved ", path, " -> ", "OK" if error == OK else "error %d" % error)
		failures += 0 if error == OK else 1
	quit(1 if failures else 0)
