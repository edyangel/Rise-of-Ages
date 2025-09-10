extends Panel

# Simple top HUD: centered HBox with icon+value pairs

@onready var box: HBoxContainer = get_node_or_null("Center/Resources")

# Resource values
var wood := 0
var gold := 0
var iron := 0
var copper := 0
var stone := 0
var water := 0
var food := 0

const ICONS_PATH := "res://MiniWorldSprites/User Interface/Icons-Essentials.png" # 64x64, 4x4 grid of 16x16

# Preload textures to avoid runtime load failures and ensure availability
const _TREES_TEX: Texture2D = preload("res://MiniWorldSprites/Nature/Trees.png")
# Custom wood image override (if present)
const _WOOD_CUSTOM: Texture2D = preload("res://MiniWorldSprites/Objects/madera.png")
const _ICONS_TEX: Texture2D = preload("res://MiniWorldSprites/User Interface/Icons-Essentials.png")

# cached icon sheet data
var _icons_tex: Texture2D = null
var _grid_cols := 4
var _grid_rows := 4
var _cell_w := 16
var _cell_h := 16

# cache for wood pyramid rebuild
var _wood_atlas: AtlasTexture = null

func _ready():
	_setup_icons()
	_refresh_all()
	# Ensure icons apply after the scene tree is fully ready
	call_deferred("_setup_icons")
	call_deferred("_refresh_all")

func _setup_icons():
	# Robustly find the box even if layout changed
	if box == null:
		box = get_node_or_null("Resources")
	if box == null:
		return

	# If someone left children at root like "Resources#WoodIcon", move them under the box and rename.
	var root := self
	if root and root is Node:
		for child in root.get_children():
			if not (child and child is Node):
				continue
			var nm := String(child.name)
			if nm.begins_with("Resources#"):
				var new_name := nm.substr(10, nm.length() - 10)
				# Avoid duplicate names
				if box.has_node(new_name):
					# remove old to avoid duplicates
					var old = box.get_node_or_null(new_name)
					if old and old is Node and old.get_parent():
						old.get_parent().remove_child(old)
				# Reparent and rename
				root.remove_child(child)
				box.add_child(child)
				child.name = new_name

	# Wood icon from Trees.png trunk frame (frame 0)
	var TreeDataRef = preload("res://scripts/tree_data.gd")
	var wood_icon: TextureRect = box.get_node_or_null("WoodIcon")
	if wood_icon:
		# Prefer custom madera.png if available
		var tex: Texture2D = _WOOD_CUSTOM if _WOOD_CUSTOM != null else _TREES_TEX
		if tex:
			var fw: int
			var fh: int
			if tex == _WOOD_CUSTOM:
				# Treat as single image (square or rectangular): use full image region
				fw = int(tex.get_size().x)
				fh = int(tex.get_size().y)
			else:
				fw = int(tex.get_size().x / TreeDataRef.FRAME_COLS)
				fh = int(tex.get_size().y)
			var at := AtlasTexture.new()
			at.atlas = tex
			# If using Trees.png, trunk at col 0; else whole image
			at.region = Rect2(0, 0, fw, fh)
			# Show only a single image
			# Clean up any previous pyramid children
			for c in wood_icon.get_children():
				if c and c is Node and String(c.name).begins_with("_w_"):
					wood_icon.remove_child(c)
					c.queue_free()
			# Disconnect resize handler if previously connected
			if wood_icon.is_connected("resized", Callable(self, "_on_wood_icon_resized")):
				wood_icon.disconnect("resized", Callable(self, "_on_wood_icon_resized"))
			_wood_atlas = null
			wood_icon.texture = at
			wood_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			wood_icon.custom_minimum_size = Vector2(24, 24)
			wood_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		elif _ICONS_TEX:
			# Fallback to icon sheet (choose some frame as placeholder)
			_icons_tex = _ICONS_TEX
			_cell_w = int(_icons_tex.get_size().x / _grid_cols)
			_cell_h = int(_icons_tex.get_size().y / _grid_rows)
			_set_icon("WoodIcon", 5) # arbitrary fallback frame

	# Other icons from icons-essentials.png frames: 1,2,3,4,8,9
	# Mapping: gold=1, iron=2, copper=3, stone=4, water=8, food=9
	_icons_tex = _ICONS_TEX
	if _icons_tex:
		_cell_w = int(_icons_tex.get_size().x / _grid_cols)
		_cell_h = int(_icons_tex.get_size().y / _grid_rows)

	_set_icon("GoldIcon", 1)
	_set_icon("IronIcon", 2)
	_set_icon("CopperIcon", 3)
	_set_icon("StoneIcon", 4)
	_set_icon("WaterIcon", 8)
	_set_icon("FoodIcon", 9)

