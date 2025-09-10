extends Node2D

func _ready():
    print("Main ready")
    if has_node("BackButton"):
        $BackButton.connect("pressed", Callable(self, "_on_back_pressed"))

func _on_back_pressed():
    get_tree().change_scene_to_file("res://scenes/menu.tscn")
