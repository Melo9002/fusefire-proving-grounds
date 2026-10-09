class_name ActionCost
extends RefCounted

var ap: int
var spend_all_remaining_ap: bool
var ends_activation: bool
var requires_active_actor: bool

func _init(p_ap := 0, p_spend_all := false, p_ends_activation := false, p_requires_active := true) -> void:
	ap = p_ap
	spend_all_remaining_ap = p_spend_all
	ends_activation = p_ends_activation
	requires_active_actor = p_requires_active

func to_dictionary() -> Dictionary:
	return {
		"ap": ap,
		"spend_all_remaining_ap": spend_all_remaining_ap,
		"ends_activation": ends_activation,
		"requires_active_actor": requires_active_actor,
	}

