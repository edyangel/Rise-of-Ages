extends CharacterBody2D

@export var speed: float = 120.0
@export var approach_radius: float = 6.0
var _selected := false
var _target: Vector2 = Vector2.ZERO

# mapping animation name -> png path (spritesheets expected horizontal frames)
const ANIM_PATHS := {
	"idle_down": "res://scenes/units/soldado 1/IDLE/idle_down.png",
	"idle_up": "res://scenes/units/soldado 1/IDLE/idle_up.png",
	"idle_left": "res://scenes/units/soldado 1/IDLE/idle_left.png",
	"idle_right": "res://scenes/units/soldado 1/IDLE/idle_right.png",
	"run_down": "res://scenes/units/soldado 1/RUN/run_down.png",
	"run_up": "res://scenes/units/soldado 1/RUN/run_up.png",
	"run_left": "res://scenes/units/soldado 1/RUN/run_left.png",
	"run_right": "res://scenes/units/soldado 1/RUN/run_right.png",
	"attack_down": "res://scenes/units/soldado 1/ATTACK 1/attack1_down.png",
	"attack_up": "res://scenes/units/soldado 1/ATTACK 1/attack1_up.png",
	"attack_left": "res://scenes/units/soldado 1/ATTACK 1/attack1_left.png",
	"attack_right": "res://scenes/units/soldado 1/ATTACK 1/attack1_right.png",
}

# frames per animation if spritesheets use non-square frames
const ANIM_FRAMES := {
	"idle_down": 8,
	"idle_up": 8,
	"idle_left": 8,
	"idle_right": 8,
	"run_down": 8,
	"run_up": 8,
	"run_left": 8,
	"run_right": 8,
	"attack_down": 8,
	"attack_up": 8,
	"attack_left": 8,
	"attack_right": 8,
}

var _is_chopping := false
var _chop_tile := Vector2.ZERO
var _chop_slot := -1
var _orig_z := 0

enum State { IDLE, MOVE, CHOP }
var _state: State = State.IDLE
var _arrival_timer: float = 0.0
var _last_dist: float = 0.0

func _ready():
	_build_sprite_frames()
	if $AnimatedSprite2D:
		# set to idle frame without playing the animation to avoid duplicated drawing
		$AnimatedSprite2D.animation = "idle_down"
		$AnimatedSprite2D.stop()
		$AnimatedSprite2D.frame = 0
		# crisp pixel art
		$AnimatedSprite2D.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		$AnimatedSprite2D.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED

	# make the soldier smaller so it fits multiple per tile
	if self is Node2D:
		self.scale = Vector2(0.6, 0.6)

func _build_sprite_frames() -> void:
	var frames = SpriteFrames.new()
	var idle_names = ["idle_down", "idle_up", "idle_left", "idle_right"]
	for anim_name in ANIM_PATHS.keys():
		var path = ANIM_PATHS[anim_name]
		var tex = load(path) as Texture2D
		if not tex:
			continue
		var size = tex.get_size()
		var frame_h = int(size.y)
		var frames_count = 1
		if anim_name in ANIM_FRAMES:
			frames_count = ANIM_FRAMES[anim_name]
		else:
			# fallback: try to compute assuming square frames
			frames_count = max(1, int(size.x / frame_h))
		# compute frame width based on frames_count (support non-square frames)
		var frame_w = int(size.x / frames_count)
		frames.add_animation(anim_name)
		# If this is an idle animation, only add the first frame to avoid wiggle
		if anim_name in idle_names:
			var at = AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(0, 0, frame_w, frame_h)
			frames.add_frame(anim_name, at)
			frames.set_animation_speed(anim_name, 1)
			frames.set_animation_loop(anim_name, false)
		else:
			for i in range(frames_count):
				var at = AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * frame_w, 0, frame_w, frame_h)
				frames.add_frame(anim_name, at)
			frames.set_animation_speed(anim_name, 8)
			frames.set_animation_loop(anim_name, true)
	$AnimatedSprite2D.frames = frames

func set_selected(value: bool) -> void:
	_selected = value
	if $AnimatedSprite2D:
		# keep original colors; avoid yellow tint
		$AnimatedSprite2D.modulate = Color(1,1,1)

