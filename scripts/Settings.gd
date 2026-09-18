extends Node
## Autoload singleton. Register this as "Settings" under
## Project Settings > Autoload so it's reachable from any scene.
## Holds the current audio/display settings, applies them to the
## engine, and persists them to user://settings.cfg between sessions.

const SETTINGS_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var master_volume: float = 1.0 # 0.0 - 1.0
var fullscreen: bool = false
var resolution: Vector2i = Vector2i(1920, 1080)

func _ready() -> void:
	load_settings()
	apply_all()

func apply_all() -> void:
	apply_volume()
	apply_window_mode()

func apply_volume() -> void:
	var idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(master_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, master_volume <= 0.0001)

func apply_window_mode() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)
		_center_window()

func _center_window() -> void:
	var screen_size := DisplayServer.screen_get_size()
	var win_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position((screen_size - win_size) / 2)

func set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	apply_volume()
	save_settings()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_window_mode()
	save_settings()

func set_resolution(res: Vector2i) -> void:
	resolution = res
	if not fullscreen:
		apply_window_mode()
	save_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "resolution_x", resolution.x)
	cfg.set_value("display", "resolution_y", resolution.y)
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	var rx: int = cfg.get_value("display", "resolution_x", resolution.x)
	var ry: int = cfg.get_value("display", "resolution_y", resolution.y)
	resolution = Vector2i(rx, ry)
