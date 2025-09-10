extends Control

func _ready():
    $Panel/HBoxContainer/Left/ItemList.item_selected.connect(_on_item_selected)

func _on_item_selected(index):
    var item_name = $Panel/HBoxContainer/Left/ItemList.get_item_text(index)
    $Panel/HBoxContainer/Right/Instructions.text = "Editando: %s".format(item_name)
    # Placeholder: cargar preview o abrir editor de píxeles
