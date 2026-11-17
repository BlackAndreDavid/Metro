extends Control

const TEXT := Color("f2eadd")
const MUTED := Color("b9b3cb")
const AMBER := Color("f0cc91")
const MINT := Color("a6dccc")
const DARK := Color("211f31")
const BORDER := Color("514b67")

func style(fill: Color, edge: Color, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	return box

func put(parent: Control, node: Control, bounds: Rect2) -> void:
	node.position = bounds.position
	node.size = bounds.size
	parent.add_child(node)

func plate(parent: Control, bounds: Rect2, color: Color, edge: Color = Color.TRANSPARENT) -> Panel:
	var block := Panel.new()
	block.mouse_filter = MOUSE_FILTER_IGNORE
	block.add_theme_stylebox_override("panel", style(color, edge))
	put(parent, block, bounds)
	return block

func label(parent: Control, message: String, bounds: Rect2, pixels: int, color: Color = TEXT, alignment: int = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = false) -> Label:
	var node := Label.new()
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.text = message
	node.horizontal_alignment = alignment
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", pixels)
	node.add_theme_color_override("font_color", color)
	put(parent, node, bounds)
	return node

func wrapped(parent: Control, message: String, bounds: Rect2, pixels: int, color: Color = TEXT) -> Label:
	var node := label(parent, message, bounds, pixels, color, HORIZONTAL_ALIGNMENT_LEFT, true)
	node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return node

func button_style(node: Button, prominent: bool = false) -> void:
	var fill := Color("463759") if prominent else Color("302b43")
	node.add_theme_stylebox_override("normal", style(fill, AMBER if prominent else BORDER))
	node.add_theme_stylebox_override("hover", style(Color("594861"), AMBER))
	node.add_theme_stylebox_override("pressed", style(Color("6a5270"), AMBER))
	node.add_theme_stylebox_override("disabled", style(Color("29263a"), Color("3b364b")))
	node.add_theme_stylebox_override("focus", style(Color.TRANSPARENT, AMBER, 2))
	node.add_theme_color_override("font_color", AMBER if prominent else TEXT)
	node.add_theme_color_override("font_hover_color", TEXT)
	node.add_theme_color_override("font_disabled_color", Color("8f889f"))
	node.add_theme_font_size_override("font_size", 16)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func action(parent: Control, caption: String, bounds: Rect2, callback: Callable, prominent: bool = false) -> Button:
	var node := Button.new()
	node.text = caption
	button_style(node, prominent)
	if bounds.size.y < 32:
		node.add_theme_font_size_override("font_size", 14)
	node.pressed.connect(callback)
	put(parent, node, bounds)
	return node

func invisible_action(parent: Control, area: Rect2, callback: Callable) -> Button:
	var hit := action(parent, "", area, callback)
	hit.focus_mode = Control.FOCUS_NONE
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", style(Color(AMBER, 0.1), Color(AMBER, 0.85), 2))
	hit.add_theme_stylebox_override("pressed", style(Color(AMBER, 0.18), AMBER, 2))
	return hit

func overlay(parent: Control, color: Color) -> void:
	var blocker := ColorRect.new()
	blocker.color = color
	blocker.mouse_filter = MOUSE_FILTER_STOP
	put(parent, blocker, Rect2(0, 0, 1280, 720))

