class_name ControlsMenu
extends Control
## Full-screen overlay for rebinding the keys in Settings.REBINDABLE_ACTIONS.
## Builds its own UI in code and inherits the theme of whatever it's
## added under, so it follows the menu's styling.
##
## Click an action's key button, then press the new key. Escape cancels.
## Bindings are applied and saved through the Settings autoload.

signal closed

## Style for the center panel. MainMenu passes the Options panel's style
## so both match; falls back to the theme's PanelContainer style.
var panel_style: StyleBox

var _key_buttons: Dictionary = {} # action -> Button
var _listening_action: StringName = &""
var _hint_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_refresh_keys()

func open() -> void:
	_cancel_listening()
	_refresh_keys()
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	var first: Button = _key_buttons.values()[0]
	first.grab_focus()

func close() -> void:
	_cancel_listening()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): visible = false)
	closed.emit()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.012, 0.043, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(528, 0)
	if panel_style != null:
		panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"HeaderLabel"
	vbox.add_child(title)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.theme_type_variation = &"SubtitleLabel"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint_label)

	for action in Settings.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		vbox.add_child(row)

		var name_label := Label.new()
		name_label.text = Settings.REBINDABLE_ACTIONS[action]
		name_label.custom_minimum_size = Vector2(160, 0)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.theme_type_variation = &"SettingLabel"
		row.add_child(name_label)

		var key_button := Button.new()
		key_button.custom_minimum_size = Vector2(192, 48)
		key_button.pressed.connect(_start_listening.bind(action))
		row.add_child(key_button)
		_key_buttons[action] = key_button

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)

	var reset_button := Button.new()
	reset_button.text = "RESET"
	reset_button.custom_minimum_size = Vector2(168, 48)
	reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset_button)

	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(168, 48)
	back_button.pressed.connect(close)
	buttons.add_child(back_button)

func _refresh_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = Settings.get_action_key_text(action)
	if _listening_action != &"":
		_key_buttons[_listening_action].text = "..."
		_hint_label.text = "Press a key for %s  (Esc to cancel)" % Settings.REBINDABLE_ACTIONS[_listening_action]
	else:
		_hint_label.text = "Click a key to change it"

func _start_listening(action: StringName) -> void:
	_listening_action = action
	_refresh_keys()

func _cancel_listening() -> void:
	_listening_action = &""
	if _hint_label != null:
		_refresh_keys()

func _on_reset_pressed() -> void:
	_cancel_listening()
	Settings.reset_controls()
	_refresh_keys()

# _input rather than _unhandled_input so the key being bound never
# reaches the focused button (e.g. Space/Enter re-pressing it).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _listening_action == &"":
		if event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			close()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var action := _listening_action
		_listening_action = &""
		if event.keycode != KEY_ESCAPE:
			Settings.rebind_action(action, event)
		_refresh_keys()
		_key_buttons[action].grab_focus()
