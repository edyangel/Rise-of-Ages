extends Node2D

func _ready():
	print("Game ready")
	# connect Back button if present
	if has_node("CanvasLayer") and $CanvasLayer.has_node("BackButton"):
		$CanvasLayer/BackButton.connect("pressed", Callable(self, "_on_back_pressed"))

	# position camera to a comfortable default if Map + Camera2D exist
	if has_node("Map") and has_node("Camera2D"):
		var map = $Map
		var camera = $Camera2D
		var tile_size = map.get_script().TILE_SIZE
		var map_w = tile_size * map.get_script().MAP_W
		var map_h = tile_size * map.get_script().MAP_H
		var vp = get_viewport_rect().size

		# center camera on map
		camera.position = Vector2(map_w / 2.0, map_h / 2.0)

		# default: show N x M tiles in viewport (e.g. 20x12)
		if map_w > 0 and map_h > 0:
			var tiles_x = 24
			var tiles_y = 14
			var desired_w = tile_size * tiles_x
			var desired_h = tile_size * tiles_y
			var zx = vp.x / desired_w
			var zy = vp.y / desired_h
			var zoom_scale = min(zx, zy)
			# clamp zoom to sane range
			zoom_scale = clamp(zoom_scale, 0.05, 5.0)
			camera.zoom = Vector2(zoom_scale, zoom_scale)

	set_process(true)

	# Initialize HUD values if present
	var hud = _hud()
	if hud:
		if hud.has_method("set_wood"): hud.set_wood(wood)
		if hud.has_method("set_gold"): hud.set_gold(gold)
		if hud.has_method("set_iron"): hud.set_iron(iron)
		if hud.has_method("set_copper"): hud.set_copper(copper)
		if hud.has_method("set_stone"): hud.set_stone(stone)
		if hud.has_method("set_water"): hud.set_water(water)
		if hud.has_method("set_food"): hud.set_food(food)

	# Create a bottom-left 'Deselect' button on CanvasLayer if not present (for mobile)
	if has_node("CanvasLayer"):
		var cl = $CanvasLayer
		if not cl.has_node("DeselectButton"):
			var btn := Button.new()
			btn.name = "DeselectButton"
			btn.text = "X"
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(48, 48)
			btn.theme_type_variation = "FlatButton"
			cl.add_child(btn)
			# Anchor bottom-left
			btn.anchor_left = 0
			btn.anchor_top = 1
			btn.anchor_right = 0
			btn.anchor_bottom = 1
			btn.offset_left = 8
			btn.offset_bottom = -8
			btn.offset_top = -56
			btn.offset_right = 56
			btn.z_index = 2000
			btn.visible = false
			btn.connect("pressed", Callable(self, "_on_deselect_pressed"))

	# Listen to selection_changed from Map to toggle Deselect button
	if has_node("Map"):
		var map = $Map
		if map.has_signal("selection_changed"):
			map.connect("selection_changed", Callable(self, "_on_map_selection_changed"))


func _process(delta):
	if not has_node("Camera2D"):
		return
	var cam = $Camera2D
	var vp = get_viewport_rect().size
	var mpos = get_viewport().get_mouse_position()
	var edge = 24 # pixels
	var speed = 600 * delta
	var move = Vector2.ZERO
	if mpos.x < edge:
		move.x -= speed
	elif mpos.x > vp.x - edge:
		move.x += speed
	if mpos.y < edge:
		move.y -= speed
	elif mpos.y > vp.y - edge:
		move.y += speed
	if move != Vector2.ZERO:
		cam.position += move

