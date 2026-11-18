extends Control
## Exploration dialogue host; uses the same persistent narrative model as trade.
const Dialogue = preload("res://scripts/commerce/customer_dialogue.gd")
var state: RefCounted
var street: Control
var encounter: Dictionary
var story: Dictionary
var title: Label
var text: RichTextLabel
var choices: VBoxContainer

func setup(owner_state: RefCounted, surface: Control, npc_id: String) -> void:
	state = owner_state
	street = surface
	encounter = Dialogue.encounter(state,npc_id)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0,0,0,0.75)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var card := PanelContainer.new()
	card.position = Vector2(270,170)
	card.size = Vector2(650,440)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	card.add_child(column)
	title = Label.new()
	column.add_child(title)
	text = RichTextLabel.new()
	text.custom_minimum_size = Vector2(610,200)
	column.add_child(text)
	choices = VBoxContainer.new()
	column.add_child(choices)
	var close := Button.new()
	close.text = "离开对话"
	close.pressed.connect(finish_interaction)
	column.add_child(close)
	street.interacting_npc = true
	next_story()

func finish_interaction() -> void:
	if is_instance_valid(street): street.interacting_npc = false
	queue_free()

func next_story() -> void:
	story = Dialogue.pending(state,encounter)
	if story.is_empty():
		title.text = Dialogue.customer_by_id(Dialogue.Customers.definition(int(encounter.visitor)).id).name
		text.text = "对方暂时没有新的消息。"
		for child in choices.get_children(): child.queue_free()
		return
	show_node(state.dialogue_progress.get(encounter.id,{}).get("node",story.start))

func show_node(id: String) -> void:
	var node := Dialogue.enter(state,encounter,story,id)
	var npc: Dictionary = Dialogue.Customers.definition(int(encounter.visitor))
	title.text = node.get("speaker",npc.name)
	text.text = node.text
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	var index := 0
	for choice in Dialogue.Meeting.new(story).replies(id):
		if Dialogue.matches(state,choice.get("conditions",{}),npc.id):
			var button := Button.new()
			button.text = choice.text
			button.pressed.connect(select_choice.bind(choice,id,index))
			choices.add_child(button)
		index += 1
	if choices.get_child_count() == 0:
		var button := Button.new()
		button.text = "继续" if node.get("next","") != "" else "结束对话"
		button.pressed.connect(advance.bind(node.get("next","")))
		choices.add_child(button)

func select_choice(choice: Dictionary, node: String, index: int) -> void:
	Dialogue.apply_effects(state,encounter,story,node+"/choice/"+str(index),choice.get("effects",{}))
	advance(choice.get("next",""))

func advance(next: String) -> void:
	if next != "": show_node(next)
	else:
		Dialogue.finish(state,encounter,story)
		next_story()
