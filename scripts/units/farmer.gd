extends CharacterBody2D

## Farmer unit with team-colored spritesheets and explicit animation slicing.
## Spritesheet spec:
## - PNG size: 80x192, grid 5 cols x 12 rows (each frame 16x16)
## - Frame indices are 1-based in the spec below; code converts to 0-based.
## Ranges (inclusive):
##  1..5   walk_down
##  6..10  walk_up
##  11..15 walk_right
##  16..20 walk_left
##  21..25 run_down
##  26..30 run_up
##  31..35 run_left
##  36..40 run_right
##  41..43 attack_down
##  46..48 attack_up
##  51..53 attack_right
##  56..58 attack_left

@export_enum("Cyan", "Lime", "Purple", "Red") var team_color: String = "Cyan"
@export var speed_walk: float = 80.0
@export var speed_run: float = 140.0
@export var approach_radius: float = 6.0

var _moving: bool = false
var _running: bool = false
var _move_dir: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _selected: bool = false
var _hp_max: int = 20
var _hp: int = 20

# placeholders to interop with map.gd safety checks
var _is_chopping := false
var _chop_tile := Vector2.ZERO
var _chop_slot := -1

# Lumberjack mode: auto-seek trees within a radius (configurable via Balance)
var _lumberjack_mode: bool = false
const _SCAN_PERIOD := 0.8
var _scan_cooldown := 0.0

# Intent queue processed in physics to avoid heavy work on input thread
var _intent: Dictionary = {}

const FRAME_W := 16
const FRAME_H := 16
const SHEET_COLS := 5
const SHEET_ROWS := 12

@onready var anim: AnimatedSprite2D = (
	$AnimatedSprite2D if has_node("AnimatedSprite2D") else _make_anim_node()
)

func _ready() -> void:
	_build_frames()
	_play_idle(Vector2.DOWN)
	set_physics_process(true)
	# scale up 15%
	if self is Node2D:
		scale = Vector2(1.15, 1.15)
	# Collide only with environment (layer 1). Put farmers on layer 2 so they don't collide with each other.
	collision_layer = 2
	collision_mask = 1
	# Ensure crisp pixel art (no smoothing)
	if anim:
		anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		anim.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED

func _physics_process(_delta: float) -> void:
	# Process intents first (e.g., lumberjack chop request)
	if _intent.has("type"):
		var t = String(_intent.get("type", ""))
		if t == "lumberjack_chop":
			var map = get_parent()
			var tile: Vector2 = _intent.get("tile", Vector2.ZERO)
			var slot: int = int(_intent.get("slot", -1))
			var queue: Array = _intent.get("queue", [])
			if map and ResourceLoader.exists("res://scripts/units/states/actions.gd"):
				var Acts = load("res://scripts/units/states/actions.gd")
				if Acts and Acts.has_method("perform_lumberjack"):
					var started = Acts.perform_lumberjack(self, map, tile, slot, queue)
					if started:
						_intent.clear()
					else:
						_intent["_retry_in"] = 0.15
			else:
				_intent.clear()
		elif t == "move_to":
			var target: Vector2 = _intent.get("target", Vector2.ZERO)
			move_to(target)
			_intent.clear()

	# tick scan cooldown
	if _scan_cooldown > 0.0:
		_scan_cooldown -= _delta
	if _moving:
		# If we have an explicit target, steer toward it with soft deceleration near the goal
		if _target != Vector2.ZERO:
			var to_go: Vector2 = (_target - global_position)
			var dist := to_go.length()
			_move_dir = to_go
			var base_speed := speed_run if _running else speed_walk
			# Decelerate within a radius so we don't visibly snap at the end
			var decel_radius: float = max(approach_radius * 3.0, 24.0)
			var factor: float = clamp(dist / decel_radius, 0.15, 1.0)
			var step: Vector2 = to_go.normalized() * base_speed * factor
			velocity = step
			# Consider arrived when extremely close; then finalize without a visible jump
			if dist <= 0.5:
				global_position = _target
				_target = Vector2.ZERO
				_moving = false
				_running = false
				velocity = Vector2.ZERO
				# If we have a chop task assigned on this tile, begin chopping now so attack anim plays
				var started := false
				var map = get_parent()
				if map and map.has_method("_world_pos_for_slot"):
					var my_tile = Vector2(floor(global_position.x / map.TILE_SIZE), floor(global_position.y / map.TILE_SIZE))
					for k in map.chop_tasks.keys():
						var task = map.chop_tasks[k]
						if task.tile == my_tile and task.units.has(self):
							var sl = int(task.slot)
							start_chopping(my_tile, sl)
							started = true
							break
				if not started:
					if not _attempt_start_chopping_here():
						_play_idle(to_go)
		else:
			# No target: keep previous velocity (e.g., command_move) and play move anim
			velocity = _move_dir.normalized() * (speed_run if _running else speed_walk)
		move_and_slide()
		# Switch to walk animation when decelerating to reinforce visual smoothness
		var is_slow := velocity.length() < (speed_walk * 0.75)
		_play_move(_move_dir, _running and not is_slow)
	else:
		velocity = Vector2.ZERO
		# Keep attacking while chopping; otherwise idle
		if _is_chopping:
			var map = get_parent()
			var dir = Vector2.DOWN
			if map and map.has_method("_world_pos_for_slot"):
				var base = map._world_pos_for_slot(_chop_tile, _chop_slot)
				dir = base - global_position
			_play_attack(dir)
		else:
			_play_idle(_move_dir)
			# If in lumberjack mode, periodically look for nearby trees and start chopping
			if _lumberjack_mode and _scan_cooldown <= 0.0:
				if _try_lumberjack_scan():
					_scan_cooldown = _SCAN_PERIOD
				else:
					_scan_cooldown = _SCAN_PERIOD

