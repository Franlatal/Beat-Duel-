extends Node
## Autoload singleton. Register this as "Settings" under
## Project Settings > Autoload so it's reachable from any scene.
## Holds the current audio/display settings and key bindings, applies
## them to the engine, and persists them to user://settings.cfg between
## sessions.

const SETTINGS_PATH := "user://settings.cfg"

enum DisplayMode { WINDOWED, BORDERLESS, EXCLUSIVE }

## On-screen names for DisplayMode, in enum order.
const DISPLAY_MODE_NAMES: Array[String] = ["Windowed", "Borderless", "Fullscreen"]

## Window sizes offered in windowed mode. The game's picture scales to
## fit whichever one is picked (see _setup_scaling()).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## Input actions the player can rebind in Options > Controls, in the
## order they're listed, with their on-screen names.
const REBINDABLE_ACTIONS := {
	&"lane_0": "Lane 1",
	&"lane_1": "Lane 2",
	&"lane_2": "Lane 3",
	&"lane_3": "Lane 4",
	&"parry": "Parry",
}

## Default keys for rebindable actions that project.godot's Input Map
## doesn't define, so a new action works without editing the project.
const FALLBACK_KEYS := {
	&"parry": KEY_Z,
}

var master_volume: float = 1.0 # 0.0 - 1.0
var display_mode: int = DisplayMode.WINDOWED # a DisplayMode
var resolution: Vector2i = Vector2i(1280, 720)

## Keyboard events each rebindable action had in project.godot, captured
## before any saved bindings are applied. Used by reset_controls().
var _default_keys: Dictionary = {}

func _ready() -> void:
	_setup_scaling()
	_capture_default_keys()
	load_settings()
	apply_all()

func apply_all() -> void:
	apply_volume()
	apply_window_mode()

func apply_volume() -> void:
	var idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(master_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, master_volume <= 0.0001)

## Draws the game at its design size (the viewport size in
## project.godot) and scales it to fill the window, adding black bars
## when the window's shape doesn't match. canvas_items keeps the pixel
## font sharp at any size.
func _setup_scaling() -> void:
	var root := get_tree().root
	root.content_scale_size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

func is_fullscreen() -> bool:
	return display_mode != DisplayMode.WINDOWED

func apply_window_mode() -> void:
	match display_mode:
		DisplayMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		DisplayMode.EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Leaving fullscreen finishes on the next frame on some platforms,
		# and a size set before then gets overwritten.
		await get_tree().process_frame
	DisplayServer.window_set_size(_fitted_window_size())
	_center_window()

## The chosen resolution, scaled down (keeping its aspect ratio) if it
## wouldn't fit on the screen with the title bar and taskbar visible.
## A 1920x1080 window on a 1080p monitor would otherwise cover the whole
## screen and look like fullscreen.
func _fitted_window_size() -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var max_size := Vector2(usable.size) * 0.9
	var fit := minf(1.0, minf(max_size.x / resolution.x, max_size.y / resolution.y))
	return Vector2i((Vector2(resolution) * fit).floor())

## The RESOLUTIONS that fit on the current screen as a window, with
## room for the title bar and taskbar. Always has at least one entry.
func available_resolutions() -> Array[Vector2i]:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var room := Vector2(usable.size) * 0.95
	var fitting: Array[Vector2i] = []
	for res in RESOLUTIONS:
		if res.x <= room.x and res.y <= room.y:
			fitting.append(res)
	if fitting.is_empty():
		fitting.append(RESOLUTIONS[0])
	return fitting

func _center_window() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var win_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(usable.position + (usable.size - win_size) / 2)

func set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	apply_volume()
	save_settings()

func set_display_mode(mode: int) -> void:
	display_mode = mode
	apply_window_mode()
	save_settings()

func set_resolution(res: Vector2i) -> void:
	resolution = res
	if not is_fullscreen():
		apply_window_mode()
	save_settings()

