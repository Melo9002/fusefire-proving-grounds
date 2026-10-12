extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_ordinary_expenditure_and_penalty_ratchet()
	_test_positive_modifier_waits_for_refresh()
	_test_zero_capacity_and_overlapping_penalties()
	_test_capacity_below_expenditure()
	_test_source_identity_and_canonical_order()
	_test_explicit_setup_contract()
	print("AP capacity and modifiers: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _stats(base: int) -> UnitStats:
	var stats := UnitStats.new()
	root.add_child(stats)
	stats.configure_base_ap(base, true)
	return stats

func _test_ordinary_expenditure_and_penalty_ratchet() -> void:
	var stats := _stats(3)
	check(stats.base_ap == 3 and stats.effective_max_ap == 3 and stats.max_ap == 3, "Base and effective maximum begin at three")
	check(stats.activation_capacity_ap == 3 and stats.spent_ap == 0 and stats.current_ap == 3, "Refresh establishes three available AP")
	check(stats.consume_ap(1), "One AP can be spent")
	check(stats.activation_capacity_ap == 3 and stats.spent_ap == 1 and stats.current_ap == 2, "Ordinary spending preserves capacity and records expenditure")
	check(stats.set_ap_modifier(&"condition:system_overload", -1), "A stable negative modifier source is accepted")
	check(stats.base_ap == 3 and stats.effective_max_ap == 2 and stats.activation_capacity_ap == 2 and stats.spent_ap == 1 and stats.current_ap == 1, "Mid-activation penalty ratchets capacity while preserving expenditure")
	check(stats.remove_ap_modifier(&"condition:system_overload"), "Known modifier source can be removed")
	check(stats.effective_max_ap == 3 and stats.activation_capacity_ap == 2 and stats.spent_ap == 1 and stats.current_ap == 1, "Penalty removal grants no AP in the same activation")
	stats.refresh_activation_ap()
	check(stats.activation_capacity_ap == 3 and stats.spent_ap == 0 and stats.current_ap == 3, "Next refresh adopts restored effective maximum")
	stats.queue_free()

func _test_positive_modifier_waits_for_refresh() -> void:
	var stats := _stats(3)
	stats.consume_ap(1)
	check(stats.set_ap_modifier(&"equipment:heavy_processor", 1), "Positive modifier is accepted")
	check(stats.effective_max_ap == 4 and stats.activation_capacity_ap == 3 and stats.current_ap == 2, "Positive modifier does not grant AP mid-activation")
	stats.refresh_activation_ap()
	check(stats.activation_capacity_ap == 4 and stats.spent_ap == 0 and stats.current_ap == 4, "Positive modifier applies at the next refresh")
	stats.queue_free()

func _test_zero_capacity_and_overlapping_penalties() -> void:
	var stats := _stats(3)
	stats.set_ap_modifier(&"condition:minor", -1)
	stats.set_ap_modifier(&"condition:major", -2)
	check(stats.effective_max_ap == 0 and stats.activation_capacity_ap == 0 and stats.current_ap == 0, "Independent penalties can reduce effective maximum and capacity to zero")
	check(stats.remove_ap_modifier(&"condition:major"), "One overlapping modifier can be removed independently")
	check(stats.effective_max_ap == 2 and stats.activation_capacity_ap == 0 and stats.current_ap == 0, "Removing one penalty does not raise capacity during the activation")
	stats.refresh_activation_ap()
	check(stats.activation_capacity_ap == 2 and stats.current_ap == 2, "Refresh adopts the remaining modifier")
	stats.queue_free()

func _test_capacity_below_expenditure() -> void:
	var stats := _stats(4)
	check(stats.consume_ap(3), "Three AP can be spent from a four-AP capacity")
	stats.set_ap_modifier(&"condition:severe", -3)
	check(stats.effective_max_ap == 1 and stats.activation_capacity_ap == 1 and stats.spent_ap == 3 and stats.current_ap == 0, "Capacity can fall below preserved expenditure")
	check(not stats.consume_ap(1) and stats.spent_ap == 3, "Overspending is rejected without altering expenditure")
	stats.remove_ap_modifier(&"condition:severe")
	check(stats.effective_max_ap == 4 and stats.activation_capacity_ap == 1 and stats.current_ap == 0, "Penalty removal does not recover availability after capacity fell below expenditure")
	stats.refresh_activation_ap()
	check(stats.activation_capacity_ap == 4 and stats.spent_ap == 0 and stats.current_ap == 4, "Refresh clears expenditure and restores capacity")
	stats.queue_free()

func _test_source_identity_and_canonical_order() -> void:
	var first := _stats(3)
	var second := _stats(3)
	check(not first.set_ap_modifier(&"", 1) and not first.set_ap_modifier(&"   ", 1), "Empty modifier source is rejected")
	check(first.set_ap_modifier(&"equipment:b", 1), "First independent source is accepted")
	check(first.set_ap_modifier(&"condition:a", -2), "Second independent source is accepted")
	check(first.set_ap_modifier(&"equipment:b", 2), "Duplicate source deterministically replaces its delta")
	second.set_ap_modifier(&"condition:a", -2)
	second.set_ap_modifier(&"equipment:b", 2)
	check(first.effective_max_ap == 3 and first.get_ap_modifier(&"equipment:b") == 2, "Replacing a source never stacks a duplicate entry")
	check(first.get_ap_modifier_snapshot() == second.get_ap_modifier_snapshot(), "Canonical modifier snapshot is independent of insertion order")
	check(first.get_ap_snapshot().current_ap == first.current_ap and first.get_ap_snapshot().effective_max_ap == first.effective_max_ap, "Observers can obtain one consistent AP snapshot")
	check(not first.remove_ap_modifier(&"missing") and not first.remove_ap_modifier(&""), "Unknown and empty-source removal are harmless")
	check(first.set_ap_modifier(&"equipment:b", 0) and not first.has_ap_modifier(&"equipment:b"), "Zero delta removes an existing source")
	check(not first.set_ap_modifier(&"equipment:b", 0), "Zero delta for an absent source is a harmless no-op")
	first.queue_free()
	second.queue_free()

func _test_explicit_setup_contract() -> void:
	var stats := _stats(3)
	var movement_budget := stats.speed
	stats.set_available_ap_for_setup(1)
	check(stats.activation_capacity_ap == 3 and stats.spent_ap == 2 and stats.current_ap == 1, "Explicit setup establishes availability through expenditure accounting")
	stats.set_available_ap_for_setup(3)
	check(stats.spent_ap == 0 and stats.current_ap == 3, "Explicit setup resets fixture availability without a second AP authority")
	stats.configure_base_ap(4)
	check(stats.base_ap == 4 and stats.effective_max_ap == 4 and stats.activation_capacity_ap == 3 and stats.current_ap == 3, "Base AP configuration does not grant mid-activation capacity")
	check(stats.speed == movement_budget, "AP capacity changes do not alter movement range")
	stats.spend_all_remaining_ap()
	check(stats.spent_ap == 3 and stats.current_ap == 0, "Spend-all records all remaining AP as expenditure")
	stats.queue_free()