func command_move(direction: Vector2, running: bool=false) -> void:
	_moving = direction.length() > 0.1
	_running = running
	_move_dir = direction
	_target = Vector2.ZERO

func move_to(target: Vector2, run: bool=false) -> void:
	_target = target
	_running = run
	_moving = true
	_move_dir = (target - global_position)

func set_selected(value: bool) -> void:
	_selected = value
	if anim:
		# keep original colors; avoid yellow tint that can look like team switch
		anim.modulate = Color(1,1,1)
	queue_redraw()

func stop_chopping() -> void:
	_is_chopping = false
	_chop_tile = Vector2.ZERO
	_chop_slot = -1
	_play_idle(Vector2.DOWN)

func command_attack(direction: Vector2) -> void:
	_moving = false
	_running = false
	_move_dir = direction
	_play_attack(direction)

func set_lumberjack(on: bool=true) -> void:
	_lumberjack_mode = on

func want_chop_lumberjack(tile: Vector2, slot: int, queue: Array=[]) -> void:
	_intent = {"type": "lumberjack_chop", "tile": tile, "slot": slot, "queue": queue}

func is_lumberjack() -> bool:
	return _lumberjack_mode

func set_team_color(color_name: String) -> void:
	team_color = color_name
	_build_frames()

func _make_anim_node() -> AnimatedSprite2D:
	var a = AnimatedSprite2D.new()
	a.name = "AnimatedSprite2D"
	add_child(a)
	return a

