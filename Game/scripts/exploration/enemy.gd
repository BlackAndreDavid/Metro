class_name ExplorationEnemy
extends RefCounted
## Enemies own presentation/collision, locomotion, perception and attacks independently of Home.
var definition: Dictionary
var id: String
var row: int
var x: float
var facing := -1.0
var awareness := 0.0
var alerted := false
var action := "patrol_move"
var timer := 1.5
var sense_clock := 0.0
var animation_clock := 0.0
var attack_hit := false
var pounce_direction := 1.0
var rng := RandomNumberGenerator.new()

func _init(spec: Dictionary = {}, placement: Dictionary = {}) -> void:
	definition = spec.duplicate(true)
	id = placement.get("id","enemy")
	row = int(placement.get("row",0))
	x = float(placement.get("x",200))
	facing = float(placement.get("facing",-1))
	rng.seed = hash(id)
	timer = rng.randf_range(float(movement().get("patrol_min",1)),float(movement().get("patrol_max",2)))

func sprite() -> Dictionary: return definition.get("sprite",{})
func movement() -> Dictionary: return definition.get("movement",{})
func senses() -> Dictionary: return definition.get("alert",{})
func attack() -> Dictionary: return definition.get("attack",{})
func body_rect(ground: float) -> Rect2:
	var size := Vector2(float(sprite().get("collision_width",128)),float(sprite().get("collision_height",32)))
	return Rect2(Vector2(x-size.x/2,ground-size.y-attack_jump()),size)

func attack_jump() -> float:
	if action != "pounce": return 0.0
	var progress := clampf(1.0-timer/maxf(0.01,float(attack().get("duration",0.28))),0,1)
	return sin(progress*PI)*float(attack().get("jump_height",24))

func perceive(player: Dictionary) -> Dictionary:
	if int(player.get("row",-1)) != row: return {"vision":false,"sound":false}
	var delta := Vector2(float(player.x)-x,float(sprite().get("collision_height",32))/2-32+float(player.get("vertical_offset",0)))
	var distance := delta.length()
	var alert := senses()
	var circle: float = alert.get("circle_radius",128)
	var cone: float = alert.get("cone_length",256)
	var forward := Vector2(facing,0)
	var dot: float = forward.dot(delta.normalized()) if distance > 0 else 1.0
	var visible: bool = not player.get("indoors",false) and (distance <= circle or (distance <= cone and dot >= cos(deg_to_rad(float(alert.get("cone_angle",70))/2))))
	return {"vision":visible,"sound":distance <= float(player.get("noise_radius",0)) and player.get("moving",false)}

func step(delta: float, player: Dictionary, limits: Vector2, ground: float) -> Dictionary:
	var result := {}
	animation_clock += delta
	sense_clock += delta
	var detection := perceive(player)
	while sense_clock >= 0.1:
		sense_clock -= 0.1
		if detection.vision: awareness += float(senses().get("visual_gain",10))
		elif detection.sound: awareness += float(senses().get("sound_gain",5))
		else: awareness -= float(senses().get("decay_per_second",25))*0.1
		awareness = clampf(awareness,0,100)
	if awareness >= 100: alerted = true
	elif awareness <= 0: alerted = false
	var same_street: bool = int(player.get("row",-1)) == row
	var exposed: bool = same_street and not player.get("indoors",false)
	var half: float = float(sprite().get("collision_width",128))/2
	var minimum := limits.x+half
	var maximum := limits.y-half
	timer -= delta
	if action == "recovery":
		if timer <= 0:
			action = "chase_move" if alerted else "patrol_move"
			timer = float(movement().get("chase_seconds",3)) if alerted else rng.randf_range(float(movement().get("patrol_min",1)),float(movement().get("patrol_max",2)))
		return result
	if action == "pounce":
		x = clampf(x+pounce_direction*float(attack().get("speed",480))*delta,minimum,maximum)
		var player_rect := Rect2(Vector2(float(player.get("x",0))-16,ground-64),Vector2(32,64))
		if exposed and not attack_hit and body_rect(ground).intersects(player_rect):
			attack_hit = true
			result = {"time_penalty":float(attack().get("time_penalty",5)),"slow_seconds":float(attack().get("slow_seconds",2)),"slow_multiplier":float(attack().get("slow_multiplier",0.8))}
		if timer <= 0:
			action = "recovery"
			timer = float(attack().get("recovery",2))
		return result
	if alerted and exposed and absf(float(player.x)-x) <= float(attack().get("range",144)):
		pounce_direction = signf(float(player.x)-x)
		if is_zero_approx(pounce_direction): pounce_direction = facing
		facing = pounce_direction
		action = "pounce"
		timer = float(attack().get("duration",0.28))
		attack_hit = false
		return result
	if alerted and action.begins_with("patrol"):
		action = "chase_move"
		timer = float(movement().get("chase_seconds",3))
	elif not alerted and action.begins_with("chase"):
		action = "patrol_move"
		timer = rng.randf_range(float(movement().get("patrol_min",1)),float(movement().get("patrol_max",2)))
	if timer <= 0:
		if action.ends_with("move"):
			action = "chase_wait" if alerted else "patrol_wait"
			timer = float(movement().get("wait_seconds",1))
		else:
			action = "chase_move" if alerted else "patrol_move"
			timer = float(movement().get("chase_seconds",3)) if alerted else rng.randf_range(float(movement().get("patrol_min",1)),float(movement().get("patrol_max",2)))
	if action.ends_with("move"):
		if alerted and same_street and not is_equal_approx(float(player.x),x): facing = signf(float(player.x)-x)
		x += facing*float(movement().get("chase_speed",220) if alerted else movement().get("patrol_speed",96))*delta
		if x <= minimum:
			x = minimum
			facing = 1
		elif x >= maximum:
			x = maximum
			facing = -1
	return result