# --- controls -------------------------------------------------------------

func _capture_default_keys() -> void:
	for action in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			if FALLBACK_KEYS.has(action):
				var ev := InputEventKey.new()
				ev.physical_keycode = FALLBACK_KEYS[action]
				InputMap.action_add_event(action, ev)
			else:
				push_warning("Settings: input action '%s' is missing from the Input Map." % action)
		_default_keys[action] = get_action_key(action)

## The keyboard event bound to an action, or null if it has none.
func get_action_key(action: StringName) -> InputEventKey:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev
	return null

## Display text for an action's key, e.g. "Left" or "D".
func get_action_key_text(action: StringName) -> String:
	var ev := get_action_key(action)
	if ev == null:
		return "---"
	return key_event_text(ev)

func key_event_text(ev: InputEventKey) -> String:
	return OS.get_keycode_string(_layout_keycode(ev))

## Binds a key to an action, replacing its old keyboard binding and
## leaving gamepad/mouse bindings alone. If another rebindable action
## already uses that key, the two actions swap keys.
func rebind_action(action: StringName, key: InputEventKey) -> void:
	var new_key := _copy_key(key)
	var old_key := get_action_key(action)
	for other in REBINDABLE_ACTIONS:
		if other != action and _same_key(get_action_key(other), new_key):
			_set_action_key(other, old_key)
	_set_action_key(action, new_key)
	save_settings()

func reset_controls() -> void:
	for action in REBINDABLE_ACTIONS:
		_set_action_key(action, _default_keys.get(action))
	save_settings()

func _set_action_key(action: StringName, key: InputEventKey) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	if key != null:
		InputMap.action_add_event(action, key)

func _copy_key(key: InputEventKey) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key.physical_keycode
	if ev.physical_keycode == KEY_NONE:
		ev.keycode = key.keycode
	return ev

func _same_key(a: InputEventKey, b: InputEventKey) -> bool:
	if a == null or b == null:
		return false
	return _layout_keycode(a) == _layout_keycode(b)

## The key's keycode on the current keyboard layout, whether the event
## was bound by physical key or by keycode.
func _layout_keycode(ev: InputEventKey) -> Key:
	if ev.physical_keycode != KEY_NONE:
		return DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
	return ev.keycode

# --- persistence ----------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("display", "mode", display_mode)
	cfg.set_value("display", "resolution_x", resolution.x)
	cfg.set_value("display", "resolution_y", resolution.y)
	for action in REBINDABLE_ACTIONS:
		var ev := get_action_key(action)
		# Saved as [physical_keycode, keycode]; [0, 0] means unbound.
		var codes := [0, 0] if ev == null else [ev.physical_keycode, ev.keycode]
		cfg.set_value("controls", action, codes)
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	# Older saves only had a fullscreen on/off flag.
	var was_fullscreen: bool = cfg.get_value("display", "fullscreen", false)
	var mode: int = cfg.get_value("display", "mode",
		DisplayMode.BORDERLESS if was_fullscreen else DisplayMode.WINDOWED)
	display_mode = clampi(mode, 0, DisplayMode.size() - 1)
	var rx: int = cfg.get_value("display", "resolution_x", resolution.x)
	var ry: int = cfg.get_value("display", "resolution_y", resolution.y)
	resolution = Vector2i(rx, ry)
	# A saved size that no longer fits (e.g. after switching to a smaller
	# monitor) falls back to the largest one that does.
	var fitting := available_resolutions()
	if not fitting.has(resolution):
		resolution = fitting[-1]
	for action in REBINDABLE_ACTIONS:
		if not cfg.has_section_key("controls", action):
			continue
		var codes: Array = cfg.get_value("controls", action, [0, 0])
		if codes.size() != 2 or (codes[0] == 0 and codes[1] == 0):
			_set_action_key(action, null)
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = codes[0]
		ev.keycode = codes[1]
		_set_action_key(action, ev)
