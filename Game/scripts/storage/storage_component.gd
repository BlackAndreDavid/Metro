class_name MetroStorage
extends Resource
## Shared capacity and cargo algorithms for item and furniture storage.
## Owners retain their save arrays; this component never changes cargo on failure.
@export var size := Vector2i.ZERO

static func from_data(data: Variant) -> Resource:
	var result = load("res://scripts/storage/storage_component.gd").new()
	if data is Dictionary:result.size=Vector2i(int(data.get("width",0)),int(data.get("height",0)))
	return result

static func cells(definitions: Dictionary,entry: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i]=[]
	for offset in definitions[entry.kind].cell_offsets(entry.get("rotated",false),entry.get("mirrored",false)):
		result.append(Vector2i(entry.x,entry.y)+offset)
	return result

static func fits(definitions: Dictionary,cargo: Array,bounds: Vector2i,box: Rect2i,ignore_id: int=-1,mask: Array[Vector2i]=[]) -> bool:
	var candidate: Array[Vector2i]=mask.duplicate()
	if candidate.is_empty():
		for y in range(box.position.y,box.end.y):
			for x in range(box.position.x,box.end.x):candidate.append(Vector2i(x,y))
	for cell in candidate:
		if not Rect2i(Vector2i.ZERO,bounds).has_point(cell):return false
	for entry in cargo:
		if entry.get("id",-2)==ignore_id:continue
		for cell in cells(definitions,entry):
			if cell in candidate:return false
	return true

static func first_free(definitions: Dictionary,cargo: Array,bounds: Vector2i,kind: String,mirrored: bool=false,preferred_rotation: bool=false) -> Dictionary:
	for rotated in [preferred_rotation,not preferred_rotation]:
		var offsets: Array=definitions[kind].cell_offsets(rotated,mirrored)
		var low:=Vector2i(1000,1000);var high:=Vector2i(-1000,-1000)
		for offset in offsets:low=low.min(offset);high=high.max(offset)
		for y in range(-low.y,bounds.y-high.y):
			for x in range(-low.x,bounds.x-high.x):
				var candidate: Array[Vector2i]=[]
				for offset in offsets:candidate.append(Vector2i(x,y)+offset)
				if fits(definitions,cargo,bounds,Rect2i(),-1,candidate):return {"cell":Vector2i(x,y),"rotated":rotated}
	return {}

static func pack(definitions: Dictionary,cargo: Array,bounds: Vector2i,keep_positions: bool=true) -> Dictionary:
	var original: Array[Dictionary]=[];original.assign(cargo.duplicate(true))
	if keep_positions:
		var preserved: Array[Dictionary]=[]
		for item in original:
			if not fits(definitions,preserved,bounds,Rect2i(),-1,cells(definitions,item)):break
			preserved.append(item)
		if preserved.size()==original.size():return {"entries":preserved}
	var total:=0
	for item in original:total+=cells(definitions,item).size()
	if total>bounds.x*bounds.y:return {}
	original.sort_custom(func(a,b):return cells(definitions,a).size()>cells(definitions,b).size())
	var trial: Array[Dictionary]=[]
	for item in original:
		var placement:=first_free(definitions,trial,bounds,item.kind,item.get("mirrored",false),item.rotated)
		if placement.is_empty():return {}
		item.x=placement.cell.x;item.y=placement.cell.y;item.rotated=placement.rotated;trial.append(item)
	return {"entries":trial}