func _sheet_path() -> String:
	# Try known locations for the spritesheets; return the first that exists.
	var candidates = [
		"res://MiniWorldSprites/Characters/Workers/%sWorker/Farmer%s.png" % [team_color, team_color],
		"res://scenes/units/farmer/Farmer%s.png" % team_color,
		"res://MiniWorldSprites/Characters/Workers/Farmer%s.png" % team_color,
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			return p
	return candidates[0]

func _build_frames() -> void:
	var tex = load(_sheet_path()) as Texture2D
	if not tex:
		push_warning("Farmer spritesheet not found: %s" % _sheet_path())
		return
	var frames = SpriteFrames.new()

	# local alias to use instance method for building ranges
	var _add = func(anim_name: String, start_i: int, end_i: int, fps: float, looped: bool=true):
		frames.add_animation(anim_name)
		for idx in range(start_i, end_i + 1):
			var at = AtlasTexture.new()
			at.atlas = tex
			at.region = _region_for_index(idx)
			frames.add_frame(anim_name, at)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, looped)

	# Walk
	_add.call("walk_down", 1, 5, 8, true)
	_add.call("walk_up", 6, 10, 8, true)
	_add.call("walk_right", 11, 15, 8, true)
	_add.call("walk_left", 16, 20, 8, true)
	# Run
	_add.call("run_down", 21, 25, 10, true)
	_add.call("run_up", 26, 30, 10, true)
	_add.call("run_left", 31, 35, 10, true)
	_add.call("run_right", 36, 40, 10, true)
	# Attack (short and non-loop)
	_add.call("attack_down", 41, 43, 8, true)
	_add.call("attack_up", 46, 48, 8, true)
	_add.call("attack_right", 51, 53, 8, true)
	_add.call("attack_left", 56, 58, 8, true)

	# Idle frames as first frame of each walk direction
	frames.add_animation("idle_down")
	frames.add_frame("idle_down", _atlas_frame(tex, 1))
	frames.set_animation_speed("idle_down", 1)
	frames.set_animation_loop("idle_down", false)

	frames.add_animation("idle_up")
	frames.add_frame("idle_up", _atlas_frame(tex, 6))
	frames.set_animation_speed("idle_up", 1)
	frames.set_animation_loop("idle_up", false)

	frames.add_animation("idle_right")
	frames.add_frame("idle_right", _atlas_frame(tex, 11))
	frames.set_animation_speed("idle_right", 1)
	frames.set_animation_loop("idle_right", false)

	frames.add_animation("idle_left")
	frames.add_frame("idle_left", _atlas_frame(tex, 16))
	frames.set_animation_speed("idle_left", 1)
	frames.set_animation_loop("idle_left", false)

	anim.frames = frames

func _atlas_frame(tex: Texture2D, index1: int) -> AtlasTexture:
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = _region_for_index(index1)
	return at

func _region_for_index(index1: int) -> Rect2:
	# Convert 1-based linear index to (col,row)
	var zero = index1 - 1
	var col = zero % SHEET_COLS
	var row = int(floor(float(zero) / float(SHEET_COLS)))
	return Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)

func _play_move(dir: Vector2, running: bool) -> void:
	if dir.length() < 0.1:
		_play_idle(Vector2.DOWN)
		return
	var horiz = abs(dir.x) >= abs(dir.y)
	if running:
		if horiz:
			if dir.x >= 0:
				anim.play("run_right")
			else:
				anim.play("run_left")
		else:
			if dir.y >= 0:
				anim.play("run_down")
			else:
				anim.play("run_up")
	else:
		if horiz:
			if dir.x >= 0:
				anim.play("walk_right")
			else:
				anim.play("walk_left")
		else:
			if dir.y >= 0:
				anim.play("walk_down")
			else:
				anim.play("walk_up")

func _play_attack(dir: Vector2) -> void:
	var horiz = abs(dir.x) >= abs(dir.y)
	if horiz:
		if dir.x >= 0:
			anim.play("attack_right")
		else:
			anim.play("attack_left")
	else:
		if dir.y >= 0:
			anim.play("attack_down")
		else:
			anim.play("attack_up")

func _play_idle(dir: Vector2) -> void:
	if abs(dir.x) >= abs(dir.y):
		anim.animation = "idle_right" if dir.x >= 0 else "idle_left"
	else:
		anim.animation = "idle_down" if dir.y >= 0 else "idle_up"
	anim.stop()
	anim.frame = 0
	queue_redraw()

func start_chopping(tile: Vector2, slot: int) -> void:
	_is_chopping = true
	_chop_tile = tile
	_chop_slot = slot
	_moving = false
	_target = Vector2.ZERO
	# choose attack animation based on relative direction
	var map = get_parent()
	var dir = Vector2.DOWN
	var base: Vector2 = Vector2.ZERO
	if map and map.has_method("_world_pos_for_slot"):
		base = map._world_pos_for_slot(tile, slot)
		dir = base - global_position
	_play_attack(dir)
	# z-index relative to tree base (map uses tree z_index ~40)
	var tree_z = 40
	if global_position.y < base.y:
		z_index = tree_z - 1
	else:
		z_index = tree_z + 1

func _attempt_start_chopping_here() -> bool:
	var map = get_parent()
	if not map:
		return false
	# Assume we are child of map.gd which has TILE_SIZE, chop_tasks, and _world_pos_for_slot
	var tile = Vector2(floor(global_position.x / map.TILE_SIZE), floor(global_position.y / map.TILE_SIZE))
	for k in map.chop_tasks.keys():
		var task = map.chop_tasks[k]
		if task.tile == tile and task.units.has(self):
			var sl = task.slot
			if task.has("assigned_slot") and task.assigned_slot.has(self):
				sl = int(task.assigned_slot[self])
			start_chopping(tile, int(sl))
			return true
	return false

