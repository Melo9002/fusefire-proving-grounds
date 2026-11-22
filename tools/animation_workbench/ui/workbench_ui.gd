class_name WorkbenchUI
extends RefCounted
## Small widget helpers shared by the workbench's panel and tabs, so each tab stays a list of what it shows rather than a list of how to build a Label. No state, no game types.

const TEXT := Color(0.88, 0.93, 1.0)
const DIM := Color(0.62, 0.70, 0.80)
const ACCENT := Color(0.5, 0.92, 1.0)
const GOOD := Color(0.45, 0.95, 0.55)
const WARN := Color(1.0, 0.8, 0.3)
const BAD := Color(1.0, 0.4, 0.35)

static func label(text: String, size := 13, colour := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", maxi(size, 14))
	node.add_theme_color_override("font_color", colour)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

## A fixed-width-font label for tables and live readouts (columns line up).
static func mono(text := "", size := 12) -> Label:
	var node := label(text, maxi(size, 14))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	node.add_theme_font_override("font", font)
	node.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY   # a long line wraps instead of widening the panel
	return node

static func button(text: String, callback: Callable, tooltip := "") -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.tooltip_text = tooltip
	node.pressed.connect(callback)
	return node

static func row(buttons: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	for entry in buttons:
		var node := button(entry[0], entry[1], entry[2] if entry.size() > 2 else "")
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(node)
	return box

static func check(text: String, on: bool, callback: Callable, tooltip := "") -> CheckBox:
	var node := CheckBox.new()
	node.text = text
	node.button_pressed = on
	node.focus_mode = Control.FOCUS_NONE
	node.tooltip_text = tooltip
	node.add_theme_font_size_override("font_size", 14)
	node.toggled.connect(callback)
	return node

## A collapsible section added to `parent`; returns the box to put its content in.
static func section(parent: Control, title: String, folded := false) -> VBoxContainer:
	var holder := FoldableContainer.new()
	holder.title = title
	holder.folded = folded
	holder.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # a long title never widens the panel
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	holder.add_child(box)
	parent.add_child(holder)
	return box

## A tab body: a vertical scroll area holding a VBox. Returns [scroll, box].
static func scroll_body() -> Array:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)
	return [scroll, box]

static func status_colour(status: String) -> Color:
	match status:
		"SUPPORTED", "ok":
			return GOOD
		"FALLBACK", "NOT_IMPLEMENTED":
			return WARN
	return BAD
