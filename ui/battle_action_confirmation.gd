class_name BattleActionConfirmation
extends ConfirmationDialog
## One modal per owning battle. Cancellation never submits a gameplay action.
var _pending := Callable()
var _was_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	exclusive = true
	dialog_autowrap = true
	get_cancel_button().custom_minimum_size = Vector2(170, 48)
	get_ok_button().custom_minimum_size = Vector2(170, 48)
	confirmed.connect(func(): _finish(true))
	canceled.connect(func(): _finish(false))
	tree_exiting.connect(func():
		if _pending.is_valid(): get_tree().paused = _was_paused)

func request(heading: String, body: String, commit: Callable, movement := false) -> void:
	if _pending.is_valid(): return
	BattleUXSettings.load_preferences()
	var enabled := BattleUXSettings.confirm_movement if movement else BattleUXSettings.confirm_actions
	if not enabled:
		await commit.call()
		return
	_pending = commit
	_was_paused = get_tree().paused
	title = heading
	dialog_text = body
	ok_button_text = "Confirm move" if movement else "Confirm"
	cancel_button_text = "Cancel / keep planning"
	get_tree().paused = true
	popup_centered(Vector2i(650, 0))
	# AcceptDialog refreshes button minimums when its labels/popup change.
	get_cancel_button().custom_minimum_size = Vector2(170, 48)
	get_ok_button().custom_minimum_size = Vector2(170, 48)
	get_cancel_button().grab_focus()

func _finish(approved: bool) -> void:
	if not _pending.is_valid(): return
	var commit := _pending
	_pending = Callable()
	hide()
	get_tree().paused = _was_paused
	if approved: await commit.call()