func _try_lumberjack_scan() -> bool:
	# Find nearest live tree using map’s fast helpers
	var m = get_parent()
	if not m:
		return false
	# configurable radius
	var radius = 5
	if ResourceLoader.exists("res://scripts/config/balance.gd"):
		var B = load("res://scripts/config/balance.gd")
		if B and B.has_method("lumber_radius_tiles"):
			radius = B.lumber_radius_tiles()
	var nearest = Vector2.ZERO
	var slot_i := -1
	# Prefer ring scan centered on our tile
	var tx = int(floor(global_position.x / m.TILE_SIZE))
	var ty = int(floor(global_position.y / m.TILE_SIZE))
	var center = Vector2(tx, ty)
	var best_d := 1e9
	for dist in range(0, radius + 1):
		if dist == 0:
			var k0 = m._get_tile_key(center) if m.has_method("_get_tile_key") else ""
			if k0 != "" and m.resource_slots.has(k0):
				for si in range(5):
					if m.resource_slots[k0][si] == "TREE":
						var pos0 = m._world_pos_for_slot(center, si)
						var d0 = global_position.distance_to(pos0)
						if d0 < best_d:
							best_d = d0
							nearest = center
							slot_i = si
		else:
			var cx = int(center.x)
			var cy = int(center.y)
			var d = dist
			for x in range(cx - d, cx + d + 1):
				var t_top = Vector2(x, cy - d)
				var kt = m._get_tile_key(t_top)
				if m.resource_slots.has(kt):
					for si in range(5):
						if m.resource_slots[kt][si] == "TREE":
							var p1 = m._world_pos_for_slot(t_top, si)
							var dd = global_position.distance_to(p1)
							if dd < best_d:
								best_d = dd
								nearest = t_top
								slot_i = si
				var t_bot = Vector2(x, cy + d)
				var kb = m._get_tile_key(t_bot)
				if m.resource_slots.has(kb):
					for sj in range(5):
						if m.resource_slots[kb][sj] == "TREE":
							var p2 = m._world_pos_for_slot(t_bot, sj)
							var dd2 = global_position.distance_to(p2)
							if dd2 < best_d:
								best_d = dd2
								nearest = t_bot
								slot_i = sj
			for y in range(cy - d + 1, cy + d):
				var t_left = Vector2(cx - d, y)
				var kl = m._get_tile_key(t_left)
				if m.resource_slots.has(kl):
					for sk in range(5):
						if m.resource_slots[kl][sk] == "TREE":
							var p3 = m._world_pos_for_slot(t_left, sk)
							var dd3 = global_position.distance_to(p3)
							if dd3 < best_d:
								best_d = dd3
								nearest = t_left
								slot_i = sk
				var t_right = Vector2(cx + d, y)
				var kr = m._get_tile_key(t_right)
				if m.resource_slots.has(kr):
					for sl in range(5):
						if m.resource_slots[kr][sl] == "TREE":
							var p4 = m._world_pos_for_slot(t_right, sl)
							var dd4 = global_position.distance_to(p4)
							if dd4 < best_d:
								best_d = dd4
								nearest = t_right
								slot_i = sl
		if slot_i >= 0:
			break
	if slot_i >= 0:
		return m.start_chop(nearest, slot_i, self)
	return false

func _draw() -> void:
	# Draw small HP bar only when selected
	if not _selected:
		return
	var w: float = 18.0
	var h: float = 3.0
	var offset := Vector2(0, -18)
	var pos := Vector2(global_position.x, global_position.y) + offset - Vector2(w/2.0, 0)
	# Since _draw is in local space, convert to local
	pos = to_local(pos + Vector2(w/2.0, 0)) - Vector2(w/2.0, 0)
	draw_rect(Rect2(pos + Vector2(-1,-1), Vector2(w+2, h+2)), Color(0,0,0,0.6), true)
	var frac: float = clamp(float(_hp) / float(max(_hp_max,1)), 0.0, 1.0)
	draw_rect(Rect2(pos, Vector2(w * frac, h)), Color(0.2,1.0,0.2,0.95), true)
