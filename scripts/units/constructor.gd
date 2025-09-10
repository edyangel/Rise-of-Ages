extends CharacterBody2D

var _selected: bool = false

func _ready():
	# use the Label node as a visible marker; ensure it's visible
	if has_node("Label"):
		$Label.visible = true

	# scale down constructor so it visually occupies less of the tile
	if self is Node2D:
		self.scale = Vector2(0.5, 0.5)

func set_selected(value: bool) -> void:
	_selected = value
	if has_node("Label"):
		$Label.modulate = Color(1,1,0.6) if _selected else Color(1,1,1)

func is_selected() -> bool:
	return _selected

func move_to(target: Vector2) -> void:
	# simple immediate move for prototype
	# target is passed in global/world coordinates from the Map
	global_position = target
	print("Constructor moved to: %s" % str(target))

func build():
	print("Construyendo...")
