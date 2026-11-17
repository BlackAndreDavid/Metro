extends Control
## One reversible depth animation for all independently stored customer sprites.
signal activated
const Catalog = preload("res://scripts/commerce/customer_catalog.gd")
@export var approach_seconds := 0.9
@export var stay_seconds := 5.0
@export var depart_seconds := 0.8
@export var gap_seconds := 1.2
var customer_index := 0
var elapsed := 0.0
var phase := "approach"
var depth := 0.0
var drag_surface: Control
var textures: Array[Texture2D] = []
@onready var portrait: TextureRect = $Customer

func _ready() -> void:
	for data in Catalog.ENTRIES:
		textures.append(load(data.texture))
	mouse_entered.connect(func(): $Hint.show())
	mouse_exited.connect(func(): $Hint.hide())
	set_customer(customer_index)
	apply_depth(0)

func set_customer(index: int) -> void:
	customer_index = posmod(index,Catalog.ENTRIES.size())
	portrait.texture = textures[customer_index]
	$Name.text = Catalog.ENTRIES[customer_index].name

func apply_depth(value: float) -> void:
	depth = clampf(value,0,1)
	portrait.scale = Vector2.ONE * lerpf(0.42,1.0,depth)
	var light := lerpf(0.3,1.0,depth)
	portrait.modulate = Color(light,light,light,lerpf(0.0,1.0,depth))

func advance(delta: float) -> void:
	# Consume overflow so a delayed frame does not stall a visit or skip a phase.
	var durations := {"approach":approach_seconds,"stay":stay_seconds,"depart":depart_seconds,"gap":gap_seconds}
	elapsed += maxf(0,delta)
	while elapsed >= maxf(0.01,durations[phase]):
		elapsed -= maxf(0.01,durations[phase])
		match phase:
			"approach": phase = "stay"
			"stay": phase = "depart"
			"depart": phase = "gap"
			"gap":
				phase = "approach"
				set_customer(customer_index+1)
	match phase:
		"approach": apply_depth(elapsed/maxf(0.01,approach_seconds))
		"stay": apply_depth(1)
		"depart": apply_depth(1-elapsed/maxf(0.01,depart_seconds))
		"gap": apply_depth(0)

func _process(delta: float) -> void: advance(delta)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_instance_valid(drag_surface):
			drag_surface.start_drag(event.global_position,func(): activated.emit())
		else: activated.emit()
		accept_event()
