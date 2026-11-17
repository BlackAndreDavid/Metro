extends Control
## Reusable texture-alpha hit testing, white silhouette and action label.
signal activated
const Outline = preload("res://assets/shaders/item_outline.gdshader")
var drag_surface: Control
var padded_image: Image
var hovered := false
@onready var visual: TextureRect = $Texture
@onready var caption: Label = $Function

func _ready() -> void:
	mouse_entered.connect(set_highlighted.bind(true))
	mouse_exited.connect(set_highlighted.bind(false))
	focus_entered.connect(set_highlighted.bind(true))
	focus_exited.connect(set_highlighted.bind(false))

func set_item(texture: Texture2D, function_text: String, surface: Control = null) -> void:
	drag_surface = surface
	var source := texture.get_image()
	if source.is_compressed():
		source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	padded_image = Image.create(source.get_width() + 4, source.get_height() + 4, false, Image.FORMAT_RGBA8)
	padded_image.fill(Color.TRANSPARENT)
	padded_image.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(2, 2))
	visual.texture = ImageTexture.create_from_image(padded_image)
	var outline := ShaderMaterial.new()
	outline.shader = Outline
	visual.material = outline
	caption.text = function_text
	caption.hide()
	tooltip_text = function_text

func set_highlighted(value: bool) -> void:
	hovered = value
	if visual.material != null:
		visual.material.set_shader_parameter("highlighted", value)
	caption.visible = value

func _has_point(point: Vector2) -> bool:
	if padded_image == null or size.x <= 0 or size.y <= 0:
		return false
	var pixel := Vector2i(point / size * Vector2(padded_image.get_size()))
	return (pixel.x >= 0 and pixel.y >= 0 and pixel.x < padded_image.get_width() and pixel.y < padded_image.get_height()
		and padded_image.get_pixelv(pixel).a > 0.1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		if is_instance_valid(drag_surface):
			drag_surface.start_drag(event.global_position, func(): activated.emit())
		else:
			activated.emit()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		activated.emit()
		accept_event()