func is_selected() -> bool:
	return _selected

func move_to(target: Vector2) -> void:
	# set global target and switch to running animation
	_target = target
	_state = State.MOVE
	var dir = (target - global_position)
	if dir.length() > 0:
		_update_animation_for_direction(dir.normalized())
	# ensure the run animation is playing (direction selected in _update_animation_for_direction)
	# call play() to start the animation (animation name already set by direction)
	$AnimatedSprite2D.play()
	_arrival_timer = 0.0
	_last_dist = (target - global_position).length()

func _physics_process(delta: float) -> void:
	if _state == State.MOVE and _target != Vector2.ZERO:
		var dir = (_target - global_position)
		var dist = dir.length()
		# arrival threshold: approach_radius
		if dist <= approach_radius:
			# Snap to target to align with fixed slot centers
			global_position = _target
			_target = Vector2.ZERO
			_state = State.IDLE
			# arrival: if this target corresponds to a tree slot, request chop
			var map = get_parent()
			if map:
				var tile = Vector2(floor(global_position.x / map.TILE_SIZE), floor(global_position.y / map.TILE_SIZE))
				# find the slot index nearest to our position
				var slot_idx = -1
				for i in range(5):
					var sp = map._world_pos_for_slot(tile, i)
					# consider approach targets assigned by map.chop_tasks for this unit
					var key_i = str(int(tile.x)) + "," + str(int(tile.y)) + ":" + str(i)
					if map.chop_tasks.has(key_i) and map.chop_tasks[key_i].has("approach") and map.chop_tasks[key_i].approach.has(self):
						var appr = map.chop_tasks[key_i].approach[self]
						if appr.distance_to(global_position) < 10:
							slot_idx = i
							break
					elif sp.distance_to(global_position) < 8:
						slot_idx = i
						break
				# after loop, handle found slot
				if slot_idx != -1 and map.has_method("chop_tree_at"):
					var key_slot = str(int(tile.x)) + "," + str(int(tile.y)) + ":" + str(slot_idx)
					if map.chop_tasks.has(key_slot):
						var task = map.chop_tasks[key_slot]
						if task.units.has(self):
							# If task stored our slot, prefer that
							if task.has("assigned_slot") and task.assigned_slot.has(self):
								var want_slot = int(task.assigned_slot[self])
								if want_slot != slot_idx:
									slot_idx = want_slot
									tile = Vector2(floor(global_position.x / map.TILE_SIZE), floor(global_position.y / map.TILE_SIZE))
							# Only start chopping if we're inside the exact task tile
							var my_tile = Vector2(floor(global_position.x / map.TILE_SIZE), floor(global_position.y / map.TILE_SIZE))
							if my_tile == tile:
								if not _is_chopping:
									start_chopping(tile, slot_idx)
							else:
								# Arrived near but outside tile due to pathing; do not force chopping
								pass
							# decide attack animation based on our relative position to the tree's base
							var base_pos = map._world_pos_for_slot(tile, slot_idx)
							var rel = (base_pos - global_position)
							# start_chopping may already have been called above; guard duplicate
							if not _is_chopping and my_tile == tile:
								start_chopping(tile, slot_idx)
							# force immediate attack animation to avoid run-loop
							# (we already selected direction below)
							# choose the attack animation to match where the soldier stands relative to the tree
							if abs(rel.x) > abs(rel.y):
								if rel.x > 0:
									$AnimatedSprite2D.play("attack_right")
								else:
									$AnimatedSprite2D.play("attack_left")
							else:
								if rel.y > 0:
									$AnimatedSprite2D.play("attack_down")
								else:
									$AnimatedSprite2D.play("attack_up")
			# if we started chopping, the start_chopping() call already set the attack animation
			if _is_chopping:
				_state = State.CHOP
				return
			# otherwise switch to idle
			_to_idle_anim()
			return
		# Clamp per-frame movement to avoid overshoot and visible snapping
		var vel = dir.normalized() * speed
		if vel.length() * delta >= dist:
			global_position = _target
			_target = Vector2.ZERO
			_state = State.IDLE
			_to_idle_anim()
			return
		move_and_collide(vel * delta)
		_update_animation_for_direction(dir.normalized())
		# anti-stuck: if close but not entering tile, retry toward tile center after short timeout
		_arrival_timer += delta
		if _arrival_timer >= 1.2:
			_arrival_timer = 0.0
			var map = get_parent()
			if map:
				var t_guess = Vector2(floor(_target.x / map.TILE_SIZE), floor(_target.y / map.TILE_SIZE))
				var center = (t_guess * map.TILE_SIZE) + Vector2(map.TILE_SIZE/2.0, map.TILE_SIZE/2.0)
				if (center - global_position).length() < (dist + 16.0):
					_target = center
		return
	else:
		# No movement target: if flagged chopping but the map no longer has a task or tree, stop
		var should_stop := false
		if _is_chopping:
			var map = get_parent()
			if map:
				# stop if there is no active task for our current chop tile/slot
				var key = "%d,%d:%d" % [int(_chop_tile.x), int(_chop_tile.y), int(_chop_slot)]
				if not map.chop_tasks.has(key):
					should_stop = true
				else:
					# or if the tree no longer exists
					var has_live := false
					for t in map.trees:
						if t["tile"] == _chop_tile and int(t.get("slot", -1)) == int(_chop_slot) and int(t.get("type", 0)) > 0:
							has_live = true
							break
					if not has_live:
						should_stop = true
		if should_stop:
			stop_chopping()
		# enforce idle animation when not moving and not chopping
		if not _is_chopping and _state != State.MOVE:
			_to_idle_anim()

