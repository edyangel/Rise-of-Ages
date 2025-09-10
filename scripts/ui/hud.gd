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
const _ICONS_TEX: Texture2D = preload("res://MiniWorldSprites/User Interface/Icons-Essentials.png")

# cached icon sheet data
var _icons_tex: Texture2D = null
var _grid_cols := 4
var _grid_rows := 4
var _cell_w := 16
var _cell_h := 16

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

	# Wood icon from Trees.png trunk frame (frame 0)
	var TreeDataRef = preload("res://scripts/tree_data.gd")
	var wood_icon: TextureRect = box.get_node_or_null("WoodIcon")
	if wood_icon:
		var tex: Texture2D = _TREES_TEX
		if tex:
			var fw = int(tex.get_size().x / TreeDataRef.FRAME_COLS)
			var fh = int(tex.get_size().y)
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(0, 0, fw, fh) # trunk at col 0
			wood_icon.texture = at
			wood_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			wood_icon.custom_minimum_size = Vector2(20, 20)
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
