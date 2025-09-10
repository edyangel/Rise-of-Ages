extends Control

var _connected_count: int = 0

func _ready():
	_connected_count = 0
	_connect_buttons_recursive(self)
	print("[menu] connected buttons:", _connected_count)

func _connect_buttons_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var text = String(child.text).to_lower().strip_edges()
			if text == "jugar" and not child.is_connected("pressed", Callable(self, "_on_jugar")):
				var err = child.connect("pressed", Callable(self, "_on_jugar"))
				if err == OK:
					_connected_count += 1
					print("[menu] connected Jugar ->", child.name)
			elif text == "multijugador" and not child.is_connected("pressed", Callable(self, "_on_multijugador")):
				var err2 = child.connect("pressed", Callable(self, "_on_multijugador"))
				if err2 == OK:
					_connected_count += 1
					print("[menu] connected Multijugador ->", child.name)
			elif text == "creacion" and not child.is_connected("pressed", Callable(self, "_on_creacion")):
				var err3 = child.connect("pressed", Callable(self, "_on_creacion"))
				if err3 == OK:
					_connected_count += 1
					print("[menu] connected Creacion ->", child.name)
			elif text == "configuraciones" and not child.is_connected("pressed", Callable(self, "_on_config")):
				var err4 = child.connect("pressed", Callable(self, "_on_config"))
				if err4 == OK:
					_connected_count += 1
					print("[menu] connected Config ->", child.name)
		elif child.get_child_count() > 0:
			_connect_buttons_recursive(child)

func _on_jugar():
	print("[menu] jugar pressed")
	var path := "res://scenes/game.tscn"
	print("[menu] exists? ", ResourceLoader.exists(path))
	var fa := FileAccess.open(path, FileAccess.READ)
	print("[menu] FileAccess open? ", fa != null)
	# Try to load explicitly to surface errors in editor output
	var res := ResourceLoader.load(path)
	if res == null:
		print("[menu] ERROR: no se pudo cargar ", path)
		# Dump contents of scenes folder to help diagnose path issues
		var da := DirAccess.open("res://scenes")
		if da:
			print("[menu] contenidos en res://scenes:")
			da.list_dir_begin()
			var fn = da.get_next()
			while fn != "":
				print("  - ", fn)
				fn = da.get_next()
			da.list_dir_end()
		return
	if res is PackedScene:
		get_tree().change_scene_to_packed(res)
	else:
		print("[menu] ERROR: recurso cargado no es PackedScene: ", typeof(res))

func _on_multijugador():
	get_tree().change_scene_to_file("res://scenes/multiplayer.tscn")

func _on_creacion():
	get_tree().change_scene_to_file("res://scenes/creacion.tscn")

func _on_config():
	get_tree().change_scene_to_file("res://scenes/config.tscn")
