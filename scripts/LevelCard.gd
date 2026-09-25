class_name LevelCard
extends Button
## One entry in the level select list. Clicking the card plays the level
## at whichever difficulty chip is currently selected.
##
## Instantiate it, add it to the tree, then call setup() with a LevelData.

signal level_chosen(level: LevelData, difficulty: String)

const CHIP_SCENE := preload("res://scenes/DifficultyChip.tscn")

@onready var title_label: Label = %CardTitle
@onready var artist_label: Label = %CardArtist
@onready var bpm_label: Label = %CardBPM
@onready var chip_row: HBoxContainer = %DifficultyChips

var level: LevelData
var selected_difficulty: String = ""

var _chip_group: ButtonGroup

func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	pivot_offset = size / 2.0
	_refresh()

func setup(data: LevelData) -> void:
	level = data
	# setup() may be called before the node is in the tree, in which
	# case _ready() does the refresh instead.
	if is_node_ready():
		_refresh()

func _refresh() -> void:
	if level == null:
		return
	title_label.text = level.title
	artist_label.text = level.artist
	artist_label.visible = level.artist != ""
	bpm_label.text = "%d BPM" % roundi(level.bpm)
	disabled = not level.unlocked
	modulate.a = 1.0 if level.unlocked else 0.45

	selected_difficulty = level.get_default_difficulty()
	_build_chips()

func _build_chips() -> void:
	for child in chip_row.get_children():
		child.queue_free()

	# A fresh group per card, so selecting a difficulty here doesn't
	# clear the selection on other cards.
	_chip_group = ButtonGroup.new()

	for difficulty in level.get_difficulties():
		var chip: Button = CHIP_SCENE.instantiate()
		chip_row.add_child(chip)
		chip.text = difficulty
		chip.button_group = _chip_group
		chip.disabled = not level.unlocked
		chip.button_pressed = difficulty == selected_difficulty
		chip.pressed.connect(_on_chip_pressed.bind(difficulty))

func _on_chip_pressed(difficulty: String) -> void:
	selected_difficulty = difficulty

func _on_pressed() -> void:
	if level != null:
		level_chosen.emit(level, selected_difficulty)

func _on_hover() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.02, 1.02), 0.1)

func _on_unhover() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
