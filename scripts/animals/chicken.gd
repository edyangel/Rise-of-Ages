extends CharacterBody2D

## Simple wandering AI for a chicken using a 4x4 (64x64) spritesheet where each frame is 16x16.
## Rows (left->right):
##  1: walk_down (4 frames)
##  2: walk_up (4 frames)
##  3: walk_left (4 frames)
##  4: walk_right (4 frames)

@export var speed_walk: float = 55.0
@export var wander_radius: float = 64.0
@export var pause_min: float = 0.6
@export var pause_max: float = 1.8

const FRAME_W := 16
const FRAME_H := 16
const SHEET_COLS := 4
const SHEET_ROWS := 4

var _moving := false
var _target: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.DOWN
var _timer := 0.0
var _pause := 0.0

@onready var anim: AnimatedSprite2D = (
    $AnimatedSprite2D if has_node("AnimatedSprite2D") else _make_anim_node()
)

func _ready() -> void:
    _build_frames()
    set_physics_process(true)
    # Crisp pixel art
    if anim:
        anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        anim.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
    # Chickens don't collide with anything by default
    collision_layer = 0
    collision_mask = 0
    _choose_new_target(true)

func _physics_process(delta: float) -> void:
    if _moving:
        var to_go = _target - global_position
        var dist = to_go.length()
        if dist < 1.0:
            global_position = _target
            _moving = false
            velocity = Vector2.ZERO
            _pause = randf_range(pause_min, pause_max)
            _timer = 0.0
            _play_idle(_dir)
        else:
            _dir = to_go
            velocity = to_go.normalized() * speed_walk
            move_and_slide()
            _play_walk(_dir)
    else:
        velocity = Vector2.ZERO
        _timer += delta
        if _timer >= _pause:
            _choose_new_target(false)

func _choose_new_target(force: bool) -> void:
    var r = randf()
    # Occasionally stay idle a bit even after pause
    if not force and r < 0.2:
        _pause = randf_range(pause_min, pause_max)
        _timer = 0.0
        _moving = false
        _play_idle(_dir)
        return
    # Pick a random point around current position
    var angle = randf() * TAU
    var radius = randf() * wander_radius
    var offset = Vector2(cos(angle), sin(angle)) * radius
    _target = global_position + offset
    _moving = true
    _dir = offset

func _make_anim_node() -> AnimatedSprite2D:
    var a = AnimatedSprite2D.new()
    a.name = "AnimatedSprite2D"
    add_child(a)
    return a

func _sheet_path() -> String:
    var candidates = [
        "res://MiniWorldSprites/Animals/Chicken.png",
        "res://MiniWorldSprites/Animals/Chicken.PNG",
        "res://MiniWorldSprites/Animals/chicken.png",
    ]
    for p in candidates:
        if ResourceLoader.exists(p):
            return p
    return candidates[0]

func _build_frames() -> void:
    var tex := load(_sheet_path()) as Texture2D
    if not tex:
        push_warning("Chicken spritesheet not found: %s" % _sheet_path())
        return
    var frames := SpriteFrames.new()

    var _add = func(anim_name: String, row1: int, frames_count: int, fps: float, looped: bool=true):
        frames.add_animation(anim_name)
        for i in range(frames_count):
            var col = i
            var row = row1 - 1
            var at = AtlasTexture.new()
            at.atlas = tex
            at.region = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
            frames.add_frame(anim_name, at)
        frames.set_animation_speed(anim_name, fps)
        frames.set_animation_loop(anim_name, looped)

    # Walk animations (3 frames each; 12 total across 4 rows)
    _add.call("walk_down", 1, 3, 8, true)
    _add.call("walk_up", 2, 3, 8, true)
    _add.call("walk_left", 3, 3, 8, true)
    _add.call("walk_right", 4, 3, 8, true)

    # Idle as frame 0 of walk
    frames.add_animation("idle_down")
    frames.add_frame("idle_down", _frame(tex, 1, 1))
    frames.add_animation("idle_up")
    frames.add_frame("idle_up", _frame(tex, 2, 1))
    frames.add_animation("idle_left")
    frames.add_frame("idle_left", _frame(tex, 3, 1))
    frames.add_animation("idle_right")
    frames.add_frame("idle_right", _frame(tex, 4, 1))
    frames.set_animation_loop("idle_down", false)
    frames.set_animation_loop("idle_up", false)
    frames.set_animation_loop("idle_left", false)
    frames.set_animation_loop("idle_right", false)

    anim.frames = frames
    anim.play("idle_down")

func _frame(tex: Texture2D, row1: int, col1: int) -> AtlasTexture:
    var at = AtlasTexture.new()
    at.atlas = tex
    at.region = Rect2((col1 - 1) * FRAME_W, (row1 - 1) * FRAME_H, FRAME_W, FRAME_H)
    return at

func _play_walk(dir: Vector2) -> void:
    if dir.length() < 0.1:
        _play_idle(Vector2.DOWN)
        return
    var horiz = abs(dir.x) >= abs(dir.y)
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

func _play_idle(dir: Vector2) -> void:
    if abs(dir.x) >= abs(dir.y):
        anim.animation = "idle_right" if dir.x >= 0 else "idle_left"
    else:
        anim.animation = "idle_down" if dir.y >= 0 else "idle_up"
    anim.stop()
    anim.frame = 0
