extends Control
## A visitor enters from the left, waits indefinitely for their order, then exits right.
signal arrived
signal departed
const Catalog = preload("res://scripts/commerce/customer_catalog.gd")
@export var approach_seconds := 0.85
@export var depart_seconds := 0.75
var customer_index := 0
var elapsed := 0.0
var phase := "empty"
var progress := 0.0
var departure_start := 0.0
var textures: Array[Texture2D] = []
@onready var portrait: TextureRect = $Customer

func _ready() -> void:
	Catalog.reload()
	for data in Catalog.ENTRIES:
		var texture := AtlasTexture.new()
		texture.atlas = Catalog.load_texture(data.texture)
		# Independent source sprites stay full-body; only the upper body is shown here.
		texture.region = Rect2(0,0,48,44)
		textures.append(texture)
	hide_customer()

func set_customer(index: int) -> void:
	Catalog.reload()
	textures.clear()
	for data in Catalog.ENTRIES:
		var texture := AtlasTexture.new()
		texture.atlas = Catalog.load_texture(data.texture)
		texture.region = Rect2(0,0,48,44)
		textures.append(texture)
	customer_index = posmod(index,Catalog.ENTRIES.size())
	portrait.texture = textures[customer_index]
	$Name.text = Catalog.ENTRIES[customer_index].name

func show_customer(index: int, completed: bool = false) -> void:
	set_customer(index)
	departure_start = (size.x-portrait.size.x)/2
	phase = "depart" if completed else "approach"
	elapsed = 0
	portrait.show()
	$Name.show()
	apply_progress(0)

func hide_customer() -> void:
	phase = "empty"
	portrait.hide()
	$Name.hide()

func finish_order() -> void:
	if phase == "empty" or phase == "depart": return
	departure_start = portrait.position.x
	phase = "depart"
	elapsed = 0
	apply_progress(0)

func apply_progress(value: float) -> void:
	progress = clampf(value,0,1)
	var center := (size.x-portrait.size.x)/2
	portrait.position.x = lerpf(-portrait.size.x,center,progress) if phase == "approach" else lerpf(departure_start,size.x,progress)
	var visibility := progress if phase == "approach" else 1-progress
	var light := lerpf(0.5,1.0,visibility)
	portrait.modulate = Color(light,light,light,lerpf(0.15,1.0,visibility))

func advance(delta: float) -> void:
	if phase not in ["approach","depart"]: return
	var duration := maxf(0.01,approach_seconds if phase == "approach" else depart_seconds)
	elapsed = minf(duration,elapsed+maxf(0,delta))
	apply_progress(elapsed/duration)
	if elapsed < duration: return
	if phase == "approach":
		phase = "stay"
		portrait.position.x = (size.x-portrait.size.x)/2
		portrait.modulate = Color.WHITE
		arrived.emit()
	else:
		hide_customer()
		departed.emit()

func _process(delta: float) -> void: advance(delta)
