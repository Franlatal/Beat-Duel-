extends Control

## Every level in the game, in display order. Add a line here when you
## add a new .tres under res://resources/levels/.
##
## This is an explicit list rather than a directory scan on purpose:
## scanning res:// works in the editor but is unreliable in exported
## builds, where resources get remapped.
const LEVEL_PATHS: Array[String] = [
	"res://resources/levels/tutorial.tres",
	"res://resources/levels/level_1.tres",
]

const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"

const LEVEL_CARD_SCENE := preload("res://scenes/LevelCard.tscn")

@onready var level_list: VBoxContainer = %LevelList
@onready var back_button: Button = %BackButton
@onready var empty_label: Label = %EmptyLabel

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_build_list()

func _build_list() -> void:
	for child in level_list.get_children():
		child.queue_free()

	var levels := _load_levels()
	empty_label.visible = levels.is_empty()

	var first_card: Control = null
	for level in levels:
		var card: LevelCard = LEVEL_CARD_SCENE.instantiate()
		level_list.add_child(card)
		card.setup(level)
		card.level_chosen.connect(_on_level_chosen)
		if first_card == null and level.unlocked:
			first_card = card

	# So the list is usable with a keyboard or controller straight away.
	if first_card != null:
		first_card.grab_focus()

func _load_levels() -> Array[LevelData]:
	var result: Array[LevelData] = []
	for path in LEVEL_PATHS:
		if not ResourceLoader.exists(path):
			push_warning("LevelSelect: no level resource at %s" % path)
			continue
		var res := load(path)
		if res is LevelData:
			result.append(res)
		else:
			push_warning("LevelSelect: %s is not a LevelData resource" % path)
	return result

func _on_level_chosen(level: LevelData, difficulty: DifficultyOption) -> void:
	if level.level_scene == null:
		push_warning("LevelSelect: %s has no level_scene set" % level.title)
		return
	GameSession.start(level, difficulty)
	get_tree().change_scene_to_packed(level.level_scene)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_on_back_pressed()
