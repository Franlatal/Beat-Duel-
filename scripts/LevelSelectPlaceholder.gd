extends Control
## Placeholder so the Play button has somewhere to go. Swap this scene
## out for your real level-select screen whenever it's ready -- just
## update LEVEL_SELECT_SCENE in MainMenu.gd to point at it.

@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
