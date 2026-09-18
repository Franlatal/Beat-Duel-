extends Control
## Placeholder gameplay scene. It just shows which level and difficulty
## were picked, so you can confirm the selection pipeline works before
## building the actual note engine.
##
## Replace the body of _start_level() with your real gameplay setup.

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelect.tscn"

@onready var title_label: Label = %TitleLabel
@onready var info_label: Label = %InfoLabel
@onready var difficulty_label: Label = %DifficultyLabel
@onready var back_button: Button = %BackButton

var level: LevelData
var difficulty: String = ""

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

	level = GameSession.current_level
	difficulty = GameSession.current_difficulty

	if level == null:
		# Happens when you run this scene directly with F6. Fall back to
		# the first level so the scene is still testable on its own.
		level = load("res://resources/levels/tutorial.tres") as LevelData
		if level != null:
			difficulty = level.get_default_difficulty()

	_start_level()

func _start_level() -> void:
	if level == null:
		title_label.text = "No level selected"
		info_label.text = ""
		difficulty_label.text = ""
		return

	title_label.text = level.title

	var bits: Array[String] = []
	if level.artist != "":
		bits.append(level.artist)
	bits.append("%d BPM" % roundi(level.bpm))
	info_label.text = "  -  ".join(bits)

	difficulty_label.text = "DIFFICULTY %s" % difficulty.to_upper()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_on_back_pressed()