func _update_animation_for_direction(dir: Vector2) -> void:
	# pick simple cardinal animation based on direction
	if abs(dir.x) > abs(dir.y):
		if dir.x > 0:
			$AnimatedSprite2D.play("run_right")
		else:
			$AnimatedSprite2D.play("run_left")
	else:
		if dir.y > 0:
			$AnimatedSprite2D.play("run_down")
		else:
			$AnimatedSprite2D.play("run_up")

func _to_idle_anim() -> void:
	$AnimatedSprite2D.animation = "idle_down"
	$AnimatedSprite2D.stop()
	$AnimatedSprite2D.frame = 0

func start_chopping(tile: Vector2, slot: int) -> void:
	_is_chopping = true
	_chop_tile = tile
	_chop_slot = slot
	# stop movement
	_target = Vector2.ZERO
	# play attack animation based on direction to target slot
	var map = get_parent()
	var dir = Vector2.ZERO
	if map and map.has_method("_world_pos_for_slot"):
		var wp = map._world_pos_for_slot(tile, slot)
		dir = (wp - global_position)
	if dir.length() == 0:
		dir = Vector2.DOWN
	if abs(dir.x) > abs(dir.y):
		if dir.x > 0:
			$AnimatedSprite2D.play("attack_right")
		else:
			$AnimatedSprite2D.play("attack_left")
	else:
		if dir.y > 0:
			$AnimatedSprite2D.play("attack_down")
		else:
			$AnimatedSprite2D.play("attack_up")
	# raise z_index so soldier renders above tree while chopping
	# set z_index so soldier appears behind the tree when standing above its base,
	# or in front when below. Use tree z-index constant (map uses 40 for trees).
	_orig_z = z_index
	var tree_z = 40
	var base_pos: Vector2 = Vector2()
	var has_base: bool = false
	if map and map.has_method("_world_pos_for_slot"):
		base_pos = map._world_pos_for_slot(tile, slot)
		has_base = true
	if has_base:
		# if soldier's global y is less than tree base y, soldier is above the tree -> render behind
		if global_position.y < base_pos.y:
			z_index = tree_z - 1
		else:
			z_index = tree_z + 1
	else:
		# fallback: keep high z so it appears above
		z_index = tree_z + 1

func stop_chopping() -> void:
	_is_chopping = false
	_chop_tile = Vector2.ZERO
	_chop_slot = -1
	# return to idle
	$AnimatedSprite2D.animation = "idle_down"
	$AnimatedSprite2D.stop()
	$AnimatedSprite2D.frame = 0
	# restore previous z_index
	z_index = _orig_z

func build():
	print("Soldado build placeholder")