func _set_icon(node_name: String, frame_idx_1based: int) -> void:
	if box == null:
		return
	var node: TextureRect = box.get_node_or_null(node_name)
	if node == null:
		return
	if _icons_tex == null:
		node.texture = null
		return
	var idx0 = max(0, frame_idx_1based - 1)
	var col = idx0 % _grid_cols
	var row = int(idx0 / _grid_cols)
	var at2 := AtlasTexture.new()
	at2.atlas = _icons_tex
	at2.region = Rect2(col * _cell_w, row * _cell_h, _cell_w, _cell_h)
	node.texture = at2
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = Vector2(20, 20)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _ensure_child_tex(parent: Control, child_name: String, atlas: AtlasTexture) -> TextureRect:
	var texr: TextureRect = parent.get_node_or_null(child_name)
	if texr == null:
		texr = TextureRect.new()
		texr.name = child_name
		texr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		parent.add_child(texr)
	texr.texture = atlas
	return texr

func _build_wood_pyramid(wood_icon: TextureRect, atlas: AtlasTexture) -> void:
	if wood_icon == null:
		return
	# Clear base texture (we'll draw children)
	wood_icon.texture = null
	var base_w = max(wood_icon.size.x, wood_icon.custom_minimum_size.x)
	var base_h = max(wood_icon.size.y, wood_icon.custom_minimum_size.y)
	if base_w <= 0 or base_h <= 0:
		base_w = 24
		base_h = 24
	var s = int(floor(min(base_w, base_h) * 0.38))
	s = clamp(s, 6, 14)
	# tighter layout: slight horizontal overlap, no vertical gap
	var h_gap = -1
	var v_gap = 0
	var row_h = s + v_gap
	var bottom_y = int(base_h) - s # align bottom to control bottom
	# positions for rows (bottom 3, middle 2, top 1)
	var total_w = 3 * s + 2 * h_gap
	var x0 = int(round((base_w - total_w) * 0.5))
	var y_bottom = bottom_y
	var y_mid = y_bottom - row_h
	var y_top = y_mid - row_h
	# create/update children
	var b1 = _ensure_child_tex(wood_icon, "_w_b1", atlas)
	var b2 = _ensure_child_tex(wood_icon, "_w_b2", atlas)
	var b3 = _ensure_child_tex(wood_icon, "_w_b3", atlas)
	var m1 = _ensure_child_tex(wood_icon, "_w_m1", atlas)
	var m2 = _ensure_child_tex(wood_icon, "_w_m2", atlas)
	var t1 = _ensure_child_tex(wood_icon, "_w_t1", atlas)
	# set sizes
	for n in [b1,b2,b3,m1,m2,t1]:
		n.custom_minimum_size = Vector2(s, s)
		n.size = Vector2(s, s)
		n.anchor_left = 0
		n.anchor_top = 0
		n.anchor_right = 0
		n.anchor_bottom = 0
		n.grow_horizontal = Control.GROW_DIRECTION_BOTH
		n.grow_vertical = Control.GROW_DIRECTION_BOTH
	# positions
	b1.position = Vector2(x0, y_bottom)
	b2.position = Vector2(x0 + (s + h_gap), y_bottom)
	b3.position = Vector2(x0 + 2 * (s + h_gap), y_bottom)
	m1.position = Vector2(x0 + int(round(0.5 * (s + h_gap))), y_mid)
	m2.position = Vector2(x0 + int(round(1.5 * (s + h_gap))), y_mid)
	t1.position = Vector2(x0 + (s + h_gap), y_top)

func _on_wood_icon_resized() -> void:
	if box == null:
		return
	var wood_icon: TextureRect = box.get_node_or_null("WoodIcon")
	if wood_icon and _wood_atlas:
		_build_wood_pyramid(wood_icon, _wood_atlas)

func _refresh_all():
	_set_label_text("WoodValue", wood)
	_set_label_text("GoldValue", gold)
	_set_label_text("IronValue", iron)
	_set_label_text("CopperValue", copper)
	_set_label_text("StoneValue", stone)
	_set_label_text("WaterValue", water)
	_set_label_text("FoodValue", food)

func _set_label_text(node_name: String, value: int):
	if box == null:
		return
	var label: Label = box.get_node_or_null(node_name)
	if label:
		label.text = str(value)

# Update APIs used by game.gd
func set_wood(v: int): wood = v; _set_label_text("WoodValue", wood)
func set_gold(v: int): gold = v; _set_label_text("GoldValue", gold)
func set_iron(v: int): iron = v; _set_label_text("IronValue", iron)
func set_copper(v: int): copper = v; _set_label_text("CopperValue", copper)
func set_stone(v: int): stone = v; _set_label_text("StoneValue", stone)
func set_water(v: int): water = v; _set_label_text("WaterValue", water)
func set_food(v: int): food = v; _set_label_text("FoodValue", food)