func _unhandled_input(event):
	# refit camera on F key
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		if has_node("Map") and has_node("Camera2D"):
			var map = $Map
			var camera = $Camera2D
			var tile_size = map.get_script().TILE_SIZE
			var map_w = tile_size * map.get_script().MAP_W
			var map_h = tile_size * map.get_script().MAP_H
			var vp = get_viewport_rect().size

			# if Shift is held, fit the entire map to the viewport
			if event.shift:
				var full_zx = vp.x / map_w
				var full_zy = vp.y / map_h
				var full_scale = clamp(min(full_zx, full_zy), 0.01, 10.0)
				camera.zoom = Vector2(full_scale, full_scale)
			else:
				# default: show the comfortable tiles window again
				var tiles_x = 24
				var tiles_y = 14
				var desired_w = tile_size * tiles_x
				var desired_h = tile_size * tiles_y
				var zx = vp.x / desired_w
				var zy = vp.y / desired_h
				var zoom_scale = clamp(min(zx, zy), 0.01, 10.0)
				camera.zoom = Vector2(zoom_scale, zoom_scale)

	# Mouse wheel zoom (desktop)
	if event is InputEventMouseButton and has_node("Camera2D"):
		var camera = $Camera2D
		var z = camera.zoom.x
		var step = 0.1
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			z = max(0.1, z * (1.0 - step))
			camera.zoom = Vector2(z, z)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			z = min(10.0, z * (1.0 + step))
			camera.zoom = Vector2(z, z)

	# Pinch zoom (mobile): use magnify gesture if available
	if event is InputEventMagnifyGesture and has_node("Camera2D"):
		var camera = $Camera2D
		var z = camera.zoom.x
		# event.factor > 1: zoom in; < 1: zoom out
		z = clamp(z / max(0.01, event.factor), 0.05, 10.0)
		camera.zoom = Vector2(z, z)

	# One-finger pan on mobile when not drag-selecting
	if event is InputEventScreenDrag and has_node("Camera2D"):
		var map = has_node("Map") ? $Map : null
		if map and map.has_method("is_dragging_selection") and map.is_dragging_selection():
			return
		var cam = $Camera2D
		# event.relative is in screen pixels; translate using zoom
		var z = cam.zoom
		cam.position -= Vector2(event.relative.x * z.x, event.relative.y * z.y)

	# Single tap: forward to map tap action if present (some devices send ScreenTouch without our map handler catching it)
	if event is InputEventScreenTouch and not event.pressed:
		var map = has_node("Map") ? $Map : null
		if map and map.has_method("mobile_tap_action"):
			# convert screen to world like map does
			var vp = get_viewport_rect().size
			var cam = has_node("Camera2D") ? $Camera2D : null
			var wp = event.position
			if cam:
				var z = cam.zoom
				wp = cam.get_screen_center_position() + Vector2((event.position.x - vp.x * 0.5) * z.x, (event.position.y - vp.y * 0.5) * z.y)
			map.mobile_tap_action(wp)


 


# Visuals are drawn by the Map scene

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

var wood: int = 0
var gold: int = 0
var iron: int = 0
var copper: int = 0
var stone: int = 0
var water: int = 0
var food: int = 0

func _hud():
	if has_node("CanvasLayer/HUD"):
		return $CanvasLayer/HUD
	return null

func add_wood(amount: int):
	wood += amount
	var hud = _hud()
	if hud and hud.has_method("set_wood"):
		hud.set_wood(wood)

func add_gold(amount: int):
	gold += amount
	var hud = _hud()
	if hud and hud.has_method("set_gold"):
		hud.set_gold(gold)

func add_iron(amount: int):
	iron += amount
	var hud = _hud()
	if hud and hud.has_method("set_iron"):
		hud.set_iron(iron)

func add_copper(amount: int):
	copper += amount
	var hud = _hud()
	if hud and hud.has_method("set_copper"):
		hud.set_copper(copper)

func add_stone(amount: int):
	stone += amount
	var hud = _hud()
	if hud and hud.has_method("set_stone"):
		hud.set_stone(stone)

func add_water(amount: int):
	water += amount
	var hud = _hud()
	if hud and hud.has_method("set_water"):
		hud.set_water(water)

func add_food(amount: int):
	food += amount
	var hud = _hud()
	if hud and hud.has_method("set_food"):
		hud.set_food(food)

# Toggle deselect button based on selection size
func _on_map_selection_changed(count: int) -> void:
	if has_node("CanvasLayer/DeselectButton"):
		$CanvasLayer/DeselectButton.visible = count > 0

func _on_deselect_pressed() -> void:
	if has_node("Map") and $Map.has_method("clear_selection_public"):
		$Map.clear_selection_public()
