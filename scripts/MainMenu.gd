extends Control

@onready var title_label: Label = $CenterContent/TitleLabel
@onready var play_button: Button = %PlayButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton

@onready var options_panel: Control = %OptionsPanel
@onready var back_button: Button = %BackButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var display_mode_option: OptionButton = %DisplayModeOption

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelect.tscn"

var controls_menu: ControlsMenu

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)

	volume_slider.value_changed.connect(_on_volume_changed)
	resolution_option.item_selected.connect(_on_resolution_selected)
	display_mode_option.item_selected.connect(_on_display_mode_selected)

	for b in [play_button, options_button, quit_button]:
		b.mouse_entered.connect(_on_button_hover.bind(b))
		b.mouse_exited.connect(_on_button_unhover.bind(b))

	_populate_display_options()
	_sync_options_ui()
	_setup_controls_menu()

	options_panel.modulate.a = 0.0
	options_panel.visible = false

	# Wait one frame so buttons/labels have their final layout size,
	# then set pivots to center so hover/pulse scaling looks right.
	await get_tree().process_frame
	title_label.pivot_offset = title_label.size / 2.0
	for b in [play_button, options_button, quit_button]:
		b.pivot_offset = b.size / 2.0
	_start_title_pulse()

func _start_title_pulse() -> void:
	var tw := create_tween()
	tw.set_loops()
	# Scaling a pixel font smears it, so pulse the brightness instead.
	tw.tween_property(title_label, "self_modulate", Color(1.25, 1.1, 1.3), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title_label, "self_modulate", Color(1, 1, 1), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _populate_display_options() -> void:
	display_mode_option.clear()
	for mode_name in Settings.DISPLAY_MODE_NAMES:
		display_mode_option.add_item(mode_name)
	resolution_option.clear()
	for res in Settings.available_resolutions():
		resolution_option.add_item("%d x %d" % [res.x, res.y])

func _sync_options_ui() -> void:
	volume_slider.value = Settings.master_volume * 100.0
	display_mode_option.selected = Settings.display_mode
	var idx := Settings.available_resolutions().find(Settings.resolution)
	resolution_option.selected = max(idx, 0)
	# Fullscreen modes always use the monitor's own size.
	resolution_option.disabled = Settings.is_fullscreen()

## Adds a CONTROLS button above BACK in the Options panel, and the
## ControlsMenu overlay it opens.
func _setup_controls_menu() -> void:
	var controls_button := Button.new()
	controls_button.name = "ControlsButton"
	controls_button.text = "CONTROLS"
	controls_button.custom_minimum_size = back_button.custom_minimum_size
	controls_button.size_flags_horizontal = back_button.size_flags_horizontal
	var options_box := back_button.get_parent()
	options_box.add_child(controls_button)
	options_box.move_child(controls_button, back_button.get_index())
	controls_button.pressed.connect(_on_controls_pressed)

	controls_menu = ControlsMenu.new()
	var options_frame := options_panel.get_node_or_null("Panel") as Control
	if options_frame != null:
		controls_menu.panel_style = options_frame.get_theme_stylebox("panel")
	controls_menu.visible = false
	add_child(controls_menu)
	controls_menu.closed.connect(func(): controls_button.grab_focus())

func _on_controls_pressed() -> void:
	controls_menu.open()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)

func _on_options_pressed() -> void:
	options_panel.visible = true
	var tw := create_tween()
	tw.tween_property(options_panel, "modulate:a", 1.0, 0.2)

func _on_back_pressed() -> void:
	var tw := create_tween()
	tw.tween_property(options_panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): options_panel.visible = false)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value / 100.0)

func _on_resolution_selected(index: int) -> void:
	Settings.set_resolution(Settings.available_resolutions()[index])

func _on_display_mode_selected(index: int) -> void:
	Settings.set_display_mode(index)
	resolution_option.disabled = Settings.is_fullscreen()

# The pixel theme's hover box does the highlighting; on top of that the
# button nudges a whole 6px to the right (scaling would blur pixel art).
func _on_button_hover(b: Button) -> void:
	b.position.x = roundf(b.position.x) + 6.0

func _on_button_unhover(b: Button) -> void:
	# Let the VBoxContainer put the button back in its slot.
	(b.get_parent() as Container).queue_sort()
