class_name MetroFurniture
extends "res://scripts/items/highlightable_item.gd"
signal selection_requested(kind: String)
var definition: Resource
var home: Control
var build_controller: Node
var is_selected := false
var render_plane := 0 # 0: whole, 1: physical, 2: wall
var plane_mask_image: Image
var depth_partner: WeakRef
var direct_hover := false

func configure(data: Resource, owner_home: Control, surface: Control) -> void:
	rotation = 0.0 # Storage rotation never becomes a furniture rotation.
	definition = data
	pivot_offset=size/2
	rotation_degrees=float(data.texture_binding.get("rotation",0))
	caption.rotation_degrees=-rotation_degrees
	home = owner_home
	var building: bool = build_controller != null and build_controller.active
	is_selected = building and build_controller.selected_id == data.id
	set_item(data.texture, data.display_name + " · 长按0.5秒移动" if building else data.function_text, surface)
	apply_depth_mask()
	set_highlighted(false)
	activated.connect(use)
	if data.id.get_slice("#",0) == "screen":
		if not building:
			caption.text = "%s · %s · %s\n%s" % [home.state.station,home.state.date_text(),home.state.weather(),home.state.news()]
			caption.position = Vector2(size.x + 12,0)
			caption.size = Vector2(380,110)
			var card := StyleBoxFlat.new()
			card.bg_color = Color("211f31f0")
			card.content_margin_left = 10
			card.content_margin_right = 10
			card.content_margin_top = 8
			card.content_margin_bottom = 8
			caption.add_theme_stylebox_override("normal",card)
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			caption.add_theme_font_size_override("font_size",14)
			caption.z_index = 30
			mouse_default_cursor_shape = Control.CURSOR_ARROW
		var info := Label.new()
		info.name = "StationInfo"
		info.text = "%s\n%s\n%s" % [home.state.station, home.state.date_text(), home.state.weather()]
		info.position = Vector2(4, 4)
		info.size = size - Vector2(8, 8)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", Color("322d3d"))
		add_child(info)

func use() -> void:
	if definition.action == "none" and (build_controller == null or not build_controller.active):
		return
	if build_controller != null and build_controller.active:
		selection_requested.emit(definition.id)
	elif home.screen == "cabin":
		definition.perform(home)

func set_highlighted(value: bool) -> void:
	direct_hover=value
	refresh_depth_highlight()
	var peer: Control=depth_partner.get_ref() if depth_partner!=null else null
	if is_instance_valid(peer):peer.refresh_depth_highlight()

func refresh_depth_highlight() -> void:
	var peer: Control=depth_partner.get_ref() if depth_partner!=null else null
	hovered=direct_hover or (is_instance_valid(peer) and peer.direct_hover)
	if visual.material!=null:visual.material.set_shader_parameter("highlighted",hovered or is_selected)
	# Both depth pieces share one silhouette, but only the actual hit shows a label.
	caption.visible=direct_hover and show_function_label

func _gui_input(event: InputEvent) -> void:
	if build_controller != null and build_controller.active and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			build_controller.press_furniture(definition.id, event.global_position)
		accept_event()
		return
	if definition.action == "none":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and is_instance_valid(drag_surface):
			drag_surface.start_drag(event.global_position, Callable())
			accept_event()
		return
	super._gui_input(event)


var animation_frame := -1
func _process(_delta: float) -> void:
	if definition==null or int(definition.animation.get("frames",1))<=1:return
	var elapsed:=Time.get_ticks_msec()/1000.0
	var frame: int=definition.frame_index(elapsed)
	if frame==animation_frame:return
	animation_frame=frame
	var text:=caption.text
	set_item(definition.frame_at(elapsed),text,drag_surface)
	apply_depth_mask()
	refresh_depth_highlight()

func apply_depth_mask() -> void:
	if render_plane==0:return
	var mask: Texture2D=definition.physical_plane_mask(padded_image.get_size()-Vector2i(4,4))
	plane_mask_image=mask.get_image()
	visual.material.set_shader_parameter("furniture_plane",render_plane)
	visual.material.set_shader_parameter("furniture_physical_mask",mask)

func _has_point(point: Vector2) -> bool:
	if not super._has_point(point):return false
	if render_plane==0 or plane_mask_image==null:return true
	var pixel:=Vector2i(point/size*Vector2(plane_mask_image.get_size()))
	var physical:=plane_mask_image.get_pixelv(pixel).r>.5
	return physical if render_plane==1 else not physical
