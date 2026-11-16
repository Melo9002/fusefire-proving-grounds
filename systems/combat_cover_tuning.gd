class_name CombatCoverTuning
extends Resource
## Provisional percentage-point penalties, shared by every combat consumer.
@export_range(0, 100, 1) var low_cover_penalty := 20
@export_range(0, 100, 1) var full_cover_penalty := 40

func is_valid() -> bool:
	return low_cover_penalty >= 0 and full_cover_penalty >= low_cover_penalty and full_cover_penalty <= 100

func signature() -> String:
	return "cover-1:%d:%d" % [low_cover_penalty, full_cover_penalty]
