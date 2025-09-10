extends Node2D

var _active: bool = false
var _p1: Vector2 = Vector2.ZERO
var _p2: Vector2 = Vector2.ZERO

func set_rect(p1: Vector2, p2: Vector2) -> void:
    _p1 = p1
    _p2 = p2
    _active = true
    visible = true
    queue_redraw()

func clear() -> void:
    _active = false
    visible = false
    queue_redraw()

func _draw() -> void:
    if not _active:
        return
    var top_left = Vector2(min(_p1.x, _p2.x), min(_p1.y, _p2.y))
    var size = Vector2(abs(_p2.x - _p1.x), abs(_p1.y - _p2.y))
    var rect = Rect2(top_left, size)
    var fill = Color(0.1, 0.6, 1.0, 0.15)
    var border = Color(0.1, 0.6, 1.0, 0.9)
    draw_rect(rect, fill, true)
    draw_rect(rect, border, false, 2.0)
