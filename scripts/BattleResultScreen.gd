class_name BattleResultScreen
extends Control
## The end-of-level screens, in the style of Deltarune's battle text: the
## battle dims, and a black text box with a white border types out a few
## "* " lines, then offers two options. The picked option (keyboard
## focus or mouse hover) turns yellow.
##
## - Win: "* You won!", the points, combo and accuracy. RETRY / LEVELS.
## - Any loss (out of HP, or Level 1's "YOU WERE SPARED"): the same
##   "* Game over." and the points. TRY AGAIN / LEVELS.
##
## LevelBase calls show_result() when the run ends. Put this node last
## under HUDRoot (full rect anchors) so it covers the rest of the HUD.
## Keyboard: arrows to pick, Enter/Space (ui_accept) to confirm and to
## skip the typing. The mouse works too.

## The level to send RETRY / LEVELS to. Empty = the nearest LevelBase.
@export var level: LevelBase
## Letters typed per second.
@export var type_speed: float = 40.0
## How dark the battle gets behind the text box.
@export_range(0.0, 1.0, 0.05) var dim: float = 0.45

@export_group("Text")
@export var win_line: String = "* You won!"
@export var game_over_line: String = "* Game over."

const BOX_WIDTH := 1440.0
const BOX_HEIGHT := 300.0

var _t: float = 0.0
var _typing: bool = false

var _dim: ColorRect
var _box: PanelContainer
var _text: Label
var _options: HBoxContainer

func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	if level == null:
		var node := get_parent()
		while node != null and not (node is LevelBase):
			node = node.get_parent()
		level = node as LevelBase
	_build()

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_dim)

	_box = PanelContainer.new()
	_box.theme_type_variation = &"BattleBox"
	_box.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_box.offset_left = -BOX_WIDTH / 2.0
	_box.offset_right = BOX_WIDTH / 2.0
	_box.offset_top = -BOX_HEIGHT - 120.0
	_box.offset_bottom = -120.0
	add_child(_box)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	_box.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)

	_text = Label.new()
	_text.theme_type_variation = &"BattleTextLabel"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = SIZE_EXPAND_FILL
	_text.add_theme_constant_override("line_spacing", 12)
	vbox.add_child(_text)

	_options = HBoxContainer.new()
	_options.alignment = BoxContainer.ALIGNMENT_CENTER
	_options.add_theme_constant_override("separation", 160)
	_options.modulate.a = 0.0
	vbox.add_child(_options)

## Shows the end screen. kind is "victory"; anything else ("game_over",
## "loss") is a loss and gets the one Game Over screen, whatever the
## title. stats has score, max_combo, accuracy (percent), hp, max_hp.
func show_result(kind: String, _title: String, stats: Dictionary) -> void:
	for child in _options.get_children():
		child.queue_free()
	var score: int = stats.get("score", 0)
	var lines: PackedStringArray = []
	if kind == "victory":
		lines.append(win_line)
		lines.append("* Got %d POINTS and a %dx COMBO." % [score, int(stats.get("max_combo", 0))])
		lines.append("* Accuracy: %d%%" % roundi(float(stats.get("accuracy", 0.0))))
		_add_option("RETRY", _retry)
	else:
		lines.append(game_over_line)
		lines.append("* Got %d POINTS." % score)
		_add_option("TRY AGAIN", _retry)
	_add_option("LEVELS", _levels)
	_text.text = "\n".join(lines)
	_text.visible_characters = 0
	_options.modulate.a = 0.0

	_dim.color = Color(0, 0, 0, 0)
	create_tween().tween_property(_dim, "color:a", dim, 0.4)
	visible = true
	_t = 0.0
	_typing = true
	set_process(true)

func _add_option(label: String, action: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.theme_type_variation = &"BattleOptionButton"
	btn.focus_mode = FOCUS_ALL
	btn.pressed.connect(action)
	# Hovering picks it too, so only one option is ever yellow.
	btn.mouse_entered.connect(btn.grab_focus)
	_options.add_child(btn)

func _process(delta: float) -> void:
	_t += delta
	var total := _text.get_total_character_count()
	_text.visible_characters = mini(int(_t * type_speed), total)
	if _text.visible_characters >= total:
		_show_menu()

func _show_menu() -> void:
	_typing = false
	set_process(false)
	_text.visible_characters = -1
	_options.modulate.a = 1.0
	if _options.get_child_count() > 0:
		(_options.get_child(0) as Control).grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if visible and _typing and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		_show_menu()
		get_viewport().set_input_as_handled()

func _retry() -> void:
	if level != null and level.has_method("_on_retry_pressed"):
		level.call("_on_retry_pressed")
	else:
		get_tree().reload_current_scene()

func _levels() -> void:
	if level != null and level.has_method("_on_back_pressed"):
		level.call("_on_back_pressed")
	else:
		get_tree().change_scene_to_file(LevelBase.LEVEL_SELECT_SCENE)
