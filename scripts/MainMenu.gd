extends Control

@onready var title_label: Label = $CenterContent/TitleLabel
@onready var play_button: Button = %PlayButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton

@onready var options_panel: Control = %OptionsPanel
@onready var back_button: Button = %BackButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var fullscreen_check: CheckBox = %FullscreenCheck

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelectPlaceholder.tscn"

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)

	volume_slider.value_changed.connect(_on_volume_changed)
	resolution_option.item_selected.connect(_on_resolution_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	for b in [play_button, options_button, quit_button]:
		b.mouse_entered.connect(_on_button_hover.bind(b))
		b.mouse_exited.connect(_on_button_unhover.bind(b))

	_populate_resolutions()
	_sync_options_ui()

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
	tw.tween_property(title_label, "scale", Vector2(1.03, 1.03), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title_label, "scale", Vector2(1.0, 1.0), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _populate_resolutions() -> void:
	resolution_option.clear()
	for res in Settings.RESOLUTIONS:
		resolution_option.add_item("%d x %d" % [res.x, res.y])

func _sync_options_ui() -> void:
	volume_slider.value = Settings.master_volume * 100.0
	fullscreen_check.button_pressed = Settings.fullscreen
	var idx := Settings.RESOLUTIONS.find(Settings.resolution)
	resolution_option.selected = max(idx, 0)
	resolution_option.disabled = Settings.fullscreen

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
	Settings.set_resolution(Settings.RESOLUTIONS[index])

func _on_fullscreen_toggled(enabled: bool) -> void:
	Settings.set_fullscreen(enabled)
	resolution_option.disabled = enabled

func _on_button_hover(b: Button) -> void:
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.1)

func _on_button_unhover(b: Button) -> void:
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2(1.0, 1.0), 0.1)
