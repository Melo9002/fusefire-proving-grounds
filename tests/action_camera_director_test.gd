extends SceneTree

const DirectorData := preload("res://presentation/camera/action_camera_director.gd")

var failures := 0

func _initialize() -> void:
	var director = DirectorData.new()
	director.frequency = director.Frequency.FINAL_ACTIONS
	check(not director.should_present(&"move", 1), "Final Actions leaves non-final movement tactical")
	check(director.should_present(&"attack", 0), "Final Actions presents an AP-exhausting attack")
	check(director.should_present(&"attack", 1, true), "Important combat overrides Final Actions")
	director.frequency = director.Frequency.COMBAT_ONLY
	check(director.should_present(&"attack", 1), "Combat Only presents attacks")
	check(not director.should_present(&"move", 0), "Combat Only leaves movement tactical")
	director.frequency = director.Frequency.ALL_ACTIONS
	check(director.should_present(&"move", 1), "All Actions presents movement")
	director.frequency = director.Frequency.OFF
	check(not director.should_present(&"attack", 0, true), "Off remains absolute for important actions")
	director.free()
	print("Action camera director: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
