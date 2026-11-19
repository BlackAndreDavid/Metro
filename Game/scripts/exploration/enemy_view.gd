extends Control
var enemy: RefCounted
var texture: Texture2D
var font: Font
func _draw() -> void:
	if enemy == null or texture == null: return
	var sprite: Dictionary = enemy.sprite()
	var count := maxi(1,int(sprite.get("frames",1)))
	var frame := int(enemy.animation_clock*float(sprite.get("fps",8)))%count if enemy.action.ends_with("move") or enemy.action == "pounce" else 0
	var width := float(sprite.get("width",128))
	var height := float(sprite.get("height",32))
	var target := Rect2(-width/2,-height-enemy.attack_jump(),width,height)
	if (enemy.facing > 0) == bool(sprite.get("faces_left",true)):
		target.position.x += width;target.size.x = -width
	draw_texture_rect_region(texture,target,Rect2(frame*texture.get_width()/float(count),0,texture.get_width()/float(count),texture.get_height()))
	if enemy.awareness > 0:
		var top := -height-12
		draw_rect(Rect2(-30,top,60,5),Color("292738"))
		draw_rect(Rect2(-30,top,60*enemy.awareness/100,5),Color("e87b75") if enemy.alerted else Color("efc488"))
		if enemy.alerted:draw_string(font,Vector2(-4,top-3),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("ff9690"))
